/// 
Class Demo.JVDoc.BOBadMsg Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As JVDoc.Document, Output pResponse As Ens.Response) As %Status
{
    $$$LOGINFO("Demo.JVDoc.BO got bad message "_pRequest.GetObj().%ToJSON()_" of DocType "_pRequest.DocType)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
<MapItem MessageType="JVDoc.Document"><Method>OnMessage</Method></MapItem>
</MapItems>
}
}