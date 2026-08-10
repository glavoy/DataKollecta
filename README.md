# GiSTX

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

See [md/BUILD_INSTRUCTIONS.md](md/BUILD_INSTRUCTIONS.md) for build and release
steps. Keystore and signing instructions are deliberately **not** in this
repository — they are kept with the keystore backup.

---

## Overview

GiSTX is a cross-platform offline survey and data collection application built with Flutter. It enables researchers and data collectors to administer XML-based questionnaires in field settings without requiring internet connectivity.

## Key Features

- **Offline-First Architecture**: All data is stored locally in SQLite database, perfect for field research in remote locations
- **XML-Based Surveys**: Define questionnaires using simple XML files with support for multiple question types (text, radio, checkbox, date, etc.)
- **Hierarchical Data Collection**: Support for parent-child survey relationships (e.g., household enrollment followed by household member surveys)
- **Auto-Repeat Surveys**: Automatically loop through child surveys based on count fields (e.g., survey N household members)
- **Dynamic ID Generation**: Configurable unique ID generation with custom prefixes and field-based composition
- **Smart Navigation**: Intuitive record selection and modification with descriptive display fields
- **Data Validation**: Built-in support for numeric ranges, date ranges, logic checks, and unique value validation
- **Dynamic Text Replacement**: Insert previously answered values into question text using `[[fieldname]]` placeholders
- **Auto-Increment Fields**: Automatic line number generation for repeated records

## Use Cases

- Household surveys with multiple members
- Clinical research data collection
- Field studies in areas with limited connectivity
- Any scenario requiring structured data collection with parent-child relationships

## Technical Stack

- **Framework**: Flutter/Dart
- **Database**: SQLite with automatic schema synchronization
- **Platforms**: Windows, macOS, Linux, Android, iOS
- **Survey Definition**: XML
