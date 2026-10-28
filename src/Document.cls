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
    Set sc = $$$OK
    If $IsObject(pInit) {
        Set cls = $ClassName(pInit)
        If (cls = "%Library.DynamicObject") || (cls = "%Library.DynamicArray") {
            Set ..Obj = pInit, ..Dirty = 1
        } Else {
            Set sc = ..Raw.CopyFrom(pInit)
        }
    } ElseIf pInit '= "" {
        Do ..Raw.Write(pInit)
    }
    Quit sc
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
        } Catch ex {
            Set pSC = ex.AsStatus()
        }
    }
    Quit ..Obj
}

/// Serializes a dynamic entity to a string by writing through a temporary character stream.<br>
/// <var>pObj</var>: the %DynamicAbstractObject to serialize<br>
/// Returns: the JSON text (at most $$$MaxLocalLength characters)
ClassMethod ToJSONString(pObj) As %String [ Private ]
{
    Set s = ##class(%Stream.TmpCharacter).%New()
    Do pObj.%ToJSON(s)
    Do s.Rewind()
    Quit s.Read($$$MaxLocalLength)
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
    Set p = $ZStrip(pPath, "<>W")
    If ($Extract(p) = "{") && ($Extract(p, *) = "}") Set p = $Extract(p, 2, *-1)
    Quit p
}

/// Parses a VDoc path into segments.<br>
/// <var>pPath</var>: path such as "a.b(2).c"; outer {} and whitespace are allowed<br>
/// <var>pSegs</var> (output): pSegs(n)=$lb(name, hasParen, idx) for each segment n; name is "" for a segment like "(2)" on a root array, idx is "" for empty ()<br>
/// <var>pKey</var>: comma-separated indexes that fill the empty () in order (DTL foreach keys); "" leaves them empty<br>
/// Returns: "Malformed path" error when a parenthesis is not closed
ClassMethod ParsePath(pPath As %String, Output pSegs, pKey As %String = "") As %Status
{
    Kill pSegs
    Set path = ..Clean(pPath), len = $Length(path), i = 1, n = 0, k = 0
    While i <= len {
        Set name = "", idx = "", paren = 0
        While i <= len {
            Set c = $Extract(path, i)
            If (c = ".") || (c = "(") Quit
            Set name = name_c, i = i+1
        }
        If (i <= len) && ($Extract(path, i) = "(") {
            Set close = $Find(path, ")", i)
            If 'close Quit
            Set idx = $Extract(path, i+1, close-2), paren = 1, i = close
            If (idx = "") && (pKey '= "") { Set k = k+1, idx = $Piece(pKey, ",", k) }
        }
        If (i <= len) && ($Extract(path, i) = ".") Set i = i+1
        Set n = n+1, pSegs(n) = $ListBuild(name, paren, idx)
    }
    If i <= len Quit $$$ERROR($$$GeneralError, "Malformed path: "_pPath)
    Quit $$$OK
}

/// Normalizes a path for field tree lookups by replacing every indexed or empty parenthesis with ().<br>
/// <var>pPath</var>: VDoc path, e.g. "items(2).qty"<br>
/// Returns: the normalized path, e.g. "items().qty"; "" for a malformed path
ClassMethod NormPath(pPath As %String) As %String
{
    If $$$ISERR(..ParsePath(pPath, .segs)) Quit ""
    Set norm = "", n = $Order(segs(""), -1)
    For i = 1:1:n {
        Set norm = norm_$Select(norm = "":"", 1:".")_$List(segs(i), 1)_$Select($List(segs(i), 2):"()", 1:"")
    }
    Quit norm
}

/// Advances one path segment.<br>
/// <var>pCur</var>: the current node (%DynamicObject or %DynamicArray)<br>
/// <var>pSeg</var>: one segment from ParsePath, $lb(name, hasParen, idx); "name()" addresses the array itself, "name(k)" element k (1-based), an empty name pCur itself<br>
/// <var>pType</var> (output): JSON type of the value found, or "unassigned" when the segment does not resolve<br>
/// Returns: the value found; "" when it does not resolve
ClassMethod Step(pCur, pSeg As %List, Output pType As %String) [ Private ]
{
    Set pType = "unassigned"
    Set name = $List(pSeg, 1), paren = $List(pSeg, 2), idx = $List(pSeg, 3)
    Set val = pCur
    If name '= "" {
        If '$IsObject(pCur) || ($ClassName(pCur) '= "%Library.DynamicObject") Quit ""
        Set t = pCur.%GetTypeOf(name)
        If t = "unassigned" Quit ""
        Set val = pCur.%Get(name), pType = t
    } ElseIf $IsObject(pCur) && ($ClassName(pCur) = "%Library.DynamicArray") {
        Set pType = "array"
    }
    If 'paren Quit val
    If pType '= "array" { Set pType = "unassigned" Quit "" }
    If idx = "" Quit val
    Set i = +idx - 1
    If (i < 0) || (i >= val.%Size()) { Set pType = "unassigned" Quit "" }
    Set pType = val.%GetTypeOf(i)
    Quit val.%Get(i)
}

/// Walks the parsed document along a path.<br>
/// <var>pPath</var>: VDoc path; "" addresses the root<br>
/// <var>pType</var> (output): JSON type of the value found, or "unassigned" when the path does not resolve<br>
/// <var>pCount</var> (output): 1 when the path ends in a bare (), meaning the caller should report the element count of the returned array<br>
/// <var>pSC</var> (output): parse or path error; "Path not found" when a segment is missing or an intermediate value is not an object or array<br>
/// Returns: the value at the path (dynamic entity for objects and arrays); "" when not found
Method Locate(pPath As %String, Output pType As %String, Output pCount As %Boolean, Output pSC As %Status) [ Private ]
{
    Set pType = "unassigned", pCount = 0
    Set cur = ..GetObj(.pSC)
    If $$$ISERR(pSC) Quit ""
    Set pSC = ..ParsePath(pPath, .segs)
    If $$$ISERR(pSC) Quit ""
    Set n = $Order(segs(""), -1)
    If n = 0 { Set pType = $Select($ClassName(cur) = "%Library.DynamicArray":"array", 1:"object") Quit cur }
    For i = 1:1:n {
        Set val = ..Step(cur, segs(i), .pType)
        If (pType = "unassigned") || ((i < n) && (pType '= "object") && (pType '= "array")) {
            Set pType = "unassigned", pSC = $$$ERROR($$$GeneralError, "Path not found: "_pPath)
            Quit
        }
        Set cur = val
    }
    If pType = "unassigned" Quit ""
    Set pCount = ($List(segs(n), 2) && ($List(segs(n), 3) = ""))
    Quit cur
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
    Set val = ..Locate(pPropertyPath, .type, .count, .pStatus)
    If $$$ISERR(pStatus) Quit ""
    If count Quit val.%Size()
    If (type = "object") || (type = "array") Quit ..ToJSONString(val)
    If type = "null" Quit ""
    Quit val
}

