class AppStrings {
  final bool isFrench;
  const AppStrings(this.isFrench);

  // ── Common ───────────────────────────────────────────────────────────────
  String get error => isFrench ? 'Erreur' : 'Error';

  // ── Special responses ──────────────────────────────────────────────────────
  String get dontKnow => isFrench ? 'Ne sait pas' : "Don't know";
  String get refuse => isFrench ? 'Refuse de répondre' : 'Refuse to answer';

  // ── Question input placeholders ────────────────────────────────────────────
  String get selectAnOption =>
      isFrench ? 'Sélectionner une option' : 'Select an option';
  String get selectADate =>
      isFrench ? 'Sélectionner une date' : 'Select a date';
  String get selectDateAndTime =>
      isFrench ? 'Sélectionner la date et l\'heure' : 'Select date and time';

  // ── Main Screen ──────────────────────────────────────────────────────────
  String get currentProject => isFrench ? 'PROJET ACTUEL' : 'CURRENT PROJECT';
  String get newSurvey => isFrench ? 'Nouveau Questionnaire' : 'New Survey';
  String get modifyExistingSurvey =>
      isFrench ? 'Modifier un Questionnaire' : 'Modify Existing Survey';
  String get selectASurvey =>
      isFrench ? 'Sélectionner un Projet' : 'Select a Survey';
  String get selectActiveSurvey =>
      isFrench ? 'Sélectionner le Projet Actif' : 'Select Active Survey';
  String get noSurveysAvailable =>
      isFrench ? 'Aucun projet disponible.' : 'No surveys available to select.';
  String get settingsRequired =>
      isFrench ? 'Paramètres Requis' : 'Settings Required';
  String get settingsRequiredMessage => isFrench
      ? 'Veuillez configurer vos paramètres avant de démarrer un questionnaire.\n\n'
          'Vous devez:\n'
          '• Entrer votre identifiant enquêteur\n'
          '• Entrer vos identifiants\n'
          '• Télécharger/sélectionner un projet actif'
      : 'Please configure your settings before starting a survey.\n\n'
          'You need to:\n'
          '• Enter your Surveyor ID\n'
          '• Enter your credentials\n'
          '• Download/select an active survey';
  String get cancel => isFrench ? 'Annuler' : 'Cancel';
  String get goToSettings =>
      isFrench ? 'Aller aux Paramètres' : 'Go to Settings';
  String get tooltipStatistics =>
      isFrench ? 'Statistiques Récapitulatives' : 'Summary Statistics';
  String get tooltipSyncCenter =>
      isFrench ? 'Centre de Synchronisation' : 'Sync Center';
  String get tooltipSettings => isFrench ? 'Paramètres' : 'Settings';
  String get tooltipExit => isFrench ? 'Quitter' : 'Exit';

  // ── Summary Statistics ────────────────────────────────────────────────────
  String get summaryStatistics =>
      isFrench ? 'Statistiques Récapitulatives' : 'Summary Statistics';
  String get completedToday =>
      isFrench ? "Complétés Aujourd'hui" : 'Completed Today';
  String get totalCompleted => isFrench ? 'Total Complété' : 'Total Completed';
  String get noSurveysFound => isFrench
      ? 'Aucun questionnaire trouvé dans cette configuration.'
      : 'No surveys found in this configuration.';
  String get errorLoadingStatistics => isFrench
      ? 'Erreur de chargement des statistiques'
      : 'Error loading statistics';

