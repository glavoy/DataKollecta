> **Versioning.** `X.Y.Z` names a release and is hand-edited in `pubspec.yaml` when one is
> cut; `+B` names a single binary and increases for every build handed to anyone, test builds
> included (`dart run tool/update_version.dart`). Between releases, changes accumulate under
> `## [UNRELEASED] - TBD`, which is renamed to `## [X.Y.Z+B] - <date>` at release. Commits do
> not get version numbers. See CLAUDE.md's "Versioning" section.

## [UNRELEASED] - TBD

### Changed
- **The parent/child relationship is now a constraint the database enforces, not a convention
  the app remembers.** Survey tables were created with every column a plain `TEXT` — no
  `PRIMARY KEY`, no `UNIQUE`, no `FOREIGN KEY` — and `PRAGMA foreign_keys` was never switched
  on anywhere in the app. So nothing stopped an orphan child, two households sharing an `hhid`,
  or a corrected parent key leaving its children behind. That last one needed no bug at all:
  `hhnum` is typed, so in edit mode the app regenerates `hhid`, and the members already entered
  kept the old one — the household split across two ids, and the next member added got
  `linenum` 1 alongside members 1-5.

  Each table is now created with `uniqueid TEXT PRIMARY KEY`, a `UNIQUE` over every column set
  its children reference, `FOREIGN KEY (linkingfield) REFERENCES parent(...) ON UPDATE CASCADE`
  so a correction carries, and a second `FOREIGN KEY (parent_uniqueid) REFERENCES
  parent(uniqueid)`. Uniqueness follows what children *reference* rather than the primary key,
  because the two are not always the same — one real dictionary links a child on `barcode`
  while its parent is keyed on `subjid`.

  A cascade rewrites children behind the app's back — it never goes through
  `updateInterview` — so each child table also carries an `AFTER UPDATE` trigger that clears
  `synced_at` and writes a `formchanges` row. Without it the device would be corrected while
  the server kept the old key forever: a silent desync, arguably worse than the orphaning.

  **These are declared only at `CREATE TABLE`.** SQLite has no `ALTER TABLE ADD CONSTRAINT`,
  so a device that already created a table keeps it unconstrained — clear the `databases/`
  folder to pick up the new schema. Nothing is deployed, which is the only reason this was
  free; once a survey ships it stops being possible.

- **Every child record now carries its parent's `uniqueid`.** `hhid` stays the
  human-readable business key, but it is built from typed answers, so anything joining on it
  depends on a value an interviewer can edit. `parent_uniqueid` — written by
  `DataKollecta-SurveyGen` onto every form that declares a `parenttable` — holds the parent's
  UUID instead, which cannot be retyped and so cannot drift. No wire, Edge Function or Postgres
  change: the whole row already uploads as schema-free JSONB.

- **The sibling ordinal (`linenum`/`netnum`) deliberately carries no `UNIQUE`.** A duplicate is
  a counter bug the interviewer never typed, and every row carries a `uniqueid`, so it stays
  reconcilable — whereas a `UNIQUE` would make the insert *fail*, and in field research a lost
  interview is worse than an identifier reconciled later. Duplicates are found with a report
  (`GROUP BY <link>, <inc> HAVING COUNT(*) > 1`). A duplicate *parent* key is refused, because
  there is no equivalent escape: with `incrementLength: 0` there is no spare digit to move, and
  a duplicate means a second copy of a household that already exists.

### Fixed
- **A change summary could list an edit that was never recorded.** Four places each decided,
  their own way, whether two answers are the same answer — the padding check in
  `AnswerValidationService`, the change summary, the `formchanges` writer in `DbService`, and
  the has-anything-changed check in `AnswerStorageService`. Only the last treated
  `2025-12-09 11:22` and `2025-12-09T11:22` as the same moment, and only two read a checkbox
  answer the way the rest of the codebase reads one.

  That mattered in edit mode, where a stored date is parsed back into a real `DateTime` on
  load: on every save one side is a `DateTime` and the other is the text it came from. So on a
  save where something else had genuinely changed, the summary shown to the interviewer could
  include a date the database never recorded a change for.

  All four now share one rule (`AnswerEquality`), the most tolerant of what the four already
  intended: same text, or the same number written differently, or the same instant written
  differently. A consequence worth knowing when comparing across versions — **fewer
  `formchanges` rows are written**, because a value re-rendered into another format no longer
  counts as an edit. That is the intended effect, not data loss; every row that stops being
  written was recording a change that did not happen.

- **The child increment counter had two implementations that disagreed.**
  `survey_screen._calculateLineNum` grouped a household's children by `crfs.primarykey`'s
  *first* field via a `SELECT MAX`, while `parent_id_selector_screen._getNextIncrementNumber`
  grouped by `crfs.linkingfield` after reading the whole child table into Dart. Which number an
  interviewer got depended only on which screen they came through; in current dictionaries the
  two agree by luck. `linkingfield` is now authoritative — it defines parentage and is what the
  foreign key is declared on — and there is one implementation.

  The selector's counter was also dead as far as stored data goes: `_calculateLineNum` runs
  after prepopulated answers are merged and assigns unconditionally, so it always overwrote it.
  Its number only ever reached the "Next linenum: N" subtitle, which could therefore disagree
  with what was saved. That subtitle now comes from one grouped query instead of a
  `FutureBuilder` built inside `build()`, which launched a full-table read per visible row per
  rebuild — including on every keystroke in the search box.

- **A failed counter read now writes `0` instead of `1`.** The counter starts at 1, so `0` is a
  value no legitimate record holds and `WHERE linenum = 0` finds every degraded row, where `1`
  was indistinguishable from a legitimate first child and so left no trace. Unlike the
  subject-ID sentinel this is a flat constant, not a reserved band: `idconfig.incrementLength`
  sizes a primary key's suffix and says nothing about how many children a parent may have.
  `0` also needs no exclusion from the counter's `MAX`, so one failed read cannot poison a
  parent's sequence.

