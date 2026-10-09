# ComfyUI MobilePocket

一款移动端 ComfyUI 远程客户端，用手机浏览服务器上的工作流、把常用参数暴露成动态表单，一键下发生成任务并实时查看进度与结果。

## 功能

- **连接管理**：配置 ComfyUI 服务地址，测试连通后自动建立 WebSocket 通道。
- **工作流浏览**：拉取服务器 `userdata/workflows` 下的 `_api.json` 工作流，或导入本地 JSON。
- **参数配置**：解析工作流节点，勾选需要暴露的种子 / 提示词 / 图片参数并命名。
- **动态表单**：按配置生成表单，支持随机种子、图片上传。
- **生成记录**：实时显示任务进度（WebSocket 回推），浏览生成结果并保存到相册。

## 技术栈

- Flutter / Riverpod（状态管理）
- shared_preferences（本地持久化）
- web_socket_channel（任务进度回推）
- video_player / gal（视频播放与相册保存）

## 开发

```bash
flutter pub get
flutter run
```

## 测试

```bash
flutter test
```

## 目录结构

```
lib/
├── main.dart                 # 入口，注入 SharedPreferences
├── utils.dart                # 通用工具函数
├── models/                   # 数据模型（TaskHistory / WorkflowNode）
├── providers/                # Riverpod 状态层
│   ├── connection_provider   # 连接配置与测试
│   ├── workflow_provider     # 工作流列表与节点映射
│   ├── task_manager          # 任务历史与提交
│   └── ws_event_provider     # WebSocket 通道
└── ui/
    ├── main_screen           # 底部导航壳
    ├── home/                 # 工作流列表
    ├── setup/                # 服务器配置
    ├── builder/              # 配置面板 / 运行页
    └── gallery/              # 生成记录与媒体浏览
```
