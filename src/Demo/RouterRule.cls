/// 
/// Example of JSON Virtual Document based Router Rule
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/22
Class JVDoc.RouterRule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.VDocRuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.VDocRoutingEngine" production="ClinicalResearch.ClinicalResearchProduction">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="">
<constraint name="msgClass" value="JVDoc.Document"></constraint>
<constraint name="docCategory" value="Demo"></constraint>
<constraint name="docName" value="Order"></constraint>
<when condition="Document.{order_id}=&quot;A1&quot;" comment="">
<send transform="DT.TestJVDoc" target="JVDoc.Null"></send>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
