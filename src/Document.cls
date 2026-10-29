/// JSON Virtual Document message body.
/// Extends Ens.MessageBody and Ens.VDoc.Interface so that JSON messages can be
/// used in DTL mappings, routing rules, and search tables with a schema-driven
/// field tree, while the original JSON stream is kept byte-for-byte intact when
/// no path write occurs.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.Document Extends (Ens.MessageBody, Ens.VDoc.Interface)
{

/// Short type label displayed in the product's document class registry and Visual Trace.
Parameter DOCCLASSNAME = "JSON";

/// Full display name shown in the product UI alongside DOCCLASSNAME.
Parameter DOCCLASSFULLNAME = "JSON Virtual Document";

/// Class that the IRIS rule editor calls for field-completion lookups (ResolveSchemaTypeToDocType).
Parameter SCHEMACLASS = "JVDoc.DocSchema";

/// Maximum length of a single value written to the search table; truncated if exceeded (must not exceed PropValue.MAXLEN)
Parameter SEARCHVALUEMAXLEN = 200;

/// Longest value GetValuesArray stores as a pArray subscript; longer values are cut there and also returned in full in pLongArray.
/// Same as the product's $$$MAXEDIARRAYSUBSCRIPT used by the HL7 and XML virtual documents
Parameter VALUESUBSCRIPTMAXLEN = 230;

/// Fallback search table class when none is registered for the DocType (subclasses may override); empty means no indexing
Parameter SEARCHTABLE;

/// Fallback Identifier path when none is registered for the DocType (subclasses may override); empty means no Identifier
Parameter IDENTIFIERPATH;

/// Every validation switch except u (unknown fields): what "all" expands to, and the set used when testing whether a value matches a sub-schema.
/// See Validate for what each letter checks
Parameter ALLFLAGS = "rtepbcaso";

/// Original JSON stream; passed through byte-for-byte when unmodified
Property Raw As %Stream.GlobalCharacter;

/// Parsed representation of Raw; populated lazily on first path access, discarded on load.
Property Obj As %DynamicAbstractObject [ Transient ];

/// Set to 1 when SetValueAt has modified Obj but Raw has not yet been re-serialized.
Property Dirty As %Boolean [ InitialExpression = 0, Transient ];

/// Temporarily holds the source JSON type during a type-aware CopyValues call
Property TypedJT As %String [ Private, Transient ];

/// Set by %OnBeforeSave when the search table rows must be rebuilt after the save
Property NeedsIndex As %Boolean [ InitialExpression = 0, Private, Transient ];

/// Set by %OnAddToSaveSet when it wrote a modified Obj back to Raw, so that %OnBeforeSave still knows the content changed
Property ContentChanged As %Boolean [ InitialExpression = 0, Private, Transient ];

/// DocType the stored search table rows were built for; empty until the document has been indexed or opened
Property IndexedDocType As %String [ Private, Transient ];

/// Lets FromStoredDocs and other DocType filters avoid scanning the whole Ens.MessageBody extent
Index DocTypeIndex On DocType;

// ---------------- Content access ----------------

/// Creates a document from an initial value.<br>
/// <var>pInit</var>: a %DynamicObject or %DynamicArray (adopted as Obj and the document is marked dirty), a stream (copied into Raw), a JSON string (written to Raw), or "" for an empty document<br>
/// Returns: error when copying the stream fails
Method %OnNew(pInit = "") As %Status [ Private, ServerOnly = 1 ]
{
    Set tSC = $$$OK
    If $IsObject(pInit) {
        Set tCls = $ClassName(pInit)
        If (tCls = "%Library.DynamicObject") || (tCls = "%Library.DynamicArray") {
            Set ..Obj = pInit, ..Dirty = 1
        } Else {
            Set tSC = ..Raw.CopyFrom(pInit)
        }
    } ElseIf pInit '= "" {
        Do ..Raw.Write(pInit)
    }
    Quit tSC
}

/// Creates a document from JSON and sets its DocType in one call. The JSON is parsed here, so malformed input is reported at once
/// instead of on the first path access; the parsed object is cached without marking the document dirty, so Raw is still saved unchanged.<br>
/// <var>pJSON</var>: the JSON as a string, a character stream (copied, not consumed), or a %DynamicObject; the root must be a JSON object<br>
/// <var>pDocType</var>: the DocType "Cat:Name"; "" leaves it unset. It is not checked against JVDoc.SchemaDef<br>
/// <var>pStatus</var> (output): $$$OK, or the error when the document cannot be created, the JSON does not parse or its root is not an object<br>
/// Returns: the new unsaved document, or "" on error
ClassMethod Create(pJSON, pDocType As %String = "", Output pStatus As %Status) As JVDoc.Document
{
    Set pStatus = $$$OK
    Set tDoc = ..%New(pJSON)
    If '$IsObject(tDoc) {
        Set pStatus = $Get(%objlasterror, $$$ERROR($$$GeneralError, "Cannot create document"))
        Quit ""
    }
    Set tObj = tDoc.GetObj(.pStatus)
    If $$$ISERR(pStatus) Quit ""
    If $ClassName(tObj) '= "%Library.DynamicObject" {
        Set pStatus = $$$ERROR($$$GeneralError, "The root of a JVDoc document must be a JSON object")
        Quit ""
    }
    Set tDoc.DocType = pDocType
    Quit tDoc
}

/// Returns the parsed document, parsing Raw on first access; an empty Raw gives an empty object {}.<br>
/// A parse error leaves Obj unset, so the next call parses again.<br>
/// <var>pSC</var> (output): parse error, or $$$OK<br>
/// Returns: the %DynamicObject or %DynamicArray for the document; unset ("") when Raw does not parse
Method GetObj(Output pSC As %Status) As %DynamicAbstractObject
{
    Set pSC = $$$OK
    If '$IsObject(..Obj) {
        Try {
            If ..Raw.Size > 0 {
                Do ..Raw.Rewind()
                Set ..Obj = {}.%FromJSON(..Raw)
            } Else {
                Set ..Obj = {}
            }
        } Catch tEx {
            Set pSC = tEx.AsStatus()
        }
    }
    Quit ..Obj
}

/// Serializes a dynamic entity to a string by writing through a temporary character stream.<br>
/// <var>pObj</var>: the %DynamicAbstractObject to serialize<br>
/// Returns: the JSON text (at most $$$MaxLocalLength characters)
ClassMethod ToJSONString(pObj) As %String [ Private ]
{
    Set tS = ##class(%Stream.TmpCharacter).%New()
    Do pObj.%ToJSON(tS)
    Do tS.Rewind()
    Quit tS.Read($$$MaxLocalLength)
}

/// Deep-copies a dynamic entity by serializing it to JSON text and parsing the result.<br>
/// <var>pObj</var>: the %DynamicAbstractObject to copy<br>
/// Returns: an independent %DynamicObject or %DynamicArray with the same content
ClassMethod CloneDyn(pObj)
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(..ToJSONString(pObj))
}

// ---------------- Path parsing ----------------

/// Strips leading/trailing whitespace and optional outer curly braces from a path.<br>
/// <var>pPath</var>: path as written in DTL or rules, e.g. "{items(1).sku}"<br>
/// Returns: the bare path, e.g. "items(1).sku"
ClassMethod Clean(pPath As %String) As %String [ Private ]
{
    Set tP = $ZStrip(pPath, "<>W")
    If ($Extract(tP) = "{") && ($Extract(tP, *) = "}") Set tP = $Extract(tP, 2, *-1)
    Quit tP
}

/// Parses a VDoc path into segments.<br>
/// <var>pPath</var>: path such as "a.b(2).c"; outer {} and whitespace are allowed<br>
/// <var>pSegs</var> (output): pSegs(n)=$lb(name, hasParen, idx) for each segment n; name is "" for a segment like "(2)" on a root array, idx is "" for empty ()<br>
/// <var>pKey</var>: comma-separated indexes that fill the empty () in order (DTL foreach keys); "" leaves them empty<br>
/// Returns: "Malformed path" error when a parenthesis is not closed
ClassMethod ParsePath(pPath As %String, Output pSegs, pKey As %String = "") As %Status
{
    Kill pSegs
    Set tPath = ..Clean(pPath), tLen = $Length(tPath), tI = 1, tN = 0, tK = 0
    While tI <= tLen {
        Set tName = "", tIdx = "", tParen = 0
        While tI <= tLen {
            Set tC = $Extract(tPath, tI)
            If (tC = ".") || (tC = "(") Quit
            Set tName = tName_tC, tI = tI+1
        }
        If (tI <= tLen) && ($Extract(tPath, tI) = "(") {
            Set tClose = $Find(tPath, ")", tI)
            If 'tClose Quit
            Set tIdx = $Extract(tPath, tI+1, tClose-2), tParen = 1, tI = tClose
            If (tIdx = "") && (pKey '= "") { Set tK = tK+1, tIdx = $Piece(pKey, ",", tK) }
        }
        If (tI <= tLen) && ($Extract(tPath, tI) = ".") Set tI = tI+1
        Set tN = tN+1, pSegs(tN) = $ListBuild(tName, tParen, tIdx)
    }
    If tI <= tLen Quit $$$ERROR($$$GeneralError, "Malformed path: "_pPath)
    Quit $$$OK
}

/// Normalizes a path for field tree lookups by replacing every indexed or empty parenthesis with ().<br>
/// <var>pPath</var>: VDoc path, e.g. "items(2).qty"<br>
/// Returns: the normalized path, e.g. "items().qty"; "" for a malformed path
ClassMethod NormPath(pPath As %String) As %String
{
    If $$$ISERR(..ParsePath(pPath, .tSegs)) Quit ""
    Set tNorm = "", tN = $Order(tSegs(""), -1)
    For tI = 1:1:tN {
        Set tNorm = tNorm_$Select(tNorm = "":"", 1:".")_$List(tSegs(tI), 1)_$Select($List(tSegs(tI), 2):"()", 1:"")
    }
    Quit tNorm
}

/// Advances one path segment.<br>
/// <var>pCur</var>: the current node (%DynamicObject or %DynamicArray)<br>
/// <var>pSeg</var>: one segment from ParsePath, $lb(name, hasParen, idx); "name()" addresses the array itself, "name(k)" element k (1-based), an empty name pCur itself<br>
/// <var>pType</var> (output): JSON type of the value found, or "unassigned" when the segment does not resolve<br>
/// Returns: the value found; "" when it does not resolve
ClassMethod Step(pCur, pSeg As %List, Output pType As %String) [ Private ]
{
    Set pType = "unassigned"
    Set tName = $List(pSeg, 1), tParen = $List(pSeg, 2), tIdx = $List(pSeg, 3)
    Set tVal = pCur
    If tName '= "" {
        If '$IsObject(pCur) || ($ClassName(pCur) '= "%Library.DynamicObject") Quit ""
        Set tT = pCur.%GetTypeOf(tName)
        If tT = "unassigned" Quit ""
        Set tVal = pCur.%Get(tName), pType = tT
    } ElseIf $IsObject(pCur) && ($ClassName(pCur) = "%Library.DynamicArray") {
        Set pType = "array"
    }
    If 'tParen Quit tVal
    If pType '= "array" { Set pType = "unassigned" Quit "" }
    If tIdx = "" Quit tVal
    Set tI = +tIdx - 1
    If (tI < 0) || (tI >= tVal.%Size()) { Set pType = "unassigned" Quit "" }
    Set pType = tVal.%GetTypeOf(tI)
    Quit tVal.%Get(tI)
}

