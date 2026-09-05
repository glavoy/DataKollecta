## To Do

### Bug
- when viewing/modifying a survey, when calculating an age (months or years) - it forces the user to enter the age form TODAY's date - when viewing/modifying n the same data it will work fine - but if it is far in the future, then teh age will be incorrect. Need to use starttime/startdate when calculating age when viewing/modifying - need to update DataKolecta as well


- questions that are skipped due to skip pattern change (xxx -> NULL) do not appear in the list of changes at the end
- in formchanges table, add the interviewer id to know who made the change
- add other question types
    - upload image
    - gps
    - voice recording


- add text backup files when writing to the database
- add an 'i' for additional information - help the end-user - might need an additional column in the spreadsheet
- set up data management website per project - create an app that listens for new data and uploads to the server
- Add 'time' question type
- examine "idconfig" - have option of entering the subjid manually
- Add stats. All eligible variables in accordian type, one opens, one closes
- stats page - have it dynamic - in the data dictionary have a summary_statistics page - have a 
- revisit 'repeat' sections - maybe have them 'inline' - asked at a point in time before the 'main' survey is over - then user can go 'back' through all of them.
- where did synced_at get introduced?


### Code health - found during the M5 decomposition, each its own commit
- **A total database failure logs the wrong reason.** When the database cannot be read at all,
  the first read to fail is `DbService.getCrfConfig`, which swallows its error and returns null -
  so `ChildIncrementService` lands on the no-linkingfield branch and logs "No linkingfield
  configured for <table>". The value it writes is correct (the degraded 0); the sentence would
  send someone debugging a real incident after a dictionary problem that does not exist. Pinned
  in `test/services/child_increment_service_test.dart`.
- **Three implementations of "are these two answers the same", and they do not agree.**
  `AnswerValidationService.isPaddingOnlyChange`, `ChangeSummaryService._isLogicallyEqual` and
  `DbService._isSameStoredValue`. All three handle the numeric case ("04" == "4"); only some
  handle `DateTime`. Unifying them is a behaviour change, not a tidy-up, so it needs its own
  commit and its own tests - decide first which rule is the right one.
- **The identifier guard is not on every raw-SQL path.** Table and column names come from data
  dictionaries and cannot be bound, so they are interpolated;
  `SurveyTableSchema.quoteIdentifier` covers most sites but four are still raw: the CSV import's
  `CREATE TABLE` (filename + header row, the least controlled input), `_syncSurveyTable`'s
  `ALTER TABLE ADD COLUMN` (the CREATE path is quoted, the ALTER path is not),
  `isValueUnique` (table and column, and it is on a hot path), and `tryGetRecordCount`'s `where`
  fragment, which is built by the caller.
- **`DbBackup.lastBackupTime` has no callers.** None in `lib/` or `test/`, and none before the
  backup journal was extracted either. Either wire it up or delete it.


## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question

## Instructions
- have a new version (surveyID) for each updated survey