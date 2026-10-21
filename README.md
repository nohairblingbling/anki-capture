# Anki Capture

在 Edge、Chrome、PDF Expert 中选中英语单词或短语，按快捷键，调用本机已登录的 Codex / Claude Code / Gemini CLI 生成字卡并写入预选 Anki 牌组。

原生 macOS 菜单栏应用与 CLI 共享 Swift 核心。macOS 14+，无常驻 Web 服务。

本机当前发布预览包为 Apple Silicon（arm64）；从源码构建需要 Xcode 16+ / Swift 6。Intel 架构需要单独构建并验证。

## 第一次使用

1. 打开 `Anki Capture.app` → **AI 连接**。为要使用的服务点击「连接账号」，在官方 CLI 和网页中完成自己的登录，然后返回刷新或验证连接。未安装 CLI 时，页面会提供官方安装入口。
2. Anki 安装 **AnkiConnect**（工具 → 插件 → 获取插件 → `2055492159`），然后重启 Anki。
3. 在 **偏好设置** 点击“刷新牌组与连接”，选择你已有的目标牌组并保存。
4. 在 **AI 连接** 选择默认制卡服务，设置默认模型、候选模型或自定义模型 ID。点击「验证连接」会发出一次示例制卡请求，消耗少量该服务额度，不向 Anki 写卡。
5. 开启辅助功能权限。在阅读器中选词，按 **⌃⌥⌘A**。快捷键可以在窗口或设置中修改。

首次写卡自动创建专用笔记类型 `Anki Capture`，包含独立的去重键、词条、释义、定义、词性、发音、例句、原句、来源和时间字段。已存在但字段不同的同名笔记类型不会被覆盖。

默认生成后自动写入。关闭“生成后直接加入牌组”后，可预览和编辑，再确认加入。

**Dock 图标**默认显示。在「偏好设置 → 应用」或菜单栏中切换「在 Dock 中显示」，立即生效并记住选择；隐藏后仍可从菜单栏打开收词窗口和 AI 连接页面。关闭主窗口不会退出菜单栏后台。

三种服务可以分别登录，只有默认制卡服务会用于新捕获的任务。登录令牌由各家 CLI 保存，安装包不包含开发者账号或个人配置。见[账号连接说明](docs/connections.md)。

## 运行与构建

```bash
swift test
scripts/build-app.sh
scripts/install.sh
```

构建产物：`dist/Anki Capture.app`。安装到 `~/Applications/Anki Capture.app`，CLI 链接位于 `~/.local/bin/anki-capture`。这是本机开发签名，尚未进行 Apple 公证；修改并重新签名后，系统可能要求重新授予辅助功能权限。

本机有 Apple Development / Developer ID 证书时，可在项目根目录的 `.signing-identity` 中用一行保存证书名称或 SHA-1，供后续构建沿用；此文件由 Git 忽略。也可用 `ANKI_CAPTURE_SIGNING_IDENTITY='证书名称或 SHA-1' scripts/build-app.sh` 临时覆盖。均未指定时使用 ad-hoc 签名，其授权绑定单次构建的代码哈希。更换签名方式后需要重新授权一次；此项目不在 Git 中保存签名私钥或证书文件。

如果系统设置中已开启辅助功能，但 App 仍显示未授权，旧版本的签名记录可能已经失效。可在系统设置中移除旧的 Anki Capture 项目，再添加当前 `~/Applications/Anki Capture.app` 并允许。也可在终端执行 `tccutil reset Accessibility dev.ankicapture.app`，然后在 App 中重新申请并由用户开启授权；此命令只清除本工具的辅助功能授权。单纯关闭再开启旧记录可能无效。

## CLI

```bash
anki-capture doctor
anki-capture connections
anki-capture connections --login-command claude
anki-capture connections --verify gemini
anki-capture models
anki-capture decks
anki-capture configure --deck 'English' --provider codex
anki-capture configure --provider gemini --model flash
anki-capture configure --show-in-dock false
anki-capture setup
anki-capture generate salient --context 'The paper highlights three salient findings.'
anki-capture add 'in light of' --context 'In light of the evidence, we revised the hypothesis.'
anki-capture add salient --preview
anki-capture add salient --queue-only
anki-capture jobs
anki-capture retry JOB_ID
anki-capture undo JOB_ID --yes
anki-capture run --watch
```

