# GiSTX XML Creation Guide

This document provides a comprehensive guide for manually creating survey XML files for the GiSTX application. It details the structure of the XML, the `question` element, and all supported options, attributes, and child tags.

## Basic Structure

The root element of the XML file is `<survey>`. Inside this root element, you define a series of `<question>` elements.

```xml
<?xml version = '1.0' encoding = 'utf-8'?>
<survey>
    <!-- Questions go here -->
    <question ...>
        ...
    </question>
</survey>
```

## The `<question>` Element

The `<question>` element is the building block of the survey. It requires specific attributes to define its behavior and data storage.

### Attributes

| Attribute | Description | Required | Options |
| :--- | :--- | :--- | :--- |
| `type` | The control type used to display the question. | Yes | `text`, `radio` (single select), `checkbox` (multi-select), `combobox` (dropdown), `date`, `datetime`, `information` (read-only), `calculation` (computed fields - also accepts `calc`, `calculated`, or legacy `automatic`) |
| `fieldname` | A unique identifier for the question (variable name). This is used in logic, skips, and database columns. | Yes | Text string (no spaces, e.g., `dob`, `participant_name`) |
| `fieldtype` | The data type for storage. | Yes | `text`, `integer`, `text_integer`, `date`, `datetime`, `n/a` (for information/label types) |

### Example

```xml
<question type='text' fieldname='participant_name' fieldtype='text'>
    <text>What is the participant's name?</text>
</question>
```

## Child Elements of `<question>`

The following elements can be nested inside a `<question>` tag to define its properties.

### `<text>`
Defines the label or question text displayed to the user.
- **Placeholders:** You can reference values from previous questions using `[[fieldname]]`.

```xml
<text>What is the gender of [[participant_name]]?</text>
```

### `<maxCharacters>`
Restricts the length of the input.
- **Value:** An integer (e.g., `80`) or an integer prefixed with `=` for fixed length (e.g., `=5` means exact length of 5).

```xml
<maxCharacters>80</maxCharacters>
<!-- OR -->
<maxCharacters>=10</maxCharacters>
```

### `<mask>`
Enforces a specific input pattern (RegEx-like).
- **Attribute:** `value` containing the mask pattern.
    - `[0-9]`: Any digit.
    - `[A-Z]`: Any uppercase letter.
    - `[A-Z0-9]`: Alphanumeric.

```xml
<mask value="R21-[0-9][0-9][0-9]-[A-Z0-9][0-9A-Z]" />
```

### `<responses>`
Defines the options for `radio`, `checkbox`, or `combobox` questions. Can be static or dynamic.

#### Static Responses (Default)
Hardcoded list of options.
- **Child Tag:** `<response value='stored_value'>Display Label</response>`

```xml
<question type='radio' fieldname='gender' fieldtype='integer'>
    <text>Gender</text>
    <responses>
        <response value='1'>Male</response>
        <response value='2'>Female</response>
    </responses>
</question>
```

#### Dynamic Responses (CSV or Database)
Loads options from an external source.
- **Attribute `source`:** `'csv'` or `'database'`.
- **Attribute `file` (CSV only):** Filename (e.g., `villages.csv`).
- **Attribute `table` (DB only):** Table name.
- **Child Tags:**
    - `<filter>`: Filters rows based on criteria.
        - Attributes: `column`, `operator` (default `=`), `value` (can use `[[fieldname]]`).
    - `<display>`: Column to show to the user (`column` attribute).
    - `<value>`: Column to store (`column` attribute).
    - `<distinct>`: `true` to show unique values only.
    - `<dont_know>` / `<not_in_list>`: Adds special options.

```xml
<responses source='csv' file='villages.csv'>
    <filter column='districtid' operator='=' value='[[district]]'/>
    <display column='village_name'/>
    <value column='village_id'/>
</responses>
```

