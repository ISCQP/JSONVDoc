/// Persistent storage for JVDoc DocType field trees (SQL table JVDoc.SchemaDef).
/// Each row stores a normalized field tree as JSON, identified by Category and Name.
/// The registration methods for per-DocType search tables and Identifier paths validate their input
/// and store the bindings in JVDoc.Binding; a trigger maintains ^JVDoc.Ver to invalidate per-process caches on schema changes.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/27
Class JVDoc.Schema Extends %Persistent [ SqlTableName = SchemaDef ]
{

/// First part of the DocType (e.g. "Demo" in "Demo:Order"); forms half of the composite primary key.
Property Category As %String(MAXLEN = 64) [ Required ];

/// Second part of the DocType (e.g. "Order" in "Demo:Order"); forms the other half of the composite primary key.
Property Name As %String(MAXLEN = 64) [ Required ];

/// Normalized field tree (JSON): {name, type, desc, vals, opt, children:[], items:{}}
Property Tree As %Stream.GlobalCharacter;

Index PK On (Category, Name) [ IdKey, PrimaryKey, Unique ];

// ---------------- Field tree storage and per-process caches ----------------

/// Persists or overwrites the field tree for the given Category/Name pair; the BumpVersion trigger then invalidates cached copies.<br>
/// <var>pCategory</var>: first part of the DocType ("Demo" in "Demo:Order")<br>
/// <var>pName</var>: second part of the DocType ("Order" in "Demo:Order")<br>
/// <var>pTree</var>: normalized field tree root (type "object" with children), as built by SchemaImport or SchemaInfer<br>
/// Returns: the status of %Save
ClassMethod Save(pCategory As %String, pName As %String, pTree As %DynamicObject) As %Status
{
    Set s = ..%OpenId(pCategory_"||"_pName)
    If '$IsObject(s) { Set s = ..%New(), s.Category = pCategory, s.Name = pName }
    Do s.Tree.Clear()
    Do pTree.%ToJSON(s.Tree)
    Quit s.%Save()
}

/// Bumps ^JVDoc.Ver for the DocType after any insert, update or delete, through objects or SQL,
/// so that every process drops its cached tree (GetTree) and type map (TypeAt)
Trigger BumpVersion [ Event = INSERT/UPDATE/DELETE, Foreach = row/object, Time = AFTER ]
{
    Set x = $Increment(^JVDoc.Ver({Category}_":"_{Name}))
}

/// Reads the field tree of a DocType. The parsed tree is kept in the process-wide variable %zJVDocTree
/// and refreshed when ^JVDoc.Ver changes; callers must not modify it.<br>
/// <var>pDocType</var>: the DocType "Cat:Name"<br>
/// Returns: the field tree root as a %DynamicObject, or "" when the DocType does not exist
ClassMethod GetTree(pDocType As %String)
{
    Set ver = +$Get(^JVDoc.Ver(pDocType))
    If $Get(%zJVDocTree($Namespace, pDocType, "ver"), -1) = ver Quit $Get(%zJVDocTree($Namespace, pDocType))
    Set tree = ""
    Set s = ..%OpenId($Piece(pDocType, ":", 1)_"||"_$Piece(pDocType, ":", 2, *))
    If $IsObject(s) {
        Do s.Tree.Rewind()
        Set tree = {}.%FromJSON(s.Tree)
    }
    Set %zJVDocTree($Namespace, pDocType) = tree, %zJVDocTree($Namespace, pDocType, "ver") = ver
    Quit tree
}

/// Looks up the declared JSON type at a path; used by SetValueAt for type coercion.
/// The path-to-type map is cached per process in ^||JVDoc.Types and rebuilt when ^JVDoc.Ver changes.<br>
/// <var>pDocType</var>: the DocType "Cat:Name"; "" gives "any" for every path<br>
/// <var>pNormPath</var>: normalized path with array indexes removed, e.g. "items().qty"<br>
/// Returns: "string", "integer", "number", "boolean", "object", "array" or "any"; "any" when the path is not in the field tree
ClassMethod TypeAt(pDocType As %String, pNormPath As %String) As %String
{
    If pDocType = "" Quit "any"
    Set ver = +$Get(^JVDoc.Ver(pDocType))
    If $Get(^||JVDoc.Types(pDocType)) '= ver {
        Kill ^||JVDoc.Types(pDocType)
        Set tree = ..GetTree(pDocType)
        If $IsObject(tree) Do ..Flatten(tree.children, "", pDocType)
        Set ^||JVDoc.Types(pDocType) = ver
    }
    Quit $Get(^||JVDoc.Types(pDocType, pNormPath), "any")
}

