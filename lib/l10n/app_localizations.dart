import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 通用：取消
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// 通用：删除
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// 通用：保存
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// 底部导航：工作流
  ///
  /// In zh, this message translates to:
  /// **'工作流'**
  String get navWorkflow;

  /// 底部导航：生成记录
  ///
  /// In zh, this message translates to:
  /// **'生成记录'**
  String get navHistory;

  /// 底部导航：画廊
  ///
  /// In zh, this message translates to:
  /// **'画廊'**
  String get navGallery;

  /// 底部导航：设置
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// 任务状态：排队中
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get taskStatusQueued;

  /// 任务状态：生成中
  ///
  /// In zh, this message translates to:
  /// **'生成中'**
  String get taskStatusRunning;

  /// 任务状态：已完成
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get taskStatusCompleted;

  /// 任务状态：已失败
  ///
  /// In zh, this message translates to:
  /// **'已失败'**
  String get taskStatusFailed;

  /// 任务状态：已中断
  ///
  /// In zh, this message translates to:
  /// **'已中断'**
  String get taskStatusInterrupted;

  /// 任务阶段：等待服务端开始执行
  ///
  /// In zh, this message translates to:
  /// **'等待执行'**
  String get taskPhaseWaiting;

  /// 任务阶段：开始执行
  ///
  /// In zh, this message translates to:
  /// **'任务开始'**
  String get taskPhaseStarted;

  /// 任务阶段：命中节点缓存
  ///
  /// In zh, this message translates to:
  /// **'命中缓存'**
  String get taskPhaseCached;

  /// 任务阶段：执行中（无进度、无节点名）
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get taskPhaseRunning;

  /// 任务阶段：正在执行某节点
  ///
  /// In zh, this message translates to:
  /// **'执行 {node}'**
  String taskPhaseRunningNode(String node);

  /// 任务阶段：执行中（只有进度百分比）
  ///
  /// In zh, this message translates to:
  /// **'处理中 {percent}%'**
  String taskPhaseRunningPercent(int percent);

  /// 任务阶段：执行中（节点名 + 进度百分比）
  ///
  /// In zh, this message translates to:
  /// **'{node} · {percent}%'**
  String taskPhaseRunningNodePercent(String node, int percent);

  /// 任务阶段：正常结束
  ///
  /// In zh, this message translates to:
  /// **'生成成功'**
  String get taskPhaseDone;

  /// 任务阶段：执行出错（无详情）
  ///
  /// In zh, this message translates to:
  /// **'执行出错'**
  String get taskPhaseError;

  /// 任务阶段：执行出错（带服务端错误详情）
  ///
  /// In zh, this message translates to:
  /// **'执行出错: {detail}'**
  String taskPhaseErrorDetail(String detail);

  /// 任务阶段：被中断
  ///
  /// In zh, this message translates to:
  /// **'任务已被中断'**
  String get taskPhaseInterrupted;

  /// 任务阶段：服务端重启或任务丢失
  ///
  /// In zh, this message translates to:
  /// **'未在服务端找到该任务'**
  String get taskPhaseLost;

  /// 任务阶段：本地解析服务端结果失败
  ///
  /// In zh, this message translates to:
  /// **'结果数据解析失败'**
  String get taskPhaseParseFailed;

  /// 历史页标题
  ///
  /// In zh, this message translates to:
  /// **'生成记录'**
  String get historyTitle;

  /// 历史页同步按钮提示
  ///
  /// In zh, this message translates to:
  /// **'同步任务状态'**
  String get historySyncTooltip;

  /// 历史页同步后的提示
  ///
  /// In zh, this message translates to:
  /// **'已同步任务状态'**
  String get historySynced;

  /// 历史页空态
  ///
  /// In zh, this message translates to:
  /// **'暂无生成记录'**
  String get historyEmpty;

  /// 历史记录操作：再次运行
  ///
  /// In zh, this message translates to:
  /// **'再次运行'**
  String get historyRerun;

  /// 无快照时无法再次运行
  ///
  /// In zh, this message translates to:
  /// **'这条记录没有工作流快照（旧版本生成），无法再次运行'**
  String get historyNoSnapshot;

  /// 快照已删除时无法再次运行
  ///
  /// In zh, this message translates to:
  /// **'对应的工作流快照已被删除，无法再次运行'**
  String get historySnapshotDeleted;

  /// 跨服务器再次运行的确认标题
  ///
  /// In zh, this message translates to:
  /// **'运行服务器不一致'**
  String get historyServerMismatchTitle;

  /// 跨服务器再次运行的确认正文
  ///
  /// In zh, this message translates to:
  /// **'这条记录当时运行在「{old}」，当前连接的是「{current}」。\n\n两台服务器的模型、插件节点可能不同，继续运行可能出现「模型不存在／节点类型不存在」之类的报错。是否继续？'**
  String historyServerMismatchBody(String old, String current);

  /// 跨服务器仍要运行
  ///
  /// In zh, this message translates to:
  /// **'仍要运行'**
  String get historyRunAnyway;

  /// 找不到对应连接时的占位名
  ///
  /// In zh, this message translates to:
  /// **'未知服务器'**
  String get historyUnknownServer;

  /// 已完成任务没有输出图时的占位
  ///
  /// In zh, this message translates to:
  /// **'无图'**
  String get historyNoImage;

  /// 删除记录确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除记录'**
  String get historyDeleteTitle;

  /// 删除记录确认正文
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{title}」这条生成记录吗？'**
  String historyDeleteConfirm(String title);

  /// 删除记录时关于画廊图片的说明
  ///
  /// In zh, this message translates to:
  /// **'选择“同时删除画廊图片”会一并移除该记录已保存到画廊的本地图片，此操作不可恢复；仅删除记录则保留画廊图片。'**
  String get historyDeleteImagesNote;

  /// 只删记录保留图片
  ///
  /// In zh, this message translates to:
  /// **'仅删除记录'**
  String get historyDeleteRecordOnly;

  /// 连带删除画廊图片
  ///
  /// In zh, this message translates to:
  /// **'同时删除画廊图片'**
  String get historyDeleteWithImages;

  /// 媒体查看器保存按钮
  ///
  /// In zh, this message translates to:
  /// **'保存到本地'**
  String get historySaveToLocal;

  /// 媒体保存中
  ///
  /// In zh, this message translates to:
  /// **'保存中...'**
  String get historySaving;

  /// 保存成功提示
  ///
  /// In zh, this message translates to:
  /// **'已保存到手机相册'**
  String get historySavedToAlbum;

  /// 保存失败提示
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get historySaveFailed;

  /// 视频加载失败
  ///
  /// In zh, this message translates to:
  /// **'视频加载失败'**
  String get historyVideoLoadFailed;

  /// 连接没有名称时的默认名
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get serverDefaultName;

  /// 新增连接未填名称时的默认名
  ///
  /// In zh, this message translates to:
  /// **'服务器 {index}'**
  String serverDefaultNameWithIndex(int index);

  /// 服务器配置页标题
  ///
  /// In zh, this message translates to:
  /// **'服务器配置'**
  String get serverTitle;

  /// 新增连接
  ///
  /// In zh, this message translates to:
  /// **'新增连接'**
  String get serverAdd;

  /// 编辑连接
  ///
  /// In zh, this message translates to:
  /// **'编辑连接'**
  String get serverEdit;

  /// 服务器页空态
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的服务器连接'**
  String get serverEmpty;

  /// 服务器页底部说明
  ///
  /// In zh, this message translates to:
  /// **'提示：点击卡片启用对应连接（同时只能启用一个）。每个连接可配置主/备两个地址，连接时先尝试主地址，不通则自动尝试备用地址。'**
  String get serverHint;

  /// 连接状态：已连通
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get serverConnected;

  /// 连接状态：已启用但未连通
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get serverActivated;

  /// 卡片里的主地址行
  ///
  /// In zh, this message translates to:
  /// **'主: {url}'**
  String serverPrimaryPrefix(String url);

  /// 卡片里的备用地址行
  ///
  /// In zh, this message translates to:
  /// **'备: {url}'**
  String serverBackupPrefix(String url);

  /// 编辑按钮提示
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get serverEditTooltip;

  /// 删除连接确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除连接'**
  String get serverDeleteTitle;

  /// 删除连接确认正文
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」吗？'**
  String serverDeleteConfirm(String name);

  /// 连接表单：名称
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get serverFormName;

  /// 连接表单：名称示例
  ///
  /// In zh, this message translates to:
  /// **'例如: 家里内网 / 公司外网'**
  String get serverFormNameHint;

  /// 连接表单：主地址
  ///
  /// In zh, this message translates to:
  /// **'主地址（优先尝试）'**
  String get serverFormPrimary;

  /// 连接表单：主地址示例
  ///
  /// In zh, this message translates to:
  /// **'例如: http://192.168.1.100:8188'**
  String get serverFormPrimaryHint;

  /// 连接表单：备用地址
  ///
  /// In zh, this message translates to:
  /// **'备用地址（可选）'**
  String get serverFormBackup;

  /// 连接表单：备用地址说明
  ///
  /// In zh, this message translates to:
  /// **'主地址不通时使用，如外网地址'**
  String get serverFormBackupHint;

  /// 测试连接按钮
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get serverTest;

  /// 未填主地址就点测试
  ///
  /// In zh, this message translates to:
  /// **'请先填写主地址'**
  String get serverTestEmptyPrimary;

  /// 探测结果：主地址可用
  ///
  /// In zh, this message translates to:
  /// **'主地址可用'**
  String get serverTestPrimaryOk;

  /// 探测结果：备用地址可用
  ///
  /// In zh, this message translates to:
  /// **'备用地址可用'**
  String get serverTestBackupOk;

  /// 探测结果：都不可用
  ///
  /// In zh, this message translates to:
  /// **'主/备地址均无法连通'**
  String get serverTestAllFailed;

  /// 启用连接失败
  ///
  /// In zh, this message translates to:
  /// **'「{name}」连接失败：主/备地址均无法连通'**
  String serverActivateFailed(String name);

  /// 启用成功且走主地址
  ///
  /// In zh, this message translates to:
  /// **'已连接「{name}」（主地址）'**
  String serverActivatedPrimary(String name);

  /// 启用成功且走备用地址
  ///
  /// In zh, this message translates to:
  /// **'已连接「{name}」（备用地址）'**
  String serverActivatedBackup(String name);

  /// 设置页标题
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// 设置页分组：通用
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get settingsSectionGeneral;

  /// 设置页分组：连接
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get settingsSectionConnection;

  /// 设置页分组：数据
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get settingsSectionData;

  /// 设置页分组：更新
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get settingsSectionUpdate;

  /// 设置页分组：关于
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsSectionAbout;

  /// 设置项：界面语言
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get settingsLanguage;

  /// 语言选项：跟随系统
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsLanguageFollow;

  /// 语言选项：简体中文
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// 语言选项：英文
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// 语言选择对话框标题
  ///
  /// In zh, this message translates to:
  /// **'选择界面语言'**
  String get settingsLanguageTitle;

  /// 设置项：服务器连接
  ///
  /// In zh, this message translates to:
  /// **'服务器连接'**
  String get settingsServerEntry;

  /// 服务器连接：未配置
  ///
  /// In zh, this message translates to:
  /// **'尚未配置任何服务器'**
  String get settingsServerNone;

  /// 服务器连接：已配置数量
  ///
  /// In zh, this message translates to:
  /// **'已配置 {count} 个服务器'**
  String settingsServerCount(int count);

  /// 设置项：工作流存储
  ///
  /// In zh, this message translates to:
  /// **'工作流存储'**
  String get settingsStorage;

  /// 工作流存储：空态
  ///
  /// In zh, this message translates to:
  /// **'导入或另存工作流后显示'**
  String get settingsStorageNone;

  /// 工作流存储：已保存数量
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 个工作流'**
  String settingsStorageCount(int count);

  /// 设置项：工作流快照
  ///
  /// In zh, this message translates to:
  /// **'工作流快照'**
  String get settingsSnapshot;

  /// 工作流快照：空态
  ///
  /// In zh, this message translates to:
  /// **'运行工作流后自动生成'**
  String get settingsSnapshotNone;

  /// 工作流快照：数量
  ///
  /// In zh, this message translates to:
  /// **'已固化 {count} 份快照'**
  String settingsSnapshotCount(int count);

  /// 设置项：GitHub 令牌
  ///
  /// In zh, this message translates to:
  /// **'GitHub 访问令牌'**
  String get settingsToken;

  /// GitHub 令牌：已配置
  ///
  /// In zh, this message translates to:
  /// **'已配置，可检查私有仓库的更新'**
  String get settingsTokenSet;

  /// GitHub 令牌：未配置
  ///
  /// In zh, this message translates to:
  /// **'未配置。仓库为私有时必须配置才能检查更新'**
  String get settingsTokenUnset;

  /// 设置项：关于
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// 设置项：关于的副标题
  ///
  /// In zh, this message translates to:
  /// **'版本信息与检查更新'**
  String get settingsAboutSubtitle;

  /// 本地导入工作流的展示名
  ///
  /// In zh, this message translates to:
  /// **'本地导入'**
  String get workflowLocalImport;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
