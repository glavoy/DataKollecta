# CRFs Table Configuration Guide

## Overview
The `crfs` table is the central configuration metadata table that defines how each survey/questionnaire behaves in the system. Each row represents one survey form.

---

## Table Structure

```sql
CREATE TABLE crfs (
	tablename	TEXT,
	primarykey	TEXT,
	displayname	TEXT,
	isbase	INTEGER DEFAULT 0,
	linkingfield	TEXT,
	parenttable	TEXT,
	incrementfield	TEXT,
	requireslink	INTEGER DEFAULT 0,
	idconfig	TEXT,
	repeat_count_field TEXT,
	auto_start_repeat INTEGER,
	repeat_enforce_count INTEGER,
	display_order INTEGER DEFAULT 0,
	display_fields TEXT,
	entry_condition TEXT
)
```

The authoritative list is `DbService._crfsColumns`; a column named by a manifest but
absent here is dropped with a log line rather than failing the survey.

---

## What the app now enforces from these fields

Until recently every one of these columns was **metadata the app read**. Survey
tables were created with every column a plain `TEXT` -- no `PRIMARY KEY`, no `UNIQUE`,
no `FOREIGN KEY` -- and `PRAGMA foreign_keys` was never switched on, so nothing stopped
an orphan child, two records sharing a key, or a corrected parent key leaving its
children behind.

Each survey table is now created with real constraints, driven by the cells below:

| Constraint | Driven by | Why |
|---|---|---|
| `uniqueid TEXT PRIMARY KEY` | always | The only key that can never refuse a record -- it is a fresh UUID -- and what makes any other collision recoverable |
| `UNIQUE(...)`, one per referenced column set | every distinct `linkingfield` its children declare, plus its own `primarykey` when it has children | A foreign key needs its referenced columns unique |
| `FOREIGN KEY (linkingfield) REFERENCES parenttable(linkingfield) ON UPDATE CASCADE` | `parenttable` + `linkingfield` | Correcting a parent's key carries to its children |
| `FOREIGN KEY (parent_uniqueid) REFERENCES parenttable(uniqueid)` | `parenttable` | A join key nothing can retype -- see below |
| A plain index on `(linkingfield, incrementfield)` | `incrementfield` | Serves the child counter's `MAX` query |

**Uniqueness follows what children reference, not the primary key.** These are not always
the same: a real dictionary links `vaccination_status` to `enrollee` on `barcode` (a
scanned physical label) while `enrollee` is keyed on `subjid`. Both get a `UNIQUE`.

**The sibling index is deliberately not `UNIQUE`.** A duplicate `linenum` is a counter
bug -- the interviewer never types it -- and every row carries a `uniqueid`, so a
duplicate stays reconcilable. A `UNIQUE` there would make the save *fail*, and in field
research a lost interview is worse than an identifier that has to be reconciled later.
Find duplicates with a report instead:

```sql
SELECT hhid, linenum, COUNT(*) FROM hh_members GROUP BY hhid, linenum HAVING COUNT(*) > 1;
```

**A duplicate parent key is refused**, because there is no equivalent escape. With
`incrementLength: 0` a key like `hhid` is a pure function of typed answers, so there is
no spare digit to move -- and a duplicate means a second copy of a household that already
exists, which is a data-entry error to catch at entry rather than a record to save under
a mangled id. The app's real-time duplicate check now fires for `automatic` key fields
too, so the interviewer is told while the components can still be corrected.

**A cascade writes an audit row.** Updating a parent's key rewrites its children behind
the app's back -- not through `updateInterview` -- so each child table carries an
`AFTER UPDATE` trigger that clears `synced_at` and writes a `formchanges` row. Without
it the device would be corrected while the server kept the old key forever.

**When the foreign key is skipped.** If `linkingfield` names a column its parent does not
have, the table is created without the key and the reason is logged. SurveyGen and the
portal both reject that shape at authoring time, which is where it belongs -- they now
check every field name a `crfs` row mentions, including that `linkingfield` exists on the
**parent**, which nothing checked before.

**The child counter groups siblings by `linkingfield`.** There used to be two
implementations that disagreed -- one grouped by `primarykey`'s first field -- so which
number an interviewer got depended on which screen they came through. Where a form has an
`incrementfield`, SurveyGen warns if `primarykey` is not `linkingfield,incrementfield`,
since anything else describes a different grouping than the one records are numbered by.
If the counter cannot be read, the app writes **`0`** rather than `1`: the counter starts
at 1, so `0` is a value no real record holds, where `1` was indistinguishable from a
legitimate first child. `WHERE <incrementfield> = 0` finds every degraded row.

