// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../services/theme_service.dart';
import '../config/app_config.dart';
import '../services/app_strings.dart';
import '../services/app_strings_http_sync.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settingsService = SettingsService();
  late final ThemeService _themeService;

  // Controllers for text fields
  final _surveyorIdController = TextEditingController();
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();
  final _projectCodeController = TextEditingController();

  bool _isLoading = true;
  bool _obscurePassword = true;
  String _appVersion = '';
  static const AppStrings _s = AppStrings(AppConfig.isFrench);
  static const HttpSyncStrings _httpSync = HttpSyncStrings();

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _themeService.addListener(_onThemeChanged);
    _initialize();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await _loadSettings();
    await _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        // The build number is what separates two test builds of the same
        // unreleased version, so it belongs on the screen an interviewer reads
        // out when reporting a problem -- not just in pubspec.yaml.
        _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      });
    }
  }

  @override
  void dispose() {
    _surveyorIdController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _projectCodeController.dispose();
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final String? username;
    final String? password;
    if (AppConfig.isDataKollecta) {
      username = await _settingsService.apiUsername;
      password = await _settingsService.apiPassword;
      _projectCodeController.text = await _settingsService.projectCode ?? '';
    } else {
      final surveyorId = await _settingsService.surveyorId;
      _surveyorIdController.text = surveyorId ?? '';
      username = await _settingsService.ftpUsername;
      password = await _settingsService.ftpPassword;
    }

    if (mounted) {
      setState(() {
        _ftpUsernameController.text = username ?? '';
        _ftpPasswordController.text = password ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      try {
        if (AppConfig.isDataKollecta) {
          await _settingsService.setApiUsername(_ftpUsernameController.text.trim());
          await _settingsService.setApiPassword(_ftpPasswordController.text);
          await _settingsService.setProjectCode(_projectCodeController.text.trim());
        } else {
          await _settingsService.saveAllSettings(
            surveyorId: _surveyorIdController.text.trim(),
            ftpHost: '',
            ftpUsername: _ftpUsernameController.text.trim(),
            ftpPassword: _ftpPasswordController.text,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_s.settingsSaved),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_s.errorSavingSettings(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_s.settings),
        actions: [
          if (_appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(
                  'v$_appVersion',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: FilledButton.tonal(
              onPressed: _saveSettings,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(_s.save),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Dark Mode Toggle
                    Row(
                      children: [
                        const Spacer(),
                        Icon(
                          _themeService.isDarkMode
                              ? Icons.dark_mode
                              : Icons.light_mode,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(_themeService.isDarkMode ? _s.darkMode : _s.lightMode),
                        const SizedBox(width: 8),
                        Switch(
                          value: _themeService.isDarkMode,
                          onChanged: (value) async {
                            await _themeService.toggleTheme();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      _s.userSettings,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    // Surveyor ID only feeds GiSTX's FTP upload filename (see
                    // sync_screen.dart) -- DataKollecta's HTTP sync never
                    // reads it, so it's not shown on that product.
                    if (!AppConfig.isDataKollecta) ...[
                      TextFormField(
                        controller: _surveyorIdController,
                        decoration: InputDecoration(
                          labelText: _s.surveyorId,
                          hintText: _s.enterSurveyorId,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return _s.surveyorIdRequired;
                          }
                          return null;
                        },
                      ),
                    ],
                    // The country is fixed when the app is built, so there is
                    // nothing to choose. Shown only on country-specific builds
                    // so a mis-built APK is obvious; the plain build shows
                    // nothing at all.
                    if (!AppConfig.isDefaultCountry) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.flag, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${_s.selectCountry}: ${AppConfig.country}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (AppConfig.isDataKollecta) ...[
                      TextFormField(
                        controller: _projectCodeController,
                        decoration: InputDecoration(
                          labelText: _httpSync.projectCode,
                          hintText: _httpSync.enterProjectCode,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return _httpSync.projectCodeRequired;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _ftpUsernameController,
                      decoration: InputDecoration(
                        labelText: _s.username,
                        hintText: _s.enterUsername,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.account_circle),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ftpPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: _s.password,
                        hintText: _s.enterPassword,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      _s.manageSurveys,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showDeleteSurveyDialog,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: Text(_s.deleteSurvey,
                          style: const TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteSurveyDialog() async {
    final surveyConfig = SurveyConfigService();
    final surveys = await surveyConfig.getAvailableSurveys();

    if (!mounted) return;

    if (surveys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.noSurveysToDelete)),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_s.deleteSurvey),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: surveys.length,
            itemBuilder: (context, index) {
              final surveyName = surveys[index];
              return ListTile(
                title: Text(surveyName),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    // Confirm deletion
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(_s.confirmDeletion),
                        content: Text(_s.confirmDeleteMessage(surveyName)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(_s.cancel),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(_s.delete),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      try {
                        await surveyConfig.deleteSurvey(surveyName);
                        if (context.mounted) {
                          Navigator.pop(context); // Close list dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_s.deletedSurvey(surveyName)),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_s.errorDeletingSurvey(e)),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s.close),
          ),
        ],
      ),
    );
  }
}
