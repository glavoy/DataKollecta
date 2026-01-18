# GiSTKollect Implementation Plan - Part 3

## Phases 11-15: Mobile App Updates & Deployment

This document continues from Part 2 with detailed instructions for updating the mobile app and deployment.

---

## Phase 11: Mobile App - Rename & Rebrand

**Estimated time: 2-3 hours**

### Step 11.1: Create New Branch

```powershell
cd C:\GeoffOffline\GiSTX

# Make sure you're on main and up to date
git checkout main
git pull

# Create new branch for Supabase integration
git checkout -b supabase-integration

# Verify you're on the new branch
git branch
```

### Step 11.2: Update pubspec.yaml

Edit `pubspec.yaml`:

```yaml
name: gistkollect  # Changed from gistx
description: GiSTKollect Data Collection App

version: 1.0.0+1  # Reset version for new release

# ... rest of file stays the same, but add:
dependencies:
  # ... existing dependencies ...

  # Add Supabase
  supabase_flutter: ^2.3.0
```

Run:
```powershell
flutter pub get
```

### Step 11.3: Update Android Configuration

**android/app/build.gradle:**

Find and update:
```gradle
defaultConfig {
    applicationId "org.gistkollect.app"  // Changed from com.example.gistx
    minSdkVersion 21
    targetSdkVersion flutter.targetSdkVersion
    versionCode flutterVersionCode.toInteger()
    versionName flutterVersionName
}
```

**android/app/src/main/AndroidManifest.xml:**

Update the label:
```xml
<application
    android:label="GiSTKollect"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

### Step 11.4: Update iOS Configuration

**ios/Runner/Info.plist:**

Find and update:
```xml
<key>CFBundleDisplayName</key>
<string>GiSTKollect</string>
<key>CFBundleName</key>
<string>GiSTKollect</string>
```

### Step 11.5: Update Windows Configuration

**windows/runner/main.cpp:**

Find and update:
```cpp
if (!window.Create(L"GiSTKollect", origin, size)) {
    return EXIT_FAILURE;
}
```

**windows/runner/Runner.rc:**

Update product name and file description:
```rc
VALUE "FileDescription", "GiSTKollect Data Collection" "\0"
VALUE "ProductName", "GiSTKollect" "\0"
```

**installer.iss (if you have one):**

Update all references from GiSTX to GiSTKollect.

### Step 11.6: Update App Text

Search the codebase for "GiSTX" or "datakollecta" and replace with "GiSTKollect" or "gistkollect":

```powershell
# Find all occurrences (use your IDE's search feature)
# Common locations:
# - lib/main.dart (app title)
# - lib/screens/*.dart (any UI text)
# - README.md
# - Any documentation
```

**lib/main.dart:**

```dart
MaterialApp(
  title: 'GiSTKollect',  // Updated
  // ...
)
```

### Step 11.7: Update App Icons (Optional)

If you want new icons:

1. Create new icon (1024x1024 PNG)
2. Use https://appicon.co/ or flutter_launcher_icons package
3. Replace icons in:
   - `android/app/src/main/res/mipmap-*`
   - `ios/Runner/Assets.xcassets/AppIcon.appiconset`
   - `windows/runner/resources/app_icon.ico`

### Step 11.8: Test the Renamed App

```powershell
# Test on each platform you support
flutter run -d windows
flutter run -d chrome
flutter build apk --debug
```

Verify:
- App name shows as "GiSTKollect" everywhere
- App functions exactly as before
- No broken references

### Step 11.9: Commit Changes

```powershell
git add .
git commit -m "Rename app from GiSTX to GiSTKollect"
```

### Step 11.10: Checklist

- [ ] Created supabase-integration branch
- [ ] Updated pubspec.yaml name
- [ ] Added supabase_flutter dependency
- [ ] Updated Android applicationId and label
- [ ] Updated iOS bundle display name
- [ ] Updated Windows app title
- [ ] Replaced all GiSTX text references
- [ ] Tested app runs correctly
- [ ] Committed changes

---

## Phase 12: Mobile App - Authentication

**Estimated time: 3-4 hours**

### Step 12.1: Create Supabase Config

**lib/config/supabase_config.dart:**

```dart
class SupabaseConfig {
  // Replace with your actual Supabase project values
  static const String url = 'https://YOUR_PROJECT.supabase.co';
  static const String anonKey = 'YOUR_ANON_KEY';