- **Editing a record could regenerate its own primary keys.** `RecordSelectorScreen` did not
  pass `linkingField` or `incrementField` to `SurveyScreen`, and two of the clauses deciding
  whether a field is an ID to generate are comparisons against exactly those — while
  `SurveyNavigationService` routes hidden primary keys through that path *precisely in edit
  mode*. With both null, every primary-key field of a record being edited reached
  `IdGenerator`, so reopening a child record could renumber its `linenum`. The comparison was
  also case-sensitive against a hand-typed worksheet cell; it is now case-insensitive, and the
  predicate moved to `SurveyNavigationService.isGeneratedIdField` where it can be tested.

- **The real-time duplicate-key check could not fire for the survey it matters most to.** It
  was only consulted from `_onAnswerChanged`, which runs for the question the interviewer is
  currently on — and where both halves of a composite key are `type='automatic'` with no
  `<calculation>`, neither ever renders, so the check had never once fired. It now also runs
  where the key is computed. Separately, `getPrimaryKeyFields` returned the worksheet's case
  verbatim while `getAllPrimaryKeys` returned SQLite's, so a sheet saying `HHID` made every
  comparison miss and every record collapse to the same empty signature; both now lowercase.

- **A failed record count could be written onto the parent as `0`.** `getRecordCount` reported
  a read failure as `0`, and mode-3 reconciliation writes that number — so a failure could set
  `nmembers = 0` on a household with five members. The only thing preventing it was the count
  question happening to declare `minvalue='1'`; a dictionary omitting its `numeric_check` had
  no protection. There is now `tryGetRecordCount` with the same null-means-failure contract
  `tryGetMaxIdIncrement` carries, and reconciliation declines to write when the count is
  unknown. Its table name also goes through the identifier guard; it was interpolated raw.
- **A subject ID generated while the database could not be read is now identifiable instead of
  a silent duplicate.** `DbService.getExistingRecords` reports every failure as an empty list,
  and `IdGenerator` read that as "this table holds no records" — so a locked, corrupt or
  otherwise unreadable database made the counter restart at 1 and hand the next interview an ID
  that was already enrolled. Nothing surfaced: the interviewer saw a normal-looking `GX57001`,
  and the collision only appeared later during analysis. (`_getNextIncrement`'s own
  `catch { return 1 }` never even ran — the layer below had already converted the failure into
  an empty list.)

  The record is still saved — losing an interview is worse than issuing an ID that has to be
  reconciled, and every record already carries a `uniqueid` UUID that keeps a duplicate
  resolvable. What changed is that the ID now announces itself: a new
  `DbService.tryGetExistingRecords` returns `null` for a failed read (a *missing* table stays
  an empty list, since it cannot hold a colliding ID), and on `null` the generator issues a
  value from a reserved band at the top of the increment range — 9999 for a four-digit
  increment, then 9998, 9997… driven by a persisted per-device counter, since the one thing it
  cannot do there is ask the table which sentinels are taken. `WHERE subjid LIKE '%999'` finds
  every degraded record.

  Two supporting changes make that safe. `nextIncrementFrom` now **ignores** values in the
  reserved band, so a degraded ID cannot poison the counter — records 001-042 plus a sentinel
  9999 still yield 043; without that, one transient failure would push `MAX` to 9999 and
  wedge every subsequent record. And it now throws `IdCapacityException` rather than return an
  increment too wide for the scheme: `padLeft` does not truncate, so 1000 in a three-digit
  increment silently produced an eight-character `GX571000`. That check applies to any survey
  that genuinely fills its range, not just the degraded path.

- **A new version of a survey can now be installed on a device that already has an earlier one
  (DataKollecta).** The extraction guard in `SurveyConfigService.initializeSurveys` refused any
  zip whose manifest `databaseName` was already claimed by a different `surveyId` — which is
  exactly what a new version looks like, since versioning a survey means a new `surveyId` (so
  the updated XML lands in a new folder and is actually read) onto an unchanged `databaseName`
  (so `DbService` opens the existing SQLite file, `ALTER TABLE`s the new questions in, and the
  subject-ID counter carries on). The guard now refuses only a genuine **cross-project**
  collision, matching `HttpSyncBackend._guardAgainstCollision` on the download path; an owner
  with no known project binding — a side-loaded zip — is allowed through, as that path already
  does. GiSTX was already exempt (see the 2026-08-31 AVERT incident recorded in the code
  comment) and is unaffected.

  This is the app half of survey versioning in `DataKollecta-Web`, which now models versions
  explicitly (`survey_packages.survey_code` + `version`) and enforces two things about
  `databaseName`: every version of a survey must declare the same one, and no two surveys
  anywhere on the platform may declare the same one. The second rule is platform-wide rather
  than per-project or per-account because this is a *device*-global namespace — `DbService`
  opens every survey's database from one flat `databases/` folder named by `databaseName`
  alone, with no project or account segment in the path, and a field worker can belong to
  projects owned by different accounts. See `docs/DATABASE_VERSIONING_DECISIONS.md`.

