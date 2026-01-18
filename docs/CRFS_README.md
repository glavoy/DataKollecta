# CRFS Table Configuration Guide

The `crfs` table is the backbone of the GiSTX application's survey navigation and logic. It defines the available forms, their hierarchy, ID generation rules, and auto-repeat behaviors.

## Table Structure & Field Usage

### Basic Identification
*   **`tablename`**: The unique identifier for the form (e.g., `enrollment`, `followup`). This matches the XML filename (without the '_dd' extension).
*   **`displayname`**: The human-readable name shown to the user (e.g., "Enrollment Form").
*   **`display_order`**: An integer determining the order in which forms appear in the list.

### Hierarchy & Navigation
*   **`parenttable`**: Defines the parent-child relationship.
    *   If `NULL` or empty: This is a top-level form (e.g., Household).
    *   If set (e.g., `household`): This form is a child of the specified table (e.g., Members within a Household).
*   **`linkingfield`**: The field used to link a child record to its parent.
    *   Example: If `parenttable` is `household` and `linkingfield` is `hhid`, the child record will inherit the `hhid` from the selected parent record.

### List Display Configuration
*   **`display_fields`**: A comma-separated list of field names used to summarize records in the selection list.
    *   Example: `subjid, name, age`
    *   Result: The list will show "GX001 - John Doe - 45" instead of just the ID.

---

## ID Generation (`idconfig`)

The `idconfig` field contains a JSON object that defines how unique IDs (Subject IDs, Household IDs) are generated for records in this table.

### Structure
```json
{
  "prefix": "STRING",
  "fields": [
    {"name": "field_name", "length": INT},
    ...
  ],
  "incrementLength": INT
}
```

### Fields Detail
1.  **`prefix`**: A static string prepended to every ID.
    *   Example: `"GL"` -> ID starts with "GL..."
2.  **`fields`**: A list of fields from the *current survey answers* to include in the ID.
    *   **`name`**: The field name in the XML form.
    *   **`length`**: The fixed length for this part. The value will be padded with leading zeros (e.g., `1` -> `01`) or truncated if too long.
3.  **`incrementLength`**: The number of digits for the auto-incrementing sequence number appended at the end.
    *   Example: `3` -> `001`, `002`, `...999`.

### Examples

#### Example 1: Simple Prefix + Increment
```json
{
  "prefix": "GL",
  "fields": [
    {"name": "community", "length": 2}
  ],
  "incrementLength": 3
}
```
*   **Scenario**: User enters `12` for `community`.
*   **Logic**:
    1.  Prefix: `GL`
    2.  Community: `12` (padded to length 2)
    3.  Increment: Finds next available number (e.g., `001`)
*   **Result**: `GL12001`

#### Example 2: Complex Composite ID
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
*   **Scenario**:
    *   `country` = `1`
    *   `parish` = `5`
    *   `village` = `10`
*   **Logic**:
    1.  Prefix: `SP`
    2.  Country: `1` (length 1)
    3.  Parish: `05` (length 2, padded)
    4.  Village: `10` (length 2)
    5.  Increment: `001`
*   **Result**: `SP10510001`

---

## Auto-Repeat Logic

These fields control how the app automatically launches child surveys based on an answer in the parent survey (e.g., "How many people live here?").

### Fields Detail

*   **`repeat_count_field`**: The field name in the *current* (parent) survey that contains the total number of child records to create.
    *   Example: `member_count`

*   **`repeat_count_source`**: The table name where the `repeat_count_field` is located.
    *   Usually matches the current `tablename`.

*   **`auto_start_repeat`**: Controls the automation behavior.
    *   `0`: **Disabled**. No auto-repeat logic.
    *   `1`: **Prompt**. After saving the parent form, asks the user: "Do you want to start entering records for [Child Form]?"
    *   `2`: **Force**. Immediately launches the child form loop after saving the parent form.

*   **`repeat_enforce_count`**: Controls how strictly the app enforces the record count.
    *   `0`: **Flexible**. No enforcement. The user can enter fewer or more records than specified.
    *   `1`: **Warn** (Default). If the count doesn't match, the app warns the user and offers to update the parent record's count field.
    *   `2`: **Force**. Strict enforcement. The app prevents the user from exiting the loop until the exact number of records are created.
    *   `3`: **Auto-Sync**. Silent enforcement. The app automatically updates the parent record's count field to match the actual number of records entered.

### Example Workflow
**Scenario**: Household Survey (`household`) asks "How many members?" (`mem_count`). We want to automatically start the Member Form (`members`).

**Configuration in `crfs` table for `members` row:**
*   `tablename`: `members`
*   `parenttable`: `household`
*   `repeat_count_source`: `household`
*   `repeat_count_field`: `mem_count`
*   `auto_start_repeat`: `2` (Force start)

**User Experience**:
1.  User fills Household form, enters `3` for `mem_count`.
2.  User clicks "Finish".
3.  App saves Household record.
4.  App immediately opens "Member 1 of 3".
5.  User finishes Member 1 -> App opens "Member 2 of 3".
6.  ...until Member 3 is done.
