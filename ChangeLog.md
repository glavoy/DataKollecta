## [1.2.0+8] - 2026-08-17

### Added
- **DataKollecta: a second product built from this same codebase.** The survey engine — XML parsing, skip/logic/calculation, ID generation, the SQLite schema — is identical; only the sync backend differs. GiSTX keeps FTP/SFTP; DataKollecta talks to a Supabase project over HTTP, with incremental per-record upload instead of one whole-database zip. Selected at build time with a new `--product` flag alongside the existing country `--flavor`:

  ```bash
  dart run tool/build.dart apk                          # GiSTX (default)
  dart run tool/build.dart apk --product datakollecta    # DataKollecta
  ```

  The two products have separate application ids (`com.gistx.gistx` /
  `com.datakollecta.datakollecta`) and separate signing keys, so they install
  side by side rather than updating each other — see `CLAUDE.md`'s "Product
  flavors" section. DataKollecta ported forward from an earlier, unmerged
  implementation that had drifted behind this codebase's engine fixes; several
  real defects in that implementation were fixed along the way, including a
  password and full record data being logged in plaintext, no timeout on any
  HTTP call, an infinite-retry bug where a failed upload batch was silently
  re-sent forever instead of the run ever completing, and every non-Android/
  Windows device reporting the same placeholder `device_id`.
- **`formchanges` gained `changeuniqueid`, `surveyor_id` and `synced_at`** (both products, additive via `ALTER TABLE`), and survey/CRF tables gained `synced_at`. Editing a previously-synced record now clears its `synced_at`, so the correction is picked up by the next DataKollecta sync instead of only the original value ever reaching the server.

### Fixed
- **A calculation could not correctly compare a checkbox field.** A checkbox answer is stored internally as a list of the selected values, and a calculation read it with Dart's default list formatting — `[1, 3]`, brackets included — instead of the comma-joined form skip conditions already use. So a `case` calculation's `when:` condition, a `lookup`, or a SQL query parameter reading a checkbox field never matched the way its literal suggested: `when:screen_cab_drug2 != 99` was true even when `99` was the only thing selected, because `"[99]"` is never equal to `"99"`. Depending on where the condition sat in the `case` block, this could make a later branch — including `else` — unreachable. All four calculation types that read a field's value now see a checkbox answer the same way skip conditions do.
- **A record saved twice by the old Finish double-tap bug (fixed in 1.1.0+7) could no longer be opened for editing.** Because `uniqueid` was declared as a normal survey question rather than the table's actual primary key, nothing stopped two rows sharing the exact same `uniqueid` from both being saved, and the record editor refused to open either one — "Multiple records found. Please select values for all primary key fields" — since it couldn't tell which was authoritative. This surfaced on a real Burkina Faso device, where one subject's interview had been saved three times. The editor now resolves this the same way the server-side data pipeline already does: when rows share an identical `uniqueid`, it silently treats the one with the most recent save time as the record, without deleting anything — the duplicate rows stay on the device and are cleaned up permanently by the pipeline as before. A genuine mismatch (two different people's records that happen to share a primary-key value like a subject ID, but have different `uniqueid`s) still shows the selection prompt exactly as before — this only ever collapses rows that are the same technical duplicate, never a real identity conflict.
- **DataKollecta: uploading pending records could fail with "type 'Null' is not a subtype of type 'int'".** Editing an already-synced record clears `synced_at` on every row sharing its `uniqueid` (see above) — for a record saved twice by the old double-tap bug, that's two rows swept into the same upload batch under one wire id. The uploader tracked wire id → row id as a single-entry map, so the second row silently lost its row id, and if the server ever echoed that wire id back more than once, the row-id count could exceed the row count entirely — surfacing as a fatal cast error that aborted the whole upload, not just the affected record. The uploader now tracks every row sharing a wire id and marks all of them synced together, and a batch row missing a usable row id is skipped and logged rather than aborting every other pending record.

## [1.1.0+7] - 2026-08-10

### Fixed
- **Duplicate records from a second tap on Finish.** Tapping Finish again before the first save completed saved the interview a second time, producing rows identical in every field but the save timestamp — one Burkina Faso interview was stored five times. Three things allowed it: the guard against a repeat save was checked before the questionnaire finished loading but only set afterwards, leaving a window a fast second tap passed straight through; the button was never disabled and gave no sign that anything was happening, so interviewers pressed it again; and the guard was released when the save finished rather than when the screen closed, so a later tap started another save. Finish is now claimed the instant it is pressed, greys out and shows a spinner while saving, and stays disabled once the record exists. This also closes a second route to the same problem: saving, then going back, changing an answer and pressing Finish again added another record instead of updating the first.
- **Decimal fields could not accept a decimal point.** A question with FieldType `text_decimal` was treated as ordinary text: it offered the alphabetic keyboard, converted input to uppercase, and accepted anything typed. It now takes digits and a single decimal point on a numeric keyboard, and a half-typed value such as `12.` keeps Next disabled until it is completed. This affects `height`, `weight`, `muac` and the distance and land fields in the AVERT questionnaires; no data dictionary needs changing.
- **`hourmin` fields now collect a real 24-hour time.** The FieldType was accepted but did nothing. A `hourmin` question now inserts the `:` as the third digit is typed and refuses any entry that could not become a valid time, so `25:00` or `12:65` cannot be recorded. Deleting backwards removes the separator along with the digit it was inserted for.

