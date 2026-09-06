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
- **A data dictionary is a trusted SQL source on one path, by design.**
  `<calculation type="query">` hands `config.sql` to `db.rawQuery` verbatim
  (`auto_fields.dart`), so a dictionary author can run any statement they like. Identifier
  validation is meaningless there -- the whole statement is theirs. Left as it is because
  the feature is the point, but worth knowing when reasoning about what a package can do:
  everything *else* dictionary-sourced is now held to
  `SurveyTableSchema.validateIdentifier` as it enters.


## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question

## Instructions
- have a new version (surveyID) for each updated survey