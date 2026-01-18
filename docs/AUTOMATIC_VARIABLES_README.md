# Calculation Fields Configuration Guide

This guide explains how to configure "Calculation Fields" in your survey XML files. These are fields that are calculated automatically by the app based on other answers, database records, or logic, rather than being entered by the user.

## Field Types Overview

### System Fields (Automatic - NOT in XML)
The following system fields are **automatically added to every CRF table** and do **NOT** need to be defined in XML files:

*   `starttime`: Timestamp when the survey started
*   `startdate`: Date when the survey started (yyyy-mm-dd)
*   `stoptime`: Timestamp when the survey finished
*   `uuid`: Unique identifier for the record (primary key)
*   `swver`: Software version used
*   `survey_id`: Survey definition ID
*   `lastmod`: Timestamp of last modification
*   `synced_at`: Timestamp when record was last synced to server

These fields are managed by the app's `AutoFields` service and should never appear in XML files.

### Calculation Fields (In XML)
For fields that need to be calculated from other data, use `type="calculation"` in your XML.

## Basic Structure

Calculation fields are defined using the `<question>` tag with `type="calculation"` (or `type="calc"` or `type="calculated"`).

```xml
<question type="calculation" fieldname="my_calculated_field">
  <calculation type="...">
    <!-- Configuration specific to the calculation type -->
  </calculation>
</question>
```

**Note:** The old `type="calculation"` is still supported for backward compatibility but will be treated as `type="calculation"`.

### Common Attributes

