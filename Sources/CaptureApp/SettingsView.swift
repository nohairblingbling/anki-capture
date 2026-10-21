import SwiftUI
import AppKit
import CaptureCore

struct SettingsView: View {
    let model: AppModel
    @State private var draft: AppConfiguration
    @State private var saved = false
    init(model: AppModel) { self.model = model; _draft = State(initialValue: model.configuration) }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("收录到 Anki") {
                    if !model.decks.isEmpty {
                        Picker("目标牌组", selection: $draft.deck) {
                            Text("请选择").tag("")
                            ForEach(Array(Set(model.decks + (draft.deck.isEmpty ? [] : [draft.deck]))).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    } else { TextField("目标牌组名称", text: $draft.deck) }
                    HStack {
                        Button("刷新牌组与连接") { Task { await model.checkConnections() } }.disabled(model.checking)
                        Link("安装 AnkiConnect", destination: URL(string: "https://ankiweb.net/shared/info/2055492159")!)
                    }
                    Text("Anki → 工具 → 插件 → 获取插件 → 2055492159，安装后重启。专用字卡模板在首次写入时创建。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("生成后直接加入牌组", isOn: $draft.autoSave)
                    Text(draft.autoSave ? "后台自动处理，成功后显示提示。" : "生成后先在最近收录中预览、编辑，再确认加入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("本机 AI") {
                    Picker("使用服务", selection: $draft.provider) {
                        ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if draft.provider == .codex {
                        Picker("模型候选", selection: $draft.codexModel) {
                            Text("沿用 CLI 默认模型").tag("")
                            ForEach(Array(Set(ExecutableLocator.codexModels() + [draft.codexModel])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        TextField("自定义模型 ID（留空沿用默认）", text: $draft.codexModel)
                    } else {
                        Picker("模型", selection: $draft.claudeModel) {
                            Text("CLI 默认模型").tag("")
                            ForEach(Array(Set(["sonnet", "opus", "haiku", draft.claudeModel])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        TextField("自定义模型 ID", text: $draft.claudeModel)
                    }
                    Text("沿用官方 CLI 的登录与计费配置。Codex 候选来自本机缓存；模型权限以实际调用为准。")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("制卡说明") { Text("英语词汇 / 短语 → 中文释义与英文例句").foregroundStyle(.secondary) }
                    TextField("额外制卡偏好（可选）", text: $draft.customInstructions, axis: .vertical).lineLimit(2...4)
                }
                Section("快捷键与权限") {
                    ShortcutRecorder()
                    HStack {
                        Label(model.permissionGranted ? "辅助功能已允许" : "辅助功能尚未允许", systemImage: model.permissionGranted ? "checkmark.circle" : "hand.raised")
                        Spacer()
                        Button("打开权限设置") { SelectionCapture.requestPermission() }
                    }
                }
                Section {
                    DisclosureGroup("高级设置") {
                        TextField("Codex 可执行文件", text: $draft.codexPath)
                        TextField("Claude 可执行文件", text: $draft.claudePath)
                        TextField("AnkiConnect 地址", text: $draft.ankiURL)
                        SecureField("AnkiConnect API Key（如有）", text: $draft.ankiAPIKey)
                        TextField("专用笔记类型", text: $draft.noteType)
                        LabeledContent("生成超时") { TextField("秒", value: $draft.timeoutSeconds, format: .number).frame(width: 70); Text("秒") }
                        Button("打开本地数据目录") { NSWorkspace.shared.open(model.paths.root) }
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                if saved { Label("设置已保存", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("保存设置") { model.saveSettings(draft); saved = model.configuration == draft }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
            }.padding(18)
        }
        .frame(minWidth: 600, minHeight: 620)
    }
}
