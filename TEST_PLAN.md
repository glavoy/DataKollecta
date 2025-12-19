# GiSTX Application Test Plan

## Overview
This test plan provides comprehensive testing for the GiSTX survey application, covering general functionality and specific validation for the enrollee.xml survey.

**Test Date:** _____________
**Tester Name:** _____________
**App Version:** _____________
**Survey Version:** _____________

---

## 1. APPLICATION SETUP & CONFIGURATION

### TC-001: Initial Application Launch
**Objective:** Verify application starts correctly and handles first-time setup
**Prerequisites:** Fresh installation or cleared app data
**Steps:**
1. Launch GiSTX application
2. Observe splash screen
3. Verify navigation to main screen

**Expected Result:**
- Application launches without crashes
- Main screen displays with survey selection option
- No surveys initially available (shows appropriate message)

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-002: FTP Settings Configuration
**Objective:** Configure and validate FTP connection settings
**Prerequisites:** Valid FTP credentials available
**Steps:**
1. Navigate to Settings screen (gear icon)
2. Enter FTP server details:
   - Server address
   - Port
   - Username
   - Password
3. Save settings
4. Navigate back to main screen

**Expected Result:**
- Settings saved successfully
- No error messages displayed
- Settings persist after app restart

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-003: Survey Download
**Objective:** Download survey from FTP server
**Prerequisites:** Valid FTP settings configured (TC-002)
**Steps:**
1. Navigate to Sync screen (cloud icon)
2. Click "Check for Updates" button
3. Wait for survey list to load
4. Select a survey from the list
5. Click Download
6. Wait for download to complete
7. Navigate back to main screen

**Expected Result:**
- Survey list displays available surveys
- Download progress shown
- Success message displayed
- Survey appears in main screen survey selector
- If only one survey: **Auto-selected automatically**

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-004: Survey Auto-Selection
**Objective:** Verify single survey auto-selection feature
**Prerequisites:** Exactly one survey downloaded
**Steps:**
1. Ensure only one survey is available
2. Navigate to Sync screen
3. Download the survey (if not already downloaded)
4. Return to main screen

**Expected Result:**
- Survey is automatically selected
- "CURRENT PROJECT" card shows the survey name
- No manual selection required

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-005: Multiple Survey Selection
**Objective:** Test manual survey selection with multiple surveys
**Prerequisites:** 2+ surveys downloaded
**Steps:**
1. Download multiple surveys
2. Click on "CURRENT PROJECT" card
3. Select different survey from list
4. Verify selection persists

**Expected Result:**
- Survey selection dialog displays all available surveys
- Selected survey is highlighted
- Selection persists across app restarts

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 2. NEW SURVEY ENTRY - GENERAL FUNCTIONALITY

### TC-006: Questionnaire Selection
**Objective:** Select and start a new questionnaire
**Prerequisites:** Survey downloaded and selected
**Steps:**
1. Click "New Survey" button on main screen
2. Select a questionnaire from the list
3. Verify navigation to survey screen

**Expected Result:**
- List of available questionnaires displayed
- Selection navigates to first question
- Question displays correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-007: Basic Question Navigation - Forward
**Objective:** Test forward navigation through survey
**Prerequisites:** Survey started (TC-006)
**Steps:**
1. Answer first question
2. Click "Next" button
3. Answer next question
4. Repeat for 5-10 questions

**Expected Result:**
- Next button enabled after answering
- Navigation moves to next question
- Progress indicator updates
- Previous answers retained

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-008: Basic Question Navigation - Backward
**Objective:** Test backward navigation through survey
**Prerequisites:** At least 3 questions answered (TC-007)
**Steps:**
1. Click "Back" button
2. Verify previous question displayed
3. Verify previous answer shown
4. Modify answer
5. Click "Next" to return

**Expected Result:**
- Back button navigates to previous question
- Previous answer displayed correctly
- Answer can be modified
- Modified answer persists

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-009: Question Types - Text Input
**Objective:** Test text input field validation
**Prerequisites:** Survey started
**Steps:**
1. Navigate to a text question
2. Enter valid text (within character limit)
3. Try entering text exceeding limit
4. Leave field empty and try to proceed
5. Enter special characters

**Expected Result:**
- Text input accepts valid input
- Character limit enforced
- Appropriate validation messages shown
- Special characters handled correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-010: Question Types - Radio Buttons
**Objective:** Test single-choice radio button selection
**Prerequisites:** Survey started
**Steps:**
1. Navigate to a radio button question
2. Select an option
3. Select a different option
4. Verify only one option selected

