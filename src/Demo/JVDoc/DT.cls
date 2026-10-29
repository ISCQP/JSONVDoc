Class Demo.JVDoc.DT Extends Ens.DataTransformDTL [ DependsOn = JVDoc.Document ]
{

Parameter GENERATEEMPTYSEGMENTS = 0;

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='JVDoc.Document' targetClass='JVDoc.Document' sourceDocType='PetStore:pet' targetDocType='PetStore:pet' create='copy' language='objectscript' >
<assign value='source.{name}_" :OtherPet" ' property='target.{name}' action='set' />
<foreach property='source.{tags()}' key='k1' >
<assign value='"O:"_source.{tags(k1).name}' property='target.{tags(k1).name}' action='set' />
</foreach>
</transform>
}

}
