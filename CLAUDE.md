# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Country flavors (single branch)

There is **one branch**. The country is chosen at **build time**, not at runtime, via
`AppConfig.country` (`lib/config/app_config.dart`), which reads a `--dart-define`:

| Build | `AppConfig.country` | Language | Server |
|---|---|---|---|
| default | `Uganda` | English | FTP, port 21 |
| `--dart-define=GISTX_COUNTRY="Burkina Faso"` | `Burkina Faso` | French | SFTP, port 2220, `r21` path prefix |

Because `country` is a compile-time constant, `AppConfig.isFrench` and
`AppConfig.isDefaultCountry` fold away during compilation: the Uganda build contains no
country control in Settings at all, and neither build needs a setting to switch.

The French/SFTP variant used to live on a `burkinafaso` branch, which silently drifted
from `main` (a `dont_know` fix sat un-ported for months). It has been merged in.

**`main` is the only branch to work on.** The `burkinafaso` branch is kept frozen — and
the tag `burkinafaso-final` marks its tip — purely so an old APK can be rebuilt from it if
a serious bug ever needs a fix on the pre-merge code. Do not commit to it; anything
committed there will not reach `main` and the drift starts again.

**Rules when touching country-specific behavior:**

- Add UI strings to `lib/services/app_strings.dart` (both languages), never as literals in a widget.
- Gate country-specific UI on `AppConfig.isDefaultCountry`, so nothing Burkina-specific appears in the Uganda build.
- **Never use Gradle product flavors for this.** They conventionally add an `applicationIdSuffix`, which makes the second build a separate app that cannot update the first — orphaning the survey database already on the device. `--dart-define` cannot change the application id, which is why it is used here. Both flavors must keep `applicationId = "com.gistx.gistx"` and the same keystore.

## Product flavors: GiSTX vs DataKollecta (two independent axes)

This codebase ships two separate products: **GiSTX** (FTP/SFTP sync, the
axis described above) and **DataKollecta** (Supabase/HTTP sync). This is a second,
independent build axis from *country* — the two must never be conflated:

| Axis | Changes app identity? | Compile-time constant | Values |
|---|---|---|---|
| Country | No — same app, different market | `AppConfig.country` | `Uganda` (default), `Burkina Faso` |
| Product | **Yes** — separate apps | `AppConfig.product` | `gistx` (default), `datakollecta` |

`country` must never change `applicationId`, the keystore, or the storage folder, because
Uganda and Burkina Faso are two markets for *one* app that must be able to update itself in
place. `product` must always change those things — GiSTX and DataKollecta are meant to
install side by side as separate apps, not update each other — which is exactly why the
country axis is forbidden from using Gradle product flavors but the product axis needs
something with equivalent effect. See `AppConfig.isDataKollecta` / `AppConfig.storageFolder`
/ `AppConfig.appName` / `AppConfig.brandingAsset` in `lib/config/app_config.dart` — all fold
away at compile time via `String.fromEnvironment('APP_PRODUCT', ...)`, so a GiSTX build
carries no HTTP/Supabase code and a DataKollecta build carries no FTP/SFTP code.

DataKollecta never sets `GISTX_COUNTRY` — it always builds as the unflavored default
(Uganda/English), which is why `AppConfig.isFrench` and its French strings are unreachable
in a DataKollecta build. It has its own `applicationId` (`com.datakollecta.datakollecta`)
and its own signing key (`android/key-datakollecta.properties`, gitignored like
`key.properties`), so the two products carry independent signing certificates.

**The product axis is driven by generated per-product config files, not Gradle flavors
either** — flavors would force `--flavor` onto every Android command permanently, and
Windows has no flavor concept at all. `tool/build.dart` copies
`tool/product/<platform>/<product>.*` over four native project files immediately before
each build, then restores them to their committed GiSTX-default content in a `finally`
block once the build finishes (success or failure):

| Generated file | Platform | Read by |
|---|---|---|
| `android/product.properties` | Android | `android/app/build.gradle.kts` (applicationId, signing file, app label, launcher icon dir) |
| `windows/product.cmake` | Windows | `windows/CMakeLists.txt` (`BINARY_NAME`, via `include()` so CMake reconfigures automatically) |
| `windows/runner/product_strings.h` | Windows | `main.cpp` (window title) and `Runner.rc` (the six `StringFileInfo` values) |
| `macos/Runner/Configs/AppInfo.xcconfig` | macOS | Already Xcode's single source of truth for `PRODUCT_NAME`/`PRODUCT_BUNDLE_IDENTIFIER`/`PRODUCT_COPYRIGHT`; this generated file *is* that file, not a separate indirection |

**Never hand-edit any of those four files directly** — edit the matching template under
`tool/product/` instead. Their committed content in the repo is always the GiSTX product, so
a fresh checkout or a build that skipped the tool stays buildable, and `git status` stays
clean between builds.