  // ── Sync Center ───────────────────────────────────────────────────────────
  String get syncCenter =>
      isFrench ? 'Centre de Synchronisation' : 'Sync Center';
  String get getNewUpdatedSurveys => isFrench
      ? 'Obtenir les Nouveaux Questionnaires'
      : 'Get New/Updated Surveys';
  String get connectToServerDescription => isFrench
      ? 'Connectez-vous au serveur pour vérifier les nouveaux formulaires ou mis à jour.'
      : 'Connect to the server to check for new or updated survey forms.';
  String get checkForUpdates =>
      isFrench ? 'Vérifier les Mises à Jour' : 'Check for Updates';
  String get connecting => isFrench ? 'Connexion...' : 'Connecting...';
  String get connectingToServer =>
      isFrench ? 'Connexion au serveur...' : 'Connecting to server...';
  String get uploadData => isFrench ? 'Téléverser les Données' : 'Upload Data';
  String get uploadFinalizedRecords => isFrench
      ? 'Téléversez les enregistrements finalisés vers le serveur.'
      : 'Upload finalized records to the server.';
  String get uploading => isFrench ? 'Téléversement...' : 'Uploading...';
  String get uploadingData =>
      isFrench ? 'Téléversement des données...' : 'Uploading data...';
  String uploadSurvey(String? name) => isFrench
      ? 'Téléverser ${name ?? "les Données"}'
      : 'Upload ${name ?? "Data"}';
  String get noUploadsYet => isFrench
      ? 'Aucun paquet de téléversement local'
      : 'No local upload packages yet';
  String get lastLocalUploadPackage => isFrench
      ? 'Dernier paquet de téléversement local'
      : 'Last local upload package';
  String get configureFtpFirst => isFrench
      ? "Veuillez d'abord configurer les identifiants FTP dans les Paramètres."
      : 'Please configure FTP credentials in Settings first.';
  String get noSurveyZipsFound => isFrench
      ? 'Aucun fichier zip trouvé dans le dossier /survey/.'
      : 'No survey zip files found in /survey/ folder.';
  String foundSurveys(int count) => isFrench
      ? '$count questionnaire${count == 1 ? '' : 's'} trouvé${count == 1 ? '' : 's'}.'
      : 'Found $count surveys.';
  String downloadedSuccessfully(String filename) => isFrench
      ? '$filename téléchargé avec succès!'
      : 'Downloaded $filename successfully!';
  String errorDownloading(String filename, Object e) => isFrench
      ? 'Erreur lors du téléchargement de $filename: $e'
      : 'Error downloading $filename: $e';
  String uploadedSuccessfully(String filename) => isFrench
      ? '$filename téléversé avec succès!'
      : 'Uploaded $filename successfully!';
  String errorUploading(Object e) =>
      isFrench ? 'Erreur lors du téléversement: $e' : 'Error uploading: $e';
  String get failedToConnectFtp => isFrench
      ? 'Impossible de se connecter au serveur FTP.'
      : 'Failed to connect to FTP server.';
  String get connectionLost =>
      isFrench ? 'Connexion perdue.' : 'Connection lost.';
  String get downloadFailed =>
      isFrench ? 'Échec du téléchargement.' : 'Download failed.';
  String get connectionFailed =>
      isFrench ? 'Échec de la connexion.' : 'Connection failed.';
  String get uploadFailed =>
      isFrench ? 'Échec du téléversement.' : 'Upload failed.';
  String get missingSettings => isFrench
      ? 'Paramètres manquants (Identifiant Enquêteur ou Projet Actif).'
      : 'Missing settings (Surveyor ID or Active Survey).';
  String couldNotFindSurveyId(String name) => isFrench
      ? "Impossible de trouver l'identifiant du questionnaire: $name"
      : 'Could not find ID for survey: $name';
  String get noCredentialsForSurvey => isFrench
      ? 'Aucun identifiant disponible pour ce questionnaire.'
      : 'No credentials available for this survey.';
  String couldNotLoadManifest(String name) => isFrench
      ? 'Impossible de charger le manifeste du questionnaire: $name'
      : 'Could not load survey manifest for: $name';
  String noDatabaseNameInManifest(String name) => isFrench
      ? 'Aucun databaseName trouvé dans le manifeste pour: $name'
      : 'No databaseName found in manifest for: $name';
  String databaseFileNotFound(String path) => isFrench
      ? 'Fichier de base de données introuvable: $path'
      : 'Database file not found: $path';
  String get lastUpload => isFrench ? 'Dernier téléversement' : 'Last upload';