/// Walks the parsed document along a path.<br>
/// <var>pPath</var>: VDoc path; "" addresses the root<br>
/// <var>pType</var> (output): JSON type of the value found, or "unassigned" when the path does not resolve<br>
/// <var>pCount</var> (output): 1 when the path ends in a bare (), meaning the caller should report the element count of the returned array<br>
/// <var>pSC</var> (output): parse or path error; "Path not found: path (No segment found)" when a segment is missing or an intermediate value is not an object or array; the "No segment found" part is what lets DTL ignore it under IGNOREMISSINGSOURCE<br>
/// Returns: the value at the path (dynamic entity for objects and arrays); "" when not found
Method Locate(pPath As %String, Output pType As %String, Output pCount As %Boolean, Output pSC As %Status) [ Private ]
{
    Set pType = "unassigned", pCount = 0
    Set tCur = ..GetObj(.pSC)
    If $$$ISERR(pSC) Quit ""
    Set pSC = ..ParsePath(pPath, .tSegs)
    If $$$ISERR(pSC) Quit ""
    Set tN = $Order(tSegs(""), -1)
    If tN = 0 { Set pType = $Select($ClassName(tCur) = "%Library.DynamicArray":"array", 1:"object") Quit tCur }
    For tI = 1:1:tN {
        Set tVal = ..Step(tCur, tSegs(tI), .pType)
        If (pType = "unassigned") || ((tI < tN) && (pType '= "object") && (pType '= "array")) {
            // Generated DTL code honours IGNOREMISSINGSOURCE only for errors whose text contains "No segment found"
            Set pType = "unassigned", pSC = $$$ERROR($$$GeneralError, "Path not found: "_pPath_" (No segment found)")
            Quit
        }
        Set tCur = tVal
    }
    If pType = "unassigned" Quit ""
    Set pCount = ($List(tSegs(tN), 2) && ($List(tSegs(tN), 3) = ""))
    Quit tCur
}

// ---------------- VDoc interface: reading ----------------

/// Returns the value at a path as a string (Ens.VDoc.Interface).<br>
/// A missing path returns "" with an error in pStatus; DTL relies on this for IGNOREMISSINGSOURCE.<br>
/// <var>pPropertyPath</var>: VDoc path such as "items(1).sku"; a bare () ending such as "items()" asks for the element count<br>
/// <var>pFormat</var>: ignored<br>
/// <var>pStatus</var> (output): "Path not found" or parse error, or $$$OK<br>
/// <var>pTreatEmptyFieldAsNull</var>: ignored<br>
/// Returns: the scalar value; objects and arrays as JSON text; null as ""; the element count for a bare ()
Method GetValueAt(pPropertyPath As %String, pFormat As %String = "", Output pStatus As %Status, pTreatEmptyFieldAsNull As %Boolean = 0) As %String
{
    Set tVal = ..Locate(pPropertyPath, .tType, .tCount, .pStatus)
    If $$$ISERR(pStatus) Quit ""
    If tCount Quit tVal.%Size()
    If (tType = "object") || (tType = "array") Quit ..ToJSONString(tVal)
    If tType = "null" Quit ""
    Quit tVal
}

/// Returns the value at a path together with its real JSON type; used for type-aware copying between JVDoc documents.<br>
/// <var>pPath</var>: VDoc path; a bare () ending asks for the element count<br>
/// <var>pJType</var> (output): JSON type of the value (string, number, boolean, null, object, array), "number" for an element count, "unassigned" when not found<br>
/// <var>pSC</var> (output): "Path not found" or parse error, or $$$OK<br>
/// Returns: the scalar value, a deep copy for objects and arrays, "" for null, or the element count
Method GetTypedAt(pPath As %String, Output pJType As %String, Output pSC As %Status)
{
    Set tVal = ..Locate(pPath, .tType, .tCount, .pSC)
    Set pJType = tType
    If $$$ISERR(pSC) Quit ""
    If tCount { Set pJType = "number"  Quit tVal.%Size() }
    If (tType = "object") || (tType = "array") Quit ..CloneDyn(tVal)
    If tType = "null" Quit ""
    Quit tVal
}