  // Edge function URLs
  static String get appLoginUrl => '$url/functions/v1/app-login';
  static String get appSyncUrl => '$url/functions/v1/app-sync';
}
```

### Step 12.2: Initialize Supabase

**lib/main.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const GiSTKollectApp());
}

class GiSTKollectApp extends StatelessWidget {
  const GiSTKollectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GiSTKollect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AppAuthWrapper(),
    );
  }
}

class AppAuthWrapper extends StatelessWidget {
  const AppAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return const MainScreen(); // Your existing main screen
        }

        return const AppLoginScreen();
      },
    );
  }

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('app_token');
    final expiresAt = prefs.getString('token_expires_at');

    if (token == null || expiresAt == null) return false;

    final expiry = DateTime.tryParse(expiresAt);
    if (expiry == null || expiry.isBefore(DateTime.now())) {
      return false;
    }

    return true;
  }
}
```

### Step 12.3: Create App Auth Service

**lib/services/app_auth_service.dart:**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

class AppAuthService {
  static const String _keyProjectId = 'project_id';
  static const String _keyProjectName = 'project_name';
  static const String _keyProjectCode = 'project_code';
  static const String _keyUsername = 'username';
  static const String _keyToken = 'app_token';
  static const String _keyExpiresAt = 'token_expires_at';
  static const String _keySurveys = 'available_surveys';

  /// Login to the app
  Future<AppLoginResult> login({
    required String projectCode,
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(SupabaseConfig.appLoginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'project_code': projectCode.trim().toLowerCase(),
          'username': username.trim(),
          'password': password,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        return AppLoginResult.failure(error['error'] ?? 'Login failed');
      }

      final data = jsonDecode(response.body);

      // Save credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyProjectId, data['project']['id']);
      await prefs.setString(_keyProjectName, data['project']['name']);
      await prefs.setString(_keyProjectCode, data['project']['code']);
      await prefs.setString(_keyUsername, data['credential']['username']);
      await prefs.setString(_keyToken, data['token']);
      await prefs.setString(_keyExpiresAt, data['expires_at']);
      await prefs.setString(_keySurveys, jsonEncode(data['surveys']));

      return AppLoginResult.success(
        projectId: data['project']['id'],
        projectName: data['project']['name'],
        surveys: (data['surveys'] as List)
            .map((s) => AvailableSurvey.fromJson(s))
            .toList(),
      );
    } catch (e) {
      return AppLoginResult.failure('Connection error: $e');
    }
  }

  /// Check if logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    final expiresAt = prefs.getString(_keyExpiresAt);

    if (token == null || expiresAt == null) return false;

    final expiry = DateTime.tryParse(expiresAt);
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  /// Get stored token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  /// Get stored project info
  Future<Map<String, String?>> getProjectInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString(_keyProjectId),
      'name': prefs.getString(_keyProjectName),
      'code': prefs.getString(_keyProjectCode),
    };
  }

  /// Get stored surveys
  Future<List<AvailableSurvey>> getStoredSurveys() async {
    final prefs = await SharedPreferences.getInstance();
    final surveysJson = prefs.getString(_keySurveys);
    if (surveysJson == null) return [];

    final surveys = jsonDecode(surveysJson) as List;
    return surveys.map((s) => AvailableSurvey.fromJson(s)).toList();
  }

  /// Get remembered credentials (for pre-filling login form)
  Future<Map<String, String?>> getRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'project_code': prefs.getString('last_project_code'),
      'username': prefs.getString('last_username'),
    };
  }

  /// Save credentials for next login
  Future<void> rememberCredentials({
    required String projectCode,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_project_code', projectCode);
    await prefs.setString('last_username', username);
  }

  /// Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProjectId);
    await prefs.remove(_keyProjectName);
    await prefs.remove(_keyProjectCode);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyToken);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keySurveys);
    // Keep last_project_code and last_username for convenience
  }

  /// Clear all data including remembered credentials
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

