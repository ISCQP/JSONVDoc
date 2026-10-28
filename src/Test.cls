/// 
Class JVDoc.Test
{

ClassMethod Test()
{
    // 1) 导入 schema
    Set sch = {}.%FromJSON("{""type"":""object"",""required"":[""order_id""],""properties"":{""order_id"":{""type"":""string""},""total"":{""type"":""number""},""paid"":{""type"":""boolean""},""items"":{""type"":""array"",""items"":{""type"":""object"",""properties"":{""sku"":{""type"":""string""},""qty"":{""type"":""integer""}}}}}}")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo","Order",sch),!

    // 2) 字段树
    Do ##class(JVDoc.Document).GetContentArray(.c,"source","Demo:Order",0) ZW c

    // 3) 路径读写与透传
    Set d = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""x"":{""keep"":1},""items"":[{""sku"":""S1"",""qty"":2}]}")
    Set d.DocType = "Demo:Order"
    Write d.GetValueAt("items()"),!                // 1
    Write d.GetValueAt("items(1).sku"),!           // S1
    Do d.SetValueAt("5","items(1).qty")            // 写成 number 5
    Do d.SetValueAt("true","paid")                 // 写成 boolean
    Do d.SetValueAt("S2","items()")                // 空括号追加元素
    Write d.GetValueAt("x"),!                      // {"keep":1}  未知字段保留
}

ClassMethod Test1()
{
    Set sch = {}.%FromJSON("{""type"":""object"",""properties"":{""invoice_no"":{""type"":""string""},""amount"":{""type"":""number""},""settled"":{""type"":""boolean""},""lines"":{""type"":""array"",""items"":{""type"":""object"",""properties"":{""code"":{""type"":""string""},""count"":{""type"":""integer""}}}}}}")
    Set sc = ##class(JVDoc.SchemaImport).FromJSONSchema("Demo","Invoice",sch)
    Write $System.Status.IsOK(sc),!
}

ClassMethod ListSchema()
{
    Set rs = ##class(%ResultSet).%New("JVDoc.Document:EnumerateDocTypes")
    For cat = "", "+", "0", "Demo", "Demo%" 
    {
    Do rs.Execute(cat)
    Write "Category=[",cat,"] -> "
    Set n = 0
    While rs.Next() { Set n = n+1  Write rs.GetData(1)," " }
    Write n," rows",!
    }
}

ClassMethod ImportSchema()
{
    //Set f="/iris-shared/durable/mgr/petstore.json"
    //Set sc = ##class(JVDoc.SchemaImport).FromFile("Pet","PetStore",f)

    //Set f="/iris-shared/durable/mgr/schematest1.json"
    //Set sc = ##class(JVDoc.SchemaImport).FromFile("Test","Test1",f)
    Set f="/iris-shared/durable/mgr/pet.json"
    Set sc = ##class(JVDoc.SchemaImport).FromFile("PetStore","Pet",f)
    Write "import: ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
}

ClassMethod Test2()
{
    // 1) 当前命名空间，以及 Schema 表里有多少行
    Write $Namespace,!
    &sql(SELECT COUNT(*) INTO :c FROM JVDoc.Schema)
    Write "SQLCODE=",SQLCODE," count=",$Get(c),!
    ZW ^JVDoc.SchemaD

    // 2) 直接调 Execute，把状态打印出来
    Set sc = ##class(JVDoc.Document).EnumerateDocTypesExecute(.qh, "")
    Write "execute: ",$Select($$$ISOK(sc):"OK", 1:$System.Status.GetErrorText(sc)),!
    ZW qh
}

/// Description
ClassMethod Test3() As %Status
{
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId("EnsLib.EDI.XML.Document||GetContentArray")
    Write "Document FormalSpec: ",m.FormalSpec,!

    Set s = ##class(%Dictionary.MethodDefinition).%OpenId("EnsLib.EDI.XML.Schema||GetContentArray")
    If $IsObject(s) 
    {
        Write "Schema FormalSpec: ",s.FormalSpec,!
        Do s.Implementation.Rewind()
        While 's.Implementation.AtEnd { Write s.Implementation.ReadLine(),! }
    } 
    Else 
    {
        Write "no source",!
    }
}

ClassMethod Dump(pClass As %String, pMethod As %String)
{
    Set d = ##class(%Dictionary.MethodDefinition).%OpenId(pClass_"||"_pMethod)
    If '$IsObject(d) { Write "no source: ",pClass,"::",pMethod,! Quit }
    Write "=== ",pClass,"::",pMethod,!,"FormalSpec: ",d.FormalSpec,!
    Do d.Implementation.Rewind()
    While 'd.Implementation.AtEnd { Write d.Implementation.ReadLine(),! }
}

ClassMethod Run()
{
    Set src = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":12.5,""paid"":true,""items"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3}],""extra"":{""keep"":1}}")
    Set src.DocType = "Demo:Order"
    Set sc = ##class(JVDoc.test5).Transform(src, .tgt)
    Write $System.Status.IsOK(sc),!
    Do tgt.Raw.Rewind()  Write tgt.GetValueAt("lines()"),!
    Write tgt.GetValueAt("amount"),!
    Write tgt.Obj.%ToJSON()
}

