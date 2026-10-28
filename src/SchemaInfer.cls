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
    Set sc = $$$OK
    Try {
        Set arr = []
        Do arr.%Push(##class(%DynamicAbstractObject).%FromJSON(pSample))
        Set sc = ..FromSamples(pCategory, pName, arr, pMaxDepth, pRequired)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
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
    Set sc = $$$OK
    Try {
        Set acc = ""
        Set it = pSamples.%GetIterator()
        While it.%GetNext(.i, .s, .t) {
            If t '= "object" Throw ##class(%Exception.General).%New("Sample", 5001, , "sample #"_(i+1)_" is not a JSON object")
            Set node = ..Infer("", s, t, 0, pMaxDepth, "")
            If acc = "" { Set acc = node } Else { Do ..Merge(acc, node, "") }
        }
        If acc = "" Throw ##class(%Exception.General).%New("Sample", 5001, , "no samples given")
        Do ..Finalize(acc, "", pRequired)
        Set sc = ##class(JVDoc.Schema).Save(pCategory, pName, acc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
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
    Set sc = $$$OK
    Try {
        Set s = ##class(%Stream.FileCharacter).%New()
        Set s.TranslateTable = "UTF8"
        Set sc = s.LinkToFile(pFile)
        If $$$ISERR(sc) Quit
        If s.Size = 0 {
            Set sc = $$$ERROR($$$GeneralError, "File is empty or not readable: "_pFile)
            Quit
        }
        Set data = ##class(%DynamicAbstractObject).%FromJSON(s)
        If $ClassName(data) = "%Library.DynamicArray" {
            If 'pMulti Throw ##class(%Exception.General).%New("Sample", 5001, , "file holds a JSON array; pass pMulti=1 to treat each element as one sample")
            Set arr = data
        } Else {
            Set arr = []
            Do arr.%Push(data)
        }
        Set sc = ..FromSamples(pCategory, pName, arr, pMaxDepth, pRequired)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
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
    Set sc = $$$OK
    Try {
        Set sql = "SELECT TOP "_(+pMaxDocs)_" ID FROM JVDoc.Document"
        If pFilterDocType '= "" Set sql = sql_" WHERE DocType = ?"
        Set sql = sql_" ORDER BY ID DESC"
        Set st = ##class(%SQL.Statement).%New()
        Set sc = st.%Prepare(sql)
        If $$$ISERR(sc) Quit
        If pFilterDocType '= "" { Set rs = st.%Execute(pFilterDocType) } Else { Set rs = st.%Execute() }
        If rs.%SQLCODE < 0 {
            Set sc = $$$ERROR($$$GeneralError, "Query failed: "_rs.%Message)
            Quit
        }
        Set acc = "", used = 0, skipped = 0
        While rs.%Next() {
            Set d = ##class(JVDoc.Document).%OpenId(rs.%Get("ID"))
            If '$IsObject(d) { Set skipped = skipped + 1  Continue }
            Set obj = d.GetObj(.gsc)
            If $$$ISERR(gsc) || '$IsObject(obj) || ($ClassName(obj) '= "%Library.DynamicObject") {
                Set skipped = skipped + 1
                Continue
            }
            Set node = ..Infer("", obj, "object", 0, pMaxDepth, "")
            If acc = "" { Set acc = node } Else { Do ..Merge(acc, node, "") }
            Set used = used + 1
        }
        If used = 0 {
            Set sc = $$$ERROR($$$GeneralError, "No usable stored documents found")
            Quit
        }
        Do ..Finalize(acc, "", pRequired)
        Do ##class(JVDoc.SchemaImport).Warn("info: inferred from "_used_" stored document(s), skipped "_skipped)
        Set sc = ##class(JVDoc.Schema).Save(pCategory, pName, acc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
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
        Set node = {"name":(pName), "type":"object", "children":[], "_n":1}
        If pDepth >= pMax {
            Do ##class(JVDoc.SchemaImport).Warn("truncated at depth "_pDepth_" under '"_pPath_"'")
            Do node.%Set("truncated", 1, "boolean")
            Quit node
        }
        Set it = pVal.%GetIterator()
        While it.%GetNext(.k, .v, .t) {
            If ##class(JVDoc.SchemaImport).BadName(k) {
                Do ##class(JVDoc.SchemaImport).Warn("skip property '"_k_"' under '"_$Select(pPath = "":"(root)", 1:pPath)_"' (name not usable in a VDoc path)")
                Continue
            }
            Set c = ..Infer(k, v, t, pDepth+1, pMax, pPath_$Select(pPath = "":"", 1:".")_k)
            Do c.%Set("_seen", 1)
            Do node.children.%Push(c)
        }
        Quit node
    }
    If pType = "array" {
        Set node = {"name":(pName), "type":"array"}
        Set items = ""
        Set it = pVal.%GetIterator()
        While it.%GetNext(.k, .v, .t) {
            If k >= ..#MAXARRAYITEMS {
                Do ##class(JVDoc.SchemaImport).Warn("array '"_pPath_"' has more than "_..#MAXARRAYITEMS_" items; only the first ones were inspected")
                Quit
            }
            Set e = ..Infer("", v, t, pDepth+1, pMax, pPath_"()")
            If items = "" { Set items = e } Else { Do ..Merge(items, e, pPath_"()") }
        }
        If items = "" Set items = {"name":"", "type":""}
        Do node.%Set("items", items)
        Quit node
    }

    Set st = $Case(pType, "boolean":"boolean", "null":"", "number":$Select(pVal = (pVal\1):"integer", 1:"number"), :"string")
    Set node = {"name":(pName), "type":(st)}
    If st '= "" {
        Set tc = {}
        Do tc.%Set(st, 1, "number")
        Do node.%Set("_tc", tc)
    }
    Quit node
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
    Set ta = pA.type, tb = pB.type
    If ta = "" Quit ..Adopt(pA, pB)
    If tb = "" Quit pA
    If ..IsScalar(ta) && ..IsScalar(tb) {
        // Both sides are scalars: accumulate type counts; the winning type is decided by majority in Finalize
        Set ca = pA.%Get("_tc"), cb = pB.%Get("_tc")
        Set it = cb.%GetIterator()
        While it.%GetNext(.k, .v) { Do ca.%Set(k, +ca.%Get(k) + v, "number") }
        Quit pA
    }
    If ta = "any" Quit pA
    If (tb = "any") || (ta '= tb) {
        // Kind mismatch between object, array, and scalar; the node becomes any
        Do ##class(JVDoc.SchemaImport).Warn("mixed kinds at '"_pPath_"': "_ta_" vs "_tb_"; typed as any")
        Quit ..MakeAny(pA)
    }
    If ta = "object" {
        Do pA.%Set("_n", pA.%Get("_n") + pB.%Get("_n"))
        Set it = pB.children.%GetIterator()
        While it.%GetNext(.k, .bc) {
            Set ac = ..FindChild(pA.children, bc.name)
            If ac = "" {
                Do pA.children.%Push(bc)
            } Else {
                Set seen = ac.%Get("_seen") + bc.%Get("_seen")
                Do ..Merge(ac, bc, pPath_$Select(pPath = "":"", 1:".")_bc.name)
                Do ac.%Set("_seen", seen)
            }
        }
    } ElseIf ta = "array" {
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
    Set it = pB.%GetIterator()
    While it.%GetNext(.k, .v, .t) {
        If (k = "name") || (k = "_seen") Continue
        If $IsObject(v) { Do pA.%Set(k, v) } Else { Do pA.%Set(k, v, t) }
    }
    Quit pA
}

