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
  String get serverTitle => 'Server config';

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
  String get settingsServerEntry => 'Server connections';

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

  @override
  String get workflowSnapshotDeleted => 'This workflow snapshot was deleted';

  @override
  String get workflowLocalMissing =>
      'This local workflow no longer exists (it may have been deleted)';

  @override
  String get workflowParsedCleared =>
      'The parsed result was cleared. Please parse it again';

  @override
  String get workflowFetchFailed =>
      'Could not fetch the workflow content. Check the server connection';

  @override
  String get workflowRefetchFailed =>
      'Failed to re-fetch the workflow. Check the server connection';

  @override
  String get workflowReparsed => 'Re-parsed. Confirm the parameters, then save';

  @override
  String get configSaved => 'Configuration saved';

  @override
  String get configParsingTitle => 'Parsing...';

  @override
  String configPanelTitle(String name) {
    return 'Config panel: $name';
  }

  @override
  String get configReparseTooltip => 'Re-parse parameters';

  @override
  String get configPanelHint =>
      'Select the parameters you want to expose in the mobile form, and give each one a name that is easy to understand.';

  @override
  String get configNoParams =>
      'No adjustable parameters were found in this workflow.';

  @override
  String configSelectedCount(int count, int total) {
    return '$count/$total selected';
  }

  @override
  String configParamCount(int total) {
    return '$total parameters';
  }

  @override
  String get configSaveButton => 'Save form configuration';

  @override
  String get paramAliasHint => 'e.g. description of the subject';

  @override
  String get paramTypeText => 'Text';

  @override
  String get paramTypeSeed => 'Seed';

  @override
  String get paramTypeImage => 'Image';

  @override
  String get paramTypeInt => 'Integer';

  @override
  String get paramTypeFloat => 'Decimal';

  @override
  String get paramTypeBool => 'Toggle';

  @override
  String get paramTypeEnum => 'Choice';

  @override
  String get paramTypeDefault => 'Parameter';

  @override
  String paramSummaryType(String type) {
    return 'Type: $type';
  }

  @override
  String paramSummaryTypeValue(String type, String value) {
    return 'Type: $type · Current: $value';
  }

  @override
  String get aliasPrompt => 'Prompt';

  @override
  String get aliasSeed => 'Random seed';

  @override
  String get aliasImage => 'Reference image';

  @override
  String get aliasSteps => 'Sampling steps';

  @override
  String get aliasCfg => 'CFG scale';

  @override
  String get aliasSampler => 'Sampler';

  @override
  String get aliasScheduler => 'Scheduler';

  @override
  String get aliasDenoise => 'Denoise strength';

  @override
  String get aliasWidth => 'Width';

  @override
  String get aliasHeight => 'Height';

  @override
  String get aliasBatchSize => 'Batch count';

  @override
  String get aliasPositive => 'Positive prompt';

  @override
  String get aliasNegative => 'Negative prompt';

  @override
  String get aliasCkpt => 'Checkpoint model';

  @override
  String get aliasUnet => 'UNet model';

  @override
  String get aliasClip => 'CLIP model';

  @override
  String get aliasVae => 'VAE model';

  @override
  String get aliasLora => 'LoRA model';

  @override
  String get aliasControlNet => 'ControlNet';

  @override
  String get aliasUpscaleModel => 'Upscale model';

  @override
  String get runSnapshotDeleted =>
      'The matching workflow snapshot was deleted, so it cannot be run again';

  @override
  String get runNoFormConfig => 'No valid form configuration found';

  @override
  String runParamsRestored(int count) {
    return 'Parameters from that run were applied ($count could not be applied because the configuration changed)';
  }

  @override
  String get runParamsRestoredAll => 'Parameters from that run were applied';

  @override
  String get runDataNotReady =>
      'Workflow data is not ready. Go back and try again';

  @override
  String get runImageUploadFailed => 'Image upload failed';

  @override
  String get runSubmitFailed =>
      'Submit failed: the server is unreachable or the request timed out';

  @override
  String get runTaskSubmitted => 'Task submitted!';

  @override
  String runErrorNodes(String nodes) {
    return ', error nodes: $nodes';
  }

  @override
  String runSubmitFailedHttp(String code, String detail) {
    return 'Submit failed (HTTP $code)$detail. Check the ComfyUI log';
  }

  @override
  String runTitle(String name) {
    return 'Run: $name';
  }

  @override
  String get runNodeConfigTooltip => 'Node configuration';

  @override
  String get runSubmitting => 'Submitting...';

  @override
  String get runGenerateNow => 'Generate';

  @override
  String get runTextHint => 'Enter a description...';

  @override
  String get runRandom => 'Random';

  @override
  String get runIntHint => 'Integer';

  @override
  String get runFloatHint => 'Number (decimals allowed)';

  @override
  String get runBoolOn => 'On';

  @override
  String get runBoolOff => 'Off';

  @override
  String runUsingServerImage(String name) {
    return 'Using image: $name';
  }

  @override
  String get runChangeImage => 'Change image';

  @override
  String get runPickImage => 'Choose image';

  @override
  String get parseStatusConnecting => 'Connecting to the server...';

  @override
  String get parseLoadTimeout =>
      'Timed out loading the ComfyUI frontend. Check the server connection';

  @override
  String get parseStatusLoadingFrontend => 'Loading the ComfyUI frontend...';

  @override
  String get parseStatusWaitingReady =>
      'Waiting for the frontend to be ready...';

  @override
  String get parseStatusConverting => 'Converting the workflow...';

  @override
  String get parseConvertTimeout =>
      'Conversion timed out. The workflow may contain unsupported nodes';

  @override
  String parseConvertFailed(String error) {
    return 'Frontend conversion failed: $error';
  }

  @override
  String parseTitle(String name) {
    return 'Parse: $name';
  }

  @override
  String get homeGroupApi => 'API workflows · ready to run';

  @override
  String get homeGroupUi => 'UI workflows · need parsing';

  @override
  String get homeUiFormatNote =>
      'The UI format is the raw structure saved by the ComfyUI interface; it must be converted to the API structure before it can run.';

  @override
  String get homeWorkflowSourceNote =>
      'Tip: workflows come from ComfyUI\'s userdata/workflows directory. The API JSON files are generated automatically by the ComfyUI-AutoSaveAPI plugin (https://github.com/Volitasa/ComfyUI-AutoSaveAPI.git).';

  @override
  String get uiStatusNotParsed => 'Not parsed yet · tap to parse';

  @override
  String get uiStatusStale => 'Updated on the server, re-parse available';

  @override
  String get uiStatusParsed => 'Parsed';

  @override
  String uiStatusParsedWithCount(int count) {
    return 'Parsed · $count parameters';
  }

  @override
  String get statusChecking => 'Checking...';

  @override
  String get menuMore => 'More actions';

  @override
  String get uiMenuParse => 'Parse';

  @override
  String get uiMenuReparse => 'Re-parse';

  @override
  String get uiMenuClearParse => 'Clear parsed cache';

  @override
  String get homeFetchFailed =>
      'Could not load workflows. Check the server connection';

  @override
  String get homeInvalidJson => 'The workflow file is not valid JSON';

  @override
  String get homeParseFailed => 'Parsing failed';

  @override
  String get clearParseBody =>
      'Clearing returns it to the unparsed state; you can parse it again from the server at any time.\n\nSaved node configuration is not affected.';

  @override
  String get clearParseDone => 'Parsed result cleared';

  @override
  String get homeDisconnectedTitle => 'Not connected to a server';

  @override
  String get homeDisconnectedBody =>
      'Configure and enable a server connection first';

  @override
  String get homeGoToConfig => 'Go to settings';

  @override
  String get homeEmptyTitle => 'No workflows found';

  @override
  String get homeEmptyBody => 'No workflow JSON files were found on the server';

  @override
  String get wfStatusUnconfigured => 'Not configured';

  @override
  String get wfStatusStale =>
      'Content changed; please review the configuration';

  @override
  String wfStatusConfigured(int count) {
    return '$count parameters configured';
  }

  @override
  String get wfMenuSaveLocal => 'Save to local library';

  @override
  String get wfMenuReconfig => 'Reconfigure nodes';

  @override
  String get wfMenuRefresh => 'Refresh content';

  @override
  String get homeRechecked => 'Re-checked';

  @override
  String get homeFetchContentFailed =>
      'Failed to fetch the workflow content. Check the server connection';

  @override
  String get homeSavedToLocal => 'Saved to the local library';

  @override
  String get nameLabel => 'Name';

  @override
  String get clear => 'Clear';

  @override
  String get localEmpty => 'Local library is empty';

  @override
  String localSummary(int count, String size) {
    return 'Local library: $count items · $size';
  }

  @override
  String get localImportButton => 'Import workflow JSON';

  @override
  String get localImportNote =>
      'Tip: import the ComfyUI API format JSON (_api.json) — keyed by node ID, with class_type and inputs. The workflow JSON saved from the normal UI does not apply here.';

  @override
  String get localNoWorkflows => 'No local workflows yet';

  @override
  String get localNoWorkflowsHint => 'Imported or saved workflows appear here';

  @override
  String get localFooterNote =>
      'These come from your own files and are unrelated to the server. You can rename or delete them. Deletion cannot be undone.';

  @override
  String get menuRename => 'Rename';

  @override
  String get localDeleteTitle => 'Delete local workflow';

  @override
  String localDeleteBody(String name) {
    return 'Delete \"$name\"?\n\nIts node configuration will be removed as well. This cannot be undone. Existing generation records are not affected.';
  }

  @override
  String get localDeleted => 'Deleted';

  @override
  String get localJsonParseFailed => 'Failed to parse the JSON file';

  @override
  String get homeRefreshTooltip => 'Refresh workflow list';

  @override
  String get homeTabServer => 'Server';

  @override
  String get homeTabLocal => 'Local';

  @override
  String get notConnected => 'Not connected';

  @override
  String get galleryRefreshTooltip => 'Refresh';

  @override
  String get galleryEmptyTitle => 'No generated images yet';

  @override
  String get galleryEmptyHint =>
      'Images are saved here automatically after generation';

  @override
  String get galleryImageMissing =>
      'The image no longer exists. Please refresh the gallery';

  @override
  String get gallerySaved => '✅ Saved to the phone gallery';

  @override
  String get gallerySaveFailed => 'Save failed';

  @override
  String get galleryDeleteTitle => 'Delete image';

  @override
  String get galleryDeleteBody => 'Delete this image from the gallery?';

  @override
  String get galleryShareTooltip => 'Share';

  @override
  String get gallerySaving => 'Saving...';

  @override
  String get gallerySaveToAlbum => 'Save to album';

  @override
  String get galleryShareSoon => 'Sharing is coming soon';

  @override
  String get storageTitle => 'Workflow storage';

  @override
  String get storageEmpty => 'No workflows saved on this device';

  @override
  String storageSummary(int total, String size) {
    return '$total items · $size in total';
  }

  @override
  String storageGroupLocal(int count) {
    return 'Local assets · $count';
  }

  @override
  String storageGroupParsed(int count) {
    return 'Parsed cache · $count';
  }

  @override
  String get storageParsedNote =>
      'The parsed cache comes from converting UI workflows on the server. Clearing it returns them to the unparsed state; you can parse them again at any time.';

  @override
  String storageOrigin(String name) {
    return 'Source: $name';
  }

  @override
  String storageParsedAt(String time, String size) {
    return 'Parsed from UI workflow · $time · $size';
  }

  @override
  String get unknownConnection => 'Unknown connection';

  @override
  String storageClearCacheBody(String name) {
    return 'Clear the parsed result of \"$name\"?\n\nIt returns to the unparsed state and can be parsed again from the server list. Saved node configuration is not affected.';
  }

  @override
  String get snapshotDeleteTitle => 'Delete snapshot';

  @override
  String snapshotDeleteBody(String name, int count) {
    return 'Delete \"$name\"?\n\nAfter deletion, the $count generation records referencing it cannot be run again.';
  }

  @override
  String get snapshotDeleted => 'Snapshot deleted';

  @override
  String get snapshotNotRecorded => 'Not recorded';

  @override
  String get snapshotTitle => 'Workflow snapshots';

  @override
  String get snapshotEmpty => 'No workflow snapshots yet';

  @override
  String snapshotFrozenAt(String time, String size) {
    return 'Saved $time · $size';
  }

  @override
  String snapshotSourceServer(String name) {
    return 'Source server: $name';
  }

  @override
  String snapshotRefCount(int count) {
    return 'Referenced by $count generation records';
  }

  @override
  String get snapshotNoRef => 'Not referenced by any generation record';

  @override
  String get tokenTitle => 'GitHub access token';

  @override
  String get tokenSaved => 'Token saved';

  @override
  String get tokenCleared => 'Token cleared';

  @override
  String get tokenConfigured => 'Configured';

  @override
  String get tokenClearButton => 'Clear token';

  @override
  String get tokenLocalOnlyNote =>
      'The token is stored on this device only and is never uploaded.';

  @override
  String get updateCheckButton => 'Check for updates';

  @override
  String get updateSourceNote => 'Update source: GitHub Releases';

  @override
  String aboutVersionBuild(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get updateChecking => 'Checking for updates...';

  @override
  String updateUpToDate(String version) {
    return 'You are on the latest version $version';
  }

  @override
  String get updateCheckFailed => 'Update check failed';

  @override
  String get retry => 'Retry';

  @override
  String get configureToken => 'Configure token';

  @override
  String updateAvailableTitle(String version) {
    return 'New version $version available';
  }

  @override
  String updateAvailableOtherPlatform(String version) {
    return 'New version $version found. In-app installation is not supported on this platform; download it manually from the Release page.';
  }

  @override
  String get releaseNotesTitle => 'Release notes';

  @override
  String get changelogTitle => 'Full changelog';

  @override
  String updateDownloadingPercent(String percent) {
    return 'Downloading $percent%';
  }

  @override
  String get updateDownloading => 'Downloading...';

  @override
  String get updateDownloadInstall => 'Download and install';

  @override
  String installLaunchFailed(String message) {
    return 'Could not open the installer: $message';
  }

  @override
  String get saveAlbumPermission => 'Gallery permission required';

  @override
  String get saveAlbumTitle => 'Save to album';

  @override
  String get saveAlbumBody =>
      'This PNG embeds workflow information. Choose how to save it:';

  @override
  String get saveAlbumPlain => 'Plain image (info removed)';

  @override
  String get saveAlbumWithWorkflow => 'Original image with workflow';

  @override
  String get parseBadPayload => 'The frontend returned unrecognized data';

  @override
  String get parseNoWorkflow =>
      'The frontend did not return a workflow structure';

  @override
  String get parseUnreadable => 'The parse result could not be read';

  @override
  String get convertEmpty =>
      'The conversion result is empty (the workflow may have no runnable nodes)';

  @override
  String get convertUiNotApi =>
      'The frontend returned a UI structure instead of an API structure';

  @override
  String convertBadNode(String index) {
    return 'Item $index of the conversion result is not a valid API node';
  }

  @override
  String get updateRepoForbiddenWithToken =>
      'Repository not accessible: make sure the token has Contents read permission for this repository and has not expired';

  @override
  String get updateRepoForbidden =>
      'Repository not accessible. If it is private, enter a read-only token in \"Settings → GitHub access token\" and try again';

  @override
  String get updateTokenInvalid =>
      'The GitHub token is invalid or expired. Update it in \"Settings → GitHub access token\"; if the repository is public, just clear the token';

  @override
  String get updateRateLimitedWithToken =>
      'GitHub rejected the request (insufficient token permission or rate limit). Try again later';

  @override
  String get updateRateLimited =>
      'GitHub API access is limited (60 anonymous requests per hour). Configure a token to raise the limit';

  @override
  String updateHttpFailed(String code) {
    return 'Update check failed (HTTP $code)';
  }

  @override
  String get updateNoRelease =>
      'This repository has no release with an installer (a git tag alone is not recognized)';

  @override
  String updateBadTag(String tag) {
    return 'Unrecognized release version ($tag)';
  }

  @override
  String get updateTimeout =>
      'Timed out connecting to GitHub. Check your network and try again';

  @override
  String get updateUnreachable =>
      'Cannot reach GitHub. Check your network and try again';

  @override
  String get updateQueryFailed =>
      'Update check failed. Check your network and try again';

  @override
  String get updateNoAsset => 'This version has no installer attached';

  @override
  String get updateNoApk => 'This version has no installable APK';

  @override
  String get updateAssetMissing =>
      'The installer URL is missing. Try again later';

  @override
  String get updateDownloadTimeout =>
      'Download timed out. Check your network and try again';

  @override
  String get updateDownloadInterrupted =>
      'Download failed: the network connection was interrupted';

  @override
  String get updateDownloadFailed =>
      'Download failed. Check your network and try again';

  @override
  String get updateDownload404Token =>
      'Installer download failed (404). Make sure the token still has read access to this repository';

  @override
  String get updateDownload404 => 'Installer download failed (404)';

  @override
  String updateDownloadHttp(String code) {
    return 'Download failed (HTTP $code)';
  }

  @override
  String get updateDownloadAborted => 'Download interrupted. Please try again';

  @override
  String get updateWriteFailed => 'Failed to write the installer';

  @override
  String get updateCheckFailedRetry =>
      'Update check failed. Please try again later';

  @override
  String get updateNoPending => 'No version pending download';

  @override
  String get updateDownloadFailedRetry =>
      'Download failed. Please try again later';

  @override
  String get localSourceImport => 'Imported';

  @override
  String get localSourceSaved => 'Saved from server';

  @override
  String get unknownSize => 'Unknown size';

  @override
  String get configExpandAll => 'Expand all';

  @override
  String get configCollapseAll => 'Collapse all';

  @override
  String get configSearchHint => 'Search params or nodes';

  @override
  String get configSearchEmpty => 'No matching params';

  @override
  String get configNodeSelectAll => 'Select all in this node';

  @override
  String get configNodeClearAll => 'Clear this node';
}
