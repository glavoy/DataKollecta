import 'dart:io';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/http_service.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _httpService = HttpService();
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();

  bool _isConnecting = false;
  List<SurveyMetadata> _remoteSurveys = [];
  String? _downloadingSurvey;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
  }

  Future<({String deviceId, String deviceInfo})> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      final deviceId = androidInfo.id;
      final deviceInfo = 'Brand: ${androidInfo.brand}, Model: ${androidInfo.model}';
      return (deviceId: deviceId, deviceInfo: deviceInfo);
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfoPlugin.windowsInfo;
      final deviceId = windowsInfo.deviceId;
      final deviceInfo = 'Windows: ${windowsInfo.productName}, ${windowsInfo.computerName}, Cores: ${windowsInfo.numberOfCores}';
      return (deviceId: deviceId, deviceInfo: deviceInfo);
    } else {
      return (deviceId: 'unknown', deviceInfo: 'Unknown Platform');
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to server...';
      _remoteSurveys = [];
    });

    try {
      // Get API credentials
      final apiCreds = await _settingsService.getApiCredentials();

      if (apiCreds == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Please configure API credentials in Settings first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final username = apiCreds['username']!;
      final password = apiCreds['password']!;
      final projectCode = apiCreds['projectCode']!;

      setState(() => _statusMessage = 'Gathering device info...');

      // Get device information
      final deviceData = await _getDeviceInfo();

      setState(() => _statusMessage = 'Authenticating...');

      // Authenticate and get survey list
      final result = await _httpService.authenticate(
        username,
        password,
        projectCode,
        deviceId: deviceData.deviceId,
        deviceInfo: deviceData.deviceInfo,
      );

      // Save the auth token
      await _settingsService.setAuthToken(result.token);

      setState(() {
        _remoteSurveys = result.surveys;
        _statusMessage = result.surveys.isEmpty
            ? 'No surveys available.'
            : 'Found ${result.surveys.length} surveys.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _downloadSurvey(SurveyMetadata survey) async {
    setState(() {
      _downloadingSurvey = survey.name;
    });

    try {
      // Download using the signed URL
      final file = await _httpService.downloadSurveyZip(
        survey.downloadUrl,
        survey.name,
      );

      if (file != null) {
        // Extract the survey and associate credentials
        await _associateCredentialsWithDownloadedSurvey(survey.name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded ${survey.name} successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Download failed.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading ${survey.name}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingSurvey = null;
        });
      }
    }
  }

  Future<void> _associateCredentialsWithDownloadedSurvey(
      String surveyName) async {
    try {
      // Extract zip first (it's in the zips folder)
      await _surveyConfig.initializeSurveys();

      // Get the surveyId for this survey
      final surveyId = await _surveyConfig.getSurveyId(surveyName);

      if (surveyId != null) {
        // Get API credentials to associate with this survey
        final apiCreds = await _settingsService.getApiCredentials();
        if (apiCreds != null) {
          await _settingsService.setSurveyCredentials(
              surveyId, apiCreds['username']!, apiCreds['password']!);
          debugPrint('[SyncScreen] Saved credentials for survey: $surveyId');
        }
      }
    } catch (e) {
      debugPrint('[SyncScreen] Error associating credentials: $e');
    }
  }

  Future<void> _uploadData() async {
    // TODO: Implement new row-by-row sync upload mechanism
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload functionality will be implemented with row-by-row sync'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Center'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
                context, 'Get New/Updated Surveys', Icons.download),
            const SizedBox(height: 16),
            _buildDownloadSection(context),
            const SizedBox(height: 32),
            _buildSectionHeader(context, 'Upload Data', Icons.upload),
            const SizedBox(height: 16),
            _buildUploadSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
        ),
      ],
    );
  }

  Widget _buildDownloadSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Connect to the server to check for new or updated survey forms.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isConnecting ? null : _checkForUpdates,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label:
                  Text(_isConnecting ? 'Connecting...' : 'Check for Updates'),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusMessage!.startsWith('Error')
                      ? Colors.red
                      : Colors.grey[700],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_remoteSurveys.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _remoteSurveys.length,
                itemBuilder: (context, index) {
                  final survey = _remoteSurveys[index];
                  final isDownloading = _downloadingSurvey == survey.name;
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(survey.name),
                    trailing: isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: _downloadingSurvey != null
                                ? null
                                : () => _downloadSurvey(survey),
                          ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload finalized records to the server (row-by-row sync).',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _uploadData,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload Data'),
            ),
            const SizedBox(height: 8),
            Text(
              'Row-by-row sync coming soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
