# Dynamic Response Configuration Guide

This guide explains how to configure questions with dynamic response options from CSV files or database queries.

## Overview

Questions can have three types of response sources:
- **Static**: Hardcoded in XML (default, backwards compatible)
- **CSV**: Loaded from CSV files with filtering
- **Database**: Queried from survey database tables

## Table of Contents
- [Static Responses (Default)](#static-responses-default)
- [CSV Responses](#csv-responses)
- [Database Responses](#database-responses)
- [Filter Operators](#filter-operators)
- [Complete Examples](#complete-examples)
- [Display Field Label Lookup](#display-field-label-lookup)
- [Troubleshooting](#troubleshooting)

---

## Static Responses (Default)

Traditional hardcoded responses. If no `source` attribute is specified, `source='static'` is assumed.

### Syntax
```xml
<question type='radio' fieldname='region' fieldtype='integer'>
    <text>Region where the MRC is located</text>
    <responses source='static'>  <!-- source='static' is optional -->
        <response value='1'>Busoga</response>
        <response value='2'>Bukedi</response>
        <response value='3'>Bugisu</response>
    </responses>
</question>
```

### Notes
- The `source='static'` attribute is optional (backwards compatible)
- All existing XML files work without modification
- Use for fixed lists that don't change

---

## CSV Responses

Load response options from a CSV file with optional filtering and distinct values.

### File Location
CSV files must be in the **same directory** as your survey XML files.

Example structure:
```
surveys/
  your_survey_name/
    ├── enrollment.xml
    ├── household.xml
    ├── mrcvillage.csv      ← CSV file here
    └── manifest.json
```

### CSV File Format
- First row must contain column headers
- All subsequent rows are data
- Values are trimmed of whitespace

Example `mrcvillage.csv`:
```csv
region,mrccode,mrcname,villagename,villagecode,vcode
14,01,Kasambya HCIII,KASAMBYA A,189070104,01
14,01,Kasambya HCIII,KASAMBYA CENTRAL,189070106,02
9,09,Kigorobya HCIV,KIRYANDONGO,133110202,01
```

### Basic Syntax
```xml
<question type='radio' fieldname='mrccode' fieldtype='text'>
    <text>Select the MRC</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <display column='mrcname'/>
        <value column='mrccode'/>
    </responses>
</question>
```

### XML Elements

#### `<responses>` Attributes
| Attribute | Required | Description |
|-----------|----------|-------------|
| `source` | Yes | Must be `'csv'` |
| `file` | Yes | CSV filename (must be in same directory as XML) |

#### `<filter>` Element
Filters which rows from the CSV to include. Can have multiple `<filter>` elements.

| Attribute | Required | Default | Description |
|-----------|----------|---------|-------------|
| `column` | Yes | - | Column name from CSV header |
| `value` | Yes | - | Value to filter for (supports `[[fieldname]]` placeholders) |
| `operator` | No | `'='` | Comparison operator (see [Filter Operators](#filter-operators)) |

#### `<display>` Element
| Attribute | Required | Description |
|-----------|----------|-------------|
| `column` | Yes | Column to show to the user as the label |

#### `<value>` Element
| Attribute | Required | Description |
|-----------|----------|-------------|
| `column` | Yes | Column value to save to the database when selected |

#### `<distinct>` Element
- **Optional** (defaults to `true`)
- Content: `true` or `false`
- If `true` (default), removes duplicate values after filtering
- If `false`, shows all rows even if values are duplicated
- In most cases, you can omit this element and use the default behavior

#### `<empty_message>` Element
- **Optional**
- Content: Message to display if no options match the filters
- If omitted, no special message is shown (Next button still enabled)

#### `<dont_know>` Element
- **Optional**
- Adds a "Don't know" option to the response list
- Attributes:
  - `value` (required): The value to save when selected (e.g., `-7`)
  - `label` (optional): Display text (defaults to "Don't know")
- For **checkboxes**: Selecting this option clears all other selections
- Use when the respondent may not know the answer

#### `<not_in_list>` Element
- **Optional**
- Adds a "Not in this list" option to the response list
- Attributes:
  - `value` (required): The value to save when selected (e.g., `-99`)
  - `label` (optional): Display text (defaults to "Not in this list")
- For **checkboxes**: Selecting this option clears all other selections
- Use when the correct answer may not be in the filtered list

### Placeholder Substitution
Values in `<filter>` elements support `[[fieldname]]` placeholders that are replaced with actual values from previous questions.

Example:
```xml
<filter column='region' value='[[region]]'/>
```
If the user selected `region = '7'`, this becomes:
```xml
<filter column='region' value='7'/>
```

### Multiple Filters
You can use multiple `<filter>` elements to filter by multiple criteria (they are ANDed together).

```xml
<question type='radio' fieldname='vcode' fieldtype='text'>
    <text>Village</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <filter column='mrccode' value='[[mrccode]]'/>
        <display column='villagename'/>
        <value column='vcode'/>
    </responses>
</question>
```

This filters rows where **both** `region` matches AND `mrccode` matches.

### Example: Cascading Dropdowns

A common pattern is to have dependent dropdowns that filter based on previous selections.

```xml
<!-- Step 1: Select Region (hardcoded) -->
<question type='radio' fieldname='region' fieldtype='integer'>
    <text>Region where the MRC is located</text>
    <responses source='static'>
        <response value='1'>Busoga</response>
        <response value='6'>Lango</response>
        <response value='7'>Acholi</response>
        <response value='8'>West Nile</response>
    </responses>
</question>

<!-- Step 2: Select MRC (filtered by region) -->
<question type='combobox' fieldname='mrccode' fieldtype='text'>
    <text>Select the MRC</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <display column='mrcname'/>
        <value column='mrccode'/>
    </responses>
</question>

<!-- Step 3: Select Village (filtered by region AND mrccode) -->
<question type='combobox' fieldname='vcode' fieldtype='text'>
    <text>Select the Village</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <filter column='mrccode' value='[[mrccode]]'/>
        <display column='villagename'/>
        <value column='vcode'/>
    </responses>
</question>
```

**How it works:**
1. User selects region "7" (Acholi)
2. MRC dropdown shows only MRCs where `region='7'`
3. User selects MRC "29" (Padibe HCIII)
4. Village dropdown shows only villages where `region='7'` AND `mrccode='29'`

### Example: Checkboxes with Special Options

Using checkboxes for multi-select with "Don't know" and "Not in this list" options.

**Scenario:** "Who slept under this net last night?" Multiple people can share a net.

```xml
<!-- Automatic field: household ID -->
<question type='automatic' fieldname='hhid' fieldtype='text'>
</question>

<!-- Automatic field: net number -->
<question type='automatic' fieldname='netnum' fieldtype='integer'>
</question>

<!-- Multi-select from household members -->
<question type='checkbox' fieldname='net_users' fieldtype='text'>
    <text>Who slept under net #[[netnum]] last night?</text>
    <responses source='database' table='hh_members'>
        <filter column='hhid' value='[[hhid]]'/>
        <display column='participantsname'/>
        <value column='uniqueid'/>
        <dont_know value='-7'/>
        <not_in_list value='-99' label='Someone not in household list'/>
    </responses>
</question>
```

**How special options work:**
- Normal options can be multi-selected (Person A + Person B)
- If user selects "Don't know", all other selections are cleared
- If user selects "Someone not in household list", all other selections are cleared
- Selecting a normal option after a special option clears the special option

**CSV Example:**
```xml
<question type='checkbox' fieldname='crops_grown' fieldtype='text'>
    <text>Which crops did you grow this season?</text>
    <responses source='csv' file='crops.csv'>
        <filter column='region' value='[[region]]'/>
        <display column='crop_name'/>
        <value column='crop_code'/>
        <dont_know value='-7'/>
        <not_in_list value='-99' label='Other crop not listed'/>
    </responses>
</question>
```

---

## Database Responses

Load response options by querying the survey database.

### When to Use
- When you need to reference data already entered in the survey
- Example: "Select the mother of this child" (query household members table)
- Example: "Select the head of household" (query members where relation=1)

### Basic Syntax
```xml
<question type='radio' fieldname='mother_id' fieldtype='text'>
    <text>Select the mother of this child</text>
    <responses source='database' table='hh_members'>
        <filter column='sex' value='1'/>
        <filter column='census_age' operator='>' value='15'/>
        <filter column='hhid' value='[[hhid]]'/>
        <display column='participantsname'/>
        <value column='uniqueid'/>
        <empty_message>No eligible mothers found in this household</empty_message>
    </responses>
</question>
```

### XML Elements

#### `<responses>` Attributes
| Attribute | Required | Description |
|-----------|----------|-------------|
| `source` | Yes | Must be `'database'` |
| `table` | Yes | Database table name (without `.xml` extension) |

#### `<filter>` Element
Filters which rows from the database table to include.

| Attribute | Required | Default | Description |
|-----------|----------|---------|-------------|
| `column` | Yes | - | Database column name |
| `value` | Yes | - | Value to filter for (supports `[[fieldname]]` placeholders) |
| `operator` | No | `'='` | Comparison operator (see [Filter Operators](#filter-operators)) |

#### `<display>` Element
| Attribute | Required | Description |
|-----------|----------|-------------|
| `column` | Yes | Database column to show to the user as the label |

#### `<value>` Element
| Attribute | Required | Description |
|-----------|----------|-------------|
| `column` | Yes | Database column value to save when selected |

#### `<distinct>` Element
- **Optional** (defaults to `true`)
- Content: `true` or `false`
- If `true` (default), adds `DISTINCT` to the SQL query
- If `false`, shows all rows even if values are duplicated
- In most cases, you can omit this element and use the default behavior

#### `<empty_message>` Element
- **Optional**
- Content: Message to display if no database records match the filters
- If omitted, no special message is shown (Next button still enabled)

#### `<dont_know>` Element
- **Optional**
- Adds a "Don't know" option to the response list
- Attributes:
  - `value` (required): The value to save when selected (e.g., `-7`)
  - `label` (optional): Display text (defaults to "Don't know")
- For **checkboxes**: Selecting this option clears all other selections
- Use when the respondent may not know the answer

#### `<not_in_list>` Element
- **Optional**
- Adds a "Not in this list" option to the response list
- Attributes:
  - `value` (required): The value to save when selected (e.g., `-99`)
  - `label` (optional): Display text (defaults to "Not in this list")
- For **checkboxes**: Selecting this option clears all other selections
- Use when the correct answer may not be in the filtered list

### Table Names
The `table` attribute should match the XML filename without the `.xml` extension.

For example:
- XML file: `hh_members.xml`
- Table name: `hh_members`

### Example: Select Head of Household
```xml
<question type='radio' fieldname='hoh_id' fieldtype='text'>
    <text>Head of Household</text>
    <responses source='database' table='hh_members'>
        <filter column='hhid' value='[[hhid]]'/>
        <filter column='household_relation' value='1'/>
        <display column='participantsname'/>
        <value column='uniqueid'/>
    </responses>
</question>
```

### Example: Select Mother (Female, Age > 15)
```xml
<question type='combobox' fieldname='mother_id' fieldtype='text'>
    <text>Who is the mother of this child?</text>
    <responses source='database' table='hh_members'>
        <filter column='hhid' value='[[hhid]]'/>
        <filter column='sex' value='1'/>
        <filter column='census_age' operator='>=' value='16'/>
        <display column='participantsname'/>
        <value column='uniqueid'/>
        <empty_message>No eligible mothers found. Please add household members first.</empty_message>
    </responses>
</question>
```

---

## Filter Operators

Both CSV and database responses support the following operators:

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equal to (default) | `<filter column='sex' value='1'/>` |
| `!=` or `<>` | Not equal to | `<filter column='sex' operator='!=' value='2'/>` |
| `>` | Greater than | `<filter column='age' operator='>' value='15'/>` |
| `<` | Less than | `<filter column='age' operator='<' value='65'/>` |
| `>=` | Greater than or equal | `<filter column='age' operator='>=' value='18'/>` |
| `<=` | Less than or equal | `<filter column='age' operator='<=' value='60'/>` |

### Numeric vs String Comparison
- If both values can be parsed as numbers, numeric comparison is used
- Otherwise, string comparison is used
- This works automatically - no configuration needed

### Examples
```xml
<!-- Numeric comparison: age > 18 -->
<filter column='census_age' operator='>' value='18'/>

<!-- String equality: sex = '1' -->
<filter column='sex' value='1'/>

<!-- String inequality: status != 'deceased' -->
<filter column='status' operator='!=' value='deceased'/>

<!-- With placeholder: hhid = (value from previous question) -->
<filter column='hhid' value='[[hhid]]'/>
```

---

## Complete Examples

### Example 1: Region → MRC → Village (CSV Cascading)

**CSV File: `mrcvillage.csv`**
```csv
region,mrccode,mrcname,villagename,villagecode,vcode
7,21,Koch Goma HCIV,Kal 'B',202040403,01
7,21,Koch Goma HCIV,Kal 'A1',202040401,02
7,23,Atiak HCIV,Kal East,108030101,01
9,09,Kigorobya HCIV,KIRYANDONGO,133110202,01
```

**XML Configuration:**
```xml
<!-- Question 1: Static region selection -->
<question type='radio' fieldname='region' fieldtype='integer'>
    <text>Region where the MRC is located</text>
    <responses source='static'>
        <response value='7'>Acholi</response>
        <response value='9'>Bunyoro</response>
    </responses>
</question>

<!-- Question 2: MRC filtered by region -->
<question type='combobox' fieldname='mrccode' fieldtype='text'>
    <text>Select the MRC</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <display column='mrcname'/>
        <value column='mrccode'/>
    </responses>
</question>

<!-- Question 3: Village filtered by region and MRC -->
<question type='combobox' fieldname='vcode' fieldtype='text'>
    <text>Select the Village</text>
    <responses source='csv' file='mrcvillage.csv'>
        <filter column='region' value='[[region]]'/>
        <filter column='mrccode' value='[[mrccode]]'/>
        <display column='villagename'/>
        <value column='vcode'/>
    </responses>
</question>
```

**User Flow:**
1. User selects "Acholi" (region=7)
2. MRC dropdown shows: "Koch Goma HCIV", "Atiak HCIV"
3. User selects "Koch Goma HCIV" (mrccode=21)
4. Village dropdown shows: "Kal 'B'", "Kal 'A1'"

---

### Example 2: Select Mother from Household (Database)

**Scenario:** Child enrollment form needs to select mother from existing household members.

**XML Configuration:**
```xml
<!-- Automatic field: household ID (from parent form) -->
<question type='automatic' fieldname='hhid' fieldtype='text'>
</question>

<!-- Text input: Child's name -->
<question type='text' fieldname='child_name' fieldtype='text'>
    <text>Child's name</text>
    <maxCharacters>100</maxCharacters>
</question>

<!-- Database query: Select mother -->
<question type='combobox' fieldname='mother_id' fieldtype='text'>
    <text>Who is [[child_name]]'s mother?</text>
    <responses source='database' table='hh_members'>
        <filter column='hhid' value='[[hhid]]'/>
        <filter column='sex' value='1'/>
        <filter column='census_age' operator='>=' value='15'/>
        <display column='participantsname'/>
        <value column='uniqueid'/>
        <empty_message>No eligible mothers found. Please add female household members aged 15+ first.</empty_message>
    </responses>
</question>
```

**How it Works:**
1. `hhid` is automatically populated from parent form
2. User enters child's name
3. Question text shows "Who is [child's name]'s mother?"
4. Dropdown queries `hh_members` table for:
   - Same household (`hhid`)
   - Female (`sex=1`)
   - Age 15 or older (`census_age >= 15`)
5. Shows participant names, saves their `uniqueid`

---

### Example 3: Mixed Static and Dynamic

**Scenario:** Select school type (static), then school name from CSV filtered by type.

**CSV File: `schools.csv`**
```csv
school_type,school_code,school_name,district
primary,P001,Kampala Primary School,Kampala
primary,P002,Entebbe Primary School,Wakiso
secondary,S001,Kampala High School,Kampala
secondary,S002,Entebbe Secondary,Wakiso
```

**XML Configuration:**
```xml
<!-- Static school type selection -->
<question type='radio' fieldname='school_type' fieldtype='text'>
    <text>Type of school</text>
    <responses source='static'>
        <response value='primary'>Primary School</response>
        <response value='secondary'>Secondary School</response>
    </responses>
</question>

<!-- Dynamic school selection based on type -->
<question type='combobox' fieldname='school_code' fieldtype='text'>
    <text>Select the school</text>
    <responses source='csv' file='schools.csv'>
        <filter column='school_type' value='[[school_type]]'/>
        <display column='school_name'/>
        <value column='school_code'/>
    </responses>
</question>
```

---

## Performance Considerations

### CSV Files
- **All CSV files are loaded into memory when the survey starts**
- Filtering happens in memory (very fast)
- Suitable for files with up to several thousand rows
- For very large files (10,000+ rows), consider using database source instead

### Database Queries
- Queries execute when the question is displayed
- Local SQLite queries are very fast (milliseconds)
- No loading indicator is shown (database is small and local)
- Indexes on commonly filtered columns improve performance

### Best Practices
1. **Use static responses** for small, fixed lists (< 10 options)
2. **Use CSV** for medium-sized reference data (100-5000 rows)
3. **Use database** for querying entered survey data
4. **Apply filters** to reduce the number of options shown
5. **Use distinct** when the same value appears multiple times

---

## Display Field Label Lookup

When displaying records in the record selector, you can use the `[[fieldname]]` syntax in the `display_fields` configuration to automatically lookup and display the label for coded values.

### When to Use

Use this feature when you have fields with coded values (like radio/checkbox options) that you want to display as human-readable labels in the record list instead of the raw codes.

### Configuration

In your `survey_manifest.gistx` file, use `[[fieldname]]` syntax in the `display_fields`:

```json
{
  "tablename": "mosquito_nets",
  "displayname": "Mosquito Nets",
  "primarykey": "hhid,netnum",
  "incrementfield": "netnum",
  "display_fields": "[[brandnet]]"
}
```

### How It Works

**Without label lookup:**
```json
"display_fields": "brandnet"
```
Result: Shows "1 - 1" (raw value repeated)

**With label lookup:**
```json
"display_fields": "[[brandnet]]"
```
Result: Shows "1 - Permanet" (value + label from XML)

### XML Configuration

The field must have static response options defined in the XML:

```xml
<question type='radio' fieldname='brandnet' fieldtype='integer'>
  <text>Brand of mosquito net</text>
  <responses>
    <response value='1'>Permanet</response>
    <response value='2'>Olyset</response>
    <response value='3'>DawaPlus</response>
    <response value='4'>Other brand</response>
  </responses>
</question>
```

### Multiple Display Fields

You can combine regular fields with label lookups:

```json
"display_fields": "participantsname,[[brandnet]],[[netcolor]]"
```

Result: "1 - John Doe, Permanet, Blue"

### Current Limitations

- **Only works with static responses** (hardcoded `<response>` elements in XML)
- Does **not** support CSV or database response sources yet
- Labels are cached when the record selector loads for performance

### Implementation Details

The app loads all question definitions from XML files when you open the record selector. It caches the question options in memory for fast lookup. When displaying each record, it checks if a display field uses `[[...]]` syntax and looks up the corresponding label from the cached question options.

---

## Troubleshooting

### CSV file not found
**Error:** `CSV file not found: /path/to/file.csv`

**Solution:** Ensure the CSV file is in the same directory as your XML files.

### No options showing
**Possible causes:**
1. Filters are too restrictive - no rows match
2. Column names in XML don't match CSV headers exactly (case-sensitive)
3. Placeholder values are empty or incorrect

**Debug steps:**
1. Check CSV file has the correct column names (first row)
2. Verify filter values match data exactly
3. Add `<empty_message>` to see if filters return no results

### Incorrect values saved
**Possible cause:** `<value column='...'/>` specifies wrong column

**Solution:** Ensure `value` column contains the data you want saved to the database.

### Duplicate options showing
**Note:** Distinct is enabled by default. Duplicates should not normally appear.

**Possible cause:** You explicitly set `<distinct>false</distinct>`

**Solution:** Remove `<distinct>false</distinct>` or change it to `<distinct>true</distinct>` (or omit entirely for default behavior).

### Database table not found
**Error:** `Table 'xyz' does not exist`

**Solution:** Ensure the `table` attribute matches the XML filename (without `.xml`).

---

## Summary

| Feature | Static | CSV | Database |
|---------|--------|-----|----------|
| Use case | Fixed lists | Reference data | Survey data |
| Data location | XML file | CSV file | SQLite database |
| Filtering | N/A | Yes (multiple) | Yes (multiple) |
| Placeholders | N/A | Yes | Yes |
| Operators | N/A | =, !=, <, >, <=, >= | =, !=, <, >, <=, >= |
| Distinct | N/A | Yes (default true) | Yes (default true) |
| Empty message | N/A | Yes | Yes |
| Don't know option | Via `<dont_know>` in question | Via `<dont_know>` in responses | Via `<dont_know>` in responses |
| Not in list option | N/A | Via `<not_in_list>` | Via `<not_in_list>` |
| Performance | Instant | Very fast (in-memory) | Fast (local DB) |
| Question types | All | radio, combobox, checkbox | radio, combobox, checkbox |

---

## Quick Reference

### Static Response Template
```xml
<responses source='static'>
    <response value='1'>Option 1</response>
    <response value='2'>Option 2</response>
</responses>
```

### CSV Response Template
```xml
<responses source='csv' file='filename.csv'>
    <filter column='column_name' value='[[previous_answer]]'/>
    <display column='display_column'/>
    <value column='value_column'/>
    <!-- <distinct> defaults to true, only specify if you want false -->
    <empty_message>No options found</empty_message>
    <!-- Optional special options -->
    <dont_know value='-7' label="Don't know"/>
    <not_in_list value='-99' label='Not in this list'/>
</responses>
```

### Database Response Template
```xml
<responses source='database' table='table_name'>
    <filter column='column_name' value='[[previous_answer]]'/>
    <filter column='another_column' operator='>=' value='10'/>
    <display column='display_column'/>
    <value column='value_column'/>
    <empty_message>No records found</empty_message>
    <!-- Optional special options -->
    <dont_know value='-7'/>
    <not_in_list value='-99'/>
</responses>
```
