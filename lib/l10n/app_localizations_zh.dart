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
  String serverDefaultNameWithIndex(int index) {
    return '服务器 $index';
  }

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
  String get settingsTokenSet => '已配置，可检查私有仓库的更新';

  @override
  String get settingsTokenUnset => '未配置。仓库为私有时必须配置才能检查更新';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsAboutSubtitle => '版本信息与检查更新';

  @override
  String get workflowLocalImport => '本地导入';
}
