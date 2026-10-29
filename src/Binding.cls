/// Per-DocType bindings that JVDoc.Document resolves at run time (SQL table JVDoc.Binding).
/// Kind "search" names the search table class that indexes a DocType; Kind "identifier" names the path that supplies its Identifier.
/// Pattern is "Cat:Name", "Cat:*" (every DocType in the category) or "*" (all DocTypes); Resolve tries them in that order.
/// Bindings are namespace data like the DocTypes themselves; as a table they can be inspected, exported and moved with SQL.
/// JVDoc.Schema.SetSearchTable / SetIdentifierPath validate the value before storing it here.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.Binding Extends %Persistent
{

/// What the binding configures: "search" (search table class) or "identifier" (Identifier path)
Property Kind As %String(MAXLEN = 16, VALUELIST = ",search,identifier") [ Required ];

/// DocType pattern: "Cat:Name", "Cat:*" or "*"
Property Pattern As %String(MAXLEN = 130) [ Required ];

/// Search table class name or Identifier path, depending on Kind
Property Value As %String(MAXLEN = 255) [ Required ];

Index PK On (Kind, Pattern) [ IdKey, PrimaryKey, Unique ];

/// Stores the binding for pKind/pPattern, or removes it when pValue is empty. Does not validate pValue; callers do.<br>
/// <var>pKind</var>: "search" or "identifier"<br>
/// <var>pPattern</var>: DocType pattern "Cat:Name", "Cat:*" or "*"<br>
/// <var>pValue</var>: search table class name or Identifier path; "" removes the binding<br>
/// Returns: $$$OK, or the error from saving or deleting the row (removing a binding that does not exist is OK)
ClassMethod Set(pKind As %String, pPattern As %String, pValue As %String = "") As %Status
{
    Set tId = pKind_"||"_pPattern
    If pValue = "" {
        If ..%ExistsId(tId) Quit ..%DeleteId(tId)
        Quit $$$OK
    }
    Set tB = ..%OpenId(tId)
    If '$IsObject(tB) Set tB = ..%New(), tB.Kind = pKind, tB.Pattern = pPattern
    Set tB.Value = pValue
    Quit tB.%Save()
}

/// Finds the binding that applies to a DocType: the exact pattern first, then "Cat:*", then "*".<br>
/// <var>pKind</var>: "search" or "identifier"<br>
/// <var>pDocType</var>: the DocType "Cat:Name"; "" checks only the "*" binding<br>
/// Returns: the bound value (search table class or Identifier path), or "" when nothing matches
ClassMethod Resolve(pKind As %String, pDocType As %String) As %String
{
    Set tV = ""
    If pDocType '= "" {
        Set tV = ..ValueOf(pKind, pDocType)
        If tV = "" Set tV = ..ValueOf(pKind, $Piece(pDocType, ":", 1)_":*")
    }
    If tV = "" Set tV = ..ValueOf(pKind, "*")
    Quit tV
}

/// Reads one binding row without locking.<br>
/// <var>pKind</var>: "search" or "identifier"<br>
/// <var>pPattern</var>: the exact pattern to look up<br>
/// Returns: the stored value, or "" when the row does not exist
ClassMethod ValueOf(pKind As %String, pPattern As %String) As %String [ Private ]
{
    Set tB = ..%OpenId(pKind_"||"_pPattern, 0)
    Quit $Select($IsObject(tB):tB.Value, 1:"")
}

Storage Default
{
<Data name="BindingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Value</Value>
</Value>
</Data>
<DataLocation>^JVDoc.BindingD</DataLocation>
<DefaultData>BindingDefaultData</DefaultData>
<IdLocation>^JVDoc.BindingD</IdLocation>
<IndexLocation>^JVDoc.BindingI</IndexLocation>
<StreamLocation>^JVDoc.BindingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
