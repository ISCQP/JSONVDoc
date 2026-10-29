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
    Set tSC = $$$OK
    Try {
        Set tRoot = ..Node("", pSchema, pSchema, 0, pMaxDepth)
        If tRoot.type '= "object" Throw ##class(%Exception.General).%New("Root", 5001, , "root schema must be an object")
        Set tSC = ##class(JVDoc.Schema).Save(pCategory, pName, tRoot)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
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
        Set tSch = {}.%FromJSON(tS)
        Set tSC = ..FromJSONSchema(pCategory, pName, tSch, pMaxDepth)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Imports several sub-schemas of one JSON Schema, each as a separate DocType named by its key; $ref between them is resolved against the whole schema.
/// Entries that are not objects, whose key is empty or contains ":" or "|", or that fail to import are skipped with a warning.
/// The warning log is reset first and records an "info: created" line per DocType.<br>
/// <var>pCategory</var>: category shared by every DocType created<br>
/// <var>pSchema</var>: the whole JSON Schema as a %DynamicObject<br>
/// <var>pSource</var>: where the sub-schemas are taken from:
/// "defs" (default) - one DocType per entry of $defs, or of definitions (draft-04 to draft-07) when $defs is absent; use it when the file is a catalog of models;
/// "properties" - one DocType per property of the root schema, named by the property key; use it when the root is an envelope whose properties are the messages.
/// Any other value is treated as "defs"<br>
/// <var>pNames</var>: comma-separated keys to import; empty imports all<br>
/// <var>pRootName</var>: when non-empty, the root schema itself is also imported as pCategory:pRootName<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off (default 8)<br>
/// Returns: $$$OK when at least one DocType was created; an error when the source container is missing, the root import fails, or nothing was created
ClassMethod FromBundle(pCategory As %String, pSchema As %DynamicObject, pSource As %String = "defs", pNames As %String = "", pRootName As %String = "", pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
    Set tSC = $$$OK
    Try {
        If pSource = "properties" {
            Set tCont = pSchema.%Get("properties")
            Set tWhat = "properties"
        } Else {
            Set tCont = pSchema.%Get("$defs")
            If '$IsObject(tCont) Set tCont = pSchema.%Get("definitions")
            Set tWhat = "$defs or definitions"
        }
        If '$IsObject(tCont) Throw ##class(%Exception.General).%New("Bundle", 5001, , "no "_tWhat_" found in the schema")
        Set tWant = $Select(pNames = "":"", 1:","_pNames_",")
        Set tMade = 0
        If pRootName '= "" {
            Set tS0 = ..SaveSub(pCategory, pRootName, pSchema, pSchema, pMaxDepth)
            If $$$ISERR(tS0) Throw ##class(%Exception.General).%New("Bundle", 5001, , "root: "_$System.Status.GetErrorText(tS0))
            Set tMade = tMade + 1
        }
        Set tIt = tCont.%GetIterator()
        While tIt.%GetNext(.tK, .tSub, .tT) {
            If (tWant '= "") && (tWant '[ (","_tK_",")) Continue
            If tT '= "object" {
                Do ..Warn("skip '"_tK_"' (not a schema object)")
                Continue
            }
            If (tK [ ":") || (tK [ "|") || (tK = "") {
                Do ..Warn("skip '"_tK_"' (name not usable in a DocType)")
                Continue
            }
            Set tS1 = ..SaveSub(pCategory, tK, tSub, pSchema, pMaxDepth)
            If $$$ISERR(tS1) {
                Do ..Warn("skip '"_tK_"': "_$System.Status.GetErrorText(tS1))
                Continue
            }
            Set tMade = tMade + 1
        }
        If tMade = 0 Throw ##class(%Exception.General).%New("Bundle", 5001, , "no DocType was created")
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Reads a UTF-8 JSON Schema file and imports it with FromBundle.<br>
/// <var>pCategory</var>: category shared by every DocType created<br>
/// <var>pFile</var>: path of the JSON Schema file on the server<br>
/// <var>pSource</var>: where the sub-schemas are taken from:
/// "defs" (default) - one DocType per entry of $defs, or of definitions (draft-04 to draft-07) when $defs is absent; use it when the file is a catalog of models;
/// "properties" - one DocType per property of the root schema, named by the property key; use it when the root is an envelope whose properties are the messages.
/// Any other value is treated as "defs"<br>
/// <var>pNames</var>: comma-separated keys to import; empty imports all<br>
/// <var>pRootName</var>: when non-empty, the root schema is also imported under this name<br>
/// <var>pMaxDepth</var>: nesting depth at which recursion is cut off (default 8)<br>
/// Returns: $$$OK when at least one DocType was created; an error when the file is empty, unreadable or not valid JSON, or FromBundle fails
ClassMethod FromBundleFile(pCategory As %String, pFile As %String, pSource As %String = "defs", pNames As %String = "", pRootName As %String = "", pMaxDepth As %Integer = 8) As %Status
{
    Kill ^||JVDoc.Warn
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
        Set tSch = {}.%FromJSON(tS)
        Set tSC = ..FromBundle(pCategory, tSch, pSource, pNames, pRootName, pMaxDepth)
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
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
    Set tNode = ..Node("", pSub, pRoot, 0, pMaxDepth)
    If tNode.type '= "object" Quit $$$ERROR($$$GeneralError, "schema is not an object (type "_tNode.type_")")
    Set tSC = ##class(JVDoc.Schema).Save(pCategory, pName, tNode)
    If $$$ISOK(tSC) Do ..Warn("info: created "_pCategory_":"_pName)
    Quit tSC
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
    Set tOut = {"properties":{}, "required":[], "cond":[], "dep":{}, "nl":[], "ds":[], "alts":[], "alls":[], "altProps":{}}
    If ('$IsObject(pSch)) || (pDepth > 10) Quit tOut
    Set tSch = ..Deref(pSch, pRoot)
    Set tFl = $ListBuild("type", "items", "description", "enum", "pattern")
    For tI = 1:1:$ListLength(tFl) {
        Set tF = $List(tFl, tI)
        If tSch.%IsDefined(tF) Do tOut.%Set(tF, tSch.%Get(tF))
    }
    Set tCl = ..ConstraintKeys()
    For tI = 1:1:$ListLength(tCl) { Do ..CopyTyped(tSch, tOut, $List(tCl, tI)) }
    // additionalProperties: only the value written directly on this node is used (not from allOf/oneOf/anyOf/if/then/else)
    Do ..CopyTyped(tSch, tOut, "additionalProperties")
    Set tCsub = tSch.%Get("contains")
    If $IsObject(tCsub) && ($ClassName(tCsub) = "%Library.DynamicObject") Do tOut.%Set("contains", tCsub)
    Set tNsub = tSch.%Get("not")
    If $IsObject(tNsub) && ($ClassName(tNsub) = "%Library.DynamicObject") Do tOut.nl.%Push(tNsub)
    Set tPsub = tSch.%Get("propertyNames")
    If $IsObject(tPsub) && ($ClassName(tPsub) = "%Library.DynamicObject") Do tOut.%Set("pn", tPsub)
    If $IsObject(tSch.%Get("properties")) {
        Set tIt = tSch.properties.%GetIterator()
        While tIt.%GetNext(.tK, .tV) { Do tOut.properties.%Set(tK, tV) }
    }
    If $IsObject(tSch.%Get("required")) {
        Set tIt = tSch.required.%GetIterator()
        While tIt.%GetNext(.tK, .tV) { Do tOut.required.%Push(tV) }
    }
    For tDk = "dependentRequired", "dependencies" {
        Set tDsrc = tSch.%Get(tDk)
        If $IsObject(tDsrc) && ($ClassName(tDsrc) = "%Library.DynamicObject") {
            Set tItd = tDsrc.%GetIterator()
            While tItd.%GetNext(.tK, .tV, .tT) {
                If tT = "array" {
                    Do ..AddDep(tOut.dep, tK, tV)
                } ElseIf (tDk = "dependencies") && (tT = "object") {
                    Do ..AddDs(tOut.ds, tK, tV)
                }
            }
        }
    }
    Set tDss = tSch.%Get("dependentSchemas")
    If $IsObject(tDss) && ($ClassName(tDss) = "%Library.DynamicObject") {
        Set tItd = tDss.%GetIterator()
        While tItd.%GetNext(.tK, .tV, .tT) { If tT = "object" Do ..AddDs(tOut.ds, tK, tV) }
    }
    Set tIfs = tSch.%Get("if")
    If $IsObject(tIfs) {
        Set tCe = {}
        Do tCe.%Set("if", tIfs)
        If $IsObject(tSch.%Get("then")) Do tCe.%Set("then", tSch.%Get("then"))
        If $IsObject(tSch.%Get("else")) Do tCe.%Set("else", tSch.%Get("else"))
        Do tOut.cond.%Push(tCe)
    }
    // allOf members are stored as 'alls' for validation; oneOf/anyOf alternatives are stored as 'alts', and their fields are merged into the parent (marked as fromAlt)
    Set tAltKinds = "", tAltAny = 0
    For tKw = "allOf", "oneOf", "anyOf" {
        If '$IsObject(tSch.%Get(tKw)) Continue
        Set tGroup = []
        Set tIt = tSch.%Get(tKw).%GetIterator()
        While tIt.%GetNext(.tN, .tAlt) {
            Set tA = ..Normalize(tAlt, pRoot, pDepth+1)
            If $IsObject(tAlt) && ($ClassName(tAlt) = "%Library.DynamicObject") {
                If tKw = "allOf" { Do tOut.alls.%Push(tAlt) } Else { Do tGroup.%Push(tAlt) }
            }
            If (tKw '= "allOf") && ..HasKind(tA) {
                Set tAk = ..TypeOf(tA)
                If tAk = "any" {
                    Set tAltAny = 1
                } Else {
                    Set tAk = $Select(tAk = "integer":"number", 1:tAk)
                    If '$ListFind(tAltKinds, tAk) Set tAltKinds = tAltKinds_$ListBuild(tAk)
                }
            }
            Set tIt2 = tA.properties.%GetIterator()
            While tIt2.%GetNext(.tK, .tV) {
                If 'tOut.properties.%IsDefined(tK) {
                    Do tOut.properties.%Set(tK, tV)
                    If (tKw '= "allOf") || tA.altProps.%IsDefined(tK) Do tOut.altProps.%Set(tK, 1, "boolean")
                }
            }
            If tKw = "allOf" {
                Set tIt2 = tA.required.%GetIterator()
                While tIt2.%GetNext(.tJ, .tR) { Do tOut.required.%Push(tR) }
            }
            For tF = "type", "items", "description" {
                If ('tOut.%IsDefined(tF)) && tA.%IsDefined(tF) Do tOut.%Set(tF, tA.%Get(tF))
            }
        }
        If (tKw '= "allOf") && tGroup.%Size() {
            Set tGe = {}
            Do tGe.%Set("kw", tKw)
            Do tGe.%Set("list", tGroup)
            Do tOut.alts.%Push(tGe)
        }
    }
    If tAltAny || ($ListLength(tAltKinds) > 1) {
        Do tOut.%Set("type", "any")
    } ElseIf ($ListLength(tAltKinds) = 1) && 'tSch.%IsDefined("type") {
        Do tOut.%Set("type", $List(tAltKinds, 1))
    }
    Quit tOut
}

/// Follows a $ref chain (up to 20 levels) to the referenced schema. Only in-document references are supported: "#", JSON pointers "#/...",
/// and "#name" anchors ($anchor or draft-07 $id: "#name"). An external or unresolved reference stops the chain with a warning, so the node becomes any.<br>
/// <var>pSch</var>: the schema, possibly carrying $ref<br>
/// <var>pRoot</var>: the whole schema document that references are resolved against<br>
/// Returns: the referenced schema, or the last schema reached when the chain could not be followed further
ClassMethod Deref(pSch, pRoot)
{
    Set tN = 0
    While $IsObject(pSch) && pSch.%IsDefined("$ref") && ($Increment(tN) <= 20) {
        Set tRef = pSch.%Get("$ref")
        Set tCur = ""
        If tRef = "#" {
            Set tCur = pRoot
        } ElseIf $Extract(tRef, 1, 2) = "#/" {
            Set tCur = pRoot
            For tI = 2:1:$Length(tRef, "/") {
                Set tSeg = $Replace($Replace($Piece(tRef, "/", tI), "~1", "/"), "~0", "~")
                If '$IsObject(tCur) || 'tCur.%IsDefined(tSeg) { Set tCur = "" Quit }
                Set tCur = tCur.%Get(tSeg)
            }
        } ElseIf ($Extract(tRef) = "#") && ($Length(tRef) > 1) {
            Set tCur = ..FindAnchor(pRoot, $Extract(tRef, 2, *))
        } Else {
            Do ..Warn("external $ref not supported, typed as any: "_tRef)
            Quit
        }
        If '$IsObject(tCur) {
            Do ..Warn("unresolved $ref, typed as any: "_tRef)
            Quit
        }
        Set pSch = tCur
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
    Set tIsObj = ($ClassName(pNode) = "%Library.DynamicObject")
    If tIsObj && ((pNode.%Get("$anchor") = pName) || (pNode.%Get("$id") = ("#"_pName))) Quit pNode
    Set tFound = ""
    Set tIt = pNode.%GetIterator()
    While tIt.%GetNext(.tK, .tV) {
        If '$IsObject(tV) Continue
        If tIsObj && ((tK = "enum") || (tK = "const") || (tK = "examples") || (tK = "default")) Continue
        Set tFound = ..FindAnchor(tV, pName, pDepth+1)
        If tFound '= "" Quit
    }
    Quit tFound
}

/// Returns the effective type of a normalized schema. For a type array, its single non-null type, or any when it mixes kinds (integer and number
/// count as one). When no type is declared, object or array is inferred from the keywords present (properties, required, dep, ds, pn, minProperties,
/// maxProperties, additionalProperties give object; items, contains, minItems, maxItems, uniqueItems give array).<br>
/// <var>pS</var>: a schema in the form produced by Normalize<br>
/// Returns: "object", "array", "string", "integer", "number", "boolean" or "any"
ClassMethod TypeOf(pS) As %String
{
    Set tT = pS.%Get("type")
    If $IsObject(tT) {
        Set tIt = tT.%GetIterator(), tFirst = "", tKinds = ""
        While tIt.%GetNext(.tK, .tV) {
            If tV = "null" Continue
            If tFirst = "" Set tFirst = tV
            Set tG = $Select(tV = "integer":"number", 1:tV)
            If '$ListFind(tKinds, tG) Set tKinds = tKinds_$ListBuild(tG)
        }
        If $ListLength(tKinds) > 1 Quit "any"
        Set tT = tFirst
    }
    If (tT = "") || (tT = "null") {
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
    Quit tT
}

/// Returns whether a normalized oneOf/anyOf alternative declares a concrete kind.<br>
/// <var>pAlt</var>: the alternative in the form produced by Normalize<br>
/// Returns: 1 when it has a non-null type, or a type that TypeOf can infer; 0 for a null-only alternative or one that would be any
ClassMethod HasKind(pAlt) As %Boolean [ Private ]
{
    Set tT = pAlt.%Get("type")
    If tT = "null" Quit 0
    If tT '= "" Quit 1
    Quit (..TypeOf(pAlt) '= "any")
}

/// Merges dependent property names into one entry of a dep map (dependentRequired), skipping duplicates and non-string entries.<br>
/// <var>pDep</var>: the dep %DynamicObject of a normalized schema; modified in place<br>
/// <var>pKey</var>: the property whose presence requires the others<br>
/// <var>pNames</var>: %DynamicArray of the required property names
ClassMethod AddDep(pDep, pKey As %String, pNames) [ Private ]
{
    If 'pDep.%IsDefined(pKey) Do pDep.%Set(pKey, [])
    Set tCur = pDep.%Get(pKey)
    Set tIt = pNames.%GetIterator()
    While tIt.%GetNext(.tI, .tNm, .tT) {
        If (tT = "string") && '..InList(tCur, tNm) Do tCur.%Push(tNm)
    }
}

/// Appends a {key, sch} entry to the ds list of a normalized schema (dependentSchemas and the draft-07 dependencies object form).<br>
/// <var>pArr</var>: the ds %DynamicArray; modified in place<br>
/// <var>pKey</var>: the property whose presence activates the sub-schema<br>
/// <var>pSub</var>: the dependent sub-schema
ClassMethod AddDs(pArr, pKey As %String, pSub) [ Private ]
{
    Set tE = {}
    Do tE.%Set("key", pKey)
    Do tE.%Set("sch", pSub)
    Do pArr.%Push(tE)
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
    Set tS = ..Normalize(pSch, pRoot, 0)
    Set tType = ..TypeOf(tS)
    Set tNode = {"name":(pName), "type":(tType)}
    If tS.%IsDefined("description") Do tNode.%Set("desc", tS.description)
    If $IsObject(tS.%Get("enum")) {
        Do tNode.%Set("vals", ..Join(tS.enum))
        Do tNode.%Set("enum", tS.enum)
    }
    If tS.%Get("pattern") '= "" Do tNode.%Set("pattern", tS.%Get("pattern"))
    Set tCl = ..ConstraintKeys()
    For tI = 1:1:$ListLength(tCl) { Do ..CopyTyped(tS, tNode, $List(tCl, tI)) }
    If tType = "object" {
        Do ..BuildObject(tS, tNode, pRoot, pDepth, pMax)
    } ElseIf tType = "array" {
        Set tItem = {}
        If tS.%IsDefined("items") && $IsObject(tS.items) && ($ClassName(tS.items) = "%Library.DynamicObject") Set tItem = tS.items
        Set tNode.items = ..Node("", tItem, pRoot, pDepth+1, pMax)
    }
    // propertyNames: the sub-schema is built into a node that is checked against every property name
    If (tType = "object") && $IsObject(tS.%Get("pn")) {
        If pDepth >= pMax {
            Do ..Warn("propertyNames skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            Set tNode.pnames = ..Node("", tS.pn, pRoot, pDepth+1, pMax)
        }
    }
    // not / contains: each sub-schema is built into its own node
    Set tHasCont = ((tType = "array") && $IsObject(tS.%Get("contains")))
    If tS.nl.%Size() || tHasCont {
        If pDepth >= pMax {
            Do ..Warn("not/contains skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            If tS.nl.%Size() {
                Set tNode.nots = []
                Set tItn = tS.nl.%GetIterator()
                While tItn.%GetNext(.tNk, .tNsub) { Do tNode.nots.%Push(..Node("", tNsub, pRoot, pDepth+1, pMax)) }
            }
            If tHasCont Set tNode.contains = ..Node("", tS.contains, pRoot, pDepth+1, pMax)
        }
    }
    // oneOf/anyOf alternatives and allOf members: each becomes its own node and is evaluated independently at validation time
    If tS.alts.%Size() || tS.alls.%Size() {
        If pDepth >= pMax {
            Do ..Warn("oneOf/anyOf/allOf skipped at depth "_pDepth_" under '"_pName_"'")
        } Else {
            If tS.alts.%Size() {
                Set tNode.alts = []
                Set tItg = tS.alts.%GetIterator()
                While tItg.%GetNext(.tGk, .tGe) {
                    Set tGn = {}
                    Do tGn.%Set("kw", tGe.kw)
                    Set tGl = []
                    Set tIta = tGe.list.%GetIterator()
                    While tIta.%GetNext(.tAk, .tAsub) { Do tGl.%Push(..Node("", tAsub, pRoot, pDepth+1, pMax)) }
                    Do tGn.%Set("list", tGl)
                    Do tNode.alts.%Push(tGn)
                }
            }
            If tS.alls.%Size() {
                Set tNode.alls = []
                Set tItm = tS.alls.%GetIterator()
                While tItm.%GetNext(.tMk, .tMsub) { Do tNode.alls.%Push(..Node("", tMsub, pRoot, pDepth+1, pMax)) }
            }
        }
    }
    Quit tNode
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
    Set tIt = pS.properties.%GetIterator()
    While tIt.%GetNext(.tK, .tV) {
        If ..BadName(tK) {
            Do ..Warn("skip property '"_tK_"' under '"_pNode.name_"' (name not usable in a VDoc path)")
            Continue
        }
        Set tC = ..Node(tK, tV, pRoot, pDepth+1, pMax)
        If '..InList(pS.required, tK) Do tC.%Set("opt", 1, "boolean")
        If pS.altProps.%IsDefined(tK) Do tC.%Set("fromAlt", 1, "boolean")
        Do pNode.children.%Push(tC)
    }
    // Names listed in required but absent from properties are added as 'any' fields
    Set tIt = pS.required.%GetIterator()
    While tIt.%GetNext(.tK, .tRn) {
        If ..BadName(tRn) || ..HasChild(pNode.children, tRn) Continue
        Do pNode.children.%Push({"name":(tRn), "type":"any"})
    }
    // dependentRequired: the key and its dependent names are added as optional any fields when missing from the tree
    Set tDepn = pS.%Get("dep")
    If $IsObject(tDepn) && tDepn.%GetIterator().%GetNext() {
        Set tItd = tDepn.%GetIterator()
        While tItd.%GetNext(.tK, .tNames) {
            Do ..EnsureAny(pNode, tK)
            Set tItn = tNames.%GetIterator()
            While tItn.%GetNext(.tJ, .tNm) { Do ..EnsureAny(pNode, tNm) }
        }
        Do pNode.%Set("dep", ..CloneNode(tDepn))
    }
    // dependentSchemas: each key gets a child node; the node's fields are merged into the parent as optional fields without constraints, and the key itself is added as an any field when absent
    If pS.ds.%Size() {
        Set pNode.dsch = []
        Set tItx = pS.ds.%GetIterator()
        While tItx.%GetNext(.tXk, .tXe) {
            Set tDn = ..CondNode(tXe.sch, pRoot, pDepth, pMax)
            Do ..EnsureAny(pNode, tXe.key)
            Do ..UnionInto(pNode, tDn)
            Set tEn = {}
            Do tEn.%Set("key", tXe.key)
            Do tEn.%Set("node", tDn)
            Do pNode.dsch.%Push(tEn)
        }
    }
    // additionalProperties: only false and a schema object need to be stored; ignored inside conditional branches
    If 'pBranch {
        Set tAt = pS.%GetTypeOf("additionalProperties")
        If tAt = "boolean" {
            If 'pS.%Get("additionalProperties") Do pNode.%Set("additional", 0, "boolean")
        } ElseIf tAt = "object" {
            Do pNode.%Set("additional", ..Node("", pS.%Get("additionalProperties"), pRoot, pDepth+1, pMax))
        }
    }
    If pS.cond.%Size() {
        Set pNode.cond = []
        Set tIt = pS.cond.%GetIterator()
        While tIt.%GetNext(.tK, .tCe) { Do ..BuildCond(tCe, pNode, pRoot, pDepth, pMax) }
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
    Set tIfs = pCE.%Get("if")
    If '$IsObject(tIfs) || ($ClassName(tIfs) '= "%Library.DynamicObject") Quit
    Set tEntry = {}
    Set tIfn = ..CondNode(tIfs, pRoot, pDepth, pMax)
    Do tEntry.%Set("if", tIfn)
    Do ..UnionInto(pNode, tIfn)
    For tBr = "then", "else" {
        Set tSub = pCE.%Get(tBr)
        If $IsObject(tSub) && ($ClassName(tSub) = "%Library.DynamicObject") {
            Set tBn = ..CondNode(tSub, pRoot, pDepth, pMax)
            Do tEntry.%Set(tBr, tBn)
            Do ..UnionInto(pNode, tBn)
        }
    }
    Do pNode.cond.%Push(tEntry)
}

/// Builds an object node for an if/then/else branch or a dependentSchemas sub-schema; additionalProperties inside the branch is ignored.<br>
/// <var>pSub</var>: the raw branch sub-schema<br>
/// <var>pRoot</var>: the whole schema document, used to resolve $ref<br>
/// <var>pDepth</var>: depth of the owning object node; the branch's children are built one level deeper<br>
/// <var>pMax</var>: depth limit at which recursion is cut off<br>
/// Returns: an unnamed object node with its children
ClassMethod CondNode(pSub, pRoot, pDepth, pMax) As %DynamicObject [ Private ]
{
    Set tS = ..Normalize(pSub, pRoot, 0)
    Set tN = {"name":"", "type":"object"}
    Do ..BuildObject(tS, tN, pRoot, pDepth+1, pMax, 1)
    Quit tN
}

/// Adds the children of one object node to another, skipping names already present; each added child is a clone stripped by Neutralize and marked opt.<br>
/// <var>pTarget</var>: the object node that receives the children; modified in place<br>
/// <var>pSource</var>: the object node whose children are copied
ClassMethod UnionInto(pTarget, pSource) [ Private ]
{
    Set tIt = pSource.children.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        If ..HasChild(pTarget.children, tC.name) Continue
        Set tC2 = ..CloneNode(tC)
        Do ..Neutralize(tC2)
        Do tC2.%Set("opt", 1, "boolean")
        Do pTarget.children.%Push(tC2)
    }
}

/// Adds an optional any child to an object node unless the name is unusable in a path (BadName) or already present.<br>
/// <var>pNode</var>: the object node; modified in place<br>
/// <var>pName</var>: the field name to add
ClassMethod EnsureAny(pNode, pName As %String) [ Private ]
{
    If ..BadName(pName) || ..HasChild(pNode.children, pName) Quit
    Set tC = {"name":(pName), "type":"any"}
    Do tC.%Set("opt", 1, "boolean")
    Do pNode.children.%Push(tC)
}

/// Strips a cloned node down to its structure: the constraint keywords, enum, vals, pattern and every sub-schema key (cond, dep, additional, nots,
/// contains, dsch, pnames, alts, alls, fromAlt) are removed, recursively through children and items, and every descendant becomes optional.
/// Used when the fields of a branch or alternative are merged into the parent, where only their names and types are wanted.<br>
/// <var>pNode</var>: the node to strip; modified in place
ClassMethod Neutralize(pNode) [ Private ]
{
    Set tKl = ..ConstraintKeys()
    For tI = 1:1:$ListLength(tKl) { Do pNode.%Remove($List(tKl, tI)) }
    For tK = "enum", "vals", "pattern", "cond", "dep", "additional", "nots", "contains", "dsch", "pnames", "alts", "alls", "fromAlt" { Do pNode.%Remove(tK) }
    If (pNode.type = "object") && $IsObject(pNode.%Get("children")) {
        Set tIt = pNode.children.%GetIterator()
        While tIt.%GetNext(.tJ, .tC) {
            Do tC.%Set("opt", 1, "boolean")
            Do ..Neutralize(tC)
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
    Set tS = ##class(%Stream.TmpCharacter).%New()
    Do pNode.%ToJSON(tS)
    Do tS.Rewind()
    Quit ##class(%DynamicAbstractObject).%FromJSON(tS)
}

/// Returns whether a children array already holds a node with a given name.<br>
/// <var>pChildren</var>: the children %DynamicArray of an object node<br>
/// <var>pName</var>: the field name to look for<br>
/// Returns: 1 when found, otherwise 0
ClassMethod HasChild(pChildren, pName As %String) As %Boolean [ Private ]
{
    Set tFound = 0
    Set tIt = pChildren.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        If tC.name = pName { Set tFound = 1  Quit }
    }
    Quit tFound
}

// ---------------- Warnings and display ----------------

/// Records a message in the process-private warning log ^||JVDoc.Warn; an identical message (compared on its first 400 characters) is counted instead of stored again.<br>
/// <var>pText</var>: the message text; a text starting with "info:" is shown by Report as INFO rather than WARN
ClassMethod Warn(pText As %String)
{
    Set tKey = $Extract(pText, 1, 400)
    If $Data(^||JVDoc.Warn("t", tKey)) {
        Set ^||JVDoc.Warn("t", tKey) = ^||JVDoc.Warn("t", tKey) + 1
        Quit
    }
    Set tW = $Increment(^||JVDoc.Warn)
    Set ^||JVDoc.Warn(tW) = pText
    Set ^||JVDoc.Warn("t", tKey) = 1
}

/// Prints the warning log of the last import or inference to the current device: one WARN or INFO line per distinct message, with its repeat count as (xN), then the number of messages.
ClassMethod Report()
{
    Set tK = "", tN = 0
    For {
        Set tK = $Order(^||JVDoc.Warn(tK), 1, tV)
        If (tK = "") || (tK '= +tK) Quit
        Set tN = tN + 1
        Set tC = +$Get(^||JVDoc.Warn("t", $Extract(tV, 1, 400)))
        Write $Select($Extract(tV, 1, 5) = "info:":"INFO: "_$ZStrip($Extract(tV, 6, *), "<W"), 1:"WARN: "_tV), $Select(tC > 1:"  (x"_tC_")", 1:""), !
    }
    Write tN, " message(s)", !
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
        Set tT = ##class(JVDoc.Schema).GetTree(pDocType)
        If '$IsObject(tT) Write "unknown DocType", ! Quit
        Set tRc = ..ConstraintText(tT)
        If tRc '= "" Write "(root)  ", tRc, !
        If $IsObject(tT.%Get("cond")) && tT.cond.%Size() Write "(root has ", tT.cond.%Size(), " conditional rule(s))", !
        Set pChildren = tT.children
    }
    Set tIt = pChildren.%GetIterator()
    While tIt.%GetNext(.tK, .tC) {
        Set tEl = $Select(tC.type = "array":tC.items, 1:tC)
        Write $Justify("", pIndent*2), tC.name, $Select(tC.type = "array":"[]", 1:""), " : ", tEl.type
        Write $Select(+tC.opt:"  ?", 1:""), $Select(+tEl.truncated:"  (truncated)", 1:"")
        Set tCs = ..ConstraintText(tC)
        If tC.type = "array" {
            Set tEs = ..ConstraintText(tEl)
            If tEs '= "" Set tCs = tCs_" items"_tEs
        }
        If tCs '= "" Write "  ", tCs
        If $IsObject(tEl.%Get("cond")) && tEl.cond.%Size() Write "  [if/then/else x", tEl.cond.%Size(), "]"
        Write !
        If (tEl.type = "object") && $IsObject(tEl.children) Do ..Outline("", tEl.children, pIndent+1)
    }
}

/// Summarizes what is stored on a node: the constraint keywords, const, dependentRequired, additionalProperties, the dependentSchemas keys,
/// propertyNames, not, contains, and the number of oneOf/anyOf alternatives and allOf members.<br>
/// <var>pNode</var>: a field-tree node<br>
/// Returns: "{key=value,...}", or "" when the node carries none of these
ClassMethod ConstraintText(pNode) As %String
{
    Set tTxt = "", tKl = ..ConstraintKeys()
    For tI = 1:1:$ListLength(tKl) {
        Set tK = $List(tKl, tI)
        If tK = "const" Continue
        Set tT = pNode.%GetTypeOf(tK)
        If tT = "unassigned" Continue
        Set tV = pNode.%Get(tK)
        If tT = "boolean" Set tV = $Select(tV:"true", 1:"false")
        Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_tK_"="_tV
    }
    If pNode.%IsDefined("const") Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"const="_..ConstText(pNode)
    If $IsObject(pNode.%Get("dep")) && pNode.dep.%GetIterator().%GetNext() Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"dependentRequired="_..JSONStr(pNode.dep)
    Set tAt = pNode.%GetTypeOf("additional")
    If tAt = "boolean" Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"additionalProperties=false"
    If tAt = "object" Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"additionalProperties="_pNode.additional.type
    If $IsObject(pNode.%Get("dsch")) && pNode.dsch.%Size() {
        Set tKeys = "", tItx = pNode.dsch.%GetIterator()
        While tItx.%GetNext(.tXk, .tXe) { Set tKeys = tKeys_$Select(tKeys = "":"", 1:"|")_tXe.key }
        Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"dependentSchemas="_tKeys
    }
    If $IsObject(pNode.%Get("pnames")) Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"propertyNames="_..SubText(pNode.pnames)
    If $IsObject(pNode.%Get("nots")) {
        Set tItn = pNode.nots.%GetIterator()
        While tItn.%GetNext(.tNk, .tNsub) { Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"not="_..SubText(tNsub) }
    }
    If $IsObject(pNode.%Get("contains")) Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"contains="_..SubText(pNode.contains)
    If $IsObject(pNode.%Get("alts")) {
        Set tItg = pNode.alts.%GetIterator()
        While tItg.%GetNext(.tGk, .tGe) { Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_tGe.kw_"="_tGe.list.%Size() }
    }
    If $IsObject(pNode.%Get("alls")) && pNode.alls.%Size() Set tTxt = tTxt_$Select(tTxt = "":"", 1:",")_"allOf="_pNode.alls.%Size()
    Quit $Select(tTxt '= "":"{"_tTxt_"}", 1:"")
}

/// Returns the display text of a sub-schema node (not, contains, propertyNames).<br>
/// <var>pSub</var>: the sub-schema node<br>
/// Returns: its type followed by its constraint summary, pattern and enum
ClassMethod SubText(pSub) As %String
{
    Set tTxt = pSub.type_..ConstraintText(pSub)
    If pSub.%Get("pattern") '= "" Set tTxt = tTxt_" pattern="_pSub.pattern
    If $IsObject(pSub.%Get("enum")) Set tTxt = tTxt_" enum="_..JSONStr(pSub.enum)
    Quit tTxt
}

/// Returns the display text of a node's const value.<br>
/// <var>pNode</var>: a field-tree node that defines const<br>
/// Returns: strings quoted, booleans as true/false, null as null, objects and arrays as JSON, numbers as written
ClassMethod ConstText(pNode) As %String
{
    Set tT = pNode.%GetTypeOf("const"), tV = pNode.%Get("const")
    If (tT = "object") || (tT = "array") Quit ..JSONStr(tV)
    If tT = "null" Quit "null"
    If tT = "boolean" Quit $Select(tV:"true", 1:"false")
    If tT = "string" Quit """"_tV_""""
    Quit tV
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
    Set tIt = pArr.%GetIterator()
    While tIt.%GetNext(.tK, .tV) { If tV = pVal Quit }
    Quit ($Get(tV) = pVal)
}

/// Concatenates the elements of an array with commas (the vals display string of an enum).<br>
/// <var>pArr</var>: the %DynamicArray<br>
/// Returns: the comma-joined string; "" for an empty array
ClassMethod Join(pArr) As %String
{
    Set tR = "", tIt = pArr.%GetIterator()
    While tIt.%GetNext(.tK, .tV) { Set tR = tR_$Select(tR = "":"", 1:",")_tV }
    Quit tR
}

/// Serializes a dynamic object or array to a string.<br>
/// <var>pObj</var>: the %DynamicAbstractObject to serialize<br>
/// Returns: the JSON text, truncated at the maximum local string length
ClassMethod JSONStr(pObj) As %String
{
    Set tS = ##class(%Stream.TmpCharacter).%New()
    Do pObj.%ToJSON(tS)
    Do tS.Rewind()
    Quit tS.Read($$$MaxLocalLength)
}

/// Copies one key from one dynamic object to another, preserving its JSON type (null included); does nothing when the key is absent.<br>
/// <var>pFrom</var>: the source %DynamicObject<br>
/// <var>pTo</var>: the target %DynamicObject; modified in place<br>
/// <var>pKey</var>: the key to copy
ClassMethod CopyTyped(pFrom, pTo, pKey As %String)
{
    Set tT = pFrom.%GetTypeOf(pKey)
    If tT = "unassigned" Quit
    Set tV = pFrom.%Get(pKey)
    If (tT = "object") || (tT = "array") {
        Do pTo.%Set(pKey, tV)
    } ElseIf tT = "null" {
        Do pTo.%Set(pKey, "", "null")
    } Else {
        Do pTo.%Set(pKey, tV, tT)
    }
}

}
