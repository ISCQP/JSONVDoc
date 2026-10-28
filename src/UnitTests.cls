/// Automated tests for the JVDoc package, built on %UnitTest.TestCase.
/// Every DocType the tests need is imported under the categories UT and UTB in OnBeforeAllTests and removed again in
/// OnAfterAllTests, together with every document, binding and search table row the tests created; Demo:* DocTypes and
/// other user data are never touched. Run the suite with Do ##class(JVDoc.UnitTests).Run() and re-run it after a product upgrade.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.UnitTests Extends %UnitTest.TestCase
{

/// IDs of the JVDoc.Document rows the tests saved; deleted in OnAfterAllTests
Property Docs As %String [ MultiDimensional ];

/// Runs this test class with %UnitTest.Manager without loading anything from disk and writes the summary to the current device
ClassMethod Run() As %Status
{
    If $Get(^UnitTestRoot) = "" Set ^UnitTestRoot = $System.Util.ManagerDirectory()_"Temp"
    Quit ##class(%UnitTest.Manager).DebugRunTestCase("", $classname(), "/noload/nodelete")
}

/// Imports every UT:* DocType the tests use; a failure here fails the whole class
Method OnBeforeAllTests() As %Status
{
    Set sc = ..Import("Order", {"type":"object","required":["order_id"],"properties":{"order_id":{"type":"string"},"total":{"type":"number"},"paid":{"type":"boolean"},"items":{"type":"array","items":{"type":"object","properties":{"sku":{"type":"string"},"qty":{"type":"integer"}}}}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Invoice", {"type":"object","properties":{"invoice_no":{"type":"string"},"amount":{"type":"number"},"settled":{"type":"boolean"},"lines":{"type":"array","items":{"type":"object","properties":{"code":{"type":"string"},"count":{"type":"integer"}}}}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Types", {"type":"object","properties":{"n":{"type":"integer"},"f":{"type":"number"},"b":{"type":"boolean"},"s":{"type":"string"},"o":{"type":"object","properties":{"k":{"type":"string"}}},"items":{"type":"array","items":{"type":"object","properties":{"qty":{"type":"integer"}}}},"tags":{"type":"array","items":{"type":"string"}},"any":{}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Deep", {"type":"object","properties":{"a":{"type":"object","properties":{"b":{"type":"object","properties":{"c":{"type":"string"}}}}},"arr":{"type":"array","items":{"type":"object","properties":{"x":{"type":"string"}}}},"s":{"type":"string"}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Status", {"type":"object","required":["status"],"properties":{"status":{"type":"string","enum":["new","paid"]},"code":{"type":"string","pattern":"^[A-Z]{2}[0-9]+$"}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Cons", {"type":"object","required":["code"],"properties":{"code":{"type":"string","minLength":2,"maxLength":4},"qty":{"type":"integer","minimum":1,"maximum":10},"tags":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"string"}},"kind":{"const":"order"},"flag":{"const":true}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Excl", {"type":"object","properties":{"price":{"type":"number","exclusiveMinimum":0,"exclusiveMaximum":100},"step":{"type":"number","multipleOf":0.25},"pack":{"type":"integer","multipleOf":5},"age":{"type":"integer","minimum":18,"exclusiveMinimum":true},"ids":{"type":"array","uniqueItems":true,"items":{"type":"integer"}},"objs":{"type":"array","uniqueItems":true,"items":{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}}}}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Props", {"type":"object","minProperties":1,"maxProperties":4,"properties":{"cc":{"type":"string"},"billing":{"type":"string"},"zip":{"type":"string"},"meta":{"type":"object","additionalProperties":false,"properties":{"a":{"type":"integer"}}},"tags":{"type":"object","additionalProperties":{"type":"integer"}}},"dependentRequired":{"cc":["billing","zip"],"x":["y"]}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("NotC", {"type":"object","properties":{"n":{"type":"integer","not":{"const":13}},"word":{"type":"string","not":{"enum":["bad","worse"]}},"tags":{"type":"array","items":{"type":"string"},"contains":{"const":"vip"},"minContains":1,"maxContains":2},"nums":{"type":"array","contains":{"type":"integer","minimum":10}},"o":{"type":"object","not":{"required":["a","b"]}}},"not":{"required":["forbidden"]}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("DepS", {"type":"object","properties":{"name":{"type":"string"},"credit_card":{"type":"string"},"billing":{"type":"string"},"meta":{"type":"object","propertyNames":{"pattern":"^[a-z_]+$","maxLength":8},"additionalProperties":{"type":"integer"}}},"dependentSchemas":{"credit_card":{"required":["billing"],"properties":{"billing":{"type":"string","minLength":3}}},"name":{"properties":{"credit_card":{"maxLength":4}}}},"propertyNames":{"not":{"const":"forbidden"}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("OneOf", {"type":"object","properties":{"pay":{"oneOf":[{"type":"string","minLength":3},{"type":"integer","minimum":100}]},"shape":{"oneOf":[{"type":"object","required":["r"],"properties":{"r":{"type":"number"}}},{"type":"object","required":["w","h"],"properties":{"w":{"type":"number"},"h":{"type":"number"}}}]},"id":{"anyOf":[{"type":"string","pattern":"^A"},{"type":"string","maxLength":2}]}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("AllOf", {"type":"object","properties":{"code":{"type":"string","allOf":[{"maxLength":5},{"maxLength":3},{"pattern":"^[A-Z]+$"}]},"n":{"allOf":[{"type":"integer","minimum":1},{"maximum":10},{"enum":[1,2,3]}]},"k":{"allOf":[{"type":"string"},{"type":"integer"}]},"c":{"enum":[1,"1",true]}},"allOf":[{"properties":{"extra":{"type":"string"}},"required":["extra"]}]})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Cond", {"type":"object","properties":{"isMember":{"type":"boolean"}},"if":{"properties":{"isMember":{"const":true}}},"then":{"properties":{"membershipNumber":{"type":"string","minLength":4}},"required":["membershipNumber"]},"else":{"properties":{"membershipNumber":{"type":"string","minLength":1}}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Cond2", {"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"string"}},"if":{"properties":{"a":{"not":{"const":1}}},"required":["a"]},"then":{"required":["b"]}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("Nested", {"type":"object","properties":{"m":{"type":"array","items":{"type":"array","minItems":1,"items":{"type":"integer"}}}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("AnyIn", {"type":"object","properties":{"payload":{}}})
    Quit:$$$ISERR(sc) sc
    Set sc = ..Import("AnyOut", {"type":"object","properties":{"data":{}}})
    Quit:$$$ISERR(sc) sc
    Set props = {}, req = []
    For i = 1:1:60 { Do props.%Set("f"_i, {"type":"string"})  Do req.%Push("f"_i) }
    Set many = {"type":"object"}
    Do many.%Set("properties", props), many.%Set("required", req)
    Quit ..Import("Many", many)
}

/// Removes every UT/UTB DocType, document, binding and search table row the tests created and verifies that nothing is left
Method OnAfterAllTests() As %Status
{
    Set id = ""
    For {
        Set id = $Order(..Docs(id))
        If id = "" Quit
        Do ##class(JVDoc.Document).%DeleteId(id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM JVDoc.Binding WHERE Pattern %STARTSWITH 'UT'")
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM JVDoc.SchemaDef WHERE Category IN ('UT', 'UTB')")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.SchemaDef WHERE Category IN ('UT', 'UTB')"), 0, "no UT schemas left")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.Binding WHERE Pattern %STARTSWITH 'UT'"), 0, "no UT bindings left")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.Document WHERE DocType %STARTSWITH 'UT:'"), 0, "no UT documents left")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.OrderSearch WHERE DocId NOT IN (SELECT ID FROM JVDoc.Document)"), 0, "no orphan search table rows")
    Quit $$$OK
}

// ---------------- helpers ----------------

/// Imports a JSON Schema as UT:pName
Method Import(pName As %String, pSchema As %DynamicObject, pMaxDepth As %Integer = 8) As %Status
{
    Quit ##class(JVDoc.SchemaImport).FromJSONSchema("UT", pName, pSchema, pMaxDepth)
}

/// Creates an unsaved document from a JSON string or dynamic object
Method Doc(pDocType As %String, pInit) As JVDoc.Document
{
    Set d = ##class(JVDoc.Document).%New(pInit)
    Set d.DocType = pDocType
    Quit d
}

/// Saves a document and remembers its ID for cleanup
Method Keep(pDoc As JVDoc.Document) As %Status
{
    Set sc = pDoc.%Save()
    If $$$ISOK(sc) Set ..Docs(pDoc.%Id()) = ""
    Quit sc
}

/// Validates a JSON string against a DocType and returns "OK" or the error text
Method Val(pDocType As %String, pJSON As %String, pSpec As %String = "all") As %String
{
    Set sc = ..Doc(pDocType, pJSON).Validate(pSpec)
    Quit $Select($$$ISOK(sc):"OK", 1:$System.Status.GetErrorText(sc))
}

/// Serialized JSON of a document's parsed object
Method Json(pDoc As JVDoc.Document) As %String
{
    Quit pDoc.GetObj().%ToJSON()
}

/// Child node with the given name in a children array of a field tree, or "" when absent
Method Child(pChildren, pName As %String)
{
    Set found = ""
    If '$IsObject(pChildren) Quit ""
    Set it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) { If c.name = pName { Set found = c  Quit } }
    Quit found
}

/// First column of a single-row SQL query
Method Count(pSQL As %String, pArg As %String = "") As %String
{
    Set rs = $Select(pArg = "":##class(%SQL.Statement).%ExecDirect(, pSQL), 1:##class(%SQL.Statement).%ExecDirect(, pSQL, pArg))
    If 'rs.%Next() Quit ""
    Quit rs.%GetData(1)
}

/// Flattens a multidimensional array into one string, for comparing two GetContentArray results
ClassMethod ArrText(ByRef pArr, pPrefix As %String = "") As %String
{
    Set out = $Select($Data(pArr)#2:pPrefix_"="_pArr_";", 1:""), k = ""
    For {
        Set k = $Order(pArr(k))
        If k = "" Quit
        Kill sub
        Merge sub = pArr(k)
        Set out = out_..ArrText(.sub, pPrefix_"/"_k)
    }
    Quit out
}

/// Whether an import warning containing pText was recorded by the last import
Method HasWarn(pText As %String) As %Boolean
{
    Set k = "", found = 0
    For {
        Set k = $Order(^||JVDoc.Warn(k), 1, v)
        If (k = "") || (k '= +k) Quit
        If v [ pText Set found = 1 Quit
    }
    Quit found
}

// ---------------- tests ----------------

/// JSON Schema import: field tree shape for the editors, bad names, $ref/$defs/$anchor, depth truncation, warnings
Method TestImport()
{
    Do $$$AssertStatusOK(##class(JVDoc.Document).GetContentArray(.c, "source", "UT:Order", 0, 0, 1), "GetContentArray UT:Order")
    Do $$$AssertEquals(c, 4, "four top-level fields")
    Do $$$AssertEquals(c(1, "name"), "order_id", "first field")
    Do $$$AssertEquals($Data(c(1, "type")), 0, "scalars carry no type")
    Do $$$AssertEquals(c(1, "opt"), 0, "order_id is required")
    Do $$$AssertEquals(c(2, "opt"), 1, "total is optional")
    Do $$$AssertEquals(c(4, "name"), "items()", "array field name ends with ()")
    Do $$$AssertEquals(c(4, "type"), "()", "array field type is ()")
    Do $$$AssertEquals(c(4), 2, "array element has two fields")
    Do $$$AssertEquals(c(4, 2, "name"), "qty", "nested field name")
    Do $$$AssertStatusNotOK(##class(JVDoc.Document).GetContentArray(.c2, "source", "UT:Nope"), "unknown DocType is an error")

    // $ref, definitions, recursion, external ref, bad property name, truncation at depth 4
    Set stress = {"definitions":{"Address":{"type":"object","required":["city"],"properties":{"city":{"type":"string"},"zip":{"type":["string","null"]}}},"Person":{"type":"object","properties":{"name":{"type":"string"},"friends":{"type":"array","items":{"$ref":"#/definitions/Person"}}}},"Base":{"type":"object","required":["id"],"properties":{"id":{"type":"integer"}}}},"allOf":[{"$ref":"#/definitions/Base"},{"properties":{"home":{"$ref":"#/definitions/Address"},"owner":{"$ref":"#/definitions/Person"},"payload":{"oneOf":[{"type":"object","properties":{"a":{"type":"string"}}},{"type":"object","properties":{"b":{"type":"number"}}}]},"ext":{"$ref":"https://example.com/other.json"},"bad.key":{"type":"string"}}}]}
    Do $$$AssertStatusOK(..Import("Stress", stress, 4), "import Stress")
    Set t = ##class(JVDoc.Schema).GetTree("UT:Stress")
    Do $$$AssertEquals(t.children.%Size(), 5, "id, home, owner, payload, ext (bad.key skipped)")
    Do $$$AssertEquals(..Child(t.children, "id").type, "integer", "allOf $ref member merged")
    Do $$$AssertEquals(+..Child(t.children, "id").%Get("opt"), 0, "required from allOf member")
    Set home = ..Child(t.children, "home")
    Do $$$AssertEquals(..Child(home.children, "zip").type, "string", "type array takes first non-null type")
    Do $$$AssertEquals(+..Child(home.children, "city").%Get("opt"), 0, "required inside $ref target")
    Do $$$AssertEquals(..Child(t.children, "ext").type, "any", "external $ref is any")
    Set payload = ..Child(t.children, "payload")
    Do $$$AssertEquals(payload.type_"/"_payload.children.%Size(), "object/2", "same-kind oneOf gives the union of properties")
    Do $$$AssertEquals(+..Child(payload.children, "a").%Get("fromAlt"), 1, "alternative-only field is marked fromAlt")
    Set friends = ..Child(..Child(t.children, "owner").children, "friends")
    Do $$$AssertEquals(friends.type, "array", "recursive $ref array")
    Set deeper = ..Child(friends.items.children, "friends")
    Do $$$AssertEquals(+deeper.items.%Get("truncated"), 1, "recursion cut at pMaxDepth with truncated flag")
    Do $$$AssertTrue(..HasWarn("external $ref not supported"), "warning for external $ref")
    Do $$$AssertTrue(..HasWarn("skip property 'bad.key'"), "warning for unusable property name")
    Do $$$AssertTrue(..HasWarn("truncated at depth"), "warning for truncation")

    // $anchor and unresolved anchor
    Do $$$AssertStatusOK(..Import("Anch", {"type":"object","properties":{"home":{"$ref":"#addr"},"work":{"$ref":"#addr"},"bad":{"$ref":"#nope"}},"$defs":{"Address":{"$anchor":"addr","type":"object","properties":{"city":{"type":"string"}}}}}), "import Anch")
    Set t = ##class(JVDoc.Schema).GetTree("UT:Anch")
    Do $$$AssertEquals(..Child(..Child(t.children, "work").children, "city").type, "string", "$anchor resolved")
    Do $$$AssertEquals(..Child(t.children, "bad").type, "any", "unresolved $ref is any")
    Do $$$AssertTrue(..HasWarn("unresolved $ref"), "warning for unresolved $ref")

    // root must be an object
    Do $$$AssertStatusNotOK(..Import("Bad", {"type":"array","items":{"type":"string"}}), "array root is rejected")
}

/// FromBundle: one DocType per $defs entry, per root property, selected names plus the root
Method TestBundle()
{
    Set sch = {"title":"MyMultiModelSchema","type":"object","properties":{"userModel":{"$ref":"#/$defs/User"},"productModel":{"$ref":"#/$defs/Product"},"orderModel":{"$ref":"#/$defs/Order"}},"$defs":{"User":{"type":"object","required":["userId","username"],"properties":{"userId":{"type":"integer"},"username":{"type":"string"}}},"Product":{"type":"object","required":["productId","price"],"properties":{"productId":{"type":"string"},"price":{"type":"number"}}},"Order":{"type":"object","required":["orderId"],"properties":{"orderId":{"type":"string"}}}}}
    Do $$$AssertStatusOK(##class(JVDoc.SchemaImport).FromBundle("UTB", sch), "bundle from $defs")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.SchemaDef WHERE Category = 'UTB'"), 3, "three DocTypes from $defs")
    Do $$$AssertEquals(..Child(##class(JVDoc.Schema).GetTree("UTB:User").children, "userId").type, "integer", "UTB:User field")
    Do $$$AssertStatusOK(##class(JVDoc.SchemaImport).FromBundle("UTB", sch, "properties"), "bundle from root properties")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.SchemaDef WHERE Category = 'UTB'"), 6, "three more, named after the properties")
    Do $$$AssertTrue($IsObject(##class(JVDoc.Schema).GetTree("UTB:userModel")), "UTB:userModel exists")
    Do $$$AssertStatusOK(##class(JVDoc.SchemaImport).FromBundle("UTB", sch, "defs", "User,Order", "Whole"), "selected names plus root")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.SchemaDef WHERE Category = 'UTB'"), 7, "root added as UTB:Whole")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetTree("UTB:Whole").children.%Size(), 3, "root has the three model properties")
    Do $$$AssertTrue(..Val("UTB:User", "{""userId"":1}") [ "username: required field is missing", "bundle DocType validates")
    Do $$$AssertStatusNotOK(##class(JVDoc.SchemaImport).FromBundle("UTB", {"type":"object"}), "no $defs is an error")
}

/// GetValueAt, GetNextIndex and SetValueAt type coercion against UT:Types
Method TestPathAccess()
{
    Set d = ..Doc("UT:Types", "{""n"":5,""f"":2.5,""b"":true,""s"":""x"",""o"":{""k"":""v""},""items"":[{""qty"":1},{""qty"":2}],""tags"":[""a"",""b""],""z"":null}")
    Do $$$AssertEquals(d.GetValueAt("n"), 5, "scalar")
    Do $$$AssertEquals(d.GetValueAt("o"), "{""k"":""v""}", "object as JSON text")
    Do $$$AssertEquals(d.GetValueAt("items()"), 2, "name() returns the element count")
    Do $$$AssertEquals(d.GetValueAt("items(2).qty"), 2, "indexed element")
    Do $$$AssertEquals(d.GetValueAt("tags(1)"), "a", "scalar array element")
    Do $$$AssertEquals(d.GetValueAt("z"), "", "null reads as empty string")
    Set v = d.GetValueAt("nope", , .sc)
    Do $$$AssertStatusNotOK(sc, "missing path is an error")
    Do $$$AssertEquals(d.GetNextIndex("items()", ""), 1, "first index")
    Do $$$AssertEquals(d.GetNextIndex("items()", 1), 2, "second index")
    Do $$$AssertEquals(d.GetNextIndex("items()", 2), "", "no third index")
    Do $$$AssertEquals(d.GetNextIndex("nope()", ""), "", "missing array has no index")

    Do $$$AssertStatusOK(d.SetValueAt("7", "n"), "set integer")
    Do $$$AssertStatusOK(d.SetValueAt("3.5", "f"), "set number")
    Do $$$AssertStatusOK(d.SetValueAt("false", "b"), "set boolean")
    Do $$$AssertStatusOK(d.SetValueAt("7", "s"), "set string")
    Do $$$AssertStatusOK(d.SetValueAt("{""k"":""w""}", "o"), "set object from JSON text")
    Do $$$AssertStatusOK(d.SetValueAt("3", "items(4).qty"), "pad array with null to index 4")
    Do $$$AssertStatusOK(d.SetValueAt("c", "tags()"), "append via name()")
    Do $$$AssertStatusOK(d.SetValueAt("d", "tags", "append"), "append via action")
    Do $$$AssertStatusOK(d.SetValueAt("[1,2]", "any"), "any field takes JSON text as a subtree")
    Do $$$AssertEquals(..Json(d), "{""n"":7,""f"":3.5,""b"":false,""s"":""7"",""o"":{""k"":""w""},""items"":[{""qty"":1},{""qty"":2},null,{""qty"":3}],""tags"":[""a"",""b"",""c"",""d""],""z"":null,""any"":[1,2]}", "typed writes")
    Do $$$AssertStatusOK(d.SetValueAt("", "n"), "empty string to a number field")
    Do $$$AssertEquals(d.GetObj().%GetTypeOf("n"), "null", "writes null")
    Do $$$AssertStatusOK(d.SetValueAt("plain", "any"), "any field takes other text as string")
    Do $$$AssertEquals(d.GetObj().%GetTypeOf("any"), "string", "non-JSON text stays a string")
    Do $$$AssertEquals(d.Dirty, 1, "document is dirty after writes")

    // paths outside the schema, and documents without a DocType, are any
    Do $$$AssertStatusOK(d.SetValueAt("{""a"":1}", "unknown"), "unknown path with JSON text")
    Do $$$AssertEquals(d.GetObj().%GetTypeOf("unknown"), "object", "parsed into a subtree")
    Do $$$AssertStatusOK(d.SetValueAt("5", "unknown2"), "unknown path with plain text")
    Do $$$AssertEquals(d.GetObj().%GetTypeOf("unknown2"), "string", "kept as string")
    Set free = ..Doc("", "{}")
    Do free.SetValueAt("[true]", "x")  Do free.SetValueAt("[urgent] call", "note")  Do free.SetValueAt("{bad", "s")
    Do $$$AssertEquals(..Json(free), "{""x"":[true],""note"":""[urgent] call"",""s"":""{bad""}", "no DocType: JSON text parsed, other text kept")
    Do $$$AssertStatusNotOK(d.SetValueAt("v", "(1)"), "root array write is an error on an object root")
    Set ro = ..Doc("UT:Types", "{""n"":1}")
    Set ro.IsMutable = 0
    Do $$$AssertStatusNotOK(ro.SetValueAt("2", "n"), "immutable document rejects writes")
}

/// remove/clear semantics and atomicity of a failed write
Method TestRemoveAndAtomicity()
{
    Set d = ..Doc("UT:Deep", "{""a"":{""b"":{""c"":""v"",""d"":1}},""arr"":[1,2,3],""s"":""keep""}")
    Do $$$AssertStatusOK(d.SetValueAt("", "a.b.c", "remove"), "remove property")
    Do $$$AssertEquals(..Json(d), "{""a"":{""b"":{""d"":1}},""arr"":[1,2,3],""s"":""keep""}", "property removed")
    Do $$$AssertEquals(d.Dirty, 1, "dirty after remove")
    Do d.SetValueAt("", "arr(2)", "clear")
    Do $$$AssertEquals(d.GetValueAt("arr"), "[1,3]", "clear removes the element")
    Do d.SetValueAt("", "arr(9)", "remove")  Do d.SetValueAt("", "s(1)", "remove")  Do d.SetValueAt("", "a.b.zz.q", "remove")
    Do $$$AssertEquals(..Json(d), "{""a"":{""b"":{""d"":1}},""arr"":[1,3],""s"":""keep""}", "missing index, non-array and missing path are no-ops")
    Do d.SetValueAt("", "arr()", "remove")
    Do $$$AssertEquals(..Json(d), "{""a"":{""b"":{""d"":1}},""s"":""keep""}", "name() removes the property")

    Set f = ..Doc("UT:Deep", "{""x"":1}")
    Do $$$AssertStatusOK(f.SetValueAt("", "nope.deeper", "remove"), "remove of a missing path succeeds")
    Do $$$AssertEquals(..Json(f)_"|"_f.Dirty, "{""x"":1}|0", "and creates nothing")
    Set sc = f.SetValueAt("notjson", "a.b")
    Do $$$AssertTrue($System.Status.GetErrorText(sc) [ "BadJSON", "bad JSON for an object field is an error")
    Do $$$AssertEquals(..Json(f)_"|"_f.Dirty, "{""x"":1}|0", "failed write left the document unchanged")
    Set sc = f.SetValueAt("v", "arr(0).x")
    Do $$$AssertTrue($System.Status.GetErrorText(sc) [ "BadIndex", "index 0 is an error")
    Do $$$AssertEquals(..Json(f)_"|"_f.Dirty, "{""x"":1}|0", "no array created for a bad index")
    Set g = ..Doc("UT:Deep", "{""s"":""str""}")
    Set sc = g.SetValueAt("{}", "s.k")
    Do $$$AssertTrue($System.Status.GetErrorText(sc) [ "PathConflict", "writing below a string is a conflict")
    Do $$$AssertEquals(..Json(g)_"|"_g.Dirty, "{""s"":""str""}|0", "conflict left the document unchanged")
    Do $$$AssertStatusOK(f.SetValueAt("{""c"":""ok""}", "a.b"), "good JSON after the failures")
    Do $$$AssertEquals(..Json(f)_"|"_f.Dirty, "{""x"":1,""a"":{""b"":{""c"":""ok""}}}|1", "intermediate object created on success")
}

/// An unmodified document is stored and re-saved byte-for-byte
Method TestPassThrough()
{
    Set json = "{ ""a"" : ""1"",  ""n"" : 1.50,"_$Char(10)_"  ""extra"" : { ""keep"" : [1, 2, 3] } }"
    Set d = ..Doc("", json)
    Do $$$AssertStatusOK(..Keep(d), "save")
    Set id = d.%Id()
    Kill d
    Set d2 = ##class(JVDoc.Document).%OpenId(id)
    Do d2.Raw.Rewind()
    Do $$$AssertEquals(d2.Raw.Read(100000), json, "stored byte-for-byte")
    Do $$$AssertEquals(d2.GetValueAt("a"), 1, "read a path")
    Do $$$AssertEquals(d2.GetValueAt("extra"), "{""keep"":[1,2,3]}", "fields outside any schema are kept")
    Do $$$AssertStatusOK(d2.%Save(), "save after read")
    Do d2.Raw.Rewind()
    Do $$$AssertEquals(d2.Raw.Read(100000), json, "still identical after read and save")
    Do $$$AssertStatusOK(d2.SetValueAt("2", "a"), "modify")
    Do $$$AssertStatusOK(d2.%Save(), "save modified")
    Do d2.Raw.Rewind()
    Do $$$AssertEquals(d2.Raw.Read(100000), "{""a"":""2"",""n"":1.50,""extra"":{""keep"":[1,2,3]}}", "re-serialized only after a write")
}

/// Clones do not share state with the source, deep or shallow, before or after the source was parsed
Method TestClone()
{
    Set src = ..Doc("", "{""a"":""1"",""extra"":{""keep"":1}}")
    Do $$$AssertEquals(src.GetValueAt("a"), 1, "A: source parsed")
    Set t = src.%ConstructClone(1)
    Do t.SetValueAt("Z", "a")
    Do $$$AssertEquals(src.GetValueAt("a")_"/"_t.GetValueAt("a")_"/"_t.GetValueAt("extra"), "1/Z/{""keep"":1}", "A: clone changed, source unchanged")

    Set src = ..Doc("", "{""a"":""1""}")
    Do src.SetValueAt("M", "a")
    Set t = src.%ConstructClone(1)
    Do $$$AssertEquals(t.GetValueAt("a"), "M", "B: clone carries unsaved changes")
    Do t.SetValueAt("N", "a")
    Do $$$AssertEquals(src.GetValueAt("a")_"/"_t.GetValueAt("a"), "M/N", "B: later change isolated")

    Set src = ..Doc("", "{""a"":""1""}")
    Set t = src.%ConstructClone(1)
    Do src.SetValueAt("S", "a")
    Do $$$AssertEquals(src.GetValueAt("a")_"/"_t.GetValueAt("a"), "S/1", "C: changing the source does not change the clone")

    Set src = ..Doc("", "{""a"":""1""}")
    Do src.GetValueAt("a")
    Set t = src.%ConstructClone(0)
    Do t.SetValueAt("Z", "a")
    Do $$$AssertEquals(src.GetValueAt("a")_"/"_t.GetValueAt("a"), "1/Z", "D: shallow clone is isolated too")
}

/// Validation of the basic keyword groups: required, type, enum, pattern, bounds, const
Method TestValidateBasics()
{
    Do $$$AssertEquals(..Val("UT:Order", "{""order_id"":""A1"",""total"":12.5,""items"":[{""sku"":""S1"",""qty"":2}]}"), "OK", "valid order")
    Do $$$AssertTrue(..Val("UT:Order", "{""total"":12.5}") [ "order_id: required field is missing", "required")
    Set e = ..Val("UT:Order", "{""order_id"":""A1"",""total"":""x"",""items"":[{""sku"":""S1"",""qty"":""2""},{""sku"":""S2"",""qty"":2.5}]}")
    Do $$$AssertTrue(e [ "total: expected number, got string", "type number")
    Do $$$AssertTrue(e [ "items(1).qty: expected integer, got string", "type integer vs string with array path")
    Do $$$AssertTrue(e [ "items(2).qty: expected integer, got number", "integer rejects a decimal")
    Do $$$AssertEquals(..Val("UT:Order", "{""order_id"":null,""total"":null}"), "OK", "null counts as present and skips type")
    Do $$$AssertTrue(..Val("UT:Order", "{""order_id"":[1]}") [ "order_id: expected string, got array", "type string vs array")
    Set e = ..Val("UT:Status", "{""status"":""old"",""code"":""ab1""}")
    Do $$$AssertTrue(e [ "status: value 'old' is not in the allowed list", "enum")
    Do $$$AssertTrue(e [ "code: value does not match pattern ^[A-Z]{2}[0-9]+$", "pattern")
    Do $$$AssertEquals(..Val("UT:Status", "{""status"":""paid"",""code"":""AB12""}"), "OK", "enum and pattern satisfied")

    Do $$$AssertEquals(..Val("UT:Cons", "{""code"":""ab"",""qty"":5,""tags"":[""x""],""kind"":""order"",""flag"":true}"), "OK", "bounds and const satisfied")
    Set e = ..Val("UT:Cons", "{""code"":""a"",""qty"":0,""tags"":[],""kind"":""other"",""flag"":false}")
    Do $$$AssertTrue(e [ "code: length 1 is shorter than minLength 2", "minLength")
    Do $$$AssertTrue(e [ "qty: value 0 is less than minimum 1", "minimum")
    Do $$$AssertTrue(e [ "tags: array has 0 item(s), fewer than minItems 1", "minItems")
    Do $$$AssertTrue(e [ "kind: value does not equal const ""order""", "const string")
    Do $$$AssertTrue(e [ "flag: value does not equal const true", "const boolean")
    Set e = ..Val("UT:Cons", "{""code"":""abcde"",""qty"":11,""tags"":[""a"",""b"",""c""]}")
    Do $$$AssertTrue(e [ "code: length 5 is longer than maxLength 4", "maxLength")
    Do $$$AssertTrue(e [ "qty: value 11 is greater than maximum 10", "maximum")
    Do $$$AssertTrue(e [ "tags: array has 3 item(s), more than maxItems 2", "maxItems")
    Do $$$AssertEquals(..Val("UT:Cons", "{""code"":""a"",""qty"":0,""tags"":[],""kind"":""other""}", "t"), "OK", "bounds and const are off without b and c")

    Do $$$AssertEquals(..Val("UT:Excl", "{""price"":50,""step"":1.75,""pack"":10,""age"":19,""ids"":[1,2,3],""objs"":[{""a"":1,""b"":2},{""a"":2,""b"":1}]}"), "OK", "exclusive bounds, multipleOf, uniqueItems satisfied")
    Set e = ..Val("UT:Excl", "{""price"":0,""step"":1.3,""pack"":12,""age"":18,""ids"":[1,2,1],""objs"":[{""a"":1,""b"":2},{""b"":2,""a"":1}]}")
    Do $$$AssertTrue(e [ "price: value 0 must be greater than exclusiveMinimum 0", "exclusiveMinimum numeric form")
    Do $$$AssertTrue(e [ "step: value 1.3 is not a multiple of .25", "multipleOf decimal")
    Do $$$AssertTrue(e [ "pack: value 12 is not a multiple of 5", "multipleOf integer")
    Do $$$AssertTrue(e [ "age: value 18 must be greater than minimum 18 (exclusive)", "exclusiveMinimum draft-04 boolean form")
    Do $$$AssertTrue(e [ "ids(3): duplicates item 1 (uniqueItems)", "uniqueItems scalars")
    Do $$$AssertTrue(e [ "objs(2): duplicates item 1 (uniqueItems)", "uniqueItems objects ignore key order")
    Do $$$AssertTrue(..Val("UT:Excl", "{""price"":100}") [ "price: value 100 must be less than exclusiveMaximum 100", "exclusiveMaximum")
    Do $$$AssertTrue(..Val("UT:Excl", "{""ids"":[1,1.0]}") [ "ids(2): duplicates item 1", "1 and 1.0 are the same number")
}

/// Validation of object-level keywords: property counts, dependentRequired, additionalProperties, not, contains, propertyNames, dependentSchemas
Method TestValidateObjects()
{
    Do $$$AssertEquals(..Val("UT:Props", "{""cc"":""1"",""billing"":""b"",""zip"":""z"",""meta"":{""a"":1}}"), "OK", "dependentRequired satisfied")
    Do $$$AssertTrue(..Val("UT:Props", "{}") [ "(root): property count 0 is less than minProperties 1", "minProperties")
    Set e = ..Val("UT:Props", "{""cc"":""1""}")
    Do $$$AssertTrue(e [ "billing: required when 'cc' is present", "dependentRequired first")
    Do $$$AssertTrue(e [ "zip: required when 'cc' is present", "dependentRequired second")
    Do $$$AssertTrue(..Val("UT:Props", "{""meta"":{""a"":1,""b"":2}}") [ "meta.b: additional property is not allowed", "additionalProperties false")
    Do $$$AssertTrue(..Val("UT:Props", "{""tags"":{""n"":1,""m"":""x""}}") [ "tags.m: expected integer, got string", "additionalProperties schema")
    Do $$$AssertTrue(..Val("UT:Props", "{""cc"":""1"",""billing"":""b"",""zip"":""z"",""meta"":{""a"":1},""tags"":{""n"":1},""extra"":1}") [ "(root): property count 6 is more than maxProperties 4", "maxProperties counts every property")
    Do $$$AssertEquals(..Val("UT:Props", "{""y"":1}"), "OK", "dependent without its key")
    Do $$$AssertTrue(..Val("UT:Props", "{""x"":null}") [ "y: required when 'x' is present", "null key counts as present")
    Do $$$AssertTrue(..Val("UT:Props", "{""meta"":{""b"":2}}", "a") [ "additional property is not allowed", "a alone")
    Do $$$AssertTrue(..Val("UT:Props", "{""meta"":{""b"":2}}", "u") [ "meta.b: unknown field", "u alone")
    Set e = ..Val("UT:Props", "{""meta"":{""b"":2}}", "au")
    Do $$$AssertTrue((e [ "unknown field") && (e '[ "additional property"), "with a and u only the u error is reported")

    Do $$$AssertEquals(..Val("UT:NotC", "{""n"":5,""word"":""ok"",""tags"":[""vip"",""a""],""nums"":[1,20],""o"":{""a"":1}}"), "OK", "not and contains satisfied")
    Set e = ..Val("UT:NotC", "{""n"":13,""word"":""bad""}")
    Do $$$AssertTrue(e [ "n: value must not match the schema in not", "not const")
    Do $$$AssertTrue(e [ "word: value must not match the schema in not", "not enum")
    Do $$$AssertTrue(..Val("UT:NotC", "{""tags"":[""a"",""b""]}") [ "tags: 0 item(s) match contains, fewer than minContains 1", "minContains")
    Do $$$AssertTrue(..Val("UT:NotC", "{""tags"":[""vip"",""vip"",""vip""]}") [ "tags: 3 item(s) match contains, more than maxContains 2", "maxContains")
    Do $$$AssertTrue(..Val("UT:NotC", "{""nums"":[1,2]}") [ "nums: no item matches contains", "contains without minContains")
    Do $$$AssertTrue(..Val("UT:NotC", "{""o"":{""a"":1,""b"":2}}") [ "o: value must not match the schema in not", "not with required")
    Do $$$AssertTrue(..Val("UT:NotC", "{""forbidden"":1}") [ "(root): value must not match the schema in not", "not on the root")
    Do $$$AssertEquals(..Val("UT:NotC", "{""n"":13,""word"":""bad""}", "all-s"), "OK", "s switched off")

    Do $$$AssertEquals(..Val("UT:DepS", "{""name"":""A"",""meta"":{""ok_key"":1}}"), "OK", "dependentSchemas and propertyNames satisfied")
    Set e = ..Val("UT:DepS", "{""credit_card"":""1234567"",""name"":""A""}")
    Do $$$AssertTrue(e [ "billing: required field is missing", "dependentSchemas required")
    Do $$$AssertTrue(e [ "credit_card: length 7 is longer than maxLength 4", "dependentSchemas constraint on another key")
    Do $$$AssertTrue(..Val("UT:DepS", "{""credit_card"":""12"",""billing"":""ab""}") [ "billing: length 2 is shorter than minLength 3", "dependentSchemas property constraint")
    Do $$$AssertEquals(..Val("UT:DepS", "{""credit_card"":""12"",""billing"":""abc""}"), "OK", "dependentSchemas satisfied")
    Set e = ..Val("UT:DepS", "{""meta"":{""Bad-Key"":1,""toolongname"":2,""fine"":""x""}}")
    Do $$$AssertTrue(e [ "meta.Bad-Key: property name is invalid: value does not match pattern", "propertyNames pattern")
    Do $$$AssertTrue(e [ "meta.toolongname: property name is invalid: length 11 is longer than maxLength 8", "propertyNames maxLength")
    Do $$$AssertTrue(e [ "meta.fine: expected integer, got string", "additionalProperties schema inside")
    Do $$$AssertTrue(..Val("UT:DepS", "{""forbidden"":1}") [ "forbidden: property name is invalid", "propertyNames with not on the root")
    Do $$$AssertTrue(..Val("UT:DepS", "{""credit_card"":null}") [ "billing: required field is missing", "null key triggers dependentSchemas")
}

/// Validation of composition and conditionals: if/then/else, oneOf, anyOf, allOf, nested arrays
Method TestValidateComposition()
{
    Do $$$AssertEquals(..Val("UT:Cond", "{""isMember"":true,""membershipNumber"":""ABCD""}"), "OK", "then satisfied")
    Do $$$AssertTrue(..Val("UT:Cond", "{""isMember"":true}") [ "membershipNumber: required field is missing", "then required")
    Do $$$AssertTrue(..Val("UT:Cond", "{""isMember"":true,""membershipNumber"":""AB""}") [ "membershipNumber: length 2 is shorter than minLength 4", "then constraint")
    Do $$$AssertEquals(..Val("UT:Cond", "{""isMember"":false,""membershipNumber"":""A""}"), "OK", "else satisfied")
    Do $$$AssertTrue(..Val("UT:Cond", "{""isMember"":false,""membershipNumber"":""""}") [ "length 0 is shorter than minLength 1", "else constraint")
    Do $$$AssertTrue(..Val("UT:Cond2", "{""a"":2}") [ "b: required field is missing", "if with property-level not matches")
    Do $$$AssertEquals(..Val("UT:Cond2", "{""a"":1}"), "OK", "property-level not inside if is evaluated")
    Do $$$AssertEquals(..Val("UT:Cond2", "{}"), "OK", "if fails on missing required key")

    Do $$$AssertEquals(..Val("UT:OneOf", "{""pay"":""abc"",""shape"":{""r"":1},""id"":""Axy""}"), "OK", "oneOf and anyOf satisfied")
    Do $$$AssertTrue(..Val("UT:OneOf", "{""pay"":""ab""}") [ "pay: value does not match any alternative of oneOf [1: length 2 is shorter than minLength 3; 2: expected integer, got string]", "oneOf no match lists each alternative's reason")
    Do $$$AssertTrue(..Val("UT:OneOf", "{""shape"":{""r"":1,""w"":2,""h"":3}}") [ "shape: value matches 2 alternatives of oneOf, exactly one is allowed", "oneOf more than one match")
    Do $$$AssertTrue(..Val("UT:OneOf", "{""id"":""Bxyz""}") [ "id: value does not match any alternative of anyOf", "anyOf no match")
    Do $$$AssertTrue(..Val("UT:OneOf", "{""shape"":{}}") [ "1: shape.r: required field is missing; 2: shape.w: required field is missing", "nested reasons carry the path")
    Do $$$AssertEquals(..Val("UT:OneOf", "{""pay"":null}"), "OK", "null skips oneOf")
    Do $$$AssertEquals(..Val("UT:OneOf", "{""shape"":{""r"":1,""w"":2,""h"":3}}", "all-o"), "OK", "o switched off")

    Do $$$AssertEquals(..Val("UT:AllOf", "{""extra"":""e"",""code"":""ABC"",""n"":2,""c"":""1""}"), "OK", "allOf satisfied, enum string ""1""")
    Set e = ..Val("UT:AllOf", "{""extra"":""e"",""code"":""ABCD"",""n"":5}")
    Do $$$AssertTrue(e [ "code: length 4 is longer than maxLength 3", "strictest allOf member applies")
    Do $$$AssertTrue(e [ "n: value 5 is not in the allowed list", "enum in allOf member")
    Do $$$AssertTrue(..Val("UT:AllOf", "{""extra"":""e"",""k"":""x""}") [ "k: expected integer, got string", "contradicting allOf types")
    Do $$$AssertTrue(..Val("UT:AllOf", "{}") [ "extra: required field is missing", "required from root allOf")
    Do $$$AssertTrue(..Val("UT:AllOf", "{""extra"":""e"",""c"":""true""}") [ "c: value 'true' is not in the allowed list", "enum is JSON-type-aware")
    Do $$$AssertEquals(..Val("UT:AllOf", "{""extra"":""e"",""c"":true}"), "OK", "boolean true is in the enum")

    Do $$$AssertEquals(..Val("UT:Nested", "{""m"":[[1,2]]}"), "OK", "nested array valid")
    Do $$$AssertTrue(..Val("UT:Nested", "{""m"":[[1,2],[3,""x""]]}") [ "m(2)(2): expected integer, got string", "nested array elements are validated")
    Do $$$AssertTrue(..Val("UT:Nested", "{""m"":[1]}") [ "m(1): expected array, got number", "inner type check")
    Do $$$AssertTrue(..Val("UT:Nested", "{""m"":[[]]}") [ "m(1): array has 0 item(s), fewer than minItems 1", "inner array constraints")
}

/// Validation spec parsing, the error cap and the ValidateJSON class method
Method TestValidateSpecAndAPI()
{
    Set bad = "{""total"":""x"",""zzz"":1}"
    Do $$$AssertTrue(..Val("UT:Order", bad, "all") '= "OK", "all reports")
    Do $$$AssertTrue(..Val("UT:Order", bad, "all") '[ "unknown field", "all does not include u")
    Do $$$AssertTrue(..Val("UT:Order", bad, "all-t") [ "required", "all-t keeps r")
    Do $$$AssertTrue(..Val("UT:Order", bad, "all-t") '[ "expected number", "all-t drops t")
    Do $$$AssertTrue(..Val("UT:Order", bad, "u") [ "zzz: unknown field", "u alone")
    Do $$$AssertEquals(..Val("UT:Order", bad, ""), "OK", "empty spec only parses")
    Do $$$AssertTrue(..Val("UT:Order", bad, "dmall") [ "total: expected number", "product letters d and m are ignored")
    Set e = ..Val("UT:Order", bad, "rtepbcaso-all")
    Do $$$AssertTrue((e '[ "required") && (e [ "expected number"), "-all is not supported: only the letter right after - is negated")
    Do $$$AssertEquals(..Val("UT:Order", bad, "-r-t"), "OK", "nothing left on")
    Do $$$AssertTrue(..Val("UT:Order", "{bad", "all") [ "Invalid JSON", "unparsable document")
    Do $$$AssertTrue(..Val("UT:Nope", "{}", "all") [ "Cannot validate: unknown DocType", "unknown DocType")
    Do $$$AssertTrue(..Val("", "{}", "all") [ "Cannot validate: DocType is empty", "empty DocType")
    Do $$$AssertTrue(..Val("UT:Order", "[1]", "all") [ "Root must be a JSON object", "array root")

    Set sc = ##class(JVDoc.Document).ValidateJSON("{}", "UT:Many", "all", .errs)
    Do $$$AssertStatusNotOK(sc, "60 missing fields")
    Do $$$AssertEquals(errs, 51, "50 errors plus the marker")
    Do $$$AssertTrue(errs(1) [ "f1: required field is missing", "first error")
    Do $$$AssertTrue(errs(51) [ "(more errors omitted)", "cap marker")

    Do $$$AssertStatusOK(##class(JVDoc.Document).ValidateJSON("{""order_id"":""A""}", "UT:Order"), "string input, default spec")
    Set st = ##class(%Stream.TmpCharacter).%New()
    Do st.Write("{""order_id"":""A"",""total"":""x""}")  Do st.Rewind()
    Set sc = ##class(JVDoc.Document).ValidateJSON(st, "UT:Order", "all", .errs)
    Do $$$AssertStatusNotOK(sc, "stream input")
    Do $$$AssertEquals(errs, 1, "one error from stream input")
    Do $$$AssertTrue(errs(1) [ "total: expected number, got string", "error text from stream input")
    Do $$$AssertStatusOK(##class(JVDoc.Document).ValidateJSON({"order_id":"A","paid":true}, "UT:Order", "all", .errs), "dynamic object input")
    Do $$$AssertEquals(errs, 0, "no errors")
    Do $$$AssertTrue($System.Status.GetErrorText(##class(JVDoc.Document).ValidateJSON("{bad", "UT:Order")) [ "Invalid JSON", "invalid JSON via ValidateJSON")
    Do $$$AssertTrue($System.Status.GetErrorText(##class(JVDoc.Document).ValidateJSON("{}", "UT:Nope")) [ "Cannot validate", "unknown DocType via ValidateJSON")
    Do $$$AssertTrue($System.Status.GetErrorText(##class(JVDoc.Document).ValidateJSON("{""order_id"":""A"",""zzz"":1}", "UT:Order", "allu")) [ "zzz: unknown field", "allu rejects fields outside the schema")
}

/// The any type: import variants, inference of mixed kinds, type-aware copying, validation
Method TestAny()
{
    Do $$$AssertStatusOK(..Import("AnyTest", {"type":"object","properties":{"payload":{},"val":{"type":["string","number"]},"choice":{"oneOf":[{"type":"string"},{"type":"object","properties":{"a":{"type":"string"}}}]},"maybe":{"type":["string","null"]},"oo":{"oneOf":[{"type":"object","properties":{"a":{"type":"string"}}},{"type":"object","properties":{"b":{"type":"number"}}}]}}}), "import AnyTest")
    Set t = ##class(JVDoc.Schema).GetTree("UT:AnyTest")
    Do $$$AssertEquals(..Child(t.children, "payload").type, "any", "empty schema is any")
    Do $$$AssertEquals(..Child(t.children, "val").type, "any", "mixed type array is any")
    Do $$$AssertEquals(..Child(t.children, "choice").type, "any", "oneOf of different kinds is any")
    Do $$$AssertEquals(..Child(t.children, "maybe").type, "string", "type with null takes the other type")
    Set oo = ..Child(t.children, "oo")
    Do $$$AssertEquals(oo.type_"/"_oo.children.%Size(), "object/2", "oneOf of objects is the union")

    Do $$$AssertStatusOK(##class(JVDoc.SchemaInfer).FromSamples("UT", "AnyInfer", [{"v":1,"w":{"a":1},"x":"s"},{"v":"s","w":"str","x":"t"}]), "infer mixed samples")
    Set t = ##class(JVDoc.Schema).GetTree("UT:AnyInfer")
    Do $$$AssertEquals(..Child(t.children, "w").type, "any", "object vs string is any")
    Do $$$AssertEquals(..Child(t.children, "v").type, "integer", "scalar tie keeps the first type")
    Do $$$AssertTrue(..HasWarn("mixed kinds at 'w'"), "mixed kinds warning")

    Set cases = $ListBuild("{""payload"":{""a"":[1,true,null]}}", "{""payload"":5}", "{""payload"":true}", "{""payload"":""x""}", "{""payload"":null}", "{""payload"":[1,2]}", "{}")
    Set expect = $ListBuild("{""data"":{""a"":[1,true,null]}}", "{""data"":5}", "{""data"":true}", "{""data"":""x""}", "{""data"":null}", "{""data"":[1,2]}", "{}")
    For i = 1:1:$ListLength(cases) {
        Set src = ..Doc("UT:AnyIn", $List(cases, i)), tgt = ..Doc("UT:AnyOut", "{}")
        Do $$$AssertStatusOK(tgt.CopyValues(src, "payload", "data", "set", ""), "copy case "_i)
        Do $$$AssertEquals(..Json(tgt), $List(expect, i), "typed copy keeps the JSON type: "_$List(cases, i))
    }
    Set tgt = ..Doc("UT:Order", "{}")
    Do tgt.CopyValues(..Doc("UT:AnyIn", "{""payload"":5}"), "payload", "order_id", "set", "")
    Do $$$AssertEquals(tgt.GetObj().%GetTypeOf("order_id"), "string", "a declared string target still coerces")
    Do $$$AssertEquals(..Val("UT:AnyIn", "{""payload"":{""x"":1}}"), "OK", "any skips the type check (object)")
    Do $$$AssertEquals(..Val("UT:AnyIn", "{""payload"":5}"), "OK", "any skips the type check (number)")
}

/// Schema inference from samples and stored documents, and the JSON Schema export round trip
Method TestInference()
{
    Set smp = "{""id"":1,""name"":""A"",""price"":12.5,""paid"":true,""note"":null,""tags"":[],""addr"":{""city"":""X""},""lines"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3,""memo"":""m""}],""matrix"":[[1,2],[3]],""bad.key"":1}"
    Do $$$AssertStatusOK(##class(JVDoc.SchemaInfer).FromSample("UT", "Inferred", smp), "infer one sample")
    Set t = ##class(JVDoc.Schema).GetTree("UT:Inferred")
    Do $$$AssertEquals(t.children.%Size(), 9, "nine fields, bad.key skipped")
    Do $$$AssertEquals(..Child(t.children, "id").type_"/"_..Child(t.children, "price").type_"/"_..Child(t.children, "paid").type_"/"_..Child(t.children, "name").type, "integer/number/boolean/string", "scalar types")
    Do $$$AssertEquals(..Child(t.children, "note").type, "string", "null assumed string")
    Do $$$AssertEquals(..Child(t.children, "tags").items.type, "string", "empty array items assumed string")
    Do $$$AssertEquals(+..Child(t.children, "id").%Get("opt"), 1, "every field optional by default")
    Set lines = ..Child(t.children, "lines")
    Do $$$AssertEquals(lines.items.children.%Size(), 3, "array element fields merged across elements")
    Do $$$AssertEquals(..Child(t.children, "matrix").items.type, "array", "nested array kept as array")
    Do $$$AssertTrue(..HasWarn("no value seen to infer a type at 'note'"), "null warning")
    Do $$$AssertTrue(..HasWarn("nested array at 'matrix'"), "nested array warning")

    Do $$$AssertStatusOK(##class(JVDoc.SchemaInfer).FromSamples("UT", "Merged", [{"id":1,"price":10,"status":"new","meta":{"a":1}},{"id":2,"price":10.5,"status":"paid","extra":"x"},{"id":"3","price":null,"status":"new","meta":null}], , 1), "infer three samples with pRequired")
    Set t = ##class(JVDoc.Schema).GetTree("UT:Merged")
    Do $$$AssertEquals(..Child(t.children, "id").type, "integer", "majority type")
    Do $$$AssertEquals(+..Child(t.children, "id").%Get("opt"), 0, "field in every sample is required")
    Do $$$AssertEquals(..Child(t.children, "price").type, "number", "integer and number give number when a decimal was seen")
    Do $$$AssertEquals(+..Child(t.children, "meta").%Get("opt")_"/"_..Child(t.children, "meta").type, "1/object", "missing in one sample is optional, null does not change the kind")
    Do $$$AssertEquals(+..Child(t.children, "extra").%Get("opt"), 1, "field seen once is optional")
    Do $$$AssertTrue(..HasWarn("mixed types at 'id'"), "mixed scalar types warning")
    Do $$$AssertStatusOK(##class(JVDoc.SchemaInfer).FromSamples("UT", "Tie", [{"v":1},{"v":"s"}]), "tie")
    Do $$$AssertEquals(..Child(##class(JVDoc.Schema).GetTree("UT:Tie").children, "v").type, "integer", "tie keeps the first type")
    Do $$$AssertStatusNotOK(##class(JVDoc.SchemaInfer).FromSamples("UT", "NotObj", [1, 2]), "samples must be objects")
    Do $$$AssertStatusNotOK(##class(JVDoc.SchemaInfer).FromSamples("UT", "Empty", []), "no samples is an error")

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("UT:Merged")
    Do $$$AssertEquals(js.%Get("$schema"), "https://json-schema.org/draft/2020-12/schema", "exported schema declares 2020-12")
    Do $$$AssertEquals(js.required.%Size(), 3, "required exported")
    Do $$$AssertStatusOK(..Import("RoundTrip", js), "re-import the export")
    Do ##class(JVDoc.Document).GetContentArray(.a1, "source", "UT:Merged", 0, 0, 1)
    Do ##class(JVDoc.Document).GetContentArray(.a2, "source", "UT:RoundTrip", 0, 0, 1)
    Do $$$AssertEquals(..ArrText(.a1), ..ArrText(.a2), "round trip keeps the field tree")
    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("UT:Props")
    Do $$$AssertStatusOK(..Import("Props2", js), "re-import a schema with constraints")
    Do ##class(JVDoc.Document).GetContentArray(.a1, "source", "UT:Props", 0, 0, 1)
    Do ##class(JVDoc.Document).GetContentArray(.a2, "source", "UT:Props2", 0, 0, 1)
    Do $$$AssertEquals(..ArrText(.a1), ..ArrText(.a2), "round trip with constraints keeps the field tree")
    Do $$$AssertEquals(..Val("UT:Props2", "{""cc"":""1""}"), ..Val("UT:Props", "{""cc"":""1""}"), "round trip keeps the constraints")

    Do $$$AssertStatusOK(..Keep(..Doc("UT:Order", "{""order_id"":""ST1"",""total"":1,""items"":[{""sku"":""A"",""qty"":1}]}")), "store doc 1")
    Do $$$AssertStatusOK(..Keep(..Doc("UT:Order", "{""order_id"":""ST2"",""paid"":true,""items"":[]}")), "store doc 2")
    Do $$$AssertStatusOK(##class(JVDoc.SchemaInfer).FromStoredDocs("UT", "FromStore", "UT:Order", 50), "infer from stored documents")
    Set t = ##class(JVDoc.Schema).GetTree("UT:FromStore")
    Do $$$AssertEquals(..Child(t.children, "order_id").type_"/"_..Child(t.children, "paid").type_"/"_..Child(t.children, "total").type, "string/boolean/integer", "fields from both stored documents")
    Do $$$AssertTrue(..HasWarn("inferred from 2 stored document(s)"), "two documents used")
    Do $$$AssertStatusNotOK(##class(JVDoc.SchemaInfer).FromStoredDocs("UT", "None", "UT:Nope", 50), "no documents is an error")
}

/// CopyValues as generated by DTL: scalars with coercion and () on both sides expanded element by element
Method TestCopyValues()
{
    Set src = ..Doc("UT:Order", "{""order_id"":""A1"",""total"":12.5,""paid"":true,""items"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3}],""extra"":{""keep"":1}}")
    Set tgt = ..Doc("UT:Invoice", "{}")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "order_id", "invoice_no", "set", ""), "copy string")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "total", "amount", "set", ""), "copy number")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "paid", "settled", "set", ""), "copy boolean")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "items().sku", "lines().code", "set", ""), "copy repeating field")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "items().qty", "lines().count", "set", ""), "copy second repeating field")
    Do $$$AssertEquals(..Json(tgt), "{""invoice_no"":""A1"",""amount"":12.5,""settled"":true,""lines"":[{""code"":""S1"",""count"":2},{""code"":""S2"",""count"":3}]}", "DTL-style copy with expansion and typing")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "missing", "amount", "set", ""), "missing source is ignored by default")
    Do $$$AssertEquals(tgt.GetValueAt("amount"), 12.5, "target untouched for a missing source")
    Do $$$AssertStatusNotOK(tgt.CopyValues(src, "missing", "amount", "set", "", 0, 0), "missing source is an error when asked")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "items(1)", "lines()", "set", ""), "append an object via () target")
    Do $$$AssertEquals(tgt.GetValueAt("lines()"), 3, "appended one element")
    Do $$$AssertEquals(tgt.GetValueAt("lines(3)"), "{""sku"":""S1"",""qty"":2}", "appended element is the parsed object")
    Do $$$AssertStatusNotOK(tgt.CopyValues(src, "items(1).sku", "lines()", "set", ""), "a scalar cannot be appended to an array of objects")
    Do $$$AssertStatusOK(tgt.CopyValues(src, "extra", "invoice_no", "set", "", 0, 1), "object copied into a string field becomes text")
    Do $$$AssertEquals(tgt.GetValueAt("invoice_no"), "{""keep"":1}", "JSON text in a string field")
}

/// Search table registration, resolution and save-time indexing
Method TestSearchTable()
{
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetSearchTable("UT:Order", "Foo.Bar"), "unknown class rejected")
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetSearchTable("UT:Order", "JVDoc.Schema"), "non-search-table class rejected")
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetSearchTable("", "JVDoc.OrderSearch"), "empty DocType rejected")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetSearchTable("UT:Order", "JVDoc.OrderSearch"), "bind UT:Order")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetSearchTable("UT:Order"), "JVDoc.OrderSearch", "exact match")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetSearchTable("UT:Invoice"), "", "unbound DocType")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetSearchTable("UT:*", "JVDoc.OrderSearch"), "bind category wildcard")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetSearchTable("UT:Invoice"), "JVDoc.OrderSearch", "category wildcard")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetSearchTable("UT:*"), "unbind wildcard")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetSearchTable("UT:Invoice"), "", "wildcard removed")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.Binding WHERE Kind = 'search' AND Pattern = 'UT:Order'"), 1, "binding visible in SQL")

    Set d = ..Doc("UT:Order", "{""order_id"":""UTA1"",""items"":[{""sku"":""UK1""},{""sku"":""UK2""}]}")
    Do $$$AssertStatusOK(..Keep(d), "save bound document")
    Set id = d.%Id(), cnt = "SELECT COUNT(*) N FROM JVDoc.OrderSearch WHERE DocId = ?"
    Do $$$AssertEquals(..Count(cnt, id), 3, "three values indexed on insert")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.OrderSearch WHERE DocId = ? AND PropValue = 'uta1'", id), 1, "values are lower-cased")
    Do $$$AssertStatusOK(d.%Save(), "unchanged re-save")
    Do $$$AssertEquals(..Count(cnt, id), 3, "rows unchanged after re-save")
    Kill d
    Set d = ##class(JVDoc.Document).%OpenId(id)
    Do $$$AssertEquals(d.GetValueAt("order_id"), "UTA1", "reopened")
    Do $$$AssertStatusOK(d.%Save(), "save after open and read")
    Do $$$AssertEquals(..Count(cnt, id), 3, "rows unchanged after open, read and save")
    Do d.SetValueAt("UTA2", "order_id")  Do d.SetValueAt("", "items(2)", "remove")
    Do $$$AssertStatusOK(d.%Save(), "save modified")
    Do $$$AssertEquals(..Count(cnt, id), 2, "rows rebuilt after a change")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM JVDoc.OrderSearch WHERE DocId = ? AND PropValue = 'uta2'", id), 1, "new value indexed")
    Set d.DocType = "UT:Invoice"
    Do $$$AssertStatusOK(d.%Save(), "save with unbound DocType")
    Do $$$AssertEquals(..Count(cnt, id), 0, "rows removed when the DocType has no search table")
    Set d.DocType = "UT:Order"
    Do $$$AssertStatusOK(d.%Save(), "save with bound DocType again")
    Do $$$AssertEquals(..Count(cnt, id), 2, "rows rebuilt")

    Do $$$AssertStatusOK(##class(JVDoc.Document).Reindex("JVDoc.OrderSearch", .n), "Reindex")
    Do $$$AssertTrue(n >= 1, "Reindex counted at least this document")
    Do $$$AssertEquals(..Count(cnt, id), 2, "rows present after Reindex")
    Do $$$AssertEquals(..Count("SELECT COUNT(*) N FROM (SELECT DocId, PropId, PropValue, COUNT(*) C FROM JVDoc.OrderSearch GROUP BY DocId, PropId, PropValue HAVING COUNT(*) > 1)"), 0, "no duplicate rows after Reindex")
    Do $$$AssertStatusNotOK(##class(JVDoc.Document).Reindex("", .n), "Reindex needs a class")
    Do $$$AssertStatusNotOK(##class(JVDoc.Document).Reindex("No.Such", .n), "Reindex of an unknown class")
    Kill d
    Do $$$AssertStatusOK(##class(JVDoc.Document).%DeleteId(id), "delete the document")
    Kill ..Docs(id)
    Do $$$AssertEquals(..Count(cnt, id), 0, "rows removed on delete")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetSearchTable("UT:Order"), "unbind UT:Order")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetSearchTable("UT:Order"), "", "binding removed")
}

/// Identifier path registration and the Identifier property
Method TestIdentifier()
{
    Set order = ..Doc("UT:Order", "{""order_id"":""A1"",""total"":12.5}")
    Set inv = ..Doc("UT:Invoice", "{""invoice_no"":""Z9""}")
    Do $$$AssertEquals(order.Identifier, "", "no binding, no identifier")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:Order", "order_id"), "bind identifier")
    Do $$$AssertEquals(order.Identifier, "A1", "identifier read from the bound path")
    Do $$$AssertEquals(inv.Identifier, "", "other DocType not bound")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:*", "invoice_no"), "bind wildcard")
    Do $$$AssertEquals(inv.Identifier, "Z9", "wildcard applies")
    Do $$$AssertEquals(order.Identifier, "A1", "exact binding wins over the wildcard")
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetIdentifierPath("UT:X", "items().sku"), "empty () rejected")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:X", "items(1).sku"), "indexed path accepted")
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetIdentifierPath("UT:X", "a(1"), "malformed path rejected")
    Do $$$AssertStatusNotOK(##class(JVDoc.Schema).SetIdentifierPath("", "a"), "empty DocType rejected")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetIdentifierPath("UT:X"), "items(1).sku", "stored path")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:Order"), "unbind exact")
    Do $$$AssertEquals(order.Identifier, "", "wildcard path invoice_no does not exist in the order")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:*"), "unbind wildcard")
    Do $$$AssertStatusOK(##class(JVDoc.Schema).SetIdentifierPath("UT:X"), "unbind UT:X")
    Do $$$AssertEquals(order.Identifier_inv.Identifier, "", "nothing bound")
}

/// Per-process caches follow ^JVDoc.Ver through saves and SQL deletes
Method TestCaches()
{
    Do $$$AssertStatusOK(..Import("Cache", {"type":"object","properties":{"a":{"type":"string"}}}), "import")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetTree("UT:Cache").children.%Size(), 1, "one field")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("UT:Cache", "a"), "string", "TypeAt known path")
    Set v0 = +$Get(^JVDoc.Ver("UT:Cache"))
    Do $$$AssertStatusOK(..Import("Cache", {"type":"object","properties":{"a":{"type":"string"},"b":{"type":"integer"}}}), "re-import")
    Do $$$AssertEquals(+$Get(^JVDoc.Ver("UT:Cache")), v0 + 1, "version bumped once by the save")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetTree("UT:Cache").children.%Size(), 2, "cached tree refreshed")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("UT:Cache", "b"), "integer", "type map refreshed")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("UT:Cache", "nope"), "any", "unknown path is any")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("", "a"), "any", "no DocType is any")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("UT:Types", "items().qty"), "integer", "array element path")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM JVDoc.SchemaDef WHERE Category = 'UT' AND Name = 'Cache'")
    Do $$$AssertEquals(rs.%SQLCODE, 0, "SQL delete")
    Do $$$AssertEquals(+$Get(^JVDoc.Ver("UT:Cache")), v0 + 2, "version bumped by the SQL delete")
    Do $$$AssertEquals(##class(JVDoc.Schema).GetTree("UT:Cache"), "", "deleted DocType is gone from the cache")
    Do $$$AssertEquals(##class(JVDoc.Schema).TypeAt("UT:Cache", "a"), "any", "type map dropped")
}

/// Message Viewer display hooks
Method TestDisplay()
{
    Set d = ..Doc("UT:Types", "{""n"":5,""o"":{""k"":""<v>""}}")
    Do $$$AssertEquals(d.%GetContentType(), "text/html", "content type for the viewer")
    Set html = d.ContentsHTML()
    Do $$$AssertTrue(html [ "<pre", "pre element")
    Do $$$AssertTrue(html [ "DocType:</b> UT:Types", "DocType shown")
    Do $$$AssertTrue(html [ ("&quot;n&quot;:5,"_$Char(10)), "indented and escaped JSON")
    Do $$$AssertTrue(html [ "&lt;v&gt;", "HTML-escaped value")
    Set bad = ..Doc("UT:Types", "{not json")
    Do $$$AssertTrue(bad.ContentsHTML() [ "{not json", "unparsable JSON shown raw")
    Do $$$AssertEquals(d.DocTypeCategory_"/"_d.DocTypeName_"/"_d.Name, "UT/Types/Types", "DocType parts")
}

}
