import SwiftUI
import AppKit
import CaptureCore

struct ConnectionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionGap) {
                PageHeading(title: "AI 连接", subtitle: "连接自己的账号，选择熟悉的模型。")
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("默认制卡服务").font(.headline)
                        Text("用于之后收录的词汇").font(.caption).foregroundStyle(.secondary)
                    }
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
                        if provider != AIProvider.allCases.last { Divider().padding(.horizontal, 20) }
                    }
                }
                .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("账号与额度由官方 CLI 管理").font(.callout.weight(.medium))
                        Text("登录在终端和官方网页完成，本应用不保存登录令牌。验证会消耗少量所选服务额度，不会写入 Anki。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(AppStyle.pagePadding).frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(AppStyle.canvas)
    }
}

private struct ProviderConnectionView: View {
    let provider: AIProvider
    let model: AppModel
    // Editable drafts are intentionally committed only to this provider.
    @State private var executable: String
    @State private var selectedModel: String
    @State private var expanded = false
    @State private var advanced = false
    @State private var saved = false
    init(provider: AIProvider, model: AppModel) {
        self.provider = provider; self.model = model
        _executable = State(initialValue: model.configuration.executable(for: provider))
        _selectedModel = State(initialValue: model.configuration.model(for: provider))
    }
    private var status: ProviderConnection? { model.connection(for: provider) }
    private var installed: Bool { FileManager.default.isExecutableFile(atPath: executable) }
    private var verifying: Bool { model.verifyingProviders.contains(provider) }
    private var modelOptions: [String] {
        Array(Set(provider.modelSuggestions + [selectedModel])).filter { !$0.isEmpty }.sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: provider == .codex ? "terminal" : provider == .claude ? "asterisk" : "sparkle")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(provider.title).font(.headline)
                        if model.configuration.provider == provider {
                            Text("默认").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        ConnectionBadge(state: status?.state, busy: verifying)
                    }
                    Text(status?.detail ?? "正在检查本机 CLI…")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if installed {
                    if status?.state == .connected {
                        Button("重新登录") { login() }
                            .accessibilityLabel("\(provider.title) 连接账号")
                    } else {
                        Button("连接账号") { login() }.buttonStyle(.borderedProminent)
                            .accessibilityLabel("\(provider.title) 连接账号")
                    }
                    Button { verify() } label: {
                        HStack(spacing: 6) {
                            if verifying { ProgressView().controlSize(.mini) }
                            Text(verifying ? "正在验证" : "验证连接")
                        }
                    }.disabled(verifying).accessibilityLabel("\(provider.title) 验证连接")
                } else {
                    Link("安装官方 CLI", destination: provider.installationURL).buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 8)
                Button { expanded.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("模型与连接设置")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless).font(.caption)
                .accessibilityLabel("\(provider.title) 模型与连接设置")
                .accessibilityValue(expanded ? "已展开" : "已折叠")
            }.padding(.leading, 48)
            if expanded { configurationEditor.padding(.top, 4) }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .onChange(of: selectedModel) { _, _ in saved = false }
        .onChange(of: executable) { _, _ in saved = false }
    }
    private var configurationEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                FieldCaption(title: "制卡模型")
                HStack(spacing: 10) {
                    Picker("\(provider.title) 模型", selection: $selectedModel) {
                        Text("沿用 CLI 默认模型").tag("")
                        ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 250)
                    Spacer()
                    Button(saved ? "已保存" : "保存配置") { saved = persist() }
                        .disabled(saved).accessibilityLabel("保存 \(provider.title) 配置")
                }
                TextField("自定义模型 ID，留空使用 CLI 默认值", text: $selectedModel)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("\(provider.title) 自定义模型 ID")
            }
            DisclosureGroup("CLI 路径与登录命令", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("\(provider.commandName) 可执行文件路径", text: $executable).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(provider.title) CLI 路径")
                        Button("选择文件…") { selectExecutable() }
                    }
                    HStack(alignment: .top) {
                        Text(LoginCommand.display(provider: provider, executable: executable.isEmpty ? provider.commandName : executable))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("复制命令") { copyLoginCommand() }
                    }
                    if provider == .gemini {
                        Text("在终端选择 Sign in with Google。完成后输入 /quit，返回这里验证连接。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            }.font(.callout)
            HStack {
                Link("官方安装说明", destination: provider.installationURL)
                Spacer()
                if let version = status?.version, !version.isEmpty {
                    Text(version).foregroundStyle(.secondary).lineLimit(1).help(version)
                }
            }.font(.caption)
        }
    }
    private func login() { if persist() { model.login(provider) } }
    private func verify() { if persist() { Task { await model.verify(provider) } } }
    private func persist() -> Bool { model.saveProvider(provider, path: executable, model: selectedModel) }
    private func copyLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(LoginCommand.display(provider: provider,
            executable: executable.isEmpty ? provider.commandName : executable), forType: .string)
    }
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
        StatusLabel(title: busy ? "正在验证" : state?.title ?? "检查中",
                    symbol: state == .connected ? "checkmark.circle.fill" : "circle", color: color)
    }
}
