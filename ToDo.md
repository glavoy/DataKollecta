## R21 Negative

### From Data Dictionary

- [x] Add MRC of Enrollment: Busitema HC III code 096 in Busia district and Kigandalo HC IV code 110 in Mayuge district
- fpbarcode1_r21: Any way to format this automatically as the id is typed in: R21-096-NYZ1
    - [x] add regex formatting for question - need to update GiSTXConfig as well


### From Test Plan checklist

- In the list of surveys to modify, can the format be subid + date enrolled + fname
	- [x] When viewing dropdown of completed surveys (when viewing/modifying a survey), show subid + date enrolled + name (add another field called 'date' - similar to date/time)
- When you exit a survey that you are modiying, you get the same message "Are you sure you want to cancel. All data will be lost!" Can this be changed? "All edits/modifications will be lost" …assuming that is true.
	- [x] Change message when users clicks cancel when viewing/modifying a survey to "All edits/modifications will be lost"
- Is there a way to "save changes" when you are modifying a survey without having to pan through the entire survey
	- [ ] Show dialog when user clicks cancel summarizing the changes - ask if they want to save them or not save them - maybe implement this, maybe not
- Can the sub id pull from the mrc id of the mcr where enrollment is happening nad not the district id. 
	- [x] Change the format of the subjid
- And we will enroll more than 999 per district/mrc if we extend the study whch is likely
	- [x] Change the incremental part of the subjid to be 4 digits
- I am able to document dose 2 and dose 3 on the same date
	- [x] Change logig check to be <=
- for malaria vaccine the dates it is possible to receive it shoud be march 1 2025 through to today. Currently you can select from birth through august 2025. 
	- [x] change date range to allow hard-coded dates - will require changes to gistconfig
    - [x] for malaria vaccine the dates it is possible to receive it shoud be march 1 2025 through to today
    - [x] for hib vaccine it can be from brith through to today - need to chang ethe way dates max/min
- If I change BUSIA to MAYUGE, it should autoclear the subcounty, parish, and village so I have to reselect at each level below the change. Instead it autoselects from the list
    - [x] change this behaviour in GiSTX app

### From email
- The upper limit sounds good, though we need it to be set relative to the child being under 1 as of April 1 2025.
    - [x] change age_at_may2025 to age_at_april2025
- It would be good to document where the survey is taking place (which MRC - I added this question) and then leave the district, parish village etc of resident options to be broader - even the full list of districts would be okay, though if possible to sort Mayuge and Busia to the top of the list, that would be good.
    - [x] change the district, parish, village options to be broader - even the full list of districts would be okay, though if possible to sort Mayuge and Busia to the top of the list, that would be good.



### Responses
- Each user uses the same username and password per project - these credentials link to specific folders on the FTP server for downloading new surveys and uploading data. Each user is assigned a unique ID that they enter into the app and this is appended to the filename when data is uploaded. This Id is also entered into each unique survey at the beginning. The FTP host and port are hard-coded in the app.

- I confirm that the enrollee data includes the latest data in each record. When uploading data, the current entire database is uploaded - you only need to look at the latest upload - it contains all the data. The 'formchanges' table contains all the changes made to the data.

### Changes
- Updated the survey with all your changes to the DD - wording, skips, logic checks, new questions, etc.
- I did not implement a complete list of all districts and villages nationwide. I expect that more than 95 percent of participants will reside in the same district as the health center they are visiting; therefore, collecting the exact village of residence is unlikely to add meaningful value for analysis. I did however include an open-text field to capture this information for participants who reside outside Busia or Mayuge. I also added a validation warning when Busitema HC III is selected in combination with Mayuge as the district of residence, and vice versa, to flag potential inconsistencies.
- changed subjid to be: 3-digit mrc + 2-digit intnum + 4 digit incremental number - 9 characters in length (mrc + intnum + 0001). Note however, that the code for Busitema HC III begins with a '0' and when you pull the data into any software, it will typically treat the subjid as a number - since it includes only numbers - and strip off the leading '0', so you will end up with some subjid's being 8 characters and some being 9 characters. My rule of thumb is never to start codes with 0, for this very reason. We can change the coding if you want so that we lose the '0' - I just kept the same codes as we use in the PRISM/UMSP studies. Let me know if you want to change these.
- Changed the eligibility criteria to be: A participant is eligible if they are at least 8 months old on the day of enrollment and were under 12 months of age as of April 1st, 2025. (Someone born on Apr. 1, 2024 is not eligible)
- Regarding 'participantsfname' and 'participantslname' from the data dictionary, I recommend just using the terminology 'Participant names' - this is more commonly understod in Uganda and the concept of first and last name is pretty much unknown. I have reverted the DD back to 'participantname' only, however, if you want to stick to first and last name, I will change it back
- changed the logic for the date of doses - e.g. dose 2 and dose 3 cannot be on the same date - I just changed '<' to '<='
- Added warnings if doses are too close together, but allows the user to continue anyway
- Malaria vaccine cannot be before March 1, 2025 - and allows date up until today
- HiB vaccine date range is from DOB up until today
- bednettwoweeks: added logic check such that user cannot select 0 nights when the previous question was 'Yes' - participant slept under a net last night
- Added a 'regex' style formatting to the barcodes - user does not have to type in 'R21-' and subsequent '-'
- When viewing dropdown of completed surveys (when viewing/modifying a survey) it now shows subid + date enrolled + name
- When you exit a survey that you are modiying, changed the text to: "Are you sure you want to cancel. All edits/modifications will be lost!" 
- When changing the district, e.g. BUSIA to MAYUGE, it clears the subcounty, parish, and village. This cascades - if only the subcounty is changed, the parish is also cleared, etc.





### Questions
- We provided a warning if the subsequent malaria dose was less than 28 days from the previous dose. We also added a summary of the malaria vaccine dates - do we want to do the same for the HiB vaccine?
- Do you want to change the codes for the mrc's to remove the leading 0?
- Do you want to keep first and last name or just stick to 'participantsname'?




### Changes required (done) to GiSTX App
- added 'startdate' automatic field type
- added regex for text types
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