class AppLoginResult {
  final bool success;
  final String? error;
  final String? projectId;
  final String? projectName;
  final List<AvailableSurvey>? surveys;

  AppLoginResult._({
    required this.success,
    this.error,
    this.projectId,
    this.projectName,
    this.surveys,
  });

  factory AppLoginResult.success({
    required String projectId,
    required String projectName,
    required List<AvailableSurvey> surveys,
  }) {
    return AppLoginResult._(
      success: true,
      projectId: projectId,
      projectName: projectName,
      surveys: surveys,
    );
  }

  factory AppLoginResult.failure(String error) {
    return AppLoginResult._(success: false, error: error);
  }
}

class AvailableSurvey {
  final String id;
  final String name;
  final String? version;
  final Map<String, dynamic>? manifest;
  final DateTime? updatedAt;
  final String? downloadUrl;

  AvailableSurvey({
    required this.id,
    required this.name,
    this.version,
    this.manifest,
    this.updatedAt,
    this.downloadUrl,
  });

  factory AvailableSurvey.fromJson(Map<String, dynamic> json) {
    return AvailableSurvey(
      id: json['id'],
      name: json['name'],
      version: json['version'],
      manifest: json['manifest'],
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      downloadUrl: json['download_url'],
    );
  }
}
```

### Step 12.4: Create App Login Screen

**lib/screens/app_login_screen.dart:**

```dart
import 'package:flutter/material.dart';
import '../services/app_auth_service.dart';

class AppLoginScreen extends StatefulWidget {
  const AppLoginScreen({super.key});

  @override
  State<AppLoginScreen> createState() => _AppLoginScreenState();
}

class _AppLoginScreenState extends State<AppLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _projectCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  final _authService = AppAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _projectCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedCredentials() async {
    final remembered = await _authService.getRememberedCredentials();

    if (remembered['project_code'] != null) {
      _projectCodeController.text = remembered['project_code']!;
    }
    if (remembered['username'] != null) {
      _usernameController.text = remembered['username']!;
    }