*   **`preserve="true"`**: (Optional) If set to `true`, the value is only calculated *once* (when it's empty). It will not be re-calculated if the user edits the survey later. This is useful for things like timestamps or generated IDs that shouldn't change.

---

## Calculation Types

### 1. Constant (`type="constant"`)
Returns a fixed value.

*   **`value`**: The string to return.
*   **Special Values**:
    *   `NOW`: Current date and time (ISO 8601).
    *   `NOW_YEAR`: Current year (e.g., "2024").

**Example:**
```xml
<question type="calculation" fieldname="survey_version">
  <calculation type="constant" value="v1.0" />
</question>
```

### 2. Lookup (`type="lookup"`)
Returns the value of another field in the current survey.

*   **`field`**: The name of the field to copy.

**Example:**
```xml
<question type="calculation" fieldname="copy_of_age">
  <calculation type="lookup" field="age" />
</question>
```

### 3. Math (`type="math"`)
Performs arithmetic operations (`+`, `-`, `*`, `/`).

*   **`operator`**: The operation to perform.
*   **`<part>`**: The operands. Can be nested calculations (lookups, constants, etc.).

**Example: Calculate Year of Birth**
```xml
<question type="calculation" fieldname="yob">
  <calculation type="math" operator="-">
    <part type="constant" value="NOW_YEAR" />
    <part type="lookup" field="age" />
  </calculation>
</question>
```

**Complex Math Example: BMI Calculation**
Calculates BMI = Weight / (Height * Height). Note that height is often in cm, so we divide by 100 first.

```xml
<question type="calculation" fieldname="bmi">
  <calculation type="math" operator="/">
    <!-- Numerator: Weight (kg) -->
    <part type="lookup" field="weight" />
    
    <!-- Denominator: Height (m) * Height (m) -->
    <part type="math" operator="*">
      <!-- Height in meters (cm / 100) -->
      <part type="math" operator="/">
        <part type="lookup" field="height_cm" />
        <part type="constant" value="100" />
      </part>
      <!-- Height in meters again -->
      <part type="math" operator="/">
        <part type="lookup" field="height_cm" />
        <part type="constant" value="100" />
      </part>
    </part>
  </calculation>
</question>
```

### 4. Concatenation (`type="concat"`)
Joins multiple strings together.

*   **`separator`**: (Optional) A string to put between parts (e.g., "-").
*   **`<part>`**: The values to join.

**Example: Generate Full Name**
```xml
<question type="calculation" fieldname="fullname">
  <calculation type="concat" separator=" ">
    <part type="lookup" field="firstname" />
    <part type="lookup" field="lastname" />
  </calculation>
</question>
```

### 5. Case Logic (`type="case"`)
Implements "If / Else If / Else" logic.

*   **`<when>`**: Defines a condition.
    *   `field`: The field to check.
    *   `operator`: `=`, `!=`, `>`, `<`, `>=`, `<=`.
    *   `value`: The value to compare against.
    *   `result`: The value to return if true (can be a nested calculation).
*   **`<else>`**: (Optional) The fallback value if no conditions are met.

**Example: Age Category**
```xml
<question type="calculation" fieldname="age_category">
  <calculation type="case">
    <when field="age" operator="&lt;" value="18">
      <result type="constant" value="Minor" />
    </when>
    <when field="age" operator="&gt;=" value="65">
      <result type="constant" value="Senior" />
    </when>
    <else>
      <result type="constant" value="Adult" />
    </else>
  </calculation>
</question>
```

### 6. Database Query (`type="query"`)
Executes a SQL query against the local database.

*   **`<sql>`**: The SQL statement. Use `@paramName` for placeholders.
*   **`<parameter>`**: Maps a placeholder to a current survey field.
    *   `name`: The placeholder name (without `@`).
    *   `field`: The source field in the current survey.

**Example: Lookup MRC Code from another table**
```xml
<question type="calculation" fieldname="mrccode">
  <calculation type="query">
    <sql>SELECT mrccode FROM schools WHERE school_id = @schoolId</sql>
    <parameter name="schoolId" field="school_name" />
  </calculation>
</question>
```

---

## Complex Examples

### 1. Generating a Unique ID
Combines `constant`, `lookup`, and `query` to create an ID like `GL-01-005`.

**Expected Output:** `GL-01-005` (where `GL` is fixed, `01` is community code, `005` is next sequence number)

```xml
<question type="calculation" fieldname="generated_id">
  <calculation type="concat" separator="-">
    <!-- Prefix -->
    <part type="constant" value="GL" />
    
    <!-- Community Code -->
    <part type="lookup" field="community_code" />
    
    <!-- Auto-Increment Number -->
    <part type="query">
      <sql>
        SELECT printf('%03d', IFNULL(MAX(CAST(substr(uniqueid, -3) AS INTEGER)), 0) + 1)
        FROM households 
        WHERE community_code = @comm
      </sql>
      <parameter name="comm" field="community_code" />
    </part>
  </calculation>
</question>
```

### 2. Nested Logic (OR Condition)
Since `case` evaluates sequentially, you can simulate "OR" logic by repeating the result.

**Logic:** If `fever` is 'Yes' (1) OR `temp` > 37.5, then 'Refer', else 'Home'.

**Expected Output:**
*   Fever=1, Temp=36.0 -> `Refer`
*   Fever=0, Temp=38.0 -> `Refer`
*   Fever=0, Temp=36.5 -> `Home`

```xml
<question type="calculation" fieldname="action">
  <calculation type="case">
    <!-- Condition 1: Fever is Yes -->
    <when field="fever" operator="=" value="1">
      <result type="constant" value="Refer" />
    </when>
    <!-- Condition 2: Temp > 37.5 -->
    <when field="temp" operator="&gt;" value="37.5">
      <result type="constant" value="Refer" />
    </when>
    <!-- Default -->
    <else>
      <result type="constant" value="Home" />
    </else>
  </calculation>
</question>
```

### 3. Dynamic Eligibility Check
Determines if a participant is eligible based on Age AND Gender.
**Logic:** Eligible if Age >= 18 AND Gender = 'Female'.

**Expected Output:**
*   Age=20, Gender=Female -> `Eligible`
*   Age=16, Gender=Female -> `Not Eligible`
*   Age=25, Gender=Male -> `Not Eligible`

```xml
<question type="calculation" fieldname="eligibility_status">
  <calculation type="case">
    <!-- Check Age first -->
    <when field="age" operator="&gt;=" value="18">
      <!-- Nested Case: Check Gender if Age is OK -->
      <result type="case">
        <when field="gender" operator="=" value="Female">
           <result type="constant" value="Eligible" />
        </when>
        <else>
           <result type="constant" value="Not Eligible" />
        </else>
      </result>
    </when>
    <!-- Default (Age < 18) -->
    <else>
      <result type="constant" value="Not Eligible" />
    </else>
  </calculation>
</question>
```

### 7. `date_offset`

Calculates a new date by adding or subtracting time from an existing date field.

**Attributes:**
*   `field`: The field name of the base date (must be a `date` or `datetime` field).
*   `value`: The offset string (e.g., `+28d`, `-1y`, `+4w`, `-6m`).
    *   `d`: Days
    *   `w`: Weeks
    *   `m`: Months
    *   `y`: Years

**Example:**
```xml
<question type="calculation" fieldname="dose2_due_date" fieldtype="date">
    <calculation type="date_offset" field="vx_dose1_date" value="+28d" />
</question>
```

### 8. `date_diff`

Calculates the difference between two dates.

**Attributes:**
*   `field`: The start date field (or the literal string `today`).
*   `value`: The end date field (or the literal string `today`).
*   `unit`: The unit of time to return:
    *   `d`: Days (default)
    *   `w`: Weeks (whole weeks)
    *   `m`: Months (whole months, accurately calculated)
    *   `y`: Years (whole years, accurately calculated)

**Example:**
```xml
<question type="calculation" fieldname="dose2_warning_time" fieldtype="integer">
    <calculation type="date_diff" field="vx_dose1_date" value="vx_dose2_date" unit="w" />
</question>
```

---

## Important Notes
*   **Sequential Execution**: Automatic calculations are performed in the order they appear in the XML. Ensure any field referenced in a `calculation` (e.g., through `field` or `sqlParams`) is defined BEFORE the automatic question.
*   **Built-in Fields**: Standard fields like `uniqueid`, `starttime`, and `stoptime` are reserved and handled automatically by the system.
