## [0.0.9] - not released yet
- the _isSaving flag is now reset after the try/catch block completes, regardless of success or failure. This ensures users can retry saving if an error occurs.

## [0.0.8] - 2026-01-02

### Fixed
- **Data persistence in skipped questions:** Implemented real-time clearing of answers when skip logic bypasses previously answered questions
  - Added `_clearAnswersInRange()` method to clear data for questions in range being jumped over during forward navigation
  - Modified `_next()` method to detect skip logic jumps and automatically clear affected fields
  - Prevents incorrect data from appearing on information screens and being saved to database
  - Complements existing save-time cleanup with proactive navigation-time clearing



### [0.0.7] - 2025-12-30
* Added 'startdate' automatic field type
* Added `date_offset` calculation type to calculate date-diff between two dates
* Added optional regex formatting (input masking) for text fileds
* Changed the exit prompt when modifying a survey to: "Are you sure you want to cancel. All edits/modifications will be lost!"
* Implemented cascading clear logic for dependent fields so that changing a 'parent' field clears 'child' fields
* Implemented a "Review Changes" system for survey modifications that generates a logical summary replacing technical IDs with human-readable labels and expanding placeholders like `[[participantsname]]`.
* Integrated numeric-aware logic into the summary system to highlight genuine data changes while ignoring benign differences like numeric padding.
* Added three options to the review dialog: Save Changes, Back to Edit, or Discard & Exit, with a secondary confirmation for the discard option.