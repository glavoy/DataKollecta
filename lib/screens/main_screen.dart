import 'dart:io';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../config/app_config.dart';
import '../services/app_strings.dart';
import 'questionnaire_selector_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'sync_screen_http.dart';
import 'summary_statistics_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();
  final List<String> _availableSurveys = [];
  String _surveyName = 'Select a Survey';
  bool _isLoading = true;
  static const AppStrings _s = AppStrings(AppConfig.isFrench);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _surveyConfig.initializeSurveys();
    await _loadAvailableSurveys();
    await _loadSurveyName();
  }

  Future<void> _loadSurveyName() async {
    final activeSurvey = await _settingsService.activeSurvey;

    String displayName = _s.selectASurvey;
    if (activeSurvey != null && activeSurvey.isNotEmpty) {
      if (_availableSurveys.contains(activeSurvey)) {
        displayName = activeSurvey;
      } else {
        // Active survey not found (maybe deleted), clear it
        await _settingsService.setActiveSurvey('');
      }
    }

    if (mounted) {
      setState(() {
        _surveyName = displayName;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAvailableSurveys() async {
    try {
      debugPrint('Scanning for surveys...');
      final surveys = await _surveyConfig.getAvailableSurveys();

      if (mounted) {
        setState(() {
          _availableSurveys.clear();
          _availableSurveys.addAll(surveys);
        });
      }
      debugPrint('Found ${surveys.length} surveys: $surveys');

      // Auto-select if only one survey is available
      if (surveys.length == 1) {
        final currentSurvey = await _settingsService.activeSurvey;
        // Only auto-select if no survey is currently selected or the current one is invalid
        if (currentSurvey == null || currentSurvey.isEmpty || !surveys.contains(currentSurvey)) {
          debugPrint('Auto-selecting single available survey: ${surveys[0]}');
          await _settingsService.setActiveSurvey(surveys[0]);
          await _loadSurveyName();
        }
      }
    } catch (e) {
      debugPrint('Error scanning for surveys: $e');
    }
  }

  Future<void> _changeSurvey() async {
    if (_availableSurveys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.noSurveysAvailable)),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_s.selectActiveSurvey),
        children: _availableSurveys.map((survey) {
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await _settingsService.setActiveSurvey(survey);
              await _loadSurveyName();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                survey,
                style: TextStyle(
                  fontWeight: survey == _surveyName
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: survey == _surveyName
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: _s.tooltipStatistics,
            onPressed: () => _navigateToStatistics(context),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            tooltip: _s.tooltipSyncCenter,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AppConfig.isDataKollecta
                      ? const HttpSyncScreen()
                      : const SyncScreen(),
                ),
              );
              // Re-initialize to extract any new zips
              await _surveyConfig.initializeSurveys();
              await _loadAvailableSurveys();
              await _loadSurveyName();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: _s.tooltipSettings,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
              await _loadAvailableSurveys();
              await _loadSurveyName();
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: _s.tooltipExit,
            onPressed: () {
              exit(0);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  // Centered logo
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        AppConfig.brandingAsset,
                        width: 120,
                        height: 120,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Current Survey Card
                  Card(
                    elevation: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                      ),
                    ),
                    child: InkWell(
                      onTap: _changeSurvey,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              _s.currentProject,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    _surveyName,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),
                  FilledButton.icon(
                    onPressed: () async {
                      // Check if settings are configured
                      final isConfigured =
                          await _surveyConfig.areSettingsConfigured();

                      if (!isConfigured) {
                        _showSettingsRequiredDialog(context);
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const QuestionnaireSelectorScreen(
                            isModifyMode: false,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(_s.newSurvey),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Check if settings are configured
                      final isConfigured =
                          await _surveyConfig.areSettingsConfigured();

                      if (!isConfigured) {
                        _showSettingsRequiredDialog(context);
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const QuestionnaireSelectorScreen(
                            isModifyMode: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(_s.modifyExistingSurvey),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToStatistics(BuildContext context) async {
    // Check if settings are configured
    final isConfigured = await _surveyConfig.areSettingsConfigured();

    if (!isConfigured) {
      if (context.mounted) _showSettingsRequiredDialog(context);
      return;
    }

    // Get active survey ID
    final activeSurvey = await _settingsService.activeSurvey;
    if (activeSurvey == null || activeSurvey.isEmpty) {
      if (context.mounted) _showSettingsRequiredDialog(context);
      return;
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SummaryStatisticsScreen(
            surveyId: activeSurvey,
          ),
        ),
      );
    }
  }

  void _showSettingsRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings, color: Colors.orange),
            const SizedBox(width: 8),
            Text(_s.settingsRequired),
          ],
        ),
        content: Text(_s.settingsRequiredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
              _loadSurveyName();
            },
            child: Text(_s.goToSettings),
          ),
        ],
      ),
    );
  }
}
