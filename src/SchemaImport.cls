/// Converts JSON Schema documents (draft-07 / 2020-12) into the JVDoc normalized field tree
/// and persists them via JVDoc.Schema.Save. Also provides Outline (pretty-print the tree),
/// Report (print import warnings), and ConstraintText (summary text for Outline display).
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.SchemaImport
{

// ---------------- Entry points ----------------

/// Imports one JSON Schema whose root describes the message and saves it as the DocType pCategory:pName.
/// The root must resolve to an object. The warning log (^||JVDoc.Warn) is reset first; read it with Report.<br>
/// <var>pCategory</var>: first part of the DocType ("Demo" in "Demo:Order")<br>
/// <var>pName</var>: second part of the DocType ("Order" in "Demo:Order"); an existing DocType of that name is overwritten<br>
/// <var>pSchema</var>: the JSON Schema as a %DynamicObject; in-document $ref, $defs and definitions are resolved against it<br>
/// <var>pMaxDepth</var>: nesting depth at which object recursion is cut off with a warning (default 8)<br>
/// Returns: $$$OK when the DocType was saved; an error when the root is not an object or the save fails
ClassMethod FromJSONSchema(pCategory As %String, pName As %String, pSchema As %DynamicObject, pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
    Set sc = $$$OK
    Try {
        Set root = ..Node("", pSchema, pSchema, 0, pMaxDepth)
        If root.type '= "object" Throw ##class(%Exception.General).%New("Root", 5001, , "root schema must be an object")
        Set sc = ##class(JVDoc.Schema).Save(pCategory, pName, root)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Reads a UTF-8 JSON Schema file and imports it with FromJSONSchema.<br>
/// <var>pCategory</var>: first part of the DocType<br>
/// <var>pName</var>: second part of the DocType<br>
/// <var>pFile</var>: path of the JSON Schema file on the server<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off (default 8)<br>
/// Returns: $$$OK when the DocType was saved; an error when the file is empty, unreadable or not valid JSON, or the import fails
ClassMethod FromFile(pCategory As %String, pName As %String, pFile As %String, pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
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
        Set sch = {}.%FromJSON(s)
        Set sc = ..FromJSONSchema(pCategory, pName, sch, pMaxDepth)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Imports several sub-schemas of one JSON Schema, each as a separate DocType named by its key; $ref between them is resolved against the whole schema.
/// Entries that are not objects, whose key is empty or contains ":" or "|", or that fail to import are skipped with a warning.
/// The warning log is reset first and records an "info: created" line per DocType.<br>
/// <var>pCategory</var>: category shared by every DocType created<br>
/// <var>pSchema</var>: the whole JSON Schema as a %DynamicObject<br>
/// <var>pSource</var>: "defs" (default) takes each entry of $defs, or of definitions when $defs is absent; "properties" takes each root property<br>
/// <var>pNames</var>: comma-separated keys to import; empty imports all<br>
/// <var>pRootName</var>: when non-empty, the root schema itself is also imported as pCategory:pRootName<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off (default 8)<br>
/// Returns: $$$OK when at least one DocType was created; an error when the source container is missing, the root import fails, or nothing was created
ClassMethod FromBundle(pCategory As %String, pSchema As %DynamicObject, pSource As %String = "defs", pNames As %String = "", pRootName As %String = "", pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
    Set sc = $$$OK
    Try {
        If pSource = "properties" {
            Set cont = pSchema.%Get("properties")
            Set what = "properties"
        } Else {
            Set cont = pSchema.%Get("$defs")
            If '$IsObject(cont) Set cont = pSchema.%Get("definitions")
            Set what = "$defs or definitions"
        }
        If '$IsObject(cont) Throw ##class(%Exception.General).%New("Bundle", 5001, , "no "_what_" found in the schema")
        Set want = $Select(pNames = "":"", 1:","_pNames_",")
        Set made = 0
        If pRootName '= "" {
            Set s0 = ..SaveSub(pCategory, pRootName, pSchema, pSchema, pMaxDepth)
            If $$$ISERR(s0) Throw ##class(%Exception.General).%New("Bundle", 5001, , "root: "_$System.Status.GetErrorText(s0))
            Set made = made + 1
        }
        Set it = cont.%GetIterator()
        While it.%GetNext(.k, .sub, .t) {
            If (want '= "") && (want '[ (","_k_",")) Continue
            If t '= "object" {
                Do ..Warn("skip '"_k_"' (not a schema object)")
                Continue
            }
            If (k [ ":") || (k [ "|") || (k = "") {
                Do ..Warn("skip '"_k_"' (name not usable in a DocType)")
                Continue
            }
            Set s1 = ..SaveSub(pCategory, k, sub, pSchema, pMaxDepth)
            If $$$ISERR(s1) {
                Do ..Warn("skip '"_k_"': "_$System.Status.GetErrorText(s1))
                Continue
            }
            Set made = made + 1
        }
        If made = 0 Throw ##class(%Exception.General).%New("Bundle", 5001, , "no DocType was created")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Reads a UTF-8 JSON Schema file and imports it with FromBundle.<br>
/// <var>pCategory</var>: category shared by every DocType created<br>
/// <var>pFile</var>: path of the JSON Schema file on the server<br>
/// <var>pSource</var>: "defs" (default) or "properties", as in FromBundle<br>
/// <var>pNames</var>: comma-separated keys to import; empty imports all<br>
/// <var>pRootName</var>: when non-empty, the root schema is also imported under this name<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off (default 8)<br>
/// Returns: $$$OK when at least one DocType was created; an error when the file is empty, unreadable or not valid JSON, or FromBundle fails
ClassMethod FromBundleFile(pCategory As %String, pFile As %String, pSource As %String = "defs", pNames As %String = "", pRootName As %String = "", pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
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
        Set sch = {}.%FromJSON(s)
        Set sc = ..FromBundle(pCategory, sch, pSource, pNames, pRootName, pMaxDepth)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Imports one sub-schema of a bundle as the document root of a DocType and records an "info: created" line in the warning log on success.<br>
/// <var>pCategory</var>: first part of the DocType<br>
/// <var>pName</var>: second part of the DocType (the bundle key or root name)<br>
/// <var>pSub</var>: the sub-schema (%DynamicObject) that describes the message<br>
/// <var>pRoot</var>: the whole schema document, against which $ref inside pSub is resolved<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off<br>
/// Returns: $$$OK when the DocType was saved; an error when the sub-schema does not resolve to an object or the save fails
ClassMethod SaveSub(pCategory As %String, pName As %String, pSub, pRoot, pMaxDepth As %Integer) As %Status [ Private ]
{
    Set node = ..Node("", pSub, pRoot, 0, pMaxDepth)
    If node.type '= "object" Quit $$$ERROR($$$GeneralError, "schema is not an object (type "_node.type_")")
    Set sc = ##class(JVDoc.Schema).Save(pCategory, pName, node)
    If $$$ISOK(sc) Do ..Warn("info: created "_pCategory_":"_pName)
    Quit sc
}

// ---------------- Schema normalization ----------------

/// Flattens one raw schema into the intermediate form that Node and BuildObject consume: resolves $ref, copies type, items, description,
/// enum, pattern, the constraint keywords and additionalProperties, and collects properties, required, dep (dependentRequired), ds (dependentSchemas
/// and the draft-07 dependencies object form), cond (if/then/else), nl (not), contains, pn (propertyNames), alls (allOf members), alts (oneOf/anyOf
/// groups) and altProps (property names that come only from alternatives). allOf members contribute properties, required and type/items/description;
/// oneOf/anyOf alternatives contribute properties and decide the type: any when their kinds differ.<br>
/// <var>pSch</var>: the raw schema object; a non-object yields the empty form<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: allOf/oneOf/anyOf nesting level; past 10 the empty form is returned<br>
/// Returns: a new %DynamicObject in normalized form; properties, required, cond, dep, nl, ds, alts, alls and altProps are always present
ClassMethod Normalize(pSch, pRoot, pDepth As %Integer) As %DynamicObject
{
    Set out = {"properties":{}, "required":[], "cond":[], "dep":{}, "nl":[], "ds":[], "alts":[], "alls":[], "altProps":{}}
    If ('$IsObject(pSch)) || (pDepth > 10) Quit out
    Set sch = ..Deref(pSch, pRoot)
    Set fl = $ListBuild("type", "items", "description", "enum", "pattern")
    For i = 1:1:$ListLength(fl) {
        Set f = $List(fl, i)
        If sch.%IsDefined(f) Do out.%Set(f, sch.%Get(f))
    }
    Set cl = ..ConstraintKeys()
    For i = 1:1:$ListLength(cl) { Do ..CopyTyped(sch, out, $List(cl, i)) }
    // additionalProperties: only the value written directly on this node is used (not from allOf/oneOf/anyOf/if/then/else)
    Do ..CopyTyped(sch, out, "additionalProperties")
    Set csub = sch.%Get("contains")
    If $IsObject(csub) && ($ClassName(csub) = "%Library.DynamicObject") Do out.%Set("contains", csub)
    Set nsub = sch.%Get("not")
    If $IsObject(nsub) && ($ClassName(nsub) = "%Library.DynamicObject") Do out.nl.%Push(nsub)
    Set psub = sch.%Get("propertyNames")
    If $IsObject(psub) && ($ClassName(psub) = "%Library.DynamicObject") Do out.%Set("pn", psub)
    If $IsObject(sch.%Get("properties")) {
        Set it = sch.properties.%GetIterator()
        While it.%GetNext(.k, .v) { Do out.properties.%Set(k, v) }
    }
    If $IsObject(sch.%Get("required")) {
        Set it = sch.required.%GetIterator()
        While it.%GetNext(.k, .v) { Do out.required.%Push(v) }
    }
    For dk = "dependentRequired", "dependencies" {
        Set dsrc = sch.%Get(dk)
        If $IsObject(dsrc) && ($ClassName(dsrc) = "%Library.DynamicObject") {
            Set itd = dsrc.%GetIterator()
            While itd.%GetNext(.k, .v, .t) {
                If t = "array" {
                    Do ..AddDep(out.dep, k, v)
                } ElseIf (dk = "dependencies") && (t = "object") {
                    Do ..AddDs(out.ds, k, v)
                }
            }
        }
    }
    Set dss = sch.%Get("dependentSchemas")
    If $IsObject(dss) && ($ClassName(dss) = "%Library.DynamicObject") {
        Set itd = dss.%GetIterator()
        While itd.%GetNext(.k, .v, .t) { If t = "object" Do ..AddDs(out.ds, k, v) }
    }
    Set ifs = sch.%Get("if")
    If $IsObject(ifs) {
        Set ce = {}
        Do ce.%Set("if", ifs)
        If $IsObject(sch.%Get("then")) Do ce.%Set("then", sch.%Get("then"))
        If $IsObject(sch.%Get("else")) Do ce.%Set("else", sch.%Get("else"))
        Do out.cond.%Push(ce)
    }
    // allOf members are stored as 'alls' for validation; oneOf/anyOf alternatives are stored as 'alts', and their fields are merged into the parent (marked as fromAlt)
    Set altKinds = "", altAny = 0
    For kw = "allOf", "oneOf", "anyOf" {
        If '$IsObject(sch.%Get(kw)) Continue
        Set group = []
        Set it = sch.%Get(kw).%GetIterator()
        While it.%GetNext(.n, .alt) {
            Set a = ..Normalize(alt, pRoot, pDepth+1)
            If $IsObject(alt) && ($ClassName(alt) = "%Library.DynamicObject") {
                If kw = "allOf" { Do out.alls.%Push(alt) } Else { Do group.%Push(alt) }
            }
            If (kw '= "allOf") && ..HasKind(a) {
                Set ak = ..TypeOf(a)
                If ak = "any" {
                    Set altAny = 1
                } Else {
                    Set ak = $Select(ak = "integer":"number", 1:ak)
                    If '$ListFind(altKinds, ak) Set altKinds = altKinds_$ListBuild(ak)
                }
            }
            Set it2 = a.properties.%GetIterator()
            While it2.%GetNext(.k, .v) {
                If 'out.properties.%IsDefined(k) {
                    Do out.properties.%Set(k, v)
                    If (kw '= "allOf") || a.altProps.%IsDefined(k) Do out.altProps.%Set(k, 1, "boolean")
                }
            }
            If kw = "allOf" {
                Set it2 = a.required.%GetIterator()
                While it2.%GetNext(.j, .r) { Do out.required.%Push(r) }
            }
            For f = "type", "items", "description" {
                If ('out.%IsDefined(f)) && a.%IsDefined(f) Do out.%Set(f, a.%Get(f))
            }
        }
        If (kw '= "allOf") && group.%Size() {
            Set ge = {}
            Do ge.%Set("kw", kw)
            Do ge.%Set("list", group)
            Do out.alts.%Push(ge)
        }
    }
    If altAny || ($ListLength(altKinds) > 1) {
        Do out.%Set("type", "any")
    } ElseIf ($ListLength(altKinds) = 1) && 'sch.%IsDefined("type") {
        Do out.%Set("type", $List(altKinds, 1))
    }
    Quit out
}

/// Follows a $ref chain (up to 20 levels) to the referenced schema. Only in-document references are supported: "#", JSON pointers "#/...",
/// and "#name" anchors ($anchor or draft-07 $id: "#name"). An external or unresolved reference stops the chain with a warning, so the node becomes any.<br>
/// <var>pSch</var>: the schema, possibly carrying $ref<br>
/// <var>pRoot</var>: the whole schema document that references are resolved against<br>
/// Returns: the referenced schema, or the last schema reached when the chain could not be followed further
ClassMethod Deref(pSch, pRoot)
{
    Set n = 0
    While $IsObject(pSch) && pSch.%IsDefined("$ref") && ($Increment(n) <= 20) {
        Set ref = pSch.%Get("$ref")
        Set cur = ""
        If ref = "#" {
            Set cur = pRoot
        } ElseIf $Extract(ref, 1, 2) = "#/" {
            Set cur = pRoot
            For i = 2:1:$Length(ref, "/") {
                Set seg = $Replace($Replace($Piece(ref, "/", i), "~1", "/"), "~0", "~")
                If '$IsObject(cur) || 'cur.%IsDefined(seg) { Set cur = "" Quit }
                Set cur = cur.%Get(seg)
            }
        } ElseIf ($Extract(ref) = "#") && ($Length(ref) > 1) {
            Set cur = ..FindAnchor(pRoot, $Extract(ref, 2, *))
        } Else {
            Do ..Warn("external $ref not supported, typed as any: "_ref)
            Quit
        }
        If '$IsObject(cur) {
            Do ..Warn("unresolved $ref, typed as any: "_ref)
            Quit
        }
        Set pSch = cur
    }
    Quit pSch
}

/// Recursively searches a schema document for the sub-schema that carries a given $anchor (or a draft-07 $id: "#name");
/// the values of enum, const, examples and default are not searched.<br>
/// <var>pNode</var>: the object or array to search<br>
/// <var>pName</var>: the anchor name without the leading #<br>
/// <var>pDepth</var>: current recursion depth; the search stops past 100<br>
/// Returns: the matching sub-schema, or "" when not found
ClassMethod FindAnchor(pNode, pName As %String, pDepth As %Integer = 0)
{
    If '$IsObject(pNode) || (pDepth > 100) Quit ""
    Set isObj = ($ClassName(pNode) = "%Library.DynamicObject")
    If isObj && ((pNode.%Get("$anchor") = pName) || (pNode.%Get("$id") = ("#"_pName))) Quit pNode
    Set found = ""
    Set it = pNode.%GetIterator()
    While it.%GetNext(.k, .v) {
        If '$IsObject(v) Continue
        If isObj && ((k = "enum") || (k = "const") || (k = "examples") || (k = "default")) Continue
        Set found = ..FindAnchor(v, pName, pDepth+1)
        If found '= "" Quit
    }
    Quit found
}

/// Returns the effective type of a normalized schema. For a type array, its single non-null type, or any when it mixes kinds (integer and number
/// count as one). When no type is declared, object or array is inferred from the keywords present (properties, required, dep, ds, pn, minProperties,
/// maxProperties, additionalProperties give object; items, contains, minItems, maxItems, uniqueItems give array).<br>
/// <var>pS</var>: a schema in the form produced by Normalize<br>
/// Returns: "object", "array", "string", "integer", "number", "boolean" or "any"
ClassMethod TypeOf(pS) As %String
{
    Set t = pS.%Get("type")
    If $IsObject(t) {
        Set it = t.%GetIterator(), first = "", kinds = ""
        While it.%GetNext(.k, .v) {
            If v = "null" Continue
            If first = "" Set first = v
            Set g = $Select(v = "integer":"number", 1:v)
            If '$ListFind(kinds, g) Set kinds = kinds_$ListBuild(g)
        }
        If $ListLength(kinds) > 1 Quit "any"
        Set t = first
    }
    If (t = "") || (t = "null") {
        If pS.properties.%GetIterator().%GetNext() Quit "object"
        If pS.required.%GetIterator().%GetNext() Quit "object"
        If $IsObject(pS.%Get("dep")) && pS.dep.%GetIterator().%GetNext() Quit "object"
        If $IsObject(pS.%Get("ds")) && pS.ds.%Size() Quit "object"
        If pS.%IsDefined("pn") Quit "object"
        If pS.%IsDefined("minProperties") || pS.%IsDefined("maxProperties") Quit "object"
        If pS.%IsDefined("additionalProperties") Quit "object"
        If pS.%IsDefined("items") || pS.%IsDefined("contains") || pS.%IsDefined("minItems") || pS.%IsDefined("maxItems") || pS.%IsDefined("uniqueItems") Quit "array"
        Quit "any"
    }
    Quit t
}

/// Returns whether a normalized oneOf/anyOf alternative declares a concrete kind.<br>
/// <var>pAlt</var>: the alternative in the form produced by Normalize<br>
/// Returns: 1 when it has a non-null type, or a type that TypeOf can infer; 0 for a null-only alternative or one that would be any
ClassMethod HasKind(pAlt) As %Boolean [ Private ]
{
    Set t = pAlt.%Get("type")
    If t = "null" Quit 0
    If t '= "" Quit 1
    Quit (..TypeOf(pAlt) '= "any")
}

/// Merges dependent property names into one entry of a dep map (dependentRequired), skipping duplicates and non-string entries.<br>
/// <var>pDep</var>: the dep %DynamicObject of a normalized schema; modified in place<br>
/// <var>pKey</var>: the property whose presence requires the others<br>
/// <var>pNames</var>: %DynamicArray of the required property names
ClassMethod AddDep(pDep, pKey As %String, pNames) [ Private ]
{
    If 'pDep.%IsDefined(pKey) Do pDep.%Set(pKey, [])
    Set cur = pDep.%Get(pKey)
    Set it = pNames.%GetIterator()
    While it.%GetNext(.i, .nm, .t) {
        If (t = "string") && '..InList(cur, nm) Do cur.%Push(nm)
    }
}

/// Appends a {key, sch} entry to the ds list of a normalized schema (dependentSchemas and the draft-07 dependencies object form).<br>
/// <var>pArr</var>: the ds %DynamicArray; modified in place<br>
/// <var>pKey</var>: the property whose presence activates the sub-schema<br>
/// <var>pSub</var>: the dependent sub-schema
ClassMethod AddDs(pArr, pKey As %String, pSub) [ Private ]
{
    Set e = {}
    Do e.%Set("key", pKey)
    Do e.%Set("sch", pSub)
    Do pArr.%Push(e)
}

// ---------------- Field tree construction ----------------

/// Builds the field-tree node for one schema: name, type (TypeOf), desc, enum with its comma-joined vals, pattern and the constraint keywords;
/// then children for an object (BuildObject) or items for an array, and the sub-schema nodes pnames (propertyNames), nots, contains,
/// alts (oneOf/anyOf groups, each with kw and list) and alls (allOf members). Sub-schema nodes are skipped with a warning once pDepth reaches pMax.<br>
/// <var>pName</var>: field name of the node; "" for the root, array items and sub-schemas<br>
/// <var>pSch</var>: the raw schema of the node<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: depth of this node in the tree (0 for the root)<br>
/// <var>pMax</var>: depth limit at which recursion is cut off<br>
/// Returns: the new field-tree node as a %DynamicObject
ClassMethod Node(pName, pSch, pRoot, pDepth, pMax) As %DynamicObject
{
    Set s = ..Normalize(pSch, pRoot, 0)
    Set type = ..TypeOf(s)
    Set node = {"name":(pName), "type":(type)}
    If s.%IsDefined("description") Do node.%Set("desc", s.description)
    If $IsObject(s.%Get("enum")) {
        Do node.%Set("vals", ..Join(s.enum))
        Do node.%Set("enum", s.enum)
    }
    If s.%Get("pattern") '= "" Do node.%Set("pattern", s.%Get("pattern"))
    Set cl = ..ConstraintKeys()
    For i = 1:1:$ListLength(cl) { Do ..CopyTyped(s, node, $List(cl, i)) }
    If type = "object" {
        Do ..BuildObject(s, node, pRoot, pDepth, pMax)
    } ElseIf type = "array" {
        Set item = {}
        If s.%IsDefined("items") && $IsObject(s.items) && ($ClassName(s.items) = "%Library.DynamicObject") Set item = s.items
        Set node.items = ..Node("", item, pRoot, pDepth+1, pMax)
    }
    // propertyNames: the sub-schema is built into a node that is checked against every property name
    If (type = "object") && $IsObject(s.%Get("pn")) {
        If pDepth >= pMax {
            Do ..Warn("propertyNames skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            Set node.pnames = ..Node("", s.pn, pRoot, pDepth+1, pMax)
        }
    }
    // not / contains: each sub-schema is built into its own node
    Set hasCont = ((type = "array") && $IsObject(s.%Get("contains")))
    If s.nl.%Size() || hasCont {
        If pDepth >= pMax {
            Do ..Warn("not/contains skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            If s.nl.%Size() {
                Set node.nots = []
                Set itn = s.nl.%GetIterator()
                While itn.%GetNext(.nk, .nsub) { Do node.nots.%Push(..Node("", nsub, pRoot, pDepth+1, pMax)) }
            }
            If hasCont Set node.contains = ..Node("", s.contains, pRoot, pDepth+1, pMax)
        }
    }
    // oneOf/anyOf alternatives and allOf members: each becomes its own node and is evaluated independently at validation time
    If s.alts.%Size() || s.alls.%Size() {
        If pDepth >= pMax {
            Do ..Warn("oneOf/anyOf/allOf skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            If s.alts.%Size() {
                Set node.alts = []
                Set itg = s.alts.%GetIterator()
                While itg.%GetNext(.gk, .ge) {
                    Set gn = {}
                    Do gn.%Set("kw", ge.kw)
                    Set gl = []
                    Set ita = ge.list.%GetIterator()
                    While ita.%GetNext(.ak, .asub) { Do gl.%Push(..Node("", asub, pRoot, pDepth+1, pMax)) }
                    Do gn.%Set("list", gl)
                    Do node.alts.%Push(gn)
                }
            }
            If s.alls.%Size() {
                Set node.alls = []
                Set itm = s.alls.%GetIterator()
                While itm.%GetNext(.mk, .msub) { Do node.alls.%Push(..Node("", msub, pRoot, pDepth+1, pMax)) }
            }
        }
    }
    Quit node
}

/// Fills the children of an object node: one child per property (opt unless listed in required, fromAlt when it came only from a oneOf/anyOf
/// alternative), required names without a property as any children, dependentRequired keys and names as optional any children plus the dep map,
/// dependentSchemas as dsch entries {key, node} whose fields are unioned into the parent, additional (false or a node), and if/then/else entries in cond.
/// When pDepth has reached pMax the node is marked truncated and left without children, with a warning.<br>
/// <var>pS</var>: the normalized schema of the object (from Normalize)<br>
/// <var>pNode</var>: the object node to fill; modified in place<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: depth of pNode in the tree<br>
/// <var>pMax</var>: depth limit at which recursion is cut off<br>
/// <var>pBranch</var>: 1 inside an if/then/else branch or dependentSchemas sub-schema, where additionalProperties is ignored (default 0)
ClassMethod BuildObject(pS, pNode, pRoot, pDepth, pMax, pBranch As %Boolean = 0) [ Private ]
{
    Set pNode.children = []
    If pDepth >= pMax {
        Do pNode.%Set("truncated", 1, "boolean")
        Do ..Warn("truncated at depth "_pDepth_" under '"_pNode.name_"'")
        Quit
    }
    Set it = pS.properties.%GetIterator()
    While it.%GetNext(.k, .v) {
        If ..BadName(k) {
            Do ..Warn("skip property '"_k_"' under '"_pNode.name_"' (name not usable in a VDoc path)")
            Continue
        }
        Set c = ..Node(k, v, pRoot, pDepth+1, pMax)
        If '..InList(pS.required, k) Do c.%Set("opt", 1, "boolean")
        If pS.altProps.%IsDefined(k) Do c.%Set("fromAlt", 1, "boolean")
        Do pNode.children.%Push(c)
    }
    // Names listed in required but absent from properties are added as 'any' fields
    Set it = pS.required.%GetIterator()
    While it.%GetNext(.k, .rn) {
        If ..BadName(rn) || ..HasChild(pNode.children, rn) Continue
        Do pNode.children.%Push({"name":(rn), "type":"any"})
    }
    // dependentRequired: the key and its dependent names are added as optional any fields when missing from the tree
    Set depn = pS.%Get("dep")
    If $IsObject(depn) && depn.%GetIterator().%GetNext() {
        Set itd = depn.%GetIterator()
        While itd.%GetNext(.k, .names) {
            Do ..EnsureAny(pNode, k)
            Set itn = names.%GetIterator()
            While itn.%GetNext(.j, .nm) { Do ..EnsureAny(pNode, nm) }
        }
        Do pNode.%Set("dep", ..CloneNode(depn))
    }
    // dependentSchemas: each key gets a child node; the node's fields are merged into the parent as optional fields without constraints, and the key itself is added as an any field when absent
    If pS.ds.%Size() {
        Set pNode.dsch = []
        Set itx = pS.ds.%GetIterator()
        While itx.%GetNext(.xk, .xe) {
            Set dn = ..CondNode(xe.sch, pRoot, pDepth, pMax)
            Do ..EnsureAny(pNode, xe.key)
            Do ..UnionInto(pNode, dn)
            Set en = {}
            Do en.%Set("key", xe.key)
            Do en.%Set("node", dn)
            Do pNode.dsch.%Push(en)
        }
    }
    // additionalProperties: only false and a schema object need to be stored; ignored inside conditional branches
    If 'pBranch {
        Set at = pS.%GetTypeOf("additionalProperties")
        If at = "boolean" {
            If 'pS.%Get("additionalProperties") Do pNode.%Set("additional", 0, "boolean")
        } ElseIf at = "object" {
            Do pNode.%Set("additional", ..Node("", pS.%Get("additionalProperties"), pRoot, pDepth+1, pMax))
        }
    }
    If pS.cond.%Size() {
        Set pNode.cond = []
        Set it = pS.cond.%GetIterator()
        While it.%GetNext(.k, .ce) { Do ..BuildCond(ce, pNode, pRoot, pDepth, pMax) }
    }
}

/// Turns one if/then/else entry into a cond entry {if, then, else} of object nodes (CondNode) appended to pNode.cond;
/// the fields of every branch are unioned into pNode as optional fields without constraints. An entry whose if is not an object is ignored.<br>
/// <var>pCE</var>: the cond entry of a normalized schema: {if, then?, else?} raw sub-schemas<br>
/// <var>pNode</var>: the object node that receives the rule; pNode.cond must already exist<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: depth of pNode in the tree<br>
/// <var>pMax</var>: depth limit at which recursion is cut off
ClassMethod BuildCond(pCE, pNode, pRoot, pDepth, pMax) [ Private ]
{
    Set ifs = pCE.%Get("if")
    If '$IsObject(ifs) || ($ClassName(ifs) '= "%Library.DynamicObject") Quit
    Set entry = {}
    Set ifn = ..CondNode(ifs, pRoot, pDepth, pMax)
    Do entry.%Set("if", ifn)
    Do ..UnionInto(pNode, ifn)
    For br = "then", "else" {
        Set sub = pCE.%Get(br)
        If $IsObject(sub) && ($ClassName(sub) = "%Library.DynamicObject") {
            Set bn = ..CondNode(sub, pRoot, pDepth, pMax)
            Do entry.%Set(br, bn)
            Do ..UnionInto(pNode, bn)
        }
    }
    Do pNode.cond.%Push(entry)
}

/// Builds an object node for an if/then/else branch or a dependentSchemas sub-schema; additionalProperties inside the branch is ignored.<br>
/// <var>pSub</var>: the raw branch sub-schema<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: depth of the owning object node; the branch's children are built one level deeper<br>
/// <var>pMax</var>: depth limit at which recursion is cut off<br>
/// Returns: an unnamed object node with its children
ClassMethod CondNode(pSub, pRoot, pDepth, pMax) As %DynamicObject [ Private ]
{
    Set s = ..Normalize(pSub, pRoot, 0)
    Set n = {"name":"", "type":"object"}
    Do ..BuildObject(s, n, pRoot, pDepth+1, pMax, 1)
    Quit n
}

/// Adds the children of one object node to another, skipping names already present; each added child is a clone stripped by Neutralize and marked opt.<br>
/// <var>pTarget</var>: the object node that receives the children; modified in place<br>
/// <var>pSource</var>: the object node whose children are copied
ClassMethod UnionInto(pTarget, pSource) [ Private ]
{
    Set it = pSource.children.%GetIterator()
    While it.%GetNext(.k, .c) {
        If ..HasChild(pTarget.children, c.name) Continue
        Set c2 = ..CloneNode(c)
        Do ..Neutralize(c2)
        Do c2.%Set("opt", 1, "boolean")
        Do pTarget.children.%Push(c2)
    }
}

/// Adds an optional any child to an object node unless the name is unusable in a path (BadName) or already present.<br>
/// <var>pNode</var>: the object node; modified in place<br>
/// <var>pName</var>: the field name to add
ClassMethod EnsureAny(pNode, pName As %String) [ Private ]
{
    If ..BadName(pName) || ..HasChild(pNode.children, pName) Quit
    Set c = {"name":(pName), "type":"any"}
    Do c.%Set("opt", 1, "boolean")
    Do pNode.children.%Push(c)
}

/// Strips a cloned node down to its structure: the constraint keywords, enum, vals, pattern and every sub-schema key (cond, dep, additional, nots,
/// contains, dsch, pnames, alts, alls, fromAlt) are removed, recursively through children and items, and every descendant becomes optional.
/// Used when the fields of a branch or alternative are merged into the parent, where only their names and types are wanted.<br>
/// <var>pNode</var>: the node to strip; modified in place
ClassMethod Neutralize(pNode) [ Private ]
{
    Set kl = ..ConstraintKeys()
    For i = 1:1:$ListLength(kl) { Do pNode.%Remove($List(kl, i)) }
    For k = "enum", "vals", "pattern", "cond", "dep", "additional", "nots", "contains", "dsch", "pnames", "alts", "alls", "fromAlt" { Do pNode.%Remove(k) }
    If (pNode.type = "object") && $IsObject(pNode.%Get("children")) {
        Set it = pNode.children.%GetIterator()
        While it.%GetNext(.j, .c) {
            Do c.%Set("opt", 1, "boolean")
            Do ..Neutralize(c)
        }
    } ElseIf (pNode.type = "array") && $IsObject(pNode.%Get("items")) {
        Do ..Neutralize(pNode.items)
    }
}

/// Deep-copies a field-tree node by serializing it to JSON text and parsing the result.<br>
/// <var>pNode</var>: the %DynamicObject or %DynamicArray to copy<br>
/// Returns: an independent copy
ClassMethod CloneNode(pNode) As %DynamicObject [ Private ]
{
    Set s = ##class(%Stream.TmpCharacter).%New()
    Do pNode.%ToJSON(s)
    Do s.Rewind()
    Quit ##class(%DynamicAbstractObject).%FromJSON(s)
}

/// Returns whether a children array already holds a node with a given name.<br>
/// <var>pChildren</var>: the children %DynamicArray of an object node<br>
/// <var>pName</var>: the field name to look for<br>
/// Returns: 1 when found, otherwise 0
ClassMethod HasChild(pChildren, pName As %String) As %Boolean [ Private ]
{
    Set found = 0
    Set it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) {
        If c.name = pName { Set found = 1  Quit }
    }
    Quit found
}

// ---------------- Warnings and display ----------------

/// Records a message in the process-private warning log ^||JVDoc.Warn; an identical message (compared on its first 400 characters) is counted instead of stored again.<br>
/// <var>pText</var>: the message text; a text starting with "info:" is shown by Report as INFO rather than WARN
ClassMethod Warn(pText As %String)
{
    Set key = $Extract(pText, 1, 400)
    If $Data(^||JVDoc.Warn("t", key)) {
        Set ^||JVDoc.Warn("t", key) = ^||JVDoc.Warn("t", key) + 1
        Quit
    }
    Set w = $Increment(^||JVDoc.Warn)
    Set ^||JVDoc.Warn(w) = pText
    Set ^||JVDoc.Warn("t", key) = 1
}

/// Prints the warning log of the last import or inference to the current device: one WARN or INFO line per distinct message, with its repeat count as (xN), then the number of messages.
ClassMethod Report()
{
    Set k = "", n = 0
    For {
        Set k = $Order(^||JVDoc.Warn(k), 1, v)
        If (k = "") || (k '= +k) Quit
        Set n = n + 1
        Set c = +$Get(^||JVDoc.Warn("t", $Extract(v, 1, 400)))
        Write $Select($Extract(v, 1, 5) = "info:":"INFO: "_$ZStrip($Extract(v, 6, *), "<W"), 1:"WARN: "_v), $Select(c > 1:"  (x"_c_")", 1:""), !
    }
    Write n, " message(s)", !
}

/// Prints the field tree of a DocType with indentation: name, [] for an array, the type, ? for optional, (truncated), the constraint summary
/// (for arrays also that of the items) and the number of if/then/else rules; constraints on the root appear on a separate (root) line.
/// Prints "unknown DocType" when there is no such tree.<br>
/// <var>pDocType</var>: the DocType to print ("Cat:Name"); used only on the top-level call<br>
/// <var>pChildren</var>: internal: the children array to print on recursive calls; leave empty<br>
/// <var>pIndent</var>: internal: indentation level on recursive calls (2 spaces per level)
ClassMethod Outline(pDocType As %String, pChildren As %DynamicArray = "", pIndent As %Integer = 0)
{
    If '$IsObject(pChildren) {
        Set t = ##class(JVDoc.Schema).GetTree(pDocType)
        If '$IsObject(t) Write "unknown DocType", ! Quit
        Set rc = ..ConstraintText(t)
        If rc '= "" Write "(root)  ", rc, !
        If $IsObject(t.%Get("cond")) && t.cond.%Size() Write "(root has ", t.cond.%Size(), " conditional rule(s))", !
        Set pChildren = t.children
    }
    Set it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) {
        Set el = $Select(c.type = "array":c.items, 1:c)
        Write $Justify("", pIndent*2), c.name, $Select(c.type = "array":"[]", 1:""), " : ", el.type
        Write $Select(+c.opt:"  ?", 1:""), $Select(+el.truncated:"  (truncated)", 1:"")
        Set cs = ..ConstraintText(c)
        If c.type = "array" {
            Set es = ..ConstraintText(el)
            If es '= "" Set cs = cs_" items"_es
        }
        If cs '= "" Write "  ", cs
        If $IsObject(el.%Get("cond")) && el.cond.%Size() Write "  [if/then/else x", el.cond.%Size(), "]"
        Write !
        If (el.type = "object") && $IsObject(el.children) Do ..Outline("", el.children, pIndent+1)
    }
}

/// Summarizes what is stored on a node: the constraint keywords, const, dependentRequired, additionalProperties, the dependentSchemas keys,
/// propertyNames, not, contains, and the number of oneOf/anyOf alternatives and allOf members.<br>
/// <var>pNode</var>: a field-tree node<br>
/// Returns: "{key=value,...}", or "" when the node carries none of these
ClassMethod ConstraintText(pNode) As %String
{
    Set txt = "", kl = ..ConstraintKeys()
    For i = 1:1:$ListLength(kl) {
        Set k = $List(kl, i)
        If k = "const" Continue
        Set t = pNode.%GetTypeOf(k)
        If t = "unassigned" Continue
        Set v = pNode.%Get(k)
        If t = "boolean" Set v = $Select(v:"true", 1:"false")
        Set txt = txt_$Select(txt = "":"", 1:",")_k_"="_v
    }
    If pNode.%IsDefined("const") Set txt = txt_$Select(txt = "":"", 1:",")_"const="_..ConstText(pNode)
    If $IsObject(pNode.%Get("dep")) && pNode.dep.%GetIterator().%GetNext() Set txt = txt_$Select(txt = "":"", 1:",")_"dependentRequired="_..JSONStr(pNode.dep)
    Set at = pNode.%GetTypeOf("additional")
    If at = "boolean" Set txt = txt_$Select(txt = "":"", 1:",")_"additionalProperties=false"
    If at = "object" Set txt = txt_$Select(txt = "":"", 1:",")_"additionalProperties="_pNode.additional.type
    If $IsObject(pNode.%Get("dsch")) && pNode.dsch.%Size() {
        Set keys = "", itx = pNode.dsch.%GetIterator()
        While itx.%GetNext(.xk, .xe) { Set keys = keys_$Select(keys = "":"", 1:"|")_xe.key }
        Set txt = txt_$Select(txt = "":"", 1:",")_"dependentSchemas="_keys
    }
    If $IsObject(pNode.%Get("pnames")) Set txt = txt_$Select(txt = "":"", 1:",")_"propertyNames="_..SubText(pNode.pnames)
    If $IsObject(pNode.%Get("nots")) {
        Set itn = pNode.nots.%GetIterator()
        While itn.%GetNext(.nk, .nsub) { Set txt = txt_$Select(txt = "":"", 1:",")_"not="_..SubText(nsub) }
    }
    If $IsObject(pNode.%Get("contains")) Set txt = txt_$Select(txt = "":"", 1:",")_"contains="_..SubText(pNode.contains)
    If $IsObject(pNode.%Get("alts")) {
        Set itg = pNode.alts.%GetIterator()
        While itg.%GetNext(.gk, .ge) { Set txt = txt_$Select(txt = "":"", 1:",")_ge.kw_"="_ge.list.%Size() }
    }
    If $IsObject(pNode.%Get("alls")) && pNode.alls.%Size() Set txt = txt_$Select(txt = "":"", 1:",")_"allOf="_pNode.alls.%Size()
    Quit $Select(txt '= "":"{"_txt_"}", 1:"")
}

/// Returns the display text of a sub-schema node (not, contains, propertyNames).<br>
/// <var>pSub</var>: the sub-schema node<br>
/// Returns: its type followed by its constraint summary, pattern and enum
ClassMethod SubText(pSub) As %String
{
    Set txt = pSub.type_..ConstraintText(pSub)
    If pSub.%Get("pattern") '= "" Set txt = txt_" pattern="_pSub.pattern
    If $IsObject(pSub.%Get("enum")) Set txt = txt_" enum="_..JSONStr(pSub.enum)
    Quit txt
}

/// Returns the display text of a node's const value.<br>
/// <var>pNode</var>: a field-tree node that defines const<br>
/// Returns: strings quoted, booleans as true/false, null as null, objects and arrays as JSON, numbers as written
ClassMethod ConstText(pNode) As %String
{
    Set t = pNode.%GetTypeOf("const"), v = pNode.%Get("const")
    If (t = "object") || (t = "array") Quit ..JSONStr(v)
    If t = "null" Quit "null"
    If t = "boolean" Quit $Select(v:"true", 1:"false")
    If t = "string" Quit """"_v_""""
    Quit v
}

// ---------------- Helpers ----------------

/// Returns whether a property name cannot appear in a VDoc path.<br>
/// <var>pName</var>: the property name<br>
/// Returns: 1 when it is empty, contains . ( ) { }, or starts with $ (schema metadata keys); otherwise 0
ClassMethod BadName(pName As %String) As %Boolean
{
    If pName = "" Quit 1
    If $Extract(pName) = "$" Quit 1
    Quit (pName [ ".") || (pName [ "(") || (pName [ ")") || (pName [ "{") || (pName [ "}")
}

/// Returns the constraint keywords that are copied verbatim, with their JSON type, from a schema into the field-tree node.<br>
/// Returns: $ListBuild of minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf, minLength, maxLength, minItems, maxItems, uniqueItems,
/// minProperties, maxProperties, minContains, maxContains and const
ClassMethod ConstraintKeys() As %List
{
    Quit $ListBuild("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "minItems", "maxItems", "uniqueItems", "minProperties", "maxProperties", "minContains", "maxContains", "const")
}

/// Returns whether a value equals an element of an array.<br>
/// <var>pArr</var>: the %DynamicArray to search; a non-object gives 0<br>
/// <var>pVal</var>: the value to look for<br>
/// Returns: 1 when found, otherwise 0
ClassMethod InList(pArr, pVal) As %Boolean
{
    If '$IsObject(pArr) Quit 0
    Set it = pArr.%GetIterator()
    While it.%GetNext(.k, .v) { If v = pVal Quit }
    Quit ($Get(v) = pVal)
}

/// Concatenates the elements of an array with commas (the vals display string of an enum).<br>
/// <var>pArr</var>: the %DynamicArray<br>
/// Returns: the comma-joined string; "" for an empty array
ClassMethod Join(pArr) As %String
{
    Set r = "", it = pArr.%GetIterator()
    While it.%GetNext(.k, .v) { Set r = r_$Select(r = "":"", 1:",")_v }
    Quit r
}

/// Serializes a dynamic object or array to a string.<br>
/// <var>pObj</var>: the %DynamicAbstractObject to serialize<br>
/// Returns: the JSON text, truncated at the maximum local string length
ClassMethod JSONStr(pObj) As %String
{
    Set s = ##class(%Stream.TmpCharacter).%New()
    Do pObj.%ToJSON(s)
    Do s.Rewind()
    Quit s.Read($$$MaxLocalLength)
}

/// Copies one key from one dynamic object to another, preserving its JSON type (null included); does nothing when the key is absent.<br>
/// <var>pFrom</var>: the source %DynamicObject<br>
/// <var>pTo</var>: the target %DynamicObject; modified in place<br>
/// <var>pKey</var>: the key to copy
ClassMethod CopyTyped(pFrom, pTo, pKey As %String)
{
    Set t = pFrom.%GetTypeOf(pKey)
    If t = "unassigned" Quit
    Set v = pFrom.%Get(pKey)
    If (t = "object") || (t = "array") {
        Do pTo.%Set(pKey, v)
    } ElseIf t = "null" {
        Do pTo.%Set(pKey, "", "null")
    } Else {
        Do pTo.%Set(pKey, v, t)
    }
}

}
