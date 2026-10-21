import SwiftUI
import Observation
import AppKit
import CaptureCore

enum AppPage: String, CaseIterable, Identifiable {
    case capture, connections, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .capture: "收词"; case .connections: "AI 连接"; case .settings: "偏好设置" }
    }
    var symbol: String {
        switch self { case .capture: "text.badge.plus"; case .connections: "point.3.connected.trianglepath.dotted"; case .settings: "slider.horizontal.3" }
    }
}

@MainActor @Observable
final class AppModel {
    var configuration: AppConfiguration
    var jobs: [CaptureJob] = []
    var decks: [String] = []
    var diagnostics: [DiagnosticItem] = []
    var message = "选中一个单词或短语，按快捷键收词。"
    var error: String?
    var checking = false
    var page: AppPage = .capture
    var connections: [ProviderConnection] = []
    var verifyingProviders: Set<AIProvider> = []
    var openMainWindow: (() -> Void)?
    var permissionGranted = SelectionCapture.isTrusted
    let paths: StoragePaths
    let store: JobStore
    let worker: QueueWorker
    private var started = false
    private var knownStatus: [String: JobStatus] = [:]

    init(storagePaths: StoragePaths? = nil) throws {
        paths = try storagePaths ?? StoragePaths()
        configuration = try AppConfiguration.load(from: paths)
        store = try JobStore(paths: paths)
        worker = QueueWorker(store: store, generator: LocalCLIGenerator(paths: paths))
    }
    var pending: Int { jobs.filter { [.queued, .generating, .ready, .saving, .waitingForAnki].contains($0.status) }.count }
    var savedToday: Int { jobs.filter { $0.status == .saved && Calendar.current.isDateInToday($0.updatedAt) }.count }

    func start() {
        guard !started else { return }
        started = true
        applyDockPreference()
        HotKeyManager.shared.onCapture = { [weak self] in
            Task { @MainActor in await self?.captureSelected() }
        }
        HotKeyManager.shared.register()
        Task { await checkConnections() }
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                permissionGranted = SelectionCapture.isTrusted
                processQueue()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func refresh() async {
        do {
            let current = try await store.list(limit: 100)
            for job in current {
                if let prior = knownStatus[job.id], prior != job.status,
                   [.saved, .duplicate, .failed, .review].contains(job.status) {
                    let text = "\(job.input.text) · \(job.status.title)"
                    message = text
                    CaptureHUD.show(text, isError: job.status == .failed)
                }
            }
            knownStatus = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.status) })
            jobs = current
        } catch { self.error = error.localizedDescription }
    }
    func captureSelected() async {
        do { await enqueue(try await SelectionCapture.capture()) }
        catch { report(error) }
    }
    @discardableResult func enqueue(_ input: CaptureInput) async -> Bool {
        do {
            let job = try await store.enqueue(input, config: configuration.validated())
            message = "\(input.text) · \(job.status.title)"
            CaptureHUD.show(message)
            await refresh()
            processQueue()
            return true
        } catch { report(error); return false }
    }
    func processQueue() {
        let config = configuration
        Task {
            do { try await worker.drain(config: config) }
            catch { report(error) }
        }
    }
    func retry(_ job: CaptureJob) async {
        do { try await store.retry(job.id); await refresh(); processQueue() }
        catch { report(error) }
    }
    func saveReview(_ job: CaptureJob, card: VocabularyCard) async {
        do { try await store.replaceReviewCard(job.id, card: card); await retry(job) }
        catch { report(error) }
    }
    @discardableResult func saveSettings(_ draft: AppConfiguration) -> Bool {
        do {
            try draft.save(to: paths)
            configuration = draft
            applyDockPreference()
            error = nil
            message = "设置已保存。"
            Task { await checkConnections() }
            return true
        } catch { report(error); return false }
    }
    func checkConnections() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        connections = await ProviderConnections.checkAll(config: configuration, paths: paths)
        diagnostics = await Diagnostics.check(config: configuration, paths: paths, connections: connections)
        if let client = try? AnkiClient(config: configuration), let names = try? await client.deckNames() { decks = names }
    }
    func applyDockPreference() {
        let policy: NSApplication.ActivationPolicy = configuration.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
    func setDockVisibility(_ visible: Bool) {
        var config = configuration; config.showInDock = visible; saveSettings(config)
    }
    func connection(for provider: AIProvider) -> ProviderConnection? {
        connections.first { $0.provider == provider }
    }
    @discardableResult func saveProvider(_ provider: AIProvider, path: String, model: String, makeDefault: Bool = false) -> Bool {
        var draft = configuration
        draft.setExecutable(path.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        draft.setModel(model.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        if makeDefault { draft.provider = provider }
        return saveSettings(draft)
    }
    func login(_ provider: AIProvider) {
        do {
            let file = try LoginCommand.write(provider: provider, config: configuration, paths: paths)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: .init()) { _, error in
                guard error != nil else { return }
                try? FileManager.default.removeItem(at: file)
                Task { @MainActor in self.report(CaptureError.process("无法打开终端。可以复制登录命令，在终端中手动执行。")) }
            }
            message = "在终端完成 \(provider.title) 登录后，返回 AI 连接页面刷新。"
        } catch { report(error) }
    }
    func verify(_ provider: AIProvider) async {
        guard !verifyingProviders.contains(provider) else { return }
        verifyingProviders.insert(provider)
        defer { verifyingProviders.remove(provider) }
        let current = configuration
        let value = await ProviderConnections.verify(provider, config: current, paths: paths)
        // A result for a previous model/path must not mark newly edited settings ready.
        guard current.model(for: provider) == configuration.model(for: provider),
              current.executable(for: provider) == configuration.executable(for: provider) else { return }
        connections.removeAll { $0.provider == provider }; connections.append(value)
    }
    func openNote(_ job: CaptureJob) async {
        guard let id = job.noteID else { return }
        do {
            let client = try AnkiClient(config: configuration)
            let _: [Int64] = try await client.call("guiBrowse", params: ["query": "nid:\(id)"])
        } catch { report(error) }
    }
    func undo(_ job: CaptureJob) async {
        do {
            try await AnkiClient(config: configuration).undo(job)
            try await store.finish(job.id, status: .undone)
            await refresh(); message = "已撤销：\(job.input.text)"
        } catch { report(error) }
    }
    func report(_ error: Error) {
        self.error = error.localizedDescription
        message = error.localizedDescription
        CaptureHUD.show(error.localizedDescription, isError: true)
    }
}

@MainActor
enum CaptureHUD {
    private static var panel: NSPanel?
    private static var token = UUID()
    static func show(_ text: String, isError: Bool = false) {
        panel?.orderOut(nil)
        let current = UUID(); token = current
        let view = HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "text.badge.plus")
                .foregroundStyle(isError ? Color.orange : Color.accentColor)
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(3)
        }.padding(16).frame(width: 340, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 372, height: 86), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 396, y: frame.maxY - 110))
        }
        self.panel = panel; panel.orderFrontRegardless()
        Task {
            try? await Task.sleep(for: .seconds(isError ? 5 : 3))
            if token == current { self.panel?.orderOut(nil); self.panel = nil }
        }
    }
}