ClassMethod Test4()
{
    For m = "GetValueAt","SetValueAt","GetNextIndex","GetContentArray","Validate","CopyValues" {
    For c = "Ens.VDoc.Interface","JVDoc.Document" 
    {
        Set d = ##class(%Dictionary.CompiledMethod).%OpenId(c_"||"_m)
        Write c,"::",m," (",$Select($IsObject(d):d.ClassMethod, 1:"?"),") ",$Select($IsObject(d):d.FormalSpec, 1:"not found"),!
    }
    Write !
}
}

ClassMethod Test5()
{
    Set src = ##class(JVDoc.Document).%New("{""a"":""1"",""extra"":{""keep"":1}}")
    Set t = src.%ConstructClone(1)
    Do t.SetValueAt("Z","a")
    Write "src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a"),!
}

ClassMethod Test6()
{
    // A) 源已解析，克隆后改克隆：源不应变
    Set src = ##class(JVDoc.Document).%New("{""a"":""1"",""extra"":{""keep"":1}}")
    Write "read a=",src.GetValueAt("a"),!
    Set t = src.%ConstructClone(1)
    Do t.SetValueAt("Z","a")
    Write "A: src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a")," extra=",t.GetValueAt("extra"),!

    // B) 源有未保存修改，克隆带上修改，再改克隆不影响源
    Set src = ##class(JVDoc.Document).%New("{""a"":""1""}")
    Do src.SetValueAt("M","a")
    Set t = src.%ConstructClone(1)
    Write "B1: src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a"),!
    Do t.SetValueAt("N","a")
    Write "B2: src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a"),!

    // C) 克隆后再改源，克隆不应变
    Set src = ##class(JVDoc.Document).%New("{""a"":""1""}")
    Set t = src.%ConstructClone(1)
    Do src.SetValueAt("S","a")
    Write "C: src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a"),!

    // D) 浅克隆也不应共用状态
    Set src = ##class(JVDoc.Document).%New("{""a"":""1""}")
    Write "read a=",src.GetValueAt("a"),!
    Set t = src.%ConstructClone(0)
    Do t.SetValueAt("Z","a")
    Write "D: src.a=",src.GetValueAt("a")," tgt.a=",t.GetValueAt("a"),!
}

ClassMethod Test7()
{
    Set json = "{ ""a"" : ""1"",  ""n"" : 1.50,"_$Char(10)_"  ""extra"" : { ""keep"" : [1, 2, 3] } }"
    Set d = ##class(JVDoc.Document).%New(json)
    Do d.%Save()
    Set id = d.%Id()
    Kill d
    Set d2 = ##class(JVDoc.Document).%OpenId(id)
    Do d2.Raw.Rewind()
    Write "raw identical: ",(d2.Raw.Read(100000) = json),!
    Write "read a=",d2.GetValueAt("a"),!
    Do d2.%Save()
    Do d2.Raw.Rewind()
    Write "still identical after read+save: ",(d2.Raw.Read(100000) = json),!
}

ClassMethod Test8()
{
    Set req = ##class(JVDoc.Document).%New("{""order_id"":""B1"",""total"":12.5,""paid"":true,""items"":[{""sku"":""BS1"",""qty"":2},{""sku"":""BS2"",""qty"":3}],""extra"":{""keep"":1}}")
    Set req.DocType = "Demo:Order"
    Set sc = ##class(EnsLib.Testing.Service).SendTestRequest("JVDoc.TestProcess", req, .resp, .sessionId)
    Write "sc=",$System.Status.IsOK(sc)," session=",$Get(sessionId),!
    If $IsObject($Get(resp)) { Write resp.GetValueAt("invoice_no"),!  Do resp.Raw.Rewind()  Write resp.Raw.Read(10000),! }
}

ClassMethod Test9()
{
    Set m = ##class(JVDoc.Document).%OpenId(47)
    Write "DocType=",m.DocType,!
    Write "Category=",m.DocTypeCategory,!
    Write "Name=",m.DocTypeName," / ",m.Name,!
    Write "Identifier=[",m.Identifier,"]",!
    Write m.XMLExportToString(.xml)  ZW xml
}

ClassMethod Test10()
{
    Set d = ##class(%Dictionary.CompiledMethod).%OpenId("Ens.MessageBody||%ShowContents")
    If $IsObject(d) { Write d.FormalSpec,! } Else { Write "not found",! }
    Do ##class(JVDoc.Test).Dump("Ens.MessageBody","%ShowContents")
}

