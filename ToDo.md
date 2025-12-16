### To Do
- Kollect, the name of the app - or GiSTKollect
- Add 'time' question type
- examine "idconfig" - have option of entering the subjid manually
- subjid and hhid - these should be normal automatic variables - check these
- a person can sleep under more than one net - how can we check this?
- add functionality to modify a table if necessary - for example changing a field type from text to int and vice versa
- Add stats. All eligible variables in accordian type, one opens, one closes
- stats page - have it dynamic - in the data dictionary have a summary_statistics page - have a 
- revisit 'repeat' sections - maybe have them 'inline' - asked at a point in time before the 'main' survey is over - then user can go 'back' through all of them.
- Add 'button' question type?
- Add dynamic date ranges. If someone is two years old, don't let date go back now tham 2 years. This can also be logic check
For Android (APK)
Instead of flutter build apk: Run 
.\build_apk.ps1

For Windows
Instead of flutter build windows: Run 
.\build_windows.ps1

Both of these scripts will now:

Automatically increment the version in 
pubspec.yaml
 (e.g., 0.0.1 -> 0.0.2).
Run the build command for you.




## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- verify logic check variables are not in the future - i.e. they alreayd have a value
- add 'help' screen to gistcongigx so user can see all of the options - add link to README


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question

## Instructions
- have a new version (surveyID) for each updaetd survey