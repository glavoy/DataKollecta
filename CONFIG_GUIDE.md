# GiSTX Configuration Guide

## Overview
This guide explains how to configure the GiSTX survey application for your deployment environment.

## Configuration File
All application settings are centralized in `lib/config/app_config.dart`.

## Configuration Options

### Software Version
```dart
static const String softwareVersion = '0.0.3';
```
- This version is displayed in the app and saved with each interview record
- Automatically populated in the `swver` field
- Update this when releasing new versions

### Database Path

#### Option 1: Default Path (Recommended for Development)
```dart
static const String? customDatabasePath = null;
```
- Uses the system's application support directory
- Windows: `C:\Users\<username>\AppData\Roaming\com.example\GiSTX\datakollecta.sqlite`
- Automatically manages path based on platform

#### Option 2: Custom Path (Recommended for Production)
```dart
static const String? customDatabasePath = 'C:\\Data\\GiSTX\\datakollecta.sqlite';
```
- Use this for fixed database locations across different machines
- Useful for network drives or standardized deployment paths
- **Important**: Use double backslashes (`\\`) in Windows paths

### Database Filename
```dart
static const String databaseFilename = 'datakollecta.sqlite';
```
- Only used when `customDatabasePath` is null
- Can be changed if you want a different database name

### Survey Configuration
```dart
static const String surveyFilename = 'survey.xml';
static const String surveyAssetPath = 'assets/surveys/survey.xml';
```
- `surveyFilename`: Name of the XML file (used to derive table name)
- `surveyAssetPath`: Path to the survey XML in your Flutter assets
- Table name is automatically derived by removing `.xml` extension

### Logging and Error Dialogs
```dart
static const bool enableDebugLogging = true;
static const bool enableErrorDialogs = true;
```
- `enableDebugLogging`: Prints detailed logs to console (useful for debugging)
- `enableErrorDialogs`: Shows user-friendly error dialogs when save fails

## Database Requirements

### Database File
- Must exist at the configured path **before** running the survey
- Database name: `datakollecta.sqlite`
- Created by your external application

### Table Requirements
The application expects:
1. **Table name** matches the survey XML filename (without `.xml`)
   - Example: `survey.xml` → table name: `survey`
2. **Columns** match the `fieldname` attributes in the XML
   - Exclude fields where `type='information'`
3. **Primary key**: `uniqueid` column (automatically generated GUID)

### Example Table Structure
For the included `survey.xml`:
```sql
CREATE TABLE survey (
    starttime TEXT,           -- automatic datetime
    subjid TEXT,              -- text field
    tabletnum TEXT,           -- text_integer field
    tabletnum2 TEXT,          -- text_integer field
    sex INTEGER,              -- radio field
    pregnant INTEGER,         -- radio field
    pregnant_date TEXT,       -- date field
    village INTEGER,          -- combobox field
    village_other TEXT,       -- text field
    prep_pep_type TEXT,       -- checkbox field (comma-separated values)
    uniqueid TEXT PRIMARY KEY,-- automatic text (GUID)
    swver TEXT,               -- automatic text (software version)
    lastmod TEXT,             -- automatic datetime
    stoptime TEXT             -- automatic datetime
);
-- NOTE: info1 and end_of_questions are NOT included (type='information')
```

## Deployment Steps

### For Development
1. Keep default settings in `app_config.dart`
2. Create database using your external tool
3. Place `datakollecta.sqlite` in the default app directory
4. Run the application

### For Production Deployment
1. Edit `lib/config/app_config.dart`
2. Set `customDatabasePath` to your fixed path:
   ```dart
   static const String? customDatabasePath = 'C:\\GiSTX\\Data\\datakollecta.sqlite';
   ```
3. Ensure the database exists at that path on all machines
4. Build and deploy the application

## Error Handling

### Database Not Found
If the database file doesn't exist, you'll see:
```
Database file not found at: <path>

The database must be created by your external application before running surveys.
```

**Solution**: Create the database file at the configured path

### Table Not Found
If the table doesn't exist, you'll see:
```
Table "survey" does not exist in database.

Expected table name: survey
Database path: <path>

Please create this table using your external application before conducting surveys.
```

**Solution**: Create the table with the correct name (matching the XML filename)

### Save Failed Dialog
When `enableErrorDialogs = true`, users will see a detailed error dialog showing:
- Error message
- Database path
- Troubleshooting steps

## Troubleshooting

### Check Database Path
The application logs the database path on startup:
```
[DbService] Using custom database path: C:\GiSTX\Data\datakollecta.sqlite
```
or
```
[DbService] Using default database path: C:\Users\...\datakollecta.sqlite
```

### Verify Table Exists
The application checks if the table exists before attempting to save data.

### Debug Logging
Enable debug logging to see detailed information:
```dart
static const bool enableDebugLogging = true;
```

Logs will show:
- Database initialization
- Table existence checks
- Column names being saved
- Save success/failure

## Example Configurations

### Single Machine Development
```dart
static const String? customDatabasePath = null;
```

### Multi-Machine Lab Environment
```dart
static const String? customDatabasePath = 'C:\\LabData\\Surveys\\datakollecta.sqlite';
```

### Network Drive
```dart
static const String? customDatabasePath = '\\\\ServerName\\SharedFolder\\datakollecta.sqlite';
```

## Notes
- All datetime fields are stored in ISO8601 format
- Date-only fields are stored as `YYYY-MM-DD`
- Checkbox fields are stored as comma-separated values
- Information-type questions are never saved to the database