**Expected Result:**
- Only one option can be selected
- Previous selection deselected automatically
- Selection visible and clear

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-011: Question Types - Date Picker
**Objective:** Test date input functionality
**Prerequisites:** Survey started
**Steps:**
1. Navigate to a date question
2. Click date picker
3. Select a valid date
4. Verify date range validation (if configured)
5. Try selecting date outside allowed range

**Expected Result:**
- Date picker opens correctly
- Selected date displays in proper format
- Date range validation works
- Invalid dates rejected with message

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-012: Automatic Fields - Timestamp
**Objective:** Verify automatic timestamp fields populate correctly
**Prerequisites:** Survey started
**Steps:**
1. Start new survey
2. Note start time
3. Complete survey
4. Check database/export for starttime and stoptime

**Expected Result:**
- starttime captured at survey start
- stoptime captured at survey completion
- Timestamps in ISO 8601 format
- Times reasonable and accurate

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-013: Automatic Fields - Unique ID
**Objective:** Verify unique ID generation
**Prerequisites:** Complete 2+ surveys
**Steps:**
1. Complete first survey, note uniqueid
2. Complete second survey, note uniqueid
3. Verify IDs are different
4. Check ID format (UUID v4)

**Expected Result:**
- Each survey gets unique ID
- IDs are valid UUIDs
- No duplicates generated

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-014: Primary Key Generation - New Survey
**Objective:** Test subjid/hhid auto-generation for new records
**Prerequisites:** Survey with ID config started
**Steps:**
1. Start new survey
2. Enter component fields (e.g., district, intnum)
3. Navigate to subjid question
4. Verify ID auto-generated
5. Note the generated ID format

**Expected Result:**
- ID generated automatically
- Format matches idConfig specification
- Increment starts at 001
- ID follows pattern: [prefix][fields][increment]

**Result:** ☐ PASS ☐ FAIL
**Actual ID Generated:** _____________
**Notes:** _____________________________________________

---

### TC-015: Skip Logic - Basic Skip
**Objective:** Test simple skip condition
**Prerequisites:** Survey with skip logic
**Steps:**
1. Answer question that triggers skip
2. Verify skipped questions not shown
3. Go back and change answer to not skip
4. Verify skipped questions now shown

**Expected Result:**
- Skip logic triggers correctly
- Skipped questions hidden
- Changing answer re-evaluates skip
- No crashes or navigation errors

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-016: Survey Completion and Save
**Objective:** Complete survey and verify data saved
**Prerequisites:** Survey nearly complete
**Steps:**
1. Answer all required questions
2. Navigate to end
3. Click "Finish" button
4. Verify success message
5. Return to main screen
6. Check "Modify Existing Survey" to verify record saved

**Expected Result:**
- Finish button appears at end
- Success message displayed
- Survey saved to database
- Record appears in modify list

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 3. MODIFY EXISTING SURVEY - GENERAL FUNCTIONALITY

### TC-017: Record Selection for Editing
**Objective:** Select and open existing record
**Prerequisites:** At least one completed survey (TC-016)
**Steps:**
1. Click "Modify Existing Survey" button
2. View list of existing records
3. Select a record
4. Verify survey opens with existing data

**Expected Result:**
- List shows all completed surveys
- Record identifiable (by ID or date)
- Survey opens in edit mode
- All previous answers displayed

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-018: Primary Key Preservation - No Changes
**Objective:** Verify subjid preserved when no component fields changed
**Prerequisites:** Completed survey with subjid (TC-016)
**Steps:**
1. Open existing survey for editing (TC-017)
2. Note the current subjid value
3. Navigate through survey WITHOUT changing component fields
4. Make minor edit to unrelated field
5. Save survey
6. Reopen survey
7. Verify subjid unchanged

**Expected Result:**
- Original subjid preserved
- Increment number NOT changed
- No new ID generated
- Debug log shows: "Preserving existing ID"

**Result:** ☐ PASS ☐ FAIL
**Original subjid:** _____________
**Final subjid:** _____________
**Notes:** _____________________________________________

---

### TC-019: Primary Key Regeneration - Component Changed
**Objective:** Verify subjid regenerated when component field changes
**Prerequisites:** Completed survey with subjid
**Steps:**
1. Open existing survey for editing
2. Note the current subjid (e.g., "18122001")
3. Change a component field (e.g., district from 181 to 124)
4. Navigate to/past subjid field
5. Note new subjid
6. Verify base changed, new increment assigned