/// Turns a node into type any and removes the structure that no longer applies (children, items, _n, _tc, truncated).<br>
/// <var>pNode</var>: raw node, modified in place<br>
/// Returns: pNode
ClassMethod MakeAny(pNode As %DynamicObject) As %DynamicObject [ Private ]
{
    Do pNode.%Set("type", "any")
    For k = "children", "items", "_n", "_tc", "truncated" { Do pNode.%Remove(k) }
    Quit pNode
}

/// Finds a child node by name.<br>
/// <var>pChildren</var>: children array of an object node<br>
/// <var>pName</var>: property name to look for<br>
/// Returns: the child node, or "" when there is none
ClassMethod FindChild(pChildren As %DynamicArray, pName As %String) [ Private ]
{
    Set found = ""
    Set it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) {
        If c.name = pName { Set found = c  Quit }
    }
    Quit found
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

    Set tc = pNode.%Get("_tc")
    If $IsObject(tc) {
        Set cnt("string") = +tc.%Get("string"), cnt("boolean") = +tc.%Get("boolean"), cnt("num") = +tc.%Get("integer") + tc.%Get("number")
        Set best = $Case(pNode.type, "integer":"num", "number":"num", :pNode.type)
        Set k = ""
        For {
            Set k = $Order(cnt(k))
            If k = "" Quit
            If cnt(k) > cnt(best) Set best = k
        }
        Set kinds = 0, desc = "", k = ""
        For {
            Set k = $Order(cnt(k))
            If k = "" Quit
            If cnt(k) > 0 {
                Set kinds = kinds + 1
                Set desc = desc_$Select(desc = "":"", 1:", ")_$Select(k = "num":"numeric", 1:k)_"("_cnt(k)_")"
            }
        }
        If kinds > 1 Do ##class(JVDoc.SchemaImport).Warn("mixed types at '"_$Select(pPath = "":"(root)", 1:pPath)_"': "_desc_"; chose "_$Select(best = "num":"numeric", 1:best))
        Do pNode.%Set("type", $Select(best = "num":$Select(+tc.%Get("number") > 0:"number", 1:"integer"), 1:best))
        Do pNode.%Remove("_tc")
    }

    If pNode.type = "object" {
        Set n = pNode.%Get("_n")
        Do pNode.%Remove("_n")
        Set it = pNode.children.%GetIterator()
        While it.%GetNext(.k, .c) {
            If 'pRequired || (c.%Get("_seen") < n) Do c.%Set("opt", 1, "boolean")
            Do c.%Remove("_seen")
            Do ..Finalize(c, pPath_$Select(pPath = "":"", 1:".")_c.name, pRequired)
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
    Set tree = ##class(JVDoc.Schema).GetTree(pDocType)
    If '$IsObject(tree) Quit ""
    Set out = ..SchemaOf(tree)
    Do out.%Set("$schema", "https://json-schema.org/draft/2020-12/schema")
    Quit out
}

/// Converts one field-tree node (and its subtree) back into a JSON Schema object: type (omitted for any), description, enum, pattern and the
/// constraint keys; boolean exclusive bounds in numeric form; not, oneOf/anyOf, properties/required, dependentRequired, additionalProperties,
/// dependentSchemas, propertyNames, items and contains. Children marked fromAlt are left to their alternative. Whatever cannot sit on the node
/// itself (further not entries, a second group of the same oneOf/anyOf keyword, allOf members, duplicate dependentSchemas keys, if/then/else) goes into allOf.<br>
/// <var>pNode</var>: a field-tree node; not modified<br>
/// Returns: a new %DynamicObject holding the JSON Schema for the node
ClassMethod SchemaOf(pNode As %DynamicObject) As %DynamicObject [ Private ]
{
    If pNode.type = "any" { Set s = {} } Else { Set s = {"type":(pNode.type)} }
    If pNode.desc '= "" Do s.%Set("description", pNode.desc)
    If $IsObject(pNode.%Get("enum")) Do s.%Set("enum", pNode.enum)
    If pNode.%Get("pattern") '= "" Do s.%Set("pattern", pNode.pattern)
    Set kl = ##class(JVDoc.SchemaImport).ConstraintKeys()
    For i = 1:1:$ListLength(kl) { Do ##class(JVDoc.SchemaImport).CopyTyped(pNode, s, $List(kl, i)) }
    // A draft-04 boolean exclusiveMinimum/exclusiveMaximum is written in the numeric form 2020-12 requires
    For bk = "Minimum", "Maximum" {
        Set ek = "exclusive"_bk, mk = $ZConvert(bk, "L")
        If s.%GetTypeOf(ek) = "boolean" {
            If s.%Get(ek) && (s.%GetTypeOf(mk) = "number") {
                Do s.%Set(ek, s.%Get(mk), "number")
                Do s.%Remove(mk)
            } Else {
                Do s.%Remove(ek)
            }
        }
    }
    Set extra = []
    If $IsObject(pNode.%Get("nots")) && pNode.nots.%Size() {
        If pNode.nots.%Size() = 1 {
            Do s.%Set("not", ..SchemaOf(pNode.nots.%Get(0)))
        } Else {
            Set itn = pNode.nots.%GetIterator()
            While itn.%GetNext(.nk, .nsub) {
                Set e = {}
                Do e.%Set("not", ..SchemaOf(nsub))
                Do extra.%Push(e)
            }
        }
    }
    // oneOf / anyOf: the first group is written directly on the node; additional groups of the same keyword are placed into allOf
    If $IsObject(pNode.%Get("alts")) {
        Set itg = pNode.alts.%GetIterator()
        While itg.%GetNext(.gk, .ge) {
            Set arr = []
            Set ita = ge.list.%GetIterator()
            While ita.%GetNext(.ak, .an) { Do arr.%Push(..SchemaOf(an)) }
            If s.%IsDefined(ge.kw) {
                Set e = {}
                Do e.%Set(ge.kw, arr)
                Do extra.%Push(e)
            } Else {
                Do s.%Set(ge.kw, arr)
            }
        }
    }
    // allOf members
    If $IsObject(pNode.%Get("alls")) {
        Set itm = pNode.alls.%GetIterator()
        While itm.%GetNext(.mk, .mn) { Do extra.%Push(..SchemaOf(mn)) }
    }
    If pNode.type = "object" {
        Set props = {}, req = []
        Set it = pNode.children.%GetIterator()
        While it.%GetNext(.k, .c) {
            If c.%Get("fromAlt") Continue
            Do props.%Set(c.name, ..SchemaOf(c))
            If 'c.%Get("opt") Do req.%Push(c.name)
        }
        Do s.%Set("properties", props)
        If req.%Size() Do s.%Set("required", req)
        If $IsObject(pNode.%Get("dep")) && pNode.dep.%GetIterator().%GetNext() Do s.%Set("dependentRequired", pNode.dep)
        If pNode.%GetTypeOf("additional") = "boolean" {
            Do s.%Set("additionalProperties", 0, "boolean")
        } ElseIf pNode.%GetTypeOf("additional") = "object" {
            Do s.%Set("additionalProperties", ..SchemaOf(pNode.additional))
        }
        If $IsObject(pNode.%Get("dsch")) && pNode.dsch.%Size() {
            Set dso = {}
            Set itx = pNode.dsch.%GetIterator()
            While itx.%GetNext(.xk, .xe) {
                If dso.%IsDefined(xe.key) {
                    Set e = {}, e2 = {}
                    Do e2.%Set(xe.key, ..SchemaOf(xe.node))
                    Do e.%Set("dependentSchemas", e2)
                    Do extra.%Push(e)
                } Else {
                    Do dso.%Set(xe.key, ..SchemaOf(xe.node))
                }
            }
            If dso.%GetIterator().%GetNext() Do s.%Set("dependentSchemas", dso)
        }
        If $IsObject(pNode.%Get("pnames")) Do s.%Set("propertyNames", ..SchemaOf(pNode.pnames))
        If $IsObject(pNode.%Get("cond")) && pNode.cond.%Size() {
            Set it = pNode.cond.%GetIterator()
            While it.%GetNext(.k, .ce) {
                Set e = {}
                Do e.%Set("if", ..SchemaOf(ce.%Get("if")))
                If $IsObject(ce.%Get("then")) Do e.%Set("then", ..SchemaOf(ce.%Get("then")))
                If $IsObject(ce.%Get("else")) Do e.%Set("else", ..SchemaOf(ce.%Get("else")))
                Do extra.%Push(e)
            }
        }
    } ElseIf pNode.type = "array" {
        Do s.%Set("items", ..SchemaOf(pNode.items))
        If $IsObject(pNode.%Get("contains")) Do s.%Set("contains", ..SchemaOf(pNode.contains))
    }
    If extra.%Size() Do s.%Set("allOf", extra)
    Quit s
}

}
