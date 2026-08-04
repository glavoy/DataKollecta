## [1.0.x-bf+x] - 2026-08-xx

### Added
- **`in` / `not in` response filters:** Database-backed response lists now support `in` and `not in` filter operators, which treat the filter value as a comma-separated list. Combined with a `query` calculation field, this allows a question to exclude choices already used elsewhere — for example, offering only the household members who have not yet been recorded as sleeping under another net. An empty list is handled as the natural no-op (`not in` excludes nothing, `in` matches nothing), so the first record of a repeating section behaves correctly.

### Fixed
- **CSV response lists on non-Windows files:** CSV files are now read correctly whether they use Windows (CRLF), Linux/macOS (LF), or legacy Mac (CR) line endings. Previously only CRLF files parsed: anything else was read as a single row, so every question backed by that CSV showed its "no options found" message even though the file was correct. Re-saving the CSV with Windows line endings is no longer necessary.
- **Leading zeros in CSV values:** Values are now stored exactly as written in the CSV. Previously anything that looked like a number was parsed as one, so a fixed-length code such as `056` was stored as `56` and `01` as `1`. Response filters still compare numerically, so padded and unpadded values continue to match each other.
- **Quoted values in CSV files mirrored to the database:** CSV files copied into SQLite (so they can back `source:database` questions) are now read with the same parser used everywhere else. Previously they were split on every comma, so a quoted value containing a comma — a school or village name such as `"St Mary's, Apac"` — was broken into two fields and shifted every later column in that row, and escaped quotes were left in the stored text (`BUSAMBEKO ""A""` instead of `BUSAMBEKO "A"`).
- **Subject ID counter accuracy:** The auto-increment portion of a generated ID (e.g. `subjid`) is now derived only from the ID field itself. Previously every column in the record was scanned, so an unrelated value that happened to share the ID's prefix and digit length could inflate the counter and cause IDs to be skipped.

### Housekeeping
- **ID generation test coverage:** Added unit tests for the subject-ID counter, covering prefix collisions with other fields, empty tables, and non-matching value formats.
- **CSV parsing test coverage:** Added unit tests covering all three line-ending styles, trailing newlines, rows missing a trailing separator, quoted values containing commas, and zero-padded codes.

## [1.0.6-bf+5] - 2026-07-20

### Added
- **Survey-record search:** Added search to the record selector when viewing or modifying a survey, making it quicker to find the correct existing record.
- **Checkbox LogicCheck operators:** Logic checks now support `contains` and `does not contain` for checkbox and other multi-select values, allowing validation rules to test whether a selected-value list includes or excludes a specific response.

## [1.0.5-bf+4] - 2026-07-13

### Fixed
- **Vaccine coverage participant message:** Fixed the message shown when there are no "Vaccine coverage" participants so it no longer displays the technical filter text `need_vac_cov=1`.
- **French special-response labels:** For Burkina Faso, "Don't know" and "Refuse" now display in French as "Ne sait pas" and "Refuse de répondre".
- **Incomplete decimal validation:** Decimal numeric fields now require a digit after the decimal separator when a decimal is entered. Values such as `120.` are blocked, while whole numbers and completed decimals such as `120`, `120.0`, and `120.5` remain valid.
- **Special-response option layout:** "Don't know" and "Refuse" radio and checkbox options now use the full response width while keeping their distinct highlight colors, preventing awkward text wrapping in longer labels.

## [1.0.4-bf+3] - 2026-07-03

### Fixed
- **SFTP survey download hang:** Downloading a survey from the Burkina Faso server could hang indefinitely. An untracked `pubspec.lock` had silently picked up a `dartssh2` release that rewrote the SSH transport's internals; pinned back to the previously known-good `2.18.0`. Also added a 2-minute timeout to the SFTP download as a safety net against future stalls.

### Housekeeping
- **`pubspec.lock` now tracked in git:** A blanket `*.lock` rule in `.gitignore` was unintentionally excluding it, so dependency versions could drift between machines/builds without anyone noticing.
- **Fixed the version-bump tool:** `tool/update_version.dart` crashed on this branch's `-bf` version suffix and, even on plain versions, silently dropped the build number instead of incrementing it.

## [1.0.3-bf+2] - 2026-07-01

### Fixed
- **Stale answers after skip navigation:** Forward postskip and preskip jumps now clear answers for every bypassed question before processing automatic fields, including chained skip routes. Primary-key and protected fields remain intact.
- **Cleared answers in modified surveys:** Answers cleared by skip logic are now written back to SQLite as `null`, preventing old values from remaining in saved records.

### Changed
- **macOS application icon:** Replaced the default Flutter icon with the GiSTX branding and configured repeatable macOS launcher-icon generation.

## [1.0.2+1] - 2026-06-22