### Housekeeping
- **`flutter analyze` now actually checks something.** `analysis_options.yaml` had
  `include: package:flutter_lints/flutter.yaml` commented out and an empty `rules:` block, and
  `flutter_lints` was not even a dev dependency — so "No issues found!" over 16,000 lines meant
  only that nothing tripped the analyzer's built-in errors. Enabling it surfaced 53 issues.

  The 24 worth having were **`use_build_context_synchronously`**: a `BuildContext` used after an
  `await`, which throws if the widget went away while the future was in flight. Most are on the
  save path in `survey_screen.dart` — a review dialog shown after the change summary is
  computed, the auto-repeat prompts, the parent-count reconciliation — plus the date/time picker
  pair in `question_views.dart`, where backing out between picking a date and picking a time hit
  it. Each now carries a guard, and the guard is `context.mounted` rather than `mounted`
  wherever the method takes its own `BuildContext` parameter: those are different objects, and
  the analyzer says so ("guarded by an unrelated 'mounted' check"). `_showDone`,
  `_checkAndStartAutoRepeat` and `_reconcileRepeatCount` all had `mounted` checks already that
  were guarding the wrong thing.

  The rest were mechanical (`dart fix`): brace-less `if` bodies, dangling library doc comments,
  `??=`, angle brackets in doc comments. The three raw `print()` calls in production catch blocks
  are now `debugPrint` with the codebase's bracketed prefix. `path_provider_platform_interface`
  is declared as a dev dependency, since the survey-config tests import it directly.
- **Tracked files that were never source are gone.** `build_log.txt`,
  `build_log_vs2022.txt` (byte-identical to it), `doctor_log.txt` and `dist.iml` were committed
  build and diagnostic output — `.gitignore` covers `*.log` but these were written as `.txt`, so
  they slipped past it. `.idea/` is untracked too; `workspace.xml` changes on every window move.
  All four patterns are now ignored.
- **`test/generate_dynamic_wide_format.py` and `test/get_wide_data.sql` deleted.** Neither is a
  test, and both query an `interviews`/`answers`/`options`/`questions` schema — an
  entity-attribute-value model the app does not have. It creates `crfs`, `formchanges`, and one
  table per form with a column per fieldname, so these could never have run against a current
  database.
- **`md/` is now explicitly an archive.** The fifteen topic guides moved to `md/archive/` behind
  a `md/README.md` that says plainly that nothing in it is maintained, names
  `TECHNICAL_README.md` as the known-wrong one, and points at `CLAUDE.md`, `docs/` and
  SurveyGen's README instead. They were previously indistinguishable from current documentation
  to anyone — or anything — grepping the repo. `Automatic Variables Migration Examples.txt`,
  loose in the repo root as a `.txt`, joined them: its worked XML examples are still readable,
  but the authoritative reference for that format is SurveyGen's README, and the app should not
  hold a second copy of the spec. `README.md`'s link to `md/BUILD_INSTRUCTIONS.md` now points at
  `CLAUDE.md`, which is where the build and release flow is actually maintained.
- **`db_service.dart` is a text file again.** Its synthetic-key prefix in
  `collapseDuplicateUniqueIds` was written as a literal NUL byte in the source rather than the
  `\u0000` escape. Dart compiled it either way, but the NUL made the whole 1,200-line file
  register as binary — `grep` skipped it silently and `git diff` refused to show it, which is
  an easy way to miss something while editing it.
- **`DbService.getNextIncrementValue` no longer swallows its errors.** The child-record counter
  (`linenum`, `netnum`) has the same shape of hazard as the subject-ID counter above — a failed
  read restarts it at 1 and duplicates within the household — but its `catch` returned 1 with no
  log line at all, so the duplicate left no trace. Now logged. An unpadded counter has no spare
  range to carry a sentinel the way a padded subject ID does, so this is a floor, not a fix.
- **GiSTX's own update path now has a test.** Two zips with different `surveyId`s and the same
  `databaseName` both extracting under a GiSTX build is the documented way to ship a survey
  revision there, but nothing pinned it — which is how the guard came to block it silently in
  the field on 2026-08-31 (a new AVERT version refused forever, with no error surfaced
  anywhere). `test/services/survey_version_extraction_test.dart` covers that alongside the
  DataKollecta cases: same project allows, different project refuses, no known project binding
  allows. The suites are gated on `AppConfig.isDataKollecta` so both product builds pass.
- **`docs/DATABASE_VERSIONING_DECISIONS.md` brought up to date.** It recorded a decision — hand-
  maintain `databaseName` in each new manifest, and adopt a `projectId` field later — that the
  portal has now answered differently, so the manual checklist it prescribes is a machine check
  for DataKollecta. Its citation of `_syncSurveyTable()` at "lines 379-452" was also stale.

- **A throttled login is now understood as a throttle, not as a retryable transfer error.** The
  server returns HTTP 429 when a username has been locked out after ten failed attempts, and the
  app had no case for it: an unrecognised status fell through to
  `SyncTransferException('Login failed (429)')`, which the sync run treats as worth **retrying**.
  Retrying a lockout extends it and loads the endpoint that just asked the device to stop.

  A new `SyncThrottledException` joins the sealed family rather than reusing either existing
  type, because both would lose something concrete. `SyncAuthException` stops the run correctly
  but the sync screen maps it to fixed "invalid credentials" copy, which would discard the wait
  time -- the only part of a throttle response an interviewer can act on. So the throttle carries
  the server's wording verbatim to the screen and stops rather than retries, and
  `RecordUploader` reports `UploadStopReason.throttled` with its own sentence: folded into the
  failure count it would read as data loss, when nothing is wrong with the records.

  `postSync` maps 429 the same way even though `app-sync` does not throttle today, so a 429 from
  a gateway or a future per-device limit cannot be retried. The 413 batch cap deliberately stays
  retryable -- that one is the client's own fault and a smaller batch is a sensible retry.

  This shipped **before** the server switched from 401 to 429, on purpose: reversed, there would
  be a window where a build in the field meets a status it mishandles.

