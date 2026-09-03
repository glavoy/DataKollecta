# Dropdown Fix Summary

## Problem
The survey dropdown in the Settings screen was empty and not showing "Fake Household Survey".

## Root Causes

### 1. **Asset Not Bundled**
The `survey_manifest.json` file wasn't included in the Flutter asset bundle because the app wasn't rebuilt after creating the file.

**Solution:** Full rebuild required (`flutter clean && flutter run`)

### 2. **AssetManifest.json Loading Issue**
The code was trying to load `AssetManifest.json` which can cause issues in debug mode.

**Solution:** Changed to load the survey manifest directly from the known path

### 3. **Initialization Timing**
`_loadSettings()` was setting `_isLoading = false` before `_loadAvailableSurveys()` completed, causing the dropdown to render empty.

**Solution:** Changed to sequential loading with `async/await`

## Changes Made

### 1. Fixed Survey Loading ([lib/screens/settings_screen.dart](lib/screens/settings_screen.dart:71-107))

**Before:**
```dart
// Tried to load AssetManifest.json (which doesn't exist in debug mode)
final manifestContent = await rootBundle.loadString('AssetManifest.json');
```

**After:**
```dart
// Load survey manifest directly from known path
const manifestPath = 'assets/surveys/fake_household_survey/survey_manifest.json';
final manifestJson = await rootBundle.loadString(manifestPath);
```

### 2. Fixed Initialization Order ([lib/screens/settings_screen.dart](lib/screens/settings_screen.dart:37-41))

**Before:**
```dart
void initState() {
  super.initState();
  _loadSettings();        // Sets _isLoading = false
  _loadAvailableSurveys(); // Runs in parallel
}
```

**After:**
```dart
void initState() {
  super.initState();
  _initialize();
}

Future<void> _initialize() async {
  await _loadAvailableSurveys(); // Wait for surveys to load
  await _loadSettings();         // Then load settings
}
```

### 3. Improved Dropdown UI ([lib/screens/settings_screen.dart](lib/screens/settings_screen.dart:213-251))

- Replaced deprecated `DropdownButtonFormField` with `InputDecorator` + `DropdownButton`
- Added helpful message when no surveys found: "No surveys available - rebuild app"
- Added null safety checks
- Added `mounted` checks before `setState`

## How to Test

### Step 1: Rebuild the App
The app has been cleaned. Now run:

```bash
cd "c:\GeoffOffline\GiSTX"
flutter run
```

### Step 2: Check Debug Output
Watch the console for these messages:

```
Attempting to load survey manifest from: assets/surveys/fake_household_survey/survey_manifest.json
Survey name from manifest: Fake Household Survey
Added survey to list: Fake Household Survey
Final available surveys: [Fake Household Survey]
```

### Step 3: Open Settings
1. Click the "Settings" button in the app
2. Look at the "Survey Selection" section
3. The dropdown should now show "Fake Household Survey"

### If It Still Doesn't Work

If you see this message in the console:
```
WARNING: No surveys found - please ensure flutter run was executed with a full rebuild
Try: flutter clean && flutter run
```

Then:
1. **Stop the app completely** (not just hot reload)
2. **Close your IDE** (VS Code, Android Studio, etc.)
3. **Run:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## Why This Happened

When you add new asset files (like `survey_manifest.json`), Flutter needs to:
1. Read the `pubspec.yaml` assets section
2. Bundle those files into the app during build
3. Create the asset registry

**Hot reload (`r`)** only updates Dart code, not assets.
**Hot restart (`R`)** reloads the app but may not always rebuild assets.
**Full rebuild** (`flutter clean && flutter run`) ensures all assets are included.

## Files Modified

- [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart)
  - Changed survey loading logic
  - Fixed initialization order
  - Improved dropdown UI

## Technical Details

### Asset Path Resolution
```
pubspec.yaml declares:
  assets:
    - assets/surveys/fake_household_survey/

This includes all files in that folder:
  ✓ survey_manifest.json
  ✓ crfs_metadata.csv
  ✓ household.xml
  ✓ hh_members.xml

At runtime, load with:
  rootBundle.loadString('assets/surveys/fake_household_survey/survey_manifest.json')
```

### Future Enhancement
For multiple surveys, we could scan all subfolders in `assets/surveys/`, but for now, we're explicitly loading the known survey manifest path. This is simpler and more reliable.

## Next Steps

Once the dropdown works:
1. ✅ Enter your Surveyor ID
2. ✅ Select "Fake Household Survey" from dropdown
3. ✅ Click Save
4. ✅ Try starting a new survey - it should load XML files from the correct folder
