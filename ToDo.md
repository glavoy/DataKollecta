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


### Code health
- **`FieldComparator.compare` parses numbers with `double`, not `num`.** So two 17-digit
  barcodes differing in the last digit compare *equal*, and a skip, logic_check or
  calculation on a long ID silently takes the wrong branch. `AnswerEquality` deliberately
  does not reuse it for that reason. Whether to switch it to `num` is a behaviour change
  for skip/logic/calculation, so it needs its own commit and its own tests.
- **The identifier guard covers the SQL this codebase writes, not the SQL sqflite writes.**
  `db.query`/`insert`/`update`/`delete` interpolate the table and column names they are
  given without quoting them, so any of those calls carrying a dictionary-sourced name is
  still exposed. `importCsvContent` now builds its own statements for exactly this reason.
  Closing it properly means validating identifiers where they enter from the dictionary
  rather than at each use, which is a design change rather than a fix.
- **`_recordChanges` does not guard its surveyor-id read, and `updateField` does.**
  `updateField` wraps that read in its own try/catch with a comment saying a settings read
  that fails must not cost us the write; `_recordChanges` lets the exception abort the
  whole method, so a settings failure loses the entire audit trail for that save rather
  than one column of it. Found while testing the answer-equality unification.


## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question

## Instructions
- have a new version (surveyID) for each updated survey