**These constraints are declared only at `CREATE TABLE`.** SQLite has no
`ALTER TABLE ... ADD CONSTRAINT`, and `_syncSurveyTable` adds columns but never
constraints -- so a device that already created a table keeps it unconstrained. Clearing
the `databases/` folder is how a development device picks up the new schema. Once a
survey is deployed this stops being possible, which is why the schema was settled before
anything shipped.

---

## `parent_uniqueid` -- the join key that cannot drift

**Written by `DataKollecta-SurveyGen`, onto every form that declares a `parenttable`.**
Do not declare a row for it; like `uniqueid` and `swver` it is a reserved system variable,
and a declared row is dropped with a warning.

`hhid` stays the human-readable business key, but it is built from typed answers -- so an
interviewer correcting a mistyped household number changes it, and anything joining on it
has to survive that. `parent_uniqueid` holds the parent record's `uniqueid` instead. A
UUID cannot be retyped, so a join on it cannot drift.

Base forms do not get the column: a base form has nothing to point at, and a null join
key is worse than none, because analysis would fall back to the business key anyway.

The app fills it in when it creates the child, from the parent's own record -- the same
channel that already carries the linking value. Nothing on the server side changed: the
whole row is uploaded as schema-free JSONB.

Contrast with the five computed variables further down (`yyyy`/`yy`/`mm`/`dd`/`doy`),
which a dictionary *must* declare. The only reason those need declaring is **position** --
one may have to sit immediately before the `idconfig` field that consumes it, which the
generator cannot infer. Nothing consumes `parent_uniqueid`, so it has no position to get
right, and generating it means forgetting a row cannot silently lose the join key.

---

## Field Definitions (in recommended order)

### **Basic Configuration**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `tablename` | TEXT | Table name in the database (same as XML filename without .xml) | `household`, `hh_members` |
| `displayname` | TEXT | User-friendly name shown in the app | `Household Survey`, `Household Members` |
| `display_order` | INTEGER | Order in which surveys appear in the app menu (10, 20, 30...) | `10`, `20`, `30` |
| `primarykey` | TEXT | Comma-separated list of fields comprising the primary key | `hhid` or `hhid,linenum` |

### **Form Hierarchy & Linking**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `isbase` | INTEGER | `1` if this is a base/enrollment form, `0` otherwise | `1` (household), `0` (hh_members) |
| `requireslink` | INTEGER | `1` if user must select a parent ID before starting, `0` otherwise | `0` (household), `1` (hh_members) |
| `parenttable` | TEXT | Parent table to get linking IDs from (NULL for base forms) | NULL (household), `household` (hh_members) |
| `linkingfield` | TEXT | Field name that links child records to parent | NULL (household), `hhid` (hh_members) |

### **ID Generation (Base Forms Only)**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `idconfig` | TEXT | JSON configuration for generating unique IDs (only for base forms) | See JSON example below |
| `incrementfield` | TEXT | Field to auto-increment within parent context (e.g., linenum) | NULL (household), `linenum` (hh_members) |

### **Auto-Repeat Configuration**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `repeat_count_field` | TEXT | Field in parent table containing the repeat count | `num_people`, `num_nets` |
| ~~`repeat_count_source`~~ | -- | **Does not exist.** Not in the `crfs` worksheet's column list, not in the app's `crfs` table. Pre-existing documentation drift, recorded here rather than silently removed from the examples below. The count is always read from `parenttable`. | -- |
| `auto_start_repeat` | INTEGER | `0`=disabled, `1`=prompt user, `2`=force auto-start | `1` (prompt) |
| `repeat_enforce_count` | INTEGER | `0`=flexible, `1`=warn on mismatch, `2`=force complete, `3`=auto-sync. Never writes a count outside the count question's `LowerRange`/`UpperRange`. | `1` (warn) |

### **Display Configuration**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `display_fields` | TEXT | Comma-separated fields to show in record selector dropdowns | `participantsname` or `participantsname,sex` |

---

## Configuration Examples

### **Example 1: Base Form (Household)**

