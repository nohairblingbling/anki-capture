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
                Section("应用") {
                    Toggle("在 Dock 中显示图标", isOn: Binding(get: { model.configuration.showInDock }, set: { model.setDockVisibility($0) }))
                    Text("立即生效。隐藏 Dock 图标后，仍可从菜单栏打开窗口或设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                Section("制卡偏好") {
                    HStack {
                        LabeledContent("当前服务", value: model.configuration.provider.title)
                        Button("管理 AI 连接") { model.page = .connections; model.openMainWindow?() }
                    }
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
                Button("保存设置") { saved = model.saveSettings(mergedSettings) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
            }.padding(18)
        }
        .frame(minWidth: 600, minHeight: 620)
    }
    private var mergedSettings: AppConfiguration {
        // Settings may be open while another window edits a provider. Commit
        // only the fields this form owns, preserving the latest AI and Dock state.
        var config = model.configuration
        config.deck = draft.deck; config.noteType = draft.noteType
        config.ankiURL = draft.ankiURL; config.ankiAPIKey = draft.ankiAPIKey
        config.timeoutSeconds = draft.timeoutSeconds; config.autoSave = draft.autoSave
        config.customInstructions = draft.customInstructions
        return config
    }
}
