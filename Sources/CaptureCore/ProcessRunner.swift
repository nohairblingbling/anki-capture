import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunner {
    public static func run(executable: String, arguments: [String], input: String = "",
                           directory: URL, timeout: Double = 120) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try runBlocking(executable: executable, arguments: arguments, input: input, directory: directory, timeout: timeout)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func runBlocking(executable: String, arguments: [String], input: String,
                                    directory: URL, timeout: Double) throws -> ProcessResult {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw CaptureError.process("找不到可执行的 CLI：\(executable)。请在设置中选择正确路径。")
            }
            let scratch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: scratch) }
            let inputURL = scratch.appendingPathComponent("stdin")
            let outURL = scratch.appendingPathComponent("stdout")
            let errURL = scratch.appendingPathComponent("stderr")
            try Data(input.utf8).write(to: inputURL)
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let stdin = try FileHandle(forReadingFrom: inputURL)
            let stdout = try FileHandle(forWritingTo: outURL)
            let stderr = try FileHandle(forWritingTo: errURL)
            defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            // Preserve official CLI authentication and provider configuration. Never read tokens here.
            var environment = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            environment["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
            environment["NO_COLOR"] = "1"
            process.environment = environment
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                throw CaptureError.process("AI CLI 超时（\(Int(timeout)) 秒）。任务已保留，可稍后重试。")
            }
            func read(_ url: URL) throws -> String {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let size = try handle.seekToEnd()
                if size > 2_000_000 { throw CaptureError.process("CLI 输出过长，请检查 CLI 配置。") }
                try handle.seek(toOffset: 0)
                return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
            }
            return ProcessResult(exitCode: process.terminationStatus, stdout: try read(outURL), stderr: try read(errURL))
    }
}

public struct DiagnosticItem: Codable, Sendable {
    public let name: String
    public let ok: Bool
    public let detail: String
    public init(name: String, ok: Bool, detail: String) { self.name = name; self.ok = ok; self.detail = detail }
}

public enum Diagnostics {
    public static func check(config: AppConfiguration, paths: StoragePaths) async -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        for provider in AIProvider.allCases {
            let path = config.executable(for: provider)
            do {
                let result = try await ProcessRunner.run(executable: path, arguments: ["--version"], directory: paths.runtime, timeout: 10)
                items.append(.init(name: provider.title, ok: result.exitCode == 0, detail: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                let args = provider == .codex ? ["login", "status"] : ["auth", "status"]
                let auth = try await ProcessRunner.run(executable: path, arguments: args, directory: paths.runtime, timeout: 10)
                var detail = "未登录或认证不可用"
                if provider == .codex {
                    let text = (auth.stdout + auth.stderr).lowercased()
                    if text.contains("chatgpt") { detail = "ChatGPT 登录" }
                    else if text.contains("api key") { detail = "API Key 登录（按 CLI 配置计费）" }
                    else if auth.exitCode == 0 { detail = "已认证，计费方式由 CLI 配置决定" }
                } else if let data = auth.stdout.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          object["loggedIn"] as? Bool == true {
                    detail = "已认证：" + (object["authMethod"] as? String ?? "CLI 配置")
                }
                items.append(.init(name: provider.title + " 登录", ok: auth.exitCode == 0, detail: detail))
            } catch { items.append(.init(name: provider.title, ok: false, detail: error.localizedDescription)) }
        }
        do {
            let client = try AnkiClient(config: config)
            let version: Int = try await client.call("version")
            items.append(.init(name: "AnkiConnect", ok: version >= 6, detail: "API v\(version)"))
            let decks = try await client.deckNames()
            items.append(.init(name: "目标牌组", ok: decks.contains(config.deck), detail: config.deck.isEmpty ? "尚未选择" : config.deck))
        } catch { items.append(.init(name: "AnkiConnect", ok: false, detail: error.localizedDescription)) }
        return items
    }
}