ClassMethod Test11()
{
    Set sch = {}.%FromJSON("{""definitions"":{""Address"":{""type"":""object"",""required"":[""city""],""properties"":{""city"":{""type"":""string""},""zip"":{""type"":[""string"",""null""]}}},""Person"":{""type"":""object"",""properties"":{""name"":{""type"":""string""},""friends"":{""type"":""array"",""items"":{""$ref"":""#/definitions/Person""}}}},""Base"":{""type"":""object"",""required"":[""id""],""properties"":{""id"":{""type"":""integer""}}}},""allOf"":[{""$ref"":""#/definitions/Base""},{""properties"":{""home"":{""$ref"":""#/definitions/Address""},""owner"":{""$ref"":""#/definitions/Person""},""payload"":{""oneOf"":[{""type"":""object"",""properties"":{""a"":{""type"":""string""}}},{""type"":""object"",""properties"":{""b"":{""type"":""number""}}}]},""ext"":{""$ref"":""https://example.com/other.json""},""bad.key"":{""type"":""string""}}}]}")
    Set sc = ##class(JVDoc.SchemaImport).FromJSONSchema("Demo","Stress",sch,4)
    Write $System.Status.IsOK(sc),!
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Stress")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test12()
{
    Set f = "/tmp/schema-resume.json"
    Write "exists: ", ##class(%File).Exists(f), "  size: ", ##class(%File).GetFileSize(f), !
    Set s = ##class(%Stream.FileCharacter).%New()
    Set s.TranslateTable = "UTF8"
    Set sc = s.LinkToFile(f)
    Write "link: ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    Write "first chars: [", $Extract(s.Read(80), 1, 80), "]", !
    Do s.Rewind()
    Try {
        Set o = {}.%FromJSON(s)
        Write "parse: OK", !
    } Catch ex {
        Write "parse: ", ex.DisplayString(), !
    }
    Set sc = ##class(JVDoc.SchemaImport).FromFile("Resume","JSONResume",f)
    Write "import: ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
}

ClassMethod Test13()
{
    Set d = ##class(JVDoc.Document).%New("{""basics"":{""name"":""A"",""profiles"":[{""network"":""GitHub""}]},""work"":[{""name"":""X"",""highlights"":[""h1"",""h2""]}]}")
    Set d.DocType = "Resume:JSONResume"
    Write d.GetValueAt("basics.name"),!
    Write d.GetValueAt("basics.profiles(1).network"),!
    Write d.GetValueAt("work()"),!
    Write d.GetValueAt("work(1).highlights(2)"),!
}

ClassMethod Outline(pClass As %String)
{
    Set c = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
    If '$IsObject(c) { Write "not found: ", pClass, ! Quit }
    Write "=== ", pClass, "  Super: ", c.Super, !
    For i = 1:1:c.Parameters.Count() {
        Set x = c.Parameters.GetAt(i)
        If x.Origin = pClass Write "PARAM  ", x.Name, " = ", x.Default, !
    }
    For i = 1:1:c.Properties.Count() {
        Set x = c.Properties.GetAt(i)
        If x.Origin = pClass Write "PROP   ", x.Name, " : ", x.Type, !
    }
    For i = 1:1:c.Methods.Count() {
        Set x = c.Methods.GetAt(i)
        If x.Origin = pClass Write "METHOD ", $Select(x.ClassMethod:"(class) ", 1:""), x.Name, "(", x.FormalSpec, ")", !
    }
    For i = 1:1:c.XDatas.Count() {
        Set x = c.XDatas.GetAt(i)
        If x.Origin = pClass Write "XDATA  ", x.Name, !
    }
}

ClassMethod ShowXData(pClass As %String, pName As %String, pMaxLines As %Integer = 40)
{
    Set x = ##class(%Dictionary.CompiledXData).%OpenId(pClass_"||"_pName)
    If '$IsObject(x) { Write "not found", ! Quit }
    Do x.Data.Rewind()
    Set n = 0
    While 'x.Data.AtEnd && ($Increment(n) <= pMaxLines) { Write x.Data.ReadLine(), ! }
}

ClassMethod Test14()
{
    Set d = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":12.5,""items"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3}]}")
    Set d.DocType = "Demo:Order"
    Set sc = d.%Save()
    Write "save: ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), "  id=", d.%Id(), !
    Set r = ##class(JVDoc.OrderSearch).IndexDoc(d)
    Write "IndexDoc returned: [", $Get(r), "]", !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DocId, PropId, PropValue FROM JVDoc.OrderSearch")
    While rs.%Next() { Write rs.%Get("DocId"), "  ", rs.%Get("PropId"), "  ", rs.%Get("PropValue"), ! }
    Set pid = ##class(JVDoc.OrderSearch).getPropId("JVDoc.OrderSearch", "Sku")
    Do ##class(JVDoc.OrderSearch).Search(.out, pid, "S2")
    ZW out
    Kill out
    Do ##class(JVDoc.OrderSearch).Search(.out, pid, "s2")
    ZW out
}

ClassMethod Test15()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 3 ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'JVDoc.Document' ORDER BY ID DESC")
    While rs.%Next() { Write rs.%Get("ID"), "  ", rs.%Get("MessageBodyClassName"), "  ", rs.%Get("MessageBodyId"), ! }
    Write "---", !
    Set rs2 = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 6 DocId, PropId, PropValue FROM JVDoc.OrderSearch ORDER BY DocId DESC, PropId")
    While rs2.%Next() { Write rs2.%Get("DocId"), "  ", rs2.%Get("PropId"), "  ", rs2.%Get("PropValue"), ! }
}

ClassMethod Test16()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent FROM %Dictionary.CompiledProperty WHERE Name = 'SearchTableClass'")
    While rs.%Next() { Write rs.%Get("parent"), ! }
}

ClassMethod Test17()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DocId, PropId, PropValue, COUNT(*) AS N FROM JVDoc.OrderSearch GROUP BY DocId, PropId, PropValue HAVING COUNT(*) > 1")
    Set dup = 0
    While rs.%Next() { Set dup = dup + 1  Write "DUP ", rs.%Get("DocId"), " ", rs.%Get("PropId"), " ", rs.%Get("PropValue"), " x", rs.%Get("N"), ! }
    Write dup, " duplicate group(s)", !
}

