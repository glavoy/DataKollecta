### To Do

- add logic checks - multiple
- add multiple skips
- add 'modifying survey' - change auto variables
- add logic for date ranges: +/- day(s)/month(s)/year(s) - gist config
- ensure skip logic works for several skips at once
- add 'special buttons'
- the OK screen confirmation at the end is not modal - when clicking anywhere it goes away and the user can click finish again and the data is saved again to the database
- add module for doing custom logic checks - or better yet, add them to the xml file and add more logic to the app
- add DB logic to check if all the fields exist in the database - based on the xml file - if not add new fields - this is now automatic

## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- look at the code for parsing logic checks - add multiple logic: if xxx = 1 and yyy < 5, then...
- have date ranges: +/- day(s)/month(s)/year(s) - gist config