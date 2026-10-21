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
            PageHeading(title: "学习偏好", subtitle: "让释义和例句适合你，界面语言独立设置。")
                .frame(maxWidth: 736, alignment: .leading)
                .padding(.horizontal, AppStyle.pagePadding).padding(.top, 28).padding(.bottom, 8)
            Form {
                Section("学习偏好") {
                    if !model.configuration.explanationLanguageConfirmed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("你希望用哪种语言理解释义？").font(.headline)
                            Text("确认一次，之后每次收录都会沿用。你可以随时在这里修改。")
                                .font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                    Picker("释义语言", selection: $draft.explanationLanguage) {
                        ForEach(AppLanguage.allCases.filter { $0 != .system }, id: \.self) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    }
                    Text("单独记住你的选择，切换界面语言不会改变释义语言。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.configuration.explanationLanguageConfirmed {
                        Button("确认释义语言") { confirmExplanationLanguage() }
                            .buttonStyle(.borderedProminent)
                    }
                    DisclosureGroup("更多学习偏好（可选）") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("常学语言").font(.callout.weight(.medium))
                            ForEach(StudyLanguage.allCases, id: \.self) { language in
                                Toggle(LocalizedStringKey(language.title), isOn: Binding(
                                    get: { draft.learningPreferences.languages.contains(language) },
                                    set: { if $0 { draft.learningPreferences.languages.insert(language) }
                                        else { draft.learningPreferences.languages.remove(language) } }
                                ))
                            }
                            Text("用于辅助判断，可全部留空。其他语言的词条也能收录。")
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("熟悉程度", selection: $draft.learningPreferences.level) {
                                ForEach(LearningLevel.allCases, id: \.self) { level in
                                    Text(LocalizedStringKey(level.title)).tag(level)
                                }
                            }
                            TextField("额外制卡偏好", text: $draft.customInstructions, axis: .vertical).lineLimit(2...4)
                                .help("例如：优先使用学术语境，例句尽量简短。留空使用默认制卡说明。")
                        }.padding(.vertical, 8)
                    }
                    Text("词条语言自动识别；语言或词义有歧义时，先预览确认再加入 Anki。")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    DeckCreator(model: model, selectedDeck: $draft.deck,
                                connectionIsSaved: draft.ankiURL == model.configuration.ankiURL && draft.ankiAPIKey == model.configuration.ankiAPIKey)
                    Toggle(isOn: $draft.autoSave) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("生成后直接加入牌组")
                            Text(LocalizedStringKey(draft.autoSave ? "识别明确时自动加入；有歧义时仍需预览确认。" : "先在最近收录中预览、编辑，再确认加入。"))
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
                Section("制卡服务") {
                    HStack {
                        LabeledContent("当前服务", value: model.configuration.provider.title)
                        Button("管理 AI 连接") { model.page = .connections; model.openMainWindow?() }
                    }
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
                    .disabled(!hasChanges || !model.configuration.explanationLanguageConfirmed)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .background(AppStyle.canvas)
        .frame(minWidth: 600, minHeight: 620)
        .onChange(of: draft) { _, _ in saved = false }
        .onChange(of: model.configuration) { old, new in
            sync(\.deck, old, new); sync(\.noteType, old, new); sync(\.ankiURL, old, new)
            sync(\.ankiAPIKey, old, new); sync(\.timeoutSeconds, old, new); sync(\.autoSave, old, new)
            sync(\.customInstructions, old, new); sync(\.explanationLanguage, old, new)
            sync(\.learningPreferences, old, new)
        }
    }
    private func sync<Value: Equatable>(_ key: WritableKeyPath<AppConfiguration, Value>, _ old: AppConfiguration, _ new: AppConfiguration) {
        if draft[keyPath: key] == old[keyPath: key] { draft[keyPath: key] = new[keyPath: key] }
    }
    private func confirmExplanationLanguage() {
        var config = model.configuration
        config.explanationLanguage = draft.explanationLanguage
        config.explanationLanguageConfirmed = true
        config.learningPreferences = draft.learningPreferences
        config.customInstructions = draft.customInstructions
        saved = model.saveSettings(config)
    }
    private var mergedSettings: AppConfiguration {
        // Another window may change AI or Dock preferences while this form is open.
        var config = model.configuration
        config.deck = draft.deck; config.noteType = draft.noteType
        config.ankiURL = draft.ankiURL; config.ankiAPIKey = draft.ankiAPIKey
        config.timeoutSeconds = draft.timeoutSeconds; config.autoSave = draft.autoSave
        config.customInstructions = draft.customInstructions
        config.explanationLanguage = draft.explanationLanguage
        config.learningPreferences = draft.learningPreferences
        return config
    }
}

private struct DeckCreator: View {
    let model: AppModel
    @Binding var selectedDeck: String
    let connectionIsSaved: Bool
    @State private var expanded = false
    @State private var name = ""
    @State private var error: String?
    @State private var createdName: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if expanded {
                TextField("新牌组名称", text: $name).textFieldStyle(.roundedBorder)
                    .focused($nameFocused).onSubmit { create() }
                    .disabled(model.creatingDeck)
                    .onExitCommand { if !model.creatingDeck { expanded = false } }
                Text("支持“父牌组::子牌组”。创建并选用后立即保存目标牌组。")
                    .font(.caption).foregroundStyle(.secondary)
                if !connectionIsSaved {
                    Text("请先保存 Anki 连接设置，再创建牌组。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Label { Text(verbatim: error).fixedSize(horizontal: false, vertical: true) }
                        icon: { Image(systemName: "exclamationmark.circle") }
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Button("取消") { expanded = false }.disabled(model.creatingDeck)
                    Button(LocalizedStringKey(model.creatingDeck ? "正在创建…" : "创建并选用")) { create() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.creatingDeck || !connectionIsSaved || (try? AnkiClient.validatedDeckName(name)) == nil)
                }
            } else {
                Button { expanded = true; error = nil; createdName = nil; nameFocused = true } label: {
                    Label("新建牌组…", systemImage: "plus")
                }.disabled(model.creatingDeck)
            }
            if let createdName {
                Label { Text(verbatim: L10n.format("已创建并选用牌组：%@", createdName)) }
                    icon: { Image(systemName: "checkmark.circle") }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
    private func create() {
        guard !model.creatingDeck, connectionIsSaved else { return }
        do {
            let validName = try AnkiClient.validatedDeckName(name)
            error = nil
            Task {
                do {
                    let created = try await model.createDeck(named: validName)
                    selectedDeck = created; createdName = created
                    name = ""; expanded = false
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
}