ClassMethod Test18()
{
    Set req = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":12.5,""paid"":true,""items"":[{""sku"":""BS1"",""qty"":2},{""sku"":""BS2"",""qty"":3}],""extra"":{""keep"":1}}")
    Set req.DocType = "Demo:Order"
    Set sc = ##class(EnsLib.Testing.Service).SendTestRequest("JVDoc.Router", req, .resp, .sessionId)
    Write "sc=",$System.Status.IsOK(sc)," session=",$Get(sessionId),!
}

ClassMethod Test19()
{
    // 带枚举和正则的 schema
    Set sch = {}.%FromJSON("{""type"":""object"",""required"":[""status""],""properties"":{""status"":{""type"":""string"",""enum"":[""new"",""paid""]},""code"":{""type"":""string"",""pattern"":""^[A-Z]{2}[0-9]+$""}}}")
    Write $System.Status.IsOK(##class(JVDoc.SchemaImport).FromJSONSchema("Demo","Status",sch)),!

    Set cases = $ListBuild("Demo:Order|{""order_id"":""A1"",""total"":12.5,""items"":[{""sku"":""S1"",""qty"":2}]}",
    "Demo:Order|{""total"":12.5}",
    "Demo:Order|{""order_id"":""A1"",""total"":""x"",""items"":[{""sku"":""S1"",""qty"":""2""},{""sku"":""S2"",""qty"":2.5}]}",
    "Demo:Order|{""order_id"":""A1"",""extra"":{""keep"":1}}",
    "Demo:Status|{""status"":""old"",""code"":""ab1""}",
    "Demo:Status|{""status"":""paid"",""code"":""AB12""}")
    For i = 1:1:$ListLength(cases) {
        Set c = $List(cases, i)
        Set d = ##class(JVDoc.Document).%New($Piece(c, "|", 2, *))
        Set d.DocType = $Piece(c, "|", 1)
        For spec = "all", "u", "" {
            Set sc = d.Validate(spec)
            Write "case ", i, " [", spec, "] -> ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
        }
    }
}

ClassMethod Test20()
{
    Set d = ##class(JVDoc.Document).%New("{""total"":""x""}")
    Set d.DocType = "Demo:Order"
    For spec = "dmall", "all-r", "-r", "dm" {
        Set sc = d.Validate(spec)
        Write "[", spec, "] -> ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
}
}

ClassMethod Test21()
{
    //Set req = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":12.5}")
    //Set req = ##class(JVDoc.Document).%New("{""total"":12.5}")
    Set req = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":""x""}")
    Set req.DocType = "Demo:Order"
    Set sc = ##class(EnsLib.Testing.Service).SendTestRequest("JVDoc.VRouter", req, .resp, .sessionId)
    Write "sc=",$System.Status.IsOK(sc)," session=",$Get(sessionId),!
}

ClassMethod Inventory()
{
    Set keep = $ListBuild("JVDoc.Document", "JVDoc.Schema", "JVDoc.Binding", "JVDoc.SchemaImport", "JVDoc.SchemaInfer", "JVDoc.DocSchema", "JVDoc.OrderSearch", "JVDoc.ValidatingRouter", "JVDoc.Test", "JVDoc.UnitTests", "JVDoc.test5", "JVDoc.NullOperation")
    Write "--- classes in package JVDoc ---", !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'JVDoc.' ORDER BY Name")
    While rs.%Next() {
        Set n = rs.%Get("Name")
        Write $Select($ListFind(keep, n):"KEEP    ", 1:"REVIEW  "), n, !
    }
    Write "--- schemas ---", !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Category, Name FROM JVDoc.SchemaDef ORDER BY Category, Name")
    While rs.%Next() { Write rs.%Get("Category"), ":", rs.%Get("Name"), ! }
    Write "--- data ---", !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.Document")
    Do rs.%Next()  Write "JVDoc.Document rows: ", rs.%Get("N"), !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.Document WHERE ID NOT IN (SELECT CAST(MessageBodyId AS INTEGER) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'JVDoc.Document' AND MessageBodyId IS NOT NULL AND MessageBodyId <> '')")
    Do rs.%Next()  Write "  of which not referenced by any message header: ", rs.%Get("N"), !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.OrderSearch")
    Do rs.%Next()  Write "JVDoc.OrderSearch rows: ", rs.%Get("N"), !
}

ClassMethod Test22()
{
    Set smp = "{""id"":1,""name"":""A"",""price"":12.5,""paid"":true,""note"":null,""tags"":[],""addr"":{""city"":""X"",""zip"":""1""},""lines"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3,""memo"":""m""}],""matrix"":[[1,2],[3]],""bad.key"":1}"
    Set sc = ##class(JVDoc.SchemaInfer).FromSample("Demo", "Inferred", smp)
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Inferred")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test23()
{
    Set smps = [{"id":1,"price":10,"status":"new","meta":{"a":1}},{"id":2,"price":10.5,"status":"paid","extra":"x"},{"id":"3","price":null,"status":"new","meta":null}]
    Set sc = ##class(JVDoc.SchemaInfer).FromSamples("Demo", "Merged", smps, , 1)
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Merged")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test24()
{
    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:Merged")
    Do js.%ToJSON()
    Write !
    Set sc = ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "RoundTrip", js)
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:RoundTrip")

    // 用推断出的 schema 校验
    Set d = ##class(JVDoc.Document).%New("{""id"":1,""price"":""x"",""status"":""new""}")
    Set d.DocType = "Demo:Merged"
    Set sc = d.Validate("all")
    Write $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
}