/// Fills the process-private ^||JVDoc.Types map for one DocType: every normalized path (arrays as "name()") to the declared type of the node, recursing into object children.<br>
/// <var>pChildren</var>: children array of an object node<br>
/// <var>pPrefix</var>: normalized path of that object node; "" for the root<br>
/// <var>pDT</var>: the DocType whose map is being filled
ClassMethod Flatten(pChildren As %DynamicArray, pPrefix As %String, pDT As %String) [ Private ]
{
    Set it = pChildren.%GetIterator()
    While it.%GetNext(.k, .c) {
        Set p = pPrefix_$Select(pPrefix = "":"", 1:".")_c.name
        If c.type = "array" {
            Set p = p_"()", el = c.items
        } Else {
            Set el = c
        }
        Set ^||JVDoc.Types(pDT, p) = el.type
        If (el.type = "object") && $IsObject(el.children) Do ..Flatten(el.children, p, pDT)
    }
}

// ---------------- Per-DocType registrations (stored in JVDoc.Binding) ----------------

/// Registers the search table class that indexes a DocType when its documents are saved.<br>
/// <var>pDocType</var>: "Cat:Name", "Cat:*" (every DocType in the category) or "*" (all DocTypes)<br>
/// <var>pClass</var>: a compiled class extending Ens.VDoc.SearchTable; "" removes the binding<br>
/// Returns: $$$OK, or an error when pDocType is empty, the class does not exist or is not a search table class
ClassMethod SetSearchTable(pDocType As %String, pClass As %String = "") As %Status
{
    If pDocType = "" Quit $$$ERROR($$$GeneralError, "DocType is empty")
    If pClass = "" Quit ##class(JVDoc.Binding).Set("search", pDocType)
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) Quit $$$ERROR($$$GeneralError, "Class not found: "_pClass)
    If '$classmethod(pClass, "%Extends", "Ens.VDoc.SearchTable") Quit $$$ERROR($$$GeneralError, pClass_" is not a search table class (Ens.VDoc.SearchTable)")
    Quit ##class(JVDoc.Binding).Set("search", pDocType, pClass)
}

/// Finds the search table class for a DocType. Resolution order: exact DocType, then "Cat:*", then "*".<br>
/// <var>pDocType</var>: the DocType "Cat:Name"<br>
/// Returns: the search table class name, or "" when nothing is registered
ClassMethod GetSearchTable(pDocType As %String) As %String
{
    Quit ##class(JVDoc.Binding).Resolve("search", pDocType)
}

/// Registers the path used to read the Identifier property for a DocType.<br>
/// <var>pDocType</var>: "Cat:Name", "Cat:*" (every DocType in the category) or "*" (all DocTypes)<br>
/// <var>pPath</var>: VDoc path to a single value, e.g. "order_id" or "items(1).sku"; "" removes the binding<br>
/// Returns: $$$OK, or an error when pDocType is empty, the path does not parse or contains an empty ()
ClassMethod SetIdentifierPath(pDocType As %String, pPath As %String = "") As %Status
{
    If pDocType = "" Quit $$$ERROR($$$GeneralError, "DocType is empty")
    If pPath = "" Quit ##class(JVDoc.Binding).Set("identifier", pDocType)
    Set sc = ##class(JVDoc.Document).ParsePath(pPath, .segs)
    If $$$ISERR(sc) Quit sc
    // Identifier must resolve to a single scalar; a bare () without an index reads the element count instead
    Set n = $Order(segs(""), -1)
    For i = 1:1:n {
        If $List(segs(i), 2) && ($List(segs(i), 3) = "") Return $$$ERROR($$$GeneralError, "Identifier path must resolve to a single value; give an index instead of empty (): "_pPath)
    }
    Quit ##class(JVDoc.Binding).Set("identifier", pDocType, pPath)
}

/// Finds the Identifier path for a DocType. Resolution order: exact DocType, then "Cat:*", then "*".<br>
/// <var>pDocType</var>: the DocType "Cat:Name"<br>
/// Returns: the Identifier path, or "" when nothing is registered
ClassMethod GetIdentifierPath(pDocType As %String) As %String
{
    Quit ##class(JVDoc.Binding).Resolve("identifier", pDocType)
}

Storage Default
{
<Data name="SchemaDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Tree</Value>
</Value>
</Data>
<DataLocation>^JVDoc.SchemaD</DataLocation>
<DefaultData>SchemaDefaultData</DefaultData>
<IdLocation>^JVDoc.SchemaD</IdLocation>
<IndexLocation>^JVDoc.SchemaI</IndexLocation>
<StreamLocation>^JVDoc.SchemaS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
