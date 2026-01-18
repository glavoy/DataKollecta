import 'dart:io';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/http_service.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../services/sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _httpService = HttpService();
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();
  final _syncService = SyncService();

  bool _isConnecting = false;
  bool _isUploading = false;
  List<SurveyMetadata> _remoteSurveys = [];
  String? _downloadingSurvey;
  String? _statusMessage;
  String? _uploadStatusMessage;
  Map<String, int> _unsyncedCounts = {};
  int _totalUnsyncedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnsyncedCounts();
  }

  Future<void> _loadUnsyncedCounts() async {
    try {
      final surveyId = await _surveyConfig.getActiveSurveyId();
      if (surveyId == null) return;

      final counts = await _syncService.getAllUnsyncedCounts(surveyId);
      if (mounted) {
        setState(() {
          _unsyncedCounts = counts;
          _totalUnsyncedCount = counts.values.fold(0, (sum, count) => sum + count);
        });
      }
    } catch (e) {
      debugPrint('[SyncScreen] Error loading unsynced counts: $e');
    }
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
      setState(() => _statusMessage = _getUserFriendlyErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final message = error.toString();
    
    if (message.contains('Project not found') || message.contains('404')) {
      return 'Project code not found. Please check your settings.';
    }
    
    if (message.contains('Authentication failed') || message.contains('401') || message.contains('403')) {
      return 'Authentication failed. Please check your username and password.';
    }
    
    if (message.contains('SocketException') || message.contains('Network is unreachable') || message.contains('Connection refused')) {
      return 'Network error. Please check your internet connection.';
    }
    
    // Clean up standard exception prefixes if present
    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }
    
    return message;
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
    if (_isUploading) return;

    // Check if there's anything to upload
    if (_totalUnsyncedCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No records to upload. All data is synced.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    // Get survey ID
    final surveyId = await _surveyConfig.getActiveSurveyId();
    if (surveyId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No survey selected. Please select a survey first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Get device info
    final deviceData = await _getDeviceInfo();

    setState(() {
      _isUploading = true;
      _uploadStatusMessage = 'Starting upload...';
    });

    try {
      final result = await _syncService.uploadAllData(
        surveyId: surveyId,
        deviceId: deviceData.deviceId,
        onProgress: (tableName, current, total, status) {
          if (mounted) {
            setState(() {
              if (tableName.isNotEmpty) {
                _uploadStatusMessage = '$tableName: $status';
              } else {
                _uploadStatusMessage = status;
              }
            });
          }
        },
      );

      // Refresh counts
      await _loadUnsyncedCounts();

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusMessage = null;
        });

        if (result.hasErrors) {
          // Show error dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Upload Completed with Errors'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Synced: ${result.syncedCount} records'),
                  Text('Failed: ${result.failedCount} records'),
                  const SizedBox(height: 8),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...result.errors.take(5).map((e) => Text(
                        '- ${e.message}',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      )),
                  if (result.errors.length > 5)
                    Text('... and ${result.errors.length - 5} more errors'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else if (result.syncedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully uploaded ${result.syncedCount} records!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No records were uploaded.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SyncScreen] Upload error: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getUserFriendlyErrorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
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
              'Upload collected data to the server.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Show unsynced counts
            if (_unsyncedCounts.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _totalUnsyncedCount > 0
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _totalUnsyncedCount > 0
                        ? Colors.orange.shade200
                        : Colors.green.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _totalUnsyncedCount > 0
                              ? Icons.cloud_off
                              : Icons.cloud_done,
                          size: 20,
                          color: _totalUnsyncedCount > 0
                              ? Colors.orange.shade700
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _totalUnsyncedCount > 0
                              ? '$_totalUnsyncedCount records pending upload'
                              : 'All records synced',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _totalUnsyncedCount > 0
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (_totalUnsyncedCount > 0) ...[
                      const SizedBox(height: 8),
                      ..._unsyncedCounts.entries
                          .where((e) => e.value > 0)
                          .map((e) => Padding(
                                padding: const EdgeInsets.only(left: 28),
                                child: Text(
                                  '${e.key}: ${e.value}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Upload button
            FilledButton.icon(
              onPressed: _isUploading ? null : _uploadData,
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isUploading ? 'Uploading...' : 'Upload Data'),
            ),

            // Upload status message
            if (_uploadStatusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _uploadStatusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                ),
              ),
            ],

            // Refresh button
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isUploading ? null : _loadUnsyncedCounts,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Counts'),
            ),
          ],
        ),
      ),
    );
  }
}
