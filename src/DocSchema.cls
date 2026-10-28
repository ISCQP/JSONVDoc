/// Stub schema class required by the IRIS rule editor (SCHEMACLASS parameter on JVDoc.Document).
/// The rule editor calls ResolveSchemaTypeToDocType to resolve the docCategory/docName
/// constraint fields into a full DocType for field-completion lookups.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/22
Class JVDoc.DocSchema
{

/// Called by the rule editor to assemble the full DocType from the docCategory and docName constraint fields.<br>
/// <var>pCategory</var>: the rule's docCategory constraint (first part of the DocType)<br>
/// <var>pName</var>: the rule's docName constraint (second part of the DocType)<br>
/// Returns: "pCategory:pName", or "" when either part is empty
ClassMethod ResolveSchemaTypeToDocType(pCategory As %String = "", pName As %String = "") As %String
{
    If (pCategory = "") || (pName = "") Quit ""
    Quit pCategory_":"_pName
}

/// Called for "Segment." expressions; JSON documents have no segment concept.<br>
/// <var>pCategory</var>: the rule's docCategory constraint (ignored)<br>
/// <var>pName</var>: the rule's docName constraint (ignored)<br>
/// <var>pSegName</var>: the segment name in the expression (ignored)<br>
/// Returns: always ""
ClassMethod ResolveSegNameToStructure(pCategory As %String = "", pName As %String = "", pSegName As %String = "") As %String
{
    Quit ""
}

}
