# JVDoc — JSON Virtual Document for InterSystems IRIS

*InterSystems IRIS 2026.x · Interoperability*

A Dynamic Object has no schema, so there are no fields to drag in the DTL graphical editor. JVDoc turns a JSON message into a Virtual Document: the schema comes from a JSON Schema or a sample JSON, and the DTL editor, the rule editor, search tables and validation can all use it directly, while the message itself is still stored as it arrived and passes through without loss.

## The problem

Processing JSON in Interoperability is common, and Dynamic Objects are convenient, but they have no schema, which causes three annoyances:

- The DTL editor shows no field tree, so you cannot drag to create a mapping and have to write code by hand.
- The rule editor offers no field suggestions when you type `Document.{`.
- Message Viewer cannot search by a field inside the message.

The usual approach is to generate classes with %JSON.Adaptor. That solves graphical mapping, but it has two costs: every message must first be instantiated as an object, which is expensive for large messages, and fields that are not in the schema are dropped on import, so lossless pass-through is not possible.

## The idea

The IRIS Virtual Document framework (Ens.VDoc.Interface) was designed for structured documents that have no matching class: editors get the field tree through it, and at run time values are read and written by path. JVDoc implements JSON on top of this interface:

- The original JSON stream is stored, and parsed into a Dynamic Object only on the first path access.
- A message that was modified is re-serialized when it is saved; one that was not modified stays byte-for-byte identical.
- A DocType is written as `Category:Name` and corresponds to one field tree; editors, rules, search tables and validation all read the same tree.
- Paths look like `a.b(2).c`, and arrays are written as `name()`, for example `items().sku`.

## Quick start

```bash
git clone https://github.com/ISCQP/JSONVDoc.git
cd JSONVDoc
docker compose up -d
```

The demo environment starts automatically. Management Portal: http://127.0.0.1:55773/csp/sys/Utilhome.csp (superuser / SYS, namespace TESTBED).

A PetStore REST endpoint is available at `http://127.0.0.1:55773/PetStoreService/PetStore` — POST a JSON pet message and watch it route through the Production.

## Main features

### 1. Generate a DocType from a JSON Schema or sample JSON

The field tree can come from three sources:

- **JSON Schema** (draft-07 / 2019-09 / 2020-12): `$ref`, allOf, oneOf/anyOf, if/then/else, dependentRequired, dependentSchemas, additionalProperties and all constraint keywords are supported. The field tree can be exported back as a JSON Schema (2020-12).
- **Sample JSON**: one or more sample messages; fields are unioned, types decided by majority, required fields are those that appear in every sample.
- **Stored messages**: messages already in the message store; only the structure is recorded.

| You have | Call | You get |
| --- | --- | --- |
| A JSON Schema whose root is the message | `SchemaImport.FromFile(cat, name, path)` or `FromJSONSchema(cat, name, schema)` | One DocType |
| One JSON Schema file describing several models | `SchemaImport.FromBundleFile(cat, path)` or `FromBundle(cat, schema)` | One DocType per model |
| One sample message | `SchemaInfer.FromSample(cat, name, json)` | One DocType, all fields optional |
| Several sample messages | `SchemaInfer.FromSamples(cat, name, array, , required)` | One DocType |
| Messages already in the store | `SchemaInfer.FromStoredDocs(cat, name, filterDocType, max)` | One DocType |

Rule of thumb: if the file root *is* the message, use `FromFile`; if the file is a catalogue of models, use `FromBundle`.

### 2. Graphical mapping in DTL

Choose `JVDoc.Document` as source and target class, pick the DocType, and drag fields exactly as you would for HL7:

- An assignment with `()` on both sides (e.g. `items().sku` → `lines().code`) expands element by element automatically.
- Values are converted to the correct JSON type (number, boolean, null) on write; unmapped fields are kept when `create='copy'`.

### 3. Lossless pass-through

A message that is only read and never modified is byte-for-byte identical after it passes through the Production, is saved and reopened — including whitespace, number formatting, and fields outside the schema.

### 4. Routing rules

In the rule editor, type `Document.{` and the field list pops up. Constraints are filled in separately: message class `JVDoc.Document`, document category and document name matching the two parts of the DocType.

### 5. Message Viewer search

Two ways to find messages by JSON content:

- **VDoc Property Path** — no setup needed. Add a criterion of type VDoc Property Path, choose the class `JVDoc.Document` and write the path, e.g. `PetStore:pet:{tags().name} = Labrador`. Match is exact and case-sensitive.
- **Search table** — define a subclass of `Ens.VDoc.SearchTable`, bind it to a DocType with `JVDoc.Schema.SetSearchTable`, and the index is built automatically on save. Search is case-insensitive and fast on large volumes.

### 6. Validation

`JVDoc.Document.Validate` and `ValidateJSON` accept switch letters: `r` required, `t` type, `e` enum, `p` pattern, `b` bounds/length/count, `c` const, `a` additionalProperties, `s` not/contains/propertyNames, `o` oneOf/anyOf, `u` unknown fields. `all` = `rtepbcaso`; `-` prefix turns a letter off.

Use `JVDoc.ValidatingRouter` at the routing entry point to intercept invalid messages before they are routed.

## Known limitations

- The root must be a JSON object.
- Property names containing `.` `(` `)` `{` `}` cannot be accessed by path (they still pass through).
- An array inside an array is not expanded in the DTL tree; the whole value is copied as JSON text.
- External `$ref`, patternProperties and format in JSON Schema are not supported.
- Numbers longer than 18 digits lose precision.

## More information

Community article (EN): https://community.intersystems.com/post/working-json-graphically-intersystems-iris-interoperability-json-virtual-documents