### Changed
- **One codebase for both countries.** The Burkina Faso variant was maintained on a separate `burkinafaso` branch, which silently drifted from `main` — a fix to special-response handling sat un-ported for months with no failing test to reveal it. The two are now a single branch, and the country is selected when the app is **built** rather than in Settings:

  ```
  dart run tool/build.dart apk                 # Uganda: English, FTP
  dart run tool/build.dart apk --flavor bf     # Burkina Faso: French, SFTP
  ```

  Because the country is a compile-time constant, the Uganda build contains **no country control in Settings at all**, and nothing needs removing from the UI once the Burkina Faso study ends. Both builds keep the same application id and signing key, so either continues to update an existing installation in place.
- **One build script for every target and platform.** `build_apk.ps1`, `build_windows.ps1` and `tool/build_macos_dmg.sh` are replaced by `tool/build.dart`, which behaves identically on macOS and Windows and handles all targets and flavors. It no longer bumps the version: both flavors of a release must carry the same version, and test builds should not consume version numbers. Run `dart run tool/update_version.dart` when cutting a release.

- **The end-of-survey screen now appears in the right language.** The survey generator writes "Press the 'Finish' button to save the data." into every questionnaire, so the Burkina Faso build showed English there — and named a button that actually reads "Terminer". The app now owns that screen's wording and translates it. Because it is matched on both the field name and the exact generated text, a hand-written message is never overwritten, and **no data dictionary needs editing and no survey package needs regenerating** — the fix arrives with the app.
- **System variables no longer have to be declared.** `starttime`, `startdate`, `uniqueid`, `swver`, `survey_id`, `lastmod` and `stoptime` are now written into every questionnaire by the survey generator, in the positions that make them correct: an automatic question records its value when navigation reaches it, so `starttime` goes before the first question and `stoptime` after the last. Where a data dictionary declares one, its row is ignored and replaced, so a variable listed in the wrong place in the spreadsheet still lands in the right place in the survey. Dictionaries may keep declaring them — useful for documenting the variables to analysts — and the generator says so in the log rather than failing. Position is the generator's responsibility alone; the app takes the questionnaire exactly as it finds it.
- **`calc`, `calculation` and `calculated` are accepted** as spellings of `automatic`, so dictionaries written either way load correctly.
- **The Burkina Faso server folder now follows the account.** The build assumed every login on that server kept its files under `/r21`. The test account created for trialling survey packages has them a level deeper, under `/r21_test/r21`, and that layout cannot be changed on our side. The folder is now looked up from the username, so one build serves both the live and test accounts: signing in as the test user reaches the test folder, and every other login behaves exactly as before. The account is stored with each downloaded survey, so a survey collected against the test folder keeps uploading there even after the username in Settings is changed back — test data cannot drift into the live folder.

### Housekeeping
- **Special-response tests now cover both languages.** The widget test previously mocked the stored country setting; it now follows the build flavor, so `flutter test` and `flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"` each assert the correct language.

## [1.0.7+6] - 2026-08-05

### Added
- **`in` / `not in` response filters:** Database-backed response lists now support `in` and `not in` filter operators, which treat the filter value as a comma-separated list. Combined with a `query` calculation field, this allows a question to exclude choices already used elsewhere — for example, offering only the household members who have not yet been recorded as sleeping under another net. An empty list is handled as the natural no-op (`not in` excludes nothing, `in` matches nothing), so the first record of a repeating section behaves correctly.

### Fixed
- **"Don't know" on dynamic radio lists:** A radio question whose CSV- or database-backed response list declares its own `dont_know` value now marks that option as a special response, matching how checkbox questions already behaved.
- **CSV response lists on non-Windows files:** CSV files are now read correctly whether they use Windows (CRLF), Linux/macOS (LF), or legacy Mac (CR) line endings. Previously only CRLF files parsed: anything else was read as a single row, so every question backed by that CSV showed its "no options found" message even though the file was correct. Re-saving the CSV with Windows line endings is no longer necessary.
- **Leading zeros in CSV values:** Values are now stored exactly as written in the CSV. Previously anything that looked like a number was parsed as one, so a fixed-length code such as `056` was stored as `56` and `01` as `1`. Response filters still compare numerically, so padded and unpadded values continue to match each other.
- **Quoted values in CSV files mirrored to the database:** CSV files copied into SQLite (so they can back `source:database` questions) are now read with the same parser used everywhere else. Previously they were split on every comma, so a quoted value containing a comma — a school or village name such as `"St Mary's, Apac"` — was broken into two fields and shifted every later column in that row, and escaped quotes were left in the stored text (`BUSAMBEKO ""A""` instead of `BUSAMBEKO "A"`).
- **Subject ID counter accuracy:** The auto-increment portion of a generated ID (e.g. `subjid`) is now derived only from the ID field itself. Previously every column in the record was scanned, so an unrelated value that happened to share the ID's prefix and digit length could inflate the counter and cause IDs to be skipped.

