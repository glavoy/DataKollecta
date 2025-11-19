### To Do
- add the name of the project to the DD - no hard coding in the app
- ensure multiple skips are working
- add DB logic to check if all the fields exist in the database - based on the xml file - if not add new fields - this is now automatic
- do not allow duplicate records for the primary key values - add 'unique' logic check
- Add time type to gistx
- for checkbox types, when don;t know or refuse, don;t allow other options
- upload to ftp server


## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- have date ranges: +/- day(s)/month(s)/year(s) - gist config
- verify logic check variables are not in the future - i.e. they alreayd have a value
- add 'help' screen to gistcongigx so user can see all of the options

## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question
