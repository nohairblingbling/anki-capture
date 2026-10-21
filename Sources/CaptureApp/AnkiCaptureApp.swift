import SwiftUI
import AppKit
import CaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.openMainWindow?()
        return true
    }
    @objc func captureSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), let model else { error.pointee = "无法获取选中的文本。"; return }
        Task { @MainActor in
            do { await model.enqueue(try CaptureInput(text: text, sourceApp: "macOS Service")) }
            catch { model.report(error) }
        }
    }
}

@main
struct AnkiCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel?
    private let startupError: String?
    init() {
        do { _model = State(initialValue: try AppModel()); startupError = nil }
        catch { _model = State(initialValue: nil); startupError = error.localizedDescription }
    }
    var body: some Scene {
        Window("Anki Capture", id: "main") {
            if let model {
                AppRootView(model: model)
                    .task { delegate.model = model; model.start() }
            } else {
                ContentUnavailableView("无法启动", systemImage: "exclamationmark.triangle", description: Text(startupError ?? "本地数据不可用"))
                    .padding(40)
            }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra {
            if let model { CaptureMenu(model: model) }
            else { Text(startupError ?? "启动失败"); Button("退出") { NSApp.terminate(nil) } }
        } label: {
            Label("Anki Capture", systemImage: model?.pending ?? 0 > 0 ? "text.badge.checkmark" : "character.book.closed")
        }
        Settings {
            if let model { SettingsView(model: model).frame(width: 650, height: 700) }
        }
    }
}

private struct CaptureMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Text(model.configuration.deck.isEmpty ? "尚未选择牌组" : "目标：\(model.configuration.deck)")
        Text("今天添加 \(model.savedToday) · 待处理 \(model.pending)")
        Divider()
        Button("打开收词窗口") { model.page = .capture; openWindow(id: "main"); NSApp.activate() }
        Button("AI 连接…") { model.page = .connections; openWindow(id: "main"); NSApp.activate() }
        Toggle("在 Dock 中显示", isOn: Binding(get: { model.configuration.showInDock }, set: { model.setDockVisibility($0) }))
        Button("设置…") { openSettings(); NSApp.activate() }
        Button("重新检查连接") { Task { await model.checkConnections() } }
        Divider()
        Text(String(model.message.prefix(65)))
        Divider()
        Button("退出 Anki Capture") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
