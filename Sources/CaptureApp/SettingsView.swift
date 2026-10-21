import SwiftUI
import AppKit
import CaptureCore

struct SettingsView: View {
    let model: AppModel
    // The form owns an editable snapshot; saves merge only its fields.
    @State private var draft: AppConfiguration
    @State private var saved = false
    init(model: AppModel) { self.model = model; _draft = State(initialValue: model.configuration) }
    private var hasChanges: Bool { mergedSettings != model.configuration }
    var body: some View {
        VStack(spacing: 0) {
            PageHeading(title: "偏好设置", subtitle: "让收词适合你的阅读习惯。")
                .frame(maxWidth: 736, alignment: .leading)
                .padding(.horizontal, AppStyle.pagePadding).padding(.top, 28).padding(.bottom, 8)
            Form {
                Section("语言") {
                    Picker("界面语言", selection: Binding(get: { model.configuration.interfaceLanguage }, set: { language in
                        var config = model.configuration; config.interfaceLanguage = language; model.saveSettings(config)
                    })) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(LocalizedStringKey(language.nativeName)).tag(language)
                        }
                    }
                    Text("立即生效，也可以随时改回跟随系统。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("应用") {
                    Toggle(isOn: Binding(get: { model.configuration.showInDock }, set: { model.setDockVisibility($0) })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("在 Dock 中显示图标")
                            Text("立即生效。隐藏后仍可从菜单栏打开窗口。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityLabel("在 Dock 中显示图标")
                        .accessibilityHint("立即生效，隐藏后可从菜单栏打开窗口。")
                }
                Section("收录到 Anki") {
                    if !model.decks.isEmpty {
                        Picker("目标牌组", selection: $draft.deck) {
                            Text("请选择").tag("")
                            ForEach(Array(Set(model.decks + (draft.deck.isEmpty ? [] : [draft.deck]))).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    } else { TextField("目标牌组名称", text: $draft.deck) }
                    Toggle(isOn: $draft.autoSave) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("生成后直接加入牌组")
                            Text(LocalizedStringKey(draft.autoSave ? "后台完成制卡与收录，成功后显示提示。" : "先在最近收录中预览、编辑，再确认加入。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityLabel("生成后直接加入牌组")
                        .accessibilityHint("关闭后，生成的字卡需要先预览确认。")
                    DisclosureGroup("Anki 连接与安装帮助") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button(LocalizedStringKey(model.checking ? "正在检查…" : "刷新牌组与连接")) { Task { await model.checkConnections() } }
                                    .disabled(model.checking)
                                Link("安装 AnkiConnect", destination: URL(string: "https://ankiweb.net/shared/info/2055492159")!)
                            }
                            Text("Anki → 工具 → 插件 → 获取插件，输入 2055492159，安装后重启 Anki。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                Section("制卡偏好") {
                    Picker("释义语言", selection: $draft.explanationLanguage) {
                        Text("与界面一致").tag(AppLanguage.system)
                        ForEach(AppLanguage.allCases.filter { $0 != .system }, id: \.self) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    }
                    HStack {
                        LabeledContent("当前服务", value: model.configuration.provider.title)
                        Button("管理 AI 连接") { model.page = .connections; model.openMainWindow?() }
                    }
                    TextField("额外制卡偏好", text: $draft.customInstructions, axis: .vertical).lineLimit(2...4)
                        .help("例如：优先使用学术语境，例句尽量简短。留空使用默认制卡说明。")
                    Text("自动识别词条语言，按所选语言生成释义。支持单词、短语和简短概念。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("快捷键与权限") {
                    ShortcutRecorder()
                    HStack {
                        StatusLabel(title: model.permissionGranted ? "辅助功能已允许" : "辅助功能尚未允许",
                                    symbol: model.permissionGranted ? "checkmark.circle" : "hand.raised")
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
            }.formStyle(.grouped).scrollContentBackground(.hidden)
                .frame(maxWidth: 800).frame(maxWidth: .infinity)
            Divider()
            HStack {
                if hasChanges {
                    Text("有尚未保存的更改").font(.caption).foregroundStyle(.secondary)
                } else if saved {
                    StatusLabel(title: "设置已保存", symbol: "checkmark.circle")
                }
                Spacer()
                Button("保存设置") { saved = model.saveSettings(mergedSettings) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasChanges)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .background(AppStyle.canvas)
        .frame(minWidth: 600, minHeight: 620)
        .onChange(of: draft) { _, _ in saved = false }
    }
    private var mergedSettings: AppConfiguration {
        // Another window may change AI or Dock preferences while this form is open.
        var config = model.configuration
        config.deck = draft.deck; config.noteType = draft.noteType
        config.ankiURL = draft.ankiURL; config.ankiAPIKey = draft.ankiAPIKey
        config.timeoutSeconds = draft.timeoutSeconds; config.autoSave = draft.autoSave
        config.customInstructions = draft.customInstructions
        config.explanationLanguage = draft.explanationLanguage
        return config
    }
}
