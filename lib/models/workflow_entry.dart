/// 工作流条目的公共视图。
///
/// 本地资产与解析缓存字段各不相同，但它们都需要参与「按 id 解析展示名」，
/// 抽这一层是为了让展示名解析不必区分具体类型。
abstract class WorkflowEntry {
  String get id;
  String get name;
}
