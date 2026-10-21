import SwiftUI
import AppKit
import CaptureCore

struct ConnectionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接你的 AI").font(.largeTitle.weight(.semibold))
                    Text("使用你自己的账号，让熟悉的模型帮你制卡。")
                        .font(.body).foregroundStyle(.secondary)
                }
                HStack {
                    Text("默认制卡服务").font(.headline)
                    Spacer()
                    Picker("默认制卡服务", selection: Binding(get: { model.configuration.provider }, set: { provider in
                        var config = model.configuration; config.provider = provider; model.saveSettings(config)
                    })) {
                        ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
                VStack(spacing: 0) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        ProviderConnectionView(provider: provider, model: model)
                        if provider != AIProvider.allCases.last { Divider().padding(.horizontal, 24) }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 7) {
                    Label("账号与额度由官方 CLI 管理", systemImage: "lock.shield")
                        .font(.callout.weight(.medium))
                    Text("本应用不接收或保存登录令牌。登录会在终端和官方网页中完成；验证连接会发送一次示例制卡请求，消耗少量所选服务额度，不会写入 Anki。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(32).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProviderConnectionView: View {
    let provider: AIProvider
    let model: AppModel
    // These are intentional editable drafts, committed only to this provider.
    @State private var executable: String
    @State private var selectedModel: String
    @State private var saved = false
    init(provider: AIProvider, model: AppModel) {
        self.provider = provider; self.model = model
        _executable = State(initialValue: model.configuration.executable(for: provider))
        _selectedModel = State(initialValue: model.configuration.model(for: provider))
    }
    private var status: ProviderConnection? { model.connection(for: provider) }
    private var installed: Bool { FileManager.default.isExecutableFile(atPath: executable) }
    private var verifying: Bool { model.verifyingProviders.contains(provider) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Text(provider == .codex ? "C" : provider == .claude ? "A" : "G")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .frame(width: 46, height: 46)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(provider.title).font(.title3.weight(.semibold))
                        if model.configuration.provider == provider { Text("默认制卡").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(status?.detail ?? "正在检查本机 CLI…")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ConnectionBadge(state: status?.state, busy: verifying)
            }
            HStack(spacing: 10) {
                if installed {
                    Button(status?.state == .connected ? "重新登录" : "连接账号") {
                        if persist() { model.login(provider) }
                    }.buttonStyle(.borderedProminent).accessibilityLabel("\(provider.title) 连接账号")
                    Button {
                        guard persist() else { return }
                        Task { await model.verify(provider) }
                    } label: {
                        HStack(spacing: 6) {
                            if verifying { ProgressView().controlSize(.small) }
                            Text(verifying ? "正在验证" : "验证连接")
                        }
                    }.disabled(verifying).accessibilityLabel("\(provider.title) 验证连接")
                } else {
                    Link("安装官方 CLI", destination: provider.installationURL).buttonStyle(.borderedProminent)
                }
                Link("安装说明", destination: provider.installationURL).font(.callout)
                Spacer()
                if let version = status?.version, !version.isEmpty { Text(version).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
            }
            HStack {
                Text("模型").font(.callout).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                Picker("\(provider.title) 模型", selection: $selectedModel) {
                    Text("沿用 CLI 默认模型").tag("")
                    ForEach(Array(Set(provider.modelSuggestions + [selectedModel])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: 220)
                TextField("或输入模型 ID", text: $selectedModel).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(provider.title) 自定义模型 ID")
                Button(saved ? "已保存" : "保存模型") { saved = persist() }.accessibilityLabel("保存 \(provider.title) 模型")
            }
            DisclosureGroup("CLI 位置与登录命令") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("\(provider.commandName) 可执行文件路径", text: $executable).textFieldStyle(.roundedBorder)
                        Button("选择文件…") { selectExecutable() }
                        Button("保存路径") { saved = persist() }
                    }
                    HStack {
                        Text(LoginCommand.display(provider: provider, executable: executable.isEmpty ? provider.commandName : executable))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                        Spacer()
                        Button("复制命令") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(LoginCommand.display(provider: provider,
                                executable: executable.isEmpty ? provider.commandName : executable), forType: .string)
                        }
                    }
                    if provider == .gemini {
                        Text("在终端选择 Sign in with Google。完成后可输入 /quit，再回到这里验证连接。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 10)
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(24)
        .onChange(of: selectedModel) { _, _ in saved = false }
        .onChange(of: executable) { _, _ in saved = false }
    }
    private func persist() -> Bool { model.saveProvider(provider, path: executable, model: selectedModel) }
    private func selectExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择已安装的 \(provider.title) 官方 CLI 可执行文件。"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            executable = url.path
        }
    }
}

struct ConnectionBadge: View {
    let state: ConnectionState?
    var busy = false
    private var color: Color {
        switch state { case .connected: .green; case .failed: .orange; default: .secondary }
    }
    var body: some View {
        Label(busy ? "正在验证" : state?.title ?? "检查中", systemImage: state == .connected ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.08), in: Capsule())
    }
}
