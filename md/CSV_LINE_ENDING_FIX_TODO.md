# TODO: Make CSV response parsing robust to line endings

## Status
Not yet fixed. Diagnosed 2026-07-30, reverted so behavior is still stock.

## Symptom
A CSV-backed dynamic response question (`source:csv` in the data dictionary)
shows its `empty_message` (e.g. "No villages found") even though:
- the CSV file is correctly included in the survey zip and extracted alongside the XML,
- the CSV content, headers, and filter/display/value column names are all correct,
- `DbService`'s own CSV import (used to mirror CSV files into SQLite tables) reads
  the exact same file successfully.

Console shows the giveaway:
```
[CsvDataService]   Headers: empty
[CsvDataService]   After filter: 0 rows
[CsvDataService] Returning 0 options from workshop_villages.csv
```
"Headers: empty" only happens when the parsed row list is empty — not a filter
mismatch, the file was never split into rows at all.

## Root cause
`lib/services/csv_data_service.dart`, `loadCsvFile()`:

```dart
final csvString = await file.readAsString();
final rows = const CsvToListConverter().convert(csvString);
```

`CsvToListConverter()` is called with no `eol` argument. When the CSV file uses
plain `\n` line endings (e.g. created/edited on macOS/Linux, or by any tool that
doesn't write Windows-style `\r\n`), the converter fails to split the content
into multiple rows — the whole file is parsed as a single row. After the header
row is stripped off, zero data rows remain, so every dynamic-response question
backed by that CSV silently shows its empty message.

This is inconsistent with `lib/services/db_service.dart`'s `_importSingleCsv()`,
which parses the same files fine because it uses `LineSplitter().convert(content)`
(handles `\n`, `\r\n`, and `\r` automatically) plus manual comma-splitting,
instead of the `csv` package's converter.

## Confirmed workaround (already applied to the workshop kit)
Re-saving the CSV with Windows/CRLF line endings makes `CsvToListConverter`
parse it correctly. This is why `workshop_kit/workshop_villages.csv` was
converted to CRLF — it's a workaround for this bug, not a real fix. Any new
CSV a study team creates on macOS, in a text editor that defaults to LF, or
via a script (like the `workshop_villages.csv` originally was), will hit this
same failure again.

## The actual fix (apply in `csv_data_service.dart`, `loadCsvFile()`)
Normalize line endings before handing the string to `CsvToListConverter`, and
pass `eol` explicitly instead of relying on auto-detection:

```dart
final csvString =
    (await file.readAsString()).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
final rows = const CsvToListConverter(eol: '\n').convert(csvString);
```

This was implemented and reverted in this session at the user's request (they
want to apply and test it themselves later). No other part of `loadCsvFile()`
needs to change — the header-trim and row-mapping logic below already assumes
a clean list of rows and works fine once parsing succeeds.

## Optional follow-up
- Add a unit test under `test/services/` that feeds `CsvDataService` a CSV
  string with LF-only line endings and asserts `getResponseOptions()` returns
  the expected rows, so this can't regress silently again.
- Consider whether `_importSingleCsv` in `db_service.dart` should be the
  canonical CSV parser (already robust to line endings) and have
  `csv_data_service.dart` reuse it instead of maintaining two separate CSV
  readers with different behavior.
