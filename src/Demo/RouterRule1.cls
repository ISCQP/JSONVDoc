/// 
Class JVDoc.RouterRule1 Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.VDocRuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.VDocRoutingEngine" production="ClinicalResearch.ClinicalResearchProduction">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="Rule1" disabled="false">
<constraint name="msgClass" value="JVDoc.Document"></constraint>
<constraint name="docCategory" value="Demo"></constraint>
<constraint name="docName" value="Order"></constraint>
<when condition="Document.{total}&gt;100" comment="">
<delete></delete>
<send transform="JVDoc.test5" target="JVDoc.Null"></send>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
