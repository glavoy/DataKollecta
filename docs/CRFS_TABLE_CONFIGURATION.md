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
	display_fields TEXT
)
```

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
| `entry_condition` | TEXT | Condition in order administer the crf | `enrolled=1` |

### **ID Generation (Base Forms Only)**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `idconfig` | TEXT | JSON configuration for generating unique IDs (only for base forms) | See JSON example below |
| `incrementfield` | TEXT | Field to auto-increment within parent context (e.g., linenum) | NULL (household), `linenum` (hh_members) |

### **Auto-Repeat Configuration**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `repeat_count_field` | TEXT | Field in parent table containing the repeat count | `num_people`, `num_nets` |
| `auto_start_repeat` | INTEGER | `0`=disabled, `1`=prompt user, `2`=force auto-start | `1` (prompt) |
| `repeat_enforce_count` | INTEGER | `0`=flexible, `1`=warn on mismatch, `2`=force complete, `3`=auto-sync | `1` (warn) |

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
  entry_condition, -- NULL
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
  entry_condition,    -- 'enrolled=1'
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
  entry_condition, -- 'enrolled=1'
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
- `2` = **Force** - Must complete all N members
- `3` = **Auto-sync** - Silently update parent record count

### **`display_order` Best Practice:**
Use increments of 10 (10, 20, 30...) to leave room for future insertions

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
12. `auto_start_repeat`
13. `repeat_enforce_count`
14. `display_fields`
15. `entry_condition`


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