  // ── Settings ──────────────────────────────────────────────────────────────
  String get settings => isFrench ? 'Paramètres' : 'Settings';
  String get save => isFrench ? 'Enregistrer' : 'Save';
  String get lightMode => isFrench ? 'Mode Clair' : 'Light Mode';
  String get darkMode => isFrench ? 'Mode Sombre' : 'Dark Mode';
  String get userSettings =>
      isFrench ? 'Paramètres Utilisateur' : 'User Settings';
  String get surveyorId => isFrench ? 'Identifiant Enquêteur' : 'Surveyor ID';
  String get enterSurveyorId => isFrench
      ? 'Entrez votre identifiant enquêteur'
      : 'Enter your surveyor ID';
  String get surveyorIdRequired => isFrench
      ? "L'identifiant enquêteur est requis"
      : 'Surveyor ID is required';
  String get serverCredentials =>
      isFrench ? 'Identifiants Serveur' : 'Server Credentials';
  String get serverCredentialsDescription => isFrench
      ? 'Entrez vos identifiants pour accéder au serveur.'
      : 'Enter your credentials to access the survey server.';
  String get username => isFrench ? "Nom d'utilisateur" : 'Username';
  String get enterUsername =>
      isFrench ? "Entrez le nom d'utilisateur" : 'Enter username';
  String get password => isFrench ? 'Mot de passe' : 'Password';
  String get enterPassword =>
      isFrench ? 'Entrez le mot de passe' : 'Enter password';
  String get manageSurveys =>
      isFrench ? 'Gérer les Questionnaires' : 'Manage Surveys';
  String get deleteSurvey =>
      isFrench ? 'Supprimer le Questionnaire' : 'Delete Survey';
  String get noSurveysToDelete => isFrench
      ? 'Aucun questionnaire installé à supprimer.'
      : 'No surveys installed to delete.';
  String get confirmDeletion =>
      isFrench ? 'Confirmer la Suppression' : 'Confirm Deletion';
  String confirmDeleteMessage(String name) => isFrench
      ? 'Êtes-vous sûr de vouloir supprimer "$name"?\n\n'
          'Cela supprimera la définition du questionnaire et le fichier zip source.\n'
          'Les données collectées (base de données) ne seront PAS supprimées.'
      : 'Are you sure you want to delete "$name"?\n\n'
          'This will remove the survey definition and source zip.\n'
          'Collected data (database) will NOT be deleted.';
  String get delete => isFrench ? 'Supprimer' : 'Delete';
  String get close => isFrench ? 'Fermer' : 'Close';
  String get settingsSaved => isFrench
      ? 'Paramètres enregistrés avec succès'
      : 'Settings saved successfully';
  String errorSavingSettings(Object e) => isFrench
      ? 'Erreur lors de l\'enregistrement: $e'
      : 'Error saving settings: $e';
  String deletedSurvey(String name) =>
      isFrench ? 'Supprimé "$name"' : 'Deleted "$name"';
  String errorDeletingSurvey(Object e) => isFrench
      ? 'Erreur lors de la suppression: $e'
      : 'Error deleting survey: $e';
  String get selectCountry =>
      isFrench ? 'Sélectionner un pays' : 'Select Country';

  // ── Questionnaire Selector ────────────────────────────────────────────────
  String get selectQuestionnaire =>
      isFrench ? 'Sélectionner le Questionnaire' : 'Select Questionnaire';
  String get selectQuestionnaireToModify => isFrench
      ? 'Sélectionner le Questionnaire à Modifier'
      : 'Select Questionnaire to Modify';
  String get goBack => isFrench ? 'Retour' : 'Go Back';
  String get selectQuestionnaireInstruction => isFrench
      ? 'Sélectionnez le questionnaire à compléter:'
      : 'Select the questionnaire you want to complete:';
  String get selectQuestionnaireToModifyInstruction => isFrench
      ? 'Sélectionnez le questionnaire à modifier:'
      : 'Select the questionnaire you want to modify:';
  String get noSurveySelectedConfigure => isFrench
      ? "Aucun projet sélectionné. Veuillez d'abord configurer les paramètres."
      : 'No survey selected. Please configure settings first.';
  String get noXmlFilesInManifest => isFrench
      ? 'Aucun fichier XML défini dans le manifeste du questionnaire.'
      : 'No XML files defined in survey manifest';
  String noQuestionnairesForSurvey(String surveyId) => isFrench
      ? 'Aucun questionnaire trouvé pour le projet: $surveyId'
      : 'No questionnaires found for survey: $surveyId';
  String errorLoadingQuestionnaires(Object e) => isFrench
      ? 'Erreur lors du chargement des questionnaires: $e'
      : 'Error loading questionnaires: $e';