    // If both are filled, focus on password
    if (remembered['project_code'] != null && remembered['username'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _passwordFocusNode.requestFocus();
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.login(
        projectCode: _projectCodeController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (result.success) {
        // Remember credentials for next time
        await _authService.rememberCredentials(
          projectCode: _projectCodeController.text,
          username: _usernameController.text,
        );

        if (mounted) {
          // Navigate to survey selector or main screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SurveySelector(surveys: result.surveys!),
            ),
          );
        }
      } else {
        setState(() => _errorMessage = result.error);
      }
    } catch (e) {
      setState(() => _errorMessage = 'An error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Icon(
                      Icons.assignment,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'GiSTKollect',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Data Collection App',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Project Code
                    TextFormField(
                      controller: _projectCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Project Code',
                        hintText: 'e.g., r21-vaccine',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter the project code';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Username
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outlined),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Login button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Step 12.5: Create Survey Selector Screen

**lib/screens/survey_selector_screen.dart:**

```dart
import 'package:flutter/material.dart';
import '../services/app_auth_service.dart';

class SurveySelector extends StatelessWidget {
  final List<AvailableSurvey> surveys;

  const SurveySelector({super.key, required this.surveys});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Survey'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: surveys.isEmpty
          ? const Center(
              child: Text('No surveys available for this project'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: surveys.length,
              itemBuilder: (context, index) {
                final survey = surveys[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      child: Icon(Icons.assignment),
                    ),
                    title: Text(
                      survey.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (survey.version != null)
                          Text('Version: ${survey.version}'),
                        if (survey.updatedAt != null)
                          Text('Updated: ${_formatDate(survey.updatedAt!)}'),
                      ],
                    ),
                    trailing: const Icon(Icons.download),
                    onTap: () => _downloadSurvey(context, survey),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _downloadSurvey(
      BuildContext context, AvailableSurvey survey) async {
    // TODO: Implement download in Phase 13
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${survey.name}...')),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final authService = AppAuthService();
    await authService.logout();

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppLoginScreen()),
      );
    }
  }
}
```

### Step 12.6: Checklist

- [ ] Supabase config file created
- [ ] Supabase initialized in main.dart
- [ ] App auth service created
- [ ] App login screen created
- [ ] Survey selector screen created
- [ ] Login working with Edge Function
- [ ] Credentials remembered after login
- [ ] Logout working

---

## Phase 13: Mobile App - Survey Download

**Estimated time: 2-3 hours**

### Step 13.1: Create Survey Download Service

**lib/services/survey_download_service.dart:**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import '../services/app_auth_service.dart';

class SurveyDownloadService {
  /// Download and extract a survey ZIP file
  Future<SurveyDownloadResult> downloadSurvey(AvailableSurvey survey) async {
    if (survey.downloadUrl == null) {
      return SurveyDownloadResult.failure('No download URL available');
    }

    try {
      // 1. Download ZIP file
      final response = await http.get(Uri.parse(survey.downloadUrl!));

      if (response.statusCode != 200) {
        return SurveyDownloadResult.failure(
            'Download failed: ${response.statusCode}');
      }

      final zipBytes = response.bodyBytes;

      // 2. Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final surveysDir = Directory('${appDir.path}/surveys/${survey.id}');

      // 3. Clear existing survey directory if exists
      if (await surveysDir.exists()) {
        await surveysDir.delete(recursive: true);
      }
      await surveysDir.create(recursive: true);

      // 4. Extract ZIP
      final archive = ZipDecoder().decodeBytes(zipBytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final outputFile = File('${surveysDir.path}/$filename');
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory('${surveysDir.path}/$filename').create(recursive: true);
        }
      }

      // 5. Save survey info
      await _saveSurveyInfo(survey, surveysDir.path);

      return SurveyDownloadResult.success(surveysDir.path);
    } catch (e) {
      return SurveyDownloadResult.failure('Download error: $e');
    }
  }

  /// Save survey metadata for later use
  Future<void> _saveSurveyInfo(AvailableSurvey survey, String path) async {
    final infoFile = File('$path/survey_info.json');
    await infoFile.writeAsString('''
{
  "id": "${survey.id}",
  "name": "${survey.name}",
  "version": "${survey.version ?? ''}",
  "downloaded_at": "${DateTime.now().toIso8601String()}"
}
''');
  }

  /// Get list of downloaded surveys
  Future<List<DownloadedSurvey>> getDownloadedSurveys() async {
    final appDir = await getApplicationDocumentsDirectory();
    final surveysDir = Directory('${appDir.path}/surveys');

    if (!await surveysDir.exists()) {
      return [];
    }

    final surveys = <DownloadedSurvey>[];

    await for (final entity in surveysDir.list()) {
      if (entity is Directory) {
        final manifestFile = File('${entity.path}/survey_manifest.gistx');
        final infoFile = File('${entity.path}/survey_info.json');

        if (await manifestFile.exists()) {
          String? name;
          String? id;

          if (await infoFile.exists()) {
            // Read from info file if available
            final infoJson = await infoFile.readAsString();
            // Parse JSON to get name and id
          }

          surveys.add(DownloadedSurvey(
            id: entity.path.split('/').last,
            name: name ?? 'Unknown Survey',
            path: entity.path,
          ));
        }
      }
    }

    return surveys;
  }

  /// Check if a survey needs update
  Future<bool> needsUpdate(AvailableSurvey available) async {
    final appDir = await getApplicationDocumentsDirectory();
    final infoFile =
        File('${appDir.path}/surveys/${available.id}/survey_info.json');

    if (!await infoFile.exists()) {
      return true; // Not downloaded yet
    }

    // Compare versions or dates
    // For now, just check if it exists
    return false;
  }

  /// Delete a downloaded survey
  Future<void> deleteSurvey(String surveyId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final surveyDir = Directory('${appDir.path}/surveys/$surveyId');

    if (await surveyDir.exists()) {
      await surveyDir.delete(recursive: true);
    }
  }
}

class SurveyDownloadResult {
  final bool success;
  final String? error;
  final String? path;

  SurveyDownloadResult._({required this.success, this.error, this.path});

  factory SurveyDownloadResult.success(String path) {
    return SurveyDownloadResult._(success: true, path: path);
  }

  factory SurveyDownloadResult.failure(String error) {
    return SurveyDownloadResult._(success: false, error: error);
  }
}

class DownloadedSurvey {
  final String id;
  final String name;
  final String path;

  DownloadedSurvey({
    required this.id,
    required this.name,
    required this.path,
  });
}
```

### Step 13.2: Update Survey Selector with Download

**lib/screens/survey_selector_screen.dart** (update the `_downloadSurvey` method):

```dart
Future<void> _downloadSurvey(
    BuildContext context, AvailableSurvey survey) async {
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Downloading survey...'),
        ],
      ),
    ),
  );

  final downloadService = SurveyDownloadService();
  final result = await downloadService.downloadSurvey(survey);

  if (context.mounted) {
    Navigator.pop(context); // Close loading dialog

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${survey.name} downloaded successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to main screen with this survey loaded
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(surveyPath: result.path),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### Step 13.3: Integrate with Existing Survey Loading

Update your existing `SurveyConfigService` to accept a path from downloaded surveys:

```dart
// In your existing survey loading code, add support for loading from
// the downloaded surveys directory instead of just assets
```

### Step 13.4: Checklist

- [ ] Survey download service created
- [ ] Download and extraction working
- [ ] Survey selector triggers download
- [ ] Downloaded surveys can be loaded
- [ ] Downloaded surveys list available

---

## Phase 14: Mobile App - Data Sync

**Estimated time: 4-6 hours**

### Step 14.1: Add Sync Status Column to Database

**lib/services/db_service.dart** - Update table creation:

```dart
// Add sync_status column to all survey tables
// In your _buildCreateTableSql method, add:

String _buildCreateTableSql(String tableName, List<Question> questions) {
  final columns = <String>[];

  for (final q in questions) {
    columns.add('${q.fieldName} ${_sqliteType(q.fieldType)}');
  }

  // Add sync tracking columns
  columns.add('sync_status TEXT DEFAULT "pending"');
  columns.add('last_sync_at TEXT');
  columns.add('server_version INTEGER DEFAULT 0');

  return 'CREATE TABLE IF NOT EXISTS $tableName (${columns.join(', ')})';
}
```

### Step 14.2: Create Supabase Sync Service

**lib/services/supabase_sync_service.dart:**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../config/supabase_config.dart';
import '../services/app_auth_service.dart';

enum SyncStatus {
  pending,
  synced,
  modified,
  error,
}

class SupabaseSyncService {
  final Database db;
  final String surveyPackageId;

  SupabaseSyncService({
    required this.db,
    required this.surveyPackageId,
  });

  /// Get counts of records needing sync
  Future<Map<String, int>> getPendingSyncCounts(List<String> tables) async {
    final counts = <String, int>{};

    for (final table in tables) {
      try {
        final result = await db.rawQuery('''
          SELECT COUNT(*) as count FROM $table
          WHERE sync_status IN ('pending', 'modified', 'error')
        ''');
        counts[table] = Sqflite.firstIntValue(result) ?? 0;
      } catch (e) {
        counts[table] = 0;
      }
    }

    return counts;
  }

  /// Sync all pending records for a table
  Future<SyncResult> syncTable(
    String tableName, {
    void Function(int synced, int total)? onProgress,
  }) async {
    int synced = 0;
    int failed = 0;

    // Get auth token
    final authService = AppAuthService();
    final token = await authService.getToken();

    if (token == null) {
      return SyncResult(synced: 0, failed: 0, total: 0, error: 'Not logged in');
    }

    // Get records needing sync
    final records = await db.query(
      tableName,
      where: 'sync_status IN (?, ?, ?)',
      whereArgs: ['pending', 'modified', 'error'],
    );

    final total = records.length;
    if (total == 0) {
      return SyncResult(synced: 0, failed: 0, total: 0);
    }

    // Prepare submissions
    final submissions = <Map<String, dynamic>>[];

    for (final record in records) {
      final data = Map<String, dynamic>.from(record);

      // Remove sync metadata from data
      final syncStatus = data.remove('sync_status');
      data.remove('last_sync_at');
      final version = (data.remove('server_version') as int?) ?? 0;

      final localUniqueId = data['uniqueid'] as String?;
      if (localUniqueId == null) continue;

      submissions.add({
        'survey_package_id': surveyPackageId,
        'table_name': tableName,
        'record_id': data['subjid'] ?? data['hhid'] ?? localUniqueId,
        'local_unique_id': localUniqueId,
        'data': data,
        'version': syncStatus == 'modified' ? version + 1 : 1,
        'parent_table': data['parent_table'],
        'parent_record_id': data['parent_record_id'],
        'device_id': await _getDeviceId(),
        'app_version': data['swver'],
        'collected_at': data['starttime'],
      });
    }

    // Send to server in batches
    const batchSize = 25;
    for (var i = 0; i < submissions.length; i += batchSize) {
      final batch = submissions.skip(i).take(batchSize).toList();

      try {
        final response = await http.post(
          Uri.parse(SupabaseConfig.appSyncUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': token,
            'submissions': batch,
          }),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          final syncedIds = List<String>.from(result['synced'] ?? []);

          // Mark synced records
          for (final id in syncedIds) {
            await db.update(
              tableName,
              {
                'sync_status': 'synced',
                'last_sync_at': DateTime.now().toIso8601String(),
              },
              where: 'uniqueid = ?',
              whereArgs: [id],
            );
            synced++;
          }

          // Mark failed records
          final failedItems = result['failed'] as List? ?? [];
          for (final item in failedItems) {
            await db.update(
              tableName,
              {'sync_status': 'error'},
              where: 'uniqueid = ?',
              whereArgs: [item['id']],
            );
            failed++;
          }
        } else {
          // Batch failed
          failed += batch.length;
        }

        onProgress?.call(synced + failed, total);
      } catch (e) {
        // Network error - don't mark as error, will retry
        failed += batch.length;
      }
    }

    return SyncResult(synced: synced, failed: failed, total: total);
  }

  /// Sync all tables
  Future<Map<String, SyncResult>> syncAll(
    List<String> tables, {
    void Function(String table, int synced, int total)? onProgress,
  }) async {
    final results = <String, SyncResult>{};

    for (final table in tables) {
      results[table] = await syncTable(
        table,
        onProgress: (synced, total) => onProgress?.call(table, synced, total),
      );
    }

    return results;
  }

  Future<String> _getDeviceId() async {
    // Use existing device ID logic or generate one
    return 'device-${DateTime.now().millisecondsSinceEpoch}';
  }
}

