### To Do
- Add time type to gistx
- upload/download to ftp server
- add functionality to modify a table if necessary - for example changing a field type from text to int and vice versa
- Add stats. All eligible variables in accordian type, one opens, one closes
- app should look at the xml files listed in the json file rather than just the ones in the folder - we may remove some from the survey
- I don't think 'crfsMetadataFile' is needed in the survey_manifest.json file
- change crfs.csv to a json file
-instructions - have a new version for each updaetd survey
- [x] add text backup files when writing to the database.



## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- verify logic check variables are not in the future - i.e. they alreayd have a value
- add 'help' screen to gistcongigx so user can see all of the options


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question
