Class Demo.JVDoc.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.JVDoc.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description></Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="Demo.JVDoc.BP" Category="" ClassName="Demo.JVDoc.BP" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Demo.JVDoc.Router" Category="" ClassName="JVDoc.ValidatingRouter" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Demo.JVDoc.RoutingRule</Setting>
    <Setting Target="Host" Name="Validation">dmall</Setting>
    <Setting Target="Host" Name="ActOnValidationError">1</Setting>
    <Setting Target="Host" Name="BadMessageHandler">Demo.JVDoc.BOBadMsg</Setting>
    <Setting Target="Host" Name="ForwardGeneratedResponseToTargets">1</Setting>
  </Item>
  <Item Name="Demo.JVDoc.BO" Category="" ClassName="Demo.JVDoc.BO" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="Demo.JVDoc.BOBadMsg" Category="" ClassName="Demo.JVDoc.BOBadMsg" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="PetStore" Category="" ClassName="JVDoc.REST.GenericService" PoolSize="0" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="DocType">PetStore:pet</Setting>
    <Setting Target="Host" Name="TargetConfigName">Demo.JVDoc.Router</Setting>
    <Setting Target="Adapter" Name="Port"></Setting>
    <Setting Target="Adapter" Name="SSLConfig"></Setting>
    <Setting Target="Host" Name="ArchiveIO">1</Setting>
    <Setting Target="Host" Name="OneWay">0</Setting>
  </Item>
</Production>
}

}
