Class JVDoc.TESTDTL Extends Ens.DataTransformDTL [ DependsOn = JVDoc.Document ]
{

/// DTL Definition.
XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform targetClass='JVDoc.Document' targetDocType='Demo:Order' sourceClass='JVDoc.Document' sourceDocType='Demo:Order' create='new' language='objectscript'>
</transform>
}

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;

}
