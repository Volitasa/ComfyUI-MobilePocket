// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get navWorkflow => 'Workflows';

  @override
  String get navHistory => 'History';

  @override
  String get navGallery => 'Gallery';

  @override
  String get navSettings => 'Settings';

  @override
  String get taskStatusQueued => 'Queued';

  @override
  String get taskStatusRunning => 'Running';

  @override
  String get taskStatusCompleted => 'Completed';

  @override
  String get taskStatusFailed => 'Failed';

  @override
  String get taskStatusInterrupted => 'Interrupted';

  @override
  String get taskPhaseWaiting => 'Waiting to run';

  @override
  String get taskPhaseStarted => 'Task started';

  @override
  String get taskPhaseCached => 'Using cached nodes';

  @override
  String get taskPhaseRunning => 'Processing';

  @override
  String taskPhaseRunningNode(String node) {
    return 'Running $node';
  }

  @override
  String taskPhaseRunningPercent(int percent) {
    return 'Processing $percent%';
  }

  @override
  String taskPhaseRunningNodePercent(String node, int percent) {
    return '$node · $percent%';
  }

  @override
  String get taskPhaseDone => 'Generation finished';

  @override
  String get taskPhaseError => 'Execution failed';

  @override
  String taskPhaseErrorDetail(String detail) {
    return 'Execution failed: $detail';
  }

  @override
  String get taskPhaseInterrupted => 'Task interrupted';

  @override
  String get taskPhaseLost => 'Task not found on the server';

  @override
  String get taskPhaseParseFailed => 'Could not read the result data';

  @override
  String get historyTitle => 'History';

  @override
  String get historySyncTooltip => 'Sync task status';

  @override
  String get historySynced => 'Task status synced';

  @override
  String get historyEmpty => 'No history yet';

  @override
  String get historyRerun => 'Run again';

  @override
  String get historyNoSnapshot =>
      'This record has no workflow snapshot (created by an older version), so it cannot be run again';

  @override
  String get historySnapshotDeleted =>
      'The matching workflow snapshot was deleted, so it cannot be run again';

  @override
  String get historyServerMismatchTitle => 'Different server';

  @override
  String historyServerMismatchBody(String old, String current) {
    return 'This record ran on \"$old\", but \"$current\" is connected now.\n\nThe two servers may have different models or custom nodes, so running it again can fail with errors like \"model not found\" or \"node type not found\". Continue anyway?';
  }

  @override
  String get historyRunAnyway => 'Run anyway';

  @override
  String get historyUnknownServer => 'Unknown server';

  @override
  String get historyNoImage => 'No image';

  @override
  String get historyDeleteTitle => 'Delete record';

  @override
  String historyDeleteConfirm(String title) {
    return 'Delete the record \"$title\"?';
  }

  @override
  String get historyDeleteImagesNote =>
      'Choosing \"Also delete gallery images\" removes the local images saved for this record as well. This cannot be undone. Deleting only the record keeps the gallery images.';

  @override
  String get historyDeleteRecordOnly => 'Delete record only';

  @override
  String get historyDeleteWithImages => 'Also delete gallery images';

  @override
  String get historySaveToLocal => 'Save to device';

  @override
  String get historySaving => 'Saving...';

  @override
  String get historySavedToAlbum => 'Saved to your photo album';

  @override
  String get historySaveFailed => 'Save failed';

  @override
  String get historyVideoLoadFailed => 'Failed to load video';

  @override
  String get serverDefaultName => 'Server';

  @override
  String serverDefaultNameWithIndex(int index) {
    return 'Server $index';
  }

  @override
  String get serverTitle => 'Servers';

  @override
  String get serverAdd => 'Add server';

  @override
  String get serverEdit => 'Edit server';

  @override
  String get serverEmpty => 'No saved servers';

  @override
  String get serverHint =>
      'Tap a card to activate that connection (only one can be active). Each connection can have a primary and a backup address; the primary is tried first and the backup is used when it is unreachable.';

  @override
  String get serverConnected => 'Connected';

  @override
  String get serverActivated => 'Enabled';

  @override
  String serverPrimaryPrefix(String url) {
    return 'Primary: $url';
  }

  @override
  String serverBackupPrefix(String url) {
    return 'Backup: $url';
  }

  @override
  String get serverEditTooltip => 'Edit';

  @override
  String get serverDeleteTitle => 'Delete server';

  @override
  String serverDeleteConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get serverFormName => 'Name';

  @override
  String get serverFormNameHint => 'e.g. Home LAN / Office WAN';

  @override
  String get serverFormPrimary => 'Primary address (tried first)';

  @override
  String get serverFormPrimaryHint => 'e.g. http://192.168.1.100:8188';

  @override
  String get serverFormBackup => 'Backup address (optional)';

  @override
  String get serverFormBackupHint =>
      'Used when the primary address is unreachable, e.g. a public address';

  @override
  String get serverTest => 'Test connection';

  @override
  String get serverTestEmptyPrimary => 'Enter the primary address first';

  @override
  String get serverTestPrimaryOk => 'Primary address reachable';

  @override
  String get serverTestBackupOk => 'Backup address reachable';

  @override
  String get serverTestAllFailed => 'Neither address is reachable';

  @override
  String serverActivateFailed(String name) {
    return 'Could not connect to \"$name\": neither address is reachable';
  }

  @override
  String serverActivatedPrimary(String name) {
    return 'Connected to \"$name\" (primary)';
  }

  @override
  String serverActivatedBackup(String name) {
    return 'Connected to \"$name\" (backup)';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsSectionData => 'Data';

  @override
  String get settingsSectionUpdate => 'Updates';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageFollow => 'Follow system';

  @override
  String get settingsLanguageZh => 'Chinese (Simplified)';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageTitle => 'Choose a language';

  @override
  String get settingsServerEntry => 'Servers';

  @override
  String get settingsServerNone => 'No server configured yet';

  @override
  String settingsServerCount(int count) {
    return '$count servers configured';
  }

  @override
  String get settingsStorage => 'Workflow storage';

  @override
  String get settingsStorageNone => 'Appears after you import a workflow';

  @override
  String settingsStorageCount(int count) {
    return '$count workflows saved';
  }

  @override
  String get settingsSnapshot => 'Workflow snapshots';

  @override
  String get settingsSnapshotNone => 'Created when you run a workflow';

  @override
  String settingsSnapshotCount(int count) {
    return '$count snapshots saved';
  }

  @override
  String get settingsToken => 'GitHub access token';

  @override
  String get settingsTokenSet =>
      'Configured, private repositories can be checked';

  @override
  String get settingsTokenUnset =>
      'Not set. Required to check updates of a private repository';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSubtitle => 'Version info and updates';

  @override
  String get workflowLocalImport => 'Local import';
}