/// Returns the value at a path together with its real JSON type; used for type-aware copying between JVDoc documents.<br>
/// <var>pPath</var>: VDoc path; a bare () ending asks for the element count<br>
/// <var>pJType</var> (output): JSON type of the value (string, number, boolean, null, object, array), "number" for an element count, "unassigned" when not found<br>
/// <var>pSC</var> (output): "Path not found" or parse error, or $$$OK<br>
/// Returns: the scalar value, a deep copy for objects and arrays, "" for null, or the element count
Method GetTypedAt(pPath As %String, Output pJType As %String, Output pSC As %Status)
{
    Set val = ..Locate(pPath, .type, .count, .pSC)
    Set pJType = type
    If $$$ISERR(pSC) Quit ""
    If count { Set pJType = "number"  Quit val.%Size() }
    If (type = "object") || (type = "array") Quit ..CloneDyn(val)
    If type = "null" Quit ""
    Quit val
}

/// Iterates the array at a path; drives the () expansion in CopyValues and search table indexing (Ens.VDoc.Interface).<br>
/// <var>pPath</var>: path of the array; a trailing () is ignored<br>
/// <var>pIndex</var>: the current 1-based index; "" to start<br>
/// <var>pStatus</var> (byref): set to the path error when the path does not resolve<br>
/// Returns: the next 1-based index, or "" at the end, when the path is missing or when it is not an array
Method GetNextIndex(pPath As %String, pIndex As %String = "", ByRef pStatus As %Status = {$$$OK}) As %String
{
    Set p = ..Clean(pPath)
    If $Extract(p, *-1, *) = "()" Set p = $Extract(p, 1, *-2)
    Set arr = ..Locate(p, .type, .count, .pStatus)
    If $$$ISERR(pStatus) || (type '= "array") Quit ""
    Set next = $Select(pIndex = "":1, 1:pIndex+1)
    Quit $Select(next <= arr.%Size():next, 1:"")
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
    Set cur = ..GetObj(.sc)
    If $$$ISERR(sc) Quit sc
    Set sc = ..ParsePath(pPropertyPath, .segs, pKey)
    If $$$ISERR(sc) Quit sc
    Set n = $Order(segs(""), -1)
    If n = 0 Quit $$$ERROR($$$GeneralError, "Empty path")
    Set action = $ZConvert(pAction, "L")
    If (action = "remove") || (action = "clear") {
        If ..RemoveAt(cur, .segs, n) Set ..Dirty = 1
        Quit $$$OK
    }
    Try {
        Set norm = ""
        For i = 1:1:n {
            Set paren = $List(segs(i), 2), idx = $List(segs(i), 3)
            If paren && ((idx '= "") || (i < n)) && (+idx < 1) Throw ##class(%Exception.General).%New("BadIndex", 5001, , "index must be >= 1: "_pPropertyPath)
            Set norm = norm_$Select(norm = "":"", 1:".")_$List(segs(i), 1)_$Select(paren:"()", 1:"")
        }
        Set name = $List(segs(n), 1), paren = $List(segs(n), 2), idx = $List(segs(n), 3)
        If (action = "append") && 'paren Set paren = 1, idx = "", norm = norm_"()"
        Set vt = ##class(JVDoc.Schema).TypeAt(..DocType, norm)
        If (vt = "any") && (..TypedJT '= "") Set vt = "@"_..TypedJT
        Set val = ..Coerce(pValue, vt, .jt)
        // From here on a PathConflict can only come from a node that already existed, so nothing has been created yet when it is thrown
        For i = 1:1:n-1 {
            If $List(segs(i), 2) {
                Set cur = ..EnsureElem(..ArrayAt(cur, $List(segs(i), 1)), +$List(segs(i), 3))
            } Else {
                Set cur = ..EnsureChild(cur, $List(segs(i), 1), "{}")
            }
        }
        If paren {
            Set arr = ..ArrayAt(cur, name)
            If idx = "" {
                Do ..Store(arr, "", val, jt, 1)                  // name() means append
            } Else {
                While arr.%Size() < +idx { Do arr.%Push("", "null") }
                Do ..Store(arr, +idx-1, val, jt)
            }
        } Else {
            Do ..Store(cur, name, val, jt)
        }
        Set ..Dirty = 1
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
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
        Set sc = ..SetValueAt(pVal, pPath, pAction, pKey)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Set ..TypedJT = ""
    Quit sc
}

/// Removes the node at a parsed path without creating anything on the way; "name(k)" removes element k, "name" and "name()" remove the property itself.<br>
/// <var>pRoot</var>: the document root<br>
/// <var>pSegs</var> (byref): segments from ParsePath<br>
/// <var>pN</var>: number of segments<br>
/// Returns: 1 when a node was removed, 0 when the path did not exist
ClassMethod RemoveAt(pRoot, ByRef pSegs, pN As %Integer) As %Boolean [ Private ]
{
    Set cur = pRoot, t = $Select($ClassName(cur) = "%Library.DynamicArray":"array", 1:"object")
    For i = 1:1:pN-1 {
        Set cur = ..Step(cur, pSegs(i), .t)
        If (t '= "object") && (t '= "array") Quit
    }
    If (t '= "object") && (t '= "array") Quit 0
    Set name = $List(pSegs(pN), 1), paren = $List(pSegs(pN), 2), idx = $List(pSegs(pN), 3)
    If paren && (idx '= "") {
        If name = "" {
            Set arr = cur
        } Else {
            Set arr = ..Step(cur, $ListBuild(name, 0, ""), .t)
            If t '= "array" Quit 0
        }
        If (+idx < 1) || (+idx > arr.%Size()) Quit 0
        Do arr.%Remove(+idx-1)
        Quit 1
    }
    If (name = "") || (t '= "object") || (cur.%GetTypeOf(name) = "unassigned") Quit 0
    Do cur.%Remove(name)
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
    Set t = pParent.%GetTypeOf(pName)
    If ((pKind = "{}") && (t = "object")) || ((pKind = "[]") && (t = "array")) Quit pParent.%Get(pName)
    If (t '= "unassigned") && (t '= "null") {
        Throw ##class(%Exception.General).%New("PathConflict", 5001, , pName_" exists with type "_t)
    }
    If pKind = "{}" { Set new = {} } Else { Set new = [] }
    Do pParent.%Set(pName, new)
    Quit new
}

/// Returns the object at an array index, padding the array with nulls and replacing a null element with {} when needed.<br>
/// <var>pArr</var>: the %DynamicArray<br>
/// <var>pIdx</var>: 1-based index<br>
/// Returns: the element object; throws BadIndex for pIdx < 1 and PathConflict when the element holds a non-object value
ClassMethod EnsureElem(pArr, pIdx As %Integer) [ Private ]
{
    If pIdx < 1 Throw ##class(%Exception.General).%New("BadIndex", 5001, , "index must be >= 1")
    While pArr.%Size() < pIdx { Do pArr.%Push("", "null") }
    Set t = pArr.%GetTypeOf(pIdx-1)
    If t '= "object" {
        If t '= "null" Throw ##class(%Exception.General).%New("PathConflict", 5001, , "element "_pIdx_" is "_t)
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
        Set v = ""
        If (pType '= "any") || ($Extract(pValue) = "{") || ($Extract(pValue) = "[") {
            Try { Set v = ##class(%DynamicAbstractObject).%FromJSON(pValue) } Catch { Set v = "" }
        }
        If $IsObject(v) {
            Set pJType = $Select($ClassName(v) = "%Library.DynamicArray":"array", 1:"object")
            Quit v
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
    Set p = $Find(pSrc, "()")
    If 'p {
        // When both source and target are JVDoc.Document and the target field is 'any', copy with the source value's real JSON type without going through a string
        If pSource.%Extends("JVDoc.Document") && (##class(JVDoc.Schema).TypeAt(..DocType, ..NormPath(pTgt)) = "any") {
            Set val = pSource.GetTypedAt(pSrc, .jt, .gsc)
            If $$$ISERR(gsc) Quit $Select(pIgnoreMissing:$$$OK, 1:gsc)
            Quit ..SetTypedAt(val, jt, pTgt, pAction, pKey)
        }
        Set val = pSource.GetValueAt(pSrc, , .gsc)
        If $$$ISERR(gsc) Quit $Select(pIgnoreMissing:$$$OK, 1:gsc)
        Quit ..SetValueAt(val, pTgt, pAction, pKey)
    }
    Set head = $Extract(pSrc, 1, p-3), tail = $Extract(pSrc, p, *)
    Set idx = "", sc = $$$OK
    For {
        Set idx = pSource.GetNextIndex(head_"()", idx, .nsc)
        If $$$ISERR(nsc) || (idx = "") Quit
        Set tgt = pTgt, q = $Find(tgt, "()")
        If q Set tgt = $Extract(tgt, 1, q-3)_"("_idx_")"_$Extract(tgt, q, *)
        Set sc = ..CopyExpand(pSource, head_"("_idx_")"_tail, tgt, pAction, pKey, pIgnoreMissing)
        If $$$ISERR(sc) Quit
    }
    Quit sc
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
    Set ref = $Get(pContents)
    Set isRef = (("%" = $Extract(ref)) || ("^" = $Extract(ref)))
    Set sc = $$$OK
    Try {
        Set tree = ##class(JVDoc.Schema).GetTree(pDocType)
        If '$IsObject(tree) {
            Set sc = $$$ERROR($$$GeneralError, "Unknown DocType: "_pDocType)
        } Else {
            Kill tmp
            Do ..Fill(tree.children, .tmp, pExtraDetails)
            If isRef {
                Kill @ref
                Merge @ref = tmp
            } Else {
                Kill pContents
                Merge pContents = tmp
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Builds one level of the content array from a children list, recursing into object children.<br>
/// <var>pChildren</var>: children array of a field tree node<br>
/// <var>pArr</var> (byref): receives pArr(n,"name"), pArr(n,"type")="()" for arrays, opt/desc/vals when pExtra is set, and the sub-levels; pArr itself is set to the child count<br>
/// <var>pExtra</var>: 1 adds opt, desc and vals
ClassMethod Fill(pChildren As %DynamicArray, ByRef pArr, pExtra) [ Private ]
{
    Set n = 0, it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) {
        Set n = n+1
        Set isArr = (c.type = "array")
        Set el = $Select(isArr:c.items, 1:c)
        Set pArr(n, "name") = c.name_$Select(isArr:"()", 1:"")
        // Consistent with product convention: scalars omit the type; array nodes use "()" as the type
        If isArr Set pArr(n, "type") = "()"
        If pExtra {
            Set pArr(n, "opt") = +c.opt
            If c.desc '= "" Set pArr(n, "desc") = c.desc
            If c.vals '= "" Set pArr(n, "vals") = c.vals
        }
        If (el.type = "object") && $IsObject(el.children) {
            Kill sub
            Do ..Fill(el.children, .sub, pExtra)
            Merge pArr(n) = sub
        }
    }
    Set pArr = n
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
    Set rows = "", std = $Get(pStandard)
    // pStandard=0 means standard categories only; all JVDoc categories are user-defined, so nothing is returned
    If std '= "0" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT Category FROM JVDoc.SchemaDef ORDER BY Category")
        If rs.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
        While rs.%Next() {
            Set c = rs.%Get("Category")
            If ..Match(c, std) Set rows = rows_$ListBuild($ListBuild(c, "JSON schema category", 0, ""))
        }
    }
    Set pHandle = $ListBuild(0, rows)
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
    Set rows = "", cat = $Get(pCategory)
    If cat '= "0" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Category, Name FROM JVDoc.SchemaDef ORDER BY Category, Name")
        If rs.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
        While rs.%Next() {
            Set c = rs.%Get("Category")
            If ..Match(c, cat) Set rows = rows_$ListBuild($ListBuild(c_":"_rs.%Get("Name")))
        }
    }
    Set pHandle = $ListBuild(0, rows)
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
    Set pos = $ListGet(pHandle, 1) + 1, rows = $ListGet(pHandle, 2)
    If pos > $ListLength(rows) {
        Set pRow = "", pAtEnd = 1, pHandle = ""
        Quit $$$OK
    }
    Set pRow = $List(rows, pos), pHandle = $ListBuild(pos, rows)
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
    Set path = ##class(JVDoc.Schema).GetIdentifierPath(i%DocType)
    If path = "" Set path = ..#IDENTIFIERPATH
    If path = "" Quit ""
    Quit ..GetValueAt(path)
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
    Set obj = ..GetObj(.sc)
    If $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "Invalid JSON: "_$System.Status.GetErrorText(sc))
    Set flags = ..ParseSpec(pValidationSpec)
    If flags = "" Quit $$$OK
    If ..DocType = "" Quit $$$ERROR($$$GeneralError, "Cannot validate: DocType is empty")
    Set tree = ##class(JVDoc.Schema).GetTree(..DocType)
    If '$IsObject(tree) Quit $$$ERROR($$$GeneralError, "Cannot validate: unknown DocType "_..DocType)
    If $ClassName(obj) '= "%Library.DynamicObject" Quit $$$ERROR($$$GeneralError, "Root must be a JSON object")
    Set n = 0
    Do ..CheckObject(tree, obj, "", flags, .errs, .n)
    Do ..CheckComposition(tree, obj, "object", "", flags, .errs, .n)
    If n = 0 Quit $$$OK
    Set sc = $$$OK
    For i = 1:1:n {
        Set st = $$$ERROR($$$GeneralError, errs(i))
        Set sc = $Select(+sc:st, 1:$System.Status.AppendStatus(sc, st))
    }
    Quit sc
}

/// Validates JSON without saving anything.<br>
/// Example: Set sc = ##class(JVDoc.Document).ValidateJSON("{""order_id"":""A1"",""total"":""x""}", "Demo:Order", "all", .errs)<br>
///          Write $System.Status.IsOK(sc), !<br>
///          For i = 1:1:errs Write errs(i), !<br>
/// <var>pJSON</var>: a JSON string, stream, or %DynamicObject<br>
/// <var>pDocType</var>: the DocType "Cat:Name" to validate against<br>
/// <var>pSpec</var>: validation switches as in Validate; default "all"<br>
/// <var>pErrors</var> (output): number of errors; pErrors(i) is the text of the i-th error<br>
/// Returns: the status of Validate
ClassMethod ValidateJSON(pJSON, pDocType As %String, pSpec As %String = "all", Output pErrors) As %Status
{
    Kill pErrors
    Set pErrors = 0
    Set d = ##class(JVDoc.Document).%New(pJSON)
    Set d.DocType = pDocType
    Set sc = d.Validate(pSpec)
    If $$$ISERR(sc) {
        Do $System.Status.DecomposeStatus(sc, .errs)
        Set pErrors = +$Get(errs)
        For i = 1:1:pErrors Set pErrors(i) = errs(i)
    }
    Quit sc
}

/// Normalizes a validation spec: "all" expands to ALLFLAGS, "-x" removes x, duplicates and letters other than ALLFLAGS and u are dropped (so the product's d and m are ignored).<br>
/// <var>pSpec</var>: the spec, e.g. "all-p" or "rt"; case-insensitive<br>
/// Returns: the active switch letters, e.g. "rtebcaso"; "" when none
ClassMethod ParseSpec(pSpec As %String) As %String [ Private ]
{
    Set s = $ZConvert($ZStrip(pSpec, "<>W"), "L"), pos = "", neg = "", valid = ..#ALLFLAGS_"u"
    If s [ "all" Set s = $Replace(s, "all", ..#ALLFLAGS)
    Set i = 1
    While i <= $Length(s) {
        Set c = $Extract(s, i)
        If c = "-" {
            Set i = i + 1, c = $Extract(s, i)
            If (c '= "") && (valid [ c) Set neg = neg_c
        } ElseIf (c '= "") && (valid [ c) && (pos '[ c) {
            Set pos = pos_c
        }
        Set i = i + 1
    }
    Set out = ""
    For j = 1:1:$Length(pos) { If neg '[ $Extract(pos, j) Set out = out_$Extract(pos, j) }
    Quit out
}

/// Appends "path: message" to the error list, skipping texts already present (allOf members and the merged field tree can report the same violation); stops at 50 entries and adds a single "(more errors omitted)" line.<br>
/// <var>pErrs</var> (byref): error list, pErrs(i)=text<br>
/// <var>pN</var> (byref): number of entries in pErrs<br>
/// <var>pPath</var>: path of the offending value; "" is shown as (root)<br>
/// <var>pMsg</var>: error text
ClassMethod AddErr(ByRef pErrs, ByRef pN, pPath As %String, pMsg As %String) [ Private ]
{
    Set txt = $Select(pPath = "":"(root)", 1:pPath)_": "_pMsg
    For i = 1:1:pN { If $Get(pErrs(i)) = txt Quit }
    If (pN > 0) && ($Get(pErrs(i)) = txt) Quit
    If pN >= 50 {
        If pN = 50 Set pN = 51, pErrs(51) = "(more errors omitted)"
        Quit
    }
    Set pN = pN + 1
    Set pErrs(pN) = txt
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
    Kill known
    Set it = pNode.children.%GetIterator()
    While it.%GetNext(.k, .c) {
        Set name = c.name, known(name) = ""
        Set path = pPath_$Select(pPath = "":"", 1:".")_name
        Set t = pData.%GetTypeOf(name)
        If t = "unassigned" {
            If (pFlags [ "r") && ('+c.opt) Do ..AddErr(.pErrs, .pN, path, "required field is missing")
            Continue
        }
        // Fields declared only inside oneOf/anyOf alternatives are checked by the alternative itself
        If (t = "null") || c.%Get("fromAlt") Continue
        Set val = pData.%Get(name)
        If c.type = "array" {
            Do ..CheckArray(c, val, t, path, pFlags, .pErrs, .pN)
        } Else {
            Do ..CheckValue(c, val, t, path, pFlags, .pErrs, .pN)
        }
    }
    // minProperties / maxProperties: count all properties on the object
    If pFlags [ "b" {
        Set cnt = 0, itc = pData.%GetIterator()
        While itc.%GetNext() { Set cnt = cnt + 1 }
        If (pNode.%GetTypeOf("minProperties") = "number") && (cnt < pNode.%Get("minProperties")) Do ..AddErr(.pErrs, .pN, pPath, "property count "_cnt_" is less than minProperties "_pNode.%Get("minProperties"))
        If (pNode.%GetTypeOf("maxProperties") = "number") && (cnt > pNode.%Get("maxProperties")) Do ..AddErr(.pErrs, .pN, pPath, "property count "_cnt_" is more than maxProperties "_pNode.%Get("maxProperties"))
    }
    // dependentRequired: when the key is present (even null), the dependent fields must also be present
    If (pFlags [ "r") && $IsObject(pNode.%Get("dep")) {
        Set itd = pNode.dep.%GetIterator()
        While itd.%GetNext(.dk, .dnames) {
            If pData.%GetTypeOf(dk) = "unassigned" Continue
            Set itn = dnames.%GetIterator()
            While itn.%GetNext(.j, .dn) {
                If pData.%GetTypeOf(dn) = "unassigned" Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_dn, "required when '"_dk_"' is present")
            }
        }
    }
    // dependentSchemas: when the key is present (even null), the object must also satisfy the corresponding sub-schema (unknown fields not checked)
    If $IsObject(pNode.%Get("dsch")) {
        Set dflags = $Translate(pFlags, "u")
        Set itx = pNode.dsch.%GetIterator()
        While itx.%GetNext(.xk, .xe) {
            If pData.%GetTypeOf(xe.key) = "unassigned" Continue
            Do ..CheckObject(xe.node, pData, pPath, dflags, .pErrs, .pN)
        }
    }
    // propertyNames: every property name (including those outside the schema) is validated as a string against the sub-schema
    If (pFlags [ "s") && $IsObject(pNode.%Get("pnames")) {
        Set itp = pData.%GetIterator()
        While itp.%GetNext(.pk) {
            Kill e3
            Set n3 = 0
            Do ..CheckValue(pNode.pnames, pk, "string", "", pFlags, .e3, .n3)
            For i = 1:1:n3 {
                Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_pk, "property name is invalid: "_$Piece(e3(i), ": ", 2, *))
            }
        }
    }
    If pFlags [ "u" {
        Set it2 = pData.%GetIterator()
        While it2.%GetNext(.k2, .v2) {
            If '$Data(known(k2)) Do ..AddErr(.pErrs, .pN, pPath_$Select(pPath = "":"", 1:".")_k2, "unknown field")
        }
    }
    // additionalProperties: false rejects unknown fields (when u is also on, only u reports them); a schema validates each additional field's value against it
    Set at = pNode.%GetTypeOf("additional"), doAdd = 0
    If pFlags [ "a" {
        If at = "object" {
            Set doAdd = 1
        } ElseIf (at = "boolean") && ('pNode.%Get("additional")) && (pFlags '[ "u") {
            Set doAdd = 1
        }
    }
    If doAdd {
        Set it3 = pData.%GetIterator()
        While it3.%GetNext(.k3, .v3, .t3) {
            If $Data(known(k3)) Continue
            Set apath = pPath_$Select(pPath = "":"", 1:".")_k3
            If at = "boolean" {
                Do ..AddErr(.pErrs, .pN, apath, "additional property is not allowed")
            } ElseIf t3 '= "null" {
                If pNode.additional.type = "array" {
                    Do ..CheckArray(pNode.additional, v3, t3, apath, pFlags, .pErrs, .pN)
                } Else {
                    Do ..CheckValue(pNode.additional, v3, t3, apath, pFlags, .pErrs, .pN)
                }
            }
        }
    }
    // if/then/else: if is evaluated with full checks to decide which branch to take; then or else is checked with the user-supplied flags (unknown fields are not checked inside branches)
    If $IsObject(pNode.%Get("cond")) {
        Set bflags = $Translate(pFlags, "u")
        Set ci = pNode.cond.%GetIterator()
        While ci.%GetNext(.ck, .ce) {
            Kill e2
            Set n2 = 0
            Do ..CheckObject(ce.%Get("if"), pData, pPath, ..#ALLFLAGS, .e2, .n2)
            Set bn = ce.%Get($Select(n2 = 0:"then", 1:"else"))
            If $IsObject(bn) Do ..CheckObject(bn, pData, pPath, bflags, .pErrs, .pN)
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
    Set n = pVal.%Size()
    If pFlags [ "b" {
        If (pArr.%GetTypeOf("minItems") = "number") && (n < pArr.%Get("minItems")) Do ..AddErr(.pErrs, .pN, pPath, "array has "_n_" item(s), fewer than minItems "_pArr.%Get("minItems"))
        If (pArr.%GetTypeOf("maxItems") = "number") && (n > pArr.%Get("maxItems")) Do ..AddErr(.pErrs, .pN, pPath, "array has "_n_" item(s), more than maxItems "_pArr.%Get("maxItems"))
        If (pArr.%GetTypeOf("uniqueItems") = "boolean") && pArr.%Get("uniqueItems") Do ..CheckUnique(pVal, n, pPath, .pErrs, .pN)
    }
    If pFlags [ "c" Do ..CheckConst(pArr, pVal, pType, pPath, .pErrs, .pN)
    Do ..CheckComposition(pArr, pVal, pType, pPath, pFlags, .pErrs, .pN)
    If (pFlags [ "e") && $IsObject(pArr.%Get("enum")) Do ..CheckEnum(pArr, pVal, pType, pPath, .pErrs, .pN)
    If pFlags [ "s" Do ..CheckContains(pArr, pVal, n, pPath, .pErrs, .pN)
    Set items = pArr.items
    For i = 0:1:n-1 {
        Set et = pVal.%GetTypeOf(i)
        If et = "null" Continue
        Do ..CheckValue(items, pVal.%Get(i), et, pPath_"("_(i+1)_")", pFlags, .pErrs, .pN)
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
    Set st = pNode.type
    // Array nodes (the items of a nested array) get the full array treatment, including their own elements
    If st = "array" Do ..CheckArray(pNode, pVal, pType, pPath, pFlags, .pErrs, .pN) Quit
    If pFlags [ "t" {
        Set ok = $Case(st, "string":(pType = "string"), "number":(pType = "number"), "integer":((pType = "number") && (pVal = (pVal\1))), "boolean":(pType = "boolean"), "object":(pType = "object"), :1)
        If 'ok {
            Do ..AddErr(.pErrs, .pN, pPath, "expected "_st_", got "_pType)
            Quit
        }
    }
    If pFlags [ "c" Do ..CheckConst(pNode, pVal, pType, pPath, .pErrs, .pN)
    Do ..CheckComposition(pNode, pVal, pType, pPath, pFlags, .pErrs, .pN)
    If (pFlags [ "e") && $IsObject(pNode.%Get("enum")) Do ..CheckEnum(pNode, pVal, pType, pPath, .pErrs, .pN)
    If st = "object" {
        If (pType = "object") && $IsObject(pNode.%Get("children")) Do ..CheckObject(pNode, pVal, pPath, pFlags, .pErrs, .pN)
        Quit
    }
    If (pFlags [ "p") && ((st = "string") || (st = "any")) && (pType = "string") && (pNode.%Get("pattern") '= "") {
        Try {
            If '$Locate(pVal, pNode.pattern) Do ..AddErr(.pErrs, .pN, pPath, "value does not match pattern "_pNode.pattern)
        } Catch ex {
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
    Quit ..MatchErr(pNode, pVal, pType, pPath, .first)
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
    Kill e
    Set n = 0, pFirst = ""
    If pNode.type = "array" {
        Do ..CheckArray(pNode, pVal, pType, pPath, ..#ALLFLAGS, .e, .n)
    } Else {
        Do ..CheckValue(pNode, pVal, pType, pPath, ..#ALLFLAGS, .e, .n)
    }
    If n > 0 {
        Set full = e(1), pre = $Select(pPath = "":"(root)", 1:pPath)_": "
        If $Extract(full, 1, $Length(pre)) = pre Set full = $Extract(full, $Length(pre)+1, *)
        Set pFirst = full
    }
    Quit (n = 0)
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
    Set itg = pNode.alts.%GetIterator()
    While itg.%GetNext(.gk, .ge) {
        Set cnt = 0, why = "", i = 0
        Set ita = ge.list.%GetIterator()
        While ita.%GetNext(.ak, .alt) {
            Set i = i + 1
            If ..MatchErr(alt, pVal, pType, pPath, .first) {
                Set cnt = cnt + 1
            } ElseIf i <= 5 {
                Set why = why_$Select(why = "":"", 1:"; ")_i_": "_$Extract(first, 1, 80)
            }
        }
        If cnt = 0 {
            Do ..AddErr(.pErrs, .pN, pPath, "value does not match any alternative of "_ge.kw_" ["_why_"]")
        } ElseIf (ge.kw = "oneOf") && (cnt > 1) {
            Do ..AddErr(.pErrs, .pN, pPath, "value matches "_cnt_" alternatives of oneOf, exactly one is allowed")
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
    Set mflags = $Translate(pFlags, "u")
    Set itm = pNode.alls.%GetIterator()
    While itm.%GetNext(.mk, .mem) {
        If mem.type = "array" {
            Do ..CheckArray(mem, pVal, pType, pPath, mflags, .pErrs, .pN)
        } Else {
            Do ..CheckValue(mem, pVal, pType, pPath, mflags, .pErrs, .pN)
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
    Set it = pNode.nots.%GetIterator()
    While it.%GetNext(.k, .sub) {
        If ..Matches(sub, pVal, pType, pPath) Do ..AddErr(.pErrs, .pN, pPath, "value must not match the schema in not")
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
    Set cn = pArr.%Get("contains")
    If '$IsObject(cn) Quit
    Set hasMin = (pArr.%GetTypeOf("minContains") = "number")
    Set minC = $Select(hasMin:pArr.%Get("minContains"), 1:1)
    Set hasMax = (pArr.%GetTypeOf("maxContains") = "number")
    Set maxC = $Select(hasMax:pArr.%Get("maxContains"), 1:0)
    Set cnt = 0
    For i = 0:1:pLen-1 {
        Set et = pVal.%GetTypeOf(i)
        If et = "null" Continue
        If ..Matches(cn, pVal.%Get(i), et, pPath_"("_(i+1)_")") Set cnt = cnt + 1
        If 'hasMax && (cnt >= minC) Quit
    }
    If cnt < minC Do ..AddErr(.pErrs, .pN, pPath, $Select(hasMin:cnt_" item(s) match contains, fewer than minContains "_minC, 1:"no item matches contains"))
    If hasMax && (cnt > maxC) Do ..AddErr(.pErrs, .pN, pPath, cnt_" item(s) match contains, more than maxContains "_maxC)
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
    Set found = 0, it = pNode.enum.%GetIterator()
    While it.%GetNext(.k, .ev, .et) {
        If ..JSONEquals(pVal, pType, ev, et) { Set found = 1  Quit }
    }
    If 'found Do ..AddErr(.pErrs, .pN, pPath, "value "_..ValText(pVal, pType)_" is not in the allowed list")
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
    Set ct = pNode.%GetTypeOf("const")
    If ct = "unassigned" Quit
    If '..JSONEquals(pVal, pType, pNode.%Get("const"), ct) Do ..AddErr(.pErrs, .pN, pPath, "value does not equal const "_##class(JVDoc.SchemaImport).ConstText(pNode))
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
        Set mn = pNode.%GetTypeOf("minimum"), emn = pNode.%GetTypeOf("exclusiveMinimum")
        If mn = "number" {
            If (emn = "boolean") && pNode.%Get("exclusiveMinimum") {
                If pVal <= pNode.%Get("minimum") Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be greater than minimum "_pNode.%Get("minimum")_" (exclusive)")
            } ElseIf pVal < pNode.%Get("minimum") {
                Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is less than minimum "_pNode.%Get("minimum"))
            }
        }
        If (emn = "number") && (pVal <= pNode.%Get("exclusiveMinimum")) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be greater than exclusiveMinimum "_pNode.%Get("exclusiveMinimum"))
        Set mx = pNode.%GetTypeOf("maximum"), emx = pNode.%GetTypeOf("exclusiveMaximum")
        If mx = "number" {
            If (emx = "boolean") && pNode.%Get("exclusiveMaximum") {
                If pVal >= pNode.%Get("maximum") Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be less than maximum "_pNode.%Get("maximum")_" (exclusive)")
            } ElseIf pVal > pNode.%Get("maximum") {
                Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is greater than maximum "_pNode.%Get("maximum"))
            }
        }
        If (emx = "number") && (pVal >= pNode.%Get("exclusiveMaximum")) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" must be less than exclusiveMaximum "_pNode.%Get("exclusiveMaximum"))
        // multipleOf: the quotient is treated as a multiple when it is within 1E-9 of an integer, tolerating floating-point rounding
        Set mo = pNode.%Get("multipleOf")
        If (pNode.%GetTypeOf("multipleOf") = "number") && (mo > 0) {
            Set q = pVal / mo
            If q < 0 Set q = -q
            Set r = q - (q\1)
            If (r > 1E-9) && (r < (1 - 1E-9)) Do ..AddErr(.pErrs, .pN, pPath, "value "_pVal_" is not a multiple of "_mo)
        }
    } ElseIf pType = "string" {
        Set len = $Length(pVal)
        If (pNode.%GetTypeOf("minLength") = "number") && (len < pNode.%Get("minLength")) Do ..AddErr(.pErrs, .pN, pPath, "length "_len_" is shorter than minLength "_pNode.%Get("minLength"))
        If (pNode.%GetTypeOf("maxLength") = "number") && (len > pNode.%Get("maxLength")) Do ..AddErr(.pErrs, .pN, pPath, "length "_len_" is longer than maxLength "_pNode.%Get("maxLength"))
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
    Kill seen
    Set cx = 0
    For i = 0:1:pLen-1 {
        Set t = pVal.%GetTypeOf(i), v = pVal.%Get(i)
        If (t = "object") || (t = "array") {
            Set cx = cx + 1
            If cx > 1000 Continue
            Set key = t_"|"
        } ElseIf t = "null" {
            Set key = "null|"
        } ElseIf t = "number" {
            Set key = "number|"_(+v)
        } Else {
            Set key = t_"|"_$Extract(v, 1, 200)
        }
        Set dup = "", j = ""
        For {
            Set j = $Order(seen(key, j))
            If j = "" Quit
            If ..JSONEquals(v, t, pVal.%Get(j), pVal.%GetTypeOf(j)) { Set dup = j  Quit }
        }
        If dup '= "" {
            Do ..AddErr(.pErrs, .pN, pPath_"("_(i+1)_")", "duplicates item "_(dup+1)_" (uniqueItems)")
        } Else {
            Set seen(key, i) = ""
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
        Set n = pA.%Size()
        If n '= pB.%Size() Quit 0
        Set ok = 1
        For i = 0:1:n-1 {
            If '..JSONEquals(pA.%Get(i), pA.%GetTypeOf(i), pB.%Get(i), pB.%GetTypeOf(i)) { Set ok = 0  Quit }
        }
        Quit ok
    }
    If pTA = "object" {
        Set ok = 1, na = 0, nb = 0
        Set it = pA.%GetIterator()
        While it.%GetNext(.k, .v, .t) {
            Set na = na + 1
            Set tb = pB.%GetTypeOf(k)
            If (tb = "unassigned") || '..JSONEquals(v, t, pB.%Get(k), tb) { Set ok = 0  Quit }
        }
        If 'ok Quit 0
        Set it = pB.%GetIterator()
        While it.%GetNext(.k2) { Set nb = nb + 1 }
        Quit (na = nb)
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
    Set st = ##class(JVDoc.Schema).GetSearchTable(..DocType)
    If st = "" Set st = ..#SEARCHTABLE
    Quit st
}

/// Rebuilds the search table rows of this document by calling IndexDoc on its search table class; does nothing for an unsaved document or one without a search table.<br>
/// <var>pClearFirst</var>: 1 (default) deletes the existing rows for the DocId first to avoid duplicates and stale values; 0 when there cannot be any (new document, table just emptied)<br>
/// Returns: error from the cleanup or from IndexDoc
Method IndexNow(pClearFirst As %Boolean = 1) As %Status
{
    Set st = ..SearchTableClass()
    If st = "" Quit $$$OK
    Set id = ..%Id()
    If id = "" Quit $$$OK
    If pClearFirst {
        Set sc = ..ClearIndexRows(st)
        If $$$ISERR(sc) Quit sc
    }
    Quit $classmethod(st, "IndexDoc", $this)
}

/// Deletes this document's rows from a search table.<br>
/// <var>pSearchTable</var>: the search table class name<br>
/// Returns: error with the SQLCODE when the DELETE fails
Method ClearIndexRows(pSearchTable As %String) As %Status [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_..SqlTableOf(pSearchTable)_" WHERE DocId = ?", ..%Id())
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "Search table cleanup failed, SQLCODE="_rs.%SQLCODE_" "_rs.%Message)
    Quit $$$OK
}

/// Returns the SQL name of a compiled class from the class dictionary, honoring SqlSchemaName and SqlTableName overrides.<br>
/// <var>pClass</var>: class name<br>
/// Returns: "schema.table", or "" when the class does not exist
ClassMethod SqlTableOf(pClass As %String) As %String [ Private ]
{
    Set c = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
    If '$IsObject(c) Quit ""
    Quit c.SqlSchemaName_"."_c.SqlTableName
}

/// Rebuilds one search table from scratch: deletes all its rows, then re-indexes every stored document whose search table is that class.<br>
/// <var>pSearchTable</var>: the search table class name<br>
/// <var>pCount</var> (output): number of documents indexed<br>
/// Returns: error when the class is missing or the cleanup fails; documents that fail to index are skipped and their errors combined in the status
ClassMethod Reindex(pSearchTable As %String, Output pCount As %Integer) As %Status
{
    Set pCount = 0
    If pSearchTable = "" Quit $$$ERROR($$$GeneralError, "Search table class is required")
    Set tbl = ..SqlTableOf(pSearchTable)
    If tbl = "" Quit $$$ERROR($$$GeneralError, "Class not found: "_pSearchTable)
    Set rs0 = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_tbl)
    If rs0.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "Cleanup failed, SQLCODE="_rs0.%SQLCODE)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM JVDoc.Document")
    Set sc = $$$OK
    While rs.%Next() {
        Set d = ..%OpenId(rs.%Get("ID"))
        If '$IsObject(d) || (d.SearchTableClass() '= pSearchTable) Continue
        Set isc = d.IndexNow(0)
        If $$$ISERR(isc) {
            Set st = $$$ERROR($$$GeneralError, "Document "_d.%Id()_": "_$System.Status.GetErrorText(isc))
            Set sc = $Select(+sc:st, 1:$System.Status.AppendStatus(sc, st))
            Continue
        }
        Set pCount = pCount + 1
    }
    Quit sc
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
    Set p = $Find(pPath, "()")
    If 'p {
        Set val = ..Locate(pPath, .type, .cnt, .sc)
        If $$$ISERR(sc) || (type = "object") || (type = "array") || (type = "null") || (val = "") Quit $$$OK
        Set val = $Extract(val, 1, ..#SEARCHVALUEMAXLEN)
        Set pArray(val) = $Get(pArray(val)) + 1
        Quit $$$OK
    }
    Set head = $Extract(pPath, 1, p-3), tail = $Extract(pPath, p, *)
    Set idx = ""
    For {
        Set idx = ..GetNextIndex(head_"()", idx, .nsc)
        If $$$ISERR(nsc) || (idx = "") Quit
        Do ..CollectValues(head_"("_idx_")"_tail, .pArray)
    }
    Quit $$$OK
}

// ---------------- Persistence callbacks ----------------

/// Decides whether the search table rows must be rebuilt after this save (new document, changed content or changed DocType), then serializes a modified Obj back to Raw.<br>
/// <var>pInsert</var>: 1 when the document is saved for the first time<br>
/// Returns: $$$OK
Method %OnBeforeSave(pInsert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    Set ..NeedsIndex = pInsert || ..Dirty || (..DocType '= ..IndexedDocType)
    If ..Dirty && $IsObject(..Obj) {
        Do ..Raw.Clear()
        Do ..Obj.%ToJSON(..Raw)
        Set ..Dirty = 0
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
        Set sc = $$$OK
        If 'pInsert && (..IndexedDocType '= "") && (..IndexedDocType '= ..DocType) {
            Set oldSt = ##class(JVDoc.Schema).GetSearchTable(..IndexedDocType)
            If oldSt = "" Set oldSt = ..#SEARCHTABLE
            If (oldSt '= "") && (oldSt '= ..SearchTableClass()) Set sc = ..ClearIndexRows(oldSt)
        }
        If $$$ISOK(sc) Set sc = ..IndexNow('pInsert)
        If $$$ISERR(sc) {
            Do ##class(Ens.Util.Log).LogStatus($classname(), "%OnAfterSave", sc)
        } Else {
            Set ..IndexedDocType = ..DocType
        }
    }
    Catch ex {
        Do ##class(Ens.Util.Log).LogStatus($classname(), "%OnAfterSave", ex.AsStatus())
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
    Set obj = ..GetObj(.sc)
    If $$$ISERR(sc) || '$IsObject(obj) {
        Do ..Raw.Rewind()
        Do ..Raw.OutputToDevice()
        Quit
    }
    Do ..OutputFormattedJSON(obj)
}

/// Builds the HTML view of the document: the DocType and the JSON indented inside a pre element; the raw text is shown when the JSON does not parse.<br>
/// Returns: the HTML fragment, truncated after 200000 characters of content with a "(content truncated)" note
Method ContentsHTML() As %String
{
    Set max = 200000
    Set obj = ..GetObj(.sc)
    If $$$ISERR(sc) || '$IsObject(obj) {
        Do ..Raw.Rewind()
        Set txt = ..Raw.Read(max)
    } Else {
        Set fmt = ##class(%JSON.Formatter).%New()
        Set fmt.Indent = 1, fmt.IndentChars = "  ", fmt.LineTerminator = $Char(10)
        Set fsc = fmt.FormatToString(..ToJSONString(obj), .txt)
        If $$$ISERR(fsc) Set txt = ..ToJSONString(obj)
    }
    Set more = ($Length(txt) > max)
    If more Set txt = $Extract(txt, 1, max)
    Set txt = $Translate(txt, $Char(13))
    Set out = "<div>"_$Char(10)
    Set out = out_"<div><b>DocType:</b> "_$ZConvert(..DocType, "O", "HTML")_"</div>"_$Char(10)
    Set out = out_"<pre style=""font-family:monospace; white-space:pre; overflow:auto;"">"_$ZConvert(txt, "O", "HTML")_"</pre>"_$Char(10)
    If more Set out = out_"<div><i>(content truncated)</i></div>"_$Char(10)
    Quit out_"</div>"_$Char(10)
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
