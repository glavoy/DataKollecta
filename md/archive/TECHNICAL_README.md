# GiSTX - Technical Documentation

## Overview

GiSTX is a Flutter-based offline survey/questionnaire application designed for data collection in field research settings. It uses XML-based survey definitions to create dynamic forms with skip logic, validation, and SQLite database storage.

## Architecture

### Core Components

```
lib/
├── config/          # Application configuration
├── models/          # Data models
├── screens/         # UI screens
├── services/        # Business logic
└── widgets/         # Reusable UI components
```

---

## Application Flow

### 1. Application Startup (`main.dart`)

**Entry Point:**
- `main()` initializes the app and runs `MyApp`
- `MyApp` is a stateless widget that sets up:
  - Material theme
  - Initial route to `MainScreen`

### 2. Main Screen (`screens/main_screen.dart`)

**Purpose:** Survey selection and record management interface

**Flow:**
1. Loads CRF (Case Report Form) configuration from database
2. Displays available surveys based on `crfs` table
3. Provides two main actions per survey:
   - **New Interview:** Creates a new survey response
   - **Modify Interview:** Edits existing survey responses

**Database Interaction:**
- Queries `crfs` table to get available surveys
- Each CRF has:
  - `filename`: XML survey definition file
  - `id_config`: JSON configuration for ID generation
  - `primary_keys`: Fields that uniquely identify records
  - `linking_field`: Field used to link to parent records (for hierarchical surveys)

---

## Survey Loading Process

### 3. Survey Initialization

When a user selects a survey, the app navigates to `SurveyScreen`:

**Constructor Parameters:**
```dart
SurveyScreen({
  required String questionnaireFilename,  // XML file name
  Map<String, dynamic>? existingAnswers,  // For edit mode
  String? uniqueId,                       // Existing record ID
  List<String>? primaryKeyFields,         // Key fields
  Map<String, dynamic>? prepopulatedAnswers, // Parent data
  String? idConfig,                       // ID generation config
  String? linkingField,                   // Parent link field
})
```

### 4. XML Survey Parsing (`services/survey_loader.dart`)

**Process:**

1. **Load XML from assets:**
   ```dart
   final xmlStr = await rootBundle.loadString('assets/surveys/${filename}');
   final doc = XmlDocument.parse(xmlStr);
   ```

2. **Parse each `<question>` element:**
   - Extract question type (text, radio, checkbox, date, etc.)
   - Parse field name and field type
   - Extract question text
   - Parse validation rules (`numeric_check`)
   - Parse response options
   - Parse skip conditions (`preskip`, `postskip`)
   - Parse logic checks
   - Parse special responses (`dont_know`, `refuse`)

3. **Build Question objects:**
   ```dart
   Question(
     type: QuestionType,
     fieldName: String,
     fieldType: String,
     text: String?,
     options: List<QuestionOption>,
     numericCheck: NumericCheck?,
     preSkips: List<SkipCondition>,
     postSkips: List<SkipCondition>,
     logicCheck: String?,
     dontKnow: String?,
     refuse: String?,
   )
   ```

**XML Structure Example:**
```xml
<question type="radio" fieldname="sex" fieldtype="integer">
  <text>Participant's Sex</text>
  <responses>
    <response value="1">Male</response>
    <response value="2">Female</response>
  </responses>
  <preskip>
    <skip fieldname="age" condition="<" response="18"
          response_type="fixed" skiptofieldname="end"/>
  </preskip>
</question>
```

---

## Data Flow During Survey

### 5. Answer Storage

**Central Data Structure:**
```dart
typedef AnswerMap = Map<String, dynamic>;
```

All answers are stored in `_answers` map in `SurveyScreen`:
- **Text/Radio/Combobox:** `String`
- **Checkbox:** `List<String>`
- **Date:** `String` (YYYY-MM-DD format)
- **DateTime:** `DateTime` object

### 6. Question Rendering (`widgets/question_views.dart`)