**Expected Result:**
- New subjid generated
- Base reflects new component values (e.g., "12422xxx")
- New increment number assigned
- Debug log shows: "Component fields changed - regenerating ID"

**Result:** ☐ PASS ☐ FAIL
**Original subjid:** _____________
**New subjid:** _____________
**Notes:** _____________________________________________

---

### TC-020: Timestamp Preservation in Edit Mode
**Objective:** Verify starttime preserved, stoptime/lastmod updated
**Prerequisites:** Completed survey
**Steps:**
1. Complete survey, note starttime and stoptime
2. Open for editing
3. Make a change
4. Save survey
5. Check database/export for timestamps

**Expected Result:**
- starttime preserved (unchanged)
- stoptime updated to new completion time
- lastmod updated to edit time
- uniqueid preserved (unchanged)

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-021: View-Only (No Changes)
**Objective:** Open survey, view data, exit without changes
**Prerequisites:** Completed survey
**Steps:**
1. Open existing survey
2. Navigate through all questions
3. Do not make any changes
4. Exit survey
5. Reopen survey
6. Verify no modifications to any fields

**Expected Result:**
- Can navigate through survey
- All data displays correctly
- No automatic changes made
- All IDs and timestamps preserved

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 4. LOGIC CHECKS - GENERAL FUNCTIONALITY

### TC-022: Logic Check - Single Condition
**Objective:** Test simple logic check with one condition
**Prerequisites:** Survey with logic checks
**Steps:**
1. Navigate to question with logic check
2. Enter value that violates check
3. Try to proceed
4. Correct the value
5. Verify can proceed

**Expected Result:**
- Error message displayed for violation
- Cannot proceed while error present
- Error message is clear and helpful
- Correcting value clears error

**Result:** ☐ PASS ☐ FAIL
**Error Message:** _____________
**Notes:** _____________________________________________

---

### TC-023: Logic Check - Multiple Conditions (Sequential)
**Objective:** Test multiple logic checks on same field
**Prerequisites:** Survey with multiple logic checks per question
**Steps:**
1. Navigate to question with 2+ logic checks
2. Violate first check
3. Note error message
4. Fix first violation but violate second check
5. Note second error message
6. Fix both violations

**Expected Result:**
- First violation shows first error message
- Only first error shown (subsequent checks skipped)
- Fixing first allows second check to run
- Second violation shows second error message
- All checks pass when corrected

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-024: Logic Check - Field Comparison
**Objective:** Test logic check comparing two fields
**Prerequisites:** Survey with field comparison logic
**Steps:**
1. Navigate to paired fields (e.g., age vs age_calculated)
2. Enter mismatched values
3. Observe error
4. Match the values
5. Verify error clears

**Expected Result:**
- Mismatched values trigger error
- Error message explains mismatch
- Matching values clears error
- Logic evaluates both fields correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-025: Logic Check - Date Comparison
**Objective:** Test date comparison logic checks
**Prerequisites:** Survey with date logic checks
**Steps:**
1. Navigate to date field with date comparison logic
2. Enter date violating logic (e.g., dose2 before dose1)
3. Observe error
4. Correct date to valid value
5. Verify error clears

**Expected Result:**
- Invalid date comparison triggers error
- Error message clear (e.g., "Date of dose 2 cannot be before date of dose 1")
- Valid date clears error
- Date parsing works correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-026: Logic Check - Complex Boolean Expression
**Objective:** Test complex logic with AND/OR operators
**Prerequisites:** Survey with complex logic expressions
**Steps:**
1. Navigate to question with complex logic (nested AND/OR)
2. Test various combinations of values
3. Verify logic evaluates correctly
4. Test edge cases

**Expected Result:**
- Complex expressions evaluate correctly
- Nested parentheses handled properly
- AND/OR precedence correct
- No parsing errors

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-027: Logic Check - Date Literal Comparison
**Objective:** Test date field vs date literal (e.g., starttime <= '2026-01-31')
**Prerequisites:** Survey with date literal comparisons
**Steps:**
1. Navigate to question with date literal logic
2. Test dates before literal
3. Test dates after literal
4. Test exact date match
5. Verify correct evaluation

**Expected Result:**
- Date literals parsed correctly
- Comparison operators work (<=, >=, <, >)
- Datetime vs date-only comparison works
- Logic evaluates accurately

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 5. NUMERIC VALIDATION