### Added
- **Special responses for text & combobox questions:** "Don't know" and "Refuse" buttons are now available on `text` and `combobox` questions, matching the existing behaviour for `radio`, `checkbox`, and `date` types. Selecting one records the configured value (e.g. `-7`) and bypasses the field's format, length, mask, and numeric-range validation.

### Fixed
- **Logic checks with negative/decimal values:** Logic-check conditions now accept signed and decimal numeric literals (e.g. `cattle = -7`). Previously these threw an "Invalid condition format" error.
- **Numeric range vs. special responses:** Selecting a special response (e.g. "Don't know") on an integer field that has a min/max range no longer blocks navigation with a range error.

### Changed
- **French localization:** Localized the remaining hardcoded English UI strings to French — combobox/date/date-time placeholders, the special-response button labels ("Ne sait pas" / "Refuse de répondre"), and the questionnaire-selector error messages. Wording follows the selected country.

## [1.0.1+1] - 2026-06-16

### Changed
- **Display fields on linked-survey selection:** When selecting a child/sister survey, the parent-record selector now shows the configured `display_fields`, making records easier to identify.
- **Build tooling:** Upgraded Gradle, the Android Gradle Plugin, and Kotlin; removed the deprecated `kotlin-android` plugin.

### Housekeeping
- Stopped tracking the contents of the `tmp/` working folder.

## [1.0.0+1] - 2026-06-12

First stable 1.0 release.

### Added
- **Burkina Faso SFTP support:** Added SFTP transfers via `dartssh2`, with the server and port (2220) selected automatically based on settings, so this build can use the Burkina Faso server.
- **Desktop builds:** Added macOS build support and a macOS/Linux `SharedPreferences` fallback.
- **Release signing:** Release builds are now signed from `key.properties`.

### Changed
- **Full French localization:** Translated all remaining hardcoded English error messages and UI strings to French; English/French wording is selected by country.

### Fixed
- **Upload verification:** FTP/SFTP uploads are now verified before being reported as successful, preventing false "upload succeeded" results.

## [0.0.10] - 2026-02-05

### Fixed
- **Linking field preservation in non-base tables:** Fixed issue where automatic linking fields (e.g., `subjid` in followup surveys) were being overwritten with `-9` when viewing/modifying records. The system now properly preserves existing values for automatic fields that have no registry handler and no calculation configuration, ensuring linking fields in non-base tables maintain their correct values from the parent table throughout the edit process.

## [0.0.9] - 2026-01-30

### Fixed
- **Save retry bug:** The `_isSaving` flag is now reset after the try/catch block completes, regardless of success or failure. This ensures users can retry saving if an error occurs.
- **Database upload mismatch:** The database upload function now correctly uses the database name specified in the `survey_manifest.gistx` file instead of assuming `{surveyId}.sqlite`. This fixes the "Database file not found" error during uploads.
- **Age calculation bug in edit mode:** Fixed critical issue where age calculations using `age_from_date` would recalculate based on today's date instead of the original survey date when editing existing surveys months later, causing incorrect age values.

### Changed
- **Enhanced `age_at_date` calculation:** Now supports field references using double bracket syntax (e.g., `separator='[[startdate]]'`) in addition to hardcoded dates. This allows dynamic date references for age calculations.
- **Deprecated `age_from_date`:** The `age_from_date` calculation type is now deprecated in favor of `age_at_date` with `separator='[[startdate]]'` for clearer, more explicit date referencing. Existing surveys using `age_from_date` will continue to work with a deprecation warning and will automatically use `startdate` as the reference date for backward compatibility.

### Documentation
- Updated `AGE_CALCULATION_GUIDE.md` with new field reference syntax and migration instructions from deprecated `age_from_date` to `age_at_date`.


## [0.0.8] - 2026-01-02

### Fixed
- **Data persistence in skipped questions:** Implemented real-time clearing of answers when skip logic bypasses previously answered questions
  - Added `_clearAnswersInRange()` method to clear data for questions in range being jumped over during forward navigation
  - Modified `_next()` method to detect skip logic jumps and automatically clear affected fields
  - Prevents incorrect data from appearing on information screens and being saved to database
  - Complements existing save-time cleanup with proactive navigation-time clearing



### [0.0.7] - 2025-12-30
* Added 'startdate' automatic field type
* Added `date_offset` calculation type to calculate date-diff between two dates
* Added optional regex formatting (input masking) for text fileds
* Changed the exit prompt when modifying a survey to: "Are you sure you want to cancel. All edits/modifications will be lost!"
* Implemented cascading clear logic for dependent fields so that changing a 'parent' field clears 'child' fields
* Implemented a "Review Changes" system for survey modifications that generates a logical summary replacing technical IDs with human-readable labels and expanding placeholders like `[[participantsname]]`.
* Integrated numeric-aware logic into the summary system to highlight genuine data changes while ignoring benign differences like numeric padding.
* Added three options to the review dialog: Save Changes, Back to Edit, or Discard & Exit, with a secondary confirmation for the discard option.
