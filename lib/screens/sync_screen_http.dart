import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/app_strings_http_sync.dart';
import '../services/settings_service.dart';
import '../services/survey_config_service.dart';
import '../services/sync/http_sync_backend.dart';
import '../services/sync/record_uploader.dart';
import '../services/sync/sync_backend.dart';
import '../config/app_config.dart';

/// The DataKollecta counterpart to sync_screen.dart. Kept as a separate
/// file rather than branches threaded through the FTP screen: the two
/// flows share almost no state (a live pending-record counter here has no
/// FTP equivalent; a last-local-zip timestamp there has no HTTP
/// equivalent), the upload paths are genuinely different operations (see
/// sync_backend.dart), and sync_screen.dart is live Burkina Faso
/// production code that a new sibling file cannot regress.
class HttpSyncScreen extends StatefulWidget {
  const HttpSyncScreen({super.key});

  @override
  State<HttpSyncScreen> createState() => _HttpSyncScreenState();
}

class _HttpSyncScreenState extends State<HttpSyncScreen> {
  final _syncBackend = HttpSyncBackend();
  final _settingsService = SettingsService();
  final _surveyConfig = SurveyConfigService();

  bool _isConnecting = false;
  bool _isUploading = false;
  List<RemoteSurvey> _remoteSurveys = [];
  String? _downloadingFilename;
  String? _statusMessage;
  bool _statusIsError = false;
  String? _activeSurveyName;
  int? _pendingCount;

  static const AppStrings _s = AppStrings(AppConfig.isFrench);
  static const HttpSyncStrings _httpSync = HttpSyncStrings();

  @override
  void initState() {
    super.initState();
    _loadActiveSurvey();
  }

  @override
  void dispose() {
    // The underlying http.Client is meant to be reused across every call
    // this screen makes -- closing it only makes sense once, when the
    // screen itself goes away, not after each individual operation (unlike
    // FTP, an HTTP bearer token stays valid across many calls, so there is
    // no per-operation connect/disconnect cycle to mirror here).
    _syncBackend.disconnect();
    super.dispose();
  }

  Future<void> _loadActiveSurvey() async {
    final name = await _settingsService.activeSurvey;
    if (mounted) {
      setState(() => _activeSurveyName = name);
      _loadPendingCount();
    }
  }

  Future<void> _loadPendingCount() async {
    if (_activeSurveyName == null) return;
    final surveyId = await _surveyConfig.getSurveyId(_activeSurveyName!);
    if (surveyId == null) return;
    final count = await _syncBackend.countPending(surveyId);
    if (mounted) setState(() => _pendingCount = count);
  }

  /// Maps a failure onto user-facing copy by exhaustively switching on the
  /// sealed SyncException family, rather than sniffing exception text the
  /// way the DataKollecta reference branch's UI did.
  String _messageFor(SyncException? error) {
    return switch (error) {
      SyncConnectionException _ => _httpSync.connectionFailed,
      SyncAuthException _ => _httpSync.invalidCredentials,
      SyncTransferException e => e.message,
      null => _s.error,
    };
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = _s.connectingToServer;
      _statusIsError = false;
      _remoteSurveys = [];
    });

    try {
      final username = await _settingsService.apiUsername;
      final password = await _settingsService.apiPassword;

      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        setState(() {
          _statusMessage = _httpSync.invalidCredentials;
          _statusIsError = true;
        });
        return;
      }

      final connected = await _syncBackend.connect(username, password);
      if (!connected) {
        setState(() {
          _statusMessage = _messageFor(_syncBackend.lastError);
          _statusIsError = true;
        });
        return;
      }

      final surveys = await _syncBackend.listSurveys();
      setState(() {
        _remoteSurveys = surveys;
        _statusMessage = surveys.isEmpty
            ? _s.noSurveyZipsFound
            : _s.foundSurveys(surveys.length);
      });
    } catch (e) {
      setState(() {
        _statusMessage = '${_s.error}: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _downloadSurvey(RemoteSurvey survey) async {
    setState(() => _downloadingFilename = survey.filename);

    try {
      final file = await _syncBackend.downloadSurvey(survey.filename);
      if (file == null) {
        throw _messageFor(_syncBackend.lastError);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.downloadedSuccessfully(survey.filename)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.errorDownloading(survey.filename, e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingFilename = null);
    }
  }

  Future<void> _uploadPending() async {
    setState(() => _isUploading = true);

    try {
      final surveyName = await _settingsService.activeSurvey;
      if (surveyName == null) throw Exception(_s.missingSettings);

      final surveyId = await _surveyConfig.getSurveyId(surveyName);
      if (surveyId == null) {
        throw Exception(_s.couldNotFindSurveyId(surveyName));
      }

      final outcome = await _syncBackend.uploadPending(surveyId);

      if (!mounted) return;

      switch (outcome.stopReason) {
        case UploadStopReason.none:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_httpSync.uploadSummary(
                  outcome.syncedCount, outcome.failedCount)),
              backgroundColor:
                  outcome.failedCount == 0 ? Colors.green : Colors.orange,
            ),
          );
        case UploadStopReason.sessionExpired:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_httpSync.sessionExpired),
              backgroundColor: Colors.red,
            ),
          );
        case UploadStopReason.tooManyFailures:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_httpSync.tooManyFailures),
              backgroundColor: Colors.red,
            ),
          );
      }

      _loadPendingCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.errorUploading(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_httpSync.syncCenter)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
                context, _httpSync.downloadSurveys, Icons.download),
            const SizedBox(height: 16),
            _buildDownloadSection(context),
            const SizedBox(height: 32),
            _buildSectionHeader(
                context, _httpSync.uploadPendingRecords, Icons.upload),
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
            Text(
              _s.connectToServerDescription,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isConnecting ? null : _checkForUpdates,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isConnecting ? _s.connecting : _s.checkForUpdates),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusIsError ? Colors.red : Colors.grey[700],
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
                  final isDownloading =
                      _downloadingFilename == survey.filename;
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(survey.filename),
                    trailing: isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: _downloadingFilename != null
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
            Text(
              _s.uploadFinalizedRecords,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isUploading ? null : _uploadPending,
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(
                  _isUploading ? _s.uploading : _httpSync.uploadPendingRecords),
            ),
            const SizedBox(height: 8),
            Text(
              _pendingCount != null
                  ? '${_httpSync.pendingRecords}: $_pendingCount'
                  : '',
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
