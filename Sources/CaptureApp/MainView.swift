import SwiftUI
import CaptureCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var term = ""
    @State private var context = ""
    @State private var source = ""
    @State private var preview: CaptureJob?
    @State private var undoJob: CaptureJob?
    @State private var submitting = false
    @FocusState private var termFocused: Bool

    var body: some View {
        HSplitView {
            capturePane.frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
            historyPane.frame(minWidth: 420)
        }
        .frame(minWidth: 760, minHeight: 590)
        .sheet(item: $preview) { job in CardPreview(job: job, model: model) }
        .confirmationDialog("撤销这次添加？", isPresented: Binding(get: { undoJob != nil }, set: { if !$0 { undoJob = nil } }), titleVisibility: .visible) {
            if let job = undoJob {
                Button(L10n.format("删除“%@”及其新建卡片", job.input.text), role: .destructive) { Task { await model.undo(job) }; undoJob = nil }
            }
            Button("取消", role: .cancel) { undoJob = nil }
        } message: { Text("仅适用于本工具新建、尚无复习记录的字卡。已有卡片不会被删除。") }
    }
    private var capturePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionGap) {
                PageHeading(title: "留下一个新词", subtitle: "阅读时选词，按快捷键收录。\n也可以在这里输入。")
                if !model.configuration.explanationLanguageConfirmed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请先确认释义语言，再开始收录。").font(.callout)
                        Button("打开学习偏好") { model.page = .settings }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("选词收录", systemImage: "keyboard").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        ShortcutRecorder(showsLabel: false)
                    }
                    if !model.permissionGranted {
                        Button("开启辅助功能权限") { SelectionCapture.requestPermission() }
                        Text("允许读取你主动选择的文本。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldCaption(title: "单词或短语")
                        TextField("salient / in light of", text: $term).textFieldStyle(.roundedBorder)
                            .controlSize(.large).accessibilityLabel("单词或短语")
                            .focused($termFocused)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldCaption(title: "原句或上下文", optional: true)
                        TextEditor(text: $context).font(.body).frame(height: 88)
                            .scrollContentBackground(.hidden).padding(8)
                            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                            .accessibilityLabel("原句或上下文，可选")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldCaption(title: "来源", optional: true)
                        TextField("标题或链接", text: $source).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("来源标题或链接，可选")
                    }
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if submitting { ProgressView().controlSize(.mini) }
                            Text(LocalizedStringKey(submitting ? "正在收录" : model.configuration.autoSave ? "生成并收录" : "生成预览"))
                            Spacer()
                            Text("⌘↩").font(.caption).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(submitting || !model.configuration.explanationLanguageConfirmed || term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.configuration.deck.isEmpty)
                    .help("生成字卡并按当前收录偏好处理，Command-Return")
                    Text(LocalizedStringKey(model.configuration.autoSave ? "识别明确时自动加入；有歧义时仍需预览确认。" : "生成后可先预览、编辑，再确认加入。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                captureStatus
            }.padding(24)
        }
        .background(AppStyle.canvas)
        .defaultFocus($termFocused, true)
    }
    private var captureStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.configuration.deck.isEmpty {
                Button("选择目标牌组") { model.page = .settings }
            }
            ForEach(model.diagnostics.filter { $0.name == "AnkiConnect" || $0.name == model.configuration.provider.title + " 登录" }, id: \.name) { item in
                StatusLabel(title: item.name == "AnkiConnect" ? (item.ok ? "Anki 已连接" : "Anki 尚未连接") : (item.ok ? L10n.format("%@ 已连接", model.configuration.provider.title) : L10n.format("%@ 需要连接", model.configuration.provider.title)),
                            symbol: item.ok ? "checkmark.circle" : "exclamationmark.circle", color: item.ok ? .secondary : .orange)
                    .help(Text(LocalizedStringKey(item.detail)))
            }
            if model.diagnostics.contains(where: { !$0.ok && $0.name == model.configuration.provider.title + " 登录" }) {
                Button("管理 AI 连接") { model.page = .connections }.font(.caption)
            }
        }
    }
    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近收录").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(L10n.format("今天 %lld · 待处理 %lld", model.savedToday, model.pending))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            if model.jobs.isEmpty {
                ContentUnavailableView("从一个词开始", systemImage: "text.badge.plus",
                    description: Text("输入单词，或在阅读器中选词并按快捷键。\n生成结果与收录状态会出现在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.jobs) { job in
                            CaptureHistoryRow(job: job, preview: { preview = job },
                                retry: { Task { await model.retry(job) } },
                                openNote: { Task { await model.openNote(job) } }, undo: { undoJob = job })
                            Divider().accessibilityHidden(true)
                        }
                    }.padding(.horizontal, 24)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tray").accessibilityHidden(true)
                Text(LocalizedStringKey(model.message)).lineLimit(2)
            }.font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppStyle.surface)
    }
    private func submit() {
        guard !submitting else { return }
        do {
            let input = try CaptureInput(text: term, context: context, source: source, sourceApp: "Manual")
            submitting = true
            Task {
                if await model.enqueue(input) { term = ""; context = ""; source = ""; termFocused = true }
                submitting = false
            }
        } catch { model.report(error) }
    }
}