`generate` 仅返回 JSON。`add` 先保存任务，再调用模型；`--queue-only` 仅入队；`--preview` 等待确认。`retry` 既可重试失败任务，也可确认预览字卡。数据操作子命令支持 `--data-dir PATH` 指定独立数据目录。`models` 列出 Codex 本机模型缓存和 Claude / Gemini 常用别名，模型实际权限由服务端验证。CLI 修改 Dock 配置后，重新打开 App 生效；App 内开关即时生效。

配置 Claude：先在终端运行 `claude auth login`，再 `anki-capture configure --provider claude --model sonnet`。程序保留官方 CLI 的认证和供应商配置，不复制或读取登录令牌。订阅登录与 API Key 登录的计费不同；设置其他供应商或 API Key 后会沿用该配置。本工具不会自动切换到另一个付费供应商。

`doctor` 会报告各组件状态；当前所选 CLI 未登录或状态尚未验证时退出码为 2，AnkiConnect 或目标牌组未就绪时为 3。Gemini 没有独立的官方登录状态查询，因此仅安装 CLI 会显示「等待验证」，可显式运行 `connections --verify gemini` 确认当前模型可用。普通状态刷新不调用模型。

## 队列和数据

本地数据位于 `~/Library/Application Support/AnkiCapture/`：

- `config.json`：牌组、模型与 CLI 路径；文件权限 `0600`。
- `jobs.sqlite3`：持久化任务、原句、生成字卡、处理状态与 Anki 笔记 ID。
- `runtime/`：调用 CLI 的临时工作目录；正常结束后清理。

数据库使用 WAL 和事务租约，允许 App 与 CLI 共用。相同词条、上下文、牌组和笔记类型的重复请求合并；写入前根据稳定的词条/词义键查重。调用超时后再次写卡会先查询，避免重复添加。Anki 离线的任务保留生成内容，每 20 秒重试写入；其他失败可手动重试。进程异常退出时，过期租约在 10 分钟内恢复。

AI 只生成固定结构的数据，Anki 写入由程序执行。所有字段在写卡前转义 HTML。仅连接本机 AnkiConnect HTTP 接口。本应用不保存 CLI 原始日志，也不读取令牌；官方 CLI 自身的会话及缓存仍遵循各家设置（Gemini CLI 可能保留本地会话）。用户选择的词汇及上下文会由所选官方 CLI 发送到其配置的模型服务；这是本地调用入口，模型推理通常在云端完成。Gemini 子进程禁用工具、扩展、MCP 和 hooks，沿用 CLI 原有认证位置。

“撤销添加”只适用于本任务新建、尚无复习记录且仍带有本工具标记的笔记；重复匹配到的已有笔记无法通过该入口删除。

## 取词范围

- 仅在触发快捷键时读取前台选区，优先使用辅助功能接口。
- 应用不提供选区时，尝试发送复制快捷键。没有检测到新复制结果时，不使用旧剪贴板内容。
- 仅在剪贴板未被再次写入时恢复原内容。
- macOS“服务”菜单另提供“加入 Anki Capture”入口。
- 原句是尽力获取；浏览器完整 URL、PDF 页码和扫描件 OCR 尚未实现。可手动补充上下文及来源。
- Edge 已在本机通过真实按键取词和生成预览；Chrome、PDF Expert 的具体页面/文档选区行为仍待实测。扫描 PDF 需先 OCR。

## 开发

见 [调研与选型](docs/research.md)、[架构与验收](docs/architecture.md)、[验证记录](docs/validation.md)。项目内已安装 SwiftUI Expert 和 macOS Development 两个开发 Skill，供 Codex 和 Claude Code 使用。运行产品无需加载 Skill。

## 准备 GitHub 分发

运行 `scripts/package-release.sh` 生成当前架构的 `.app` ZIP 和 SHA-256 校验文件，仅打包应用，不包含本机账号、配置、队列或签名私钥。接收者需要安装官方 CLI、登录自己的账号并配置 AnkiConnect。当前为开发预览版本，公开发行前仍需 Developer ID 签名、Apple 公证及对应架构的构建验证；此脚本不会上传 GitHub 或发布 Release。
