import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';

import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../services/ftp_service.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _ftpService = FtpService();
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();

  bool _isConnecting = false;
  bool _isUploading = false;
  List<String> _remoteFiles = [];
  String? _downloadingFile;
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

  Future<void> _checkForUpdates() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to server...';
      _remoteFiles = [];
    });

    try {
      final username = await _settingsService.ftpUsername;
      final password = await _settingsService.ftpPassword;

      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Please configure FTP credentials in Settings first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final connected = await _ftpService.connect(username, password);
      if (!connected) {
        throw Exception('Failed to connect to FTP server.');
      }

      setState(() => _statusMessage = 'Listing files...');
      final files = await _ftpService.listSurveyZips();

      setState(() {
        _remoteFiles = files;
        _statusMessage = files.isEmpty
            ? 'No survey zip files found in /survey/ folder.'
            : 'Found ${files.length} surveys.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      await _ftpService.disconnect();
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _downloadSurvey(String filename) async {
    setState(() {
      _downloadingFile = filename;
    });

    try {
      final username = await _settingsService.ftpUsername;
      final password = await _settingsService.ftpPassword;

      if (username == null || password == null) return;

      final connected = await _ftpService.connect(username, password);
      if (!connected) throw Exception('Connection lost.');

      final file = await _ftpService.downloadSurveyZip(filename);

      if (file != null) {
        // Extract surveyId from the downloaded zip to save credentials
        // The zip file name should be something like "surveyname.zip"
        // After extraction, we need to read the manifest to get the surveyId
        await _associateCredentialsWithDownloadedSurvey(
            filename, username, password);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded $filename successfully!'),
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
            content: Text('Error downloading $filename: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _ftpService.disconnect();
      if (mounted) {
        setState(() {
          _downloadingFile = null;
        });
      }
    }
  }

  Future<void> _associateCredentialsWithDownloadedSurvey(
      String filename, String username, String password) async {
    try {
      // Extract zip first (it's in the zips folder)
      await _surveyConfig.initializeSurveys();

      // The survey name is the filename without .zip extension
      final surveyName =
          filename.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');

      // Get the surveyId for this survey
      final surveyId = await _surveyConfig.getSurveyId(surveyName);

      if (surveyId != null) {
        // Save the credentials that were used to download this survey
        await _settingsService.setSurveyCredentials(
            surveyId, username, password);
        debugPrint('[SyncScreen] Saved credentials for survey: $surveyId');
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
            if (_remoteFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _remoteFiles.length,
                itemBuilder: (context, index) {
                  final filename = _remoteFiles[index];
                  final isDownloading = _downloadingFile == filename;
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(filename.replaceAll(
                        RegExp(r'\.zip$', caseSensitive: false), '')),
                    trailing: isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: _downloadingFile != null
                                ? null
                                : () => _downloadSurvey(filename),
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
