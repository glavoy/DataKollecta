## R21 Negative

### From Data Dictionary

- [ ] Update survey with Annies changes to the DD - wording, skips, logic checks, new questions, etc.
    - Question text updated automatically from data dictionary
- [ ] Add MRC of Enrollment: Busitema HC III code 096 in Busia district and Kigandalo HC IV code 110 in Mayuge district
- fpbarcode1_r21: Any way to format this automatically as the id is typed in: R21-096-NYZ1
    - [ ] add regex formatting for question - need to update GiSTXConfig as well


### From Test Plan checklist

- In the list of surveys to modify, can the format be subid + date enrolled + fname
	- [ ] When viewing dropdown of completed surveys (when viewing/modifying a survey), show subid + date enrolled + name (add another field called 'date' - similar to date/time)
- When you exit a survey that you are modiying, you get the same message "Are you sure you want to cancel. All data will be lost!" Can this be changed? "All edits/modifications will be lost" …assuming that is true.
	- [ ] Change message when users clicks cancel when viewing/modifying a survey to "All edits/modifications will be lost"
- Is there a way to "save changes" when you are modifying a survey without having to pan through the entire survey
	- [ ] Show dialog when user clicks cancel summarizing the changes - ask if they want to save them or not save them - maybe implement this, maybe not
- Can the sub id pull from the mrc id of the mcr where enrollment is happening nad not the district id. 
	- [ ] Change the format of the subjid
- And we will enroll more than 999 per district/mrc if we extend the study whch is likely
	- [ ] Change the incremental part of the subjid to be 4 digits
- I am able to document dose 2 and dose 3 on the same date
	- [ ] Change logig check to be <=
- for malaria vaccine the dates it is possible to receive it shoud be march 1 2025 through to today. Currently you can select from birth through august 2025. 
	- [ ] change date range to allow hard-coded dates - will require changes to gistconfig
    - [ ] for malaria vaccine the dates it is possible to receive it shoud be march 1 2025 through to today
    - [ ] for hib vaccine it can be from brith through to today - need to chang ethe way dates max/min
- If I change BUSIA to MAYUGE, it should autoclear the subcounty, parish, and village so I have to reselect at each level below the change. Instead it autoselects from the list
    - [ ] change this behaviour in GiSTX app

### From email
- The upper limit sounds good, though we need it to be set relative to the child being under 1 as of April 1 2025.
    - [ ] change age_at_may2025 to age_at_april2025
- It would be good to document where the survey is taking place (which MRC - I added this question) and then leave the district, parish village etc of resident options to be broader - even the full list of districts would be okay, though if possible to sort Mayuge and Busia to the top of the list, that would be good.
    - [ ] change the district, parish, village options to be broader - even the full list of districts would be okay, though if possible to sort Mayuge and Busia to the top of the list, that would be good.



### Responses
- Username and password provided work as expected. Same credentials for user? How to edit server address and port? 
    - host and port are hard-coded
- Regarding 'participantsfname' and 'participantslname' from the data dictionary, I recommend just using the terminology 'Participant names' - this is more commonly understod in Uganda and the concept of first and last name is pretty much unknown.
- we provided a warning if the subsequent malaria dose was less than 28 days from the previous dose. We also added a summary of the malaria vaccine dates - do we want to do the same for the HiB vaccine?
- I also did look at the data on the web side and it looks good. To confirm - the enrollee data should include the latest data in each record (reflecting any newest changes made)?
    - [ ] yes, the enrollee data includes the latest data in each record (reflecting any newest changes made)

### Changes required to GiSTX App
- vx_dose1_date:
    - Need to ensure functionality to do comparisons with fixed dates - need to update GiSTXConfig as well
	- vx_dose1_date < dob; 'Date of vaccination cannot be before date of birth!'
	- vx_dose1_date < March 1 2025; 'Date of vaccination cannot be before March 1 2025!'
- vx_dose2_datecheck, vx_dose3_datecheck, vx_dose4_datecheck:
    - need to ensure functionality to do comparisons with dates +/- a time period - need to update GiSTXConfig as well
    - preskip: vx_dose2_date < vx_dose1_date+28



## To Do

- Kollect, the name of the app - or GiSTKollect
- add text backup files when writing to the database
- add an 'i' for additional information - help the end-user - might need an additional column in the spreadsheet
- set up data management website per project - create an app that listens for new data and uploads to the server
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