### TC-028: Numeric Range Validation
**Objective:** Test min/max value validation
**Prerequisites:** Survey with numeric_check elements
**Steps:**
1. Navigate to numeric field with range
2. Enter value below minimum
3. Enter value above maximum
4. Enter value within range
5. Test boundary values

**Expected Result:**
- Below minimum rejected with error
- Above maximum rejected with error
- Within range accepted
- Boundary values handled correctly
- Error messages display configured message

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-029: Character Limit Validation
**Objective:** Test maxCharacters enforcement
**Prerequisites:** Survey with character limits
**Steps:**
1. Navigate to text field with maxCharacters
2. Enter text at limit
3. Try entering text beyond limit
4. Verify truncation or prevention

**Expected Result:**
- Character limit enforced
- Cannot exceed specified length
- Limit indicator shown (if applicable)

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 6. SKIP LOGIC - ADVANCED SCENARIOS

### TC-030: Pre-skip Logic
**Objective:** Test question skipped before display (preskip)
**Prerequisites:** Survey with preskip conditions
**Steps:**
1. Answer question that triggers preskip
2. Verify target question skipped
3. Go back and change answer
4. Verify question now shown

**Expected Result:**
- Question skipped based on previous answer
- Skip happens before question display
- Changing condition shows question
- Navigation handles skips smoothly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-031: Post-skip Logic
**Objective:** Test skip after answering (postskip)
**Prerequisites:** Survey with postskip conditions
**Steps:**
1. Answer question with postskip
2. Verify navigation jumps to target
3. Go back and change answer
4. Verify different navigation path

**Expected Result:**
- Skip occurs after answering
- Navigation jumps to correct target
- Different answers create different paths
- No questions lost or duplicated

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-032: Multiple Skip Conditions
**Objective:** Test question with multiple skip rules (first match wins)
**Prerequisites:** Survey with multiple skip elements
**Steps:**
1. Answer question that has multiple skip options
2. Set answer to trigger first skip
3. Verify first skip target reached
4. Go back, change to trigger second skip
5. Verify second skip target reached

**Expected Result:**
- First matching skip executes
- Subsequent skips not evaluated
- Each skip goes to correct target
- Order of skips matters (sequential)

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-033: Nested Skip Logic
**Objective:** Test skip leading to another skip
**Prerequisites:** Survey with chained skips
**Steps:**
1. Answer question that skips to another skipped question
2. Verify final destination correct
3. Trace skip chain
4. Go back through chain

**Expected Result:**
- Multiple skips chain correctly
- Final destination reached
- Back navigation works through chain
- No infinite loops

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 7. DATA EXPORT & SYNC

### TC-034: Data Export Generation
**Objective:** Verify survey data can be exported
**Prerequisites:** Completed surveys in database
**Steps:**
1. Navigate to sync screen
2. Click "Generate Exports" or similar
3. Verify export files created
4. Check export file format
5. Verify data completeness

**Expected Result:**
- Export files generated successfully
- Files in correct format (ZIP)
- All survey data included
- Export stored in outbox folder

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-035: Data Upload to FTP
**Objective:** Upload survey data to FTP server
**Prerequisites:** Export generated (TC-034), FTP configured
**Steps:**
1. Navigate to sync screen
2. Click "Upload Data" or similar
3. Wait for upload to complete
4. Verify success message
5. Check FTP server for file

**Expected Result:**
- Upload completes successfully
- Success message displayed
- File appears on FTP server
- Upload folder shows completed uploads

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 8. ERROR HANDLING & EDGE CASES

### TC-036: Network Error Handling
**Objective:** Test behavior when network unavailable
**Prerequisites:** Ability to disable network
**Steps:**
1. Disable network connection
2. Try downloading survey
3. Try uploading data
4. Verify error messages
5. Re-enable network and retry

**Expected Result:**
- Clear error messages displayed
- App doesn't crash
- Operations can be retried
- Partial downloads handled gracefully

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-037: Invalid FTP Credentials
**Objective:** Test behavior with wrong credentials
**Prerequisites:** None
**Steps:**
1. Enter incorrect FTP credentials
2. Try checking for updates
3. Observe error message
4. Correct credentials
5. Retry operation

**Expected Result:**
- Authentication error displayed
- Clear message about credentials
- No crash
- Retry works with correct credentials

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-038: Application Restart Mid-Survey
**Objective:** Test survey recovery after app restart
**Prerequisites:** Survey in progress
**Steps:**
1. Start new survey
2. Answer several questions
3. Force close application
4. Relaunch application
5. Check if survey recoverable

