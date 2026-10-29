/// 
Class Demo.JVDoc.SearchTablePet Extends (%Persistent, Ens.VDoc.SearchTable)
{

Parameter DOCCLASS = "JVDoc.Document";

XData SearchSpec [ XMLNamespace = "http://www.intersystems.com/EnsSearchTable" ]
{
<Items>
<Item DocType="" PropName="Category">[category.name]</Item>
<Item DocType="" PropName="Name">[name]</Item>
<Item DocType="" PropName="Tag">[tags().name]</Item>
</Items>
}

Storage Default
{
<Data name="SearchTablePetDefaultData">
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
<DataLocation>^Demo.JVDoc.SearchTablePetD</DataLocation>
<DefaultData>SearchTablePetDefaultData</DefaultData>
<IdLocation>^Demo.JVDoc.SearchTablePetD</IdLocation>
<IndexLocation>^Demo.JVDoc.SearchTablePetI</IndexLocation>
<StreamLocation>^Demo.JVDoc.SearchTablePetS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
