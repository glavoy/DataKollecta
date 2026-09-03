# Phase 1: Settings and Survey Configuration - Implementation Summary

## Overview
This phase establishes the foundation for multi-survey support and external configuration management, moving away from hardcoded survey-specific settings.

## What Was Implemented

### 1. Settings Service (`lib/services/settings_service.dart`)
- Created encrypted storage service using `flutter_secure_storage`
- Stores user credentials and survey selection:
  - Surveyor ID (user-entered identifier for data tracking)
  - FTP Host, Username, Password (for future download/upload)
  - Active Survey (currently selected survey)
- All sensitive data (especially FTP password) stored encrypted
- Platform-appropriate storage (Windows Credential Manager, Android Keystore)

### 2. Settings Screen (`lib/screens/settings_screen.dart`)
- New UI for configuring user settings
- Three main sections:
  1. **User Settings**: Surveyor ID field (required)
  2. **Survey Selection**: Dropdown to select active survey
  3. **FTP Settings**: Host, username, password (optional, for future use)
- Accessible via new "Settings" button in main screen
- Validates required fields (surveyor ID)
- Shows/hides password with toggle button

### 3. Survey Manifest System
Created example configuration for "Fake Household Survey":

**survey_manifest.json** - Survey metadata
```json
{
  "surveyId": "fake_household_survey",
  "surveyName": "Fake Household Survey",
  "version": "1.0.0",
  "lastUpdated": "2025-01-27T00:00:00Z",
  "databaseName": "fake_household_survey.sqlite",
  "xmlFiles": [
    "household.xml",
    "hh_members.xml",
    "enrollment.xml",
    "followup.xml",
    "swf.xml"
  ],
  "crfsMetadataFile": "crfs_metadata.csv"
}
```

**crfs_metadata.csv** - Survey behavior metadata
- Contains CRF table configuration previously in Excel
- Defines table relationships, primary keys, display order, auto-repeat logic
- CSV format for easy export from Excel

### 4. Folder Restructuring
**Before:**
```
assets/surveys/
  ├── enrollment.xml
  ├── followup.xml
  ├── household.xml
  ├── hh_members.xml
  └── swf.xml
```

**After:**
```
assets/surveys/
  └── fake_household_survey/
      ├── survey_manifest.json
      ├── crfs_metadata.csv
      ├── enrollment.xml
      ├── followup.xml
      ├── household.xml
      ├── hh_members.xml
      └── swf.xml
```

This structure supports multiple surveys in parallel.

### 5. App Config Refactoring (`lib/config/app_config.dart`)
**Removed (survey-specific):**
- `applicationName` → Now read from settings/manifest
- Survey-specific database paths

**Kept (app-level):**
- `softwareVersion` (GiSTX app version)
- `enableDebugLogging`
- `enableErrorDialogs`

**Temporary (for compatibility):**
- Added back database path methods with `@deprecated` markers
- TODO: Remove after db_service.dart is refactored to use manifests

### 6. Main Screen Updates (`lib/screens/main_screen.dart`)
- Changed from StatelessWidget to StatefulWidget
- Loads survey name from settings instead of hardcoded AppConfig
- Shows "GiSTX Survey App" as default if no survey selected
- Added "Settings" button in app bar

## Package Dependencies Added
- `flutter_secure_storage: ^9.2.2` - Encrypted credential storage

## File Upload Structure (Planned)
When FTP upload is implemented, structure will be:
```
ftp://server/
  ├── project1/
  │   ├── config/
  │   │   ├── survey_manifest.json
  │   │   ├── crfs_metadata.csv
  │   │   └── *.xml files
  │   └── data/
  │       ├── surveyor_001/
  │       │   ├── survey_2025-01-27_10-30-00.db.zip
  │       │   └── survey_2025-01-27_14-15-00.db.zip
  │       └── surveyor_002/
  │           └── ...
```

## Current Status
✅ Settings screen created and accessible
✅ Settings service with encrypted storage
✅ Survey manifest and crfs_metadata examples
✅ Folder structure reorganized
✅ App config refactored
✅ All code compiles without errors

## Next Steps (Future Phases)

### Phase 2: Survey Loading & Database Generation
- Parse survey_manifest.json to load surveys
- Parse crfs_metadata.csv for survey behavior
- Update db_service.dart to use manifest for database paths
- Generate database from XML + crfs metadata
- Implement survey dropdown population (scan assets/surveys/)

### Phase 3: FTP Download
- Implement FTP client
- Connect using stored credentials
- Browse available surveys on server
- Download survey packages (manifest + xmls + crfs)
- Save to local assets/surveys/{survey_id}/

### Phase 4: FTP Upload
- Implement data sync button/automatic sync
- Zip current database
- Upload to surveyor-specific folder
- Filename format: `{surveyname}_{timestamp}.db.zip`
- Track last sync time

### Phase 5: Version Management
- Check server for survey updates
- Compare local vs server versions
- Download and apply updates
- Preserve existing data during updates

## Notes for Developer
- The surveyor ID will be used in upload filenames and folder organization
- FTP credentials are stored encrypted but not currently used
- The survey dropdown currently shows hardcoded "Fake Household Survey"
- Database service still uses old paths (marked with TODO)
- All changes are backward compatible with existing functionality

## Testing Recommendations
1. Run the app and open Settings screen
2. Enter a surveyor ID and save
3. Verify settings persist across app restarts
4. Check that main screen displays correct survey name
5. Verify existing survey functionality still works