class SyncResult {
  final int synced;
  final int failed;
  final int total;
  final String? error;

  SyncResult({
    required this.synced,
    required this.failed,
    required this.total,
    this.error,
  });

  bool get hasFailures => failed > 0;
  bool get allSucceeded => failed == 0 && synced == total;
}
```

### Step 14.3: Mark Records as Modified on Edit

In your survey saving logic, update sync status when editing:

```dart
// When saving a record
Future<void> saveRecord(String tableName, Map<String, dynamic> data) async {
  final uniqueId = data['uniqueid'];

  // Check if record exists
  final existing = await db.query(
    tableName,
    where: 'uniqueid = ?',
    whereArgs: [uniqueId],
  );

  if (existing.isNotEmpty) {
    // Existing record - check if it was synced
    final currentSyncStatus = existing.first['sync_status'];

    if (currentSyncStatus == 'synced') {
      data['sync_status'] = 'modified';
    }
    // If pending/error, keep as is

    data['lastmod'] = DateTime.now().toIso8601String();

    await db.update(
      tableName,
      data,
      where: 'uniqueid = ?',
      whereArgs: [uniqueId],
    );
  } else {
    // New record
    data['sync_status'] = 'pending';
    await db.insert(tableName, data);
  }
}
```

### Step 14.4: Create Sync Screen

**lib/screens/sync_screen.dart:**

```dart
import 'package:flutter/material.dart';
import '../services/supabase_sync_service.dart';
import '../services/db_service.dart';

