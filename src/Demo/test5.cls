Class JVDoc.test5 Extends Ens.DataTransformDTL [ DependsOn = JVDoc.Document ]
{

Parameter GENERATEEMPTYSEGMENTS = 0;

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='JVDoc.Document' targetClass='JVDoc.Document' sourceDocType='Demo:Order' targetDocType='Demo:Invoice' create='copy' language='objectscript' >
<assign value='source.{order_id}' property='target.{invoice_no}' action='set' />
<assign value='source.{total}' property='target.{amount}' action='set' />
<assign value='source.{paid}' property='target.{settled}' action='set' />
<foreach property='source.{items()}' key='k1' >
<assign value='source.{items(k1).sku}' property='target.{lines(k1).code}' action='set' />
<assign value='source.{items(k1).qty}' property='target.{lines(k1).count}' action='set' />
</foreach>
</transform>
}

}
