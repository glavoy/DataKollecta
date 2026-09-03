# Archived topic guides

**Nothing in `archive/` is maintained, and some of it is wrong.**

These are the app's original topic guides, written before `CLAUDE.md` and
`docs/` existed. They are kept because several still explain *why* a mechanism
works the way it does, and that reasoning is not recorded anywhere else — but
they were not updated as the app changed, so they describe behaviour that in
places no longer exists.

`TECHNICAL_README.md` is the clearest example: it describes an
asset-bundled survey model the app abandoned in favour of downloading and
extracting zip packages at runtime. Treat it as a conceptual reference for
skip/logic/validation semantics only, never as ground truth for survey
loading or storage paths.

Where to look instead:

| For | Read |
|---|---|
| App architecture, both build axes, the release flow | [`../CLAUDE.md`](../CLAUDE.md) |
| `crfs` configuration | [`../docs/CRFS_TABLE_CONFIGURATION.md`](../docs/CRFS_TABLE_CONFIGURATION.md) |
| Database naming and versioning decisions | [`../docs/DATABASE_VERSIONING_DECISIONS.md`](../docs/DATABASE_VERSIONING_DECISIONS.md) |
| The data-dictionary format and the XML dialect | `DataKollecta-SurveyGen/README.md` — the de-facto specification |
| Release history | [`../ChangeLog.md`](../ChangeLog.md) |

`archive/AUTOMATIC_VARIABLES_MIGRATION_EXAMPLES.md` was loose in the repo root
as a `.txt` file. Its worked XML examples are still readable, but the
authoritative reference for that format is SurveyGen's README — the app is not
the place to keep a second copy of the spec.
