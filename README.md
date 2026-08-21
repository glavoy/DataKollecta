# DataKollecta

This repository builds two separately-branded products — **GiSTX** and
**DataKollecta** — from one codebase; see below.

**`main` is the only branch to work on.** There was previously a separate
`burkinafaso` branch for the French/SFTP variant; it silently drifted from
`main` and has been merged in. The country is now chosen when the app is
**built**, not at runtime:

| Build | Language | Server |
|---|---|---|
| `dart run tool/build.dart apk` | English | FTP |
| `dart run tool/build.dart apk --flavor bf` | French | SFTP |

Both flavours share one application id and one signing key, so either can
update an existing installation in place without losing the device's database.

The `burkinafaso` branch is kept frozen — the tag `burkinafaso-final` marks its
tip — purely so an old APK could be rebuilt from the pre-merge code if a serious
bug ever needed fixing there. **Do not commit to it.** Anything committed there
will not reach `main` and the drift starts again.

This same codebase also builds a second product, **DataKollecta** — same survey
engine, a different sync backend (Supabase/HTTP with incremental upload instead
of FTP/SFTP). It's a separate, independent build axis from the country flavors
above: country never changes which app you get, product always does.

| Build | Product | Sync |
|---|---|---|
| `dart run tool/build.dart apk` | GiSTX | FTP/SFTP |
| `dart run tool/build.dart apk --product datakollecta` | DataKollecta | Supabase/HTTP |

The two products have separate application ids and separate signing keys, so
they install side by side rather than updating each other. See CLAUDE.md's
"Product flavors" section for how the build mechanism works.

See [md/BUILD_INSTRUCTIONS.md](md/BUILD_INSTRUCTIONS.md) for build and release
steps. Keystore and signing instructions are deliberately **not** in this
repository — they are kept with the keystore backup.

---

## Overview

GiSTX and DataKollecta are offline-first survey and data collection applications built with
Flutter from this one codebase. They administer XML-based questionnaires in field settings
without requiring internet connectivity, then sync collected data back — GiSTX over FTP/SFTP
(with an SFTP/French variant for Burkina Faso), DataKollecta over Supabase/HTTP with
incremental per-record upload (see the product table above).

Survey XML is normally not hand-written. It's generated from an Excel data dictionary by a
sibling tool, [`DataKollecta-SurveyGen`](../DataKollecta-SurveyGen), which also emits the
reserved system variables (`starttime`, `subjid`, `swver`, etc.) and validates the dictionary
before anything is built. This repo trusts that generated XML as-is — it doesn't re-derive or
re-validate what SurveyGen already decided.

For how the pieces fit together — the survey rendering pipeline, the SQLite schema-sync
layer, ID generation, the two sync backends, reserved/computed system variables — see
[CLAUDE.md](CLAUDE.md), which is the maintained architecture reference for this codebase.

## Key Features

- **Offline-First Architecture**: All data is stored locally in SQLite, with schema
  automatically reconciled against the survey XML on load (new fields get added as columns;
  nothing is ever dropped)
- **XML-Based Surveys**: Multi-page questionnaires with static, CSV-backed, and DB-backed
  response options; text, radio, checkbox, combobox, date/datetime, and computed
  ("automatic") question types
- **Hierarchical Data Collection**: Parent-child survey relationships (e.g., household
  enrollment followed by household member surveys), with auto-repeat looping driven by a
  count field on the parent record
- **Skip and Logic Rules**: Pre/post-answer skip conditions and cross-field logic checks
  (`AND`/`OR`, parentheses, field references), evaluated during navigation
- **Configurable ID Generation**: Subject/record IDs composed from survey fields, fixed
  strings, and an auto-incrementing counter — including an opt-in family of computed
  date-part fields (`yyyy`/`yy`/`mm`/`dd`/`doy`) designers can fold into an ID to shrink the
  collision window after a device reinstall resets its local counter
- **Dynamic Text Replacement**: Insert previously answered values into question text via
  `[[fieldname]]` placeholders
- **Data Validation**: Numeric/date range checks, logic checks, and unique-value validation

## Use Cases

- Household surveys with multiple members
- Clinical research data collection
- Field studies in areas with limited connectivity
- Any scenario requiring structured data collection with parent-child relationships

## Technical Stack

- **Framework**: Flutter/Dart
- **Database**: SQLite (`sqflite` on Android, `sqflite_common_ffi` on desktop) with
  automatic schema synchronization, one database per survey
- **Platforms actually built by `tool/build.dart`**: Android (APK), Windows, macOS. The repo
  also carries scaffold `ios/` and `linux/` directories from `flutter create`, but neither is
  a wired-up build target today.
- **Survey Definition**: XML, normally generated from an Excel data dictionary by
  `DataKollecta-SurveyGen`
- **Sync**: FTP/SFTP (GiSTX) or Supabase edge functions over HTTP (DataKollecta)
