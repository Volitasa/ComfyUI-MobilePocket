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

  /// 大图加载失败时的占位提示
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败，请检查服务器连接'**
  String get historyImageLoadFailed;

  /// 看图页参考图分组的标题前缀，拼成「输入 1 / 2」
  ///
  /// In zh, this message translates to:
  /// **'输入'**
  String get historyRefGroupLabel;

  /// 在出图页按住不放时的提示条
  ///
  /// In zh, this message translates to:
  /// **'输入 {index} / {total} · 松开回到出图'**
  String historyRefPeekToInput(int index, int total);

  /// 在参考图页按住不放时的提示条
  ///
  /// In zh, this message translates to:
  /// **'{index} / {total} · 松开回到参考图'**
  String historyRefPeekToOutput(int index, int total);

  /// 参考图 404 时的占位说明
  ///
  /// In zh, this message translates to:
  /// **'参考图已不在服务器上'**
  String get historyRefUnavailable;

  /// 记录所属服务器被删除后的占位说明
  ///
  /// In zh, this message translates to:
  /// **'原服务器已移除，无法查看参考图'**
  String get historyRefServerRemoved;

  /// 进行中记录的停止按钮
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get historyStopTooltip;

  /// 停止生成确认标题
  ///
  /// In zh, this message translates to:
  /// **'停止这次生成？'**
  String get historyStopTitle;

  /// 停止生成确认正文
  ///
  /// In zh, this message translates to:
  /// **'已经算出来的进度会丢失，服务器会停掉这个任务。'**
  String get historyStopBody;

  /// 停止生成确认按钮
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get historyStopConfirm;

  /// 停止成功提示
  ///
  /// In zh, this message translates to:
  /// **'已停止生成'**
  String get historyStopped;

  /// 服务器上这条任务已经跑完/已丢失
  ///
  /// In zh, this message translates to:
  /// **'任务已结束'**
  String get historyStopNotRunning;

  /// 停止失败提示
  ///
  /// In zh, this message translates to:
  /// **'停止失败，请检查服务器连接'**
  String get historyStopFailed;

  /// 停止失败时提示里的删除入口，避免记录卡在进行中
  ///
  /// In zh, this message translates to:
  /// **'仍要删除'**
  String get historyStopActionDelete;

  /// 连接没有名称时的默认名（仅在展示层兜底，不落盘）
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get serverDefaultName;

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

  /// 设置项：界面外观（浅色 / 深色）
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// 外观选择对话框标题
  ///
  /// In zh, this message translates to:
  /// **'选择外观'**
  String get settingsAppearanceTitle;

  /// 外观选项：始终浅色
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsAppearanceLight;

  /// 外观选项：始终深色
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsAppearanceDark;

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
  /// **'已配置'**
  String get settingsTokenSet;

  /// GitHub 令牌：未配置
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
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

  /// 配置页：快照已不存在
  ///
  /// In zh, this message translates to:
  /// **'工作流快照已被删除'**
  String get workflowSnapshotDeleted;

  /// 配置页：本地工作流已删除
  ///
  /// In zh, this message translates to:
  /// **'本地工作流已不存在，可能已被删除'**
  String get workflowLocalMissing;

  /// 配置页：解析缓存已清除
  ///
  /// In zh, this message translates to:
  /// **'解析结果已被清除，请重新解析'**
  String get workflowParsedCleared;

  /// 配置页：首次拉取线上工作流失败
  ///
  /// In zh, this message translates to:
  /// **'拉取线上工作流内容失败，请检查服务器连接'**
  String get workflowFetchFailed;

  /// 配置页：重新拉取线上工作流失败
  ///
  /// In zh, this message translates to:
  /// **'重新拉取工作流失败，请检查服务器连接'**
  String get workflowRefetchFailed;

  /// 配置页：重新解析完成
  ///
  /// In zh, this message translates to:
  /// **'已重新解析，请确认参数后保存'**
  String get workflowReparsed;

  /// 配置页：保存成功提示
  ///
  /// In zh, this message translates to:
  /// **'配置已保存'**
  String get configSaved;

  /// 配置页：解析中的页面标题
  ///
  /// In zh, this message translates to:
  /// **'解析中...'**
  String get configParsingTitle;

  /// 配置页标题
  ///
  /// In zh, this message translates to:
  /// **'配置面板: {name}'**
  String configPanelTitle(String name);

  /// 配置页：重新解析按钮提示
  ///
  /// In zh, this message translates to:
  /// **'重新解析参数'**
  String get configReparseTooltip;

  /// 配置页顶部说明
  ///
  /// In zh, this message translates to:
  /// **'请勾选需要暴露到手机 App 表单的参数，并为它们起一个易懂的名字。'**
  String get configPanelHint;

  /// 配置页：无可配置参数
  ///
  /// In zh, this message translates to:
  /// **'此工作流没有找到可动态修改的参数。'**
  String get configNoParams;

  /// 配置页：分组头部已选数量
  ///
  /// In zh, this message translates to:
  /// **'{count}/{total} 项已选'**
  String configSelectedCount(int count, int total);

  /// 配置页：分组头部参数总数
  ///
  /// In zh, this message translates to:
  /// **'{total} 项参数'**
  String configParamCount(int total);

  /// 配置页底部保存按钮
  ///
  /// In zh, this message translates to:
  /// **'保存表单配置'**
  String get configSaveButton;

  /// 配置页：正在向服务器取节点说明书
  ///
  /// In zh, this message translates to:
  /// **'正在获取节点信息...'**
  String get configSpecsFetching;

  /// 配置页：取说明书失败或超时后的降级提示
  ///
  /// In zh, this message translates to:
  /// **'未获取到服务器节点信息，已按参数名推断控件'**
  String get configSpecsDegraded;

  /// 配置页：该节点在服务器上不存在
  ///
  /// In zh, this message translates to:
  /// **'服务器缺少节点：{classType}'**
  String configNodeMissingOnServer(String classType);

  /// 配置页：说明书里找不到该参数
  ///
  /// In zh, this message translates to:
  /// **'服务器上没有这个参数'**
  String get configParamMissingOnServer;

  /// 配置页：别名输入框占位提示
  ///
  /// In zh, this message translates to:
  /// **'例如: 画面主体描述'**
  String get paramAliasHint;

  /// 参数类型：文本
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get paramTypeText;

  /// 参数类型：种子
  ///
  /// In zh, this message translates to:
  /// **'种子'**
  String get paramTypeSeed;

  /// 参数类型：图片
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get paramTypeImage;

  /// 参数类型：整数
  ///
  /// In zh, this message translates to:
  /// **'整数'**
  String get paramTypeInt;

  /// 参数类型：小数
  ///
  /// In zh, this message translates to:
  /// **'小数'**
  String get paramTypeFloat;

  /// 参数类型：开关
  ///
  /// In zh, this message translates to:
  /// **'开关'**
  String get paramTypeBool;

  /// 参数类型：选项
  ///
  /// In zh, this message translates to:
  /// **'选项'**
  String get paramTypeEnum;

  /// 参数类型：未知类型兜底
  ///
  /// In zh, this message translates to:
  /// **'参数'**
  String get paramTypeDefault;

  /// 参数摘要：只有类型
  ///
  /// In zh, this message translates to:
  /// **'类型: {type}'**
  String paramSummaryType(String type);

  /// 参数摘要：类型 + 当前值
  ///
  /// In zh, this message translates to:
  /// **'类型: {type} · 当前值: {value}'**
  String paramSummaryTypeValue(String type, String value);

  /// 参数摘要：属于哪个节点 + 当前值（主视图用）
  ///
  /// In zh, this message translates to:
  /// **'{node} · {value}'**
  String paramSummaryNodeValue(String node, String value);

  /// 默认别名：种子
  ///
  /// In zh, this message translates to:
  /// **'随机种子'**
  String get aliasSeed;

  /// 默认别名：参考图
  ///
  /// In zh, this message translates to:
  /// **'参考图片'**
  String get aliasImage;

  /// 默认别名：steps
  ///
  /// In zh, this message translates to:
  /// **'采样步数'**
  String get aliasSteps;

  /// 默认别名：cfg
  ///
  /// In zh, this message translates to:
  /// **'CFG 强度'**
  String get aliasCfg;

  /// 默认别名：sampler_name
  ///
  /// In zh, this message translates to:
  /// **'采样器'**
  String get aliasSampler;

  /// 默认别名：scheduler
  ///
  /// In zh, this message translates to:
  /// **'调度器'**
  String get aliasScheduler;

  /// 默认别名：denoise
  ///
  /// In zh, this message translates to:
  /// **'重绘幅度'**
  String get aliasDenoise;

  /// 默认别名：width
  ///
  /// In zh, this message translates to:
  /// **'宽度'**
  String get aliasWidth;

  /// 默认别名：height
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get aliasHeight;

  /// 默认别名：batch_size
  ///
  /// In zh, this message translates to:
  /// **'生成数量'**
  String get aliasBatchSize;

  /// 默认别名：positive
  ///
  /// In zh, this message translates to:
  /// **'正向提示词'**
  String get aliasPositive;

  /// 默认别名：negative
  ///
  /// In zh, this message translates to:
  /// **'负向提示词'**
  String get aliasNegative;

  /// 默认别名：ckpt_name
  ///
  /// In zh, this message translates to:
  /// **'Checkpoint 模型'**
  String get aliasCkpt;

  /// 默认别名：unet_name
  ///
  /// In zh, this message translates to:
  /// **'UNet 模型'**
  String get aliasUnet;

  /// 默认别名：clip_name
  ///
  /// In zh, this message translates to:
  /// **'CLIP 模型'**
  String get aliasClip;

  /// 默认别名：vae_name
  ///
  /// In zh, this message translates to:
  /// **'VAE 模型'**
  String get aliasVae;

  /// 默认别名：lora_name
  ///
  /// In zh, this message translates to:
  /// **'LoRA 模型'**
  String get aliasLora;

  /// 默认别名：control_net_name
  ///
  /// In zh, this message translates to:
  /// **'ControlNet'**
  String get aliasControlNet;

  /// 默认别名：upscale_model
  ///
  /// In zh, this message translates to:
  /// **'放大模型'**
  String get aliasUpscaleModel;

  /// 运行页：快照已删除
  ///
  /// In zh, this message translates to:
  /// **'对应的工作流快照已被删除，无法再次运行'**
  String get runSnapshotDeleted;

  /// 运行页：无表单配置
  ///
  /// In zh, this message translates to:
  /// **'未找到有效的表单配置'**
  String get runNoFormConfig;

  /// 运行页：再次运行时部分参数未能套用
  ///
  /// In zh, this message translates to:
  /// **'已套用当时的参数（{count} 项因配置变更未能套用）'**
  String runParamsRestored(int count);

  /// 运行页：再次运行时参数全部套用
  ///
  /// In zh, this message translates to:
  /// **'已套用当时的参数'**
  String get runParamsRestoredAll;

  /// 运行页：数据未就绪
  ///
  /// In zh, this message translates to:
  /// **'工作流数据未就绪，请返回重试'**
  String get runDataNotReady;

  /// 运行页：上传图片失败
  ///
  /// In zh, this message translates to:
  /// **'图片上传失败'**
  String get runImageUploadFailed;

  /// 运行页：提交失败（无响应）
  ///
  /// In zh, this message translates to:
  /// **'提交失败：无法连接服务器或请求超时'**
  String get runSubmitFailed;

  /// 运行页：任务下发成功
  ///
  /// In zh, this message translates to:
  /// **'任务下发成功！'**
  String get runTaskSubmitted;

  /// 运行页：服务端返回的错误节点
  ///
  /// In zh, this message translates to:
  /// **'，错误节点: {nodes}'**
  String runErrorNodes(String nodes);

  /// 运行页：提交失败（HTTP 错误码）
  ///
  /// In zh, this message translates to:
  /// **'提交失败 (HTTP {code}){detail}，请检查 ComfyUI 日志'**
  String runSubmitFailedHttp(String code, String detail);

  /// 运行页标题
  ///
  /// In zh, this message translates to:
  /// **'运行: {name}'**
  String runTitle(String name);

  /// 运行页：前往配置页按钮提示
  ///
  /// In zh, this message translates to:
  /// **'节点配置'**
  String get runNodeConfigTooltip;

  /// 运行页：提交中的按钮文案
  ///
  /// In zh, this message translates to:
  /// **'下发任务中...'**
  String get runSubmitting;

  /// 运行页：生成按钮文案
  ///
  /// In zh, this message translates to:
  /// **'立即生成'**
  String get runGenerateNow;

  /// 运行页：文本输入占位提示
  ///
  /// In zh, this message translates to:
  /// **'请输入描述...'**
  String get runTextHint;

  /// 运行页：随机种子按钮
  ///
  /// In zh, this message translates to:
  /// **'随机'**
  String get runRandom;

  /// 运行页：整数输入占位提示
  ///
  /// In zh, this message translates to:
  /// **'整数'**
  String get runIntHint;

  /// 运行页：小数输入占位提示
  ///
  /// In zh, this message translates to:
  /// **'数值（可小数）'**
  String get runFloatHint;

  /// 运行页：数值输入不是数字
  ///
  /// In zh, this message translates to:
  /// **'请输入数字'**
  String get runNumberInvalid;

  /// 运行页：数值超出服务器给定的范围
  ///
  /// In zh, this message translates to:
  /// **'范围 {min} – {max}'**
  String runNumberRange(String min, String max);

  /// 运行页尺寸卡：比例预设标题
  ///
  /// In zh, this message translates to:
  /// **'画面比例'**
  String get runSizeRatio;

  /// 运行页尺寸卡：长边档位标题
  ///
  /// In zh, this message translates to:
  /// **'长边'**
  String get runSizeLongEdge;

  /// 运行页尺寸卡：自定义宽高入口
  ///
  /// In zh, this message translates to:
  /// **'自定义宽高'**
  String get runSizeCustom;

  /// 运行页：放弃本地改图，恢复工作流自带的服务器图片
  ///
  /// In zh, this message translates to:
  /// **'用原图'**
  String get runUseServerImage;

  /// 运行页：开关打开
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get runBoolOn;

  /// 运行页：开关关闭
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get runBoolOff;

  /// 运行页：沿用服务器上的原图
  ///
  /// In zh, this message translates to:
  /// **'已用图: {name}'**
  String runUsingServerImage(String name);

  /// 运行页：更换图片按钮
  ///
  /// In zh, this message translates to:
  /// **'更换图片'**
  String get runChangeImage;

  /// 运行页：选择图片按钮
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get runPickImage;

  /// 运行页：图片参数还没选图时的占位文案
  ///
  /// In zh, this message translates to:
  /// **'未选择图片'**
  String get runImageEmpty;

  /// 运行页：图片来源标签，本地选的图会在生成时才上传
  ///
  /// In zh, this message translates to:
  /// **'本地 · 待上传'**
  String get runImageSourceLocal;

  /// 运行页：图片来源标签，服务器 input 目录已有
  ///
  /// In zh, this message translates to:
  /// **'服务器 · 已有'**
  String get runImageSourceServer;

  /// 运行页：图片来源标签，图来自服务器 output 目录
  ///
  /// In zh, this message translates to:
  /// **'服务器 · 输出目录'**
  String get runImageSourceOutput;

  /// 运行页：图片来源标签，图来自服务器 input 目录
  ///
  /// In zh, this message translates to:
  /// **'服务器 · 输入目录'**
  String get runImageSourceInput;

  /// 运行页：图片参数的第二颗按钮，进服务器目录选图
  ///
  /// In zh, this message translates to:
  /// **'从服务器选'**
  String get runPickServerImage;

  /// 运行页：没连服务器时点「从服务器选」的提示
  ///
  /// In zh, this message translates to:
  /// **'先连接服务器'**
  String get runNeedServer;

  /// 选图页：标题
  ///
  /// In zh, this message translates to:
  /// **'选择服务器图片'**
  String get serverImageTitle;

  /// 选图页：输出目录 Tab
  ///
  /// In zh, this message translates to:
  /// **'输出目录'**
  String get serverImageTabOutput;

  /// 选图页：输入目录 Tab
  ///
  /// In zh, this message translates to:
  /// **'输入目录'**
  String get serverImageTabInput;

  /// 选图页：目录为空
  ///
  /// In zh, this message translates to:
  /// **'这个目录里还没有图片'**
  String get serverImageEmpty;

  /// 选图页：internal 与 history 都失败
  ///
  /// In zh, this message translates to:
  /// **'读不到服务器的图片列表'**
  String get serverImageFailed;

  /// 选图页：重新读取
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get serverImageRetry;

  /// 选图页：internal 接口不可用，降级用 history
  ///
  /// In zh, this message translates to:
  /// **'这台服务器只能列出生成过的图片'**
  String get serverImageDegraded;

  /// 全屏查看器：大图没加载出来
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败'**
  String get imageViewerLoadFailed;

  /// 运行页：节点卡片展开/折叠菜单
  ///
  /// In zh, this message translates to:
  /// **'展开与折叠'**
  String get runFoldMenu;

  /// 运行页：展开全部节点卡片
  ///
  /// In zh, this message translates to:
  /// **'展开全部'**
  String get runExpandAll;

  /// 运行页：折叠全部节点卡片
  ///
  /// In zh, this message translates to:
  /// **'折叠全部'**
  String get runCollapseAll;

  /// 解析页：初始状态
  ///
  /// In zh, this message translates to:
  /// **'正在连接服务器…'**
  String get parseStatusConnecting;

  /// 解析页：加载前端超时
  ///
  /// In zh, this message translates to:
  /// **'加载 ComfyUI 前端超时，请检查服务器连接'**
  String get parseLoadTimeout;

  /// 解析页：加载前端中
  ///
  /// In zh, this message translates to:
  /// **'正在加载 ComfyUI 前端…'**
  String get parseStatusLoadingFrontend;

  /// 解析页：等待前端就绪
  ///
  /// In zh, this message translates to:
  /// **'正在等待前端就绪…'**
  String get parseStatusWaitingReady;

  /// 解析页：转换中
  ///
  /// In zh, this message translates to:
  /// **'正在转换工作流…'**
  String get parseStatusConverting;

  /// 解析页：转换超时
  ///
  /// In zh, this message translates to:
  /// **'转换超时，工作流可能包含不支持的节点'**
  String get parseConvertTimeout;

  /// 解析页：转换异常
  ///
  /// In zh, this message translates to:
  /// **'调用前端转换失败：{error}'**
  String parseConvertFailed(String error);

  /// 解析页标题
  ///
  /// In zh, this message translates to:
  /// **'解析: {name}'**
  String parseTitle(String name);

  /// 首页分组：API 工作流
  ///
  /// In zh, this message translates to:
  /// **'API 工作流 · 可直接运行'**
  String get homeGroupApi;

  /// 首页分组：UI 工作流
  ///
  /// In zh, this message translates to:
  /// **'UI 工作流 · 需解析'**
  String get homeGroupUi;

  /// 首页：工作流来源说明
  ///
  /// In zh, this message translates to:
  /// **'提示：工作流来自 ComfyUI 的 userdata/workflows 目录。UI 格式是 ComfyUI 界面保存的原始结构，需转换为 API 结构后才能运行。可在应用内直接解析转换，无需安装插件；也可在 ComfyUI 安装 ComfyUI-AutoSaveAPI 插件自动生成 API JSON（https://github.com/Volitasa/ComfyUI-AutoSaveAPI.git）。'**
  String get homeWorkflowSourceNote;

  /// UI 工作流状态：未解析
  ///
  /// In zh, this message translates to:
  /// **'尚未解析 · 点击解析'**
  String get uiStatusNotParsed;

  /// UI 工作流状态：服务器有更新
  ///
  /// In zh, this message translates to:
  /// **'服务器有更新，可重新解析'**
  String get uiStatusStale;

  /// UI 工作流状态：已解析
  ///
  /// In zh, this message translates to:
  /// **'已解析'**
  String get uiStatusParsed;

  /// UI 工作流状态：已解析（带参数数）
  ///
  /// In zh, this message translates to:
  /// **'已解析 · {count} 项参数'**
  String uiStatusParsedWithCount(int count);

  /// 通用：检查中
  ///
  /// In zh, this message translates to:
  /// **'检查中…'**
  String get statusChecking;

  /// 通用：更多操作菜单
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get menuMore;

  /// UI 工作流菜单：解析
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get uiMenuParse;

  /// UI 工作流菜单：重新解析
  ///
  /// In zh, this message translates to:
  /// **'重新解析'**
  String get uiMenuReparse;

  /// UI 工作流菜单：清除解析缓存
  ///
  /// In zh, this message translates to:
  /// **'清除解析缓存'**
  String get uiMenuClearParse;

  /// 首页：拉取工作流失败
  ///
  /// In zh, this message translates to:
  /// **'拉取工作流失败，请检查服务器连接'**
  String get homeFetchFailed;

  /// 首页：工作流文件不是合法 JSON
  ///
  /// In zh, this message translates to:
  /// **'工作流文件不是有效的 JSON'**
  String get homeInvalidJson;

  /// 首页：解析失败
  ///
  /// In zh, this message translates to:
  /// **'解析失败'**
  String get homeParseFailed;

  /// 清除解析缓存对话框正文
  ///
  /// In zh, this message translates to:
  /// **'清除后会回到未解析状态，可随时从服务器重新解析。\n\n已保存的节点配置不受影响。'**
  String get clearParseBody;

  /// 首页：已清除解析结果
  ///
  /// In zh, this message translates to:
  /// **'已清除解析结果'**
  String get clearParseDone;

  /// 首页空态：未连接服务器
  ///
  /// In zh, this message translates to:
  /// **'尚未连接到服务器'**
  String get homeDisconnectedTitle;

  /// 首页空态：未连接服务器说明
  ///
  /// In zh, this message translates to:
  /// **'请先配置并启用一个服务器连接'**
  String get homeDisconnectedBody;

  /// 首页空态：前往配置按钮
  ///
  /// In zh, this message translates to:
  /// **'前往配置'**
  String get homeGoToConfig;

  /// 首页空态：无工作流
  ///
  /// In zh, this message translates to:
  /// **'未找到工作流'**
  String get homeEmptyTitle;

  /// 首页空态：服务器上无工作流
  ///
  /// In zh, this message translates to:
  /// **'服务器上没有找到工作流 JSON 文件'**
  String get homeEmptyBody;

  /// 工作流状态：未配置
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get wfStatusUnconfigured;

  /// 工作流状态：内容有更新
  ///
  /// In zh, this message translates to:
  /// **'内容已更新，需重新确认配置'**
  String get wfStatusStale;

  /// 工作流状态：已配置参数数
  ///
  /// In zh, this message translates to:
  /// **'{count} 项参数已配置'**
  String wfStatusConfigured(int count);

  /// 工作流菜单：存入本地库
  ///
  /// In zh, this message translates to:
  /// **'存入本地库'**
  String get wfMenuSaveLocal;

  /// 工作流菜单：重新配置节点
  ///
  /// In zh, this message translates to:
  /// **'重新配置节点'**
  String get wfMenuReconfig;

  /// 工作流菜单：刷新内容
  ///
  /// In zh, this message translates to:
  /// **'刷新内容'**
  String get wfMenuRefresh;

  /// 首页：重新检查完成
  ///
  /// In zh, this message translates to:
  /// **'已重新检查'**
  String get homeRechecked;

  /// 首页：拉取工作流内容失败
  ///
  /// In zh, this message translates to:
  /// **'拉取工作流内容失败，请检查服务器连接'**
  String get homeFetchContentFailed;

  /// 首页：已存入本地库
  ///
  /// In zh, this message translates to:
  /// **'已存入本地库'**
  String get homeSavedToLocal;

  /// 通用：名称输入框标签
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get nameLabel;

  /// 通用：清除
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// 本地库：空态标题
  ///
  /// In zh, this message translates to:
  /// **'本地库为空'**
  String get localEmpty;

  /// 本地库：条目数与体积
  ///
  /// In zh, this message translates to:
  /// **'本地库 {count} 项 · {size}'**
  String localSummary(int count, String size);

  /// 本地库：导入按钮
  ///
  /// In zh, this message translates to:
  /// **'导入工作流 JSON'**
  String get localImportButton;

  /// 本地库：导入格式说明
  ///
  /// In zh, this message translates to:
  /// **'提示：这里导入的是 ComfyUI 的 API 格式 JSON（_api.json），即以节点 ID 为键、含 class_type 与 inputs 的结构；普通 UI 界面保存的 workflow JSON 不适用。'**
  String get localImportNote;

  /// 本地库：空态
  ///
  /// In zh, this message translates to:
  /// **'还没有本地工作流'**
  String get localNoWorkflows;

  /// 本地库：空态说明
  ///
  /// In zh, this message translates to:
  /// **'导入或另存的工作流会保存在这里'**
  String get localNoWorkflowsHint;

  /// 本地库：底部说明
  ///
  /// In zh, this message translates to:
  /// **'来自你自己的文件，与服务器无关，可重命名或删除。删除后无法恢复。'**
  String get localFooterNote;

  /// 通用：重命名
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get menuRename;

  /// 本地库：删除确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除本地工作流'**
  String get localDeleteTitle;

  /// 本地库：删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」吗？\n\n它的节点配置会一并清除，删除后无法恢复。已生成的记录不受影响。'**
  String localDeleteBody(String name);

  /// 本地库：删除完成
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get localDeleted;

  /// 本地库：JSON 解析失败
  ///
  /// In zh, this message translates to:
  /// **'JSON 文件解析失败'**
  String get localJsonParseFailed;

  /// 首页：刷新按钮提示
  ///
  /// In zh, this message translates to:
  /// **'刷新工作流列表'**
  String get homeRefreshTooltip;

  /// 首页页签：服务器
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get homeTabServer;

  /// 首页页签：本地
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get homeTabLocal;

  /// 连接状态：未连接
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get notConnected;

  /// 画廊：刷新按钮提示
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get galleryRefreshTooltip;

  /// 画廊空态标题
  ///
  /// In zh, this message translates to:
  /// **'还没有生成图片'**
  String get galleryEmptyTitle;

  /// 画廊空态说明
  ///
  /// In zh, this message translates to:
  /// **'生成成功后图片会自动保存到这里'**
  String get galleryEmptyHint;

  /// 画廊：图片已不存在
  ///
  /// In zh, this message translates to:
  /// **'图片已不存在，请刷新画廊'**
  String get galleryImageMissing;

  /// 画廊：保存成功
  ///
  /// In zh, this message translates to:
  /// **'✅ 已保存到手机相册'**
  String get gallerySaved;

  /// 画廊：保存失败
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get gallerySaveFailed;

  /// 画廊：删除确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除图片'**
  String get galleryDeleteTitle;

  /// 画廊：删除确认正文
  ///
  /// In zh, this message translates to:
  /// **'确定从画廊删除这张图片吗？'**
  String get galleryDeleteBody;

  /// 画廊：分享按钮提示
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get galleryShareTooltip;

  /// 画廊里再次运行前的一次性说明
  ///
  /// In zh, this message translates to:
  /// **'会用当时的工作流重新生成，不保证与这张完全一致'**
  String get galleryRerunNotice;

  /// 画廊：保存中
  ///
  /// In zh, this message translates to:
  /// **'保存中...'**
  String get gallerySaving;

  /// 画廊：保存到相册按钮
  ///
  /// In zh, this message translates to:
  /// **'保存到相册'**
  String get gallerySaveToAlbum;

  /// 画廊：分享功能提示
  ///
  /// In zh, this message translates to:
  /// **'分享功能即将上线'**
  String get galleryShareSoon;

  /// No description provided for @storageTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作流存储'**
  String get storageTitle;

  /// No description provided for @storageEmpty.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有保存任何工作流'**
  String get storageEmpty;

  /// No description provided for @storageSummary.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 项 · 合计 {size}'**
  String storageSummary(int total, String size);

  /// No description provided for @storageGroupLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地资产 · {count} 项'**
  String storageGroupLocal(int count);

  /// No description provided for @storageGroupParsed.
  ///
  /// In zh, this message translates to:
  /// **'解析缓存 · {count} 项'**
  String storageGroupParsed(int count);

  /// No description provided for @storageParsedNote.
  ///
  /// In zh, this message translates to:
  /// **'解析缓存由服务器上的 UI 工作流转换而来，清除后回到未解析状态，可随时重新解析。'**
  String get storageParsedNote;

  /// No description provided for @storageOrigin.
  ///
  /// In zh, this message translates to:
  /// **'来源 {name}'**
  String storageOrigin(String name);

  /// No description provided for @storageParsedAt.
  ///
  /// In zh, this message translates to:
  /// **'UI 工作流解析 · {time} · {size}'**
  String storageParsedAt(String time, String size);

  /// No description provided for @unknownConnection.
  ///
  /// In zh, this message translates to:
  /// **'未知连接'**
  String get unknownConnection;

  /// No description provided for @storageClearCacheBody.
  ///
  /// In zh, this message translates to:
  /// **'确定清除「{name}」的解析结果吗？\n\n清除后回到未解析状态，在服务器列表里可以重新解析。已保存的节点配置不受影响。'**
  String storageClearCacheBody(String name);

  /// No description provided for @snapshotDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除快照'**
  String get snapshotDeleteTitle;

  /// No description provided for @snapshotDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」吗？\n\n删除后，引用它的 {count} 条生成记录将无法再次运行。'**
  String snapshotDeleteBody(String name, int count);

  /// No description provided for @snapshotDeleted.
  ///
  /// In zh, this message translates to:
  /// **'快照已删除'**
  String get snapshotDeleted;

  /// No description provided for @snapshotNotRecorded.
  ///
  /// In zh, this message translates to:
  /// **'未记录'**
  String get snapshotNotRecorded;

  /// No description provided for @snapshotTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作流快照'**
  String get snapshotTitle;

  /// No description provided for @snapshotEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无工作流快照'**
  String get snapshotEmpty;

  /// No description provided for @snapshotFrozenAt.
  ///
  /// In zh, this message translates to:
  /// **'固化时间 {time} · {size}'**
  String snapshotFrozenAt(String time, String size);

  /// No description provided for @snapshotSourceServer.
  ///
  /// In zh, this message translates to:
  /// **'来源服务器 {name}'**
  String snapshotSourceServer(String name);

  /// No description provided for @snapshotRefCount.
  ///
  /// In zh, this message translates to:
  /// **'被 {count} 条生成记录引用'**
  String snapshotRefCount(int count);

  /// No description provided for @snapshotNoRef.
  ///
  /// In zh, this message translates to:
  /// **'未被任何生成记录引用'**
  String get snapshotNoRef;

  /// No description provided for @tokenTitle.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 访问令牌'**
  String get tokenTitle;

  /// No description provided for @tokenSaved.
  ///
  /// In zh, this message translates to:
  /// **'令牌已保存'**
  String get tokenSaved;

  /// No description provided for @tokenCleared.
  ///
  /// In zh, this message translates to:
  /// **'令牌已清除'**
  String get tokenCleared;

  /// No description provided for @tokenConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get tokenConfigured;

  /// No description provided for @tokenClearButton.
  ///
  /// In zh, this message translates to:
  /// **'清除令牌'**
  String get tokenClearButton;

  /// No description provided for @tokenLocalOnlyNote.
  ///
  /// In zh, this message translates to:
  /// **'令牌仅保存在本机，不会上传。'**
  String get tokenLocalOnlyNote;

  /// No description provided for @updateCheckButton.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get updateCheckButton;

  /// No description provided for @updateSourceNote.
  ///
  /// In zh, this message translates to:
  /// **'更新来源：GitHub Releases'**
  String get updateSourceNote;

  /// No description provided for @aboutVersionBuild.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}（构建 {build}）'**
  String aboutVersionBuild(String version, String build);

  /// No description provided for @updateChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本 {version}'**
  String updateUpToDate(String version);

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败'**
  String get updateCheckFailed;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @configureToken.
  ///
  /// In zh, this message translates to:
  /// **'配置令牌'**
  String get configureToken;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {version}'**
  String updateAvailableTitle(String version);

  /// No description provided for @updateAvailableOtherPlatform.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {version}，当前平台不支持应用内安装，请到 Release 页面手动下载'**
  String updateAvailableOtherPlatform(String version);

  /// No description provided for @releaseNotesTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新说明'**
  String get releaseNotesTitle;

  /// No description provided for @changelogTitle.
  ///
  /// In zh, this message translates to:
  /// **'完整变更记录'**
  String get changelogTitle;

  /// No description provided for @updateDownloadingPercent.
  ///
  /// In zh, this message translates to:
  /// **'下载中 {percent}%'**
  String updateDownloadingPercent(String percent);

  /// No description provided for @updateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载…'**
  String get updateDownloading;

  /// No description provided for @updateDownloadInstall.
  ///
  /// In zh, this message translates to:
  /// **'下载并安装'**
  String get updateDownloadInstall;

  /// No description provided for @installLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法唤起安装界面：{message}'**
  String installLaunchFailed(String message);

  /// No description provided for @saveAlbumPermission.
  ///
  /// In zh, this message translates to:
  /// **'需要相册权限'**
  String get saveAlbumPermission;

  /// No description provided for @saveAlbumTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存到相册'**
  String get saveAlbumTitle;

  /// No description provided for @saveAlbumBody.
  ///
  /// In zh, this message translates to:
  /// **'这张 PNG 内嵌了工作流信息。选择保存方式：'**
  String get saveAlbumBody;

  /// No description provided for @saveAlbumPlain.
  ///
  /// In zh, this message translates to:
  /// **'普通图片（剔除信息）'**
  String get saveAlbumPlain;

  /// No description provided for @saveAlbumWithWorkflow.
  ///
  /// In zh, this message translates to:
  /// **'带工作流原图'**
  String get saveAlbumWithWorkflow;

  /// No description provided for @parseBadPayload.
  ///
  /// In zh, this message translates to:
  /// **'前端返回了无法识别的数据'**
  String get parseBadPayload;

  /// No description provided for @parseNoWorkflow.
  ///
  /// In zh, this message translates to:
  /// **'前端未返回工作流结构'**
  String get parseNoWorkflow;

  /// No description provided for @parseUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'解析结果无法读取'**
  String get parseUnreadable;

  /// No description provided for @convertEmpty.
  ///
  /// In zh, this message translates to:
  /// **'转换结果为空（工作流可能没有可运行的节点）'**
  String get convertEmpty;

  /// No description provided for @convertUiNotApi.
  ///
  /// In zh, this message translates to:
  /// **'前端返回了 UI 结构而非 API 结构'**
  String get convertUiNotApi;

  /// No description provided for @convertBadNode.
  ///
  /// In zh, this message translates to:
  /// **'转换结果第 {index} 项不是有效的 API 节点'**
  String convertBadNode(String index);

  /// No description provided for @updateRepoForbiddenWithToken.
  ///
  /// In zh, this message translates to:
  /// **'仓库不可访问：请确认令牌对该仓库有 Contents 读取权限，且未过期'**
  String get updateRepoForbiddenWithToken;

  /// No description provided for @updateRepoForbidden.
  ///
  /// In zh, this message translates to:
  /// **'仓库不可访问。若该仓库是私有的，请在「设置 → GitHub 访问令牌」中填入只读令牌后重试'**
  String get updateRepoForbidden;

  /// No description provided for @updateTokenInvalid.
  ///
  /// In zh, this message translates to:
  /// **'令牌无效或已过期，请到「设置 → GitHub 访问令牌」更新或清除'**
  String get updateTokenInvalid;

  /// No description provided for @updateRateLimitedWithToken.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 拒绝了请求（令牌权限不足或触发限流），请稍后再试'**
  String get updateRateLimitedWithToken;

  /// No description provided for @updateRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 接口访问受限（匿名请求每小时 60 次），配置访问令牌可放宽限额'**
  String get updateRateLimited;

  /// No description provided for @updateHttpFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询更新失败（HTTP {code}）'**
  String updateHttpFailed(String code);

  /// No description provided for @updateNoRelease.
  ///
  /// In zh, this message translates to:
  /// **'该仓库还没有发布带安装包的版本（仅有 git tag 不会被识别）'**
  String get updateNoRelease;

  /// No description provided for @updateBadTag.
  ///
  /// In zh, this message translates to:
  /// **'发布版本号无法识别（{tag}）'**
  String updateBadTag(String tag);

  /// No description provided for @updateTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接 GitHub 超时，请检查网络后重试'**
  String get updateTimeout;

  /// No description provided for @updateUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'无法连接 GitHub，请检查网络后重试'**
  String get updateUnreachable;

  /// No description provided for @updateQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询更新失败，请检查网络后重试'**
  String get updateQueryFailed;

  /// No description provided for @updateNoAsset.
  ///
  /// In zh, this message translates to:
  /// **'该版本没有附带安装包'**
  String get updateNoAsset;

  /// No description provided for @updateNoApk.
  ///
  /// In zh, this message translates to:
  /// **'该版本没有可安装的 APK'**
  String get updateNoApk;

  /// No description provided for @updateAssetMissing.
  ///
  /// In zh, this message translates to:
  /// **'安装包地址缺失，请稍后重试'**
  String get updateAssetMissing;

  /// No description provided for @updateDownloadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'下载超时，请检查网络后重试'**
  String get updateDownloadTimeout;

  /// No description provided for @updateDownloadInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，网络连接已中断'**
  String get updateDownloadInterrupted;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请检查网络后重试'**
  String get updateDownloadFailed;

  /// No description provided for @updateDownload404Token.
  ///
  /// In zh, this message translates to:
  /// **'安装包下载失败（404），请确认令牌仍有该仓库的读取权限'**
  String get updateDownload404Token;

  /// No description provided for @updateDownload404.
  ///
  /// In zh, this message translates to:
  /// **'安装包下载失败（404）'**
  String get updateDownload404;

  /// No description provided for @updateDownloadHttp.
  ///
  /// In zh, this message translates to:
  /// **'下载失败（HTTP {code}）'**
  String updateDownloadHttp(String code);

  /// No description provided for @updateDownloadAborted.
  ///
  /// In zh, this message translates to:
  /// **'下载中断，请重试'**
  String get updateDownloadAborted;

  /// No description provided for @updateWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装包写入失败'**
  String get updateWriteFailed;

  /// No description provided for @updateCheckFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请稍后重试'**
  String get updateCheckFailedRetry;

  /// No description provided for @updateNoPending.
  ///
  /// In zh, this message translates to:
  /// **'没有待下载的版本'**
  String get updateNoPending;

  /// No description provided for @updateDownloadFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请稍后重试'**
  String get updateDownloadFailedRetry;

  /// 本地工作流来源：导入
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get localSourceImport;

  /// 本地工作流来源：从服务器另存
  ///
  /// In zh, this message translates to:
  /// **'另存'**
  String get localSourceSaved;

  /// 通用：大小未知
  ///
  /// In zh, this message translates to:
  /// **'未知大小'**
  String get unknownSize;

  /// 配置页：展开全部节点分组
  ///
  /// In zh, this message translates to:
  /// **'一键展开'**
  String get configExpandAll;

  /// 配置页：折叠全部节点分组
  ///
  /// In zh, this message translates to:
  /// **'一键折叠'**
  String get configCollapseAll;

  /// 配置页：搜索框提示
  ///
  /// In zh, this message translates to:
  /// **'搜索参数或节点'**
  String get configSearchHint;

  /// 配置页：搜索无结果
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的参数'**
  String get configSearchEmpty;

  /// 配置页：勾选该节点下全部参数
  ///
  /// In zh, this message translates to:
  /// **'全选本节点'**
  String get configNodeSelectAll;

  /// 配置页：取消该节点下全部参数
  ///
  /// In zh, this message translates to:
  /// **'取消本节点'**
  String get configNodeClearAll;

  /// 配置页：主视图统计，表单里几项、工作流一共几项
  ///
  /// In zh, this message translates to:
  /// **'已放进表单 {count} 项（共 {total} 项）'**
  String configFormCount(int count, int total);

  /// 配置页：主视图副标题
  ///
  /// In zh, this message translates to:
  /// **'长按可拖动排序，改名或移出只影响手机上的表单'**
  String get configFormHint;

  /// 配置页：主视图空态
  ///
  /// In zh, this message translates to:
  /// **'还没有参数放进表单'**
  String get configFormEmpty;

  /// 配置页：进入全量参数列表的入口
  ///
  /// In zh, this message translates to:
  /// **'添加参数'**
  String get configAddParams;

  /// 配置页：添加入口，附带还剩多少项可加
  ///
  /// In zh, this message translates to:
  /// **'添加参数（还有 {count} 项）'**
  String configAddParamsCount(int count);

  /// 配置页：把该参数移出手机表单
  ///
  /// In zh, this message translates to:
  /// **'移出表单'**
  String get configRemoveParam;

  /// 添加参数页：标题
  ///
  /// In zh, this message translates to:
  /// **'添加参数'**
  String get configPickerTitle;

  /// 添加参数页：完成按钮
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get configPickerDone;

  /// 添加参数页：用途分段-提示词
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get categoryPrompt;

  /// 添加参数页：用途分段-采样
  ///
  /// In zh, this message translates to:
  /// **'采样'**
  String get categorySampling;

  /// 添加参数页：用途分段-画面尺寸
  ///
  /// In zh, this message translates to:
  /// **'画面尺寸'**
  String get categorySize;

  /// 添加参数页：用途分段-模型与权重
  ///
  /// In zh, this message translates to:
  /// **'模型与权重'**
  String get categoryModel;

  /// 添加参数页：用途分段-精细控制
  ///
  /// In zh, this message translates to:
  /// **'精细控制'**
  String get categoryControl;

  /// 添加参数页：用途分段-其余
  ///
  /// In zh, this message translates to:
  /// **'其余节点'**
  String get categoryOther;

  /// 节点位置说明：这个节点的输出接到了哪个节点的哪个输入（两个名字都是官方名，不翻译）
  ///
  /// In zh, this message translates to:
  /// **'连到 {node} · {slot}'**
  String roleLinksTo(String node, String slot);

  /// 节点位置说明：下游不止一处，只报第一处 + 总处数
  ///
  /// In zh, this message translates to:
  /// **'连到 {node} · {slot} 等 {count} 处'**
  String roleLinksToMany(String node, String slot, int count);

  /// 生成记录页：搜索框提示
  ///
  /// In zh, this message translates to:
  /// **'搜索工作流或提示词'**
  String get historySearchHint;

  /// 生成记录页：搜索无结果
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的记录'**
  String get historySearchEmpty;

  /// 生成记录页：状态筛选-全部
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get historyFilterAll;

  /// 生成记录页：状态筛选-进行中（排队+生成）
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get historyFilterPending;

  /// 运行页：下拉未选中时的占位提示
  ///
  /// In zh, this message translates to:
  /// **'请选择'**
  String get runSelectPlaceholder;

  /// 运行页：工作流里的模型在服务器上找不到
  ///
  /// In zh, this message translates to:
  /// **'服务器没有此模型'**
  String get runModelMissing;

  /// 运行页：提交时服务器不认识该节点（取数成功但返回空）
  ///
  /// In zh, this message translates to:
  /// **'服务器缺少节点：{classType}'**
  String runNodeMissingOnServer(String classType);

  /// 运行页：提交时下拉当前值不在服务器选项里
  ///
  /// In zh, this message translates to:
  /// **'「{name}」的当前值服务器上没有，请重新选择'**
  String runOptionMissingOnServer(String name);

  /// 运行页：手动重新拉取服务器模型列表
  ///
  /// In zh, this message translates to:
  /// **'刷新模型列表'**
  String get runRefreshModels;

  /// 运行页：刷新成功提示
  ///
  /// In zh, this message translates to:
  /// **'已刷新'**
  String get runOptionsRefreshed;

  /// 运行页：刷新失败提示
  ///
  /// In zh, this message translates to:
  /// **'刷新失败，请检查连接'**
  String get runOptionsRefreshFailed;

  /// 工作流列表：该工作流上次运行的时间
  ///
  /// In zh, this message translates to:
  /// **'上次运行 {time}'**
  String wfLastRun(String time);

  /// 工作流列表：一次都没跑过
  ///
  /// In zh, this message translates to:
  /// **'尚未运行'**
  String get wfNeverRun;

  /// 顶部连接徽标：已连过但此刻断开、正在自动重连
  ///
  /// In zh, this message translates to:
  /// **'重连中'**
  String get badgeReconnecting;

  /// 设置项：点开选择哪些操作会震动
  ///
  /// In zh, this message translates to:
  /// **'震动反馈'**
  String get settingsHaptics;

  /// 设置项副标题：一类震动都没开
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get settingsHapticsOff;

  /// 设置项副标题：当前开启的震动词条数
  ///
  /// In zh, this message translates to:
  /// **'已开启 {count} 项'**
  String settingsHapticsCount(int count);

  /// 震动分类：切换底部标签
  ///
  /// In zh, this message translates to:
  /// **'切换标签页'**
  String get hapticsNav;

  /// 震动分类：勾选 / 取消勾选 / 节点内全选参数
  ///
  /// In zh, this message translates to:
  /// **'勾选参数'**
  String get hapticsCheck;

  /// 震动分类：长按拖动参数排序
  ///
  /// In zh, this message translates to:
  /// **'拖动排序'**
  String get hapticsReorder;

  /// 震动分类：展开 / 折叠参数卡
  ///
  /// In zh, this message translates to:
  /// **'折叠卡片'**
  String get hapticsFold;

  /// 震动分类：任务下发成功
  ///
  /// In zh, this message translates to:
  /// **'提交成功'**
  String get hapticsSubmit;

  /// 震动选择弹窗：一次打开所有分类
  ///
  /// In zh, this message translates to:
  /// **'全部开启'**
  String get hapticsAllOn;

  /// 震动选择弹窗：一次关掉所有分类
  ///
  /// In zh, this message translates to:
  /// **'全部关闭'**
  String get hapticsAllOff;

  /// 设置项：AI 供应商配置入口
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get settingsAiService;

  /// 设置项副标题：没有可用供应商
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get settingsAiServiceNone;

  /// AI 供应商配置页标题
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get aiServiceTitle;

  /// 供应商列表空态
  ///
  /// In zh, this message translates to:
  /// **'还没有配置 AI 服务'**
  String get aiServiceEmpty;

  /// 选择器：已选数量
  ///
  /// In zh, this message translates to:
  /// **'已选 {count}'**
  String aiSelectedCount(int count);

  /// 选择器：确定按钮
  ///
  /// In zh, this message translates to:
  /// **'确定 · {count} 项'**
  String aiConfirmCount(int count);

  /// 结果卡：字数变化
  ///
  /// In zh, this message translates to:
  /// **'{after} 字 · 原 {before} 字'**
  String aiCharsChange(int after, int before);

  /// 写入成功横幅
  ///
  /// In zh, this message translates to:
  /// **'已写入「{target}」'**
  String aiWrittenBanner(String target);

  /// 读取原图进度
  ///
  /// In zh, this message translates to:
  /// **'正在读取原图 {done}/{total}'**
  String aiReadingImages(int done, int total);

  /// 发送前提示：图片数量与体积
  ///
  /// In zh, this message translates to:
  /// **'已发送 {count} 张原图 · {size}'**
  String aiImagesSent(int count, String size);

  /// 写入校验失败
  ///
  /// In zh, this message translates to:
  /// **'无法写入：{reason}'**
  String aiCannotWrite(String reason);

  /// 测试连接失败
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{msg}'**
  String aiServiceTestFail(String msg);

  /// No description provided for @aiServiceName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get aiServiceName;

  /// No description provided for @aiServiceUse.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get aiServiceUse;

  /// AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'添加 AI 服务'**
  String get aiServiceAdd;

  /// AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'编辑 AI 服务'**
  String get aiServiceEdit;

  /// AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'删除 AI 服务'**
  String get aiServiceDeleteTitle;

  /// AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'DeepSeek 预设'**
  String get aiServicePresetDeepSeek;

  /// AI 服务配置
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get aiServicePresetCustom;

  /// 删除确认
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？'**
  String aiServiceDeleteConfirm(String name);

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'添加参考节点'**
  String get aiAddInput;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'选择要填充的参数'**
  String get aiAddOutput;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get aiCanceled;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get aiCopied;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get aiCopy;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'（空）'**
  String get aiEmptyValue;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'AI'**
  String get aiEntry;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'请求被拒绝'**
  String get aiErrorBadRequest;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'连不上服务'**
  String get aiErrorNetwork;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'地址或模型名不对'**
  String get aiErrorNotFound;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'请求太频繁，稍等再试'**
  String get aiErrorRateLimited;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'服务暂时不可用'**
  String get aiErrorServer;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'等太久了，已停止'**
  String get aiErrorTimeout;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'密钥无效或无权限'**
  String get aiErrorUnauthorized;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get aiGenerate;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'正在生成'**
  String get aiGenerating;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'原图已不在服务器'**
  String get aiImageMissing;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'输入 · 可多选'**
  String get aiInputLabel;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'描述你要做什么…'**
  String get aiInstructionHint;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'看图写词需要至少一张参考图'**
  String get aiNeedImage;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'写一句要求，或选一个模板'**
  String get aiNeedInstruction;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'先选要填充的参数'**
  String get aiNeedOutput;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'先配置 AI 服务'**
  String get aiNoProvider;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'未按格式返回'**
  String get aiNotStructured;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get aiOpenSettings;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'输出 · 单选'**
  String get aiOutputLabel;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'选择节点'**
  String get aiPickNodes;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get aiRemove;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'建议'**
  String get aiResultTitle;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get aiRetry;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'搜索节点或参数'**
  String get aiSearchNodes;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get aiServiceActiveTag;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get aiServiceApiKey;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'接口地址'**
  String get aiServiceBaseUrl;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'删除此服务'**
  String get aiServiceDelete;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'密钥保存在本机应用私有存储，只会随请求发往上面填写的地址。'**
  String get aiServiceKeyNote;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get aiServiceModel;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get aiServiceTest;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get aiServiceTestOk;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiSheetTitle;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get aiStop;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get aiTabAll;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get aiTabImage;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get aiTabText;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'看图写词'**
  String get aiTemplateImage;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'更多…'**
  String get aiTemplateMore;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'改写'**
  String get aiTemplateRewrite;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get aiUndo;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'写入'**
  String get aiWrite;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'目标已变化'**
  String get aiWriteNodeMissing;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'不在本次目标里'**
  String get aiWriteNotAllowed;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'目标不是文本框'**
  String get aiWriteNotText;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'文本过长'**
  String get aiWriteTooLong;

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'已写入'**
  String get aiWritten;

  /// 设置项副标题：当前供应商名
  ///
  /// In zh, this message translates to:
  /// **'当前：{name}'**
  String settingsAiServiceActive(String name);

  /// AI 助手
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get aiTemplateCustom;

  /// 结果卡：供应商实际返回的模型名
  ///
  /// In zh, this message translates to:
  /// **'模型：{model}'**
  String aiServedModel(String model);
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
