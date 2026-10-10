# ComfyUI MobilePocket

移动端 ComfyUI 远程客户端。用手机浏览服务器上的工作流，把常用参数暴露成动态表单，一键下发生成任务，实时跟踪进度，并把结果存进本地画廊与手机相册。

## 使用前准备

1. 一台已启动、且 App 能访问到的 **ComfyUI 服务端**。
2. 若要使用「在线获取工作流」，服务端需要安装 [ComfyUI-AutoSaveAPI](https://github.com/Volitasa/ComfyUI-AutoSaveAPI) 插件——它负责把工作流导出为 `userdata/workflows/` 下的 API 格式文件供本 App 读取。

> 注：App 识别的是 **API 格式 JSON**（以节点 ID 为键、含 `class_type` 与 `inputs`），普通 UI 界面保存的 workflow JSON 不适用。

## 功能

### 连接管理

- 支持保存多套服务器配置（如「家里内网」「公司外网」），每条可设**主地址 + 备用地址**，主地址不通时自动回退
- 一键测试连通性；顶部常驻连接状态徽标，点击直达配置页
- 切换服务器会清空工作流列表，但**不影响**本地生成记录与画廊

### 工作流

- 拉取服务器 `userdata/workflows` 下的 API 格式工作流，也可导入本地 JSON 文件
- 自动解析节点参数；白名单节点（KSampler、CLIPTextEncode、各类 Loader、EmptyLatentImage 等）内的**种子、提示词、尺寸、采样器、模型名**等可勾选暴露，并自定义别名
- 已配置过的工作流，在首页点击可直接进入运行页

### 生成

- 按配置动态生成表单：整数 / 浮点 / 文本 / 下拉枚举 / 布尔 / 种子（带随机按钮）/ 参考图上传
- WebSocket 实时回推进度，显示当前所在节点与百分比
- 任务共五种状态：**排队中 / 生成中 / 已完成 / 已失败 / 已中断**；失败时会展示服务端返回的具体错误原因
- App 崩溃或断线后重新连接，会主动向服务端对账，修正卡在未终结状态的任务

### 画廊与生成记录

- 生成结果自动下载到本地画廊，**保留原始 PNG 元数据**（可拖回 ComfyUI 复现）
- 独立画廊 Tab：网格浏览、大图查看、视频播放、保存到手机相册
- 保存相册时可选「普通图片（剔除元数据）」或「带工作流原图」
- 删除生成记录时可自行选择**仅删记录**（保留图片）或**同时删除画廊图片**；画廊随记录变化自动刷新

## 技术栈

Flutter · Riverpod（状态管理）· http · web_socket_channel · shared_preferences · file_picker · video_player · gal（相册保存）· path_provider

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
├── theme.dart                # 主题色
├── utils.dart                # 通用工具函数
├── models/                   # 数据模型
│   ├── task_history          # 任务历史（五种状态与本地图片路径）
│   └── workflow_node         # 工作流节点 / 参数配置
├── providers/                # Riverpod 状态层
│   ├── connection_provider   # 多服务器连接与主备回退
│   ├── workflow_provider     # 工作流列表、内容与参数映射
│   ├── task_manager          # 任务提交、历史持久化、本地画廊化
│   └── ws_event_provider     # WebSocket 通道
├── services/
│   ├── gallery_store         # 本地画廊存储（保留元数据）
│   └── png_metadata_stripper # PNG 元数据剔除（保存普通图片时）
└── ui/
    ├── main_screen           # 底部导航壳
    ├── home/                 # 工作流列表与本地导入
    ├── setup/                # 服务器配置
    ├── builder/              # 参数配置面板 / 运行页
    ├── gallery/              # 生成记录 / 画廊 / 媒体浏览
    └── widgets/              # 连接状态徽标
```

## 图标

App 使用自定义图标，并按 Android 自适应图标规范输出：背景层铺满整个 108dp 画布，前景层内容位于中央 72dp 安全圆内，因此在圆形、圆角方形、水滴形等不同 launcher 遮罩下都不会露出底色或被裁切。图标源文件见 `design/app_icon_1024.png`。