```bash
dart run tool/build.dart apk                            # GiSTX Uganda       -> gistx.apk
dart run tool/build.dart apk --flavor bf                # GiSTX Burkina Faso -> gistx-bf.apk
dart run tool/build.dart apk --product datakollecta      # DataKollecta       -> datakollecta.apk
```

`--flavor` is rejected for a product that doesn't vary by country (checked in
`tool/build.dart`, not just documented).

## Commands

```bash
flutter pub get                 # install dependencies
flutter analyze                 # static analysis (analysis_options.yaml)
flutter test                    # run all tests
flutter test test/services/db_service_test.dart   # run a single test file
flutter test --plain-name "explicit null update"  # run a single test by name

# language-dependent widget tests must pass in both flavors, and the DataKollecta
# product axis must pass its own suite (see "Product flavors" above)
flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"
flutter test --dart-define=APP_PRODUCT=datakollecta

flutter run -d windows|macos|linux|chrome                              # GiSTX Uganda
flutter run -d macos --dart-define=GISTX_COUNTRY="Burkina Faso"        # GiSTX Burkina Faso
flutter run -d macos --dart-define=APP_PRODUCT=datakollecta            # DataKollecta
```

One build script for every target, product, and flavor, working the same way on macOS and
Windows:

```bash
dart run tool/build.dart apk                            # GiSTX Uganda       -> gistx.apk
dart run tool/build.dart apk --flavor bf                # GiSTX Burkina Faso -> gistx-bf.apk
dart run tool/build.dart apk --product datakollecta      # DataKollecta       -> datakollecta.apk
dart run tool/build.dart windows                         # -> build/windows/runner/Release/gistx.exe
dart run tool/build.dart macos                           # -> installer_output/GiSTX-<version>.dmg
```

The build script **never changes the version** — both flavors of a release must carry the
same version, and test builds should not consume version numbers. Bump deliberately when
cutting a release, by hand-editing `version:` in `pubspec.yaml`. `tool/update_version.dart`
only ever increments the patch digit, which understates a release that adds real functionality
rather than just fixing bugs — semver's MINOR is for that, and the script has no path to it. Do
not run `tool/update_version.dart`; choose the version bump yourself instead.

When cutting a release, update `ChangeLog.md` (Added/Changed/Fixed/Housekeeping sections per version) alongside the version bump.

## Architecture

GiSTX and DataKollecta are offline-first Flutter survey/data-collection apps built from this one codebase (see "Product flavors" above). Surveys are defined in XML and rendered as dynamic multi-page questionnaires; all responses are stored locally in SQLite. There is no bundled `assets/surveys` folder — surveys are downloaded/side-loaded as zip packages and extracted at runtime (see below), which is a departure from `md/TECHNICAL_README.md` (that doc describes an older, asset-bundled version of the app and is stale on this point; treat it as a conceptual reference for skip/logic/validation semantics, not as ground truth for survey loading or storage paths).

### Survey packaging and multi-survey storage (`SurveyConfigService`)

- Each survey is a zip containing one or more question-XML files plus a `survey_manifest.gistx` (JSON) with `surveyId`, `surveyName`, and `databaseName`.
- Zips are placed in `<platform-base-dir>/GiSTX/zips/` and extracted once into `<platform-base-dir>/GiSTX/surveys/<zip-name>/` (idempotent — skipped if the target folder already exists).
- The "active survey" is just a name stored in `SettingsService`; `SurveyConfigService.getActiveSurveyId()` resolves it to a `surveyId` by scanning manifests in the surveys directory. Multiple surveys can be installed side by side, each with its own manifest, credentials, and database.
- Platform base dir differs: Android → external storage dir, Windows → `%LOCALAPPDATA%`, Linux/macOS → application support dir.
- **`databaseName` in the manifest must stay stable across survey versions.** Because the subject-ID counter is derived from `MAX(...)` in the survey's own table, giving a new zip a new `databaseName` silently resets ID counters and causes duplicate subject IDs. See [docs/DATABASE_VERSIONING_DECISIONS.md](docs/DATABASE_VERSIONING_DECISIONS.md) before changing anything about database naming/versioning.

### Database layer (`DbService`)

- One SQLite database per surveyId (`Map<surveyId, Database>`), opened via `sqflite` on mobile and `sqflite_common_ffi` on desktop (Windows/Linux/macOS init FFI in `DbService.init()`).
- On survey init, `_syncSurveyTable()` reconciles the table schema against the XML questions: creates the table if missing, otherwise diffs existing columns and runs `ALTER TABLE ... ADD COLUMN` for new fields (added as `TEXT`; existing data and unused old columns are preserved, never dropped).
- Table name = survey XML filename (lowercase, no extension); column names = question `fieldname` values, so XML fieldnames and DB columns must match exactly (case-sensitive).
- `crfs` table drives `MainScreen`'s survey list: `filename`, `id_config` (JSON for `IdGenerator`), `primary_keys`, `linking_field` (parent-child hierarchical linking).
- Updates only write changed fields (diff current vs. `_originalAnswers`); explicit `null`s must still be written to clear previously-skipped answers (see `prepareUpdateRowData` and the null-handling test in `test/services/db_service_test.dart`).