**QuestionView Widget:**
- Stateful widget that renders appropriate UI based on `QuestionType`
- Maintains local state for UI (selected values)
- Updates shared `AnswerMap` when values change

**Question Type Implementations:**

1. **Text Input (`_buildText`):**
   - `TextField` with validation
   - Supports `maxCharacters`
   - Validates `numeric_check` for integer fields
   - Auto-focuses on load

2. **Radio Buttons (`_buildRadio`):**
   - Uses `RadioListTile` for each option
   - Single selection
   - Updates `_radioSelection` and `answers[fieldName]`

3. **Checkboxes (`_buildCheckbox`):**
   - Uses `CheckboxListTile` for each option
   - Multiple selection
   - Stores as `List<String>` in answers map

4. **Dropdown/Combobox (`_buildCombobox`):**
   - Uses `DropdownButton`
   - Single selection from list

5. **Date Picker (`_buildDate`):**
   - Shows date picker dialog
   - Stores as YYYY-MM-DD string
   - Supports special responses (don't know, refuse)
   - Special response buttons appear below date picker if configured

6. **DateTime Picker (`_buildDateTime`):**
   - Shows date picker then time picker
   - Stores as `DateTime` object

7. **Information Display (`_buildInformation`):**
   - Non-interactive text display
   - Supports placeholder expansion (e.g., `[[fieldname]]`)

---

## Navigation & Skip Logic

### 7. Question Navigation (`screens/survey_screen.dart`)

**Navigation State:**
```dart
int _currentQuestion;           // Current question index
List<int> _history;             // Navigation history
Set<String> _visitedFields;     // Tracking displayed questions
```

**Forward Navigation (`_next`):**

1. Add current question to history (if not automatic)
2. Check **postskip** conditions on current question
3. Determine next question index
4. Call `_findNextDisplayedQuestion` to handle:
   - Automatic questions (process and skip)
   - Primary key questions in edit mode (skip)
   - Preskip conditions (jump to target)
5. Update `_currentQuestion` and clear logic errors

**Backward Navigation (`_prev`):**
- Pop from `_history` stack
- Return to previous displayed question

### 8. Skip Conditions (`services/skip_service.dart`)

**Skip Condition Structure:**
```dart
SkipCondition(
  fieldName: 'sex',           // Field to check
  condition: '=',             // Operator
  response: '1',              // Value to compare
  responseType: 'fixed',      // 'fixed' or 'dynamic'
  skipToFieldName: 'village', // Target question
)
```

**Evaluation:**
```dart
static String? evaluateSkips(List<SkipCondition> skips, AnswerMap answers)
```

- Returns target field name if condition is met
- Returns null if no skip should occur
- Supports operators: `=`, `<>`, `<`, `>`, `<=`, `>=`, `contains`, `does not contain`

**Types of Skips:**
- **Preskip:** Evaluated BEFORE showing a question (can prevent question from displaying)
- **Postskip:** Evaluated AFTER answering a question (jumps to target after answer)

---

## Validation System

### 9. Answer Validation

**Two-stage validation:**

1. **`_isAnswered(Question q)`:**
   - Checks if question has been answered
   - Type-specific checks:
     - Text: non-empty string
     - Radio/Combobox: value exists
     - Checkbox: list not empty
     - Date/DateTime: value exists
   - Special case: 'comments' field is always optional

2. **`_isValid(Question q)`:**
   - Validates answer correctness
   - For integer text fields:
     - Parses as integer
     - Checks against `numeric_check` range
     - Supports exception values (`other_values`)

### 10. Logic Checks (`services/logic_service.dart`)

**Purpose:** Cross-field validation with custom error messages

**Format:**
```xml
<logic_check>
  tabletnum2 &lt;&gt; tabletnum; 'This does not match your previous entry!'
</logic_check>
```

**Parsing Process:**

1. **Normalize whitespace:**
   - Collapses newlines/tabs to single spaces
   - Allows multi-line logic in XML

2. **Split into condition and message:**
   ```dart
   final parts = expression.split(';');
   final conditionStr = parts[0];  // "tabletnum2 <> tabletnum"
   final message = parts[1];        // "'This does...'"
   ```

3. **Evaluate expression:**
   - Supports `OR` and `AND` operators
   - Supports parentheses for grouping
   - Example: `(field1 = '2' and field2 = '29') or (field1 = '3' and field2 = '30')`

4. **Condition evaluation:**
   - Regex pattern: `(fieldname) (operator) (value)`
   - Value can be quoted string or field reference
   - Compares values (numeric or string)
   - Returns `true` if condition fails (error exists)

**Result:**
- Returns error message string if validation fails
- Returns null if validation passes
- Error displayed in UI, blocks navigation

---

## Automatic Fields

### 11. Auto-Generated Fields (`services/auto_fields.dart`)

**Registry Pattern:**
```dart
static final Map<String, AutoFieldComputer> _registry = {
  'starttime': (answers, question, {isEditMode}) => ...,
  'stoptime': (answers, question, {isEditMode}) => ...,
  'uniqueid': (answers, question, {isEditMode}) => ...,
  'swver': (answers, question, {isEditMode}) => ...,
  'lastmod': (answers, question, {isEditMode}) => ...,
};
```

**Processing:**
- Automatic questions (type='automatic') don't display UI
- Values computed via `AutoFields.compute()`
- Called during navigation and initialization

**Field Handlers:**

1. **starttime:**
   - New record: Current timestamp
   - Edit mode: Preserve existing value

2. **stoptime:**
   - Always current timestamp
   - Updated on every save

3. **uniqueid:**
   - New record: UUID v4
   - Edit mode: Preserve existing value

4. **swver:**
   - Software version from `AppConfig.version`

5. **lastmod:**
   - Updated via `AutoFields.touchLastMod()`
   - Only called when actually saving changes
   - Not updated during UI interactions

---

## ID Generation System

### 12. Subject ID Generation (`services/id_generator.dart`)

**Purpose:** Generate unique identifiers based on configurable rules

**Configuration (JSON):**
```json
{
  "fields": [
    {"source": "tabletnum", "pad": 2},
    {"source": "fixed", "value": "E"}
  ],
  "counter_digits": 3
}
```

**Process:**

1. **Validate required fields:**
   ```dart
   validateIdFields(idConfigJson, answers)
   ```
   - Ensures all source fields have values

2. **Build ID components:**
   - Extract values from answer map
   - Apply padding (zero-fill)
   - Add fixed strings

3. **Generate counter:**
   - Query database for max counter
   - Increment by 1
   - Pad to specified digits

4. **Combine and return:**
   - Example: `"01E001"` (tablet=01, fixed=E, counter=001)

**Database Interaction:**
```sql
SELECT MAX(CAST(SUBSTR(subjid, 3, 3) AS INTEGER))
FROM tablename
WHERE subjid LIKE '01E%'
```

---

## Database Operations

### 13. Database Service (`services/db_service.dart`)

**Initialization:**
```dart
static Future<void> init() async {
  final dbPath = AppConfig.databasePath;
  _database = await openDatabase(dbPath);
}
```

**Save New Interview:**
```dart
static Future<void> saveInterview({
  required String surveyFilename,
  required AnswerMap answers,
})
```

**Process:**
1. Derive table name from filename
2. Build INSERT statement
3. Convert values to database types:
   - `DateTime` → ISO8601 string
   - `List<String>` → comma-separated string
   - `String` → string
   - `null` → NULL
4. Execute insert

**Update Existing Interview:**
```dart
static Future<void> updateInterview({
  required String surveyFilename,
  required AnswerMap answers,
  required String uniqueId,
  Map<String, dynamic>? originalAnswers,
})
```

**Process:**
1. Compare current vs. original answers
2. Build UPDATE statement for changed fields only
3. Use `uniqueid` in WHERE clause
4. Execute update

**Query Records:**
```dart
static Future<List<Map<String, dynamic>>> getRecordsForTable(String tableName)
```

---

## Save Process Flow

### 14. Completing a Survey (`_showDone()`)

**Save Flow:**

1. **Clear skipped answers:**
   ```dart
   _clearSkippedAnswers(questions)
   ```
   - Removes answers for questions not visited
   - Ensures data consistency when skip logic changes

2. **Generate IDs (if configured):**
   - Validate required fields
   - Generate subject/household ID
   - Add to answers map

3. **Check for changes (edit mode):**
   ```dart
   if (!_hasChanges()) {
     // Show "No Changes" dialog
     return;
   }
   ```

4. **Update lastmod:**
   ```dart
   AutoFields.touchLastMod(_answers);
   ```
   - Only called when actually saving
   - Not updated during UI interactions

5. **Save to database:**
   - New record: `DbService.saveInterview()`
   - Update: `DbService.updateInterview()`

6. **Show result dialog:**
   - Success: "All done!" message
   - Failure: Error details with troubleshooting

---

## Record Modification

### 15. Editing Existing Records (`screens/record_selector_screen.dart`)

**Selection Process:**

1. **Display record list:**
   - Query records from table
   - Show primary key fields for identification

2. **Select record:**
   - Pass `existingAnswers` to `SurveyScreen`
   - Set `uniqueId` for update mode

3. **Populate answers:**
   ```dart
   _populateAnswersFromRecord(record, questions)
   ```

**Data Type Conversion:**
- Database → App:
  - Comma-separated string → `List<String>` (checkboxes)
  - ISO8601 string → `DateTime`
  - String values preserved
  - Store deep copy as `_originalAnswers`

4. **Skip primary key questions:**
   - Questions with field names in `primaryKeyFields`
   - Automatically skipped during navigation
   - Values preserved but not editable

5. **Change detection:**
   ```dart
   bool _hasChanges()
   ```
   - Compares `_answers` vs `_originalAnswers`
   - Handles all data types (List, DateTime, String)
   - Prevents unnecessary database writes

---

## Special Features

### 16. Special Response Buttons (Date Fields)

**Implementation:**

**XML Configuration:**
```xml
<question type="date" fieldname="pregnant_date">
  <dont_know>-7</dont_know>
  <refuse>-8</refuse>
</question>
```

**UI Rendering:**
- Buttons appear below date picker
- Highlighted when selected (orange background)
- Date display shows text instead of date
- Clicking button stores special value (e.g., "-7")
- Clicking date picker clears special response

**Initialization:**
- Checks if existing value matches special response
- Doesn't attempt to parse as date
- Displays appropriate state

### 17. Placeholder Expansion

**Purpose:** Display dynamic content in information questions

**Format:**
```xml
<text>Your tablet number is: [[tabletnum]]</text>
```

**Processing:**
```dart
expandPlaceholders(template, answers)
```
- Regex: `\[\[(.+?)\]\]`
- Replaces with value from answers map
- Handles Lists (joins with ', ')
- Empty string if value not found

---

## Configuration System

### 18. App Configuration (`config/app_config.dart`)

**Settings:**

```dart
class AppConfig {
  static const String version = '1.0.0';
  static const String databasePath = 'path/to/database.db';
  static const bool enableErrorDialogs = true;
}
```

**Database Schema Management:**
- Tables pre-created by external tool
- Table name matches survey filename (lowercase, no .xml)
- Column names match question field names
- Primary keys defined in `crfs` table

---

## Question Types Reference

### 19. Supported Question Types

| Type | Field Type | Storage | UI Component |
|------|-----------|---------|--------------|
| `text` | `text`, `text_integer` | String | TextField |
| `radio` | `integer` | String | RadioListTile |
| `checkbox` | `text` | List<String> | CheckboxListTile |
| `combobox` | `integer`, `text` | String | DropdownButton |
| `date` | `date` | String (YYYY-MM-DD) | DatePicker |
| `datetime` | `datetime` | DateTime | DatePicker + TimePicker |
| `information` | `n/a` | N/A | Text display |
| `automatic` | varies | varies | Hidden (auto-calculated) |

---

## Error Handling

### 20. Error Management

**Database Initialization:**
- Catches and logs errors
- Allows survey to load without database
- Warns that data cannot be saved

**Save Failures:**
- Try-catch around database operations
- Captures error message
- Shows detailed error dialog (if enabled)
- Provides troubleshooting steps

**Logic Check Errors:**
- Caught and displayed inline
- Blocks forward navigation
- Clears on navigation

**Validation Errors:**
- TextField validation (red text)
- Numeric range validation
- Displayed immediately on change

---

## Performance Considerations

### 21. Optimization Strategies

**State Management:**
- Minimal rebuilds via `setState()`
- Question state isolated in `QuestionView`
- Shared `AnswerMap` reference (no copying)

**Navigation:**
- History stack (no re-computation)
- Lazy automatic question processing
- Cached loaded questions

**Database:**
- Single connection instance
- Prepared statements (via sqflite)
- Batch operations for updates

**UI:**
- `AnimatedSwitcher` for smooth transitions
- `SingleChildScrollView` for long forms
- `ConstrainedBox` for responsive layout

---

## Data Persistence

### 22. Storage Locations

**SQLite Database:**
- Survey responses
- CRF configuration
- ID counters

**Assets:**
- XML survey definitions
- Branding images
- App configuration

**No cloud sync:**
- Purely offline application
- Data export/sync handled externally

---

## Testing Considerations

### 23. Key Test Scenarios

**Skip Logic:**
- Forward skips (postskip)
- Backward skips (preskip)
- Conditional chains
- Skip to non-existent fields

**Validation:**
- Numeric ranges
- Exception values
- Required vs optional
- Cross-field logic checks

**Data Types:**
- Checkbox multi-select
- Date special responses
- DateTime persistence
- String/integer conversion

**Edit Mode:**
- Change detection
- Primary key preservation
- Lastmod updates
- No-change scenario

---

## Extension Points

### 24. Adding New Features

**New Question Type:**
1. Add to `QuestionType` enum
2. Add case in `parseQuestionType()`
3. Implement `_buildXXX()` in `question_views.dart`
4. Add to `_isAnswered()` switch
5. Add to `_isValid()` if needed

**New Automatic Field:**
1. Add handler to `AutoFields._registry`
2. Implement computation logic
3. Test in edit vs new mode

**New Validation Rule:**
1. Parse from XML in `survey_loader.dart`
2. Add field to `Question` model
3. Implement check in `question_views.dart`

**New Skip Operator:**
1. Add case in `SkipService._evaluateCondition()`
2. Test with various data types

---

## Security Considerations

### 25. Data Security

**Local Storage:**
- SQLite database on device
- No encryption by default
- File system permissions apply

**Input Validation:**
- All text input sanitized via TextField
- Numeric parsing with `tryParse`
- No SQL injection (uses parameterized queries)

**XML Parsing:**
- Trusted sources only (bundled assets)
- XmlDocument handles malformed XML

---

## Debugging

### 26. Debug Outputs

**Key Debug Prints:**

```dart
debugPrint('Primary key fields: $primaryKeyFields')
debugPrint('Loaded checkbox field "$key": $list')
debugPrint('[SkipService] Evaluating skip...')
debugPrint('[LogicService] Evaluating logic for ${fieldName}...')
debugPrint('Generated ID "$generatedId" for field "$idHolderField"')
debugPrint('Clearing ${skippedFields.length} skipped fields...')
```

**Logging Strategy:**
- Service-level logging with prefixes
- Data type information
- Skip/logic evaluation results
- ID generation confirmation

---

## Development Workflow

### 27. Typical Development Tasks

**Adding a New Survey:**
1. Create XML file in `assets/surveys/`
2. Create matching database table
3. Add entry to `crfs` table
4. Test with sample data

**Modifying Question Logic:**
1. Update XML `<skip>` or `<logic_check>`
2. Hot reload app
3. Test navigation flow

**Adding Validation:**
1. Update `<numeric_check>` in XML
2. Test boundary conditions
3. Verify error messages

**Debugging Skip Logic:**
1. Enable debug prints in `SkipService`
2. Step through survey
3. Check console for evaluation results

---

## Architecture Decisions

### 28. Key Design Choices

**Why XML for survey definitions?**
- Human-readable
- Easy to edit without recompiling
- Supports complex nesting
- Standard parsing libraries

**Why shared AnswerMap?**
- Single source of truth
- Simplifies state management
- Easy to serialize to database
- Direct field name mapping

**Why skip-based navigation?**
- Flexible conditional logic
- Supports complex survey flows
- Declarative (defined in XML)
- Easy to test and modify

**Why separate automatic fields?**
- Clear separation of concerns
- Reusable across surveys
- Consistent calculation logic
- Easy to test independently

---

## Common Pitfalls

### 29. Things to Watch Out For

1. **XML Escaping:**
   - Use `&lt;` for `<` in skip conditions
   - Use `&gt;` for `>` in skip conditions
   - Example: `condition = '&lt;&gt;'` for not-equal

2. **Field Name Mismatches:**
   - XML fieldname must match database column
   - Case-sensitive
   - No automatic conversion

3. **Data Type Conversions:**
   - Checkbox always List<String>, even single values
   - Date stored as string in DB
   - DateTime stored as ISO8601 string

4. **Skip Logic Loops:**
   - Avoid circular skip conditions
   - Can cause infinite loops
   - Test navigation thoroughly

5. **Primary Key Changes:**
   - Primary keys cannot be edited
   - Ensure correct fields in `crfs.primary_keys`
   - Changes require new record

6. **Lastmod Timing:**
   - Only updated on actual save
   - Not updated during UI interactions
   - Change detection prevents false updates

---

## Dependencies

### 30. Key Flutter Packages

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.x.x          # SQLite database
  path: ^1.x.x             # File path operations
  xml: ^6.x.x              # XML parsing
  uuid: ^3.x.x             # UUID generation
  path_provider: ^2.x.x    # Platform-specific paths
```

**Usage:**
- `sqflite`: All database operations
- `xml`: Survey XML parsing
- `uuid`: Unique ID generation
- `path_provider`: Database file location

---

## Future Enhancements

### 31. Potential Improvements

**Considered Features:**
1. Data export to CSV/Excel
2. Cloud synchronization
3. Photo capture questions
4. GPS location questions
5. Multi-language support
6. Survey versioning
7. Offline data validation reports
8. Survey branching visualizer

**Architecture Impacts:**
- Would require schema migration system
- Cloud sync needs conflict resolution
- Media questions need storage management
- Multi-language needs i18n framework

---

## Troubleshooting Guide

### 32. Common Issues and Solutions

**Issue: Survey doesn't load**
- Check XML syntax
- Verify file path in assets
- Check console for parsing errors

**Issue: Skip logic not working**
- Verify field names match exactly
- Check operator syntax
- Enable debug logging
- Test with debugger

**Issue: Data not saving**
- Check database path
- Verify table exists
- Check column names match field names
- Look for error dialog

**Issue: Validation not triggering**
- Check `numeric_check` syntax
- Verify field type is `text_integer`
- Test with boundary values

**Issue: IDs not generating**
- Check `id_config` JSON syntax
- Verify required fields have values
- Check database for counter table

---

## Summary

GiSTX is a well-structured Flutter application that separates concerns effectively:

- **Models** define data structures
- **Services** handle business logic
- **Screens** manage navigation and overall flow
- **Widgets** render UI components
- **XML** defines survey structure declaratively
- **SQLite** provides persistent storage

The architecture is extensible, testable, and maintainable, with clear separation between survey definition (XML), business logic (services), and UI (widgets/screens).
