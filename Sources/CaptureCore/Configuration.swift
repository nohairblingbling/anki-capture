import Foundation

public struct StoragePaths: Sendable {
    public let root: URL
    public var config: URL { root.appendingPathComponent("config.json") }
    public var database: URL { root.appendingPathComponent("jobs.sqlite3") }
    public var runtime: URL { root.appendingPathComponent("runtime", isDirectory: true) }
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnkiCapture", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var provider: AIProvider = .codex
    public var codexPath: String = ExecutableLocator.find("codex") ?? ""
    public var claudePath: String = ExecutableLocator.find("claude") ?? ""
    public var codexModel: String = ""
    public var claudeModel: String = "sonnet"
    public var deck: String = ""
    public var noteType: String = "Anki Capture"
    public var ankiURL: String = "http://127.0.0.1:8765"
    public var ankiAPIKey: String = ""
    public var timeoutSeconds: Double = 120
    public var autoSave: Bool = true
    public var customInstructions: String = ""
    public init() {}
    public var model: String { provider == .codex ? codexModel : claudeModel }
    public func executable(for provider: AIProvider) -> String { provider == .codex ? codexPath : claudePath }
    public func validated() throws -> Self {
        guard let url = URL(string: ankiURL), url.scheme == "http",
              let host = url.host, ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw CaptureError.invalid("AnkiConnect 地址须为本机 HTTP 地址，例如 http://127.0.0.1:8765。")
        }
        guard (15...300).contains(timeoutSeconds), !noteType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              noteType.count <= 120, deck.count <= 200, codexModel.count <= 150, claudeModel.count <= 150,
              customInstructions.count <= 6000 else { throw CaptureError.invalid("请检查超时、牌组、模板或模型设置。") }
        return self
    }
    public static func load(from paths: StoragePaths) throws -> Self {
        guard FileManager.default.fileExists(atPath: paths.config.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: paths.config)).validated()
    }
    public func save(to paths: StoragePaths) throws {
        let value = try validated()
        try Data(jsonString(value).utf8).write(to: paths.config, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.config.path)
    }
}

public enum ExecutableLocator {
    public static func find(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public static func codexModels() -> [String] {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("models_cache.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { model in
            guard model["visibility"] as? String != "hide", model["hidden"] as? Bool != true else { return nil }
            return model["slug"] as? String
        }.filter { !$0.contains("auto-review") }
    }
}