### Survey rendering pipeline

1. `SurveyLoader` parses a survey XML file (from a local `File`, not `rootBundle`) into a `List<Question>` (`lib/models/question.dart`), including static/CSV/DB-backed response options, preskip/postskip conditions, logic checks, numeric/date range validation, unique checks, computed `calculation` expressions, and input `mask`.
2. `SurveyScreen` (`lib/screens/survey_screen.dart`, the largest file — ~2000 lines) owns navigation state (`_currentQuestion`, `_history`, `_visitedFields`) and the single shared `AnswerMap` (`Map<String, dynamic>`) that all questions read/write directly — this is the one source of truth, not per-widget copies.
3. `SkipService` evaluates preskip (before showing a question) and postskip (after answering) conditions to jump between fields; `LogicService` evaluates cross-field `logic_check` expressions (supports `AND`/`OR`, parentheses, quoted/field-reference operands) and blocks navigation with an inline message on failure.
4. `AutoFields` computes values for `type="automatic"` questions via a registry keyed by fieldname (`starttime`, `stoptime`, `uniqueid`, `swver`, `lastmod`, etc.) — these never render UI. An automatic question is computed **when navigation reaches it**, so its position in the list decides what it records: `starttime` must precede the first real question and `stoptime` must follow the last one. Only `lastmod` is additionally refreshed at save time.

### System variables and the end-of-survey screen

- **Reserved system variables** — `starttime`, `startdate`, `uniqueid`, `swver`, `survey_id`, `lastmod`, `stoptime` are written by `DataKollecta-SurveyGen` (the data-dictionary-to-XML generator, a separate repo), not by the app. The generator drops any row a data dictionary declares for them and emits its own: the leading pair before the first real question, the trailing five after the last one but ahead of the end-of-survey screen (navigation stops on that screen, so anything after it is never computed). **The app trusts the XML** — `SurveyLoader` never adds, moves or de-duplicates a system variable. Getting their position right is the generator's job alone; don't add a second implementation in the app.
- **The end-of-survey screen** (`SurveyLoader.finalizeQuestions`) — `DataKollecta-SurveyGen` writes `end_of_questions` into every questionnaire with a fixed English sentence. Because no data dictionary can author that question, the app owns its wording and translates it. Matching is on the fieldname **and** the exact generated text, so hand-customised wording is never overwritten. This is why a French build shows the right text without regenerating or redeploying any survey package.

`calc`, `calculation` and `calculated` are accepted as spellings of `automatic`. The spelling never decides behavior — that comes from the fieldname (a reserved variable), from whether a `<calculation>` is present, or from the CRF's `idconfig` (generated IDs).
5. `IdGenerator` builds subject/record IDs from the CRF's `id_config` JSON (field sources + padding + fixed strings + an auto-incrementing counter queried from the survey's own table).
6. `question_views.dart` renders each `QuestionType` (text/radio/checkbox/combobox/date/datetime/information/automatic); dynamic response lists come from `DatabaseResponseService` (DB-backed, with placeholder-expanded filters) or `csv_data_service.dart` (CSV-backed).
7. On completion, skipped-question answers are cleared, IDs are generated if configured, `lastmod` is touched only on an actual save, and the record is written via `DbService.saveInterview` / `updateInterview`.

### Sync: two backends, selected by product

`SettingsService` stores secrets via `flutter_secure_storage`, except on macOS/Linux where it falls back to `shared_preferences` (keychain entitlements conflict with local ad-hoc code signing there).

**GiSTX — `FtpService`, `sync_screen.dart`.** Transfers survey data files to/from a single remote FTP server via `ftpconnect` (SFTP via `dartssh2` for the Burkina Faso flavor). Credentials can be global (`SettingsService.ftpHost/Username/Password`) or per-survey (`getCredentialsForSurvey`, falling back to global). Upload zips the whole SQLite database and PUTs one blob.

**DataKollecta — `lib/services/sync/`, `sync_screen_http.dart`.** Talks to two deployed Supabase edge functions (`app-login`, `app-sync`) plus signed-URL downloads. Upload is incremental and per-record, not a whole-database blob: `RecordUploader` walks unsynced rows in batches via a strictly-monotonic SQLite `rowid` cursor, so a batch that fails is never re-fetched forever (a real defect found and fixed when porting from an earlier, unmerged reference implementation of this backend). `ApiClient` is the HTTP transport (never logs request/response bodies — only method/host/status/counts); `DeviceIdentity` gives every platform a real, stable `device_id` (never the literal string `'unknown'`); `HttpSyncBackend` ties them together and additionally exposes `uploadPending()`/`countPending()`, which are not part of the shared seam below.