### `<numeric_check>`
Validates numeric input ranges.
- **Child Tag:** `<values>`
    - `minvalue`: Minimum acceptable value.
    - `maxvalue`: Maximum acceptable value.
    - `other_values`: Comma-separated list of allowed exceptions (e.g., '99' for unknown).
    - `message`: Error message to display.

```xml
<numeric_check>
    <values minvalue='18' maxvalue='99' other_values='0' message='Age must be between 18 and 99!'/>
</numeric_check>
```

### `<date_range>`
Restricts date inputs.
- **Child Tags:** `<min_date>` and `<max_date>`.
- **Formats:**
    - ISO Date: `2025-01-01`
    - Relative: `-3y` (3 years ago), `+1m` (1 month future), `0` (today).

```xml
<date_range>
    <min_date>-100y</min_date>
    <max_date>0</max_date>
</date_range>
```

### `<logic_check>`
Custom validation logic.
- **Content:** `condition; 'Error Message'`
- **Alternative:** Attribute `message` on tag, condition as text content.

```xml
<logic_check>
    age &lt; 18; 'Participant must be an adult.'
</logic_check>
```
*Note: `&lt;` is `<` and `&gt;` is `>` in XML.*

### `<unique_check>`
Ensures the value hasn't been used before in the database.
- **Child Tag:** `<message>`

```xml
<unique_check>
    <message>This ID has already been registered!</message>
</unique_check>
```

### `<preskip>` and `<postskip>`
Controls logic flow (skipping questions).
- `preskip`: Evaluated *before* showing the question (to hide it).
- `postskip`: Evaluated *after* answering (to jump to a later question).
- **Child Tag:** `<skip>`
    - `fieldname`: The field to check.
    - `condition`: Operator (`=`, `<>`, `<`, `>`).
    - `response`: Value to check against.
    - `skiptofieldname`: The `fieldname` of the question to jump to.

```xml
<preskip>
    <!-- If age is less than 18, skip to the 'parent_consent' question -->
    <skip fieldname='age' condition='&lt;' response='18' skiptofieldname='parent_consent'/>
</preskip>
```

### `<calculation>`
Used for `calculation` type questions to compute values from other fields, database lookups, or formulas.
- **Attribute `type`:**
    - `age_from_date`: Calculates age from a date field.
        - `field`: Source date field.
        - `value`: `'years'` or `'months'`.
    - `age_at_date`: Age at a specific reference date.
        - `separator`: Reference date (ISO string).
    - `date_diff`: Difference between two dates.
        - `field`: Start date.
        - `value`: End date.
        - `unit`: `'y'`, `'m'`, `'w'`, `'d'`.
    - `case`: Conditional logic (if/else).
        - Child `<when>`: attributes `field`, `operator`, `value`, and child `<result>`.
        - Child `<else>`: child `<result>`.
    - `concat`: Concatenates values.
    - `math`: Basic arithmetic.
    - `constant`: Fixed value.

**Example: Age Calculation**
```xml
<question type='calculation' fieldname='age_years' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='years'/>
</question>
```

**Example: Conditional Logic**
```xml
<question type='calculation' fieldname='is_eligible' fieldtype='integer'>
    <calculation type='case'>
        <when field='age' operator='&gt;=' value='18'>
            <result type='constant' value='1' />
        </when>
        <else>
            <result type='constant' value='0' />
        </else>
    </calculation>
</question>
```

### Other Options
- `<dont_know>`: Adds a "Don't know" option to the list. Text content is the stored value (e.g., `99`).
- `<refuse>`: Adds a "Refuse to answer" option.

## Full Example Snippet

```xml
<question type='radio' fieldname='education' fieldtype='integer'>
    <text>What is your highest level of education?</text>
    <responses>
        <response value='0'>None</response>
        <response value='1'>Primary</response>
        <response value='2'>Secondary</response>
    </responses>
    <preskip>
        <skip fieldname='age' condition='&lt;' response='5' skiptofieldname='next_section'/>
    </preskip>
</question>
```