```sql
INSERT INTO crfs (
  tablename,           -- 'household'
  displayname,         -- 'Household Survey'
  display_order,       -- 10
  primarykey,          -- 'hhid'
  isbase,              -- 1
  requireslink,        -- 0
  parenttable,         -- NULL
  linkingfield,        -- NULL
  idconfig,            -- '{"prefix":"HH","fields":[{"name":"village","length":3}],"incrementLength":3}'
  incrementfield,      -- NULL
  repeat_count_field,  -- NULL
  repeat_count_source, -- NULL
  auto_start_repeat,   -- 0
  repeat_enforce_count,-- 0
  display_fields       -- NULL
) VALUES (
  'household',
  'Household Survey',
  10,
  'hhid',
  1,
  0,
  NULL,
  NULL,
  '{"prefix":"HH","fields":[{"name":"village","length":3}],"incrementLength":3}',
  NULL,
  NULL,
  NULL,
  0,
  0,
  NULL
);
```

### **Example 2: Child Form with Auto-Repeat (Household Members)**

```sql
INSERT INTO crfs (
  tablename,           -- 'hh_members'
  displayname,         -- 'Household Members'
  display_order,       -- 20
  primarykey,          -- 'hhid,linenum'
  isbase,              -- 0
  requireslink,        -- 1
  parenttable,         -- 'household'
  linkingfield,        -- 'hhid'
  idconfig,            -- NULL
  incrementfield,      -- 'linenum'
  repeat_count_field,  -- 'num_people'
  repeat_count_source, -- 'household'
  auto_start_repeat,   -- 1 (prompt user)
  repeat_enforce_count,-- 1 (warn on mismatch)
  display_fields       -- 'participantsname'
) VALUES (
  'hh_members',
  'Household Members',
  20,
  'hhid,linenum',
  0,
  1,
  'household',
  'hhid',
  NULL,
  'linenum',
  'num_people',
  'household',
  1,
  1,
  'participantsname'
);
```

### **Example 3: Another Repeat Form (Mosquito Nets)**

```sql
INSERT INTO crfs (
  tablename,           -- 'mosquito_nets'
  displayname,         -- 'Mosquito Nets'
  display_order,       -- 30
  primarykey,          -- 'hhid,netnum'
  isbase,              -- 0
  requireslink,        -- 1
  parenttable,         -- 'household'
  linkingfield,        -- 'hhid'
  idconfig,            -- NULL
  incrementfield,      -- 'netnum'
  repeat_count_field,  -- 'num_nets'
  repeat_count_source, -- 'household'
  auto_start_repeat,   -- 1
  repeat_enforce_count,-- 1
  display_fields       -- 'net_type,net_color'
) VALUES (
  'mosquito_nets',
  'Mosquito Nets',
  30,
  'hhid,netnum',
  0,
  1,
  'household',
  'hhid',
  NULL,
  'netnum',
  'num_nets',
  'household',
  1,
  1,
  'net_type,net_color'
);
```

---

## Field Value Reference

### **`auto_start_repeat` Options:**
- `0` = **Disabled** - User must manually start child surveys
- `1` = **Prompt** - Ask user "Add now or later?" (RECOMMENDED)
- `2` = **Force** - Automatically start without asking

### **`repeat_enforce_count` Options:**
- `0` = **Flexible** - Allow any count, no warnings
- `1` = **Warn** - Show warning if count doesn't match (RECOMMENDED)
- `2` = **Force** - Must complete all N members (no "Exit Anyway" escape)
- `3` = **Auto-sync** - Update parent record count with no choice offered, then show an acknowledgement dialog telling the interviewer it changed

**When reconciliation runs.** Modes `1` and `3` reconcile the parent's count both when the
auto-repeat loop ends *and* whenever a child record is saved on its own — added later from
the questionnaire menu, or edited. Mode `2` only applies inside the loop. With
`auto_start_repeat = 0` there is no loop, so the count is reconciled only on those
standalone child saves.

**The count question's range is never violated.** Before writing, the actual number of
children is checked against the `LowerRange`/`UpperRange` declared on the count question in
the parent's `_dd` worksheet — the same check the interviewer's typed answer passes. Nothing
is written when the count would fall below `LowerRange` (inside the loop the interviewer is
held there until it does not), when it would exceed `UpperRange` (they are warned instead),
or when the count question was skipped and its value is NULL. To require at least N children
of a form, set `LowerRange` on its count question; there is deliberately no separate minimum
column here.

### **`display_order` Best Practice:**
Use increments of 10 (10, 20, 30...) to leave room for future insertions

