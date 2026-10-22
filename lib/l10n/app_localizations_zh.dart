// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get navWorkflow => '工作流';

  @override
  String get navHistory => '生成记录';

  @override
  String get navGallery => '画廊';

  @override
  String get navSettings => '设置';

  @override
  String get taskStatusQueued => '排队中';

  @override
  String get taskStatusRunning => '生成中';

  @override
  String get taskStatusCompleted => '已完成';

  @override
  String get taskStatusFailed => '已失败';

  @override
  String get taskStatusInterrupted => '已中断';

  @override
  String get taskPhaseWaiting => '等待执行';

  @override
  String get taskPhaseStarted => '任务开始';

  @override
  String get taskPhaseCached => '命中缓存';

  @override
  String get taskPhaseRunning => '处理中';

  @override
  String taskPhaseRunningNode(String node) {
    return '执行 $node';
  }

  @override
  String taskPhaseRunningPercent(int percent) {
    return '处理中 $percent%';
  }

  @override
  String taskPhaseRunningNodePercent(String node, int percent) {
    return '$node · $percent%';
  }

  @override
  String get taskPhaseDone => '生成成功';

  @override
  String get taskPhaseError => '执行出错';

  @override
  String taskPhaseErrorDetail(String detail) {
    return '执行出错: $detail';
  }

  @override
  String get taskPhaseInterrupted => '任务已被中断';

  @override
  String get taskPhaseLost => '未在服务端找到该任务';

  @override
  String get taskPhaseParseFailed => '结果数据解析失败';

  @override
  String get historyTitle => '生成记录';

  @override
  String get historySyncTooltip => '同步任务状态';

  @override
  String get historySynced => '已同步任务状态';

  @override
  String get historyEmpty => '暂无生成记录';

  @override
  String get historyRerun => '再次运行';

  @override
  String get historyNoSnapshot => '这条记录没有工作流快照（旧版本生成），无法再次运行';

  @override
  String get historySnapshotDeleted => '对应的工作流快照已被删除，无法再次运行';

  @override
  String get historyServerMismatchTitle => '运行服务器不一致';

  @override
  String historyServerMismatchBody(String old, String current) {
    return '这条记录当时运行在「$old」，当前连接的是「$current」。\n\n两台服务器的模型、插件节点可能不同，继续运行可能出现「模型不存在／节点类型不存在」之类的报错。是否继续？';
  }

  @override
  String get historyRunAnyway => '仍要运行';

  @override
  String get historyUnknownServer => '未知服务器';

  @override
  String get historyNoImage => '无图';

  @override
  String get historyDeleteTitle => '删除记录';

  @override
  String historyDeleteConfirm(String title) {
    return '确定删除「$title」这条生成记录吗？';
  }

  @override
  String get historyDeleteImagesNote =>
      '选择“同时删除画廊图片”会一并移除该记录已保存到画廊的本地图片，此操作不可恢复；仅删除记录则保留画廊图片。';

  @override
  String get historyDeleteRecordOnly => '仅删除记录';

  @override
  String get historyDeleteWithImages => '同时删除画廊图片';

  @override
  String get historySaveToLocal => '保存到本地';

  @override
  String get historySaving => '保存中...';

  @override
  String get historySavedToAlbum => '已保存到手机相册';

  @override
  String get historySaveFailed => '保存失败';

  @override
  String get historyVideoLoadFailed => '视频加载失败';

  @override
  String get serverDefaultName => '服务器';

  @override
  String get serverTitle => '服务器配置';

  @override
  String get serverAdd => '新增连接';

  @override
  String get serverEdit => '编辑连接';

  @override
  String get serverEmpty => '还没有保存的服务器连接';

  @override
  String get serverHint =>
      '提示：点击卡片启用对应连接（同时只能启用一个）。每个连接可配置主/备两个地址，连接时先尝试主地址，不通则自动尝试备用地址。';

  @override
  String get serverConnected => '已连接';

  @override
  String get serverActivated => '已启用';

  @override
  String serverPrimaryPrefix(String url) {
    return '主: $url';
  }

  @override
  String serverBackupPrefix(String url) {
    return '备: $url';
  }

  @override
  String get serverEditTooltip => '编辑';

  @override
  String get serverDeleteTitle => '删除连接';

  @override
  String serverDeleteConfirm(String name) {
    return '确定删除「$name」吗？';
  }

  @override
  String get serverFormName => '名称';

  @override
  String get serverFormNameHint => '例如: 家里内网 / 公司外网';

  @override
  String get serverFormPrimary => '主地址（优先尝试）';

  @override
  String get serverFormPrimaryHint => '例如: http://192.168.1.100:8188';

  @override
  String get serverFormBackup => '备用地址（可选）';

  @override
  String get serverFormBackupHint => '主地址不通时使用，如外网地址';

  @override
  String get serverTest => '测试连接';

  @override
  String get serverTestEmptyPrimary => '请先填写主地址';

  @override
  String get serverTestPrimaryOk => '主地址可用';

  @override
  String get serverTestBackupOk => '备用地址可用';

  @override
  String get serverTestAllFailed => '主/备地址均无法连通';

  @override
  String serverActivateFailed(String name) {
    return '「$name」连接失败：主/备地址均无法连通';
  }

  @override
  String serverActivatedPrimary(String name) {
    return '已连接「$name」（主地址）';
  }

  @override
  String serverActivatedBackup(String name) {
    return '已连接「$name」（备用地址）';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsSectionConnection => '连接';

  @override
  String get settingsSectionData => '数据';

  @override
  String get settingsSectionUpdate => '更新';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get settingsLanguage => '界面语言';

  @override
  String get settingsLanguageFollow => '跟随系统';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageTitle => '选择界面语言';

  @override
  String get settingsServerEntry => '服务器连接';

  @override
  String get settingsServerNone => '尚未配置任何服务器';

  @override
  String settingsServerCount(int count) {
    return '已配置 $count 个服务器';
  }

  @override
  String get settingsStorage => '工作流存储';

  @override
  String get settingsStorageNone => '导入或另存工作流后显示';

  @override
  String settingsStorageCount(int count) {
    return '已保存 $count 个工作流';
  }

  @override
  String get settingsSnapshot => '工作流快照';

  @override
  String get settingsSnapshotNone => '运行工作流后自动生成';

  @override
  String settingsSnapshotCount(int count) {
    return '已固化 $count 份快照';
  }

  @override
  String get settingsToken => 'GitHub 访问令牌';

  @override
  String get settingsTokenSet => '已配置';

  @override
  String get settingsTokenUnset => '未配置';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsAboutSubtitle => '版本信息与检查更新';

  @override
  String get workflowLocalImport => '本地导入';

  @override
  String get workflowSnapshotDeleted => '工作流快照已被删除';

  @override
  String get workflowLocalMissing => '本地工作流已不存在，可能已被删除';

  @override
  String get workflowParsedCleared => '解析结果已被清除，请重新解析';

  @override
  String get workflowFetchFailed => '拉取线上工作流内容失败，请检查服务器连接';

  @override
  String get workflowRefetchFailed => '重新拉取工作流失败，请检查服务器连接';

  @override
  String get workflowReparsed => '已重新解析，请确认参数后保存';

  @override
  String get configSaved => '配置已保存';

  @override
  String get configParsingTitle => '解析中...';

  @override
  String configPanelTitle(String name) {
    return '配置面板: $name';
  }

  @override
  String get configReparseTooltip => '重新解析参数';

  @override
  String get configPanelHint => '请勾选需要暴露到手机 App 表单的参数，并为它们起一个易懂的名字。';

  @override
  String get configNoParams => '此工作流没有找到可动态修改的参数。';

  @override
  String configSelectedCount(int count, int total) {
    return '$count/$total 项已选';
  }

  @override
  String configParamCount(int total) {
    return '$total 项参数';
  }

  @override
  String get configSaveButton => '保存表单配置';

  @override
  String get paramAliasHint => '例如: 画面主体描述';

  @override
  String get paramTypeText => '文本';

  @override
  String get paramTypeSeed => '种子';

  @override
  String get paramTypeImage => '图片';

  @override
  String get paramTypeInt => '整数';

  @override
  String get paramTypeFloat => '小数';

  @override
  String get paramTypeBool => '开关';

  @override
  String get paramTypeEnum => '选项';

  @override
  String get paramTypeDefault => '参数';

  @override
  String paramSummaryType(String type) {
    return '类型: $type';
  }

  @override
  String paramSummaryTypeValue(String type, String value) {
    return '类型: $type · 当前值: $value';
  }

  @override
  String get aliasPrompt => '提示词';

  @override
  String get aliasSeed => '随机种子';

  @override
  String get aliasImage => '参考图片';

  @override
  String get aliasSteps => '采样步数';

  @override
  String get aliasCfg => 'CFG 强度';

  @override
  String get aliasSampler => '采样器';

  @override
  String get aliasScheduler => '调度器';

  @override
  String get aliasDenoise => '重绘幅度';

  @override
  String get aliasWidth => '宽度';

  @override
  String get aliasHeight => '高度';

  @override
  String get aliasBatchSize => '生成数量';

  @override
  String get aliasPositive => '正向提示词';

  @override
  String get aliasNegative => '负向提示词';

  @override
  String get aliasCkpt => 'Checkpoint 模型';

  @override
  String get aliasUnet => 'UNet 模型';

  @override
  String get aliasClip => 'CLIP 模型';

  @override
  String get aliasVae => 'VAE 模型';

  @override
  String get aliasLora => 'LoRA 模型';

  @override
  String get aliasControlNet => 'ControlNet';

  @override
  String get aliasUpscaleModel => '放大模型';

  @override
  String get runSnapshotDeleted => '对应的工作流快照已被删除，无法再次运行';

  @override
  String get runNoFormConfig => '未找到有效的表单配置';

  @override
  String runParamsRestored(int count) {
    return '已套用当时的参数（$count 项因配置变更未能套用）';
  }

  @override
  String get runParamsRestoredAll => '已套用当时的参数';

  @override
  String get runDataNotReady => '工作流数据未就绪，请返回重试';

  @override
  String get runImageUploadFailed => '图片上传失败';

  @override
  String get runSubmitFailed => '提交失败：无法连接服务器或请求超时';

  @override
  String get runTaskSubmitted => '任务下发成功！';

  @override
  String runErrorNodes(String nodes) {
    return '，错误节点: $nodes';
  }

  @override
  String runSubmitFailedHttp(String code, String detail) {
    return '提交失败 (HTTP $code)$detail，请检查 ComfyUI 日志';
  }

  @override
  String runTitle(String name) {
    return '运行: $name';
  }

  @override
  String get runNodeConfigTooltip => '节点配置';

  @override
  String get runSubmitting => '下发任务中...';

  @override
  String get runGenerateNow => '立即生成';

  @override
  String get runTextHint => '请输入描述...';

  @override
  String get runRandom => '随机';

  @override
  String get runIntHint => '整数';

  @override
  String get runFloatHint => '数值（可小数）';

  @override
  String get runNumberInvalid => '请输入数字';

  @override
  String runNumberRange(String min, String max) {
    return '范围 $min – $max';
  }

  @override
  String get runSizeRatio => '画面比例';

  @override
  String get runSizeLongEdge => '长边';

  @override
  String get runSizeCustom => '自定义宽高';

  @override
  String get runUseServerImage => '用原图';

  @override
  String get runBoolOn => '开启';

  @override
  String get runBoolOff => '关闭';

  @override
  String runUsingServerImage(String name) {
    return '已用图: $name';
  }

  @override
  String get runChangeImage => '更换图片';

  @override
  String get runPickImage => '选择图片';

  @override
  String get runFoldMenu => '展开与折叠';

  @override
  String get runExpandAll => '展开全部';

  @override
  String get runCollapseAll => '折叠全部';

  @override
  String get parseStatusConnecting => '正在连接服务器…';

  @override
  String get parseLoadTimeout => '加载 ComfyUI 前端超时，请检查服务器连接';

  @override
  String get parseStatusLoadingFrontend => '正在加载 ComfyUI 前端…';

  @override
  String get parseStatusWaitingReady => '正在等待前端就绪…';

  @override
  String get parseStatusConverting => '正在转换工作流…';

  @override
  String get parseConvertTimeout => '转换超时，工作流可能包含不支持的节点';

  @override
  String parseConvertFailed(String error) {
    return '调用前端转换失败：$error';
  }

  @override
  String parseTitle(String name) {
    return '解析: $name';
  }

  @override
  String get homeGroupApi => 'API 工作流 · 可直接运行';

  @override
  String get homeGroupUi => 'UI 工作流 · 需解析';

  @override
  String get homeWorkflowSourceNote =>
      '提示：工作流来自 ComfyUI 的 userdata/workflows 目录。UI 格式是 ComfyUI 界面保存的原始结构，需转换为 API 结构后才能运行。可在应用内直接解析转换，无需安装插件；也可在 ComfyUI 安装 ComfyUI-AutoSaveAPI 插件自动生成 API JSON（https://github.com/Volitasa/ComfyUI-AutoSaveAPI.git）。';

  @override
  String get uiStatusNotParsed => '尚未解析 · 点击解析';

  @override
  String get uiStatusStale => '服务器有更新，可重新解析';

  @override
  String get uiStatusParsed => '已解析';

  @override
  String uiStatusParsedWithCount(int count) {
    return '已解析 · $count 项参数';
  }

  @override
  String get statusChecking => '检查中…';

  @override
  String get menuMore => '更多操作';

  @override
  String get uiMenuParse => '解析';

  @override
  String get uiMenuReparse => '重新解析';

  @override
  String get uiMenuClearParse => '清除解析缓存';

  @override
  String get homeFetchFailed => '拉取工作流失败，请检查服务器连接';

  @override
  String get homeInvalidJson => '工作流文件不是有效的 JSON';

  @override
  String get homeParseFailed => '解析失败';

  @override
  String get clearParseBody => '清除后会回到未解析状态，可随时从服务器重新解析。\n\n已保存的节点配置不受影响。';

  @override
  String get clearParseDone => '已清除解析结果';

  @override
  String get homeDisconnectedTitle => '尚未连接到服务器';

  @override
  String get homeDisconnectedBody => '请先配置并启用一个服务器连接';

  @override
  String get homeGoToConfig => '前往配置';

  @override
  String get homeEmptyTitle => '未找到工作流';

  @override
  String get homeEmptyBody => '服务器上没有找到工作流 JSON 文件';

  @override
  String get wfStatusUnconfigured => '未配置';

  @override
  String get wfStatusStale => '内容已更新，需重新确认配置';

  @override
  String wfStatusConfigured(int count) {
    return '$count 项参数已配置';
  }

  @override
  String get wfMenuSaveLocal => '存入本地库';

  @override
  String get wfMenuReconfig => '重新配置节点';

  @override
  String get wfMenuRefresh => '刷新内容';

  @override
  String get homeRechecked => '已重新检查';

  @override
  String get homeFetchContentFailed => '拉取工作流内容失败，请检查服务器连接';

  @override
  String get homeSavedToLocal => '已存入本地库';

  @override
  String get nameLabel => '名称';

  @override
  String get clear => '清除';

  @override
  String get localEmpty => '本地库为空';

  @override
  String localSummary(int count, String size) {
    return '本地库 $count 项 · $size';
  }

  @override
  String get localImportButton => '导入工作流 JSON';

  @override
  String get localImportNote =>
      '提示：这里导入的是 ComfyUI 的 API 格式 JSON（_api.json），即以节点 ID 为键、含 class_type 与 inputs 的结构；普通 UI 界面保存的 workflow JSON 不适用。';

  @override
  String get localNoWorkflows => '还没有本地工作流';

  @override
  String get localNoWorkflowsHint => '导入或另存的工作流会保存在这里';

  @override
  String get localFooterNote => '来自你自己的文件，与服务器无关，可重命名或删除。删除后无法恢复。';

  @override
  String get menuRename => '重命名';

  @override
  String get localDeleteTitle => '删除本地工作流';

  @override
  String localDeleteBody(String name) {
    return '确定删除「$name」吗？\n\n它的节点配置会一并清除，删除后无法恢复。已生成的记录不受影响。';
  }

  @override
  String get localDeleted => '已删除';

  @override
  String get localJsonParseFailed => 'JSON 文件解析失败';

  @override
  String get homeRefreshTooltip => '刷新工作流列表';

  @override
  String get homeTabServer => '服务器';

  @override
  String get homeTabLocal => '本地';

  @override
  String get notConnected => '未连接';

  @override
  String get galleryRefreshTooltip => '刷新';

  @override
  String get galleryEmptyTitle => '还没有生成图片';

  @override
  String get galleryEmptyHint => '生成成功后图片会自动保存到这里';

  @override
  String get galleryImageMissing => '图片已不存在，请刷新画廊';

  @override
  String get gallerySaved => '✅ 已保存到手机相册';

  @override
  String get gallerySaveFailed => '保存失败';

  @override
  String get galleryDeleteTitle => '删除图片';

  @override
  String get galleryDeleteBody => '确定从画廊删除这张图片吗？';

  @override
  String get galleryShareTooltip => '分享';

  @override
  String get gallerySaving => '保存中...';

  @override
  String get gallerySaveToAlbum => '保存到相册';

  @override
  String get galleryShareSoon => '分享功能即将上线';

  @override
  String get storageTitle => '工作流存储';

  @override
  String get storageEmpty => '本机还没有保存任何工作流';

  @override
  String storageSummary(int total, String size) {
    return '共 $total 项 · 合计 $size';
  }

  @override
  String storageGroupLocal(int count) {
    return '本地资产 · $count 项';
  }

  @override
  String storageGroupParsed(int count) {
    return '解析缓存 · $count 项';
  }

  @override
  String get storageParsedNote => '解析缓存由服务器上的 UI 工作流转换而来，清除后回到未解析状态，可随时重新解析。';

  @override
  String storageOrigin(String name) {
    return '来源 $name';
  }

  @override
  String storageParsedAt(String time, String size) {
    return 'UI 工作流解析 · $time · $size';
  }

  @override
  String get unknownConnection => '未知连接';

  @override
  String storageClearCacheBody(String name) {
    return '确定清除「$name」的解析结果吗？\n\n清除后回到未解析状态，在服务器列表里可以重新解析。已保存的节点配置不受影响。';
  }

  @override
  String get snapshotDeleteTitle => '删除快照';

  @override
  String snapshotDeleteBody(String name, int count) {
    return '确定删除「$name」吗？\n\n删除后，引用它的 $count 条生成记录将无法再次运行。';
  }

  @override
  String get snapshotDeleted => '快照已删除';

  @override
  String get snapshotNotRecorded => '未记录';

  @override
  String get snapshotTitle => '工作流快照';

  @override
  String get snapshotEmpty => '暂无工作流快照';

  @override
  String snapshotFrozenAt(String time, String size) {
    return '固化时间 $time · $size';
  }

  @override
  String snapshotSourceServer(String name) {
    return '来源服务器 $name';
  }

  @override
  String snapshotRefCount(int count) {
    return '被 $count 条生成记录引用';
  }

  @override
  String get snapshotNoRef => '未被任何生成记录引用';

  @override
  String get tokenTitle => 'GitHub 访问令牌';

  @override
  String get tokenSaved => '令牌已保存';

  @override
  String get tokenCleared => '令牌已清除';

  @override
  String get tokenConfigured => '已配置';

  @override
  String get tokenClearButton => '清除令牌';

  @override
  String get tokenLocalOnlyNote => '令牌仅保存在本机，不会上传。';

  @override
  String get updateCheckButton => '检查更新';

  @override
  String get updateSourceNote => '更新来源：GitHub Releases';

  @override
  String aboutVersionBuild(String version, String build) {
    return '版本 $version（构建 $build）';
  }

  @override
  String get updateChecking => '正在检查更新…';

  @override
  String updateUpToDate(String version) {
    return '当前已是最新版本 $version';
  }

  @override
  String get updateCheckFailed => '检查更新失败';

  @override
  String get retry => '重试';

  @override
  String get configureToken => '配置令牌';

  @override
  String updateAvailableTitle(String version) {
    return '发现新版本 $version';
  }

  @override
  String updateAvailableOtherPlatform(String version) {
    return '发现新版本 $version，当前平台不支持应用内安装，请到 Release 页面手动下载';
  }

  @override
  String get releaseNotesTitle => '更新说明';

  @override
  String get changelogTitle => '完整变更记录';

  @override
  String updateDownloadingPercent(String percent) {
    return '下载中 $percent%';
  }

  @override
  String get updateDownloading => '正在下载…';

  @override
  String get updateDownloadInstall => '下载并安装';

  @override
  String installLaunchFailed(String message) {
    return '无法唤起安装界面：$message';
  }

  @override
  String get saveAlbumPermission => '需要相册权限';

  @override
  String get saveAlbumTitle => '保存到相册';

  @override
  String get saveAlbumBody => '这张 PNG 内嵌了工作流信息。选择保存方式：';

  @override
  String get saveAlbumPlain => '普通图片（剔除信息）';

  @override
  String get saveAlbumWithWorkflow => '带工作流原图';

  @override
  String get parseBadPayload => '前端返回了无法识别的数据';

  @override
  String get parseNoWorkflow => '前端未返回工作流结构';

  @override
  String get parseUnreadable => '解析结果无法读取';

  @override
  String get convertEmpty => '转换结果为空（工作流可能没有可运行的节点）';

  @override
  String get convertUiNotApi => '前端返回了 UI 结构而非 API 结构';

  @override
  String convertBadNode(String index) {
    return '转换结果第 $index 项不是有效的 API 节点';
  }

  @override
  String get updateRepoForbiddenWithToken =>
      '仓库不可访问：请确认令牌对该仓库有 Contents 读取权限，且未过期';

  @override
  String get updateRepoForbidden =>
      '仓库不可访问。若该仓库是私有的，请在「设置 → GitHub 访问令牌」中填入只读令牌后重试';

  @override
  String get updateTokenInvalid => '令牌无效或已过期，请到「设置 → GitHub 访问令牌」更新或清除';

  @override
  String get updateRateLimitedWithToken => 'GitHub 拒绝了请求（令牌权限不足或触发限流），请稍后再试';

  @override
  String get updateRateLimited => 'GitHub 接口访问受限（匿名请求每小时 60 次），配置访问令牌可放宽限额';

  @override
  String updateHttpFailed(String code) {
    return '查询更新失败（HTTP $code）';
  }

  @override
  String get updateNoRelease => '该仓库还没有发布带安装包的版本（仅有 git tag 不会被识别）';

  @override
  String updateBadTag(String tag) {
    return '发布版本号无法识别（$tag）';
  }

  @override
  String get updateTimeout => '连接 GitHub 超时，请检查网络后重试';

  @override
  String get updateUnreachable => '无法连接 GitHub，请检查网络后重试';

  @override
  String get updateQueryFailed => '查询更新失败，请检查网络后重试';

  @override
  String get updateNoAsset => '该版本没有附带安装包';

  @override
  String get updateNoApk => '该版本没有可安装的 APK';

  @override
  String get updateAssetMissing => '安装包地址缺失，请稍后重试';

  @override
  String get updateDownloadTimeout => '下载超时，请检查网络后重试';

  @override
  String get updateDownloadInterrupted => '下载失败，网络连接已中断';

  @override
  String get updateDownloadFailed => '下载失败，请检查网络后重试';

  @override
  String get updateDownload404Token => '安装包下载失败（404），请确认令牌仍有该仓库的读取权限';

  @override
  String get updateDownload404 => '安装包下载失败（404）';

  @override
  String updateDownloadHttp(String code) {
    return '下载失败（HTTP $code）';
  }

  @override
  String get updateDownloadAborted => '下载中断，请重试';

  @override
  String get updateWriteFailed => '安装包写入失败';

  @override
  String get updateCheckFailedRetry => '检查更新失败，请稍后重试';

  @override
  String get updateNoPending => '没有待下载的版本';

  @override
  String get updateDownloadFailedRetry => '下载失败，请稍后重试';

  @override
  String get localSourceImport => '导入';

  @override
  String get localSourceSaved => '另存';

  @override
  String get unknownSize => '未知大小';

  @override
  String get configExpandAll => '一键展开';

  @override
  String get configCollapseAll => '一键折叠';

  @override
  String get configSearchHint => '搜索参数或节点';

  @override
  String get configSearchEmpty => '没有匹配的参数';

  @override
  String get configNodeSelectAll => '全选本节点';

  @override
  String get configNodeClearAll => '取消本节点';

  @override
  String get historySearchHint => '搜索工作流或提示词';

  @override
  String get historySearchEmpty => '没有匹配的记录';

  @override
  String get historyFilterAll => '全部';

  @override
  String get historyFilterPending => '进行中';

  @override
  String get runSelectPlaceholder => '请选择';

  @override
  String get runModelMissing => '服务器没有此模型';

  @override
  String get runSelectModelFirst => '请先选择模型';

  @override
  String get runRefreshModels => '刷新模型列表';

  @override
  String get runOptionsRefreshed => '已刷新';

  @override
  String get runOptionsRefreshFailed => '刷新失败，请检查连接';

  @override
  String wfLastRun(String time) {
    return '上次运行 $time';
  }

  @override
  String get wfNeverRun => '尚未运行';
}