ClassMethod Test25()
{
    Set sc = ##class(JVDoc.SchemaInfer).FromStoredDocs("Demo", "FromStore", "Demo:Order", 50)
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:FromStore")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test26()
{
    // 1) pRequired=1：lines[] 里 memo 只出现在一个元素，应为可选；sku、qty 应为必填
    Set sc = ##class(JVDoc.SchemaInfer).FromSample("Demo", "Inferred2", "{""lines"":[{""sku"":""S1"",""qty"":2},{""sku"":""S2"",""qty"":3,""memo"":""m""}]}", , 1)
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Inferred2")
}

ClassMethod Test27()
{
    Set sc = ##class(JVDoc.SchemaInfer).FromSampleFile("Demo", "FromFile", "/iris-shared/durable/mgr/jsonschema2.json")
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:FromFile")
}

ClassMethod Test28()
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8"
    Do f.LinkToFile("/tmp/samples.json")
    Do f.Write("[{""a"":1,""b"":""x""},{""a"":2.5,""c"":true}]")
    Write $System.Status.IsOK(f.%Save()), !
    Set sc = ##class(JVDoc.SchemaInfer).FromSampleFile("Demo", "FromArr", "/tmp/samples.json",1 , ,1 )
    Write $System.Status.IsOK(sc), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:FromArr")
}

ClassMethod Test29()
{
    Write ##class(JVDoc.Schema).GetSearchTable("Demo:Order"), !      // JVDoc.OrderSearch
    Write "[", ##class(JVDoc.Schema).GetSearchTable("Demo:Invoice"), "]", !   // []
    Do ##class(JVDoc.Schema).SetSearchTable("Demo:*", "JVDoc.OrderSearch")
    Write ##class(JVDoc.Schema).GetSearchTable("Demo:Invoice"), !    // JVDoc.OrderSearch
    Do ##class(JVDoc.Schema).SetSearchTable("Demo:*")                // 解除通配绑定
    Write "[", ##class(JVDoc.Schema).GetSearchTable("Demo:Invoice"), "]", !   // []
    Write ##class(JVDoc.Schema).SetSearchTable("Demo:X", "Foo.Bar"), !        // 报错：Class not found
}

ClassMethod Test30()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.OrderSearch")
    Do rs.%Next()  Set n0 = rs.%Get("N")

    Set d = ##class(JVDoc.Document).%New("{""order_id"":""A9"",""items"":[{""sku"":""S9"",""qty"":1}]}")
    Set d.DocType = "Demo:Order"
    Do d.%Save()
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.OrderSearch")
    Do rs.%Next()  Set n1 = rs.%Get("N")

    Set i = ##class(JVDoc.Document).%New("{""invoice_no"":""A9"",""lines"":[{""code"":""S9""}]}")
    Set i.DocType = "Demo:Invoice"
    Do i.%Save()
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM JVDoc.OrderSearch")
    Do rs.%Next()  Set n2 = rs.%Get("N")

    Write "order added: ", n1 - n0, "  invoice added: ", n2 - n1, !
}

ClassMethod Test31()
{
    Do ##class(JVDoc.Document).Reindex("JVDoc.OrderSearch")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DocId, PropId, PropValue, COUNT(*) AS N FROM JVDoc.OrderSearch GROUP BY DocId, PropId, PropValue HAVING COUNT(*) > 1")
    Set dup = 0
    While rs.%Next() { Set dup = dup + 1 }
    Write dup, " duplicate group(s)", !
}

