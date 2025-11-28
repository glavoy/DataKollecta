// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settingsService = SettingsService();

  // Controllers for text fields
  final _surveyorIdController = TextEditingController();
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSettings();
  }

  @override
  void dispose() {
    _surveyorIdController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
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
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'User Settings',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Server Credentials',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 32),
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
