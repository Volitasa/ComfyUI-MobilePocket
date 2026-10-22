import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/workflow_node.dart';
import '../../providers/workflow_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/task_manager.dart';
import '../../providers/ws_event_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/object_info_provider.dart';
import '../../services/object_info_service.dart';
import '../../services/submit_check.dart';
import '../../services/workflow_node_parser.dart';
import '../../utils.dart';
import '../main_screen.dart';
import '../widgets/param_field.dart';
import 'param_widgets/param_card_registry.dart';
import 'param_widgets/latent_size_card.dart';
import 'workflow_view.dart';

class RunView extends ConsumerStatefulWidget {
  final String workflowId;

  /// 非空时进入「快照模式」：表单结构与工作流数据都取自快照，不请求服务端。
  final String? snapshotId;

  /// 预填的表单值（键为 nodeParamKey），用于「再次运行」。
  final Map<String, dynamic>? initialParams;

  const RunView({
    super.key,
    required this.workflowId,
    this.snapshotId,
    this.initialParams,
  });

  @override
  ConsumerState<RunView> createState() => _RunViewState();
}

class _RunViewState extends ConsumerState<RunView> {
  List<WorkflowNode> _formConfig = [];
  final Map<String, dynamic> _formData = {};
  final Map<String, TextEditingController> _controllers = {};
  // 枚举下拉、开关、滑块的当前选中值
  final Map<String, dynamic> _widgetValues = {};
  bool _isExecuting = false;
  // 节点分组的展开/收起状态
  final Set<String> _expandedNodeIds = {};
  final Set<String> _collapsedNodeIds = {};
  // 「再次运行」时因配置变更而套用不到的参数条数（不能静默丢弃，要告知用户）
  int _unappliedCount = 0;
  // 本表单里需要向服务器问选项的下拉，所属的节点类名（决定要不要问、问哪些）
  /// 需要问下拉选项的节点类名（模型 / 采样器 / 调度器）。
  Set<String> _optionClassTypes = {};

  /// 需要问数值范围的节点类名（步数 / CFG / 尺寸 …）。
  Set<String> _rangeClassTypes = {};

  /// 工作流数据在缓存中的归属 ID：快照模式下用快照 id，否则用工作流 id。
  /// 两者必须区分，否则快照数据会被判成属于另一个工作流（串台）。
  String get _dataOwnerId => widget.snapshotId ?? widget.workflowId;