class SyncScreen extends StatefulWidget {
  final DbService dbService;
  final String surveyPackageId;
  final List<String> tableNames;

  const SyncScreen({
    super.key,
    required this.dbService,
    required this.surveyPackageId,
    required this.tableNames,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  Map<String, int> _pendingCounts = {};
  Map<String, SyncResult>? _syncResults;
  bool _isSyncing = false;
  String _currentTable = '';
  int _currentProgress = 0;
  int _currentTotal = 0;

  late SupabaseSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _initSyncService();
  }

  Future<void> _initSyncService() async {
    final db = await widget.dbService.database;
    _syncService = SupabaseSyncService(
      db: db,
      surveyPackageId: widget.surveyPackageId,
    );
    await _loadPendingCounts();
  }

  Future<void> _loadPendingCounts() async {
    final counts = await _syncService.getPendingSyncCounts(widget.tableNames);
    setState(() => _pendingCounts = counts);
  }

  Future<void> _startSync() async {
    setState(() {
      _isSyncing = true;
      _syncResults = null;
    });

    final results = await _syncService.syncAll(
      widget.tableNames,
      onProgress: (table, synced, total) {
        setState(() {
          _currentTable = table;
          _currentProgress = synced;
          _currentTotal = total;
        });
      },
    );

    setState(() {
      _isSyncing = false;
      _syncResults = results;
    });

    await _loadPendingCounts();
  }

  @override
  Widget build(BuildContext context) {
    final totalPending = _pendingCounts.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Records to Sync',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$totalPending',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: totalPending > 0 ? Colors.orange : Colors.green,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Per-table breakdown
            Text('By Form:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),

            ..._pendingCounts.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key),
                      Chip(
                        label: Text('${e.value}'),
                        backgroundColor:
                            e.value > 0 ? Colors.orange.shade100 : Colors.green.shade100,
                      ),
                    ],
                  ),
                )),

            const SizedBox(height: 24),

            // Progress (when syncing)
            if (_isSyncing) ...[
              Text('Syncing $_currentTable...'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _currentTotal > 0 ? _currentProgress / _currentTotal : null,
              ),
              const SizedBox(height: 4),
              Text('$_currentProgress / $_currentTotal'),
              const SizedBox(height: 24),
            ],

            // Results
            if (_syncResults != null)
              Card(
                color: _hasAnyFailures ? Colors.orange.shade50 : Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasAnyFailures
                            ? 'Sync Completed with Errors'
                            : 'Sync Complete',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._syncResults!.entries.map((e) => Text(
                            '${e.key}: ${e.value.synced} synced, ${e.value.failed} failed',
                          )),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // Sync button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing || totalPending == 0 ? null : _startSync,
                icon: Icon(_isSyncing ? Icons.hourglass_top : Icons.cloud_upload),
                label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasAnyFailures =>
      _syncResults?.values.any((r) => r.hasFailures) ?? false;
}
```

### Step 14.5: Checklist

- [ ] Sync status column added to database
- [ ] Supabase sync service created
- [ ] Records marked as modified on edit
- [ ] Sync screen created
- [ ] Batch sync working
- [ ] Progress indication working
- [ ] Error handling working

---

## Phase 15: Testing & Deployment

**Estimated time: 4-6 hours**

### Step 15.1: End-to-End Testing

**Test the complete workflow:**

1. **Web App:**
   - [ ] Register new account
   - [ ] Create project
   - [ ] Upload survey (when implemented)
   - [ ] Create app credentials
   - [ ] View credentials

2. **Mobile App:**
   - [ ] Login with project code + credentials
   - [ ] Download survey
   - [ ] Collect data offline
   - [ ] Edit existing record
   - [ ] Sync data to server

3. **Web App (continued):**
   - [ ] View synced data
   - [ ] Export to CSV
   - [ ] View reports

### Step 15.2: Build Web App for Production

```powershell
cd C:\GeoffOffline\gistkollect_web

