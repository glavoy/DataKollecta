# Age Calculation and Validation Guide

This guide explains how to use the age calculation features in your XML survey files to validate age entries against date of birth.

## Overview

The system now supports automatic age calculations from date fields, which can be used in logic checks to validate user-entered ages against dates of birth.

## Calculation Types

### 1. `age_from_date` - Calculate age to today

Calculates the age from a date field to the current date.

**XML Syntax:**
```xml
<question type='automatic' fieldname='age_calculated' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='years'/>
</question>
```

**Attributes:**
- `type='age_from_date'` - Required. Specifies this is an age calculation to today
- `field='dob'` - Required. The fieldname of the date to calculate from
- `value='years'` - Optional. Unit of measurement. Options:
  - `'years'` (default) - Returns age in whole years
  - `'months'` - Returns age in total months
  - `'days'` - Returns age in total days

**Examples:**
```xml
<!-- Calculate age in years -->
<question type='automatic' fieldname='age_years' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='years'/>
</question>

<!-- Calculate age in months -->
<question type='automatic' fieldname='age_months' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='months'/>
</question>

<!-- Calculate age in days -->
<question type='automatic' fieldname='age_days' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='days'/>
</question>
```

### 2. `age_at_date` - Calculate age at a specific date

Calculates the age from a date field to a specific target date (useful for eligibility criteria).

**XML Syntax:**
```xml
<question type='automatic' fieldname='age_on_cutoff' fieldtype='integer'>
    <calculation type='age_at_date' field='dob' value='months' separator='2025-05-31'/>
</question>
```

**Attributes:**
- `type='age_at_date'` - Required. Specifies this is an age calculation to a specific date
- `field='dob'` - Required. The fieldname of the date to calculate from
- `separator='2025-05-31'` - Required. The target date in ISO format (YYYY-MM-DD)
- `value='months'` - Optional. Unit of measurement (years, months, or days)

**Examples:**
```xml
<!-- Calculate age in months on May 31, 2025 -->
<question type='automatic' fieldname='age_on_may31' fieldtype='integer'>
    <calculation type='age_at_date' field='dob' value='months' separator='2025-05-31'/>
</question>

<!-- Calculate age in years on a specific enrollment date -->
<question type='automatic' fieldname='age_at_enrollment' fieldtype='integer'>
    <calculation type='age_at_date' field='dob' value='years' separator='2025-12-31'/>
</question>
```

## Using Age Calculations in Logic Checks

Once you have automatic age calculation fields, you can reference them in logic checks to validate user input.

### Example 1: Validate entered age matches DOB

```xml
<!-- Date of birth -->
<question type='date' fieldname='dob' fieldtype='date'>
    <text>Record date of birth</text>
    <date_range>
        <min_date>-5y</min_date>
        <max_date>0</max_date>
    </date_range>
</question>

<!-- Calculate age automatically -->
<question type='automatic' fieldname='age_calculated' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='years'/>
</question>

<!-- User enters age with validation -->
<question type='text' fieldname='age' fieldtype='integer'>
    <text>Record age in years</text>
    <maxCharacters>1</maxCharacters>
    <numeric_check>
        <values minvalue='0' maxvalue='5' other_values='0'
                message='Number must be between 0 and 5!'></values>
    </numeric_check>
    <logic_check message='The age entered does not match the date of birth!'>
        age &lt;&gt; age_calculated
    </logic_check>
</question>
```

**How it works:**
1. User enters date of birth
2. System automatically calculates `age_calculated` from the DOB
3. User enters age manually
4. Logic check compares entered age with calculated age
5. If they don't match, shows error message

### Example 2: Complex eligibility validation