- **The subject-ID counter is one SQL aggregate instead of a whole-table read.** Generating an
  ID used to call `getExistingRecords`, which materialises every row and lowercases every key
  of every row, to compute `MAX` of one column in Dart. On a table with 20,000 records that is
  a visible pause at the moment the interviewer is waiting. It is now a single
  `SELECT MAX(...)` with the reserved sentinel band excluded in the `WHERE` clause rather than
  filtered afterwards, so a degraded ID cannot push `MAX` to the top of the range.

  Three query details each avoid a trap, and each has a test: the base ID is matched with
  `substr(col, 1, n) = ?` rather than `LIKE '<base>%'`, because SQLite's `LIKE` is
  ASCII-case-insensitive *and* would treat a `%` or `_` inside a dictionary-supplied prefix as
  a wildcard; the increment is gated on `GLOB '[0-9]...'` rather than a bare `CAST`, because
  `CAST('12x' AS INTEGER)` is `12` in SQLite while `int.tryParse('12x')` is null, so a `CAST`
  alone would let a malformed value advance the counter; and a value stored as `INTEGER`
  rather than `TEXT` still counts, which is what a CSV import or a legacy row can leave behind.

- **Upload batches hold 25 records, not 10.** Eight hundred records collected offline went in
  80 HTTP requests; now 32. The server caps a request at 500 rows, and the constant's comment
  records that ceiling so a future build raising 25 can see what it must stay under.

  Recorded as a decision, because it was briefly built the other way: this was first
  implemented as a Settings dropdown and then reverted. Batch size is not a question to put to
  an interviewer — it has no meaning in their work, they have no way to judge an answer, and a
  wrong answer makes uploads worse. It is tuned in the code and shipped in a build.

- **`SurveyScreen` no longer runs its "load existing primary keys" block twice.** The block
  appeared verbatim, comment included, two times in initialisation, so every new record ran two
  `getPrimaryKeyFields` queries and two full-table `getAllPrimaryKeys` reads. Idempotent, so
  the result was right and only the cost was wrong — but that cost lands before the first
  question appears on screen.

- **The child counter's SQL identifiers are quoted.** `getNextIncrementValue` interpolated its
  table, increment column and primary-key column straight into the statement. All three come
  from a data dictionary's crfs sheet and cannot be bound as parameters, which is why
  `_quoteIdentifier` exists and why the sibling subject-ID query already used it; this was the
  one place that bypassed it. It also had no test at all, so the query is now split into a
  `@visibleForTesting nextIncrementValueIn` with seven of them.