# Build for web
flutter build web --release

# Output is in build/web/
```

### Step 15.3: Deploy Web App

**Option A: Vercel**

```powershell
# Install Vercel CLI
npm install -g vercel

# Deploy
cd build/web
vercel

# Follow prompts to link to your Vercel account
```

**Option B: Firebase Hosting**

```powershell
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize (select Hosting)
firebase init

# Build and deploy
flutter build web
firebase deploy
```

### Step 15.4: Configure Domain

1. In your hosting provider (Vercel/Firebase), add custom domain
2. Update DNS records at your domain registrar:
   - Type: A or CNAME
   - Name: @ (or www)
   - Value: (provided by hosting provider)

3. Wait for DNS propagation (up to 48 hours)

4. Enable HTTPS (usually automatic)

### Step 15.5: Update Supabase Settings

1. Go to Supabase Dashboard > Authentication > URL Configuration
2. Add your domain to:
   - Site URL: `https://gistkollect.org`
   - Redirect URLs: `https://gistkollect.org/**`

### Step 15.6: Build Mobile Apps

**Android:**

```powershell
cd C:\GeoffOffline\GiSTX

# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# Output: build/app/outputs/flutter-apk/app-release.apk
# Output: build/app/outputs/bundle/release/app-release.aab
```

**Windows:**