```xml
<!-- Date of birth -->
<question type='date' fieldname='dob' fieldtype='date'>
    <text>Record date of birth</text>
    <date_range>
        <min_date>-5y</min_date>
        <max_date>0</max_date>
    </date_range>
</question>

<!-- Calculate current age in months -->
<question type='automatic' fieldname='age_in_months' fieldtype='integer'>
    <calculation type='age_from_date' field='dob' value='months'/>
</question>

<!-- Calculate age on specific date -->
<question type='automatic' fieldname='age_on_may31_2025' fieldtype='integer'>
    <calculation type='age_at_date' field='dob' value='months' separator='2025-05-31'/>
</question>

<!-- Eligibility question with complex validation -->
<question type='radio' fieldname='age_eligible' fieldtype='integer'>
    <text>Individual is between 6 months and 5 years of age at time of enrolment

OR

Individual was 11 months or younger (or not yet born) on May 31 2025</text>
    <responses>
        <response value='1'>Yes - continue to next criterium</response>
        <response value='0'>No - exclude</response>
    </responses>
    <logic_check message='Age eligibility selection does not match the age criteria!'>
        (age_eligible = 1 and age_in_months &lt; 6) or
        (age_eligible = 1 and age_in_months &gt; 60) or
        (age_eligible = 0 and age_in_months &gt;= 6 and age_in_months &lt;= 60) or
        (age_eligible = 0 and age_on_may31_2025 &lt;= 11)
    </logic_check>
</question>
```

**How it works:**
1. User enters DOB
2. System calculates current age in months
3. System calculates age on May 31, 2025 in months
4. User selects Yes or No for eligibility
5. Logic check validates:
   - If user said "Yes" but age is < 6 months → ERROR
   - If user said "Yes" but age is > 60 months (5 years) → ERROR
   - If user said "No" but age is between 6-60 months → ERROR
   - If user said "No" but age on May 31, 2025 was ≤ 11 months → ERROR

## Important Notes

### XML Character Escaping

When writing logic checks in XML, you must escape special characters:
- `<` becomes `&lt;`
- `>` becomes `&gt;`
- `&` becomes `&amp;`
- `"` becomes `&quot;`
- `'` becomes `&apos;`

**Example:**
```xml
<!-- WRONG - will cause XML parsing error -->
<logic_check message='Error'>
    age < 5 and age > 0
</logic_check>

<!-- CORRECT - properly escaped -->
<logic_check message='Error'>
    age &lt; 5 and age &gt; 0
</logic_check>
```

### Date Field Requirements

The date field referenced in `field` attribute must:
1. Be of type `date` or `datetime`
2. Come before the automatic calculation question in the survey order
3. Be answered before the logic check is evaluated

### Logic Check Behavior

Logic checks return TRUE when validation **FAILS**:
- If the condition evaluates to `true`, the error message is shown
- If the condition evaluates to `false`, validation passes

This is counter-intuitive but intentional. Write your conditions to describe what makes the check fail.

**Example:**
```xml
<!-- This condition says: "Show error if age does NOT match calculated age" -->
<logic_check message='Age mismatch!'>
    age &lt;&gt; age_calculated
</logic_check>
```

## Complete Working Example

See the file `tmp/enrollee_with_age_validation.xml` for a complete working example that includes:
- Date of birth entry
- Automatic age calculations (years, months, specific date)
- Age entry with validation
- Complex eligibility validation

## Testing Your Calculations

To test your age calculations:

1. Create a test survey with a DOB field and automatic calculation
2. Run the survey and enter a known date of birth
3. Check the database to verify the calculated age is correct
4. Test edge cases:
   - Birthday today
   - Birthday yesterday
   - Birthday tomorrow
   - End of month dates (e.g., Feb 29, Jan 31)

## Troubleshooting

### Calculation returns empty string

**Possible causes:**
- The date field hasn't been answered yet
- The date field name is misspelled in the `field` attribute
- The date format is invalid

**Solution:** Ensure the date field is answered before the automatic calculation runs.

### Logic check doesn't work

**Possible causes:**
- Automatic field comes after the field being validated
- Field names are misspelled
- Logic condition syntax is incorrect

**Solution:**
- Move automatic calculations before the questions that reference them
- Double-check field names match exactly
- Test logic conditions step by step

### Age is off by one

**Possible causes:**
- Birthday hasn't occurred yet this year/month

**Solution:** This is correct behavior. Age calculations properly account for whether the birthday has occurred yet.

## Additional Resources

- See `lib/services/auto_fields.dart` for implementation details
- See `lib/services/logic_service.dart` for logic check evaluation
- See existing XML files in `tmp/` folder for more examples
