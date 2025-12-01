### To Do
- Update GiSTXConfig to create the json files - add survey_id to the json config in GiSTConfig
- Add utilization of csv files in the app - nested selects as well - also add 'static' to <responses>
- Add functionality to pick data from the database i.e. Who sleep under the net. Who is the mother; - add functionality so that structures/names can be the options for a question

- Add time type to gistx
- examine "idconfig" - have option of entering the subjid manually
- subjid and hhid - these should be normal automatic variables
- revisit automatic variables - is there a better way so we don;t need to change the code
- add auto gen of responses for prism css - schools - mrccode  - select school

- add this to gistxconfig
		<unique_check>
			<message>barcode will create duplicates</message>
		</unique_check>


- add functionality to modify a table if necessary - for example changing a field type from text to int and vice versa
- Add stats. All eligible variables in accordian type, one opens, one closes





## GistXConfig
- look at the code for parsing skips - add multiple logic: if xxx = 1 and yyy < 5, then skip to...
- verify logic check variables are not in the future - i.e. they alreayd have a value
- add 'help' screen to gistcongigx so user can see all of the options


## To test
- when viewing/modifying a survey
    - are the correct changes made in the DB
    - are changes saved to the formchanges table
- does the previous button always take you to the correct question

## Instructions
- have a new version (surveyID) for each updaetd survey