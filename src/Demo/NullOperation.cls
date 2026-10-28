Include Ensemble

Class JVDoc.NullOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As JVDoc.Document, Output pResponse As Ens.Response) As %Status
{
    $$$LOGINFO("JVDoc.NullOperation got order_id=["_pRequest.GetValueAt("order_id")_"] DocType="_pRequest.DocType)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
<MapItem MessageType="JVDoc.Document"><Method>OnMessage</Method></MapItem>
</MapItems>
}

}
