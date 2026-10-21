import SwiftUI
import CaptureCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var term = ""
    @State private var context = ""
    @State private var source = ""
    @State private var preview: CaptureJob?
    @State private var undoJob: CaptureJob?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HSplitView {
            capturePane.frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
            historyPane.frame(minWidth: 420)
        }
        .frame(minWidth: 800, minHeight: 590)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { Task { await model.checkConnections() } } label: { Label("检查连接", systemImage: "arrow.clockwise") }
                    .disabled(model.checking)
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink { Label("设置", systemImage: "gearshape") }
            }
        }
        .sheet(item: $preview) { job in CardPreview(job: job, model: model) }
        .confirmationDialog("撤销这次添加？", isPresented: Binding(get: { undoJob != nil }, set: { if !$0 { undoJob = nil } }), titleVisibility: .visible) {
            if let job = undoJob {
                Button("删除“\(job.input.text)”及其新建卡片", role: .destructive) { Task { await model.undo(job) }; undoJob = nil }
            }
            Button("取消", role: .cancel) { undoJob = nil }
        } message: { Text("仅适用于本工具新建、尚无复习记录的字卡。已有卡片不会被删除。") }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var capturePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "character.book.closed.fill").font(.system(size: 30)).foregroundStyle(.tint)
                    Text("把遇到的词留下来").font(.title2.bold())
                    Text("在阅读器中选词，按快捷键。\n也可以在这里输入单词或短语。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ShortcutRecorder()
                    if !model.permissionGranted {
                        Button("开启辅助功能权限") { SelectionCapture.requestPermission() }
                            .buttonStyle(.bordered)
                        Text("用于读取你主动选择的文本；不持续监视剪贴板。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    TextField("单词或短语，如 salient / in light of", text: $term).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("单词或短语")
                    Text("原句 / 上下文（可选）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $context).font(.body).frame(height: 90)
                        .scrollContentBackground(.hidden).padding(5).background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        .accessibilityLabel("上下文")
                    TextField("来源标题或链接（可选）", text: $source).textFieldStyle(.roundedBorder)
                    Button {
                        do {
                            let input = try CaptureInput(text: term, context: context, source: source, sourceApp: "Manual")
                            Task {
                                if await model.enqueue(input) { term = ""; context = ""; source = "" }
                            }
                        } catch { model.report(error) }
                    } label: { Label(model.configuration.autoSave ? "生成并收录" : "生成预览", systemImage: "plus") .frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.configuration.deck.isEmpty)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.configuration.deck.isEmpty ? "请先选择目标牌组" : model.configuration.deck, systemImage: "rectangle.stack")
                    Text("\(model.configuration.provider.title) · \(model.configuration.model.isEmpty ? "CLI 默认模型" : model.configuration.model)")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.configuration.deck.isEmpty { Button("配置连接与牌组") { openSettings() } }
                }
                if !model.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.diagnostics, id: \.name) { item in
                            Label(item.name + "：" + item.detail, systemImage: item.ok ? "checkmark.circle.fill" : "circle")
                                .font(.caption).foregroundStyle(item.ok ? Color.secondary : Color.orange)
                                .lineLimit(2)
                        }
                    }
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近收录").font(.title2.bold())
                Spacer()
                Text("今天 \(model.savedToday) · 待处理 \(model.pending)").font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            if model.jobs.isEmpty {
                ContentUnavailableView("从一个词开始", systemImage: "text.badge.plus",
                    description: Text("生成结果和处理状态会出现在这里。\nAnki 暂时离线时，任务会留在本机。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(job.input.text).font(.headline).textSelection(.enabled)
                            Spacer()
                            Text(job.status.title).font(.caption).foregroundStyle(statusColor(job.status))
                        }
                        if let card = job.card {
                            Text(card.meaningZh).lineLimit(2)
                            Text(card.definitionEn).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let error = job.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
                        HStack(spacing: 12) {
                            Text(job.deck).lineLimit(1)
                            Text(job.createdAt, style: .relative)
                            Spacer()
                            if job.card != nil { Button(job.status == .review ? "预览并确认" : "查看") { preview = job } }
                            if [.failed, .waitingForAnki].contains(job.status) {
                                Button("重试") { Task { await model.retry(job) } }
                            }
                            if job.noteID != nil { Button("在 Anki 中打开") { Task { await model.openNote(job) } } }
                            if job.status == .saved { Button("撤销添加", role: .destructive) { undoJob = job } }
                        }.font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
                    }.padding(.vertical, 10)
                }.listStyle(.inset)
            }
            Divider()
            Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }
    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .saved: return .green
        case .failed, .waitingForAnki: return .orange
        case .generating, .saving, .queued: return .accentColor
        default: return .secondary
        }
    }
}

private struct CardPreview: View {
    let job: CaptureJob
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var card: VocabularyCard
    init(job: CaptureJob, model: AppModel) {
        self.job = job; self.model = model
        _card = State(initialValue: job.card ?? .init(term: job.input.text, lemma: "", senseKey: "", meaningZh: "", definitionEn: ""))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(card.term).font(.largeTitle.bold())
            Form {
                TextField("中文释义", text: $card.meaningZh)
                TextField("英文解释", text: $card.definitionEn)
                TextField("词性", text: $card.partOfSpeech)
                TextField("发音", text: $card.pronunciation)
                TextField("例句", text: $card.exampleEn)
                TextField("例句翻译", text: $card.exampleZh)
                if !job.input.context.isEmpty { LabeledContent("原句", value: job.input.context) }
                if !job.input.source.isEmpty { LabeledContent("来源", value: job.input.source) }
            }.formStyle(.grouped).disabled(job.status != .review)
            HStack {
                if card.needsReview { Label("词义存在歧义，建议检查。", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                if job.status == .review {
                    Button("确认加入 Anki") { Task { await model.saveReview(job, card: card) }; dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }.padding(24).frame(width: 640, height: 580)
    }
}