  bool get _isSnapshotMode => widget.snapshotId != null;

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  void _initForm() {
    final List<WorkflowNode>? savedConfig;

    if (_isSnapshotMode) {
      final snapshot = ref
          .read(snapshotProvider.notifier)
          .byId(widget.snapshotId!);
      if (snapshot == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).runSnapshotDeleted),
            ),
          );
          Navigator.pop(context);
        });
        return;
      }
      savedConfig = snapshot.mappingConfig;
      // 快照自带工作流数据，直接写入缓存，不请求服务端。
      // 这里还在 initState 里，写 provider 得让出当前帧
      scheduleProviderWrite(
        () => ref
            .read(workflowProvider.notifier)
            .setWorkflowData(snapshot.workflowJson, workflowId: _dataOwnerId),
      );
    } else {
      savedConfig = ref
          .read(workflowProvider.notifier)
          .getMappingConfig(widget.workflowId);
    }

    if (savedConfig == null || savedConfig.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).runNoFormConfig)),
        );
        Navigator.pop(context);
      });
      return;
    }

    _formConfig = savedConfig.where((node) => node.exposed).toList();

    _optionClassTypes = _collectOptionClassTypes();
    _rangeClassTypes = _collectRangeClassTypes();
    _ensureOptionData();

    final params = widget.initialParams;
    if (params != null) {
      // 配置被改过 → 部分参数在当前表单里已不存在，统计出来提示用户
      final exposedKeys = _formConfig
          .map((n) => nodeParamKey(n.id, n.key))
          .toSet();
      _unappliedCount = params.keys
          .where((k) => !exposedKeys.contains(k))
          .length;
    }

    for (var node in _formConfig) {
      // 同一节点可有多个参数，控制器/状态统一用 id:key 复合键，避免串台
      final k = nodeParamKey(node.id, node.key);
      final dynamic fromParams = params?[k];
      final bool hasInitial = params != null && params.containsKey(k);
      // 预填优先，否则退回配置里保存的默认值
      final dynamic initial = hasInitial ? fromParams : node.value;

      // ⚠️ 按 `control` 分派，与渲染同源：`control` 说是开关就是开关，
      // 哪怕 `paramType` 被推断成了 text（说明书声明 BOOLEAN、工作流里
      // 却存成了字符串时就会这样）。否则开关读不到初值，明明工作流里
      // 是「开」，首帧却显示成「关」。
      switch (_controlFor(node, paired: false)) {
        case ParamControl.seed:
          // 原样沿用：工作流本身可能就设了固定种子，且用户未必想换，
          // 替他随机反而是帮倒忙。只有完全没有初值时才生成。
          final seed = initial is int
              ? initial
              : int.tryParse(initial?.toString() ?? '');
          if (seed != null) {
            _setSeedValue(k, seed);
          } else {
            _generateSeed(k);
          }
          break;
        case ParamControl.text:
          _controllers[k] = TextEditingController(
            text: initial?.toString() ?? '',
          );
          break;
        case ParamControl.number:
        case ParamControl.slider:
          _controllers[k] = TextEditingController(text: _numToString(initial));
          break;
        case ParamControl.toggle:
          _widgetValues[k] = _isTrueLike(initial);
          break;
        case ParamControl.select:
          // 下拉当前值：取 value，若为空则取 options 第一项
          final opts = node.options;
          final current = initial?.toString();
          _widgetValues[k] = (current != null && opts.contains(current))
              ? current
              : (opts.isNotEmpty ? opts.first : (current ?? ''));
          break;
        case ParamControl.upload:
          // 图片初值为服务器上已有的文件名，仅作展示，不预载图片
          if (initial is String && initial.isNotEmpty) {
            _widgetValues[k] = initial;
          }
          break;
      }
    }

    // 确保工作流数据已加载：从首页直接进入运行页时，或缓存属于其它工作流时，
    // 都必须重新拉取当前工作流的数据。
    // （曾因只判空导致复用了上一个工作流的缓存，把错误的图提交给服务器）
    _ensureWorkflowData();
  }

  Future<void> _ensureWorkflowData() async {
    if (_isSnapshotMode) return; // 快照模式：数据已由 _initForm 写入缓存

    final state = ref.read(workflowProvider);
    // 数据已就绪且归属匹配当前工作流 → 无需拉取
    if (state.hasDataFor(_dataOwnerId)) return;

    // 本地资产与解析缓存都持久化在本地，重启后依然可用。
    // 解析缓存若已被清除这里会取不到 —— 入口来自服务器列表，清除后条目随即变灰，
    // 正常走不到这一步；真走到了也不能拿去按文件名请求服务器（那是 UI 格式）。
    final persisted = persistedWorkflowJson(ref, widget.workflowId);
    if (persisted != null) {
      // 从 initState 进来时不允许直接改 provider，让出当前帧再写
      await scheduleProviderWrite(
        () => ref
            .read(workflowProvider.notifier)
            .setWorkflowData(persisted, workflowId: widget.workflowId),
      );
      return;
    }

    await ref
        .read(workflowProvider.notifier)
        .fetchWorkflowContent(widget.workflowId);
  }

  /// 本表单里，哪些下拉需要向服务器问真实选项（按所属节点类名去重）。
  ///
  /// 新配置一律看 [WorkflowNode.control]：**凡是下拉都要问选项**。
  /// 旧的键名名单（`kDynamicOptionKeys ∪ kExtraComboKeys`）只在「没有 `control`」
  /// 的旧配置上兜底 —— 那份名单是「配置页还没定型」时代的启发式，必然漏键；
  /// 现在形态已落盘就别再拿它当口径，否则 `aspect_ratio` / `color_space` /
  /// `bit_depth` 这类被定成 `select` 的参数永远刷不回选项，
  /// 下拉里只剩当前值一项，等于白定型（方案 §8.1 陷阱 5）。
  ///
  /// 图片上传参数不在内（它的 `control` 是 `upload`），否则下拉会变成一串
  /// 服务器文件名，用户就传不了新图了。
  Set<String> _collectOptionClassTypes() {
    final types = <String>{};
    for (final node in _formConfig) {
      final control = node.control;
      if (control != null) {
        if (control != ParamControl.select) continue;
      } else {
        // 旧配置：形态只能靠推断，`ckpt_name` 这种「推断成文本、服务端实为
        // COMBO」的参数若不看名单就刷不到选项 —— 这里保留原行为。
        if (node.paramType == ParamType.image) continue;
        if (!kDynamicOptionKeys.contains(node.key) &&
            !kExtraComboKeys.contains(node.key)) {
          continue;
        }
      }
      types.add(node.classType);
    }
    return types;
  }

  /// 这个参数该用什么控件 —— **运行页形态的唯一权威**（方案 §1.1 原则 2、§3.5）。
  ///
  /// 只读配置页落盘的 [WorkflowNode.control]，**不做任何网络查询**，
  /// 因此取数成功 / 失败 / 取回不同版本，都不会让控件形态变一下。
  ///
  /// 旧配置、旧快照没有 `control` → 退回 [WorkflowNodeParser.resolveControl]
  /// 现算一次：用的是配置页同一份判定表，所以不存在两页形态错配的窗口。
  ///
  /// [spec] 只在 `control` 为 null 时起作用（兜底推断要用）。build 路径传
  /// [_specFor] 的结果；initState 里拿不到，传 null 即可。
  ///
  /// [paired] 为 true 表示占半列：半列宽放不下滑块，一律退回输入框。
  ParamControl _controlFor(
    WorkflowNode node, {
    required bool paired,
    NodeInputSpec? spec,
  }) {
    final resolved =
        node.control ??
        WorkflowNodeParser.resolveControl(
          key: node.key,
          rawValue: node.value,
          paramType: node.paramType,
          spec: spec,
        ) ??
        ParamControl.text;
    if (paired && resolved == ParamControl.slider) return ParamControl.number;
    return resolved;
  }

  /// 哪些节点需要为数值参数问 min/max（名单见 [kRangeParamKeys]）。
  ///
  /// 与下拉分开收：刷新按钮只在真有下拉时才出现，不能因为多了几个数值参数
  /// 就摆一个跟下拉无关的刷新入口。
  ///
  /// 判定看 `control`（与渲染同源），不再看推断出的 `paramType` ——
  /// 说明书说某个 text 参数其实是 INT 时，也才会被算进来。
  Set<String> _collectRangeClassTypes() {
    final types = <String>{};
    for (final node in _formConfig) {
      final control = _controlFor(node, paired: false);
      if (control != ParamControl.number && control != ParamControl.slider) {
        continue;
      }
      if (!kRangeParamKeys.contains(node.key)) continue;
      types.add(node.classType);
    }
    return types;
  }

  /// 该参数在服务器说明书里的定义（拿不到就是 null）。
  NodeInputSpec? _specFor(WorkflowNode node) {
    final serverId = ref.watch(connectionProvider).activeServerId;
    if (serverId == null) return null;
    return ref
        .watch(objectInfoProvider)
        .specFor(serverId, node.classType, node.key);
  }

  /// 与 [_specFor] 相同，但用 `read` —— **构建之外**的路径（提交取值、收集参数）用。
  ///
  /// `ref.watch` 只能在 build 里调，放进按钮回调会直接断言失败。
  NodeInputSpec? _specForRead(WorkflowNode node) {
    final serverId = ref.read(connectionProvider).activeServerId;
    if (serverId == null) return null;
    return ref
        .read(objectInfoProvider)
        .specFor(serverId, node.classType, node.key);
  }

  /// 数值输入框的红字提示。**只提示、不拦提交** —— 越界时让用户自己看见，
  /// 由他决定要不要改（有时就是要故意超范围试一下）。
  String? _numberError(WorkflowNode node) {
    final spec = _specFor(node);
    final key = nodeParamKey(node.id, node.key);
    final issue = checkNumberAgainstSpec(
      spec: spec,
      text: _controllers[key]?.text ?? '',
    );
    if (issue == null) return null;

    final l = AppLocalizations.of(context);
    if (issue == NumberIssue.notANumber) return l.runNumberInvalid;
    return l.runNumberRange(_fmtNum(spec!.min!), _fmtNum(spec.max!));
  }

  /// 1.0 显示成 1，0.5 仍显示 0.5，避免提示里冒出一堆多余的 0。
  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// 数值输入框。
  ///
  /// 用 [ValueListenableBuilder] 监听控制器：越界提示依赖当前文本，而改文本
  /// 本身不会让整页重建，不监听的话红字要等下一次重建才出现。
  /// 滑块只在「档位够少」时才画。
  ///
  /// 服务端给的合法范围经常大到没法拖：steps 1–10000（9999 档）、
  /// cfg 0–100（1000 档）、LoRA 强度 −100…100（20000 档）。而且两列布局下
  /// 滑轨实际只有 ~70dp，拖 1dp 就是上百步。这类一律退回输入框，
  /// 只有 denoise / start_percent 这种 0–1（100 档）才留滑块。
  ///
  /// ⚠️ 阈值必须用 [kSliderMaxDivisions]，别在这里另写一个常量 ——
  /// 配置页定型用的是那个，两处一旦漂移就会出现「配置页定成滑块、
  /// 运行页却死活不肯画」的矛盾（本文件原来有个同值的私有常量，已删）。

  /// 这个数值参数的可取值范围：**优先用配置页落盘的 `bounds`**。
  ///
  /// 落盘那份是定型时算的，**离线也能画滑块**；只有旧配置（没有 `bounds`）
  /// 才退回运行时说明书。否则滑块会在「说明书到达」那一刻从输入框跳成滑块，
  /// 直接违反 §1.1 原则 1（运行页形态不随网络变化）。
  ParamBounds? _boundsFor(WorkflowNode node) =>
      node.bounds ?? _specFor(node)?.toBounds();

  bool _sliderUsable(ParamBounds? bounds, bool decimal) {
    if (bounds == null || !bounds.hasSliderRange) return false;
    final step = (bounds.step != null && bounds.step! > 0)
        ? bounds.step!
        : (decimal ? 0.01 : 1);
    final divisions = (bounds.max! - bounds.min!) / step;
    return divisions.isFinite &&
        divisions > 0 &&
        divisions <= kSliderMaxDivisions;
  }

  Widget _numberField(
    WorkflowNode node, {
    required bool decimal,
    required String hint,
    bool paired = false,
    // ⚠️ 是否允许画滑块，由配置页定好的 `control` 决定（方案 §8.1 约束 9）。
    // 不能在这里再算一遍「档位够不够」—— 请求回来的 bounds 一变，
    // 档位数跨过 100 就会让控件在输入框与滑块之间跳变。
    bool allowSlider = true,
  }) {
    final k = nodeParamKey(node.id, node.key);
    final controller = _controllers[k];
    if (controller == null) return const SizedBox.shrink();

    final bounds = _boundsFor(node);
    // 半列宽放不下「滑块 + 数值」，两列时一律用输入框
    if (allowSlider && !paired && _sliderUsable(bounds, decimal)) {
      return _sliderField(node, controller, bounds!, decimal: decimal);
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, _, _) => TextField(
        controller: controller,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        decoration: ParamFieldStyle.decoration(
          context,
          hintText: hint,
          errorText: _numberError(node),
        ),
      ),
    );
  }

  /// 滑块 + 可编辑数值：手机上拖比打字快，但要随时能看到/改到精确值。
  Widget _sliderField(
    WorkflowNode node,
    TextEditingController controller,
    ParamBounds bounds, {
    required bool decimal,
  }) {
    final min = bounds.min!;
    final max = bounds.max!;
    final step = (bounds.step != null && bounds.step! > 0)
        ? bounds.step!
        : (decimal ? 0.01 : 1);
    final divisions = (max - min) / step;
    final usableDivisions = divisions.isFinite && divisions <= 1000
        ? divisions.round()
        : null;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, _) {
        final parsed = num.tryParse(value.text.trim());
        // 超出范围（或手输成了别的）时夹回边界，滑块必须有合法位置
        final current = (parsed ?? min).toDouble().clamp(min, max);
        // 滑块本身拖不出范围，但右手那个数值框可以手输 ——
        // 越界一样要看得见，不能因为「有滑块」就不提示。
        final error = _numberError(node);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: current,
                    min: min,
                    max: max,
                    divisions: usableDivisions,
                    onChanged: (v) => controller.text = _fmtValue(v, decimal),
                  ),
                ),
                SizedBox(
                  // 72 是「位数多一点的整数 + 小数」放得下的宽度；
                  // 原来 56 遇到 1000000 这种就开始横向滚动了
                  width: 72,
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13),
                    keyboardType: decimal
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    decoration: ParamFieldStyle.decoration(
                      context,
                      contentPadding: ParamFieldStyle.compactPadding,
                      invalid: error != null,
                    ),
                  ),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  error,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 写回控制器时的格式：整数不带小数点，小数最多两位、去掉尾随 0。
  ///
  /// 必须与 `_resolveValue` 的 `num.tryParse` 对得上，不能出现
  /// 「4.5000000001」这种提交后被服务器当成怪值。
  String _fmtValue(double v, bool decimal) {
    if (!decimal) return v.round().toString();
    final s = (v * 100).round() / 100;
    return s == s.roundToDouble() ? s.toInt().toString() : s.toString();
  }

  /// 进页面后问一次服务器，把下拉的真实选项取回来。
  ///
  /// 拿不到就当作没问过：界面退回原样（下拉里仍是工作流当前的那个值），
  /// 不弹错误、不卡住页面。
  ///
  /// ⚠️ **必须走写入式刷新，不能用 `ensureLoaded`**：后者是「补缺式」的
  /// （缓存命中就跳过），连进两次页面第二次一个请求都不发，跟方案 §3.5
  /// 「每次进入都重取」的承诺相反 —— 电脑上刚装的模型就永远拉不到。
  /// 也不能用 `refresh()`：它会先把整桶清空，首帧的完整选项会先缩成
  /// 「只剩当前值」再涨回去，观感上闪一下。
  void _ensureOptionData() {
    final classTypes = <String>{..._optionClassTypes, ..._rangeClassTypes};
    if (classTypes.isEmpty) return;
    final config = ref.read(connectionProvider);
    final serverId = config.activeServerId;
    if (!config.isConnected || serverId == null) return;

    // 还在 initState 里，写 provider 必须让出当前帧
    scheduleProviderWrite(() {
      ref
          .read(objectInfoProvider.notifier)
          .refreshInPlace(
            serverId: serverId,
            baseUrl: config.comfyUrl,
            classTypes: classTypes,
          );
    });
  }

  /// 手动刷新下拉选项：电脑上新装了模型，手机上能立刻拉到。
  Future<void> _refreshOptions() async {
    final l = AppLocalizations.of(context);
    final config = ref.read(connectionProvider);
    final serverId = config.activeServerId;
    if (serverId == null) return;

    final ok = await ref
        .read(objectInfoProvider.notifier)
        .refreshInPlace(
          serverId: serverId,
          baseUrl: config.comfyUrl,
          classTypes: <String>{..._optionClassTypes, ..._rangeClassTypes},
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l.runOptionsRefreshed : l.runOptionsRefreshFailed),
      ),
    );
  }

  /// 这个下拉当前该怎么显示（选项、选中项、是否以服务器为准）。
  EnumOptionView _enumView(WorkflowNode node) {
    final serverId = ref.watch(connectionProvider).activeServerId;
    final spec = serverId == null
        ? null
        : ref
              .watch(objectInfoProvider)
              .specFor(serverId, node.classType, node.key);
    // 只有「确实拿到了选项」才以服务器为准；
    // 问过但没问到（服务器不认识这个节点）等同于没数据。
    final usable = spec != null && spec.hasOptions ? spec : null;

    return resolveEnumOptions(
      hasServerData: usable != null,
      serverOptions: usable?.options ?? const [],
      currentValue: _widgetValues[nodeParamKey(node.id, node.key)]?.toString(),
      fallbackOptions: node.options,
    );
  }

  /// 提交前的「服务器侧」检查（方案 §3.7）。返回**第一条**该拦下的问题。
  ///
  /// 判定规则全在 [checkBeforeSubmit] 里（纯函数、可单测），这里只负责
  /// 把 provider 的取数状态、说明书、控件当前值喂给它。
  SubmitBlock? _preSubmitIssue() {
    final serverId = ref.read(connectionProvider).activeServerId;
    if (serverId == null) return null;

    final objectInfo = ref.read(objectInfoProvider);
    return checkBeforeSubmit(
      config: _formConfig,
      statusOf: (classType) => objectInfo.statusFor(serverId, classType),
      specOf: (classType, key) => objectInfo.specFor(serverId, classType, key),
      controlOf: (node) => _controlFor(node, paired: false),
      currentOf: (node) =>
          _widgetValues[nodeParamKey(node.id, node.key)]?.toString(),
    );
  }

  /// 收集当前表单值，供「再次运行」预填
  Map<String, dynamic> _collectParams() {
    final params = <String, dynamic>{};
    for (final node in _formConfig) {
      final k = nodeParamKey(node.id, node.key);
      if (_controlFor(node, paired: false) == ParamControl.upload) {
        // 图片只记录服务端文件名（原图可能已被服务端清理）
        final v = _widgetValues[k];
        if (v is String && v.isNotEmpty) params[k] = v;
        continue;
      }
      final v = _resolveValue(node);
      if (v == null || v == '') continue;
      params[k] = v;
    }
    return params;
  }

  /// 「再次运行」时顶部的提示条：说明参数来源与未能套用的条数
  Widget _buildRestoreBanner() {
    final l = AppLocalizations.of(context);
    final text = _unappliedCount > 0
        ? l.runParamsRestored(_unappliedCount)
        : l.runParamsRestoredAll;
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.history_toggle_off, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  String _numToString(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v is double) {
      // 去掉多余的小数尾零
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  void _setSeedValue(String nodeId, int seed) {
    setState(() {
      _formData[nodeId] = seed;
      final controller = _controllers.putIfAbsent(
        nodeId,
        () => TextEditingController(),
      );
      controller.text = seed.toString();
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _generateSeed(String nodeId) {
    // 定长生成：高 10 位 + 低 5 位，固定 15 位，避免 substring(0,15) 越界崩溃
    final high = Random().nextInt(1000000000) + 1000000000; // 10 位（1e9 ~ 2e9）
    final low = Random().nextInt(100000); // 0 ~ 99999
    final seed = high * 100000 + low;
    _setSeedValue(nodeId, seed);
  }

  Future<void> _pickImage(String nodeId) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _formData[nodeId] = {
          'bytes': result.files.single.bytes!,
          'filename': result.files.single.name,
        };
      });
    }
  }

  // 把控件里的值解析成提交用的 Dart 类型（纯函数在 utils.dart，便于单测）
  dynamic _resolveValue(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    // ⚠️ 这里在 build 之外（按钮回调 / 收集参数），必须用 read 版取说明书：
    // `ref.watch` 只能在 build 里用，放回调里会直接断言失败。
    final spec = _specForRead(node);
    return resolveParamValue(
      node: node,
      // 形态按 control 来 —— 与渲染同一个入口，两处不会打架
      control: _controlFor(node, paired: false, spec: spec),
      text: _controllers[k]?.text ?? '',
      widgetValue: _widgetValues[k],
      // 下拉提交原始值（`bit_depth` 选 8 提交整数 8，不是 "8"）
      spec: spec,
    );
  }

  Future<void> _handleExecute() async {
    // 在首个 await 前取好文案，避免异步 gap 后使用 context
    final l = AppLocalizations.of(context);
    final wfState = ref.read(workflowProvider);
    // 提交前再次校验：数据必须存在且归属匹配，避免提交错误的工作流
    if (!wfState.hasDataFor(_dataOwnerId)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.runDataNotReady)));
      }
      return;
    }
    final workflowData = wfState.currentWorkflowData!;

    // 服务器侧前置检查（方案 §3.7）：缺节点 / 缺选项先拦下来。
    // 不然请求发出去也是失败，服务器只会回一句看不懂的 node_errors。
    final issue = _preSubmitIssue();
    if (issue != null) {
      final text = issue.classType != null
          ? l.runNodeMissingOnServer(issue.classType!)
          : l.runOptionMissingOnServer(issue.alias!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      return;
    }

    setState(() => _isExecuting = true);
    ref.read(wsProvider.notifier).connect();

    try {
      // 深拷贝一份原始工作流，防止污染内存
      Map<String, dynamic> originalJson = jsonDecode(jsonEncode(workflowData));
      // 与解析侧保持一致：统一归一化后再解包节点结构
      Map<String, dynamic> promptNodes = normalizeWorkflowJson(originalJson);

      final taskManager = ref.read(taskManagerProvider.notifier);

      for (var node in _formConfig) {
        dynamic value;

        final paramKey = nodeParamKey(node.id, node.key);

        if (_controlFor(node, paired: false) == ParamControl.upload) {
          // 图片：只有用户重新选择了本地图片才上传；否则沿用工作流里的原值
          final picked = _formData[paramKey];
          if (picked != null) {
            final uploadedName = await taskManager.uploadImage(
              picked['bytes'],
              picked['filename'],
            );
            if (uploadedName == null) {
              throw Exception(l.runImageUploadFailed);
            }
            value = uploadedName;
            // 记进快照参数，否则再次运行时会丢掉本次上传的图
            _widgetValues[paramKey] = uploadedName;
          } else {
            // 未重新选择，保持工作流原有图片文件名不变
            continue;
          }
        } else {
          value = _resolveValue(node);
        }

        if (value == null || value == '') continue;

        if (promptNodes[node.id] != null &&
            promptNodes[node.id]['inputs'] != null) {
          promptNodes[node.id]['inputs'][node.key] = value;
        }
      }

      final result = await taskManager.executeWorkflow(promptNodes);

      if (result == null) {
        throw Exception(l.runSubmitFailed);
      }
      if (result.containsKey('prompt_id')) {
        // 固化快照：内容没变则复用同一份，供后续「再次运行」还原表单
        final snapshotId = ref
            .read(snapshotProvider.notifier)
            .upsert(
              workflowJson: workflowData,
              mappingConfig: _formConfig,
              // 取不到真实名字时留空，展示时按当前语言补默认名（翻译不落盘）。
              // 必须用「本地资产 + 解析缓存」的合集：服务器解析来的工作流只在
              // 解析缓存里，只查本地库会查不到，名字存成空串显示成「本地导入」。
              sourceName:
                  workflowNameForStorage(
                    ref.read(knownWorkflowEntriesProvider),
                    widget.workflowId,
                  ) ??
                  '',
              serverId: ref.read(connectionProvider).activeServerId,
            );
        taskManager.createNewTask(
          result['prompt_id'],
          widget.workflowId,
          snapshotId: snapshotId,
          params: _collectParams(),
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).runTaskSubmitted),
          ),
        );
        Navigator.pop(context);
        ref.read(mainTabIndexProvider.notifier).state = MainTabs.history;
      } else {
        // 服务端返回非 200：透出具体错误（node_errors 等），而非笼统提示
        final code = result['_http_error'];
        final body = result['_body'];
        String detail = '';
        if (body is Map && body['node_errors'] != null) {
          final errors = body['node_errors'];
          detail = errors is Map && errors.isNotEmpty
              ? l.runErrorNodes(errors.keys.join(', '))
              : '';
        }
        throw Exception(l.runSubmitFailedHttp('$code', detail));
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  /// 把全部节点卡片一次性展开或折叠：节点一多，先折叠看全貌比逐张点快得多。
  void _setAllExpanded(bool expand) {
    final ids = _formConfig.map((n) => n.id).toSet();
    setState(() {
      if (expand) {
        _collapsedNodeIds.clear();
        _expandedNodeIds.addAll(ids);
      } else {
        _expandedNodeIds.clear();
        _collapsedNodeIds.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayName = resolveWorkflowName(
      ref.read(knownWorkflowEntriesProvider),
      widget.workflowId,
      localLabel: AppLocalizations.of(context).workflowLocalImport,
    );
    // 只有一张卡时「展开/折叠全部」没有意义，不摆
    final hasManyCards = _formConfig.map((n) => n.id).toSet().length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).runTitle(displayName),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (hasManyCards)
            PopupMenuButton<bool>(
              tooltip: AppLocalizations.of(context).runFoldMenu,
              icon: const Icon(Icons.unfold_more),
              onSelected: _setAllExpanded,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: true,
                  child: Text(AppLocalizations.of(context).runExpandAll),
                ),
                PopupMenuItem(
                  value: false,
                  child: Text(AppLocalizations.of(context).runCollapseAll),
                ),
              ],
            ),
          // 只在表单里确实有模型/采样器下拉时才出现，纯提示词的工作流不该
          // 摆一个点不动的按钮。
          if (_optionClassTypes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context).runRefreshModels,
              onPressed: _refreshOptions,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppLocalizations.of(context).runNodeConfigTooltip,
            // 跳转到节点配置面板（用 pushReplacement 替换当前页，
            // 与配置页「保存并进入运行页」的 pushReplacement 对称，避免栈内重复）
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => WorkflowView(
                  workflowId: widget.workflowId,
                  snapshotId: widget.snapshotId,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 由「再次运行」进入时，说明参数来源与 seed 的处理方式
          if (widget.initialParams != null) _buildRestoreBanner(),
          Expanded(
            child: Builder(
              builder: (context) {
                // 按节点分组展示：同一节点的多个参数合并为一张卡片，支持展开/折叠
                final groups = <String, List<WorkflowNode>>{};
                for (final n in _formConfig) {
                  groups.putIfAbsent(n.id, () => []).add(n);
                }
                final groupIds = groups.keys.toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupIds.length,
                  itemBuilder: (context, index) {
                    final nodeId = groupIds[index];
                    final params = groups[nodeId]!;
                    final expanded = _expandedNodeIds.contains(nodeId)
                        ? true
                        : _collapsedNodeIds.contains(nodeId)
                        ? false
                        : true; // 运行页默认全部展开

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            onTap: () => setState(() {
                              if (expanded) {
                                _collapsedNodeIds.add(nodeId);
                                _expandedNodeIds.remove(nodeId);
                              } else {
                                _expandedNodeIds.add(nodeId);
                                _collapsedNodeIds.remove(nodeId);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  AnimatedRotation(
                                    turns: expanded ? 0 : -0.25,
                                    duration: const Duration(milliseconds: 150),
                                    child: const Icon(
                                      Icons.expand_more,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _groupLabel(params),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    AppLocalizations.of(context)
                                        .configParamCount(params.length),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (expanded)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Column(
                                children: [
                                  const Divider(height: 1),
                                  ..._buildParamBody(params),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _isExecuting ? Colors.grey : Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isExecuting ? null : _handleExecute,
                  icon: _isExecuting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: Text(
                    _isExecuting
                        ? AppLocalizations.of(context).runSubmitting
                        : AppLocalizations.of(context).runGenerateNow,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡内主体：命中自定义卡就用自定义卡，否则走通用参数块。
  List<Widget> _buildParamBody(List<WorkflowNode> params) {
    final match = matchParamCard(params);
    if (match != null && match.kind == ParamCardKind.latentSize) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LatentSizeCard(
            params: match.params,
            controllerOf: (node) =>
                _controllers[nodeParamKey(node.id, node.key)],
          ),
        ),
      ];
    }
    return _buildParamFields(params);
  }

  /// 同一节点内的参数块序列。
  ///
  /// 成对的短数值（宽/高、步数/CFG、两个 LoRA 强度）在屏幕够宽时并排两列，
  /// 窄屏自动回退单列 —— 并排是为了少滚一屏，代价是每列变窄，不能硬来。
  List<Widget> _buildParamFields(List<WorkflowNode> params) {
    final width = MediaQuery.sizeOf(context).width;
    final twoColumns = width >= 360;
    final rows = <Widget>[];
    var i = 0;
    while (i < params.length) {
      final node = params[i];
      final partner = twoColumns ? _pairPartner(node, params, i) : null;
      if (partner != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildParamBlock(node, paired: true)),
                const SizedBox(width: 12),
                Expanded(child: _buildParamBlock(partner, paired: true)),
              ],
            ),
          ),
        );
        i += 2;
      } else {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildParamBlock(node),
          ),
        );
        i += 1;
      }
    }
    return rows;
  }

  /// 找紧随其后的「搭档参数」，能配对就返回，否则 null。
  WorkflowNode? _pairPartner(
    WorkflowNode node,
    List<WorkflowNode> params,
    int i,
  ) {
    final expected = kPairParamKeys[node.key];
    if (expected == null) return null;
    if (i + 1 >= params.length) return null;
    final next = params[i + 1];
    if (next.key != expected) return null;
    if (!_pairable(node) || !_pairable(next)) return null;
    return next;
  }

  /// 能不能占半列：短控件才可以（数值、下拉、单行文本）。
  /// 布尔整行更好点、图片要宽度、种子带骰子按钮，都不并排。
  ///
  /// ⚠️ 判定改按 [ParamControl]（方案 §8.1 陷阱 2）：`paramType` 只是推断结果，
  /// 而真正在屏幕上占多宽的是控件。比如 `type` / `device` 推断成 text、运行页却是
  /// 下拉，两者判定口径不同就会导致「明明是短下拉却不并排」。
  bool _pairable(WorkflowNode node) {
    switch (_controlFor(node, paired: false, spec: _specFor(node))) {
      case ParamControl.number:
      case ParamControl.slider:
      case ParamControl.select:
      case ParamControl.text:
        return true;
      case ParamControl.upload:
      case ParamControl.toggle:
      case ParamControl.seed:
        return false;
    }
  }

  /// 单个参数：别名 + 参数键 chip + 控件
  Widget _buildParamBlock(WorkflowNode node, {bool paired = false}) {
    // 布尔参数合成一行：别名 + 状态 + 开关。
    // 分成「标签行 + 开关行」时，开关行的「开启/关闭」跟上面的别名说的是同一件事，
    // 白占一行 40px，而开关本身已经把状态摆在那里了。
    if (_controlFor(node, paired: paired, spec: _specFor(node)) ==
        ParamControl.toggle) {
      return _buildBoolBlock(node);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                node.alias,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            // 别名就是参数名时再挂一个同名 chip 只是重复
            if (node.key != 'text' &&
                node.key != 'value' &&
                node.alias != node.key)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.key,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildInputControl(node, paired: paired),
      ],
    );
  }

  /// 布尔参数的一行版：别名在左、状态小字在右、开关收尾。
  Widget _buildBoolBlock(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    final on = _widgetValues[k] == true;
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            node.alias,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          on ? l.runBoolOn : l.runBoolOff,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        _boolSwitch(k),
      ],
    );
  }

  /// 开关本身。单独抽出来是为了让「参数块」与「一行版」共用同一份状态读写，
  /// 不至于两处各写一份 setState。
  Widget _boolSwitch(String k) {
    return Switch(
      value: _widgetValues[k] == true,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: (val) => setState(() => _widgetValues[k] = val),
    );
  }

  // 分组卡片头部标签：优先节点标题，无有效标题回退类名
  String _groupLabel(List<WorkflowNode> params) {
    final classType = params.first.classType;
    final title = params.first.title;
    if (isMeaningfulTitle(title, classType)) return title;
    return classType;
  }

  /// 下拉控件。enumType 与「服务器说是 COMBO 的 text 参数」共用这一份渲染。
  ///
  /// 拿到服务器真实选项时，下拉里**只有**真实选项 —— 工作流里写的那个模型
  /// 如果服务器上没有，就不再塞进选项里凑数，用户点开菜单自己看得出来，
  /// 提交时也会被拦下（拦截只针对模型/采样器类键，见 _missingOnServerNodes）。
  Widget _enumControl(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    final l10n = AppLocalizations.of(context);
    final view = _enumView(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // 选项是在页面显示之后才到的。initialValue 只在创建时生效一次，
          // 所以必须让 key 跟着选项走，否则真选项到了下拉也不刷新。
          key: ValueKey(
            '$k:${view.fromServer ? 's' : 'f'}:${view.options.length}',
          ),
          initialValue: view.selected,
          hint: Text(l10n.runSelectPlaceholder),
          isExpanded: true,
          decoration: ParamFieldStyle.decoration(context),
          items: view.options
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _widgetValues[k] = val);
          },
        ),
        if (view.missingOnServer) ...[
          const SizedBox(height: 4),
          Text(
            l10n.runModelMissing,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _buildInputControl(WorkflowNode node, {bool paired = false}) {
    // 同一节点可有多个参数，控制器/状态统一用 id:key 复合键
    final k = nodeParamKey(node.id, node.key);
    final l10n = AppLocalizations.of(context);

    // ⚠️ 形态的**唯一权威**是配置页定好的 `control`：运行页**只读它**，
    // 请求回来的数据只能改「下拉候选值」和「校验用的 bounds」，
    // 绝不能反过来改变控件（方案 §1.1 原则 1 / 2、§3.5）。
    //
    // 没有 `control`（升级前保存的旧配置 / 旧快照）时退回 `resolveControl`
    // 现算一次 —— 用的是同一份判定表，所以不存在两页形态错配的窗口。
    final control = _controlFor(node, paired: paired, spec: _specFor(node));
    switch (control) {
      case ParamControl.upload:
        return _imageUploader(node);
      case ParamControl.select:
        // 非 enumType 的参数没有 _widgetValues 初值，这里补一次；
        // _resolveValue 会优先读它，否则提交时会把下拉选的值丢掉。
        // ⚠️ 必须取控制器里的文本（「再次运行」时它装着上次的预填值），
        //    不能直接取 node.value —— 否则预填会被工作流原值顶掉。
        _widgetValues.putIfAbsent(
          k,
          () => _controllers[k]?.text ?? node.value?.toString() ?? '',
        );
        return _enumControl(node);
      case ParamControl.toggle:
        _widgetValues.putIfAbsent(k, () => _isTrueLike(node.value));
        return Align(alignment: Alignment.centerLeft, child: _boolSwitch(k));
      case ParamControl.number:
        return _numberField(
          node,
          decimal: node.paramType == ParamType.float,
          hint: node.paramType == ParamType.float
              ? l10n.runFloatHint
              : l10n.runIntHint,
          paired: paired,
          allowSlider: false,
        );
      case ParamControl.slider:
        return _numberField(
          node,
          decimal: node.paramType == ParamType.float,
          hint: node.paramType == ParamType.float
              ? l10n.runFloatHint
              : l10n.runIntHint,
          paired: paired,
          allowSlider: true,
        );
      case ParamControl.seed:
        return _seedControl(node);
      case ParamControl.text:
        // 只有提示词类需要多行；`default`、`filename_prefix` 这种短值
        // 给两行纯粹是白占高度（按 key 判，不按内容判 —— 内容一变就得重建）
        final isPrompt = node.key == 'text' || node.key == 'value';
        return TextField(
          controller: _controllers[k],
          maxLines: isPrompt ? 6 : 1,
          minLines: isPrompt ? 2 : 1,
          decoration: ParamFieldStyle.decoration(
            context,
            hintText: AppLocalizations.of(context).runTextHint,
          ),
        );
    }
  }

  /// 图片上传卡：缩略图 96 + 两个按钮并排，不再把按钮压在图下面。
  ///
  /// ⚠️ 只要是图片参数就一定走这里（方案 §8.1 约束 3）：服务器说明书说它是
  /// COMBO 也不听 —— 否则下拉里会是一串服务器文件名，用户就传不了新图了。
  Widget _imageUploader(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    final hasImage = _formData[k] != null;
    final serverImage = _widgetValues[k] as String?;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _formData[k]['bytes'],
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (serverImage != null && serverImage.isNotEmpty) ...[
          // 工作流自带的服务器图片：从 /view 拉预览
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              _serverImageUrl(serverImage),
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 96,
                width: double.infinity,
                color: Colors.grey.shade100,
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.runUsingServerImage(serverImage),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(k),
                icon: const Icon(Icons.image, size: 18),
                label: Text(hasImage ? l.runChangeImage : l.runPickImage),
              ),
            ),
            // 换了本地图之后还能退回工作流里那张
            if (hasImage && serverImage != null && serverImage.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _formData.remove(k)),
                  child: Text(l.runUseServerImage),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 种子：数字框 + 骰子按钮。
  ///
  /// 只留图标：带文字的按钮在窄屏会把种子输入框挤成一条缝，
  /// 而这一行里真正要看的是那串数字。
  Widget _seedControl(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controllers[k],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _generateSeed(k),
          icon: const Icon(Icons.casino, size: 20),
          tooltip: AppLocalizations.of(context).runRandom,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
      ],
    );
  }

  /// 值是否算「真」：bool 直接判，数字非零为真，字符串认 true/yes/on/1。
  ///
  /// ⚠️ 只在一种情况下有意义：服务器说明书声明为 BOOLEAN，但工作流里
  /// 写成了字符串或数字。此时 `paramType` 会被推断成 text，initState
  /// 只建了文本控制器、没准备 `_widgetValues`，开关得自己兜个初值，
  /// 否则明明工作流里是「开」，界面上却显示成「关」。
  bool _isTrueLike(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == 'yes' || s == 'on' || s == '1';
    }
    return false;
  }

  // 组装服务器图片的查看 URL（用于工作流自带参考图的预览）
  String _serverImageUrl(String filename) {
    final config = ref.read(connectionProvider);
    final encoded = Uri.encodeComponent(filename);
    // LoadImage 的图片通常在 input 目录；type 默认 input
    return '${config.comfyUrl}/view?filename=$encoded&type=input';
  }
}