ClassMethod Test32()
{
    Write $System.Status.IsOK(##class(JVDoc.Schema).SetIdentifierPath("Demo:Order", "order_id")), !

    Set d = ##class(JVDoc.Document).%New("{""order_id"":""A1"",""total"":12.5}")
    Set d.DocType = "Demo:Order"
    Write "order: [", d.Identifier, "]", !

    Set i = ##class(JVDoc.Document).%New("{""invoice_no"":""Z9""}")
    Set i.DocType = "Demo:Invoice"
    Write "invoice (not bound): [", i.Identifier, "]", !

    Do ##class(JVDoc.Schema).SetIdentifierPath("Demo:*", "invoice_no")
    Write "invoice (Demo:*): [", i.Identifier, "]", !
    Write "order (exact wins): [", d.Identifier, "]", !

    Set sc = ##class(JVDoc.Schema).SetIdentifierPath("Demo:X", "items().sku")
    Write $System.Status.GetErrorText(sc), !
    Write "ok index form: ", $System.Status.IsOK(##class(JVDoc.Schema).SetIdentifierPath("Demo:X", "items(1).sku")), !

    Do ##class(JVDoc.Schema).SetIdentifierPath("Demo:Order")
    Do ##class(JVDoc.Schema).SetIdentifierPath("Demo:*")
    Do ##class(JVDoc.Schema).SetIdentifierPath("Demo:X")
    Write "after unbind: [", d.Identifier, "]", !
}

ClassMethod Test33()
{
    // 1) 导入：各种"任意类型"的写法
    Set sch = {"type":"object","properties":{"payload":{},"val":{"type":["string","number"]},"choice":{"oneOf":[{"type":"string"},{"type":"object","properties":{"a":{"type":"string"}}}]},"maybe":{"type":["string","null"]},"oo":{"oneOf":[{"type":"object","properties":{"a":{"type":"string"}}},{"type":"object","properties":{"b":{"type":"number"}}}]}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "AnyTest", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:AnyTest")

    // 2) 推断：对象与字符串混用
    Set smps = [{"v":1,"w":{"a":1},"x":"s"},{"v":"s","w":"str","x":"t"}]
    Write ##class(JVDoc.SchemaInfer).FromSamples("Demo", "AnyInfer", smps), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:AnyInfer")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test34()
{
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "AnyIn", {"type":"object","properties":{"payload":{}}}), !
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "AnyOut", {"type":"object","properties":{"data":{}}}), !

    Set cases = $ListBuild("{""payload"":{""a"":[1,true,null]}}", "{""payload"":5}", "{""payload"":true}", "{""payload"":""x""}", "{""payload"":null}", "{""payload"":[1,2]}", "{}")
    For i = 1:1:$ListLength(cases) {
        Set src = ##class(JVDoc.Document).%New($List(cases, i))
        Set src.DocType = "Demo:AnyIn"
        Set tgt = ##class(JVDoc.Document).%New()
        Set tgt.DocType = "Demo:AnyOut"
        Set sc = tgt.CopyValues(src, "payload", "data", "set", "")
        Write $List(cases, i), "  ->  "
        Do tgt.GetObj().%ToJSON()
        Write !
    }
}

ClassMethod Test35()
{
    Set d = ##class(JVDoc.Document).%New("{""payload"":{""x"":1}}")
    Set d.DocType = "Demo:AnyIn"
    Set sc = d.Validate("all")
    Write $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
}

ClassMethod Test36()
{
    // 1) 约束
    Set sch = {"type":"object","required":["code"],"properties":{"code":{"type":"string","minLength":2,"maxLength":4},"qty":{"type":"integer","minimum":1,"maximum":10},"tags":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"string"}},"kind":{"const":"order"},"flag":{"const":true}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Cons", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Cons")

    Set cases = $ListBuild("{""code"":""ab"",""qty"":5,""tags"":[""x""],""kind"":""order"",""flag"":true}", "{""code"":""a"",""qty"":0,""tags"":[],""kind"":""other"",""flag"":false}", "{""code"":""abcde"",""qty"":11,""tags"":[""a"",""b"",""c""]}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:Cons"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    Set d = ##class(JVDoc.Document).%New($List(cases, 2))
    Set d.DocType = "Demo:Cons"
    Write "case 2 with t only: ", $Select($System.Status.IsOK(d.Validate("t")):"OK", 1:"errors"), !
}

ClassMethod Test37()
{
    // 2) $anchor
    Set sch = {"type":"object","properties":{"home":{"$ref":"#addr"},"work":{"$ref":"#addr"},"bad":{"$ref":"#nope"}},"$defs":{"Address":{"$anchor":"addr","type":"object","properties":{"city":{"type":"string"}}}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Anch", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Anch")
    Do ##class(JVDoc.SchemaImport).Report()
}

ClassMethod Test38()
{
    // 3) if/then/else
    Set sch = {"type":"object","properties":{"isMember":{"type":"boolean"}},"if":{"properties":{"isMember":{"const":true}}},"then":{"properties":{"membershipNumber":{"type":"string","minLength":4}},"required":["membershipNumber"]},"else":{"properties":{"membershipNumber":{"type":"string","minLength":1}}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Cond", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Cond")

    Set cases = $ListBuild("{""isMember"":true,""membershipNumber"":""ABCD""}", "{""isMember"":true}", "{""isMember"":true,""membershipNumber"":""AB""}", "{""isMember"":false,""membershipNumber"":""A""}", "{""isMember"":false,""membershipNumber"":""""}", "{""membershipNumber"":""AB""}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:Cond"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
}

ClassMethod Test39()
{
    // 4) 导出再导入
    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:Cons")
    Do js.%ToJSON()
    Write !
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Cons2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Cons2")
    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:Cond")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Cond2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Cond2")
}

ClassMethod Test40()
{
    Set sch = {"type":"object","properties":{"price":{"type":"number","exclusiveMinimum":0,"exclusiveMaximum":100},"step":{"type":"number","multipleOf":0.25},"tenth":{"type":"number","multipleOf":0.1},"pack":{"type":"integer","multipleOf":5},"age":{"type":"integer","minimum":18,"exclusiveMinimum":true},"ids":{"type":"array","uniqueItems":true,"items":{"type":"integer"}},"objs":{"type":"array","uniqueItems":true,"items":{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}}}}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Excl", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Excl")

    Set cases = $ListBuild("{""price"":50,""step"":1.75,""tenth"":0.3,""pack"":10,""age"":19,""ids"":[1,2,3],""objs"":[{""a"":1,""b"":2},{""a"":2,""b"":1}]}", "{""price"":0,""step"":1.3,""tenth"":0.35,""pack"":12,""age"":18,""ids"":[1,2,1],""objs"":[{""a"":1,""b"":2},{""b"":2,""a"":1}]}", "{""price"":100,""ids"":[],""objs"":[]}", "{""ids"":[1,1.0]}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:Excl"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    Set d = ##class(JVDoc.Document).%New($List(cases, 2))
    Set d.DocType = "Demo:Excl"
    Write "case 2 with t only: ", $Select($System.Status.IsOK(d.Validate("t")):"OK", 1:"errors"), !

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:Excl")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Excl2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Excl2")
}

ClassMethod Test41()
{
    Set sch = {"type":"object","minProperties":1,"maxProperties":4,"properties":{"cc":{"type":"string"},"billing":{"type":"string"},"zip":{"type":"string"},"meta":{"type":"object","additionalProperties":false,"properties":{"a":{"type":"integer"}}},"tags":{"type":"object","additionalProperties":{"type":"integer"}}},"dependentRequired":{"cc":["billing","zip"],"x":["y"]}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Props", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Props")

    Set cases = $ListBuild("{""cc"":""1"",""billing"":""b"",""zip"":""z"",""meta"":{""a"":1}}", "{}", "{""cc"":""1""}", "{""meta"":{""a"":1,""b"":2}}", "{""tags"":{""n"":1,""m"":""x""}}", "{""cc"":""1"",""billing"":""b"",""zip"":""z"",""meta"":{""a"":1},""tags"":{""n"":1},""extra"":1}", "{""y"":1}", "{""x"":null}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:Props"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    Set d = ##class(JVDoc.Document).%New("{""meta"":{""b"":2}}")
    Set d.DocType = "Demo:Props"
    For spec = "a", "u", "au", "r" {
        Set sc = d.Validate(spec)
        Write "[", spec, "] ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }

    // 导出再导入
    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:Props")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Props2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Props2")

    // draft-07 的 dependencies
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Dep7", {"type":"object","properties":{"a":{"type":"string"}},"dependencies":{"a":["b"]}}), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Dep7")
}

ClassMethod Test42()
{
    Set sch = {"type":"object","properties":{"n":{"type":"integer","not":{"const":13}},"age":{"type":"integer","not":{"minimum":65}},"word":{"type":"string","not":{"enum":["bad","worse"]}},"tags":{"type":"array","items":{"type":"string"},"contains":{"const":"vip"},"minContains":1,"maxContains":2},"nums":{"type":"array","contains":{"type":"integer","minimum":10}},"opt":{"type":"array","contains":{"const":"x"},"minContains":0,"maxContains":1},"o":{"type":"object","not":{"required":["a","b"]}},"multi":{"type":"integer","allOf":[{"not":{"const":1}},{"not":{"const":2}}]}},"not":{"required":["forbidden"]}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "NotC", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:NotC")

    Set cases = $ListBuild("{""n"":5,""age"":30,""word"":""ok"",""tags"":[""vip"",""a""],""nums"":[1,20],""opt"":[""y""],""o"":{""a"":1},""multi"":3}", "{""n"":13,""age"":70,""word"":""bad""}", "{""tags"":[""a"",""b""]}", "{""tags"":[""vip"",""vip"",""vip""]}", "{""nums"":[1,2]}", "{""opt"":[""x"",""x""]}", "{""o"":{""a"":1,""b"":2}}", "{""forbidden"":1}", "{""multi"":2}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:NotC"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    Set d = ##class(JVDoc.Document).%New($List(cases, 2))
    Set d.DocType = "Demo:NotC"
    Write "case 2 with all-s: ", $Select($System.Status.IsOK(d.Validate("all-s")):"OK", 1:"errors"), !

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:NotC")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "NotC2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:NotC2")
}

ClassMethod Test43()
{
    Set sch = {"type":"object","properties":{"name":{"type":"string"},"credit_card":{"type":"string"},"billing":{"type":"string"},"meta":{"type":"object","propertyNames":{"pattern":"^[a-z_]+$","maxLength":8},"additionalProperties":{"type":"integer"}}},"dependentSchemas":{"credit_card":{"required":["billing"],"properties":{"billing":{"type":"string","minLength":3}}},"name":{"properties":{"credit_card":{"maxLength":4}}}},"propertyNames":{"not":{"const":"forbidden"}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "DepS", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:DepS")

    Set cases = $ListBuild("{""name"":""A"",""meta"":{""ok_key"":1}}", "{""credit_card"":""1234567"",""name"":""A""}", "{""credit_card"":""12"",""billing"":""ab""}", "{""credit_card"":""12"",""billing"":""abc""}", "{""meta"":{""Bad-Key"":1,""toolongname"":2,""fine"":""x""}}", "{""forbidden"":1}", "{""credit_card"":null}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:DepS"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    For c = 5, 6 {
        Set d = ##class(JVDoc.Document).%New($List(cases, c))
        Set d.DocType = "Demo:DepS"
        Set sc = d.Validate("all-s")
        Write "case ", c, " with all-s: ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:DepS")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "DepS2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:DepS2")

    // draft-07 dependencies 的对象形式
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "Dep7s", {"type":"object","properties":{"a":{"type":"string"}},"dependencies":{"a":{"required":["b"]}}}), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:Dep7s")
    Set d = ##class(JVDoc.Document).%New("{""a"":""x""}")
    Set d.DocType = "Demo:Dep7s"
    Write $Select($System.Status.IsOK(d.Validate("all")):"OK", 1:$System.Status.GetErrorText(d.Validate("all"))), !
}

ClassMethod Test44()
{
    Set sch = {"title":"MyMultiModelSchema","type":"object","properties":{"userModel":{"$ref":"#/$defs/User"},"productModel":{"$ref":"#/$defs/Product"},"orderModel":{"$ref":"#/$defs/Order"}},"$defs":{"User":{"type":"object","required":["userId","username"],"properties":{"userId":{"type":"integer"},"username":{"type":"string"}}},"Product":{"type":"object","required":["productId","price"],"properties":{"productId":{"type":"string"},"price":{"type":"number"}}},"Order":{"type":"object","required":["orderId"],"properties":{"orderId":{"type":"string"}}}}}

    // 1) 默认：每个 $defs 项一个 DocType
    Write ##class(JVDoc.SchemaImport).FromBundle("Demo", sch), !
    Do ##class(JVDoc.SchemaImport).Report()
    For n = "User", "Product", "Order" { Write "-- Demo:", n, !  Do ##class(JVDoc.SchemaImport).Outline("Demo:"_n) }

    // 2) 按根 properties 的名字
    Write ##class(JVDoc.SchemaImport).FromBundle("Demo2", sch, "properties"), !
    Do ##class(JVDoc.SchemaImport).Report()
    Write "-- Demo2:userModel", !
    Do ##class(JVDoc.SchemaImport).Outline("Demo2:userModel")

    // 3) 只导入指定的，并把根也导入成一个 DocType
    Write ##class(JVDoc.SchemaImport).FromBundle("Demo3", sch, "defs", "User,Order", "Whole"), !
    Do ##class(JVDoc.SchemaImport).Report()
    Write "-- Demo3:Whole", !
    Do ##class(JVDoc.SchemaImport).Outline("Demo3:Whole")

    // 4) 校验
    Set d = ##class(JVDoc.Document).%New("{""userId"":1}")
    Set d.DocType = "Demo:User"
    Write $Select($System.Status.IsOK(d.Validate("all")):"OK", 1:$System.Status.GetErrorText(d.Validate("all"))), !
}

ClassMethod Test45()
{
    // 1) oneOf / anyOf
    Set sch = {"type":"object","properties":{"pay":{"oneOf":[{"type":"string","minLength":3},{"type":"integer","minimum":100}]},"shape":{"oneOf":[{"type":"object","required":["r"],"properties":{"r":{"type":"number"}}},{"type":"object","required":["w","h"],"properties":{"w":{"type":"number"},"h":{"type":"number"}}}]},"id":{"anyOf":[{"type":"string","pattern":"^A"},{"type":"string","maxLength":2}]},"both":{"oneOf":[{"type":"integer"},{"type":"number"}]},"x":{"oneOf":[{"type":"object","properties":{"v":{"type":"string"}}},{"type":"object","properties":{"v":{"type":"integer"}}}]}}}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "OneOf", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:OneOf")

    Set cases = $ListBuild("{""pay"":""abc"",""shape"":{""r"":1},""id"":""Axy"",""both"":5.5,""x"":{""v"":1}}", "{""pay"":""ab""}", "{""pay"":50}", "{""shape"":{""r"":1,""w"":2,""h"":3}}", "{""id"":""Bxyz""}", "{""both"":5}", "{""shape"":{}}", "{""x"":{""v"":true}}", "{""pay"":null}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:OneOf"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }
    Set d = ##class(JVDoc.Document).%New($List(cases, 4))
    Set d.DocType = "Demo:OneOf"
    Write "case 4 with all-o: ", $Select($System.Status.IsOK(d.Validate("all-o")):"OK", 1:"errors"), !

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:OneOf")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "OneOf2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:OneOf2")
}

ClassMethod Test46()
{
    // 2) allOf 成员，以及 enum 的类型区分
    Set sch = {"type":"object","properties":{"code":{"type":"string","allOf":[{"maxLength":5},{"maxLength":3},{"pattern":"^[A-Z]+$"}]},"n":{"allOf":[{"type":"integer","minimum":1},{"maximum":10},{"enum":[1,2,3]}]},"k":{"allOf":[{"type":"string"},{"type":"integer"}]},"c":{"enum":[1,"1",true]}},"allOf":[{"properties":{"extra":{"type":"string"}},"required":["extra"]}]}
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "AllOfT", sch), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:AllOfT")

    Set cases = $ListBuild("{""extra"":""e"",""code"":""ABC"",""n"":2,""c"":""1""}", "{""extra"":""e"",""code"":""ABCD"",""n"":5}", "{""extra"":""e"",""code"":""abc"",""n"":20}", "{""extra"":""e"",""k"":""x""}", "{}", "{""extra"":""e"",""c"":""true""}", "{""extra"":""e"",""c"":true}")
    For i = 1:1:$ListLength(cases) {
        Set d = ##class(JVDoc.Document).%New($List(cases, i))
        Set d.DocType = "Demo:AllOfT"
        Set sc = d.Validate("all")
        Write "case ", i, ": ", $Select($System.Status.IsOK(sc):"OK", 1:$System.Status.GetErrorText(sc)), !
    }

    Set js = ##class(JVDoc.SchemaInfer).ToJSONSchema("Demo:AllOfT")
    Write ##class(JVDoc.SchemaImport).FromJSONSchema("Demo", "AllOfT2", js), !
    Do ##class(JVDoc.SchemaImport).Outline("Demo:AllOfT2")
}

}
