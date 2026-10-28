/// Routing engine that validates JVDoc messages against their JSON Schema at the routing entry point.
/// Extends EnsLib.MsgRouter.VDocRoutingEngine and overrides OnValidate to run JVDoc.Document.Validate
/// after the product's own checks pass.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/22
Class JVDoc.ValidatingRouter Extends EnsLib.MsgRouter.VDocRoutingEngine
{

/// Runs the product's built-in validation first (which rejects a missing DocType), then validates the message against its JSON Schema using the Validation spec.<br>
/// <var>pDoc</var>: the incoming message; only JVDoc.Document instances get the schema check<br>
/// <var>pValSpec</var>: the Validation setting, e.g. "dmall"; the product handles d and m, JVDoc.Document.Validate the flag letters<br>
/// <var>pStatus</var> (output): $$$OK when the message is valid, otherwise the first error found; an error triggers Bad Message Handler / Act On Validation Error<br>
/// Returns: always 1, meaning validation was handled here and the default validation must not run again
Method OnValidate(pDoc As %Persistent, pValSpec As %String, Output pStatus As %Status = {$$$OK}) As %Boolean
{
    Do ##super(pDoc, pValSpec, .pStatus)
    If $$$ISERR(pStatus) Quit 1
    If $IsObject(pDoc) && pDoc.%Extends("JVDoc.Document") Set pStatus = pDoc.Validate(pValSpec)
    Quit 1
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