**Expected Result:**
- App launches normally
- In-progress survey either auto-recovered or discarded appropriately
- No data corruption
- Can start fresh survey

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-039: Date Picker Edge Cases
**Objective:** Test date picker boundary conditions
**Prerequisites:** Survey with date fields
**Steps:**
1. Try selecting today's date
2. Try selecting maximum allowed date
3. Try selecting minimum allowed date
4. Test February 29 on leap year
5. Test February 29 on non-leap year

**Expected Result:**
- Today's date selectable
- Boundary dates work correctly
- Leap year handled correctly
- Invalid dates prevented

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-040: Special Characters in Text Fields
**Objective:** Test handling of special characters
**Prerequisites:** Survey with text fields
**Steps:**
1. Enter text with apostrophes (')
2. Enter text with quotes (")
3. Enter text with Unicode characters
4. Save and reload
5. Verify data integrity

**Expected Result:**
- Special characters accepted
- Data saved correctly (no SQL injection)
- Unicode characters display properly
- Data retrieved without corruption

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 9. ENROLLEE.XML SPECIFIC TESTS

### TC-041: Age Calculation - Years
**Objective:** Test automatic age calculation from DOB
**Prerequisites:** Enrollee survey started
**Steps:**
1. Navigate to DOB question
2. Enter date of birth within 2-year limit (e.g., 18 months ago)
3. Navigate to age_calculated field
4. Verify calculated age in years correct

**Expected Result:**
- Age calculated automatically
- Value matches manual calculation (should be 1 year for 18-month-old)
- Updates if DOB changed

**Result:** ☐ PASS ☐ FAIL
**DOB Entered:** _____________
**Calculated Age:** _____________
**Notes:** _____________________________________________

---

### TC-042: Age Calculation - Months
**Objective:** Test automatic age calculation in months
**Prerequisites:** Enrollee survey started
**Steps:**
1. Navigate to DOB question
2. Enter date of birth (e.g., 15 months ago)
3. Navigate to agemonths_calculated field
4. Verify calculated age in months correct

**Expected Result:**
- Age in months calculated automatically
- Value accurate
- Updates if DOB changed

**Result:** ☐ PASS ☐ FAIL
**DOB Entered:** _____________
**Calculated Months:** _____________
**Notes:** _____________________________________________

---

### TC-043: Age Validation Logic Check
**Objective:** Test age vs age_calculated comparison
**Prerequisites:** Enrollee survey
**Steps:**
1. Enter DOB resulting in age 1 year (within 2-year DOB limit)
2. Navigate to age question
3. Enter age = 1 (matching calculated)
4. Verify no error
5. Change age to 3 (mismatch - manually entered)
6. Verify error displayed

**Expected Result:**
- Matching ages: no error
- Mismatched ages: error "The age entered does not match the date of birth!"
- Logic check evaluates correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-044: Age in Months Validation
**Objective:** Test agemonths vs agemonths_calculated comparison
**Prerequisites:** Enrollee survey
**Steps:**
1. Enter DOB resulting in 6 months (within 2-year DOB limit)
2. Enter age = 0 years (to keep agemonths question visible)
3. Navigate to agemonths question
4. Enter agemonths = 6 (matching calculated)
5. Verify no error
6. Change agemonths to 3 (mismatch)
7. Verify error displayed

**Expected Result:**
- Matching agemonths: no error
- Mismatched agemonths: error "Age in months does not match the age in months from the DOB!"
- Validation accurate
- Note: agemonths question only shown when age = 0

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-045: Age Eligibility - Complex Date-Based Logic
**Objective:** Test complex age eligibility logic with date comparison
**Prerequisites:** Enrollee survey, system date known
**Steps:**
1. Test scenario where starttime <= '2026-01-31':
   - Set age_eligible = 1, agemonths_calculated < 9
   - Verify logic check triggers error
   - Set agemonths_calculated = 15 (9-21 range), age_eligible = 1
   - Verify logic check triggers error
   - Set agemonths_calculated = 15, age_eligible = 0
   - Verify NO error (valid)
2. Test edge cases at boundaries

**Expected Result:**
- Logic evaluates complex expression correctly
- Date literal comparison works
- AND/OR operators work correctly
- Nested parentheses parsed properly
- Error: "Age eligibility selection does not match the age criteria!"

**Result:** ☐ PASS ☐ FAIL
**System Date:** _____________
**Notes:** _____________________________________________

---

### TC-046: Subject ID Generation - Enrollee
**Objective:** Test subjid generation with district + intnum + increment
**Prerequisites:** Fresh enrollee survey
**Test Data:**
- district = 181 (BUSIA)
- intnum = 22

**Steps:**
1. Start new enrollee survey
2. Enter starttime (automatic)
3. Enter intnum = 22
4. Select district = 181
5. Navigate to subjid field
6. Note generated subjid

**Expected Result:**
- subjid format: [district:3][intnum:2][increment:3]
- Example: "18122001"
- Increment starts at 001 for first record
- Subsequent records: 18122002, 18122003, etc.

**Result:** ☐ PASS ☐ FAIL
**Generated subjid:** _____________
**Notes:** _____________________________________________

---

### TC-047: Subject ID Preservation - Enrollee Edit
**Objective:** Verify subjid preserved when editing without changing components
**Prerequisites:** Completed enrollee survey with subjid="18122001"
**Steps:**
1. Open survey for editing
2. Note current subjid
3. Change non-component field (e.g., participantsname)
4. Navigate through survey
5. Save
6. Reopen and check subjid

**Expected Result:**
- subjid remains "18122001"
- Increment NOT changed to "002"
- Debug shows: "Preserving existing ID"

**Result:** ☐ PASS ☐ FAIL
**Original subjid:** _____________
**Final subjid:** _____________
**Notes:** _____________________________________________

---

### TC-048: Subject ID Regeneration - District Changed
**Objective:** Verify subjid regenerated when district changes
**Prerequisites:** Completed enrollee survey with subjid="18122001"
**Steps:**
1. Open survey for editing
2. Change district from 181 to 124 (MAYUGE)
3. Navigate to/past subjid
4. Note new subjid
5. Save survey

**Expected Result:**
- New subjid generated
- Base changed from "18122" to "12422"
- New increment assigned (e.g., "12422001")
- Debug shows: "Component fields changed - regenerating ID"

**Result:** ☐ PASS ☐ FAIL
**Original subjid:** _____________
**New subjid:** _____________
**Notes:** _____________________________________________

---

### TC-049: Vaccine Dose Date Validation - Multiple Logic Checks
**Objective:** Test multiple date logic checks on vx_dose2_date
**Prerequisites:** Enrollee survey with DOB and vx_dose1_date entered
**Test Data:**
- dob = 2023-06-15
- vx_dose1_date = 2024-01-10

**Steps:**
1. Navigate to vx_dose2_date question
2. Enter date = 2023-05-01 (before DOB)
3. Verify error: "Date of vaccination cannot be before date of birth!"
4. Change to 2024-01-05 (before dose 1)
5. Verify error: "Date of dose 2 cannot be before date of dose 1"
6. Change to 2024-02-15 (valid)
7. Verify no error

**Expected Result:**
- First logic check catches DOB violation
- Second logic check only shown after fixing first
- Valid date passes both checks
- Error messages specific and helpful

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-050: Vaccine Card Logic Check
**Objective:** Test vaccine card consistency validation
**Prerequisites:** Enrollee survey
**Steps:**
1. Set vx_card = 0 (No card)
2. Navigate to vx_doses_received_ver
3. Select "Vaccine card" (value = 2)
4. Verify error: "You previously indicated that the guardian does not have a vaccine card!"
5. Change to "Guardian report"
6. Verify error clears

**Expected Result:**
- Logic check catches inconsistency
- Error message references previous answer
- Changing to consistent value clears error

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-051: Skip Logic - Vaccine Not Received
**Objective:** Test skip when vx_any = 0 (not received)
**Prerequisites:** Enrollee survey
**Steps:**
1. Enter DOB (within 2-year limit, e.g., 18 months ago)
2. Enter corresponding age (e.g., 1 year)
3. Set vx_any = 0 (No)
4. Verify vx_any_no question appears
5. Answer vx_any_no
6. Verify skip to next section (skips dose questions)

**Expected Result:**
- vx_any = 0 shows reason question
- After reason, skips to next appropriate question
- Dose questions skipped entirely

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-052: CSV-Based Response Loading - Villages
**Objective:** Test dynamic response loading from villages.csv
**Prerequisites:** villages.csv file present in survey folder
**Steps:**
1. Navigate to district question
2. Select district = 181 (BUSIA)
3. Navigate to subcounty question
4. Verify only BUSIA subcounties shown
5. Select subcounty
6. Navigate to parish question
7. Verify filtered parishes shown
8. Select parish
9. Navigate to village question
10. Verify filtered villages shown

**Expected Result:**
- Subcounty list filtered by district
- Parish list filtered by district AND subcounty
- Village list filtered by all three
- Correct cascading filters applied
- No villages from wrong district shown

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-053: Unique ID Validation
**Objective:** Test unique UID field prevents duplicates
**Prerequisites:** One enrollee survey completed
**Steps:**
1. Complete first survey with UID = "12345"
2. Start new survey
3. Navigate to UID question
4. Enter same UID = "12345"
5. Try to proceed
6. Verify error: "This UID as already been used!"
7. Change to unique value
8. Verify accepted

**Expected Result:**
- Duplicate UID rejected
- Error message clear
- Unique UID accepted
- Validation checks database

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-054: Barcode Re-entry Validation
**Objective:** Test barcode confirmation fields match
**Prerequisites:** Enrollee survey
**Steps:**
1. Enter fpbarcode1_r21 = "123456789012"
2. Navigate to fpbarcode2_r21
3. Enter different value = "999999999999"
4. Try to proceed
5. Verify error: "This does not match your previous entry of the barcode!"
6. Change to matching value
7. Verify accepted

**Expected Result:**
- Mismatched barcodes rejected
- Error message specific
- Matching barcodes accepted
- Case-sensitive comparison

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-055: Conditional Survey Flow - Consent
**Objective:** Test skip to end when consent not given
**Prerequisites:** Enrollee survey
**Steps:**
1. Progress through survey
2. Navigate to consent question
3. Select "No" (value = 0)
4. Verify skip directly to comments (near end)
5. Verify laboratory questions skipped
6. Go back, change to "Yes"
7. Verify laboratory questions now shown

**Expected Result:**
- No consent skips medical questions
- Skip goes to comments section
- Yes consent shows all questions
- Postskip logic works correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-056: Conditional Questions - Dose Count
**Objective:** Test dose questions shown based on vx_doses_received
**Prerequisites:** Enrollee survey
**Steps:**
1. Set vx_doses_received = 2
2. Verify dose 1 and dose 2 questions shown
3. Verify dose 3 and dose 4 questions skipped
4. Go back, change to vx_doses_received = 4
5. Verify all dose questions shown

**Expected Result:**
- Only relevant dose questions shown
- Preskip logic evaluates vx_doses_received
- Dynamic survey path based on answer
- No errors navigating

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-057: Enrollment Eligibility - Complete Flow
**Objective:** Test complete enrollment eligibility flow
**Prerequisites:** Fresh enrollee survey
**Steps:**
1. Enter eligible participant data:
   - Age: 1 year, 3 months (15 months)
   - Age eligible: Yes
   - Malaria test eligible: Yes
   - Consent eligible: Yes
2. Verify survey continues to main questions
3. Restart with ineligible data:
   - Age: 0 years, 6 months
   - Age eligible: No
4. Verify skip to exclusion comments

**Expected Result:**
- Eligible participants continue to full survey
- Ineligible participants skip to end
- Eligibility criteria properly evaluated
- Clear exclusion path

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 10. PERFORMANCE & USABILITY

### TC-058: Survey Loading Performance
**Objective:** Measure survey loading time
**Prerequisites:** Large survey available
**Steps:**
1. Select questionnaire
2. Time from selection to first question display
3. Note any delays

**Expected Result:**
- Survey loads in < 3 seconds
- No noticeable lag
- Smooth transition

**Result:** ☐ PASS ☐ FAIL
**Load Time:** _______ seconds
**Notes:** _____________________________________________

---

### TC-059: Navigation Performance
**Objective:** Test navigation responsiveness
**Prerequisites:** Survey in progress
**Steps:**
1. Click Next button 10 times rapidly
2. Click Back button 10 times rapidly
3. Note any delays or freezes

**Expected Result:**
- Navigation responds immediately
- No UI freezing
- Smooth animations
- No duplicate navigation

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-060: Large Dataset Handling
**Objective:** Test with many completed surveys
**Prerequisites:** 20+ completed surveys
**Steps:**
1. Navigate to "Modify Existing Survey"
2. Observe list loading time
3. Scroll through list
4. Select a record
5. Verify performance acceptable

**Expected Result:**
- List loads in < 5 seconds
- Scrolling smooth
- Record selection quick
- No memory issues

**Result:** ☐ PASS ☐ FAIL
**Record Count:** _____________
**Notes:** _____________________________________________

---

### TC-061: UI Responsiveness
**Objective:** General UI/UX evaluation
**Prerequisites:** Survey in use
**Steps:**
1. Test all buttons respond to clicks
2. Verify error messages readable
3. Check text size appropriate
4. Verify colors/contrast acceptable
5. Test with different screen sizes (if applicable)

**Expected Result:**
- All UI elements functional
- Messages clear and visible
- Professional appearance
- Accessible design

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## 11. DATA INTEGRITY

### TC-062: Database Persistence
**Objective:** Verify data persists across app restarts
**Prerequisites:** Completed survey
**Steps:**
1. Complete survey
2. Note all field values
3. Close application completely
4. Relaunch application
5. Open survey for editing
6. Verify all values unchanged

**Expected Result:**
- All data persists
- No data loss
- Values exactly as entered
- Timestamps preserved

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-063: Concurrent Survey Handling
**Objective:** Test multiple surveys in same session
**Prerequisites:** Survey selected
**Steps:**
1. Start survey A
2. Answer 5 questions
3. Exit to main screen (don't finish)
4. Start survey B
5. Complete survey B
6. Verify survey A data not corrupted

**Expected Result:**
- Each survey independent
- No data mixing
- Survey A can be resumed or discarded
- Survey B saves correctly

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

### TC-064: Special Value Handling
**Objective:** Test handling of special values (-9, null, empty)
**Prerequisites:** Survey started
**Steps:**
1. Skip optional questions (leave empty)
2. Enter fallback value -9 where used
3. Complete survey
4. Reopen and verify values

**Expected Result:**
- Empty values stored as null or empty string
- -9 values preserved
- No confusion between null and -9
- Export handles special values

**Result:** ☐ PASS ☐ FAIL
**Notes:** _____________________________________________

---

## TEST EXECUTION SUMMARY

**Total Test Cases:** 64
**Passed:** _______
**Failed:** _______
**Blocked:** _______
**Not Executed:** _______

**Pass Rate:** _______%

### Critical Issues Found
1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

### Recommendations
1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

### Sign-Off

**Tester Signature:** ____________________
**Date:** ____________________
**Approved By:** ____________________
**Date:** ____________________

---

## APPENDIX A: Test Data Reference

### Sample Enrollee Test Data Set 1 (Eligible)
```
district: 181 (BUSIA)
intnum: 22
dob: 2023-06-15
age: 1
agemonths: 3
age_eligible: 1 (Yes)
mal_test_eligible: 1 (Yes)
consent_eligible: 1 (Yes)
participantsname: "Test Subject 001"
gender: 1 (Male)
vx_any: 1 (Yes)
vx_doses_received: 2
```

### Sample Enrollee Test Data Set 2 (Ineligible - Age)
```
district: 181 (BUSIA)
intnum: 23
dob: 2024-06-15
age: 0
agemonths: 6
age_eligible: 0 (No - too young)
```

### Sample Enrollee Test Data Set 3 (Edit Test)
```
Original:
  subjid: 18122001
  district: 181
  intnum: 22
  participantsname: "Original Name"

Scenario A (No component change):
  subjid: 18122001 (preserved)
  district: 181
  intnum: 22
  participantsname: "Modified Name"

Scenario B (Component changed):
  subjid: 12422001 (regenerated)
  district: 124 (changed)
  intnum: 22
  participantsname: "Modified Name"
```

---

## APPENDIX B: Quick Reference - Expected Behaviors

### Primary Key (subjid) Behavior
| Scenario | Component Fields | Expected subjid Behavior |
|----------|-----------------|-------------------------|
| New survey | district=181, intnum=22 | Generate: 18122001 |
| Edit - no changes | No change to 181, 22 | **Preserve**: 18122001 |
| Edit - minor changes | No change to 181, 22 | **Preserve**: 18122001 |
| Edit - component changed | district changed to 124 | **Regenerate**: 12422001 |
| Multiple new surveys | Same 181, 22 | Increment: 18122002, 18122003... |

### Logic Check Evaluation Order
| Check Type | When Evaluated | Stop on Fail |
|-----------|---------------|--------------|
| Multiple logic checks | Sequential order | Yes - first error only |
| Complex AND/OR | Full expression | Yes - if any violation |
| Date comparisons | Real-time | Yes |
| Field comparisons | When both fields have values | Yes |

### Skip Logic Priority
| Skip Type | Evaluation Time | Override Behavior |
|-----------|----------------|------------------|
| Preskip | Before question display | First match wins |
| Postskip | After answer submitted | First match wins |
| Multiple skips on same question | Sequential order | First match wins |

---

**END OF TEST PLAN**