---

## Computed Automatic Variables (yyyy, yy, mm, dd, doy)

Five `FieldName`s the app already knows how to compute, the same way it computes `startdate`
— but unlike a truly reserved variable, **nothing writes these in for you.** You have to
declare a row for each one yourself, exactly where you want it in the questionnaire. Each is
computed once, from *today's* date, and never recomputed. That's deliberate: one common use
is sitting immediately before a specific `idconfig` field they feed (see the worked example
below), a position the generator has no way to infer on its own — but they aren't
idconfig-specific, and can be declared on any worksheet, for any reason a survey wants
"today."

| FieldName | What it computes | Format |
|-----------|-------------------|--------|
| `yyyy` | the current four-digit year | zero-padded to 4 — `"2026"` |
| `yy` | the current two-digit year | `year % 100`, zero-padded to 2 — `2026` → `"26"` |
| `mm` | the current month | zero-padded to 2 — `"01"`–`"12"` |
| `dd` | the current day of the month | zero-padded to 2 — `"01"`–`"31"` |
| `doy` | the ordinal day within the current calendar year | zero-padded to 3 — `"001"` (Jan 1) through `"365"`/`"366"` (Dec 31) |

**Worked examples:** `2001` → `yy` `"01"`; Feb 1 → `doy` `"032"`.

**A given `yy` repeats every century** — `2000` and `2100` are both `"00"`. A real ambiguity,
not a bug: acceptable because no study spans a century.

**Called `doy`, not `ddd`** — `ddd` for day-of-year isn't a convention anywhere (POSIX uses
`%j`; R uses `yday()`), and it collides with Excel's own custom date-format meaning for
`ddd`: abbreviated weekday name, not day-of-year, in the exact tool used to author these
dictionaries.

**Declare them as ordinary `automatic`-type rows with a blank `Responses` column** — no
`calc:` block, on any worksheet, not only a table that references one in its own `idconfig`.
**Do not build these with `calc:constant value:NOW_YEAR` or similar**: a `calc:` field is
only protected from being recomputed mid-edit if its survey explicitly marks it
`preserve: true`, which the generator currently has no way to author from Excel at all (a
pre-existing gap, not specific to these fields). Without that, editing an existing record on
a later day (or year) could silently mint a *new* subject ID for the same person. These
fields avoid that because, like `starttime`/`startdate`, the app preserves an already-stored
value unconditionally, with no flag to forget — see `DataKollecta-SurveyGen/README.md`'s
`idconfig` reference for the full design rationale.

**Want a component from a date *other* than today** — `dob`, an appointment date? These
fields can't do that; use the `date_part` calculation type instead (`calc:date_part`,
documented in `DataKollecta-SurveyGen/README.md`'s Automatic Calculations section). It shares
the same five unit tokens but extracts from a named field and recomputes on every edit
(the `preserve` gap above applies to it too) — the opposite default from this section, and
correct for that use case.

---

## `idconfig` JSON Configuration

### **Structure:**
```json
{
  "prefix": "SP",
  "fields": [
    {"name": "country", "length": 1},
    {"name": "parish", "length": 2},
    {"name": "village", "length": 2}
  ],
  "incrementLength": 3
}
```

### **Field Descriptions:**
- `prefix`: Static prefix for all IDs (e.g., "SP", "HH", "GX")
- `fields`: Array of field names and their padded lengths
  - `name`: Field name from the survey
  - `length`: Number of digits to pad to (3 → 03, 5 → 05)
- `incrementLength`: Length of auto-incrementing number (3 = 001, 002...)

### **Generated ID Examples:**

**Configuration:**
```json
{
  "prefix": "SP",
  "fields": [
    {"name": "country", "length": 1},
    {"name": "parish", "length": 2},
    {"name": "village", "length": 2}
  ],
  "incrementLength": 3
}
```

**User Input:**
- country = 5
- parish = 3
- village = 12

**Generated IDs:**
- `SP5031201` (first subject)
- `SP5031202` (second subject)
- `SP5031203` (third subject)

**Breakdown:**
- `SP` = prefix
- `5` = country (padded to length 1)
- `03` = parish (3 padded to length 2)
- `12` = village (12 already length 2)
- `001`, `002`, `003` = increment (padded to length 3)

**Another Example:**

**User Input:**
- country = 2
- parish = 7
- village = 5

