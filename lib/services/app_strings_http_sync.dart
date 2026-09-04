/// English-only strings for DataKollecta's HTTP/Supabase sync UI.
///
/// DataKollecta builds never set GISTX_COUNTRY (AppConfig.isFrench is always
/// false), so French copy for this UI would be unreachable code that still
/// has to be maintained. Kept out of AppStrings so the boundary of "what is
/// translated" stays visible in review rather than buried in one file. If
/// DataKollecta ever needs French, fold these into AppStrings the same way
/// the rest of the app's strings work, gated on AppConfig.isFrench.
class HttpSyncStrings {
  const HttpSyncStrings();

  String get projectCode => 'Project Code';
  String get enterProjectCode => 'Enter your project code';
  String get projectCodeRequired => 'Project code is required';

  String get syncCenter => 'Sync Center';
  String get connect => 'Connect';
  String get uploadPendingRecords => 'Upload pending records';
  String get downloadSurveys => 'Download surveys';
  String get pendingRecords => 'Pending records';

  String uploadSummary(int synced, int failed) => failed == 0
      ? 'Uploaded $synced record${synced == 1 ? '' : 's'}.'
      : 'Uploaded $synced record${synced == 1 ? '' : 's'}, $failed failed.';

  /// Summarizes an upload-everything pass across every installed survey:
  /// how many surveys uploaded cleanly, how many hit some failure while
  /// uploading, and how many couldn't even be routed to a project.
  String uploadAllSummary({
    required int totalSynced,
    required int surveysWithFailures,
    required int surveysNotRouted,
  }) {
    final parts = <String>['Uploaded $totalSynced record${totalSynced == 1 ? '' : 's'}'];
    if (surveysWithFailures > 0) {
      parts.add('$surveysWithFailures survey${surveysWithFailures == 1 ? '' : 's'} had failures');
    }
    if (surveysNotRouted > 0) {
      parts.add(
          '$surveysNotRouted survey${surveysNotRouted == 1 ? '' : 's'} could not be uploaded (see below)');
    }
    return parts.join(', ');
  }

  String get sessionExpired => 'Session expired -- please log in again.';
  String get tooManyFailures =>
      'Upload stopped after repeated failures. Some records were not sent.';
  String get connectionFailed =>
      'Could not reach the server. Check your connection and try again.';
  String get invalidCredentials =>
      'Invalid project code, username, or password.';

  // -- Multi-project routing (see HttpSyncBackend.RoutingFailure) --

  String get noAssociatedProject =>
      'This survey isn\'t linked to a project. Add the project it came from '
      'in Settings, or contact your project administrator.';
  String get noSessionForProject =>
      'This survey\'s project was removed from Settings. Add it back to '
      'upload its records.';
  String get routingLoginFailed =>
      'Could not log back in to upload this survey -- check its project\'s '
      'saved password in Settings.';

  // -- Settings: multi-project management --

  String get projects => 'Projects';
  String get addProject => 'Add project';
  String get noProjectsConfigured =>
      'No projects added yet. Add one to download and sync its surveys.';
  String get projectCodeHint => 'e.g. prism-css-test-2026';
  String get savingAnywayNoConnection =>
      'Could not reach the server. Save this project anyway and verify the '
      'password once you\'re back online?';
  String get saveAnyway => 'Save anyway';
  String get removeProject => 'Remove project';
  String removeProjectWarning(String projectCode, int pendingCount) =>
      pendingCount == 0
          ? 'Remove project "$projectCode"? Its surveys will no longer be able to upload.'
          : 'Remove project "$projectCode"? It has $pendingCount unsynced '
              'record${pendingCount == 1 ? '' : 's'} that will be stranded until it\'s '
              'added back. Upload first, or remove anyway?';
  String get uploadFirst => 'Upload first';
  String get removeAnyway => 'Remove anyway';
  String projectAdded(String projectCode) => 'Added project "$projectCode".';
  String projectRemoved(String projectCode) => 'Removed project "$projectCode".';

  // -- Check for Updates / download collisions --

  String projectCheckFailed(String projectCode, String reason) =>
      'Project "$projectCode": $reason';
  String get noSurveysFromAnyProject =>
      'No new surveys found across your configured projects.';
  String downloadCollision(String surveyId, String existingProjectCode) =>
      'Survey "$surveyId" is already linked to project "$existingProjectCode" '
      'on this device and cannot also be downloaded from a different project.';

  // -- Upload tuning --

  String get uploadSettings => 'Upload';
  String get recordsPerUpload => 'Records per upload';

  /// Says what the number does in terms of the thing an interviewer can
  /// actually observe -- whether uploads keep failing on this connection --
  /// rather than in terms of HTTP batches.
  String get recordsPerUploadHelp =>
      'How many records are sent at a time. Lower this if uploads keep failing '
      'on a weak connection; raise it to upload faster on a good one.';

  String recordsPerUploadSaved(int size) =>
      'Uploads will now send $size record${size == 1 ? '' : 's'} at a time.';
}
