import Foundation

public enum ConnectionState: String, Codable, Sendable {
    case missing, signedOut, connected, needsVerification, failed
    public var title: String {
        switch self {
        case .missing: "尚未安装"
        case .signedOut: "尚未登录"
        case .connected: "已连接"
        case .needsVerification: "等待验证"
        case .failed: "连接异常"
        }
    }
}

public struct ProviderConnection: Codable, Identifiable, Sendable {
    public var id: AIProvider { provider }
    public let provider: AIProvider
    public let state: ConnectionState
    public let version: String
    public let detail: String
    public init(provider: AIProvider, state: ConnectionState, version: String = "", detail: String) {
        self.provider = provider; self.state = state; self.version = version; self.detail = detail
    }
}

public enum ProviderConnections {
    public static func checkAll(config: AppConfiguration, paths: StoragePaths) async -> [ProviderConnection] {
        await withTaskGroup(of: ProviderConnection.self) { group in
            for provider in AIProvider.allCases {
                group.addTask { await check(provider, config: config, paths: paths) }
            }
            var values: [ProviderConnection] = []
            for await value in group { values.append(value) }
            return AIProvider.allCases.compactMap { provider in values.first { $0.provider == provider } }
        }
    }

    public static func check(_ provider: AIProvider, config: AppConfiguration, paths: StoragePaths) async -> ProviderConnection {
        let executable = config.executable(for: provider)
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .init(provider: provider, state: .missing, detail: "先安装官方 CLI，或选择它在本机的位置。")
        }
        do {
            let version = try await ProcessRunner.run(executable: executable, arguments: ["--version"], directory: paths.runtime, timeout: 12)
            guard version.exitCode == 0 else {
                return .init(provider: provider, state: .failed, detail: "CLI 无法启动，请检查版本及可执行文件路径。")
            }
            let label = String(version.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
            if provider == .gemini {
                // Gemini has no equivalent of `auth status`. Never read its token
                // cache, or turn an installed binary into an authenticated badge.
                return .init(provider: provider, state: .needsVerification, version: label,
                             detail: "在官方 CLI 完成 Google 登录后，点击验证连接。")
            }
            let args = provider == .codex ? ["login", "status"] : ["auth", "status"]
            let auth = try await ProcessRunner.run(executable: executable, arguments: args, directory: paths.runtime, timeout: 12)
            return parseAuthentication(provider: provider, version: label, result: auth)
        } catch {
            return .init(provider: provider, state: .failed, detail: "CLI 检查失败，请确认路径、版本和终端运行环境。")
        }
    }

    public static func parseAuthentication(provider: AIProvider, version: String, result: ProcessResult) -> ProviderConnection {
        var state: ConnectionState = .signedOut
        var detail = "在官方 CLI 中登录你的账号。"
        if provider == .codex, result.exitCode == 0 {
            state = .connected
            let text = (result.stdout + result.stderr).lowercased()
            if text.contains("chatgpt") { detail = "已沿用本机 ChatGPT 登录。" }
            else if text.contains("api key") { detail = "沿用 CLI 的 API Key，按其配置计费。" }
            else { detail = "已沿用本机 CLI 登录与计费配置。" }
        } else if provider == .claude, result.exitCode == 0,
                  let object = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
                  object["loggedIn"] as? Bool == true {
            state = .connected
            let method = object["authMethod"] as? String ?? ""
            detail = ["claude.ai", "oauth_token"].contains(method)
                ? "已沿用本机 Claude 账号登录。" : "已沿用 CLI 的认证与计费配置。"
        }
        return .init(provider: provider, state: state, version: version, detail: detail)
    }

    public static func verify(_ provider: AIProvider, config: AppConfiguration, paths: StoragePaths) async -> ProviderConnection {
        do {
            _ = try await LocalCLIGenerator(paths: paths).generate(
                input: CaptureInput(text: "hello", context: "Hello, nice to meet you.", sourceApp: "Connection check"),
                provider: provider, model: config.model(for: provider), config: config)
            return .init(provider: provider, state: .connected,
                         detail: "当前模型已成功返回字卡。验证不会向 Anki 写入内容。")
        } catch { return verificationFailure(error, provider: provider) }
    }
    static func verificationFailure(_ error: Error, provider: AIProvider) -> ProviderConnection {
        if case CaptureError.authentication = error {
            return .init(provider: provider, state: .signedOut, detail: "尚未完成账号登录。点击连接账号，在官方 CLI 中登录后再验证。")
        }
        return .init(provider: provider, state: .failed, detail: error.localizedDescription)
    }
}

public enum LoginCommand {
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func display(provider: AIProvider, executable: String) -> String {
        ([executable] + provider.loginArguments).map(shellQuoted).joined(separator: " ")
    }
    public static func script(provider: AIProvider, executable: String) -> String {
        """
        #!/bin/zsh
        export PATH=\(shellQuoted(URL(fileURLWithPath: executable).deletingLastPathComponent().path)):"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd "$HOME"
        print -r -- 'Anki Capture · \(provider.title)'
        print -r -- \(shellQuoted(L10n.text("请在官方 CLI 中完成登录，然后返回应用刷新连接。")))
        \(display(provider: provider, executable: executable))
        TASK_LOGIN_STATUS=$?
        print -r -- ''
        print -r -- \(shellQuoted(L10n.text("登录流程已结束。返回 Anki Capture，点击刷新或验证连接。")))
        /bin/rm -f -- "$0"
        read -r \(shellQuoted("?" + L10n.text("按回车关闭此窗口。")))
        exit "$TASK_LOGIN_STATUS"
        """
    }
    public static func write(provider: AIProvider, config: AppConfiguration, paths: StoragePaths) throws -> URL {
        let executable = config.executable(for: provider)
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CaptureError.invalid(L10n.format("请先安装 %@ 官方 CLI，或选择正确的文件位置。", provider.title))
        }
        let url = paths.runtime.appendingPathComponent("login-\(provider.rawValue)-\(UUID().uuidString).command")
        try Data(script(provider: provider, executable: executable).utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