### Housekeeping
- **ID generation test coverage:** Added unit tests for the subject-ID counter, covering prefix collisions with other fields, empty tables, and non-matching value formats.
- **CSV parsing test coverage:** Added unit tests covering all three line-ending styles, trailing newlines, rows missing a trailing separator, and quoted values containing commas.

## [1.0.6+5] - 2026-07-20

### Added
- **Survey-record search:** Added search to the record selector when viewing or modifying a survey, making it quicker to find the correct existing record.
- **Checkbox LogicCheck operators:** Logic checks now support `contains` and `does not contain` for checkbox and other multi-select values, allowing validation rules to test whether a selected-value list includes or excludes a specific response.

## [1.0.5+4] - 2026-07-13

### Fixed
- **French special-response labels:** For Burkina Faso, "Don't know" and "Refuse" now display in French as "Ne sait pas" and "Refuse de répondre".
- **Vaccine coverage participant message:** Fixed the message shown when there are no "Vaccine coverage" participants so it no longer displays the technical filter text `need_vac_cov=1`.
- **Incomplete decimal validation:** Decimal numeric fields now require a digit after the decimal separator when a decimal is entered. Values such as `120.` are blocked, while whole numbers and completed decimals such as `120`, `120.0`, and `120.5` remain valid.
- **Special-response option layout:** "Don't know" and "Refuse" radio and checkbox options now use the full response width while keeping their distinct highlight colors, preventing awkward text wrapping in longer labels.

## [1.0.4+3] - 2026-07-03

### Fixed
- **SFTP survey download hang:** Downloading a survey from the Burkina Faso server could hang indefinitely. An untracked `pubspec.lock` had silently picked up a `dartssh2` release that rewrote the SSH transport's internals; pinned back to the previously known-good `2.18.0`. Also added a 2-minute timeout to the SFTP download as a safety net against future stalls.
- **Survey download timeout:** Added a 2-minute timeout to the FTP survey zip download, so a stalled connection now fails clearly instead of hanging indefinitely.

### Housekeeping
- **`pubspec.lock` now tracked in git:** A blanket `*.lock` rule in `.gitignore` was unintentionally excluding it, so dependency versions could drift between machines/builds without anyone noticing.
- **Fixed the version-bump tool:** `tool/update_version.dart` was silently dropping the build number instead of incrementing it.

## [1.0.3+2] - 2026-07-01

### Fixed
- **Stale answers after skip navigation:** Forward postskip and preskip jumps now clear answers for every bypassed question before processing automatic fields, including chained skip routes. Primary-key and protected fields remain intact.
- **Cleared answers in modified surveys:** Answers cleared by skip logic are now written back to SQLite as `null`, preventing old values from remaining in saved records.

### Changed
- **macOS application icon:** Replaced the default Flutter icon with the GiSTX branding and configured repeatable macOS launcher-icon generation.

## [1.0.2] - 2026-06-22

### Added
- **Special responses for text & combobox questions:** "Don't know" and "Refuse" buttons are now available on `text` and `combobox` questions, matching the existing behaviour for `radio`, `checkbox`, and `date` types. Selecting one records the configured value (e.g. `-7`) and bypasses the field's format, length, mask, and numeric-range validation.
- **Display fields on linked-survey selection:** When selecting a child/sister survey, the parent-record selector now shows the configured `display_fields`, making records easier to identify.

### Fixed
- **Logic checks with negative/decimal values:** Logic-check conditions now accept signed and decimal numeric literals (e.g. `cattle = -7`). Previously these threw an "Invalid condition format" error.
- **Numeric range vs. special responses:** Selecting a special response (e.g. "Don't know") on an integer field that has a min/max range no longer blocks navigation with a range error.

### Changed
- **Build tooling:** Upgraded Gradle, the Android Gradle Plugin, and Kotlin; removed the deprecated `kotlin-android` plugin.

### Housekeeping
- Stopped tracking the contents of the `tmp/` working folder.

## [1.0.0] - 2026-06-12

First stable 1.0 release.

### Added
- **Burkina Faso SFTP support:** Added SFTP transfers via `dartssh2`, with the server and port (2220) selected automatically, so a Burkina Faso build can use that server.
- **French localization:** Translated the UI to French for the Burkina Faso build — error messages, placeholders, and special-response button labels.
- **Desktop builds:** Added macOS build support and a macOS/Linux `SharedPreferences` fallback.
- **Release signing:** Release builds are now signed from `key.properties`.

### Fixed
- **Upload verification:** FTP uploads are now verified before being reported as successful, preventing false "upload succeeded" results.

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