private struct CaptureHistoryRow: View {
    let job: CaptureJob
    let preview: () -> Void
    let retry: () -> Void
    let openNote: () -> Void
    let undo: () -> Void
    private var statusColor: Color {
        switch job.status {
        case .saved: .green
        case .failed, .waitingForAnki: .orange
        case .generating, .saving, .queued: .accentColor
        default: .secondary
        }
    }
    private var statusSymbol: String {
        switch job.status {
        case .saved: "checkmark.circle"
        case .failed, .waitingForAnki: "exclamationmark.circle"
        case .review: "eye"
        case .generating, .saving, .queued, .ready: "clock"
        default: "circle"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.input.text).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                    Spacer(minLength: 12)
                    StatusLabel(title: job.status.title, symbol: statusSymbol, color: statusColor)
                }
                if let card = job.card {
                    Text(card.meaningZh).font(.body).lineLimit(2)
                    Text(card.definitionEn).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                if let error = job.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            }.accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Text(job.deck).lineLimit(1)
                Text("·").accessibilityHidden(true)
                Text(job.createdAt, style: .relative)
                Spacer()
                if job.card != nil {
                    Button(LocalizedStringKey(job.status == .review ? "预览并确认" : "查看字卡"), action: preview)
                        .accessibilityLabel(Text(verbatim: job.input.text + ", " + L10n.text(job.status == .review ? "预览并确认" : "查看字卡")))
                }
            }.font(.caption).foregroundStyle(.secondary)
            if [.failed, .waitingForAnki].contains(job.status) || job.noteID != nil || job.status == .saved {
                HStack(spacing: 16) {
                    if [.failed, .waitingForAnki].contains(job.status) { Button("重试", action: retry) }
                    if job.noteID != nil { Button("在 Anki 中打开", action: openNote) }
                    Spacer()
                    if job.status == .saved { Button("撤销添加", role: .destructive, action: undo) }
                }.font(.caption)
            }
        }
        .buttonStyle(.borderless).padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }
}

struct CardPreview: View {
    let job: CaptureJob
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var card: VocabularyCard
    @State private var saving = false
    init(job: CaptureJob, model: AppModel) {
        self.job = job; self.model = model
        _card = State(initialValue: job.card ?? .init(term: job.input.text, lemma: "", senseKey: "", meaningZh: "", definitionEn: ""))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.term).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                Label(job.deck, systemImage: "rectangle.stack").font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Form {
                if card.needsReview {
                    Section("需要确认") {
                        Label { Text(verbatim: reviewReason).fixedSize(horizontal: false, vertical: true) }
                            icon: { Image(systemName: "info.circle") }
                        Text("检查语言、释义和例句；可直接修改后确认。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let language = card.sourceLanguage, !language.isEmpty {
                    Section("词条语言") {
                        LabeledContent("自动识别") {
                            Text(verbatim: model.configuration.interfaceLanguage.locale.localizedString(forIdentifier: language) ?? language)
                        }
                    }
                }
                Section("释义") {
                    cardField("释义", text: $card.meaningZh)
                    cardField("定义", text: $card.definitionEn)
                    cardField("词性", text: $card.partOfSpeech)
                    cardField("发音", text: $card.pronunciation)
                }
                Section("例句") {
                    cardField("例句", text: $card.exampleEn)
                    cardField("例句翻译", text: $card.exampleZh)
                }
                if !job.input.context.isEmpty || !job.input.source.isEmpty {
                    Section("阅读来源") {
                        if !job.input.context.isEmpty { LabeledContent("原句", value: job.input.context).textSelection(.enabled) }
                        if !job.input.source.isEmpty { LabeledContent("来源", value: job.input.source).textSelection(.enabled) }
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).disabled(saving)
            Divider()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                if job.status == .review {
                    Button(LocalizedStringKey(saving ? "正在保存…" : "确认加入 Anki")) {
                        saving = true
                        Task {
                            if await model.saveReview(job, card: card) { dismiss() }
                            saving = false
                        }
                    }.buttonStyle(.borderedProminent).disabled(saving)
                }
            }.padding(20)
        }.frame(width: 650, height: 680).background(AppStyle.canvas)
            .interactiveDismissDisabled(saving)
    }
    private var reviewReason: String {
        if let reason = card.reviewReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return reason }
        return L10n.text("词义可能存在歧义，请检查。")
    }
    @ViewBuilder private func cardField(_ title: String, text: Binding<String>) -> some View {
        if job.status == .review {
            TextField(LocalizedStringKey(title), text: text, axis: .vertical).lineLimit(1...4)
        } else {
            LabeledContent(LocalizedStringKey(title)) { Text(text.wrappedValue).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(LocalizedStringKey(title))).accessibilityValue(text.wrappedValue)
        }
    }
}