**Generated IDs:**
- `SP2070501`
- `SP2070502`
- `SP2070503`

**Breakdown:**
- `SP` = prefix
- `2` = country (length 1)
- `07` = parish (7 padded to length 2)
- `05` = village (5 padded to length 2)
- `001`, `002`, `003` = increment

**Example 3: A reinstall-resilient ID, using `yy` / `doy`**

```json
{
  "prefix": "GX",
  "fields": [
    {"name": "nn", "length": 2},
    {"name": "yy", "length": 2},
    {"name": "doy", "length": 3}
  ],
  "incrementLength": 2
}
```
→ `GX07260451` (interviewer `07`, year `26`, day-of-year `045`, increment `01`, resetting
daily since the base ID changes every day — see
[Computed Automatic Variables](#computed-automatic-variables-yyyy-yy-mm-dd-doy) above for how
to declare `yy`/`doy`, their exact format, and why this shrinks a reinstall's collision
window without eliminating it).

---

## Recommended Spreadsheet Column Order

For creating the CRFs table from a spreadsheet, use this column order:

1. `tablename`
2. `displayname`
3. `display_order`
4. `isbase`
5. `primarykey`
6. `requireslink`
7. `parenttable`
8. `linkingfield`
9. `incrementfield`
10. `idconfig`
11. `repeat_count_field`
12. `repeat_count_source`
13. `auto_start_repeat`
14. `repeat_enforce_count`
15. `display_fields`

This order groups related fields together logically.

---

## Quick Reference Table

| Survey Type | isbase | requireslink | parenttable | linkingfield | idconfig | repeat fields |
|-------------|--------|--------------|-------------|--------------|----------|---------------|
| **Base/Enrollment** | 1 | 0 | NULL | NULL | JSON config | NULL |
| **Child with Auto-Repeat** | 0 | 1 | parent_table | linking_field | NULL | Configure repeat_* |
| **Independent Child** | 0 | 1 | parent_table | linking_field | NULL | NULL |

---

## Common Configuration Patterns

### **Pattern 1: Simple Base Form**
Used for the main enrollment/registration survey.

```
isbase = 1
requireslink = 0
parenttable = NULL
linkingfield = NULL
idconfig = {"prefix":"XX","fields":[...],"incrementLength":3}
repeat_* = NULL or 0
```

### **Pattern 2: Child Form with Auto-Repeat**
Used for repeated sections like household members, medications, etc.

```
isbase = 0
requireslink = 1
parenttable = 'base_table_name'
linkingfield = 'parent_id_field'
idconfig = NULL
incrementfield = 'linenum' or similar
repeat_count_field = 'num_items'
auto_start_repeat = 1
repeat_enforce_count = 1
display_fields = 'descriptive_field'
```

### **Pattern 3: Independent Child Form**
Used for optional child records not part of auto-repeat.

```
isbase = 0
requireslink = 1
parenttable = 'base_table_name'
linkingfield = 'parent_id_field'
idconfig = NULL
incrementfield = NULL or field_name
repeat_* = NULL or 0
```

---

## Validation Checklist

Before deploying, verify:

- [ ] All base forms have `isbase = 1` and `idconfig` properly configured
- [ ] All child forms have `requireslink = 1`, `parenttable`, and `linkingfield` set
- [ ] Primary keys match the composite key structure (e.g., `hhid,linenum`)
- [ ] Auto-repeat forms have all `repeat_*` fields configured
- [ ] `display_order` values allow room for future insertions (use 10, 20, 30...)
- [ ] `display_fields` are set for any forms users will view/modify
- [ ] Each table name matches its XML filename (without .xml extension)
- [ ] JSON in `idconfig` is valid and properly escaped

---

## Troubleshooting

### **Auto-repeat not working:**
1. Check `repeat_count_field` exists in parent table
2. Verify `repeat_count_source` matches parent table name
3. Ensure `auto_start_repeat` is 1 or 2
4. Confirm parent form has the count question in XML

### **Record selector shows just numbers:**
1. Add `display_fields` configuration
2. Verify field names are spelled correctly
3. Ensure display fields exist in the table

### **IDs not generating:**
1. Check `idconfig` JSON is valid
2. Verify field names in JSON match survey XML fields
3. Ensure `isbase = 1` for the form
4. Check all required fields are answered before generation

---

This configuration guide provides all necessary information for setting up and maintaining the CRFs table for your survey application.
