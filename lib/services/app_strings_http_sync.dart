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

  String get sessionExpired => 'Session expired -- please log in again.';
  String get tooManyFailures =>
      'Upload stopped after repeated failures. Some records were not sent.';
  String get connectionFailed =>
      'Could not reach the server. Check your connection and try again.';
  String get invalidCredentials =>
      'Invalid project code, username, or password.';
}
