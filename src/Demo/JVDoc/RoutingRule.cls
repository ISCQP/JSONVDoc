/// 
Class Demo.JVDoc.RoutingRule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.VDocRuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.VDocRoutingEngine" production="Demo.JVDoc.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="" disabled="false">
<constraint name="msgClass" value="JVDoc.Document"></constraint>
<constraint name="docCategory" value="PetStore"></constraint>
<constraint name="docName" value="pet"></constraint>
<when condition="Document.{category.name}=&quot;Dogs&quot;" comment="">
<send transform="" target="Demo.JVDoc.BO"></send>
</when>
<otherwise>
<send transform="Demo.JVDoc.DT" target="Demo.JVDoc.BO"></send>
</otherwise>
</rule>
</ruleSet>
</ruleDefinition>
}

}
