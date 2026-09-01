// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../services/sync/http_sync_backend.dart';
import '../services/sync/project_sessions.dart';
import '../services/sync/sync_backend.dart';
import '../services/theme_service.dart';
import '../config/app_config.dart';
import '../services/app_strings.dart';
import '../services/app_strings_http_sync.dart';
import 'sync_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settingsService = SettingsService();
  final _syncBackend = HttpSyncBackend();
  late final ThemeService _themeService;

  // Controllers for text fields. Username/password are FTP-only now --
  // DataKollecta has no single global project credential anymore, each
  // project's own username/password lives in the projects list below.
  final _surveyorIdController = TextEditingController();
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _obscurePassword = true;
  String _appVersion = '';

  // DataKollecta project list.
  List<ProjectSession> _projects = [];
  bool _projectsLoading = false;

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
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (AppConfig.isDataKollecta) {
      await _loadProjects();
    } else {
      // Settings is a pure staging area: it always shows exactly what was
      // last typed and saved here, never something survey-specific --
      // showing a survey's own stored values here (tried earlier this
      // session) meant navigating away and back without downloading
      // anything made a just-typed, just-saved edit appear to vanish (it
      // hadn't -- it was still in this global slot, just not displayed),
      // which reads as data loss. A survey's actual association is only
      // ever visible/correct via Sync Center or the credentials an upload
      // actually uses.
      final surveyorId = await _settingsService.surveyorId;
      final username = await _settingsService.ftpUsername;
      final password = await _settingsService.ftpPassword;

      if (mounted) {
        setState(() {
          _surveyorIdController.text = surveyorId ?? '';
          _ftpUsernameController.text = username ?? '';
          _ftpPasswordController.text = password ?? '';
        });
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProjects() async {
    setState(() => _projectsLoading = true);
    final doc = await _syncBackend.loadDocument();
    if (mounted) {
      setState(() {
        _projects = doc.sessions.values.toList()
          ..sort((a, b) => a.projectCode.compareTo(b.projectCode));
        _projectsLoading = false;
      });
    }
  }

  /// Only the FTP branch has anything left in the staged form -- every
  /// DataKollecta project is added/removed immediately, the same way the
  /// dark-mode toggle and survey deletion already are.
  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      try {
        // Only ever updates the global "next download" slot -- a survey's
        // own record is written exclusively by a successful download
        // (_associateCredentialsWithDownloadedSurvey in sync_screen.dart),
        // never from here. Writing here too used to overwrite whichever
        // survey happened to still be active with credentials typed for a
        // DIFFERENT survey not yet downloaded -- the normal "prepare
        // credentials, then download" workflow, not a corner case.
        await _settingsService.saveAllSettings(
          surveyorId: _surveyorIdController.text.trim(),
          ftpHost: '',
          ftpUsername: _ftpUsernameController.text.trim(),
          ftpPassword: _ftpPasswordController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_s.settingsSaved),
              backgroundColor: Colors.green,
            ),
          );
          // Saving credentials is almost always in service of downloading a
          // survey next -- go straight to Sync Center instead of back to
          // the main screen, since that's the immediate next step.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SyncScreen()),
          );
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

  Future<void> _showAddProjectDialog() async {
    final codeController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;
    var submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_httpSync.addProject),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: _httpSync.projectCode,
                    hintText: _httpSync.projectCodeHint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? _httpSync.projectCodeRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: _s.username,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? _s.error : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: _s.password,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? _s.error : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(_s.cancel),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => submitting = true);
                      final projectCode = codeController.text.trim();
                      try {
                        await _syncBackend.addProject(
                          projectCode,
                          usernameController.text.trim(),
                          passwordController.text,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(_httpSync.projectAdded(projectCode)),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        await _loadProjects();
                      } on SyncConnectionException {
                        setDialogState(() => submitting = false);
                        if (!dialogContext.mounted) return;
                        final saveAnyway = await showDialog<bool>(
                          context: dialogContext,
                          builder: (c) => AlertDialog(
                            content: Text(_httpSync.savingAnywayNoConnection),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(_s.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(_httpSync.saveAnyway),
                              ),
                            ],
                          ),
                        );
                        if (saveAnyway == true) {
                          // Stored without a token; resolveToken will try a
                          // real login the first time this project's survey
                          // is uploaded, once back online.
                          await ProjectSessionsRepository.shared.update(
                            (d) => d.withSession(ProjectSession(
                              projectCode: projectCode,
                              username: usernameController.text.trim(),
                              password: passwordController.text,
                            )),
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await _loadProjects();
                        }
                      } on SyncException catch (e) {
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_s.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeProject(ProjectSession session) async {
    final pendingCount =
        await _syncBackend.pendingCountForProject(session.projectCode);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_httpSync.removeProject),
        content: Text(
            _httpSync.removeProjectWarning(session.projectCode, pendingCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_s.cancel),
          ),
          if (pendingCount > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_httpSync.uploadFirst),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_httpSync.removeAnyway),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncBackend.removeProject(session.projectCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_httpSync.projectRemoved(session.projectCode)),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadProjects();
    }
  }

  Widget _buildProjectsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              _httpSync.projects,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_projectsLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _httpSync.noProjectsConfigured,
              style: const TextStyle(color: Colors.grey),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final session in _projects)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(session.projectName ?? session.projectCode),
                    subtitle: Text(session.projectCode),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _removeProject(session),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _showAddProjectDialog,
          icon: const Icon(Icons.add),
          label: Text(_httpSync.addProject),
        ),
      ],
    );
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
          // DataKollecta has nothing left in the staged form -- every
          // project and the survey list are both immediate-apply -- so the
          // Save button only makes sense for GiSTX/FTP's surveyor
          // id/username/password fields.
          if (!AppConfig.isDataKollecta)
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
                      _buildProjectsSection(context),
                    ] else ...[
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
                      const SizedBox(height: 4),
                      Text(
                        _s.lastSavedCredentials,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
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
