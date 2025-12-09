// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../services/theme_service.dart';

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

  bool _isLoading = true;
  bool _obscurePassword = true;
  String _appVersion = '';

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
        _appVersion = packageInfo.version;
      });
    }
  }

  @override
  void dispose() {
    _surveyorIdController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final surveyorId = await _settingsService.surveyorId;
    // ftpHost is no longer used in UI
    final ftpUsername = await _settingsService.ftpUsername;
    final ftpPassword = await _settingsService.ftpPassword;

    if (mounted) {
      setState(() {
        _surveyorIdController.text = surveyorId ?? '';
        _ftpUsernameController.text = ftpUsername ?? '';
        _ftpPasswordController.text = ftpPassword ?? '';

        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _settingsService.saveAllSettings(
          surveyorId: _surveyorIdController.text.trim(),
          ftpHost: '', // Host is hidden/hardcoded, passing empty for now
          ftpUsername: _ftpUsernameController.text.trim(),
          ftpPassword: _ftpPasswordController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving settings: $e'),
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
        title: const Text('Settings'),
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
              child: const Text('Save'),
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
                        Text(_themeService.isDarkMode ? 'Dark Mode' : 'Light Mode'),
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
                      'User Settings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _surveyorIdController,
                      decoration: const InputDecoration(
                        labelText: 'Surveyor ID',
                        hintText: 'Enter your surveyor ID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Surveyor ID is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Server Credentials',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your credentials to access the survey server.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ftpUsernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'Enter username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_circle),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ftpPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter password',
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
                      'Manage Surveys',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showDeleteSurveyDialog,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Delete Survey',
                          style: TextStyle(color: Colors.red)),
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
        const SnackBar(content: Text('No surveys installed to delete.')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Survey'),
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
                        title: const Text('Confirm Deletion'),
                        content: Text(
                            'Are you sure you want to delete "$surveyName"?\n\n'
                            'This will remove the survey definition and source zip.\n'
                            'Collected data (database) will NOT be deleted.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
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
                              content: Text('Deleted "$surveyName"'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error deleting survey: $e'),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
