import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _ftpService = FtpService(); // Used for uploads only
  final _httpService = HttpService(); // Used for downloads
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();

  bool _isConnecting = false;
  bool _isUploading = false;
  List<SurveyMetadata> _remoteSurveys = []; // Changed from List<String>
  String? _downloadingSurvey;
  String? _statusMessage;
  String? _activeSurveyName;

  DateTime? _lastUploadTime;

  @override
  void initState() {
    super.initState();
    _loadActiveSurvey();
  }

  Future<void> _loadActiveSurvey() async {
    final name = await _settingsService.activeSurvey;
    if (mounted) {
      setState(() {
        _activeSurveyName = name;
      });
      _loadLastUploadTime();
    }
  }

  Future<void> _loadLastUploadTime() async {
    if (_activeSurveyName == null) return;
    final surveyId = await _surveyConfig.getSurveyId(_activeSurveyName!);
    if (surveyId != null) {
      try {
        final outboxDir = await _surveyConfig.getOutboxDirectory();
        if (!await outboxDir.exists()) {
          if (mounted) setState(() => _lastUploadTime = null);
          return;
        }

        final files = await outboxDir.list().toList();
        final surveyFiles = files.where((f) {
          final name = p.basename(f.path);
          return f is File &&
              name.startsWith(surveyId) &&
              name.endsWith('.zip');
        }).toList();

        if (surveyFiles.isEmpty) {
          if (mounted) setState(() => _lastUploadTime = null);
          return;
        }

        // Sort by modification time (descending)
        surveyFiles.sort((a, b) {
          return b.statSync().modified.compareTo(a.statSync().modified);
        });

        final lastFile = surveyFiles.first;
        final lastMod = lastFile.statSync().modified;

        if (mounted) {
          setState(() {
            _lastUploadTime = lastMod;
          });
        }
      } catch (e) {
        debugPrint('Error loading last upload time: $e');
      }
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
    setState(() {
      _isUploading = true;
    });

    try {
      final surveyorId = await _settingsService.surveyorId;
      final surveyName = await _settingsService.activeSurvey;

      if (surveyorId == null || surveyName == null) {
        throw Exception('Missing settings (Surveyor ID or Active Survey).');
      }

      // 1. Get Survey ID and DB Path
      final surveyId = await _surveyConfig.getSurveyId(surveyName);
      if (surveyId == null)
        throw Exception('Could not find ID for survey: $surveyName');

      // 2. Get credentials for THIS survey (survey-specific or falls back to global)
      final credentials =
          await _settingsService.getCredentialsForSurvey(surveyId);
      if (credentials == null) {
        throw Exception('No credentials available for this survey.');
      }

      final username = credentials['username']!;
      final password = credentials['password']!;

      // 3. Get DB Path
      final baseDir = await _surveyConfig.getSurveysDirectory();
      // Go up one level from surveys to get to DataKollecta root, then into databases
      final datakollectDir = baseDir.parent;
      final dbPath =
          p.join(datakollectDir.path, 'databases', '$surveyId.sqlite');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        throw Exception('Database file not found: $dbPath');
      }

      // 4. Create Zip
      final timestamp = DateFormat('yyyy-MM-dd_HH_mm').format(DateTime.now());
      final zipFilename = '${surveyId}_${surveyorId}_$timestamp.zip';

      final encoder = ZipFileEncoder();

      // Use 'outbox' folder instead of temp
      final outboxDir = Directory(p.join(datakollectDir.path, 'outbox'));
      if (!await outboxDir.exists()) {
        await outboxDir.create(recursive: true);
      }
      final zipPath = p.join(outboxDir.path, zipFilename);

      encoder.create(zipPath);
      encoder.addFile(dbFile);

      // Add backups folder if exists
      final backupsDir =
          Directory(p.join(datakollectDir.path, 'backups', surveyId));
      if (await backupsDir.exists()) {
        await encoder.addDirectory(backupsDir);
      }

      encoder.close();

      final zipFile = File(zipPath);

      // 5. Upload
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading data...')),
        );
      }

      final connected = await _ftpService.connect(username, password);
      if (!connected) throw Exception('Connection failed.');

      final success = await _ftpService.uploadFile(zipFile, zipFilename);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded $zipFilename successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Update last upload time
          _loadLastUploadTime();
        }
      } else {
        throw Exception('Upload failed.');
      }

      // Cleanup - We keep the file in outbox now
      // if (await zipFile.exists()) {
      //   await zipFile.delete();
      // }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _ftpService.disconnect();
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
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
              'Upload finalized records to the server.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
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
              label: Text(_isUploading
                  ? 'Uploading...'
                  : 'Upload ${_activeSurveyName ?? "Data"}'),
            ),
            const SizedBox(height: 8),
            Text(
              _lastUploadTime != null
                  ? 'Last upload: ${DateFormat('MMM d, yyyy HH:mm').format(_lastUploadTime!)}'
                  : 'No uploads yet',
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
