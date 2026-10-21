import SwiftUI
import AppKit

struct AppRootView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppPage?>(get: { model.page }, set: { if let page = $0 { model.page = page } })) {
                ForEach(AppPage.allCases) { page in Label(page.title, systemImage: page.symbol).tag(page) }
            }
            .listStyle(.sidebar)
            .navigationTitle("Anki Capture")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 9) {
                    Label(model.configuration.deck.isEmpty ? "尚未选择牌组" : model.configuration.deck, systemImage: "rectangle.stack")
                        .lineLimit(2)
                    Text("\(model.configuration.provider.title) · \(model.configuration.model.isEmpty ? "默认模型" : model.configuration.model)")
                        .lineLimit(2).foregroundStyle(.secondary)
                }.font(.caption).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch model.page {
                case .capture: MainView(model: model)
                case .connections: ConnectionsView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .navigationTitle(model.page.title)
            .toolbar {
                ToolbarItem {
                    Button { Task { await model.checkConnections() } } label: { Label("刷新连接", systemImage: "arrow.clockwise") }
                        .disabled(model.checking)
                }
            }
        }
        .frame(minWidth: 1020, minHeight: 660)
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task {
            model.openMainWindow = { openWindow(id: "main"); NSApp.activate() }
            model.start()
        }
    }
}
