/// 
Class Demo.JVDoc.BP Extends Ens.BusinessProcessBPL
{

/// BPL Definition
XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Ens.StringRequest' response='Ens.Response' height='2000' width='2000' >
<context>
<property name='SourceJVDoc' type='JVDoc.Document' instantiate='1' deletewithcontext='0' />
<property name='TargetJVDoc' type='JVDoc.Document' instantiate='1' deletewithcontext='0' />
<property name='Temp' type='%String' instantiate='0' deletewithcontext='0' >
<parameters>
<parameter name='MAXLEN'  value='2500' />
</parameters>
</property>
</context>
<sequence xend='200' yend='550' >
<code name='Initialize' xpos='200' ypos='250' >
<![CDATA[ Set context.SourceJVDoc = ##class(JVDoc.Document).Create(request.StringValue,"PetStore:pet")]]>
</code>
<call name='Router' target='Demo.JVDoc.Router' async='0' xpos='200' ypos='450' >
<request type='JVDoc.Document' >
<assign property="callrequest" value="context.SourceJVDoc" action="set" />
</request>
<response type='Ens.Response' >
<assign property="response" value="callresponse" action="set" />
</response>
</call>
</sequence>
</process>
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
