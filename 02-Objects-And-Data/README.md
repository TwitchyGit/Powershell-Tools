# Objects and data

This unit shows how PowerShell stores, reshapes and serializes data.

The scripts cover custom objects, hashtables, member access, calculated properties, sorting, grouping and common exchange formats.

Process focus:

- `PsCustomObject.ps1` creates predictable report rows.
- `CalculatedProperties.ps1` adds derived fields without mutating source data.
- `CsvImportExport.ps1` performs a CSV round trip, validates required columns and casts imported values.
- `JsonConversion.ps1` shows nested JSON conversion and round-trip shape.
- `HashtableBasics.ps1` validates required keys in a settings table.
- `OrderedHashtable.ps1` preserves report column order.
- `ObjectMembers.ps1` inspects methods before relying on object behavior.
- `DynamicMemberAccess.ps1` checks dynamic property access.
- `FormatDataVsObjects.ps1` shows why formatting should stay at the display boundary.
- `SelectExpandProperty.ps1` compares wrapped and expanded property output.
- `SortingGrouping.ps1` builds a grouped summary.
- `XmlParsing.ps1` reads XML node attributes safely.
- `Display-PSDStructure.ps1` is the larger utility for rendering PSD1 structure.

Useful checks:

```powershell
./PsCustomObject.ps1
./CalculatedProperties.ps1
./CsvImportExport.ps1
./JsonConversion.ps1
```

Training aim: keep data as objects until the final display or export step.