  // ── Record Selector ───────────────────────────────────────────────────────
  String get selectRecord =>
      isFrench ? "Sélectionner l'Enregistrement" : 'Select Record';
  String get errorLoadingRecords => isFrench
      ? 'Erreur de chargement des enregistrements'
      : 'Error loading records';
  String get noRecordsFound =>
      isFrench ? 'Aucun enregistrement trouvé' : 'No records found';
  String get noRecordsToModify => isFrench
      ? "Il n'y a pas de questionnaires existants à modifier."
      : 'There are no existing surveys to modify.';
  String get configurationError =>
      isFrench ? 'Erreur de Configuration' : 'Configuration Error';
  String noPrimaryKey(String tableName) => isFrench
      ? 'Aucune clé primaire définie dans la table CRFs pour "$tableName".'
      : 'No primary key defined in CRFs table for "$tableName".';
  String get selectRecordToModify => isFrench
      ? "Sélectionner l'Enregistrement à Modifier"
      : 'Select Record to Modify';
  String foundRecords(int count) => isFrench
      ? '$count enregistrement${count == 1 ? '' : 's'} existant${count == 1 ? '' : 's'} trouvé${count == 1 ? '' : 's'}'
      : 'Found $count existing records';
  String get viewModifySurvey =>
      isFrench ? 'Voir/Modifier le Questionnaire' : 'View/Modify Survey';
  String pleaseSelectValue(String field) => isFrench
      ? 'Veuillez sélectionner une valeur pour ${field.toUpperCase()}.'
      : 'Please select a value for ${field.toUpperCase()}.';
  String get noRecordMatchingCriteria => isFrench
      ? 'Aucun enregistrement trouvé pour les critères sélectionnés.'
      : 'No record found matching the selected criteria.';
  String get multipleRecordsFound => isFrench
      ? 'Plusieurs enregistrements trouvés. Veuillez sélectionner des valeurs pour tous les champs clés primaires.'
      : 'Multiple records found. Please select values for all primary key fields.';
  String get noUniqueId => isFrench
      ? "L'enregistrement n'a pas de champ uniqueid."
      : 'Record does not have a uniqueid field.';
  String selectFieldHint(String field) =>
      isFrench ? 'Sélectionner $field' : 'Select $field';
  String get searchRecordsHint =>
      isFrench ? 'Rechercher un enregistrement...' : 'Search records...';
  String matchingRecordsCount(int count) => isFrench
      ? '$count enregistrement${count == 1 ? '' : 's'} correspondant${count == 1 ? '' : 's'}'
      : '$count matching record${count == 1 ? '' : 's'}';
  String get noMatchingRecords => isFrench
      ? 'Aucun enregistrement correspondant trouvé'
      : 'No matching records found';

  // ── Parent ID Selector ────────────────────────────────────────────────────
  String noEligibleIds(String field, String table, String? condition) => isFrench
      ? 'Aucun $field éligible trouvé dans la table $table.\n\n'
          '${condition != null ? "Remarque: Seuls les enregistrements éligibles pour ce questionnaire sont affichés.\n\n" : ""}'
          'Veuillez d\'abord compléter un questionnaire $table.'
      : 'No eligible $field found in $table table.\n\n'
          '${condition != null ? "Note: Only records eligible for this questionnaire are shown.\n\n" : ""}'
          'Please complete a $table questionnaire first.';
  String errorLoadingIds(Object e) =>
      isFrench ? 'Erreur de chargement des IDs: $e' : 'Error loading IDs: $e';
  String selectFieldTitle(String field) => isFrench
      ? 'Sélectionner ${field.toUpperCase()}'
      : 'Select ${field.toUpperCase()}';
  String selectFieldInstruction(String field) => isFrench
      ? 'Sélectionnez le ${field.toUpperCase()} pour ce questionnaire:'
      : 'Select the ${field.toUpperCase()} for this questionnaire:';
  String searchField(String field) =>
      isFrench ? 'Rechercher $field...' : 'Search $field...';
  String availableCount(int count, String field) => isFrench
      ? '$count $field disponible${count == 1 ? '' : 's'}'
      : '$count ${field}(s) available';
  String noMatchingField(String field) => isFrench
      ? 'Aucun $field correspondant trouvé'
      : 'No matching $field found';
  String nextIncrement(String field, int value) =>
      isFrench ? 'Prochain $field: $value' : 'Next $field: $value';