```powershell
flutter build windows --release

# Output: build/windows/x64/runner/Release/

# Create installer with Inno Setup (if configured)
```

### Step 15.7: Final Checklist

**Backend:**
- [ ] Supabase database schema complete
- [ ] Storage buckets configured
- [ ] Edge Functions deployed
- [ ] RLS policies working

**Web App:**
- [ ] Authentication working
- [ ] Project management working
- [ ] Team management working
- [ ] Credential management working
- [ ] Data viewing working
- [ ] Deployed to production URL

**Mobile App:**
- [ ] Renamed to GiSTKollect
- [ ] Login with project credentials working
- [ ] Survey download working
- [ ] Data collection working (offline)
- [ ] Sync to Supabase working
- [ ] APK built for distribution

**Domain:**
- [ ] Domain configured and working
- [ ] HTTPS enabled

---

## Post-Launch Tasks

### Monitoring

1. Set up error tracking (Sentry, Firebase Crashlytics)
2. Monitor Supabase usage in dashboard
3. Set up alerts for high usage

### Documentation

1. Create user guide for web app
2. Create user guide for mobile app
3. Document API if needed

### Backup

1. Enable Supabase Point-in-Time Recovery (Pro plan)
2. Set up regular database exports

### Future Enhancements

- [ ] QR code login
- [ ] Visual survey builder
- [ ] Advanced reporting
- [ ] Data validation rules
- [ ] Push notifications for sync reminders

---

## Troubleshooting

### Common Issues

**"Invalid credentials" on app login:**
- Check project code is correct (lowercase)
- Verify credential is active in web admin
- Check password was entered correctly

**Sync fails:**
- Check internet connection
- Verify token hasn't expired (re-login)
- Check Supabase Edge Function logs

**Survey download fails:**
- Signed URL may have expired (re-login to get new URLs)
- Check storage bucket policies

**Web app shows blank:**
- Check browser console for errors
- Verify Supabase URL and keys are correct

### Getting Help

- Supabase Documentation: https://supabase.com/docs
- Flutter Documentation: https://docs.flutter.dev
- Stack Overflow for specific errors

---

*GiSTKollect Implementation Plan - Complete*
*Version 1.0.0*