- **A doc comment that read as a guarantee now reads as an open hazard.**
  `getExistingRecords` says callers that only display records are fine with a failed read
  flattening to an empty list. `parent_id_selector_screen._getNextIncrementNumber` derives a
  child increment from it, so a failed read there still becomes increment 1 and a duplicate
  `linenum` inside a household. It cannot be fixed alone: that screen and
  `getNextIncrementValue` are two implementations of the same counter that group a household's
  children by *different* columns (`crfs.primarykey`'s first field versus `crfs.linkingfield`),
  so which answer an interviewer gets depends only on which screen they came through. Choosing
  between them is a design question, and it is the parent/child integrity work's first one.

- **Every held-back dependency now records why.** `dartssh2` and `intl` already carried their
  reasons inline; `device_info_plus`, `flutter_secure_storage`, `package_info_plus`, `csv` and
  `xml` did not, so a future pass — human or agent — would re-litigate each one and possibly
  re-break what was already fixed. Versions unchanged; this is deliberately documentation and
  not an upgrade.

- **Three build-time `debugPrint`s removed from `question_views.dart`.** One per radio build,
  one per checkbox build, and one per checkbox *option* per build, which together put 11 lines
  into every `flutter test` run, interleaved with the progress line so the tail was unreadable.
  The four that remain in that file all sit behind an `if` or on an error path.

- **The three largest files are decomposed, and `survey_screen.dart` has tests for the first
  time.** The code review's last open item. `survey_screen.dart` went 2,308 → 1,899,
  `db_service.dart` 2,004 → 1,589, and `question_views.dart` 1,282 → 1,024. The suite went from
  392/392/394 to 485/485/487 across the three build axes — 93 new tests, all of them covering
  code that had none.

  The rule for `SurveyScreen` was that nothing moved unless a test moved with it, because no test
  file references it and there is no `test/screens/` directory: `flutter analyze` and
  `flutter test` passing proves nothing about that file. Five services came out with a test file
  each — `ChildIncrementService` (the sibling ordinal), `DuplicateKeySnapshot` (the real-time
  primary-key check), `AnswerValidationService` (per-keystroke validation),
  `AnswerStorageService` (the pure steps of the save path) and `RepeatPlanService` (which child
  forms auto-repeat). What stayed is everything that needs a `BuildContext`: `build`, the save
  orchestration, every dialog, and `_processAutomaticQuestion` — an automatic question is
  computed when navigation reaches it, so moving it can change what a record stores and no test
  would notice.

  One extraction needed care and is worth recording. The validation rules signalled "incomplete
  input" with a bare `return` inside a `setState` closure, which also skipped the duplicate-key
  check that followed. Returning just a message would have started running that check on
  half-typed keys — a behaviour change wearing a refactor's clothes — so the result carries
  `stopsFurtherChecks` and there are tests on both sides of the line.

  From `db_service.dart`, the pure schema builders became `SurveyTableSchema` (they were the
  covered half, so the move is provable) and the SQL backup journal became `DbBackup`.
  `DatabaseException` moved to its own file so the schema layer need not import `DbService`,
  which exposed a latent collision: sqflite exports a `DatabaseException` too, and ours only won
  by being declared locally. sqflite's is now hidden. The survey-table CRUD was deliberately left
  alone — every write path goes through one chokepoint, and splitting it would cost the property
  that makes the file readable.

  From `question_views.dart`, the four input formatters and `AppRadioTheme` moved out; the eight
  render arms did not. The arms are the easy part, and the 246-line seeding layer beneath them is
  where a silent behaviour change would live.

  Four dead members of `QuestionView` are gone: two `ScrollController`s that were constructed and
  disposed but never attached to a widget, and the `onRequestNext`/`logicError` parameters, which
  were passed on every build and read nowhere. `_deepCopyAnswers` is now `_snapshotAnswers`,
  since it was neither deep nor a copy of anything but lists — and it produces `_originalAnswers`,
  the baseline every change comparison and the `formchanges` audit are measured against.

## [1.3.6+17] - 2026-09-01

### Added
- **`calc:timestamp`: an explicit calculation type for mid-questionnaire timestamps.**
  Previously, a custom timestamp field (distinct from the reserved `starttime`/`stoptime`) was
  authored implicitly — an `automatic`/`datetime` field with a *blank* Responses column, left to
  fall through to a runtime default. That shape turned out to be ambiguous: `survey_screen.dart`'s
  primary-key-detection heuristic treated any unregistered automatic field with no calculation as
  an ID field whenever the questionnaire had an `idconfig`, so these blank-Responses timestamp
  fields were silently stamped with a generated subject-ID-shaped value instead of a clock reading.
  `calc:timestamp` (`DataKollecta-SurveyGen`) removes the ambiguity: it's authored the same
  explicit way every other calculation is, always requires `FieldType: datetime`, and always
  generates with `preserve: true` baked in (freezing the captured time across a later edit, the
  same way `starttime`/`stoptime` do — this generator has no other way to author `preserve` from
  Excel). The old implicit fallback is removed entirely: an `automatic`/`datetime` field with a
  blank Responses column is now a build-blocking generator error, not a special case.

### Fixed
- **GiSTX/DataKollecta: automatic fields could be silently misrouted into ID generation.**
  `_processAutomaticQuestion`'s `isIdField` check (`survey_screen.dart`) matched *any* automatic
  field that wasn't in the `AutoFields` registry and had no calculation, whenever the
  questionnaire had an `idconfig` — written before "blank Responses + `datetime` FieldType" existed
  as a second legitimate meaning for that same shape (see `calc:timestamp` above). Two categories
  of field could be hit: custom timestamp fields (stamped with a generated ID instead of the
  current time — confirmed against real field data, see below), and, in a hierarchy with a
  parent-child link, a CRF's own `linkingfield`/`incrementfield` (e.g. `hhid`/`linenum`) on a
  questionnaire that also has its own `idconfig` for a different primary key — both already get
  their real value from elsewhere before this check runs, so being caught here could silently
  overwrite a correct linked/incremented value with a freshly-generated or `-9` sentinel one. The
  check now also excludes `datetime`-typed fields (no legitimate ID target is ever typed datetime)
  and this screen's own `linkingField`/`incrementField`. Found while tracing why
  `avert_ug_test_2026_07-13.sqlite`'s `time_eligible`/`time_start_vac_coverage`/
  `time_start_mal_risk_factors`/`time_start_smc` columns held subject-ID-shaped values instead of
  timestamps.

## [1.3.5+16] - 2026-08-31

### Fixed
- **GiSTX could no longer install a new survey version onto an already-installed device.**
  A `databaseName`/`surveyId` collision guard added in 1.3.2+10 (to stop a DataKollecta phone
  holding two different projects' surveys from silently sharing one physical database) ran
  unconditionally for every product, including GiSTX -- which has no multi-project concept at
  all. `DataKollecta-SurveyGen`'s documented way to version a survey is a new `surveyId` per
  release with the *same* `databaseName` on purpose (so the subject-ID counter and existing
  data survive the update), which is exactly the shape the guard mistook for a collision: every
  such update was silently refused, forever, with no error shown anywhere in the UI -- the FTP
  download itself succeeded, the survey just never appeared on the main screen. The guard is
  now DataKollecta-only, where the collision it protects against can actually happen.
- **GiSTX never actually saved a survey's FTP credentials.** `_associateCredentialsWithDownloadedSurvey`
  resolved a downloaded survey's ID by matching the zip's filename against the manifest's
  human-readable display name -- different strings under `DataKollecta-SurveyGen`'s normal
  naming convention (e.g. `avert_ug_2026_08_31` vs `AVERT UG 2026-08-31`), so the match always
  failed and the credentials were silently never saved, for any survey, ever. Every upload
  therefore used whatever was currently sitting in the global Settings fields, regardless of
  which login actually downloaded the currently active survey -- switching between two surveys
  downloaded under two different logins could upload data under the wrong one. Now resolves the
  survey directly from its known extraction folder instead of matching a display name.

### Changed
- **GiSTX's Surveyor ID is now preserved per survey.** A field worker can legitimately be
  assigned a different Surveyor ID per project, but it was a single global value baked into
  every upload's filename regardless of which survey was active -- switching surveys could
  tag an upload with the wrong ID. A survey's Surveyor ID is now captured alongside its
  credentials the moment it's downloaded, and resolved per-survey (falling back to global
  only when a survey has none saved yet) whenever it's uploaded.
- **Settings is a pure staging area, unconditionally** -- it always shows and only ever
  writes the credentials/Surveyor ID that will apply to the *next* download, never a
  specific already-installed survey's stored values. An earlier version of this change made
  Settings show, and Save correct, whichever survey happened to be active; live testing found
  that actively corrupts data (typing credentials meant for a not-yet-downloaded survey and
  saving silently overwrote an unrelated already-active survey's real association) and, once
  that was fixed, still looked like data loss (a just-saved edit appeared to vanish when you
  navigated away and back without downloading). A survey's actual, correct association is
  created only by a successful download, and is only ever visible via Sync Center or the
  credentials an upload actually uses.

## [1.3.3+13] - 2026-08-29

### Fixed
- **Uganda FTP uploads now use a hostname controlled by IDRC.** Network Solutions silently
  moved the FTP endpoint from its legacy `netsolhost.com` address to a generated
  `registeredsite.com` hostname, breaking field uploads. Uganda now connects through
  `ftp-sync.idrcdata.org`, an IDRC-managed DNS alias, so a future provider hostname migration
  needs a DNS update rather than another app release. If that alias is temporarily unavailable,
  the app tries the current provider hostname once as a fallback. Burkina Faso's separate SFTP
  connection is unchanged.

## [1.3.2+12] - 2026-08-24

### Fixed
- **DataKollecta could hang forever on a blank spinner after the splash screen**, with no
  crash and no visible error. `MainScreen`'s startup sequence ran unawaited inside `initState`,
  so an exception during it was silently swallowed by Flutter's default release-mode error
  handler, leaving `_isLoading` stuck at `true`. Root cause on the device this was found on:
  Android's Keystore-backed encryption key had stopped matching data already written to disk
  (`BadPaddingException`/`BAD_DECRYPT`), which `SettingsService` had no handling for. Startup
  failures now surface a real error screen with a Retry button, and a secure-storage decrypt
  failure is treated as "nothing stored" and wipes the corrupted store -- one bad key means
  every entry in that file is equally unreadable, so resetting it lets subsequent reads/writes
  succeed under a working key instead of failing the same way forever.
- **Local macOS builds (`dart run tool/build.dart macos`) failed with "No profiles for
  'com.gistx.gistx' were found"**, needing an Xcode GUI run-then-stop workaround every time.
  The Runner target's signing had drifted to `Automatic`/Apple Development/a specific team,
  which needs Xcode to generate a real provisioning profile and stopped resolving; the
  project's own base signing was already ad-hoc. Reverted Runner to that ad-hoc default and
  removed the unused `keychain-access-groups` entitlement (macOS never uses Keychain --
  `SettingsService` already falls back to `shared_preferences` there for exactly this reason),
  which was the one remaining thing still requiring team-based signing. CLI builds now succeed
  end to end with no Xcode step required.

## [1.3.2+10] - 2026-08-24

### Fixed
- **DataKollecta could only hold one project's login session at a time.** Logging into a
  second project silently overwrote the first project's stored token, so uploading a survey
  from Project A after logging into Project B could send Project A's records under Project
  B's session -- normally rejected server-side and left pending, but silently misrouted if the
  two projects happened to reuse the same Survey ID. `SettingsService`'s single
  `project_code`/`api_username`/`api_password`/`auth_token` set is replaced by a per-project
  document (`sync/project_sessions.dart`) that remembers every configured project and which
  project each locally-known survey came from, so upload always routes to the right one and
  re-logs in silently when a token has expired. A `surveyId`/`databaseName` collision between
  two projects (both are device-global storage keys) is refused outright rather than allowed to
  silently share one on-device database.

### Changed
- **Settings' single Project Code field is now a list.** Add or remove projects individually;
  "Check for Updates" polls every configured project in one tap, and "Upload" flushes every
  installed survey, each routed to its own project -- there is still no project switcher.



### Changed
- **A `comments` field is no longer optional by name.** `_isAnswered` hardcoded
  `fieldname.toLowerCase() == 'comments'` as always-skippable, for any QuestionType, regardless
  of what the survey XML actually declared -- the only way to get a skippable text field at all.
  A question is now optional only when the XML explicitly says so
  (`<optional>1</optional>`, from the data dictionary's new `Optional` column), which any text
  question can now use, not just one hardcoded name. **Any existing survey package with a
  `comments` field must be regenerated with `Optional` set before this version reaches the
  field**, or that field becomes mandatory and an interview cannot be finished without typing
  something into it.

### Fixed
- **Skipping to the end of a questionnaire could fabricate a value for a custom calculation.**
  `_advanceToEnd` (the handler for `skip to end`) computed every automatic question it walked
  past, including author-declared `calc:` fields, using whatever was in `answers` at that point --
  and an unanswered input isn't a short-circuit for a calculation, it's read as empty (`auto_fields.dart`'s
  `_answerText`), which for a `math` calculation becomes `0`, not blank. A calculation whose inputs
  sat past the point the interview actually reached could silently record a real-looking but
  fabricated number. It now nulls a custom `calc:` field caught in that range instead of computing
  it, matching the rule `clearAnswersInRange` already applies to an ordinary skip. The reserved
  trailing system fields (`uniqueid`/`swver`/`survey_id`/`lastmod`/`stoptime`) and registry-only
  automatic fields with no `calc:` block (`yyyy`/`yy`/`mm`/`dd`/`doy`, which read no other answer)
  are unaffected and are still computed. A survey author who needs a calculation to always have a
  value must place it before any skip that could bypass it.

## [1.3.1+9] - 2026-08-22

### Added
- **`yyyy`/`yy`/`mm`/`dd`/`doy`: five new automatic fields, and a `date_part` calculation to match.** `idconfig`'s auto-increment counter is a `MAX()` over the survey's own local SQLite table, which Android deletes entirely on uninstall — so the counter silently restarts at 1 and can issue a subject ID that collides with one already generated (and possibly already synced) before the reinstall. A survey can fold `yy` and `doy` (day of year, `001`–`366`) into `idconfig.fields` alongside an interviewer/device code, so the ID's base changes every calendar day and the counter only has to stay collision-free within one interviewer's one day, not for the life of the study — a real, if partial, risk reduction rather than a guarantee (a same-day reinstall-and-continue can still collide). The other three (`yyyy`, `mm`, `dd`) exist for the same reason `yy`/`doy` are useful beyond ID composition: a survey wanting just the current month for a seasonal skip, or a year for a label, shouldn't need to invent one. (This started as just `yy`/`ddd`, narrowly scoped to the ID use case; broadened here to the full, obvious set once it was clear the narrower framing undersold them.)

  Unlike `starttime`/`uniqueid` and the other **reserved** system variables, these are **not** auto-injected — a data dictionary has to declare a row for each, positioned before whatever field reads it. The generator's auto-injection only knows two positions, "before the first question" or "after the last one" (`LEADING_SYSTEM_FIELDS`/`TRAILING_SYSTEM_FIELDS` in `DataKollecta-SurveyGen/models.py`), which fits a value every record needs computed at a fixed moment — these don't fit that, so they're opt-in per form instead. They can be declared on **any** worksheet, including a repeating child form with no `idconfig` of its own — `KNOWN_AUTOMATIC_FIELDS` in `DataKollecta-SurveyGen/models.py` exempts them from needing a `calc:` block by name alone, since the app can compute them on any form regardless of whether that form's own `idconfig` happens to reference them. (An earlier version of this exemption was tied to `idconfig.fields` membership on the *same* table and rejected `yy`/`ddd` declared anywhere else — found and fixed before release, alongside this rename/expansion.)

  All five are plain `AutoFields` registry entries, computed the same way `startdate` already is, with **no `calc:` configuration** — this is deliberate: a survey author declaring one via `calc:constant value:NOW_YEAR` or similar would get no protection against being recomputed when an existing record is edited on a later day, which would silently mint a *new* subject ID for the same person mid-edit, since `IdGenerator`'s own edit-mode check (`hasBaseIdChanged`) rebuilds the ID's base fields from the current answers and only preserves the stored `subjid` if that rebuild matches. These fields avoid the recompute risk because, like `starttime`/`startdate`, the app preserves an already-stored value unconditionally rather than depending on a `preserve` flag a survey author could forget to set. Purely additive — a survey that doesn't declare any of them is completely unaffected.

  **`ddd` is now `doy`.** `ddd` for day-of-year wasn't a real convention anywhere (POSIX uses `%j`; R uses `yday()`) and collided with Excel's own custom date-format meaning for `ddd` — abbreviated weekday name, in the exact tool used to author these dictionaries. Decided and renamed before this shipped to any real survey config, so there was no migration cost.

  **New `date_part` calculation type**, for extracting a component from a date field *other* than today — `dob`, an appointment date, anything else the survey collects — which the five fields above can't do (they only ever mean "today"). `calc:date_part`, with `field` (the source, or `today`) and `unit` (`yyyy`/`yy`/`mm`/`dd`/`doy`). Unlike the fixed fields, it recomputes on every edit by default, correct for tracking a live source — a survey wanting it frozen would use `preserve: true`, except that, like every calculation type in this generator, there is currently no way to author `preserve: true` from the Excel dictionary at all (a pre-existing gap, not introduced here).
- **The build number is now visible, so a field-test build can be identified.** Between releases the release version does not move, and every test build carried the same version string as every other — the Settings screen showed `v1.2.0`, and so did the `swver` recorded on every record, because both read only the version *name* and ignored the build number beside it. The Android APK had no version in its filename at all, and successive macOS DMGs overwrote each other. All four now carry the build number: Settings reads `v1.3.0+9`, records store `swver = DataKollecta 1.3.0+9`, and artifacts are named `datakollecta-1.3.0-build9.apk` / `DataKollecta-1.3.0-build9.dmg`. A tester can now read their exact build off the Settings screen, and any record they collected identifies the binary that produced it. **`swver`'s format changes for all future records** — same free-text shape, with `+<build>` appended; existing records are untouched.
- **`dart run tool/build.dart --bump`** bumps the build number and builds in one step, so a test build cannot go out on a number that was already used. It is deliberately opt-in: a release is built once per product and flavor, and those artifacts must all share one build number.

### Changed
- **`repeat_enforce_count=3` (Auto-sync) now tells the interviewer when it corrects the count.** It previously wrote the corrected count with no UI at all — only a `debugPrint` a field interviewer would never see — so a household enumerated as 3 members that turned out to have 2 could have its `nmembers` silently rewritten with nothing on screen to explain why the number changed. It still offers no choice (that's mode `1`'s job, and remains unchanged), but now shows a single acknowledgement dialog naming the old and new count immediately after the write. The `LowerRange`/`UpperRange` gate that keeps an impossible count unwritable applies exactly as before.
- **Stopping a repeat loop early now warns about the count *before* you confirm, not only after.** The child form's own Cancel/X dialog was also the generic "Cancel Interview... all edits will be lost!" warning reused unchanged inside a repeat loop — misleading, since confirming there only discards the one in-progress record, not the parent or the records already saved, and it said nothing about the count you were about to leave short. Inside a repeat loop it now reads "Skip This &lt;entity&gt;?" and, in modes `1` and `3` when stopping now would leave the count short, names the consequence up front: "You've entered X of Y &lt;records&gt;. If you stop now, [you'll be asked whether to update / the count will be automatically updated to] X." Mode `2` is unaffected, since the loop already blocks completion there instead of offering to cancel.
- **`tool/update_version.dart` now bumps only the build number.** It used to increment the patch digit and the build number together, so it could only ever produce a PATCH release — it had no way to express a release that adds functionality, which is why the project documentation told you not to run it at all. It now advances `+B` and never touches `X.Y.Z`: the counter that must never repeat is automated, and the release number, which is a judgement call, stays a deliberate hand-edit of `pubspec.yaml`. Pre-release suffixes such as `1.3.0-rc.1+9` are carried through untouched, and it now rewrites only the `version:` line rather than the whole file.

### Fixed
- **A repeating section's count could not be trusted after the interview moved on.** `repeat_enforce_count` decides what happens when the number of child records entered does not match the count declared on the parent — how many household members, sleeping structures or nets were said to be there. It was only ever evaluated at the end of the auto-repeat loop that follows the parent's save, and the loop only runs when a *parent* form is saved. So a household member added later — *New Survey → Household Members → pick the household* — or one edited through *Modify Existing Survey* never touched `nmembers`: a household enumerated as six members stayed six forever, however many members the device actually held. The count is now reconciled wherever the number of children can change, using the same rules in both places: when the repeat loop ends, and whenever a child record is saved on its own. `repeat_enforce_count=1` offers to correct the count as before; `=3` corrects it silently; `=0` still never checks, and `=2` remains a loop-only rule because there is nothing to block outside the loop.
- **Auto-syncing a count could write a number the questionnaire itself forbids.** `repeat_enforce_count=3` wrote whatever it counted, bypassing the range check every typed answer has to pass. Backing out of the very first household member would silently rewrite `nmembers` from 6 to 0 — a value the interviewer could not have entered, since the question declares a `LowerRange` of 1. The count is now checked against the `LowerRange`/`UpperRange` on the count question in the parent's `_dd` worksheet — the same check, `other_values` exceptions included — before anything is written. Below `LowerRange` nothing is written and, inside the repeat loop, the interviewer is told how many are required and cannot leave until they have entered them, whatever the enforce mode. Above `UpperRange` they are warned and the data left for correction. A count question that was **skipped** is stored as NULL and is now left as NULL, so a household that answered "no" to owning nets keeps `nnets` empty even if a net record is later added by hand — previously nothing distinguished a skipped count from a declared one. **To require at least N records of a repeating form, set `LowerRange` on its count question**; there is deliberately no separate setting on the `crfs` worksheet, so the minimum cannot drift out of step with the question it constrains. A count question with no range declared behaves exactly as before.
- **A corrected count never reached the server if the record had already been uploaded.** Updating a single field — which is how an auto-synced count is written — wrote only that column: it left `synced_at` set, so a record already sent kept its old count on the server forever, and it recorded nothing in `formchanges`, so a value the app changed on the interviewer's behalf left no trace at all. Single-field updates now go through the same bookkeeping as any other edit: `synced_at` is cleared so the row is re-uploaded, `lastmod` is refreshed, and the change is written to `formchanges` with the surveyor's id. A write that would not actually change the stored value is skipped entirely, so nothing is queued for re-upload without cause.
- **A survey could be left with no questionnaires after an app update.** The `crfs` table holds the app's list of forms. It was created only when absent and otherwise cleared and repopulated from the survey manifest, with no way to add a column an older build had never created. Installing an app whose manifest names a newer column over a device carrying an older `crfs` table therefore deleted every row and then failed to insert any of them, leaving the table empty — and an empty `crfs` means the questionnaire list is empty and the survey cannot be opened, with nothing but a debug log to say why. Missing columns are now added by `ALTER TABLE` before anything is written, matching how `formchanges` has always been migrated; the clear-and-repopulate runs in a transaction, so a row that will not insert rolls back to the previous working configuration instead of leaving none; a manifest naming a column this build genuinely does not know about now keeps the rest of the row rather than failing the whole survey; and a `crfs` table that ends up empty is logged as the serious fault it is.
- **The Windows installer can now package DataKollecta.** `installer.iss` was written for GiSTX alone and hard-coded every product-specific value — the name, `gistx.exe`, the GiSTX icon and a single `AppId` — so building DataKollecta for Windows produced an installer that called itself GiSTX, looked for an executable that was not there, and would have replaced any existing GiSTX installation rather than sitting beside it. The script now takes its identity from `windows/installer_config.iss`, which the build writes, and selects name, executable, icon, output filename and `AppId` from it. DataKollecta has its own `AppId`, so the two install and uninstall independently, exactly as their separate Android `applicationId`s already ensured. Building for Windows on a non-Windows host now fails immediately with an explanation instead of part-way through Flutter.
- **The DataKollecta Windows executable now wears its own icon.** `windows/runner/resources/app_icon.ico` is compiled into the executable from a fixed path, and nothing ever swapped it per product, so a DataKollecta Windows build shipped with the GiSTX icon on the exe, the taskbar and the Start menu. The build now copies `assets/branding/<product>.ico` into place alongside the other per-product build inputs, and reverts it afterwards like the rest. That file is also what the installer uses for its own icon, so each product has exactly one icon serving both. GiSTX's icon is unchanged artwork but now carries its 16/32/48 px sizes into the executable as well as the 256 px one — previously only 256 px was compiled in, so Windows downscaled it for the taskbar and file listings. `flutter_launcher_icons`' Windows generation is switched off, since it would overwrite that file with a single-size GiSTX icon whatever product was being built.
- **The Windows installer no longer carries its own copy of the version.** `installer.iss` hard-coded `MyAppVersion "1.0.3+2"` while the app shipped `1.2.0+8`, so every Windows installer built in between was labelled 1.0.3+2 in Add/Remove Programs and in its own setup filename — five releases of drift from a second number kept in sync by hand. The version is now written to `windows/installer_version.iss` from `pubspec.yaml` on every Windows build and included by the installer script.

### Housekeeping
- **`tool/build.dart --help` no longer contradicts the project documentation.** It recommended running `tool/update_version.dart` to bump a release version, which `CLAUDE.md` explicitly told you not to do; it now describes what that script actually does.
- **The numeric range check has one definition.** `LowerRange`/`UpperRange` validation was written out twice in the survey screen — once to show the error and once to gate the Next button — and the auto-synced count bypassed both. It now lives in `NumericValidationService.isWithinRange`, which all three call, so a value the app writes cannot be one the form would have rejected.
- **Question-cache loading is no longer copied between screens.** The record selector and the parent-ID selector each carried their own copy of the "load this survey's questions if they are not cached" routine; both now call `QuestionCacheService.ensureLoadedForSurvey`.
- **Test coverage for repeat-count reconciliation, range checks and the `crfs` migration.** New unit tests cover every enforce mode against a real household/members schema — matching, short, over, zero, above the maximum, no declared range, and a skipped count — plus the re-upload and audit behaviour of a single-field update, `isWithinRange` including its exception list, the `crfs` upgrade, unknown-column and failed-repopulate paths, and the build-number bump (including that it never alters `MAJOR.MINOR.PATCH`).
- **Documentation corrected.** The survey generator's README described an "Exit Anyway" escape in `repeat_enforce_count=2` that the app has never offered, and neither it nor the app's own CRF documentation said that enforcement depends on `auto_start_repeat`, or what happens when the count falls outside the count question's declared range. All three documents now match the app.

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