  // ── Survey Screen ─────────────────────────────────────────────────────────
  String get previous => isFrench ? 'Précédent' : 'Previous';
  String get next => isFrench ? 'Suivant' : 'Next';
  String get finish => isFrench ? 'Terminer' : 'Finish';
  String get cancelInterview =>
      isFrench ? "Annuler l'entretien" : 'Cancel Interview';
  String get cancelInterviewMessage => isFrench
      ? "Êtes-vous sûr de vouloir annuler l'entretien?\n\nToutes les modifications seront perdues!"
      : 'Are you sure you want to cancel the interview? \n\nAll edits/modifications will be lost!';
  String get no => isFrench ? 'Non' : 'No';
  String get yes => isFrench ? 'Oui' : 'Yes';
  String get duplicateRecord =>
      isFrench ? 'Enregistrement en double' : 'Duplicate Record';
  String get duplicateRecordMessage => isFrench
      ? 'Un enregistrement avec cet ID existe déjà. Veuillez entrer un ID unique.'
      : 'A record with this ID already exists. Please enter a unique ID.';
  String get ok => 'OK';
  String get incompleteDecimalValue => isFrench
      ? 'Veuillez entrer un chiffre après le séparateur décimal.'
      : 'Please enter a digit after the decimal separator.';
  String get noChanges => isFrench ? 'Aucune Modification' : 'No Changes';
  String get noChangesMessage => isFrench
      ? "Aucune modification n'a été apportée à cet enregistrement."
      : 'No changes were made to this record.';
  String addEntityNow(String displayName) =>
      isFrench ? 'Ajouter $displayName Maintenant?' : 'Add $displayName Now?';
  String addEntityMessage(int count) => isFrench
      ? 'Vous avez indiqué $count ${count == 1 ? 'enregistrement' : 'enregistrements'}.\n\nVoulez-vous les ajouter maintenant?'
      : 'You indicated $count ${count == 1 ? 'record' : 'records'}.\n\nWould you like to add them now?';
  String get addLater => isFrench ? 'Ajouter Plus Tard' : 'Add Later';
  String get addNow => isFrench ? 'Ajouter Maintenant' : 'Add Now';
  String mustCompleteAll(String entityNamePlural) => isFrench
      ? 'Compléter tous les $entityNamePlural'
      : 'Must Complete All $entityNamePlural';
  String mustCompleteMessage(
          int total, String entityNamePlural, String entityName, int current) =>
      isFrench
          ? 'Vous devez ajouter $total $entityNamePlural.\n\nActuellement sur ${entityName.toLowerCase()} $current sur $total.'
          : 'You must add all $total $entityNamePlural.\n\nCurrently on ${entityName.toLowerCase()} $current of $total.';
  String get exitAnyway => isFrench ? 'Quitter Quand Même' : 'Exit Anyway';
  String get exitAnywayWarning =>
      isFrench ? 'Quitter Quand Même ⚠️' : 'Exit Anyway ⚠️';
  String get continueLabel => isFrench ? 'Continuer' : 'Continue';
  String get incompleteData =>
      isFrench ? 'Données Incomplètes' : 'Incomplete Data';
  String incompleteDataMessage(int expected, String displayName, int actual) => isFrench
      ? 'Vous avez indiqué $expected ${expected == 1 ? 'enregistrement' : 'enregistrements'} pour $displayName mais seulement $actual ${actual == 1 ? 'a été ajouté' : 'ont été ajoutés'}.\n\nCela causera des problèmes de qualité des données.'
      : 'You indicated $expected ${expected == 1 ? 'record' : 'records'} for $displayName but only added $actual.\n\nThis will cause data quality issues.';
  String updateCountTo(int actual) => isFrench
      ? 'Mettre à jour le compte à $actual'
      : 'Update Count to $actual';
  String get allDone => isFrench ? 'Terminé!' : 'All done!';
  String get recordUpdatedSuccess => isFrench
      ? 'Merci! Enregistrement mis à jour avec succès.'
      : 'Thanks! Record updated successfully.';
  String get answersSavedSuccess => isFrench
      ? 'Merci! Réponses enregistrées avec succès.'
      : 'Thanks! Answers saved successfully.';
  String get saveFailed =>
      isFrench ? "Échec de l'enregistrement" : 'Save Failed';
  String get saveFailedMessage => isFrench
      ? "Impossible d'enregistrer les données dans la base de données."
      : 'Failed to save the interview data to the database.';
  String get errorDetails =>
      isFrench ? "Détails de l'erreur:" : 'Error details:';
  String get saveFailedChecklist => isFrench
      ? 'Veuillez vérifier:\n'
          '• Le fichier de base de données existe\n'
          '• Le nom de la table correspond au fichier du questionnaire\n'
          '• Toutes les colonnes requises existent dans la table'
      : 'Please check:\n'
          '• Database file exists at the configured path\n'
          '• Table name matches the survey filename\n'
          '• All required columns exist in the table';

  // ── Review Changes dialog ─────────────────────────────────────────────────
  String get reviewChanges =>
      isFrench ? 'Réviser les Modifications' : 'Review Changes';
  String get noChangesDetected => isFrench
      ? 'Aucune modification détectée.'
      : 'No logical changes detected.';
  String get discardAndExit =>
      isFrench ? 'Annuler & Quitter' : 'Discard & Exit';
  String get backToEdit => isFrench ? "Retour à l'Édition" : 'Back to Edit';
  String get saveChanges =>
      isFrench ? 'Enregistrer les Modifications' : 'Save Changes';
  String get discardChangesTitle =>
      isFrench ? 'Annuler les Modifications?' : 'Discard Changes?';
  String get discardChangesMessage => isFrench
      ? 'Êtes-vous sûr de vouloir annuler toutes les modifications et quitter? '
          'Cette action est irréversible.'
      : 'Are you sure you want to discard all changes and exit? This cannot be undone.';
}
