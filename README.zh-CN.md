<div align="center">

# Anki Capture

**继续阅读，把遇到的词留进 Anki。**

原生 Mac 应用与 CLI，直接调用你自己的 **Codex · Claude Code · Gemini CLI**。

[English](README.md) · [简体中文](README.zh-CN.md)

[下载预览版](https://github.com/nohairblingbling/anki-capture/releases) · [开始使用](#开始使用) · [反馈问题](https://github.com/nohairblingbling/anki-capture/issues)

![macOS](https://img.shields.io/badge/macOS-14%2B-333333?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-56846A)

</div>

![收词界面，使用示例数据](docs/images/capture-zh-CN.png)

在论文、网页或 PDF 阅读器里选中一个词，按 **⌃⌥⌘A**，应用会在后台生成字卡，识别明确时加入预选牌组；语言或词义不确定时等待预览确认。也可以手动输入。

## 它能做什么

- **少打断阅读。** 自定义全局快捷键，常驻菜单栏，Dock 图标可以显示或隐藏。
- **沿用自己的 AI 账号。** Codex、Claude Code、Gemini 分别登录，模型可选，也能填写自定义 ID；不需要共享账号或另建后台。
- **三种界面语言。** 英文、简体中文、日文，默认跟随系统，也能随时手动切换，立即生效。
- **适合自己的学习偏好。** 首次确认中、英或日文释义，独立记住，不随界面切换。可选常学语言、熟悉程度和额外制卡偏好；日语发音可以使用假名。
- **任务不会轻易丢失。** 先保存到本地队列；Anki 离线时保留生成结果，重试复用已有内容，并检查重复笔记。
- **收录可控。** 有歧义的字卡即使开启自动收录也须先预览确认。支持编辑、在 Anki 中打开，以及撤销本工具新建且尚未复习的卡片。

以单词和短语为主，也能记录“机会成本”这样的简短概念。界面语言不会限制词条语言：中文界面可以学日语，英文界面也可以收录中文词汇。

## 开始使用

### 1. 安装应用

从 [Releases](https://github.com/nohairblingbling/anki-capture/releases) 下载 Apple Silicon 的 **macOS 预览版 ZIP**，解压后将 **Anki Capture.app** 放到 `~/Applications`。

需要 **macOS 14+**、Anki 桌面版，以及至少一种已安装的官方 AI CLI。当前二进制为 **arm64**；Intel 版本尚未验证。

> 当前为开发预览版，**尚未经过 Apple 公证**。如果 macOS 阻止运行下载的版本，建议从源码构建并使用自己的签名身份，不要关闭系统安全保护。

### 2. 连接 AI 账号

打开 **AI 连接**，选择服务并点击“连接账号”。在终端和官方网页完成自己的登录，再回到应用刷新或验证。

| 服务 | 官方安装说明 | 登录方式 |
| --- | --- | --- |
| Codex | [安装](https://developers.openai.com/codex/cli) | `codex login` |
| Claude Code | [安装](https://code.claude.com/docs/en/setup) | `claude auth login` |
| Gemini CLI | [安装](https://geminicli.com/docs/get-started/installation/) | 运行 `gemini`，选择 **Sign in with Google**，完成后输入 `/quit` |

展开各服务的“模型与连接设置”，可选择模型、填写自定义模型 ID 或选择 CLI 文件位置。“验证连接”会发送一次小型制卡请求、消耗少量额度，**不会写入 Anki**。Gemini 没有独立的官方登录状态命令，因此需要主动验证。

### 3. 连接 Anki 牌组

在 Anki 中打开 **工具 → 插件 → 获取插件**，输入 **`2055492159`**（[AnkiConnect](https://ankiweb.net/shared/info/2055492159)），安装后 **重启 Anki**。

在 Anki Capture 的 **偏好设置 → 收录到 Anki → Anki 连接与安装帮助** 中刷新牌组，选择已有牌组并保存。收录时保持 Anki 打开；专用笔记类型会在首次写卡时自动创建。

### 4. 设置语言，开始收词

首次打开时，**偏好设置 → 学习偏好** 会询问“你希望用哪种语言理解释义？”，确认后即可收录。初始选择只是建议，不据此推断母语。确认结果独立保存：日文界面也可以一直使用中文释义。**偏好设置 → 语言** 控制界面语言，立即生效，也可以跟随系统。

展开“更多学习偏好（可选）”，可选择常学语言、熟悉程度，或填写额外制卡要求。可全部留空、使用自动适配；常学语言仅作辅助，不限制收录其他语言。后续修改按 **⌘S** 保存。

每次收词会结合词条和原句自动识别语言。AI 提示不确定、无法确定语言，或缺少上下文的简短纯汉字词，都会进入“预览并确认”，即使开启了自动收录。预览会显示原因和识别语言；检查、编辑释义和例句后，再确认加入。提供原句可以减少歧义。自动识别仍可能出错，如希望逐条检查，可关闭自动收录。

![首次确认释义语言，使用示例设置](docs/images/learning-zh-CN.png)

按提示为 Anki Capture 开启 **辅助功能** 权限。在阅读器选词，按 **Control + Option + Command + A** 即可。快捷键可以在设置中修改。

**Edge 已在开发机通过真实全局快捷键验证。Chrome、PDF Expert 是预期支持的取词目标，具体页面和文档仍需更多实测；扫描版 PDF 需要先 OCR。**

## 常用快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⌥⌘A` | 全局收录选区，可自定义 |
| `⌘1` / `⌘2` / `⌘3` | 收词 / AI 连接 / 偏好设置 |
| `⌘↩` | 提交手动收词 |
| `⌘S` | 保存设置 |
| `Esc` | 关闭字卡预览 |

界面跟随系统明暗，保留原生焦点样式，状态和按钮提供辅助功能语义，没有自定义装饰动画。完整 VoiceOver 人工朗读验收仍待完成。

<details>
<summary>查看日文连接页</summary>

![日文界面，使用示例连接状态](docs/images/connections-ja.png)

</details>

## CLI 用法

应用内置 `Contents/MacOS/anki-capture`。从源码构建并运行 `scripts/install.sh` 后，也会将 CLI 链接到 `~/.local/bin`。

```bash
anki-capture doctor
anki-capture connections
anki-capture configure --deck '阅读生词' --provider codex
anki-capture configure --language system --explanation-language zh-Hans
anki-capture configure --study-languages en,ja --learning-level intermediate
anki-capture configure --provider gemini --model flash
anki-capture generate '折り合い' --context '互いに歩み寄って、折り合いをつけた。'
anki-capture add 'in light of' --preview
anki-capture jobs
anki-capture retry JOB_ID
anki-capture run --watch
```

首次 `generate` 或 `add` 前，需要用 `--explanation-language en`、`zh-Hans` 或 `ja` 确认释义语言；`system` 仅用于界面。`generate` 仅输出 JSON，包含 `source_language`、`needs_review` 和 `review_reason`。`add --preview` 始终等待确认；自动模式遇到歧义也会等待。通过 `jobs` 检查内容后，`retry JOB_ID` 表示明确确认待预览字卡。`add --queue-only` 只入队。数据命令可用 `--data-dir PATH` 指定独立目录。更多选项见 `--help`。

## 数据与隐私

- 配置和队列位于 `~/Library/Application Support/AnkiCapture/`。发布包不包含个人配置、队列或登录令牌。
- 所选词条、上下文和来源会通过官方 CLI 发送到其配置的模型服务。推理通常在云端进行。
- 认证、额度、订阅和计费沿用各家 CLI 配置。订阅权限由账号决定；API Key 可能产生独立费用。
- 只在触发收词时读取选区，必要时发送复制快捷键；安全时恢复剪贴板，不持续监视剪贴板。
- AI 子进程不开放工具调用；内容写入 Anki 前转义 HTML，AnkiConnect 只允许本机 HTTP 地址。

切换语言不会翻译已有字卡。新任务保存捕获时的释义语言和学习偏好；升级时保留已经明确选择的释义语言，旧的“与界面一致”设置需要确认一次独立语言。0.3 之前的排队任务继续使用原来的中文释义行为。`meaning_zh`、`example_en` 等 JSON 字段名因兼容性保留，**不限制实际内容语言**。确认结果与编辑内容可在 Anki 离线或应用重启后保留，无需再次生成。

## 从源码构建

需要 **Xcode 16+ / Swift 6**；SQLite 使用系统版本。

```bash
git clone https://github.com/nohairblingbling/anki-capture.git
cd anki-capture
swift test
python3 scripts/check-localizations.py
scripts/build-app.sh
scripts/install.sh
```

为了在重建后保留辅助功能授权，可将本机签名身份写入 Git 忽略的 `.signing-identity`，或设置 `ANKI_CAPTURE_SIGNING_IDENTITY`。否则使用 ad-hoc 签名，重建后可能需要重新授权。

翻译源文件是 `App/Translations.json`，修改后运行 `python3 scripts/check-localizations.py --write`。检查器会验证翻译覆盖和格式参数。`scripts/render-ui.sh` 可生成三种语言、系统明暗及窄窗口的隔离示例预览，不连接 AI 或 Anki。README 截图均使用示例数据。

- [架构说明](docs/architecture.md) · [验证记录](docs/validation.md) · [账号连接](docs/connections.md)
- [产品原则](PRODUCT.md) · [设计约定](DESIGN.md)
- [分享渠道与发布文案草稿](docs/sharing.md)

欢迎提交问题、翻译修正和不同阅读器的测试反馈。如果它对你有帮助，也欢迎点一个 Star，让更多人发现它。

## 许可证

[MIT](LICENSE)。本项目独立开发，并非 Anki、OpenAI、Anthropic 或 Google 的官方应用。