/// Iterates the array at a path; drives the () expansion in CopyValues and search table indexing (Ens.VDoc.Interface).<br>
/// <var>pPath</var>: path of the array; a trailing () is ignored<br>
/// <var>pIndex</var>: the current 1-based index; "" to start<br>
/// <var>pStatus</var> (byref): set to the path error when the path does not resolve<br>
/// Returns: the next 1-based index, or "" at the end, when the path is missing or when it is not an array
Method GetNextIndex(pPath As %String, pIndex As %String = "", ByRef pStatus As %Status = {$$$OK}) As %String
{
    Set tP = ..Clean(pPath)
    If $Extract(tP, *-1, *) = "()" Set tP = $Extract(tP, 1, *-2)
    Set tArr = ..Locate(tP, .tType, .tCount, .pStatus)
    If $$$ISERR(pStatus) || (tType '= "array") Quit ""
    Set tNext = $Select(pIndex = "":1, 1:pIndex+1)
    Quit $Select(tNext <= tArr.%Size():tNext, 1:"")
}

/// Returns every value at a path, expanding each () to all array elements (Ens.VDoc.Interface); the Message Viewer calls it to
/// filter and display messages by a VDoc Property Path. Values are those of GetValueAt (objects and arrays as JSON text, booleans as 1/0);
/// null and "" give no value. A path that does not exist in this document gives no values rather than an error, so such messages simply do not match.<br>
/// <var>pPropertyPath</var>: VDoc path such as "order_id" or "items().sku"; outer {} and whitespace are allowed<br>
/// <var>pFormat</var>: ignored<br>
/// <var>pArray</var> (byref): cleared, then pArray(value)="" for each distinct value, cut to VALUESUBSCRIPTMAXLEN characters<br>
/// <var>pStatus</var> (output): $$$OK, or the error when the path is malformed or the document does not parse<br>
/// <var>pLongArray</var> (byref): cleared, then pLongArray(n) holds the full text of each value of VALUESUBSCRIPTMAXLEN characters or more, and pLongArray their count
Method GetValuesArray(pPropertyPath As %String, pFormat As %String = "", ByRef pArray As %String, Output pStatus As %Status, ByRef pLongArray As %String)
{
    Kill pArray, pLongArray
    Set tPath = ..Clean(pPropertyPath)
    Set pStatus = ..ParsePath(tPath, .tSegs)
    If $$$ISOK(pStatus) Do ..GetObj(.pStatus)
    If $$$ISERR(pStatus) Quit
    Do ..CollectAllValues(tPath, .pArray, .pLongArray)
}

/// Recursively walks a path for GetValuesArray, expanding the first () into all array elements and recursing on the rest.<br>
/// <var>pPath</var>: cleaned, well-formed path, possibly with ()<br>
/// <var>pArray</var> (byref): receives pArray(value)="", values cut to VALUESUBSCRIPTMAXLEN<br>
/// <var>pLongArray</var> (byref): receives the full text of values of VALUESUBSCRIPTMAXLEN characters or more
Method CollectAllValues(pPath As %String, ByRef pArray As %String, ByRef pLongArray As %String) [ Private ]
{
    Set tP = $Find(pPath, "()")
    If 'tP {
        Set tVal = ..GetValueAt(pPath, , .tSC)
        If $$$ISERR(tSC) || (tVal = "") Quit
        If $Length(tVal) >= ..#VALUESUBSCRIPTMAXLEN Set pLongArray($Increment(pLongArray)) = tVal
        Set pArray($Extract(tVal, 1, ..#VALUESUBSCRIPTMAXLEN)) = ""
        Quit
    }
    Set tHead = $Extract(pPath, 1, tP-3), tTail = $Extract(pPath, tP, *)
    Set tIdx = ""
    For {
        Set tIdx = ..GetNextIndex(tHead_"()", tIdx, .tNsc)
        If $$$ISERR(tNsc) || (tIdx = "") Quit
        Do ..CollectAllValues(tHead_"("_tIdx_")"_tTail, .pArray, .pLongArray)
    }
}

// ---------------- VDoc interface: writing ----------------

/// Writes a value at a path, creating intermediate objects and arrays as needed (Ens.VDoc.Interface).<br>
/// The value is coerced to the schema type and the indexes are checked before the document is touched, so a failed write leaves the document unchanged.<br>
/// <var>pValue</var>: the value as a string; converted by the type at the path in the field tree (number, boolean, null for an empty number, parsed JSON for object/array/any)<br>
/// <var>pPropertyPath</var>: VDoc path; "name()" as the last segment appends, "name(k)" sets element k and pads with nulls<br>
/// <var>pAction</var>: "set" (default), "append" (push onto the array at the path), "remove" or "clear" (delete the node; pValue ignored)<br>
/// <var>pKey</var>: comma-separated indexes for the empty () in the path (DTL foreach keys)<br>
/// Returns: error when the document is not mutable, the path is empty or malformed, an index is below 1, an existing node has another kind (PathConflict) or the value is not JSON for an object/array field
Method SetValueAt(pValue As %String, pPropertyPath As %String, pAction As %String = "set", pKey As %String = "") As %Status
{
    If '..IsMutable Quit $$$ERROR($$$GeneralError, "Document is not mutable")
    Set tCur = ..GetObj(.tSC)
    If $$$ISERR(tSC) Quit tSC
    Set tSC = ..ParsePath(pPropertyPath, .tSegs, pKey)
    If $$$ISERR(tSC) Quit tSC
    Set tN = $Order(tSegs(""), -1)
    If tN = 0 Quit $$$ERROR($$$GeneralError, "Empty path")
    Set tAction = $ZConvert(pAction, "L")
    If (tAction = "remove") || (tAction = "clear") {
        If ..RemoveAt(tCur, .tSegs, tN) Set ..Dirty = 1
        Quit $$$OK
    }
    Try {
        Set tNorm = ""
        For tI = 1:1:tN {
            Set tParen = $List(tSegs(tI), 2), tIdx = $List(tSegs(tI), 3)
            If tParen && ((tIdx '= "") || (tI < tN)) && (+tIdx < 1) Throw ##class(%Exception.General).%New("BadIndex", 5001, , "index must be >= 1: "_pPropertyPath)
            Set tNorm = tNorm_$Select(tNorm = "":"", 1:".")_$List(tSegs(tI), 1)_$Select(tParen:"()", 1:"")
        }
        Set tName = $List(tSegs(tN), 1), tParen = $List(tSegs(tN), 2), tIdx = $List(tSegs(tN), 3)
        If (tAction = "append") && 'tParen Set tParen = 1, tIdx = "", tNorm = tNorm_"()"
        Set tVt = ##class(JVDoc.Schema).TypeAt(..DocType, tNorm)
        If (tVt = "any") && (..TypedJT '= "") Set tVt = "@"_..TypedJT
        Set tVal = ..Coerce(pValue, tVt, .tJt)
        // From here on a PathConflict can only come from a node that already existed, so nothing has been created yet when it is thrown
        For tI = 1:1:tN-1 {
            If $List(tSegs(tI), 2) {
                Set tCur = ..EnsureElem(..ArrayAt(tCur, $List(tSegs(tI), 1)), +$List(tSegs(tI), 3))
            } Else {
                Set tCur = ..EnsureChild(tCur, $List(tSegs(tI), 1), "{}")
            }
        }
        If tParen {
            Set tArr = ..ArrayAt(tCur, tName)
            If tIdx = "" {
                Do ..Store(tArr, "", tVal, tJt, 1)                  // name() means append
            } Else {
                While tArr.%Size() < +tIdx { Do tArr.%Push("", "null") }
                Do ..Store(tArr, +tIdx-1, tVal, tJt)
            }
        } Else {
            Do ..Store(tCur, tName, tVal, tJt)
        }
        Set ..Dirty = 1
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Writes a value with a given JSON type: fields declared any (or not in the field tree) take pJType as-is; other fields are still coerced by their declared type.<br>
/// <var>pVal</var>: the value, as returned by GetTypedAt<br>
/// <var>pJType</var>: its JSON type (string, number, boolean, null, object, array)<br>
/// <var>pPath</var>: target VDoc path<br>
/// <var>pAction</var>: as in SetValueAt<br>
/// <var>pKey</var>: as in SetValueAt<br>
/// Returns: the status of SetValueAt
Method SetTypedAt(pVal, pJType As %String, pPath As %String, pAction As %String = "set", pKey As %String = "") As %Status
{
    Set ..TypedJT = pJType
    Try {
        Set tSC = ..SetValueAt(pVal, pPath, pAction, pKey)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Set ..TypedJT = ""
    Quit tSC
}

/// Removes the node at a parsed path without creating anything on the way; "name(k)" removes element k, "name" and "name()" remove the property itself.<br>
/// <var>pRoot</var>: the document root<br>
/// <var>pSegs</var> (byref): segments from ParsePath<br>
/// <var>pN</var>: number of segments<br>
/// Returns: 1 when a node was removed, 0 when the path did not exist
ClassMethod RemoveAt(pRoot, ByRef pSegs, pN As %Integer) As %Boolean [ Private ]
{
    Set tCur = pRoot, tT = $Select($ClassName(tCur) = "%Library.DynamicArray":"array", 1:"object")
    For tI = 1:1:pN-1 {
        Set tCur = ..Step(tCur, pSegs(tI), .tT)
        If (tT '= "object") && (tT '= "array") Quit
    }
    If (tT '= "object") && (tT '= "array") Quit 0
    Set tName = $List(pSegs(pN), 1), tParen = $List(pSegs(pN), 2), tIdx = $List(pSegs(pN), 3)
    If tParen && (tIdx '= "") {
        If tName = "" {
            Set tArr = tCur
        } Else {
            Set tArr = ..Step(tCur, $ListBuild(tName, 0, ""), .tT)
            If tT '= "array" Quit 0
        }
        If (+tIdx < 1) || (+tIdx > tArr.%Size()) Quit 0
        Do tArr.%Remove(+tIdx-1)
        Quit 1
    }
    If (tName = "") || (tT '= "object") || (tCur.%GetTypeOf(tName) = "unassigned") Quit 0
    Do tCur.%Remove(tName)
    Quit 1
}

/// Returns the array a "name()" or "name(k)" segment refers to, creating it when absent.<br>
/// <var>pCur</var>: the current node<br>
/// <var>pName</var>: segment name; "" (segment "(k)") refers to pCur itself, which must then be an array<br>
/// Returns: the %DynamicArray; throws PathConflict when the node is not an array
ClassMethod ArrayAt(pCur, pName As %String) [ Private ]
{
    If pName '= "" Quit ..EnsureChild(pCur, pName, "[]")
    If $ClassName(pCur) '= "%Library.DynamicArray" Throw ##class(%Exception.General).%New("PathConflict", 5001, , "() without a name needs an array, found an object")
    Quit pCur
}

/// Returns a child object or array, creating it when the key is absent or null.<br>
/// <var>pParent</var>: the %DynamicObject to look in<br>
/// <var>pName</var>: property name; "" returns pParent itself<br>
/// <var>pKind</var>: "{}" for an object, "[]" for an array<br>
/// Returns: the child; throws PathConflict when the key already holds a value of another kind
ClassMethod EnsureChild(pParent, pName As %String, pKind As %String) [ Private ]
{
    If pName = "" Quit pParent
    Set tT = pParent.%GetTypeOf(pName)
    If ((pKind = "{}") && (tT = "object")) || ((pKind = "[]") && (tT = "array")) Quit pParent.%Get(pName)
    If (tT '= "unassigned") && (tT '= "null") {
        Throw ##class(%Exception.General).%New("PathConflict", 5001, , pName_" exists with type "_tT)
    }
    If pKind = "{}" { Set tNew = {} } Else { Set tNew = [] }
    Do pParent.%Set(pName, tNew)
    Quit tNew
}

/// Returns the object at an array index, padding the array with nulls and replacing a null element with {} when needed.<br>
/// <var>pArr</var>: the %DynamicArray<br>
/// <var>pIdx</var>: 1-based index<br>
/// Returns: the element object; throws BadIndex for pIdx < 1 and PathConflict when the element holds a non-object value
ClassMethod EnsureElem(pArr, pIdx As %Integer) [ Private ]
{
    If pIdx < 1 Throw ##class(%Exception.General).%New("BadIndex", 5001, , "index must be >= 1")
    While pArr.%Size() < pIdx { Do pArr.%Push("", "null") }
    Set tT = pArr.%GetTypeOf(pIdx-1)
    If tT '= "object" {
        If tT '= "null" Throw ##class(%Exception.General).%New("PathConflict", 5001, , "element "_pIdx_" is "_tT)
        Do pArr.%Set(pIdx-1, {})
    }
    Quit pArr.%Get(pIdx-1)
}

/// Converts a value into what is stored for a field of a given schema type, before anything in the document is touched.<br>
/// <var>pValue</var>: the value to write, normally a string from DTL<br>
/// <var>pType</var>: schema type at the target path (string, integer, number, boolean, object, array, any); a "@" prefix such as "@number" means "store with this JSON type as-is" (type-aware copy)<br>
/// <var>pJType</var> (output): the JSON type to store the value as (string, number, boolean, null, object, array)<br>
/// Returns: the value to store (a parsed subtree for object/array, and for any when the text is JSON); throws BadJSON when an object/array field receives text that is not JSON
ClassMethod Coerce(pValue, pType As %String, Output pJType As %String) [ Private ]
{
    If $Extract(pType) = "@" {
        Set pJType = $Extract(pType, 2, *)
        If (pJType '= "object") && (pJType '= "array") && (pJType '= "null") && (pJType '= "number") && (pJType '= "boolean") Set pJType = "string"
        Quit pValue
    }
    If (pType = "object") || (pType = "array") || (pType = "any") {
        Set tV = ""
        If (pType '= "any") || ($Extract(pValue) = "{") || ($Extract(pValue) = "[") {
            Try { Set tV = ##class(%DynamicAbstractObject).%FromJSON(pValue) } Catch { Set tV = "" }
        }
        If $IsObject(tV) {
            Set pJType = $Select($ClassName(tV) = "%Library.DynamicArray":"array", 1:"object")
            Quit tV
        }
        If pType '= "any" Throw ##class(%Exception.General).%New("BadJSON", 5001, , "value is not valid JSON for an "_pType_" field")
    }
    Set pJType = $Case(pType, "integer":"number", "number":"number", "boolean":"boolean", :"string")
    If (pJType = "number") && (pValue = "") Set pJType = "null"
    If pJType = "boolean" Set pValue = $Select((pValue = 1) || ($ZConvert(pValue, "L") = "true"):1, 1:0)
    Quit pValue
}

/// Stores a value already converted by Coerce.<br>
/// <var>pTarget</var>: the %DynamicObject or %DynamicArray to write into<br>
/// <var>pKey</var>: property name, or 0-based array index; ignored when pPush=1<br>
/// <var>pValue</var>: the value from Coerce<br>
/// <var>pJType</var>: JSON type from Coerce<br>
/// <var>pPush</var>: 1 appends to the array instead of setting pKey
ClassMethod Store(pTarget, pKey, pValue, pJType As %String, pPush As %Boolean = 0) [ Private ]
{
    If (pJType = "object") || (pJType = "array") {
        If pPush { Do pTarget.%Push(pValue) } Else { Do pTarget.%Set(pKey, pValue) }
    } ElseIf pJType = "null" {
        If pPush { Do pTarget.%Push("", "null") } Else { Do pTarget.%Set(pKey, "", "null") }
    } Else {
        If pPush { Do pTarget.%Push(pValue, pJType) } Else { Do pTarget.%Set(pKey, pValue, pJType) }
    }
}

// ---------------- DTL support ----------------

/// Entry point of every DTL assignment (8-argument product signature): cleans both paths and delegates to CopyExpand.<br>
/// <var>pSource</var>: the source document (any Ens.VDoc.Interface; a JVDoc source enables type-aware copying)<br>
/// <var>pSourcePath</var>: source path; () is expanded element by element<br>
/// <var>pTargetPath</var>: target path; its first () receives the same index as the source<br>
/// <var>pAction</var>: as in SetValueAt<br>
/// <var>pKey</var>: as in SetValueAt<br>
/// <var>pTreatEmptyRepeatingFieldAsNull</var>: ignored<br>
/// <var>pIgnoreMissingSource</var>: 1 (default) skips a missing source path; 0 returns its error<br>
/// <var>pGenerateEmptySegments</var>: ignored<br>
/// Returns: the first error of a write (or of a missing source when pIgnoreMissingSource=0)
Method CopyValues(pSource As Ens.VDoc.Interface, pSourcePath As %String, pTargetPath As %String, pAction As %String = "set", pKey As %String = "", pTreatEmptyRepeatingFieldAsNull As %Boolean = 0, pIgnoreMissingSource As %Boolean = 1, pGenerateEmptySegments As %Boolean = 0) As %Status
{
    Quit ..CopyExpand(pSource, ..Clean(pSourcePath), ..Clean(pTargetPath), pAction, pKey, pIgnoreMissingSource)
}

/// Copies source to target, expanding the first () in the source path element by element and substituting the same index into the first () of the target path; recurses for further ().<br>
/// A JVDoc source copied into an any target keeps its real JSON types (GetTypedAt/SetTypedAt).<br>
/// <var>pSource</var>: the source document<br>
/// <var>pSrc</var>: cleaned source path<br>
/// <var>pTgt</var>: cleaned target path<br>
/// <var>pAction</var>: as in SetValueAt<br>
/// <var>pKey</var>: as in SetValueAt<br>
/// <var>pIgnoreMissing</var>: 1 skips a missing source path<br>
/// Returns: the first write error, or the missing-source error when pIgnoreMissing=0
Method CopyExpand(pSource As Ens.VDoc.Interface, pSrc As %String, pTgt As %String, pAction As %String, pKey As %String, pIgnoreMissing As %Boolean) As %Status [ Private ]
{
    Set tP = $Find(pSrc, "()")
    If 'tP {
        // When both source and target are JVDoc.Document and the target field is 'any', copy with the source value's real JSON type without going through a string
        If pSource.%Extends("JVDoc.Document") && (##class(JVDoc.Schema).TypeAt(..DocType, ..NormPath(pTgt)) = "any") {
            Set tVal = pSource.GetTypedAt(pSrc, .tJt, .tGsc)
            If $$$ISERR(tGsc) Quit $Select(pIgnoreMissing:$$$OK, 1:tGsc)
            Quit ..SetTypedAt(tVal, tJt, pTgt, pAction, pKey)
        }
        Set tVal = pSource.GetValueAt(pSrc, , .tGsc)
        If $$$ISERR(tGsc) Quit $Select(pIgnoreMissing:$$$OK, 1:tGsc)
        Quit ..SetValueAt(tVal, pTgt, pAction, pKey)
    }
    Set tHead = $Extract(pSrc, 1, tP-3), tTail = $Extract(pSrc, tP, *)
    Set tIdx = "", tSC = $$$OK
    For {
        Set tIdx = pSource.GetNextIndex(tHead_"()", tIdx, .tNsc)
        If $$$ISERR(tNsc) || (tIdx = "") Quit
        Set tTgt = pTgt, tQ = $Find(tTgt, "()")
        If tQ Set tTgt = $Extract(tTgt, 1, tQ-3)_"("_tIdx_")"_$Extract(tTgt, tQ, *)
        Set tSC = ..CopyExpand(pSource, tHead_"("_tIdx_")"_tTail, tTgt, pAction, pKey, pIgnoreMissing)
        If $$$ISERR(tSC) Quit
    }
    Quit tSC
}

/// Gives the clone its own parse state: Obj and Dirty are reset so it re-parses from its own Raw, and unsaved changes of the source are serialized into the clone's Raw first.<br>
/// <var>pObject</var>: the source document being cloned<br>
/// <var>pDeep</var>: deep-clone flag passed by %ConstructClone<br>
/// <var>pCloned</var> (byref): map of objects already cloned, maintained by %ConstructClone<br>
/// Returns: $$$OK
Method %OnConstructClone(pObject As %RegisteredObject, pDeep As %Boolean = 0, ByRef pCloned As %String) As %Status [ Private, ServerOnly = 1 ]
{
    Set ..Obj = "", ..Dirty = 0
    If pObject.Dirty && $IsObject(pObject.Obj) 
    {
        Do ..Raw.Clear()
        Do pObject.Obj.%ToJSON(..Raw)
    }
    Quit $$$OK
}

// ---------------- Metadata for the DTL and rule editors ----------------

/// Fills the content array the DTL and rule editors read (Ens.VDoc.Interface).<br>
/// <var>pContents</var> (output): pContents(n,"name") per field (arrays as name() with type "()"), composite nodes with pContents(n)=child count and children at pContents(n,m,...). When the editors pass a global reference name (^... or %...) in pContents, the result is written to that reference instead<br>
/// <var>pMode</var>: "source" or "target"; ignored<br>
/// <var>pDocType</var>: the DocType "Cat:Name"<br>
/// <var>pLevel</var>: ignored; the whole tree is returned<br>
/// <var>pIncludeBase</var>: ignored<br>
/// <var>pExtraDetails</var>: 1 adds "opt", "desc" and "vals" per node<br>
/// Returns: "Unknown DocType" error when the DocType does not exist
ClassMethod GetContentArray(Output pContents, pMode As %String = "source", pDocType As %String = "", pLevel As %Integer = "", pIncludeBase As %Boolean = 0, pExtraDetails = 0) As %Status
{
    // The editor passes pContents as a global reference name ("^IRIS.Temp..." or "%xxx"); results must be written to that reference
    Set tRef = $Get(pContents)
    Set tIsRef = (("%" = $Extract(tRef)) || ("^" = $Extract(tRef)))
    Set tSC = $$$OK
    Try {
        Set tTree = ##class(JVDoc.Schema).GetTree(pDocType)
        If '$IsObject(tTree) {
            Set tSC = $$$ERROR($$$GeneralError, "Unknown DocType: "_pDocType)
        } Else {
            Kill tTmp
            Do ..Fill(tTree.children, .tTmp, pExtraDetails)
            If tIsRef {
                Kill @tRef
                Merge @tRef = tTmp
            } Else {
                Kill pContents
                Merge pContents = tTmp
            }
        }
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Builds one level of the content array from a children list, recursing into object children.<br>
/// <var>pChildren</var>: children array of a field tree node<br>
/// <var>pArr</var> (byref): receives pArr(n,"name"), pArr(n,"type")="()" for arrays, opt/desc/vals when pExtra is set, and the sub-levels; pArr itself is set to the child count<br>
/// <var>pExtra</var>: 1 adds opt, desc and vals
ClassMethod Fill(pChildren As %DynamicArray, ByRef pArr, pExtra) [ Private ]
{
    Set tN = 0, tIt = pChildren.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        Set tN = tN+1
        Set tIsArr = (tC.type = "array")
        Set tEl = $Select(tIsArr:tC.items, 1:tC)
        Set pArr(tN, "name") = tC.name_$Select(tIsArr:"()", 1:"")
        // Consistent with product convention: scalars omit the type; array nodes use "()" as the type
        If tIsArr Set pArr(tN, "type") = "()"
        If pExtra {
            Set pArr(tN, "opt") = +tC.opt
            If tC.desc '= "" Set pArr(tN, "desc") = tC.desc
            If tC.vals '= "" Set pArr(tN, "vals") = tC.vals
        }
        If (tEl.type = "object") && $IsObject(tEl.children) {
            Kill tSub
            Do ..Fill(tEl.children, .tSub, pExtra)
            Merge pArr(tN) = tSub
        }
    }
    Set pArr = tN
}

/// Lists all DocType categories stored in JVDoc.SchemaDef; required by the DTL and rule editors to populate the category list.<br>
/// <var>pStandard</var>: "0" asks for standard categories only and returns nothing (all JVDoc categories are user-defined); otherwise a category filter: "" or "+" for all, a name, or "prefix%"<br>
/// Rows: Category, Description, IsStandard (always 0), Base (always "")
Query EnumerateTypeCategories(pStandard As %String = "") As %Query(ROWSPEC = "Category:%String,Description:%String,IsStandard:%Boolean,Base:%String")
{
}

/// Builds the rows of EnumerateTypeCategories from the distinct Category values in JVDoc.SchemaDef.<br>
/// <var>pHandle</var> (byref): receives $lb(position, rows) for the Fetch method<br>
/// <var>pStandard</var>: as in EnumerateTypeCategories<br>
/// Returns: SQL error when the query fails
ClassMethod EnumerateTypeCategoriesExecute(ByRef pHandle As %Binary, pStandard As %String = "") As %Status
{
    Set tRows = "", tStd = $Get(pStandard)
    // pStandard=0 means standard categories only; all JVDoc categories are user-defined, so nothing is returned
    If tStd '= "0" {
        Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT Category FROM JVDoc.SchemaDef ORDER BY Category")
        If tRs.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, tRs.%SQLCODE, tRs.%Message)
        While tRs.%Next() {
            Set tC = tRs.%Get("Category")
            If ..Match(tC, tStd) Set tRows = tRows_$ListBuild($ListBuild(tC, "JSON schema category", 0, ""))
        }
    }
    Set pHandle = $ListBuild(0, tRows)
    Quit $$$OK
}

/// Returns the next row of EnumerateTypeCategories.<br>
/// <var>pHandle</var> (byref): the cursor built by Execute<br>
/// <var>pRow</var> (byref): receives the row as a $list, or "" at the end<br>
/// <var>pAtEnd</var> (byref): set to 1 when all rows have been returned<br>
/// Returns: $$$OK
ClassMethod EnumerateTypeCategoriesFetch(ByRef pHandle As %Binary, ByRef pRow As %List, ByRef pAtEnd As %Integer = 0) As %Status
{
    Quit ..FetchRow(.pHandle, .pRow, .pAtEnd)
}

/// Clears the query handle after the EnumerateTypeCategories cursor is closed.<br>
/// <var>pHandle</var> (byref): the cursor to clear<br>
/// Returns: $$$OK
ClassMethod EnumerateTypeCategoriesClose(ByRef pHandle As %Binary) As %Status
{
    Set pHandle = ""
    Quit $$$OK
}

/// Lists all DocTypes in "Category:Name" form from JVDoc.SchemaDef; required by the DTL and rule editors to populate the DocType list.<br>
/// <var>pCategory</var>: category filter: "" or "+" for all, a name, or "prefix%"; "0" returns nothing<br>
/// <var>pIncludeBase</var>: ignored<br>
/// Rows: Type
Query EnumerateDocTypes(pCategory As %String = "", pIncludeBase As %Boolean = 0) As %Query(ROWSPEC = "Type:%String")
{
}

/// Builds the rows of EnumerateDocTypes from Category and Name in JVDoc.SchemaDef.<br>
/// <var>pHandle</var> (byref): receives $lb(position, rows) for the Fetch method<br>
/// <var>pCategory</var>: as in EnumerateDocTypes<br>
/// <var>pIncludeBase</var>: ignored<br>
/// Returns: SQL error when the query fails
ClassMethod EnumerateDocTypesExecute(ByRef pHandle As %Binary, pCategory As %String = "", pIncludeBase As %Boolean = 0) As %Status
{
    Set tRows = "", tCat = $Get(pCategory)
    If tCat '= "0" {
        Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Category, Name FROM JVDoc.SchemaDef ORDER BY Category, Name")
        If tRs.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, tRs.%SQLCODE, tRs.%Message)
        While tRs.%Next() {
            Set tC = tRs.%Get("Category")
            If ..Match(tC, tCat) Set tRows = tRows_$ListBuild($ListBuild(tC_":"_tRs.%Get("Name")))
        }
    }
    Set pHandle = $ListBuild(0, tRows)
    Quit $$$OK
}

/// Returns the next row of EnumerateDocTypes.<br>
/// <var>pHandle</var> (byref): the cursor built by Execute<br>
/// <var>pRow</var> (byref): receives the row as a $list, or "" at the end<br>
/// <var>pAtEnd</var> (byref): set to 1 when all rows have been returned<br>
/// Returns: $$$OK
ClassMethod EnumerateDocTypesFetch(ByRef pHandle As %Binary, ByRef pRow As %List, ByRef pAtEnd As %Integer = 0) As %Status
{
    Quit ..FetchRow(.pHandle, .pRow, .pAtEnd)
}

/// Clears the query handle after the EnumerateDocTypes cursor is closed.<br>
/// <var>pHandle</var> (byref): the cursor to clear<br>
/// Returns: $$$OK
ClassMethod EnumerateDocTypesClose(ByRef pHandle As %Binary) As %Status
{
    Set pHandle = ""
    Quit $$$OK
}

/// Matches a category against an editor filter.<br>
/// <var>pCategory</var>: the category name<br>
/// <var>pFilter</var>: "" or "+" for all, an exact name, or "prefix%" for a prefix match<br>
/// Returns: 1 when the category passes the filter
ClassMethod Match(pCategory As %String, pFilter As %String) As %Boolean [ Private ]
{
    If (pFilter = "") || (pFilter = "+") Quit 1
    If $Extract(pFilter, *) = "%" Quit ($Extract(pCategory, 1, $Length(pFilter)-1) = $Extract(pFilter, 1, *-1))
    Quit (pCategory = pFilter)
}

/// Advances the in-memory query cursor by one row; shared by both Fetch methods.<br>
/// <var>pHandle</var> (byref): $lb(position, rows); cleared at the end<br>
/// <var>pRow</var> (byref): receives the current row, or "" at the end<br>
/// <var>pAtEnd</var> (byref): set to 1 when all rows have been returned<br>
/// Returns: $$$OK
ClassMethod FetchRow(ByRef pHandle As %Binary, ByRef pRow As %List, ByRef pAtEnd As %Integer) As %Status [ Private ]
{
    Set tPos = $ListGet(pHandle, 1) + 1, tRows = $ListGet(pHandle, 2)
    If tPos > $ListLength(tRows) {
        Set pRow = "", pAtEnd = 1, pHandle = ""
        Quit $$$OK
    }
    Set pRow = $List(tRows, tPos), pHandle = $ListBuild(tPos, tRows)
    Quit $$$OK
}

// ---------------- Derived properties ----------------

/// Getter of DocTypeCategory.<br>
/// Returns: the text of DocType before the first colon
Method DocTypeCategoryGet() As %String [ ServerOnly = 1 ]
{
    Quit $Piece(i%DocType, ":", 1)
}

/// Getter of DocTypeName.<br>
/// Returns: the text of DocType after the first colon
Method DocTypeNameGet() As %String [ ServerOnly = 1 ]
{
    Quit $Piece(i%DocType, ":", 2, *)
}

/// Getter of Name, required by Ens.VDoc.Interface; same as DocTypeName.<br>
/// Returns: the text of DocType after the first colon
Method NameGet() As %String [ ServerOnly = 1 ]
{
    Quit $Piece(i%DocType, ":", 2, *)
}

/// Getter of Identifier: reads the path registered for the DocType (JVDoc.Schema.GetIdentifierPath), falling back to IDENTIFIERPATH. Parses the JSON on every read.<br>
/// Returns: the value at that path; "" when no path is set or the path is missing
Method IdentifierGet() As %String [ ServerOnly = 1 ]
{
    Set tPath = ##class(JVDoc.Schema).GetIdentifierPath(i%DocType)
    If tPath = "" Set tPath = ..#IDENTIFIERPATH
    If tPath = "" Quit ""
    Quit ..GetValueAt(tPath)
}

// ---------------- Validation ----------------

/// Validates this document against the field tree of its DocType and returns a combined error status
/// listing up to 50 violations, each prefixed with the path of the offending value.
/// <p>pValidationSpec is a string of single-letter switches; each letter turns on one group of checks:</p>
/// <ul>
/// <li><b>r</b> required: a required field is missing (also dependentRequired, and required inside then/else and dependentSchemas)</li>
/// <li><b>t</b> type: the JSON type differs from the declared type (integer also requires a whole number); fields of type any are not checked</li>
/// <li><b>e</b> enum: the value is not one of the listed values (comparison is JSON-type-aware)</li>
/// <li><b>p</b> pattern: a string does not match the regular expression (unanchored, IRIS regex engine)</li>
/// <li><b>b</b> bounds: minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf (numbers);
///     minLength, maxLength (strings); minItems, maxItems, uniqueItems (arrays); minProperties, maxProperties (objects)</li>
/// <li><b>c</b> const: the value does not equal the constant (object key order ignored, numbers by value)</li>
/// <li><b>a</b> additionalProperties: with false, fields outside the schema are errors; with a schema, their values are checked against it</li>
/// <li><b>s</b> sub-schemas: not, contains with minContains/maxContains, and propertyNames</li>
/// <li><b>o</b> alternatives: oneOf must match exactly one alternative, anyOf at least one</li>
/// <li><b>u</b> unknown: any field that is not in the field tree is an error; not part of "all", because pass-through is the premise</li>
/// </ul>
/// <p>"all" expands to ALLFLAGS (rtepbcaso). A letter preceded by "-" is turned off, e.g. "all-p" ("-all" is not supported).
/// Letters that are not switches (such as d and m, which the routing engine handles itself) are ignored.
/// An empty spec only checks that the JSON parses. if/then/else and dependentSchemas have no switch of their own:
/// if is always evaluated with ALLFLAGS, and the chosen branch is checked with the switches you turned on.
/// A JSON null value counts as present for r and skips every other check.</p>
/// <p><var>pValidationSpec</var>: the switch letters described above, e.g. "all", "all-p", "rt"; default "" only checks that the JSON parses<br>
/// Returns: $$$OK when valid; otherwise a status combining one error per violation (at most 50), each "path: message", or an error when the JSON does not parse, the DocType is empty or unknown, or the root is not an object</p>
Method Validate(pValidationSpec As %String = "") As %Status
{
    Set tObj = ..GetObj(.tSC)
    If $$$ISERR(tSC) Quit $$$ERROR($$$GeneralError, "Invalid JSON: "_$System.Status.GetErrorText(tSC))
    Set tFlags = ..ParseSpec(pValidationSpec)
    If tFlags = "" Quit $$$OK
    If ..DocType = "" Quit $$$ERROR($$$GeneralError, "Cannot validate: DocType is empty")
    Set tTree = ##class(JVDoc.Schema).GetTree(..DocType)
    If '$IsObject(tTree) Quit $$$ERROR($$$GeneralError, "Cannot validate: unknown DocType "_..DocType)
    If $ClassName(tObj) '= "%Library.DynamicObject" Quit $$$ERROR($$$GeneralError, "Root must be a JSON object")
    Set tN = 0
    Do ..CheckObject(tTree, tObj, "", tFlags, .tErrs, .tN)
    Do ..CheckComposition(tTree, tObj, "object", "", tFlags, .tErrs, .tN)
    If tN = 0 Quit $$$OK
    Set tSC = $$$OK
    For tI = 1:1:tN {
        Set tSt = $$$ERROR($$$GeneralError, tErrs(tI))
        Set tSC = $Select(+tSC:tSt, 1:$System.Status.AppendStatus(tSC, tSt))
    }
    Quit tSC
}

/// Validates JSON without saving anything.<br>
/// Example: Set sc = ##class(JVDoc.Document).ValidateJSON("{""order_id"":""A1"",""total"":""x""}", "Demo:Order", "all", .errs)<br>
///          Write $System.Status.IsOK(sc), !<br>
///          For i = 1:1:errs Write errs(i), !<br>
/// <var>pJSON</var>: a JSON string, stream, or %DynamicObject<br>
/// <var>pDocType</var>: the DocType "Cat:Name" to validate against<br>
/// <var>pValidationSpec</var>: validation switches as in Validate; default "all"<br>
/// <var>pErrors</var> (output): number of errors; pErrors(i) is the text of the i-th error<br>
/// Returns: the status of Validate
ClassMethod ValidateJSON(pJSON, pDocType As %String, pValidationSpec As %String = "all", Output pErrors) As %Status
{
    Kill pErrors
    Set pErrors = 0
    Set tD = ##class(JVDoc.Document).%New(pJSON)
    Set tD.DocType = pDocType
    Set tSC = tD.Validate(pValidationSpec)
    If $$$ISERR(tSC) {
        Do $System.Status.DecomposeStatus(tSC, .tErrs)
        Set pErrors = +$Get(tErrs)
        For tI = 1:1:pErrors Set pErrors(tI) = tErrs(tI)
    }
    Quit tSC
}

/// Normalizes a validation spec: "all" expands to ALLFLAGS, "-x" removes x, duplicates and letters other than ALLFLAGS and u are dropped (so the product's d and m are ignored).<br>
/// <var>pValidationSpec</var>: the spec, e.g. "all-p" or "rt"; case-insensitive<br>
/// Returns: the active switch letters, e.g. "rtebcaso"; "" when none
ClassMethod ParseSpec(pValidationSpec As %String) As %String [ Private ]
{
    Set tS = $ZConvert($ZStrip(pValidationSpec, "<>W"), "L"), tPos = "", tNeg = "", tValid = ..#ALLFLAGS_"u"
    If tS [ "all" Set tS = $Replace(tS, "all", ..#ALLFLAGS)
    Set tI = 1
    While tI <= $Length(tS) {
        Set tC = $Extract(tS, tI)
        If tC = "-" {
            Set tI = tI + 1, tC = $Extract(tS, tI)
            If (tC '= "") && (tValid [ tC) Set tNeg = tNeg_tC
        } ElseIf (tC '= "") && (tValid [ tC) && (tPos '[ tC) {
            Set tPos = tPos_tC
        }
        Set tI = tI + 1
    }
    Set tOut = ""
    For tJ = 1:1:$Length(tPos) { If tNeg '[ $Extract(tPos, tJ) Set tOut = tOut_$Extract(tPos, tJ) }
    Quit tOut
}

/// Appends "path: message" to the error list, skipping texts already present (allOf members and the merged field tree can report the same violation); stops at 50 entries and adds a single "(more errors omitted)" line.<br>
/// <var>pErrs</var> (byref): error list, pErrs(i)=text<br>
/// <var>pN</var> (byref): number of entries in pErrs<br>
/// <var>pPath</var>: path of the offending value; "" is shown as (root)<br>
/// <var>pMsg</var>: error text
ClassMethod AddErr(ByRef pErrs, ByRef pN, pPath As %String, pMsg As %String) [ Private ]
{
    Set tTxt = $Select(pPath = "":"(root)", 1:pPath)_": "_pMsg
    For tI = 1:1:pN { If $Get(pErrs(tI)) = tTxt Quit }
    If (pN > 0) && ($Get(pErrs(tI)) = tTxt) Quit
    If pN >= 50 {
        If pN = 50 Set pN = 51, pErrs(51) = "(more errors omitted)"
        Quit
    }
    Set pN = pN + 1
    Set pErrs(pN) = tTxt
}

/// Validates an object against an object node: each declared child (required when missing, otherwise CheckArray/CheckValue; null values and fields declared only in oneOf/anyOf alternatives are skipped),
/// then minProperties/maxProperties, dependentRequired, dependentSchemas, propertyNames, unknown fields (u), additionalProperties and if/then/else.<br>
/// <var>pNode</var>: object node of the field tree<br>
/// <var>pData</var>: the %DynamicObject to check<br>
/// <var>pPath</var>: path of pData, prefixed to error texts; "" for the root<br>
/// <var>pFlags</var>: active switch letters from ParseSpec<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckObject(pNode As %DynamicObject, pData, pPath As %String, pFlags As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Kill tKnown
    Set tIt = pNode.children.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        Set tName = tC.name, tKnown(tName) = ""
        Set tPath = pPath_$Select(pPath = "":"", 1:".")_tName
        Set tT = pData.%GetTypeOf(tName)
        If tT = "unassigned" {
            If (pFlags [ "r") && ('+tC.opt) Do ..AddErr(.pErrs, .pN, tPath, "required field is missing")
            Continue
        }
        // Fields declared only inside oneOf/anyOf alternatives are checked by the alternative itself
        If (tT = "null") || tC.%Get("fromAlt") Continue
        Set tVal = pData.%Get(tName)
        If tC.type = "array" {
            Do ..CheckArray(tC, tVal, tT, tPath, pFlags, .pErrs, .pN)
        } Else {
            Do ..CheckValue(tC, tVal, tT, tPath, pFlags, .pErrs, .pN)
        }
    }
    // minProperties / maxProperties: count all properties on the object
    If pFlags [ "b" {
        Set tCnt = 0, tItc = pData.%GetIterator()
        While tItc.%GetNext() { Set tCnt = tCnt + 1 }
        If (pNode.%GetTypeOf("minProperties") = "number") && (tCnt < pNode.%Get("minProperties")) Do ..AddErr(.pErrs, .pN, pPath, "property count "_tCnt_" is less than minProperties "_pNode.%Get("minProperties"))
        If (pNode.%GetTypeOf("maxProperties") = "number") && (tCnt > pNode.%Get("maxProperties")) Do ..AddErr(.pErrs, .pN, pPath, "property count "_tCnt_" is more than maxProperties "_pNode.%Get("maxProperties"))
    }
    // dependentRequired: when the key is present (even null), the dependent fields must also be present
    If (pFlags [ "r") && $IsObject(pNode.%Get("dep")) {
        Set tItd = pNode.dep.%GetIterator()
        While tItd.%GetNext(.tDk, .tDnames) {
            If pData.%GetTypeOf(tDk) = "unassigned" Continue
            Set tItn = tDnames.%GetIterator()
            While tItn.%GetNext(.tJ, .tDn) {
                If pData.%GetTypeOf(tDn) = "unassigned" Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_tDn, "required when '"_tDk_"' is present")
            }
        }
    }
    // dependentSchemas: when the key is present (even null), the object must also satisfy the corresponding sub-schema (unknown fields not checked)
    If $IsObject(pNode.%Get("dsch")) {
        Set tDflags = $Translate(pFlags, "u")
        Set tItx = pNode.dsch.%GetIterator()
        While tItx.%GetNext(.tXk, .tXe) {
            If pData.%GetTypeOf(tXe.key) = "unassigned" Continue
            Do ..CheckObject(tXe.node, pData, pPath, tDflags, .pErrs, .pN)
        }
    }
    // propertyNames: every property name (including those outside the schema) is validated as a string against the sub-schema
    If (pFlags [ "s") && $IsObject(pNode.%Get("pnames")) {
        Set tItp = pData.%GetIterator()
        While tItp.%GetNext(.tPk) {
            Kill tE3
            Set tN3 = 0
            Do ..CheckValue(pNode.pnames, tPk, "string", "", pFlags, .tE3, .tN3)
            For tI = 1:1:tN3 {
                Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_tPk, "property name is invalid: "_$Piece(tE3(tI), ": ", 2, *))
            }
        }
    }
    If pFlags [ "u" {
        Set tIt2 = pData.%GetIterator()
        While tIt2.%GetNext(.tK2, .tV2) {
            If '$Data(tKnown(tK2)) Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_tK2, "unknown field")
        }
    }
    // additionalProperties: false rejects unknown fields (when u is also on, only u reports them); a schema validates each additional field's value against it
    Set tAt = pNode.%GetTypeOf("additional"), tDoAdd = 0
    If pFlags [ "a" {
        If tAt = "object" {
            Set tDoAdd = 1
        } ElseIf (tAt = "boolean") && ('pNode.%Get("additional")) && (pFlags '[ "u") {
            Set tDoAdd = 1
        }
    }
    If tDoAdd {
        Set tIt3 = pData.%GetIterator()
        While tIt3.%GetNext(.tK3, .tV3, .t3) {
            If $Data(tKnown(tK3)) Continue
            Set tApath = pPath_$Select(pPath = "":"", 1:".")_tK3
            If tAt = "boolean" {
                Do ..AddErr(.pErrs, .pN, tApath, "additional property is not allowed")
            } ElseIf t3 '= "null" {
                If pNode.additional.type = "array" {
                    Do ..CheckArray(pNode.additional, tV3, t3, tApath, pFlags, .pErrs, .pN)
                } Else {
                    Do ..CheckValue(pNode.additional, tV3, t3, tApath, pFlags, .pErrs, .pN)
                }
            }
        }
    }
    // if/then/else: if is evaluated with full checks to decide which branch to take; then or else is checked with the user-supplied flags (unknown fields are not checked inside branches)
    If $IsObject(pNode.%Get("cond")) {
        Set tBflags = $Translate(pFlags, "u")
        Set tCi = pNode.cond.%GetIterator()
        While tCi.%GetNext(.tCk, .tCe) {
            Kill tE2
            Set tN2 = 0
            Do ..CheckObject(tCe.%Get("if"), pData, pPath, ..#ALLFLAGS, .tE2, .tN2)
            Set tBn = tCe.%Get($Select(tN2 = 0:"then", 1:"else"))
            If $IsObject(tBn) Do ..CheckObject(tBn, pData, pPath, tBflags, .pErrs, .pN)
        }
    }
}

/// Validates an array against an array node: type, minItems/maxItems/uniqueItems, const, composition (not, oneOf/anyOf, allOf), enum, contains,
/// then every non-null element against the items node.<br>
/// <var>pArr</var>: array node of the field tree<br>
/// <var>pVal</var>: the value to check<br>
/// <var>pType</var>: JSON type of pVal; anything other than array is a type error (with t) and stops the checks<br>
/// <var>pPath</var>: path of the value, prefixed to error texts<br>
/// <var>pFlags</var>: active switch letters<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckArray(pArr As %DynamicObject, pVal, pType As %String, pPath As %String, pFlags As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If pType '= "array" {
        If pFlags [ "t" Do ..AddErr(.pErrs, .pN, pPath, "expected array, got "_pType)
        Quit
    }
    Set tN = pVal.%Size()
    If pFlags [ "b" {
        If (pArr.%GetTypeOf("minItems") = "number") && (tN < pArr.%Get("minItems")) Do ..AddErr(.pErrs, .pN, pPath, "array has "_tN_" item(s), fewer than minItems "_pArr.%Get("minItems"))
        If (pArr.%GetTypeOf("maxItems") = "number") && (tN > pArr.%Get("maxItems")) Do ..AddErr(.pErrs, .pN, pPath, "array has "_tN_" item(s), more than maxItems "_pArr.%Get("maxItems"))
        If (pArr.%GetTypeOf("uniqueItems") = "boolean") && pArr.%Get("uniqueItems") Do ..CheckUnique(pVal, tN, pPath, .pErrs, .pN)
    }
    If pFlags [ "c" Do ..CheckConst(pArr, pVal, pType, pPath, .pErrs, .pN)
    Do ..CheckComposition(pArr, pVal, pType, pPath, pFlags, .pErrs, .pN)
    If (pFlags [ "e") && $IsObject(pArr.%Get("enum")) Do ..CheckEnum(pArr, pVal, pType, pPath, .pErrs, .pN)
    If pFlags [ "s" Do ..CheckContains(pArr, pVal, tN, pPath, .pErrs, .pN)
    Set tItems = pArr.items
    For tI = 0:1:tN-1 {
        Set tEt = pVal.%GetTypeOf(tI)
        If tEt = "null" Continue
        Do ..CheckValue(tItems, pVal.%Get(tI), tEt, pPath_"("_(tI+1)_")", pFlags, .pErrs, .pN)
    }
}

/// Validates one value against a node: array nodes are delegated to CheckArray; otherwise type, const, composition, enum, then CheckObject for object nodes,
/// or pattern and bounds for scalars. A type mismatch stops further checks on that value.<br>
/// <var>pNode</var>: field tree node<br>
/// <var>pVal</var>: the value to check<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value, prefixed to error texts<br>
/// <var>pFlags</var>: active switch letters<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckValue(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, pFlags As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Set tSt = pNode.type
    // Array nodes (the items of a nested array) get the full array treatment, including their own elements
    If tSt = "array" Do ..CheckArray(pNode, pVal, pType, pPath, pFlags, .pErrs, .pN) Quit
    If pFlags [ "t" {
        Set tOk = $Case(tSt, "string":(pType = "string"), "number":(pType = "number"), "integer":((pType = "number") && (pVal = (pVal\1))), "boolean":(pType = "boolean"), "object":(pType = "object"), :1)
        If 'tOk {
            Do ..AddErr(.pErrs, .pN, pPath, "expected "_tSt_", got "_pType)
            Quit
        }
    }
    If pFlags [ "c" Do ..CheckConst(pNode, pVal, pType, pPath, .pErrs, .pN)
    Do ..CheckComposition(pNode, pVal, pType, pPath, pFlags, .pErrs, .pN)
    If (pFlags [ "e") && $IsObject(pNode.%Get("enum")) Do ..CheckEnum(pNode, pVal, pType, pPath, .pErrs, .pN)
    If tSt = "object" {
        If (pType = "object") && $IsObject(pNode.%Get("children")) Do ..CheckObject(pNode, pVal, pPath, pFlags, .pErrs, .pN)
        Quit
    }
    If (pFlags [ "p") && ((tSt = "string") || (tSt = "any")) && (pType = "string") && (pNode.%Get("pattern") '= "") {
        Try {
            If '$Locate(pVal, pNode.pattern) Do ..AddErr(.pErrs, .pN, pPath, "value does not match pattern "_pNode.pattern)
        } Catch tEx {
            Do ..AddErr(.pErrs, .pN, pPath, "invalid pattern in schema: "_pNode.pattern)
        }
    }
    If pFlags [ "b" Do ..CheckBounds(pNode, pVal, pType, pPath, .pErrs, .pN)
}

/// Tests a value against a sub-schema with all checks except u.<br>
/// <var>pNode</var>: the sub-schema node<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// Returns: 1 when there is no error
ClassMethod Matches(pNode As %DynamicObject, pVal, pType As %String, pPath As %String) As %Boolean [ Private ]
{
    Quit ..MatchErr(pNode, pVal, pType, pPath, .tFirst)
}

/// Tests a value against a sub-schema with all checks except u, and reports why it does not match.<br>
/// <var>pNode</var>: the sub-schema node<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pFirst</var> (output): on mismatch, the first error text without the path prefix; "" on match<br>
/// Returns: 1 when there is no error
ClassMethod MatchErr(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, Output pFirst As %String) As %Boolean [ Private ]
{
    Kill tE
    Set tN = 0, pFirst = ""
    If pNode.type = "array" {
        Do ..CheckArray(pNode, pVal, pType, pPath, ..#ALLFLAGS, .tE, .tN)
    } Else {
        Do ..CheckValue(pNode, pVal, pType, pPath, ..#ALLFLAGS, .tE, .tN)
    }
    If tN > 0 {
        Set tFull = tE(1), tPre = $Select(pPath = "":"(root)", 1:pPath)_": "
        If $Extract(tFull, 1, $Length(tPre)) = tPre Set tFull = $Extract(tFull, $Length(tPre)+1, *)
        Set pFirst = tFull
    }
    Quit (tN = 0)
}

/// Dispatches the composition checks: not (with s), oneOf/anyOf (with o), and allOf (always).<br>
/// <var>pNode</var>: field tree node<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pFlags</var>: active switch letters<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckComposition(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, pFlags As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If pFlags [ "s" Do ..CheckNots(pNode, pVal, pType, pPath, .pErrs, .pN)
    If pFlags [ "o" Do ..CheckAlts(pNode, pVal, pType, pPath, .pErrs, .pN)
    Do ..CheckAlls(pNode, pVal, pType, pPath, pFlags, .pErrs, .pN)
}

/// oneOf: exactly one alternative must match; anyOf: at least one. On failure the error lists the first reason from up to five alternatives.<br>
/// <var>pNode</var>: node holding the alts groups<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckAlts(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If '$IsObject(pNode.%Get("alts")) Quit
    Set tItg = pNode.alts.%GetIterator()
    While tItg.%GetNext(.tGk, .tGe) {
        Set tCnt = 0, tWhy = "", tI = 0
        Set tIta = tGe.list.%GetIterator()
        While tIta.%GetNext(.tAk, .tAlt) {
            Set tI = tI + 1
            If ..MatchErr(tAlt, pVal, pType, pPath, .tFirst) {
                Set tCnt = tCnt + 1
            } ElseIf tI <= 5 {
                Set tWhy = tWhy_$Select(tWhy = "":"", 1:"; ")_tI_": "_$Extract(tFirst, 1, 80)
            }
        }
        If tCnt = 0 {
            Do ..AddErr(.pErrs, .pN, pPath, "value does not match any alternative of "_tGe.kw_" ["_tWhy_"]")
        } ElseIf (tGe.kw = "oneOf") && (tCnt > 1) {
            Do ..AddErr(.pErrs, .pN, pPath, "value matches "_tCnt_" alternatives of oneOf, exactly one is allowed")
        }
    }
}

/// allOf: the value must satisfy every member; unknown fields (u) are not checked inside a member.<br>
/// <var>pNode</var>: node holding the alls members<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pFlags</var>: active switch letters<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckAlls(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, pFlags As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If '$IsObject(pNode.%Get("alls")) Quit
    Set tMflags = $Translate(pFlags, "u")
    Set tItm = pNode.alls.%GetIterator()
    While tItm.%GetNext(.tMk, .tMem) {
        If tMem.type = "array" {
            Do ..CheckArray(tMem, pVal, pType, pPath, tMflags, .pErrs, .pN)
        } Else {
            Do ..CheckValue(tMem, pVal, pType, pPath, tMflags, .pErrs, .pN)
        }
    }
}

/// not: reports an error for each schema in the nots list that the value matches.<br>
/// <var>pNode</var>: node holding the nots list<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckNots(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If '$IsObject(pNode.%Get("nots")) Quit
    Set tIt = pNode.nots.%GetIterator()
    While tIt.%GetNext(.tK, .tSub) {
        If ..Matches(tSub, pVal, pType, pPath) Do ..AddErr(.pErrs, .pN, pPath, "value must not match the schema in not")
    }
}

/// contains: counts the elements that match the contains node; minContains defaults to 1, maxContains to unlimited, and null elements never count.<br>
/// <var>pArr</var>: array node holding contains/minContains/maxContains<br>
/// <var>pVal</var>: the %DynamicArray<br>
/// <var>pLen</var>: its size<br>
/// <var>pPath</var>: path of the array<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckContains(pArr As %DynamicObject, pVal, pLen As %Integer, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Set tCn = pArr.%Get("contains")
    If '$IsObject(tCn) Quit
    Set tHasMin = (pArr.%GetTypeOf("minContains") = "number")
    Set tMinC = $Select(tHasMin:pArr.%Get("minContains"), 1:1)
    Set tHasMax = (pArr.%GetTypeOf("maxContains") = "number")
    Set tMaxC = $Select(tHasMax:pArr.%Get("maxContains"), 1:0)
    Set tCnt = 0
    For tI = 0:1:pLen-1 {
        Set tEt = pVal.%GetTypeOf(tI)
        If tEt = "null" Continue
        If ..Matches(tCn, pVal.%Get(tI), tEt, pPath_"("_(tI+1)_")") Set tCnt = tCnt + 1
        If 'tHasMax && (tCnt >= tMinC) Quit
    }
    If tCnt < tMinC Do ..AddErr(.pErrs, .pN, pPath, $Select(tHasMin:tCnt_" item(s) match contains, fewer than minContains "_tMinC, 1:"no item matches contains"))
    If tHasMax && (tCnt > tMaxC) Do ..AddErr(.pErrs, .pN, pPath, tCnt_" item(s) match contains, more than maxContains "_tMaxC)
}

/// enum: the value must equal one of the listed values; comparison is JSON-type-aware, so number 1, string "1" and boolean true are all distinct.<br>
/// <var>pNode</var>: node holding the enum array<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckEnum(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Set tFound = 0, tIt = pNode.enum.%GetIterator()
    While tIt.%GetNext(.tK, .tEv, .tEt) {
        If ..JSONEquals(pVal, pType, tEv, tEt) { Set tFound = 1  Quit }
    }
    If 'tFound Do ..AddErr(.pErrs, .pN, pPath, "value "_..ValText(pVal, pType)_" is not in the allowed list")
}

/// const: the value must equal the const value of the node by JSON equality; nodes without const are not checked.<br>
/// <var>pNode</var>: field tree node<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckConst(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Set tCt = pNode.%GetTypeOf("const")
    If tCt = "unassigned" Quit
    If '..JSONEquals(pVal, pType, pNode.%Get("const"), tCt) Do ..AddErr(.pErrs, .pN, pPath, "value does not equal const "_##class(JVDoc.SchemaImport).ConstText(pNode))
}

/// Checks numeric bounds (minimum/maximum, exclusiveMinimum/exclusiveMaximum in boolean or numeric form, multipleOf) and string length (minLength/maxLength, in characters).<br>
/// <var>pNode</var>: field tree node<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: JSON type of pVal; only number and string are checked<br>
/// <var>pPath</var>: path of the value<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckBounds(pNode As %DynamicObject, pVal, pType As %String, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    If pType = "number" {
        Set tMn = pNode.%GetTypeOf("minimum"), tEmn = pNode.%GetTypeOf("exclusiveMinimum")
        If tMn = "number" {
            If (tEmn = "boolean") && pNode.%Get("exclusiveMinimum") {
                If pVal <= pNode.%Get("minimum") Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be greater than minimum "_pNode.%Get("minimum")_" (exclusive)")
            } ElseIf pVal < pNode.%Get("minimum") {
                Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is less than minimum "_pNode.%Get("minimum"))
            }
        }
        If (tEmn = "number") && (pVal <= pNode.%Get("exclusiveMinimum")) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be greater than exclusiveMinimum "_pNode.%Get("exclusiveMinimum"))
        Set tMx = pNode.%GetTypeOf("maximum"), tEmx = pNode.%GetTypeOf("exclusiveMaximum")
        If tMx = "number" {
            If (tEmx = "boolean") && pNode.%Get("exclusiveMaximum") {
                If pVal >= pNode.%Get("maximum") Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be less than maximum "_pNode.%Get("maximum")_" (exclusive)")
            } ElseIf pVal > pNode.%Get("maximum") {
                Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is greater than maximum "_pNode.%Get("maximum"))
            }
        }
        If (tEmx = "number") && (pVal >= pNode.%Get("exclusiveMaximum")) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be less than exclusiveMaximum "_pNode.%Get("exclusiveMaximum"))
        // multipleOf: the quotient is treated as a multiple when it is within 1E-9 of an integer, tolerating floating-point rounding
        Set tMo = pNode.%Get("multipleOf")
        If (pNode.%GetTypeOf("multipleOf") = "number") && (tMo > 0) {
            Set tQ = pVal / tMo
            If tQ < 0 Set tQ = -tQ
            Set tR = tQ - (tQ\1)
            If (tR > 1E-9) && (tR < (1 - 1E-9)) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is not a multiple of "_tMo)
        }
    } ElseIf pType = "string" {
        Set tLen = $Length(pVal)
        If (pNode.%GetTypeOf("minLength") = "number") && (tLen < pNode.%Get("minLength")) Do ..AddErr(.pErrs, .pN, pPath, "length "_tLen_" is shorter than minLength "_pNode.%Get("minLength"))
        If (pNode.%GetTypeOf("maxLength") = "number") && (tLen > pNode.%Get("maxLength")) Do ..AddErr(.pErrs, .pN, pPath, "length "_tLen_" is longer than maxLength "_pNode.%Get("maxLength"))
    }
}

/// uniqueItems: scalars are keyed by type+value and confirmed with JSONEquals; objects and arrays are compared pairwise (at most the first 1000 of them). Each duplicate is reported at its own index.<br>
/// <var>pVal</var>: the %DynamicArray<br>
/// <var>pLen</var>: its size<br>
/// <var>pPath</var>: path of the array<br>
/// <var>pErrs</var> (byref): error list, see AddErr<br>
/// <var>pN</var> (byref): number of errors
ClassMethod CheckUnique(pVal, pLen As %Integer, pPath As %String, ByRef pErrs, ByRef pN) [ Private ]
{
    Kill tSeen
    Set tCx = 0
    For tI = 0:1:pLen-1 {
        Set tT = pVal.%GetTypeOf(tI), tV = pVal.%Get(tI)
        If (tT = "object") || (tT = "array") {
            Set tCx = tCx + 1
            If tCx > 1000 Continue
            Set tKey = tT_"|"
        } ElseIf tT = "null" {
            Set tKey = "null|"
        } ElseIf tT = "number" {
            Set tKey = "number|"_(+tV)
        } Else {
            Set tKey = tT_"|"_$Extract(tV, 1, 200)
        }
        Set tDup = "", tJ = ""
        For {
            Set tJ = $Order(tSeen(tKey, tJ))
            If tJ = "" Quit
            If ..JSONEquals(tV, tT, pVal.%Get(tJ), pVal.%GetTypeOf(tJ)) { Set tDup = tJ  Quit }
        }
        If tDup '= "" {
            Do ..AddErr(.pErrs, .pN, pPath_"("_(tI+1)_")", "duplicates item "_(tDup+1)_" (uniqueItems)")
        } Else {
            Set tSeen(tKey, tI) = ""
        }
    }
}

/// JSON equality: types must match, object key order is ignored and numbers compare by value.<br>
/// <var>pA</var>: first value<br>
/// <var>pTA</var>: JSON type of pA<br>
/// <var>pB</var>: second value<br>
/// <var>pTB</var>: JSON type of pB<br>
/// Returns: 1 when the values are equal
ClassMethod JSONEquals(pA, pTA As %String, pB, pTB As %String) As %Boolean [ Private ]
{
    If pTA '= pTB Quit 0
    If pTA = "null" Quit 1
    If pTA = "number" Quit (+pA = +pB)
    If (pTA = "string") || (pTA = "boolean") Quit (pA = pB)
    If pTA = "array" {
        Set tN = pA.%Size()
        If tN '= pB.%Size() Quit 0
        Set tOk = 1
        For tI = 0:1:tN-1 {
            If '..JSONEquals(pA.%Get(tI), pA.%GetTypeOf(tI), pB.%Get(tI), pB.%GetTypeOf(tI)) { Set tOk = 0  Quit }
        }
        Quit tOk
    }
    If pTA = "object" {
        Set tOk = 1, tNa = 0, tNb = 0
        Set tIt = pA.%GetIterator()
        While tIt.%GetNext(.tK, .tV, .tT) {
            Set tNa = tNa + 1
            Set tTb = pB.%GetTypeOf(tK)
            If (tTb = "unassigned") || '..JSONEquals(tV, tT, pB.%Get(tK), tTb) { Set tOk = 0  Quit }
        }
        If 'tOk Quit 0
        Set tIt = pB.%GetIterator()
        While tIt.%GetNext(.tK2) { Set tNb = tNb + 1 }
        Quit (tNa = tNb)
    }
    Quit 0
}

/// Formats a value for an error message.<br>
/// <var>pVal</var>: the value<br>
/// <var>pType</var>: its JSON type<br>
/// Returns: JSON text for objects and arrays (60 characters at most), a quoted string, true/false, or the number
ClassMethod ValText(pVal, pType As %String) As %String [ Private ]
{
    If (pType = "object") || (pType = "array") Quit $Extract(##class(JVDoc.SchemaImport).JSONStr(pVal), 1, 60)
    If pType = "string" Quit "'"_$Extract(pVal, 1, 60)_"'"
    If pType = "boolean" Quit $Select(pVal:"true", 1:"false")
    Quit pVal
}

// ---------------- Search table indexing ----------------

/// Returns the search table class of this document: the per-DocType registration (JVDoc.Schema.GetSearchTable) first, then SEARCHTABLE.<br>
/// Returns: the class name, or "" when the document is not indexed
Method SearchTableClass() As %String
{
    Set tSt = ##class(JVDoc.Schema).GetSearchTable(..DocType)
    If tSt = "" Set tSt = ..#SEARCHTABLE
    Quit tSt
}

/// Rebuilds the search table rows of this document by calling IndexDoc on its search table class; does nothing for an unsaved document or one without a search table.<br>
/// <var>pClearFirst</var>: 1 (default) deletes the existing rows for the DocId first to avoid duplicates and stale values; 0 when there cannot be any (new document, table just emptied)<br>
/// Returns: error from the cleanup or from IndexDoc
Method IndexNow(pClearFirst As %Boolean = 1) As %Status
{
    Set tSt = ..SearchTableClass()
    If tSt = "" Quit $$$OK
    Set tId = ..%Id()
    If tId = "" Quit $$$OK
    If pClearFirst {
        Set tSC = ..ClearIndexRows(tSt)
        If $$$ISERR(tSC) Quit tSC
    }
    Quit $classmethod(tSt, "IndexDoc", $this)
}

/// Deletes this document's rows from a search table.<br>
/// <var>pSearchTable</var>: the search table class name<br>
/// Returns: error with the SQLCODE when the DELETE fails
Method ClearIndexRows(pSearchTable As %String) As %Status [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_..SqlTableOf(pSearchTable)_" WHERE DocId = ?", ..%Id())
    If tRs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "Search table cleanup failed, SQLCODE="_tRs.%SQLCODE_" "_tRs.%Message)
    Quit $$$OK
}

/// Returns the SQL name of a compiled class from the class dictionary, honoring SqlSchemaName and SqlTableName overrides.<br>
/// <var>pClass</var>: class name<br>
/// Returns: "schema.table", or "" when the class does not exist
ClassMethod SqlTableOf(pClass As %String) As %String [ Private ]
{
    Set tC = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
    If '$IsObject(tC) Quit ""
    Quit tC.SqlSchemaName_"."_tC.SqlTableName
}

/// Rebuilds one search table from scratch: deletes all its rows, then re-indexes every stored document whose search table is that class.<br>
/// <var>pSearchTable</var>: the search table class name<br>
/// <var>pCount</var> (output): number of documents indexed<br>
/// Returns: error when the class is missing or the cleanup fails; documents that fail to index are skipped and their errors combined in the status
ClassMethod Reindex(pSearchTable As %String, Output pCount As %Integer) As %Status
{
    Set pCount = 0
    If pSearchTable = "" Quit $$$ERROR($$$GeneralError, "Search table class is required")
    Set tTbl = ..SqlTableOf(pSearchTable)
    If tTbl = "" Quit $$$ERROR($$$GeneralError, "Class not found: "_pSearchTable)
    Set tRs0 = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_tTbl)
    If tRs0.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "Cleanup failed, SQLCODE="_tRs0.%SQLCODE)
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM JVDoc.Document")
    Set tSC = $$$OK
    While tRs.%Next() {
        Set tD = ..%OpenId(tRs.%Get("ID"))
        If '$IsObject(tD) || (tD.SearchTableClass() '= pSearchTable) Continue
        Set tIsc = tD.IndexNow(0)
        If $$$ISERR(tIsc) {
            Set tSt = $$$ERROR($$$GeneralError, "Document "_tD.%Id()_": "_$System.Status.GetErrorText(tIsc))
            Set tSC = $Select(+tSC:tSt, 1:$System.Status.AppendStatus(tSC, tSt))
            Continue
        }
        Set pCount = pCount + 1
    }
    Quit tSC
}

/// Called by the IndexDoc that a search table generates: collects the scalar values at a path, expanding () to every array element.<br>
/// Values are truncated to SEARCHVALUEMAXLEN; objects, arrays, null and "" are not indexed.<br>
/// <var>pSegmentPropertyPath</var>: the path from the SearchSpec item, e.g. "[items().sku]" without the brackets<br>
/// <var>pSeparators</var>: ignored<br>
/// <var>pArray</var> (byref): cleared, then receives pArray(value)=number of occurrences<br>
/// <var>pStatus</var> (output): always $$$OK; missing paths simply give no values<br>
/// <var>pSchemaCategory</var>: ignored<br>
/// <var>pLongArray</var> (byref): ignored
Method FindSegmentValuesArray(pSegmentPropertyPath As %String, pSeparators As %String = "", ByRef pArray As %String, Output pStatus As %Status, pSchemaCategory As %String = "", ByRef pLongArray As %String)
{
    Kill pArray
    Set pStatus = ..CollectValues(..Clean(pSegmentPropertyPath), .pArray)
}

/// Recursively walks a path, expanding () into all array elements, and collects the scalar values for search table indexing.<br>
/// <var>pPath</var>: cleaned path, possibly with ()<br>
/// <var>pArray</var> (byref): receives pArray(value)=count; values are truncated to SEARCHVALUEMAXLEN<br>
/// Returns: $$$OK; missing paths and non-scalar values are skipped
Method CollectValues(pPath As %String, ByRef pArray As %String) As %Status [ Private ]
{
    Set tP = $Find(pPath, "()")
    If 'tP {
        Set tVal = ..Locate(pPath, .tType, .tCnt, .tSC)
        If $$$ISERR(tSC) || (tType = "object") || (tType = "array") || (tType = "null") || (tVal = "") Quit $$$OK
        Set tVal = $Extract(tVal, 1, ..#SEARCHVALUEMAXLEN)
        Set pArray(tVal) = $Get(pArray(tVal)) + 1
        Quit $$$OK
    }
    Set tHead = $Extract(pPath, 1, tP-3), tTail = $Extract(pPath, tP, *)
    Set tIdx = ""
    For {
        Set tIdx = ..GetNextIndex(tHead_"()", tIdx, .tNsc)
        If $$$ISERR(tNsc) || (tIdx = "") Quit
        Do ..CollectValues(tHead_"("_tIdx_")"_tTail, .pArray)
    }
    Quit $$$OK
}

// ---------------- Persistence callbacks ----------------

/// Decides whether the search table rows must be rebuilt after this save: new document, content rewritten by %OnAddToSaveSet, or changed DocType.<br>
/// <var>pInsert</var>: 1 when the document is saved for the first time<br>
/// Returns: $$$OK
Method %OnBeforeSave(pInsert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    Set ..NeedsIndex = pInsert || ..ContentChanged || (..DocType '= ..IndexedDocType)
    Set ..ContentChanged = 0
    Quit $$$OK
}

/// Serializes a modified Obj back to Raw at the start of %Save. This must happen here and not in %OnBeforeSave: %OnBeforeSave runs inside
/// %SerializeObject, after the stream references have been taken, so rewriting a Raw that is already stored (a document opened from the
/// database, or a clone of one as DTL create='copy' makes) would leave the saved document pointing to an empty stream.<br>
/// <var>depth</var>: save depth passed by %Save<br>
/// <var>insert</var>: 1 when the document is new<br>
/// <var>callcount</var>: how often the hook has run in this save; the rewrite happens once because Dirty is cleared<br>
/// Returns: $$$OK
Method %OnAddToSaveSet(depth As %Integer = 3, insert As %Integer = 0, callcount As %Integer = 0) As %Status [ Private, ServerOnly = 1 ]
{
    If ..Dirty && $IsObject(..Obj) {
        Do ..Raw.Clear()
        Do ..Obj.%ToJSON(..Raw)
        Set ..Dirty = 0, ..ContentChanged = 1
    }
    Quit $$$OK
}

/// Rebuilds the search table rows when %OnBeforeSave found them stale. When the DocType changed and the previous DocType was bound to a different search table, the rows in that table are removed as well.<br>
/// <var>pInsert</var>: 1 when the document was saved for the first time (no old rows to delete)<br>
/// Returns: always $$$OK; an indexing error is logged to the event log, so the save itself succeeds
Method %OnAfterSave(pInsert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    If '..NeedsIndex Quit $$$OK
    Try {
        Set tSC = $$$OK
        If 'pInsert && (..IndexedDocType '= "") && (..IndexedDocType '= ..DocType) {
            Set tOldSt = ##class(JVDoc.Schema).GetSearchTable(..IndexedDocType)
            If tOldSt = "" Set tOldSt = ..#SEARCHTABLE
            If (tOldSt '= "") && (tOldSt '= ..SearchTableClass()) Set tSC = ..ClearIndexRows(tOldSt)
        }
        If $$$ISOK(tSC) Set tSC = ..IndexNow('pInsert)
        If $$$ISERR(tSC) {
            Do ##class(Ens.Util.Log).LogStatus($classname(), "%OnAfterSave", tSC)
        } Else {
            Set ..IndexedDocType = ..DocType
        }
    }
    Catch tEx {
        Do ##class(Ens.Util.Log).LogStatus($classname(), "%OnAfterSave", tEx.AsStatus())
    }
    Quit $$$OK
}

/// Remembers the DocType the stored search table rows were built for, so that saving an unchanged document does not re-index it.<br>
/// Returns: $$$OK
Method %OnOpen() As %Status [ Private, ServerOnly = 1 ]
{
    Set ..IndexedDocType = ..DocType
    Quit $$$OK
}

/// Removes the search table rows of a document that is deleted with %DeleteId; Ens.MessageHeader.Purge calls the same product method for every body it purges.<br>
/// <var>pOID</var>: OID of the document being deleted<br>
/// Returns: the status of Ens.SearchTableBase.RemoveSearchTableEntries
ClassMethod %OnDelete(pOID As %ObjectIdentity) As %Status [ Private, ServerOnly = 1 ]
{
    Quit ##class(Ens.SearchTableBase).RemoveSearchTableEntries($classname(), $List(pOID, 1), 1)
}

// ---------------- Display in Message Viewer and Visual Trace ----------------

/// Content type the Message Viewer / Visual Trace content pane uses for this body.
/// Ens.MessageBody inherits %XML.Adaptor, so the base implementation returns text/xml and the browser
/// would render the %ShowContents output as an XML document, collapsing all whitespace.<br>
/// Returns: "text/html"
Method %GetContentType() As %String
{
    Quit "text/html"
}

/// Renders the message body for Message Viewer: indented JSON when the page asked for application/json, otherwise an HTML fragment with the DocType and the indented JSON.<br>
/// <var>pZenOutput</var>: passed by the product; forwarded to OnShowJSONContents
Method %ShowContents(pZenOutput As %Boolean = 0)
{
    If $IsObject($Get(%response)) && (%response.ContentType = "application/json") {
        Do ..OnShowJSONContents(pZenOutput)
    } Else {
        Write ..ContentsHTML()
    }
}

/// Writes the document JSON itself, indented, for the application/json view; the base implementation would serialize the class properties (Raw, DocType, ...) instead. The raw stream is written unchanged when it does not parse.<br>
/// <var>pZenOutput</var>: passed by the product; ignored
Method OnShowJSONContents(pZenOutput As %Boolean = 0)
{
    Set tObj = ..GetObj(.tSC)
    If $$$ISERR(tSC) || '$IsObject(tObj) {
        Do ..Raw.Rewind()
        Do ..Raw.OutputToDevice()
        Quit
    }
    Do ..OutputFormattedJSON(tObj)
}

/// Builds the HTML view of the document: the DocType and the JSON indented inside a pre element; the raw text is shown when the JSON does not parse.<br>
/// Returns: the HTML fragment, truncated after 200000 characters of content with a "(content truncated)" note
Method ContentsHTML() As %String
{
    Set tMax = 200000
    Set tObj = ..GetObj(.tSC)
    If $$$ISERR(tSC) || '$IsObject(tObj) {
        Do ..Raw.Rewind()
        Set tTxt = ..Raw.Read(tMax)
    } Else {
        Set tFmt = ##class(%JSON.Formatter).%New()
        Set tFmt.Indent = 1, tFmt.IndentChars = "  ", tFmt.LineTerminator = $Char(10)
        Set tFsc = tFmt.FormatToString(..ToJSONString(tObj), .tTxt)
        If $$$ISERR(tFsc) Set tTxt = ..ToJSONString(tObj)
    }
    Set tMore = ($Length(tTxt) > tMax)
    If tMore Set tTxt = $Extract(tTxt, 1, tMax)
    Set tTxt = $Translate(tTxt, $Char(13))
    Set tOut = "<div>"_$Char(10)
    Set tOut = tOut_"<div><b>DocType:</b> "_$ZConvert(..DocType, "O", "HTML")_"</div>"_$Char(10)
    Set tOut = tOut_"<pre style=""font-family:monospace; white-space:pre; overflow:auto;"">"_$ZConvert(tTxt, "O", "HTML")_"</pre>"_$Char(10)
    If tMore Set tOut = tOut_"<div><i>(content truncated)</i></div>"_$Char(10)
    Quit tOut_"</div>"_$Char(10)
}

Storage Default
{
<Data name="DocumentDefaultData">
<Subscript>"Document"</Subscript>
<Value name="1">
<Value>Raw</Value>
</Value>
<Value name="2">
<Value>DocType</Value>
</Value>
<Value name="3">
<Value>TimeCreated</Value>
</Value>
<Value name="4">
<Value>Source</Value>
</Value>
<Value name="5">
<Value>IsMutable</Value>
</Value>
<Value name="6">
<Value>OriginalDocId</Value>
</Value>
</Data>
<Data name="UserValues">
<Attribute>UserValues</Attribute>
<Structure>subnode</Structure>
<Subscript>"JVDoc.Document.UserValues"</Subscript>
</Data>
<DefaultData>DocumentDefaultData</DefaultData>
<IndexLocation>^JVDoc.DocumentI</IndexLocation>
<Type>%Storage.Persistent</Type>
}

}