**The shared seam — `sync_backend.dart`.** `SyncBackend` covers **download only** (`connect`/`listSurveys`/`downloadSurvey`/`disconnect`); `createSyncBackend()` selects `FtpSyncBackend` or `HttpSyncBackend` based on `AppConfig.isDataKollecta`. Upload is deliberately **not** unified — FTP ships one whole-database zip, HTTP ships incrementally-acknowledged batches, and forcing both behind one `Future<void> upload()` would hide that difference rather than abstract it. Each product's sync screen calls its own upload path directly, which is also why `sync_screen.dart` (FTP) and `sync_screen_http.dart` (DataKollecta) are two separate files rather than one with branches threaded through — they share almost no state, and `sync_screen.dart` is live production code for Burkina Faso that a new sibling file cannot regress.

Failures from the HTTP backend are a sealed `SyncException` family (`SyncConnectionException`/`SyncAuthException`/`SyncTransferException`), so a call site exhaustively `switch`es into a user-facing message instead of sniffing exception text.

New DataKollecta-only UI copy lives in `app_strings_http_sync.dart` (`HttpSyncStrings`, English-only, with its reasoning documented inline) rather than `app_strings.dart` — DataKollecta never sets `GISTX_COUNTRY`, so French copy for it would be unreachable code.

### Key services reference

| Service | Responsibility |
|---|---|
| `survey_loader.dart` | XML → `Question` model parsing |
| `survey_config_service.dart` | Zip extraction, manifest lookup, multi-survey storage paths |
| `db_service.dart` | Per-survey SQLite lifecycle, schema sync, CRUD |
| `skip_service.dart` | preskip/postskip evaluation |
| `logic_service.dart` | Cross-field `logic_check` evaluation |
| `field_comparator.dart` | Shared checkbox-aware text resolution and the numeric/date/string/contains comparison used by skip, logic_check, and calculation |
| `auto_fields.dart` | Computed/automatic field registry |
| `id_generator.dart` | Subject/record ID generation and validation |
| `database_response_service.dart` / `csv_data_service.dart` | Dynamic response-option sources for radio/checkbox/combobox |
| `question_cache_service.dart` | Caches parsed questions across a survey's XML files for fast option-label lookup |
| `change_summary_service.dart` | Diffs answers for edit-mode change detection |
| `survey_navigation_service.dart` | Navigation helpers shared with `SurveyScreen` |
| `settings_service.dart` | Secure/prefs-backed credentials and app settings |
| `theme_service.dart` | Light/dark theme state |
| `ftp_service.dart` | FTP/SFTP transport for the GiSTX product (unchanged since the sync-backend seam was added) |
| `sync/sync_backend.dart` | The download-only `SyncBackend` seam, `SyncException` family, `createSyncBackend()` |
| `sync/ftp_sync_backend.dart` | Thin `SyncBackend` adapter over `FtpService` |
| `sync/http_sync_backend.dart` | `SyncBackend` adapter over `ApiClient` for DataKollecta; also owns `uploadPending()`/`countPending()` |
| `sync/api_client.dart` | HTTP transport for the deployed Supabase `app-login`/`app-sync` edge functions and signed-URL downloads |
| `sync/record_uploader.dart` | Batched, cursor-based record upload for DataKollecta with a bounded-retry circuit breaker |
| `sync/device_identity.dart` | Per-platform stable `device_id`, with a persisted-UUID fallback |
| `app_strings_http_sync.dart` | English-only UI copy for DataKollecta's HTTP sync screen |

### Platform-specific notes

- Desktop (Windows/Linux/macOS) uses `sqflite_common_ffi`; mobile uses native `sqflite`. Any DB code must work under both.
- File-system base directories differ per platform (see `SurveyConfigService._getBaseDir()` and the equivalent logic in `DbService`/`FtpService`) — Android uses external storage, Windows uses `%LOCALAPPDATA%`, macOS/Linux use application support dir. The path segment under that base dir is `AppConfig.storageFolder` (`'GiSTX'` or `'DataKollecta'`) — per-product, never per-country, since the two country flavors share one storage folder on purpose.
- macOS keychain entitlements conflict with local ad-hoc signing, hence the `shared_preferences` fallback in `SettingsService` for macOS/Linux.
- The four generated build-config files (see "Product flavors" above) are native project files, not Dart — they aren't covered by `flutter analyze`/`flutter test`. Verify a product's build directly (`dart run tool/build.dart apk --product datakollecta`, etc.) rather than assuming the Dart test suite catches a mistake in them.
