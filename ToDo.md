### To Do
- the tablet number is 05 and not 54 that I entered
- remove the whole async thing - the fields for the subjid will always be before the generation of the ID
- need to update gistconficx to add new crfs table format
- add 'Special buttons'
- add 'does not contain' and contains
- add logic checks - multiple
- add multiple skips
- add number in crfs table for the order of the crfs to be displayed
- commetns fiewld should be optional
- add 'modifying survey' - change auto variables
- add logic for date ranges: +/- day(s)/month(s)/year(s) - gist config
- ensure skip logic works for several skips at once
- the OK screen confirmation at the end is not modal - when clicking anywhere it goes away and the user can click finish again and the data is saved again to the database
- add module for doing custom logic checks - or better yet, add them to the xml file and add more logic to the app
- add DB logic to check if all the fields exist in the database - based on the xml file - if not add new fields - this is now automatic
- need to check if any responses changed when modifying a surevy - if so, record changes - if not there is no need to do anything except show a dialog box that nothing changed - lastmod - should not change - in fact nothing is written to the database
- add selection of survey
- when modifying survey - make the background a differnt colour - or add some kind of widget to make it clear
- add to main screen the surveys in the databse - crfs. config, formchanges, ...
- do not allow duplicate records for the primary key values
- when selecting/adding a date - can it be modal - clicking outside the date picker makes it disappear and the dtae you may have selected is not the selected date
- datetime stamp - is it local time - it looks like GMT
- added comments filed - should always be there - make it optional
- Add time type to gistx
- add 'help' screen to gistcongigx so user can see all of the options

## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- look at the code for parsing logic checks - add multiple logic: if xxx = 1 and yyy < 5, then...
- have date ranges: +/- day(s)/month(s)/year(s) - gist config


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question
