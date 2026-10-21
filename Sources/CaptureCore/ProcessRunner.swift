import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunner {
    public static func run(executable: String, arguments: [String], input: String = "",
                           directory: URL, timeout: Double = 120, environmentOverrides: [String: String] = [:]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try runBlocking(executable: executable, arguments: arguments, input: input, directory: directory, timeout: timeout, environmentOverrides: environmentOverrides)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func runBlocking(executable: String, arguments: [String], input: String,
                                    directory: URL, timeout: Double, environmentOverrides: [String: String]) throws -> ProcessResult {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw CaptureError.process(L10n.format("找不到可执行的 CLI：%@。请在设置中选择正确路径。", executable))
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
            environment["PATH"] = [URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
            environment["NO_COLOR"] = "1"
            environment.merge(environmentOverrides) { _, override in override }
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
                throw CaptureError.process(L10n.format("AI CLI 超时（%d 秒）。任务已保留，可稍后重试。", Int(timeout)))
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
    public static func check(config: AppConfiguration, paths: StoragePaths, connections: [ProviderConnection]? = nil) async -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        let statuses: [ProviderConnection]
        if let connections { statuses = connections }
        else { statuses = await ProviderConnections.checkAll(config: config, paths: paths) }
        for status in statuses {
            items.append(.init(name: status.provider.title, ok: ![.missing, .failed].contains(status.state), detail: status.version.isEmpty ? status.detail : status.version))
            items.append(.init(name: status.provider.title + " 登录", ok: status.state == .connected, detail: status.detail))
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
