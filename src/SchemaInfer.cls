/// Generator of JSON Schema from JSON examples
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.SchemaInfer
{

/// Maximum number of array elements inspected during inference
Parameter MAXARRAYITEMS = 1000;

// ---------------- Entry points ----------------

/// Infers a DocType from one sample and saves it as pCategory:pName.<br>
/// <var>pCategory</var>: first part of the DocType ("Demo" in "Demo:Order")<br>
/// <var>pName</var>: second part of the DocType ("Order" in "Demo:Order")<br>
/// <var>pSample</var>: one JSON object as a string, stream or %DynamicObject<br>
/// <var>pMaxDepth</var>: object nesting depth after which the tree is truncated (with a warning)<br>
/// <var>pRequired</var>: 0 (default) makes every field optional; 1 marks every field present in the sample as required<br>
/// Returns: $$$OK, or an error when the sample does not parse or its root is not an object
ClassMethod FromSample(pCategory As %String, pName As %String, pSample, pMaxDepth As %Integer = 12, pRequired As %Boolean = 0) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tArr = []
        Do tArr.%Push(##class(%DynamicAbstractObject).%FromJSON(pSample))
        Set tSC = ..FromSamples(pCategory, pName, tArr, pMaxDepth, pRequired)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Infers a DocType from several samples and saves it as pCategory:pName. The samples' field trees are merged
/// (fields unioned, scalar types decided by majority, kind conflicts typed as any).
/// Clears the warning log (^||JVDoc.Warn) first, so Report() afterwards shows only this run.<br>
/// <var>pCategory</var>: first part of the DocType ("Demo" in "Demo:Order")<br>
/// <var>pName</var>: second part of the DocType ("Order" in "Demo:Order")<br>
/// <var>pSamples</var>: %DynamicArray whose elements must all be JSON objects<br>
/// <var>pMaxDepth</var>: object nesting depth after which the tree is truncated (with a warning)<br>
/// <var>pRequired</var>: 0 (default) makes every field optional; 1 marks a field required only when it appears in every sample<br>
/// Returns: $$$OK, or an error when the array is empty, an element is not an object, or saving fails
ClassMethod FromSamples(pCategory As %String, pName As %String, pSamples As %DynamicArray, pMaxDepth As %Integer = 12, pRequired As %Boolean = 0) As %Status
{
    Kill ^||JVDoc.Warn
    Set tSC = $$$OK
    Try {
        Set tAcc = ""
        Set tIt = pSamples.%GetIterator()
        While tIt.%GetNext(.tI, .tS, .tT) {
            If tT '= "object" Throw ##class(%Exception.General).%New("Sample", 5001, , "sample #"_(tI+1)_" is not a JSON object")
            Set tNode = ..Infer("", tS, tT, 0, pMaxDepth, "")
            If tAcc = "" { Set tAcc = tNode } Else { Do ..Merge(tAcc, tNode, "") }
        }
        If tAcc = "" Throw ##class(%Exception.General).%New("Sample", 5001, , "no samples given")
        Do ..Finalize(tAcc, "", pRequired)
        Set tSC = ##class(JVDoc.Schema).Save(pCategory, pName, tAcc)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Reads a UTF-8 file and infers a DocType from it. A file that holds an array without pMulti=1 is an error rather than a wrong schema.<br>
/// <var>pCategory</var>: first part of the DocType ("Demo" in "Demo:Order")<br>
/// <var>pName</var>: second part of the DocType ("Order" in "Demo:Order")<br>
/// <var>pFile</var>: path of the file on the server<br>
/// <var>pMulti</var>: 0 (default) expects one JSON object; 1 also accepts a JSON array whose elements are the samples<br>
/// <var>pMaxDepth</var>: object nesting depth after which the tree is truncated (with a warning)<br>
/// <var>pRequired</var>: as in FromSamples; 1 marks fields present in every sample as required<br>
/// Returns: $$$OK, or an error when the file is missing or empty, does not parse, or holds an array without pMulti=1
ClassMethod FromSampleFile(pCategory As %String, pName As %String, pFile As %String, pMulti As %Boolean = 0, pMaxDepth As %Integer = 12, pRequired As %Boolean = 0) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tS = ##class(%Stream.FileCharacter).%New()
        Set tS.TranslateTable = "UTF8"
        Set tSC = tS.LinkToFile(pFile)
        If $$$ISERR(tSC) Quit
        If tS.Size = 0 {
            Set tSC = $$$ERROR($$$GeneralError, "File is empty or not readable: "_pFile)
            Quit
        }
        Set tData = ##class(%DynamicAbstractObject).%FromJSON(tS)
        If $ClassName(tData) = "%Library.DynamicArray" {
            If 'pMulti Throw ##class(%Exception.General).%New("Sample", 5001, , "file holds a JSON array; pass pMulti=1 to treat each element as one sample")
            Set tArr = tData
        } Else {
            Set tArr = []
            Do tArr.%Push(tData)
        }
        Set tSC = ..FromSamples(pCategory, pName, tArr, pMaxDepth, pRequired)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Infers a DocType from JVDoc.Document messages already stored in this namespace; only structure is recorded, never field values.
/// Documents that do not parse or whose root is not an object are skipped and counted in the final info message.<br>
/// <var>pCategory</var>: first part of the DocType to create<br>
/// <var>pName</var>: second part of the DocType to create<br>
/// <var>pFilterDocType</var>: read only documents with this DocType; "" (default) reads all<br>
/// <var>pMaxDocs</var>: number of newest documents (ID descending) to read; default 200<br>
/// <var>pMaxDepth</var>: object nesting depth after which the tree is truncated (with a warning)<br>
/// <var>pRequired</var>: as in FromSamples; 1 marks fields present in every document as required<br>
/// Returns: $$$OK, or an error when the query fails or no usable document was found
ClassMethod FromStoredDocs(pCategory As %String, pName As %String, pFilterDocType As %String = "", pMaxDocs As %Integer = 200, pMaxDepth As %Integer = 12, pRequired As %Boolean = 0) As %Status
{
    Kill ^||JVDoc.Warn
    Set tSC = $$$OK
    Try {
        Set tSql = "SELECT TOP "_(+pMaxDocs)_" ID FROM JVDoc.Document"
        If pFilterDocType '= "" Set tSql = tSql_" WHERE DocType = ?"
        Set tSql = tSql_" ORDER BY ID DESC"
        Set tSt = ##class(%SQL.Statement).%New()
        Set tSC = tSt.%Prepare(tSql)
        If $$$ISERR(tSC) Quit
        If pFilterDocType '= "" { Set tRs = tSt.%Execute(pFilterDocType) } Else { Set tRs = tSt.%Execute() }
        If tRs.%SQLCODE < 0 {
            Set tSC = $$$ERROR($$$GeneralError, "Query failed: "_tRs.%Message)
            Quit
        }
        Set tAcc = "", tUsed = 0, tSkipped = 0
        While tRs.%Next() {
            Set tD = ##class(JVDoc.Document).%OpenId(tRs.%Get("ID"))
            If '$IsObject(tD) { Set tSkipped = tSkipped + 1  Continue }
            Set tObj = tD.GetObj(.tGsc)
            If $$$ISERR(tGsc) || '$IsObject(tObj) || ($ClassName(tObj) '= "%Library.DynamicObject") {
                Set tSkipped = tSkipped + 1
                Continue
            }
            Set tNode = ..Infer("", tObj, "object", 0, pMaxDepth, "")
            If tAcc = "" { Set tAcc = tNode } Else { Do ..Merge(tAcc, tNode, "") }
            Set tUsed = tUsed + 1
        }
        If tUsed = 0 {
            Set tSC = $$$ERROR($$$GeneralError, "No usable stored documents found")
            Quit
        }
        Do ..Finalize(tAcc, "", pRequired)
        Do ##class(JVDoc.SchemaImport).Warn("info: inferred from "_tUsed_" stored document(s), skipped "_tSkipped)
        Set tSC = ##class(JVDoc.Schema).Save(pCategory, pName, tAcc)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

// ---------------- Inference ----------------

/// Builds the raw field-tree node for one JSON value. Objects get children (each stamped _seen=1) and _n=1 (number of samples seen),
/// and are cut off with truncated=1 at pMax depth; arrays get an items node merged from at most MAXARRAYITEMS elements, "" typed when empty;
/// scalars get the type string/integer/number/boolean plus a vote counter _tc, and null gets type "" (unknown).
/// Property names that cannot appear in a path are skipped with a warning.<br>
/// <var>pName</var>: property name of the value; "" for the root and for array elements<br>
/// <var>pVal</var>: the JSON value (a dynamic object/array, or a scalar)<br>
/// <var>pType</var>: its %GetTypeOf type: "object", "array", "string", "number", "boolean" or "null"<br>
/// <var>pDepth</var>: current nesting depth; 0 at the root<br>
/// <var>pMax</var>: depth at which objects are truncated<br>
/// <var>pPath</var>: normalized path of the value, used in warnings<br>
/// Returns: the raw node
ClassMethod Infer(pName, pVal, pType As %String, pDepth As %Integer, pMax As %Integer, pPath As %String) As %DynamicObject [ Private ]
{
    If pType = "object" {
        Set tNode = {"name":(pName), "type":"object", "children":[], "_n":1}
        If pDepth >= pMax {
            Do ##class(JVDoc.SchemaImport).Warn("truncated at depth "_pDepth_" under '"_pPath_"'")
            Do tNode.%Set("truncated", 1, "boolean")
            Quit tNode
        }
        Set tIt = pVal.%GetIterator()
        While tIt.%GetNext(.tK, .tV, .tT) {
            If ##class(JVDoc.SchemaImport).BadName(tK) {
                Do ##class(JVDoc.SchemaImport).Warn("skip property '"_tK_"' under '"_$Select(pPath = "":"(root)", 1:pPath)_"' (name not usable in a VDoc path)")
                Continue
            }
            Set tC = ..Infer(tK, tV, tT, pDepth+1, pMax, pPath_$Select(pPath = "":"", 1:".")_tK)
            Do tC.%Set("_seen", 1)
            Do tNode.children.%Push(tC)
        }
        Quit tNode
    }
    If pType = "array" {
        Set tNode = {"name":(pName), "type":"array"}
        Set tItems = ""
        Set tIt = pVal.%GetIterator()
        While tIt.%GetNext(.tK, .tV, .tT) {
            If tK >= ..#MAXARRAYITEMS {
                Do ##class(JVDoc.SchemaImport).Warn("array '"_pPath_"' has more than "_..#MAXARRAYITEMS_" items; only the first ones were inspected")
                Quit
            }
            Set tE = ..Infer("", tV, tT, pDepth+1, pMax, pPath_"()")
            If tItems = "" { Set tItems = tE } Else { Do ..Merge(tItems, tE, pPath_"()") }
        }
        If tItems = "" Set tItems = {"name":"", "type":""}
        Do tNode.%Set("items", tItems)
        Quit tNode
    }

    Set tSt = $Case(pType, "boolean":"boolean", "null":"", "number":$Select(pVal = (pVal\1):"integer", 1:"number"), :"string")
    Set tNode = {"name":(pName), "type":(tSt)}
    If tSt '= "" {
        Set tTc = {}
        Do tTc.%Set(tSt, 1, "number")
        Do tNode.%Set("_tc", tTc)
    }
    Quit tNode
}

/// Merges raw node pB into pA in place and returns pA. An untyped pA adopts pB; an untyped pB changes nothing; two scalars add their
/// _tc vote counters; a kind mismatch (object vs array vs scalar, or any on either side) makes pA any with a warning; two objects add _n,
/// union their children and add the _seen counts of common ones; two arrays merge their items nodes.<br>
/// <var>pA</var>: accumulated raw node, modified in place<br>
/// <var>pB</var>: raw node from the next sample; its children may be moved into pA<br>
/// <var>pPath</var>: normalized path of the node, used in warnings<br>
/// Returns: pA
ClassMethod Merge(pA As %DynamicObject, pB As %DynamicObject, pPath As %String) As %DynamicObject [ Private ]
{
    Set tTa = pA.type, tTb = pB.type
    If tTa = "" Quit ..Adopt(pA, pB)
    If tTb = "" Quit pA
    If ..IsScalar(tTa) && ..IsScalar(tTb) {
        // Both sides are scalars: accumulate type counts; the winning type is decided by majority in Finalize
        Set tCa = pA.%Get("_tc"), tCb = pB.%Get("_tc")
        Set tIt = tCb.%GetIterator()
        While tIt.%GetNext(.tK, .tV) { Do tCa.%Set(tK, +tCa.%Get(tK) + tV, "number") }
        Quit pA
    }
    If tTa = "any" Quit pA
    If (tTb = "any") || (tTa '= tTb) {
        // Kind mismatch between object, array, and scalar; the node becomes any
        Do ##class(JVDoc.SchemaImport).Warn("mixed kinds at '"_pPath_"': "_tTa_" vs "_tTb_"; typed as any")
        Quit ..MakeAny(pA)
    }
    If tTa = "object" {
        Do pA.%Set("_n", pA.%Get("_n") + pB.%Get("_n"))
        Set tIt = pB.children.%GetIterator()
        While tIt.%GetNext(.tK, .tBc) {
            Set tAc = ..FindChild(pA.children, tBc.name)
            If tAc = "" {
                Do pA.children.%Push(tBc)
            } Else {
                Set tSeen = tAc.%Get("_seen") + tBc.%Get("_seen")
                Do ..Merge(tAc, tBc, pPath_$Select(pPath = "":"", 1:".")_tBc.name)
                Do tAc.%Set("_seen", tSeen)
            }
        }
    } ElseIf tTa = "array" {
        Do ..Merge(pA.items, pB.items, pPath_"()")
    }
    Quit pA
}

/// Copies every key of pB except name and _seen into pA (type, children, items, _n, _tc, truncated), preserving JSON types;
/// used when pA has no type yet (only null or empty arrays were seen) so that pB supplies the structure.<br>
/// <var>pA</var>: untyped raw node, modified in place; keeps its name and _seen<br>
/// <var>pB</var>: raw node that supplies the structure<br>
/// Returns: pA
ClassMethod Adopt(pA As %DynamicObject, pB As %DynamicObject) As %DynamicObject [ Private ]
{
    Set tIt = pB.%GetIterator()
    While tIt.%GetNext(.tK, .tV, .tT) {
        If (tK = "name") || (tK = "_seen") Continue
        If $IsObject(tV) { Do pA.%Set(tK, tV) } Else { Do pA.%Set(tK, tV, tT) }
    }
    Quit pA
}

/// Turns a node into type any and removes the structure that no longer applies (children, items, _n, _tc, truncated).<br>
/// <var>pNode</var>: raw node, modified in place<br>
/// Returns: pNode
ClassMethod MakeAny(pNode As %DynamicObject) As %DynamicObject [ Private ]
{
    Do pNode.%Set("type", "any")
    For tK = "children", "items", "_n", "_tc", "truncated" { Do pNode.%Remove(tK) }
    Quit pNode
}

/// Finds a child node by name.<br>
/// <var>pChildren</var>: children array of an object node<br>
/// <var>pName</var>: property name to look for<br>
/// Returns: the child node, or "" when there is none
ClassMethod FindChild(pChildren As %DynamicArray, pName As %String) [ Private ]
{
    Set tFound = ""
    Set tIt = pChildren.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        If tC.name = pName { Set tFound = tC  Quit }
    }
    Quit tFound
}

/// Tests whether a field-tree type is a scalar type.<br>
/// <var>pType</var>: a field-tree type string<br>
/// Returns: 1 for string, integer, number or boolean; 0 otherwise (object, array, any, "")
ClassMethod IsScalar(pType As %String) As %Boolean [ Private ]
{
    Quit (pType = "string") || (pType = "integer") || (pType = "number") || (pType = "boolean")
}

/// Converts a merged raw tree into the stored field tree, recursively. An untyped node becomes string with a warning; a scalar's _tc votes
/// decide its type (integer and number count together and give number if any decimal was seen; ties keep the current type; disagreement
/// is reported); a child is marked opt unless pRequired=1 and its _seen equals the parent's _n; _tc, _n and _seen are removed.
/// Warns about nested arrays, which the DTL tree does not expand.<br>
/// <var>pNode</var>: merged raw node, converted in place<br>
/// <var>pPath</var>: normalized path of the node, used in warnings; "" for the root<br>
/// <var>pRequired</var>: 1 marks children seen in every sample as required; 0 makes all children optional
ClassMethod Finalize(pNode As %DynamicObject, pPath As %String, pRequired As %Boolean) [ Private ]
{
    If pNode.type = "" {
        Do pNode.%Set("type", "string")
        Do ##class(JVDoc.SchemaImport).Warn("no value seen to infer a type at '"_$Select(pPath = "":"(root)", 1:pPath)_"' (null or empty array); assumed string")
    }

    Set tTc = pNode.%Get("_tc")
    If $IsObject(tTc) {
        Set tCnt("string") = +tTc.%Get("string"), tCnt("boolean") = +tTc.%Get("boolean"), tCnt("num") = +tTc.%Get("integer") + tTc.%Get("number")
        Set tBest = $Case(pNode.type, "integer":"num", "number":"num", :pNode.type)
        Set tK = ""
        For {
            Set tK = $Order(tCnt(tK))
            If tK = "" Quit
            If tCnt(tK) > tCnt(tBest) Set tBest = tK
        }
        Set tKinds = 0, tDesc = "", tK = ""
        For {
            Set tK = $Order(tCnt(tK))
            If tK = "" Quit
            If tCnt(tK) > 0 {
                Set tKinds = tKinds + 1
                Set tDesc = tDesc_$Select(tDesc = "":"", 1:", ")_$Select(tK = "num":"numeric", 1:tK)_"("_tCnt(tK)_")"
            }
        }
        If tKinds > 1 Do ##class(JVDoc.SchemaImport).Warn("mixed types at '"_$Select(pPath = "":"(root)", 1:pPath)_"': "_tDesc_"; chose "_$Select(tBest = "num":"numeric", 1:tBest))
        Do pNode.%Set("type", $Select(tBest = "num":$Select(+tTc.%Get("number") > 0:"number", 1:"integer"), 1:tBest))
        Do pNode.%Remove("_tc")
    }

    If pNode.type = "object" {
        Set tN = pNode.%Get("_n")
        Do pNode.%Remove("_n")
        Set tIt = pNode.children.%GetIterator()
        While tIt.%GetNext(.tK, .tC) {
            If 'pRequired || (tC.%Get("_seen") < tN) Do tC.%Set("opt", 1, "boolean")
            Do tC.%Remove("_seen")
            Do ..Finalize(tC, pPath_$Select(pPath = "":"", 1:".")_tC.name, pRequired)
        }
    } ElseIf pNode.type = "array" {
        Do ..Finalize(pNode.items, pPath_"()", pRequired)
        If pNode.items.type = "array" Do ##class(JVDoc.SchemaImport).Warn("nested array at '"_pPath_"': not expanded in the DTL tree, copied as JSON text")
    }
}

// ---------------- Export as JSON Schema ----------------

/// Exports the stored field tree as a JSON Schema 2020-12 document (the draft that defines every keyword the field tree can hold).<br>
/// <var>pDocType</var>: the DocType "Cat:Name"<br>
/// Returns: the JSON Schema as a %DynamicObject with $schema set, or "" for an unknown DocType
ClassMethod ToJSONSchema(pDocType As %String)
{
    Set tTree = ##class(JVDoc.Schema).GetTree(pDocType)
    If '$IsObject(tTree) Quit ""
    Set tOut = ..SchemaOf(tTree)
    Do tOut.%Set("$schema", "https://json-schema.org/draft/2020-12/schema")
    Quit tOut
}

/// Converts one field-tree node (and its subtree) back into a JSON Schema object: type (omitted for any), description, enum, pattern and the
/// constraint keys; boolean exclusive bounds in numeric form; not, oneOf/anyOf, properties/required, dependentRequired, additionalProperties,
/// dependentSchemas, propertyNames, items and contains. Children marked fromAlt are left to their alternative. Whatever cannot sit on the node
/// itself (further not entries, a second group of the same oneOf/anyOf keyword, allOf members, duplicate dependentSchemas keys, if/then/else) goes into allOf.<br>
/// <var>pNode</var>: a field-tree node; not modified<br>
/// Returns: a new %DynamicObject holding the JSON Schema for the node
ClassMethod SchemaOf(pNode As %DynamicObject) As %DynamicObject [ Private ]
{
    If pNode.type = "any" { Set tS = {} } Else { Set tS = {"type":(pNode.type)} }
    If pNode.desc '= "" Do tS.%Set("description", pNode.desc)
    If $IsObject(pNode.%Get("enum")) Do tS.%Set("enum", pNode.enum)
    If pNode.%Get("pattern") '= "" Do tS.%Set("pattern", pNode.pattern)
    Set tKl = ##class(JVDoc.SchemaImport).ConstraintKeys()
    For tI = 1:1:$ListLength(tKl) { Do ##class(JVDoc.SchemaImport).CopyTyped(pNode, tS, $List(tKl, tI)) }
    // A draft-04 boolean exclusiveMinimum/exclusiveMaximum is written in the numeric form 2020-12 requires
    For tBk = "Minimum", "Maximum" {
        Set tEk = "exclusive"_tBk, tMk = $ZConvert(tBk, "L")
        If tS.%GetTypeOf(tEk) = "boolean" {
            If tS.%Get(tEk) && (tS.%GetTypeOf(tMk) = "number") {
                Do tS.%Set(tEk, tS.%Get(tMk), "number")
                Do tS.%Remove(tMk)
            } Else {
                Do tS.%Remove(tEk)
            }
        }
    }
    Set tExtra = []
    If $IsObject(pNode.%Get("nots")) && pNode.nots.%Size() {
        If pNode.nots.%Size() = 1 {
            Do tS.%Set("not", ..SchemaOf(pNode.nots.%Get(0)))
        } Else {
            Set tItn = pNode.nots.%GetIterator()
            While tItn.%GetNext(.tNk, .tNsub) {
                Set tE = {}
                Do tE.%Set("not", ..SchemaOf(tNsub))
                Do tExtra.%Push(tE)
            }
        }
    }
    // oneOf / anyOf: the first group is written directly on the node; additional groups of the same keyword are placed into allOf
    If $IsObject(pNode.%Get("alts")) {
        Set tItg = pNode.alts.%GetIterator()
        While tItg.%GetNext(.tGk, .tGe) {
            Set tArr = []
            Set tIta = tGe.list.%GetIterator()
            While tIta.%GetNext(.tAk, .tAn) { Do tArr.%Push(..SchemaOf(tAn)) }
            If tS.%IsDefined(tGe.kw) {
                Set tE = {}
                Do tE.%Set(tGe.kw, tArr)
                Do tExtra.%Push(tE)
            } Else {
                Do tS.%Set(tGe.kw, tArr)
            }
        }
    }
    // allOf members
    If $IsObject(pNode.%Get("alls")) {
        Set tItm = pNode.alls.%GetIterator()
        While tItm.%GetNext(.tMk, .tMn) { Do tExtra.%Push(..SchemaOf(tMn)) }
    }
    If pNode.type = "object" {
        Set tProps = {}, tReq = []
        Set tIt = pNode.children.%GetIterator()
        While tIt.%GetNext(.tK, .tC) {
            If tC.%Get("fromAlt") Continue
            Do tProps.%Set(tC.name, ..SchemaOf(tC))
            If 'tC.%Get("opt") Do tReq.%Push(tC.name)
        }
        Do tS.%Set("properties", tProps)
        If tReq.%Size() Do tS.%Set("required", tReq)
        If $IsObject(pNode.%Get("dep")) && pNode.dep.%GetIterator().%GetNext() Do tS.%Set("dependentRequired", pNode.dep)
        If pNode.%GetTypeOf("additional") = "boolean" {
            Do tS.%Set("additionalProperties", 0, "boolean")
        } ElseIf pNode.%GetTypeOf("additional") = "object" {
            Do tS.%Set("additionalProperties", ..SchemaOf(pNode.additional))
        }
        If $IsObject(pNode.%Get("dsch")) && pNode.dsch.%Size() {
            Set tDso = {}
            Set tItx = pNode.dsch.%GetIterator()
            While tItx.%GetNext(.tXk, .tXe) {
                If tDso.%IsDefined(tXe.key) {
                    Set tE = {}, tE2 = {}
                    Do tE2.%Set(tXe.key, ..SchemaOf(tXe.node))
                    Do tE.%Set("dependentSchemas", tE2)
                    Do tExtra.%Push(tE)
                } Else {
                    Do tDso.%Set(tXe.key, ..SchemaOf(tXe.node))
                }
            }
            If tDso.%GetIterator().%GetNext() Do tS.%Set("dependentSchemas", tDso)
        }
        If $IsObject(pNode.%Get("pnames")) Do tS.%Set("propertyNames", ..SchemaOf(pNode.pnames))
        If $IsObject(pNode.%Get("cond")) && pNode.cond.%Size() {
            Set tIt = pNode.cond.%GetIterator()
            While tIt.%GetNext(.tK, .tCe) {
                Set tE = {}
                Do tE.%Set("if", ..SchemaOf(tCe.%Get("if")))
                If $IsObject(tCe.%Get("then")) Do tE.%Set("then", ..SchemaOf(tCe.%Get("then")))
                If $IsObject(tCe.%Get("else")) Do tE.%Set("else", ..SchemaOf(tCe.%Get("else")))
                Do tExtra.%Push(tE)
            }
        }
    } ElseIf pNode.type = "array" {
        Do tS.%Set("items", ..SchemaOf(pNode.items))
        If $IsObject(pNode.%Get("contains")) Do tS.%Set("contains", ..SchemaOf(pNode.contains))
    }
    If tExtra.%Size() Do tS.%Set("allOf", tExtra)
    Quit tS
}

}
