import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/app_strings_http_sync.dart';
import '../services/sync/http_sync_backend.dart';
import '../services/sync/project_sessions.dart';
import '../services/sync/record_uploader.dart';
import '../services/sync/sync_backend.dart';
import '../config/app_config.dart';
import 'settings_screen.dart';

/// The DataKollecta counterpart to sync_screen.dart. Kept as a separate
/// file rather than branches threaded through the FTP screen: the two
/// flows share almost no state, the upload paths are genuinely different
/// operations, and sync_screen.dart is live Burkina Faso production code
/// that a new sibling file cannot regress.
///
/// Every survey on the device is routed to the project it was downloaded
/// from -- there is no project switcher here. "Check for Updates" polls
/// every configured project, and "Upload" flushes every installed survey in
/// one tap, each against its own project's session.
class HttpSyncScreen extends StatefulWidget {
  const HttpSyncScreen({super.key});

  @override
  State<HttpSyncScreen> createState() => _HttpSyncScreenState();
}

class _HttpSyncScreenState extends State<HttpSyncScreen> {
  final _syncBackend = HttpSyncBackend();

  bool _isConnecting = false;
  bool _isUploading = false;
  bool _hasAnyProjectConfigured = true; // assumed true until first load
  List<RemoteProjectSurvey> _remoteSurveys = [];
  final Map<String, String> _projectErrors = {}; // projectCode -> message
  String? _downloadingSurveyId;
  String? _statusMessage;
  bool _statusIsError = false;
  int? _pendingCount;
  List<InstalledSurveyUploadResult> _lastUploadResults = [];

  static const AppStrings _s = AppStrings(AppConfig.isFrench);
  static const HttpSyncStrings _httpSync = HttpSyncStrings();

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  @override
  void dispose() {
    // The underlying http.Client is meant to be reused across every call
    // this screen makes -- closing it only makes sense once, when the
    // screen itself goes away.
    _syncBackend.disconnect();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    final count = await _syncBackend.countAllPending();
    if (mounted) setState(() => _pendingCount = count);
  }

  /// Maps a failure onto user-facing copy by exhaustively switching on the
  /// sealed SyncException family, rather than sniffing exception text.
  String _messageFor(SyncException? error) {
    return switch (error) {
      SyncConnectionException _ => _httpSync.connectionFailed,
      SyncAuthException _ => _httpSync.invalidCredentials,
      // The server's own wording, because it is the only place the wait time
      // appears. Replacing it with fixed copy the way the auth branch does
      // would drop the one fact the interviewer needs.
      SyncThrottledException e => e.message,
      SyncTransferException e => e.message,
      null => _s.error,
    };
  }

  String _routingMessage(RoutingFailure reason) {
    return switch (reason) {
      RoutingFailure.noAssociatedProject => _httpSync.noAssociatedProject,
      RoutingFailure.noSessionForProject => _httpSync.noSessionForProject,
      RoutingFailure.loginFailed => _httpSync.routingLoginFailed,
    };
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = _s.connectingToServer;
      _statusIsError = false;
      _remoteSurveys = [];
      _projectErrors.clear();
    });

    try {
      final doc = await _syncBackend.loadDocument();
      if (doc.sessions.isEmpty) {
        setState(() {
          _hasAnyProjectConfigured = false;
          _statusMessage = null;
        });
        return;
      }
      setState(() => _hasAnyProjectConfigured = true);

      final results = await _syncBackend.checkAllForUpdates();
      final surveys = <RemoteProjectSurvey>[];
      for (final result in results) {
        if (result.succeeded) {
          surveys.addAll(result.surveys);
        } else {
          _projectErrors[result.projectCode] = _messageFor(result.error);
        }
      }

      setState(() {
        _remoteSurveys = surveys;
        if (_projectErrors.isNotEmpty) {
          _statusMessage = null; // per-project errors render inline instead
        } else {
          _statusMessage = surveys.isEmpty
              ? _httpSync.noSurveysFromAnyProject
              : _s.foundSurveys(surveys.length);
        }
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

  Future<void> _downloadSurvey(RemoteProjectSurvey survey) async {
    setState(() => _downloadingSurveyId = survey.surveyId);

    try {
      await _syncBackend.downloadSurvey(survey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.downloadedSuccessfully(survey.name)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ProjectAssociationConflict catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_httpSync.downloadCollision(
                e.surveyId, e.existingProjectCode)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on SyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.errorDownloading(survey.name, e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingSurveyId = null);
      _loadPendingCount();
    }
  }

  Future<void> _uploadAllPending() async {
    setState(() => _isUploading = true);

    try {
      final results = await _syncBackend.uploadAllPending();
      if (!mounted) return;

      var totalSynced = 0;
      var surveysWithFailures = 0;
      var surveysNotRouted = 0;
      var sawSessionExpired = false;
      var sawThrottled = false;

      for (final r in results) {
        final outcome = r.result.outcome;
        if (outcome != null) {
          totalSynced += outcome.syncedCount;
          if (outcome.failedCount > 0 || outcome.stoppedEarly) {
            surveysWithFailures++;
          }
          if (outcome.stopReason == UploadStopReason.sessionExpired) {
            sawSessionExpired = true;
          }
          if (outcome.stopReason == UploadStopReason.throttled) {
            sawThrottled = true;
          }
        } else {
          surveysNotRouted++;
        }
      }

      setState(() => _lastUploadResults = results);

      final hasIssues = surveysWithFailures > 0 || surveysNotRouted > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(results.isEmpty
              ? _s.noSurveyZipsFound
              // A throttle needs its own sentence rather than being folded
              // into the failure count: nothing is wrong with the records,
              // and "try again in a few minutes" is the only useful next
              // step. Without this it reads as data loss.
              : sawThrottled
                  ? _httpSync.uploadThrottled
                  : _httpSync.uploadAllSummary(
                      totalSynced: totalSynced,
                      surveysWithFailures: surveysWithFailures,
                      surveysNotRouted: surveysNotRouted,
                    )),
          backgroundColor: !hasIssues
              ? Colors.green
              : (sawSessionExpired ? Colors.red : Colors.orange),
        ),
      );

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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
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
            if (!_hasAnyProjectConfigured) _buildNoProjectsCard(context),
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

  Widget _buildNoProjectsCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_httpSync.noProjectsConfigured),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.add),
              label: Text(_httpSync.addProject),
            ),
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
              onPressed:
                  (_isConnecting || !_hasAnyProjectConfigured) ? null : _checkForUpdates,
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
            // Per-project failures shown inline, individually -- one
            // unreachable project must never look like every project
            // failed, and the survey list below still renders whatever
            // the OTHER projects returned.
            if (_projectErrors.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._projectErrors.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _httpSync.projectCheckFailed(e.key, e.value),
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )),
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
                      _downloadingSurveyId == survey.surveyId;
                  // Deliberately no project label here -- the survey name
                  // alone is what an interviewer needs to recognize it.
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
                            onPressed: _downloadingSurveyId != null
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
    final unrouted =
        _lastUploadResults.where((r) => !r.result.routed).toList();

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
              onPressed: _isUploading ? null : _uploadAllPending,
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
            // A survey that couldn't even be routed to a project needs an
            // actionable, sticky recovery path -- the survey list itself
            // carries no project label, so this is the only place the
            // problem (and the fix, in Settings) is visible at all.
            if (unrouted.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              ...unrouted.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.surveyName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                _routingMessage(r.result.routingFailure!),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _openSettings,
                  child: Text(_httpSync.addProject),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
