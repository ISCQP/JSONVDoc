/// Search table example
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/22
Class JVDoc.OrderSearch Extends (%Persistent, Ens.VDoc.SearchTable)
{

Parameter DOCCLASS = "JVDoc.Document";

XData SearchSpec [ XMLNamespace = "http://www.intersystems.com/EnsSearchTable" ]
{
<Items>
<Item DocType="" PropName="OrderId">[order_id]</Item>
<Item DocType="" PropName="Sku">[items().sku]</Item>
</Items>
}

Storage Default
{
<Data name="OrderSearchDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>DocId</Value>
</Value>
<Value name="3">
<Value>PropValue</Value>
</Value>
<Value name="4">
<Value>PropId</Value>
</Value>
</Data>
<DataLocation>^JVDoc.OrderSearchD</DataLocation>
<DefaultData>OrderSearchDefaultData</DefaultData>
<IdLocation>^JVDoc.OrderSearchD</IdLocation>
<IndexLocation>^JVDoc.OrderSearchI</IndexLocation>
<StreamLocation>^JVDoc.OrderSearchS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
