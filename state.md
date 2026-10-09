移动端 ComfyUI 控制台项目全局档案 (V2 详尽版)
一、 宏观架构与技术栈
产品定位：跨平台移动端 App（基于 Capacitor 封装），作为本地或云端 ComfyUI 的远程遥控器与结果接收端。

前端基建：Vue 3 (Composition API) + Vue Router (SPA 路由) + Pinia (全局状态共享)。

通信协议：

RESTful API (HTTP)：负责连通性测试、工作流拉取、图片上传、任务下发（/system_stats, /userdata, /upload/image, /prompt, /history）。

WebSocket：负责建立长连接，实时监听生图进度（executing, progress）与成品回传（executed）。

网络代理：开发环境下利用 Vite server.proxy 绕过浏览器 CORS 同源策略并重写 Origin 头；生产环境（原生 App）直接发包。

二、 全局功能规划路线图 (Roadmap)
整个 App 的产品生命周期划分为以下 5 个核心模块：

通信与发现模块 (Phase 1 - 基建)

规划：支持多服务器地址管理，输入 IP 即可探测 ComfyUI 连通性。拉取服务端 /userdata/workflows 目录下的所有 API 格式图纸并列表展示。

状态：✅ 已完成。

动态 UI 映射模块 (Phase 2 - 装配)

规划：解析 _api.json 内部的深层节点依赖。允许用户勾选需要暴露到手机端的参数（如 KSampler 的种子、CLIPTextEncode 的提示词），为其设置易懂的别名（Alias），并将这套映射关系持久化到本地。

状态：✅ 已完成。

核心执行与实时反馈模块 (Phase 3 - 核心交互)

规划：渲染上一步装配好的表单。处理文本、数字、图片（文件上传）等不同类型的数据输入。执行时深拷贝模板，精准覆写参数，发起 POST 请求，并利用 WebSocket 实时渲染进度条与最终生成的图片。

状态：🚧 开发中（当前卡点所在）。指令下发已通，但 WebSocket 状态机解析与 SPA 生命周期管理存在 Bug。

历史记录与资产管理模块 (Phase 4 - 沉淀)

规划：调用 /history 接口，展示过往生成的历史图片画廊。支持点击图片查看当时使用的 Prompt 参数（类似图库的 EXIF 信息查看）。

状态：❌ 未开始。

原生端能力接入 (Phase 5 - 移动化)

规划：利用 Capacitor 插件，将最终生成的图片直接保存至手机相册（Camera Roll）；调用手机原生相册或摄像头直接作为 LoadImage 节点的输入源。

状态：❌ 未开始。

三、 已经落地的核心逻辑细节
身份凭证固化：在 config.js 中实现了 App 运行期唯一的 clientId，作为 WebSocket 和 HTTP 任务下发的统一身份标识。

绕过路径路由限制：成功处理了 ComfyUI /userdata 接口不能直接通过 URL 路径访问多级目录的问题，采用 encodeURIComponent('workflows/xxx.json') 转化为 %2F 实现单文件精准拉取。

参数覆写机制：在 handleExecute 中实现了数据组装，先将 File 对象通过 FormData 异步上传，拿到远端 filename 后，再连同文本、数字参数一起精准注入到目标节点的 inputs 字段中。

四、 尚未开发的待办事项 (TODO)
配置页 (WorkflowView.vue) 需要增加“直接运行”按钮，对于已经装配过的图纸，允许一键跳过配置步骤。

工作流列表页的搜索过滤与分类功能。

断线重连或杀后台后的“手动恢复/同步远端任务”交互按钮。

五、 当前阻断性 Bug 与异常表现 (待新窗口解决的核心)
WebSocket 进度遭误杀（假死状态）：

现象：点击生成后，UI 永远停留在“等待服务端响应...”，进度条不走，最终图片也不显示。

根本原因：引入的 activePromptId 拦截防御机制存在缺陷。ComfyUI 推送的 progress 和 executing 数据包中可能并没有携带 prompt_id，或者层级不对，导致 workflow.js 中的 if (msg.data.prompt_id !== activePromptId.value) return 触发了误杀，丢弃了真正的进度更新。

SPA 路由状态脱节（防失忆机制失效）：

现象：在生成过程中，从 RunView 退回首页列表，再重新点击该工作流进入，进度条和图片显示全部丢失，变成白板开局。

根本原因：为了防止“串图”，之前暴力删除了 onMounted 里的 checkHistoryForTask（自动查历史记录），并且现有的 lastWorkflowId 判断逻辑未能优雅地在“返回再进入”时接管仍在运行的 WebSocket 状态。
