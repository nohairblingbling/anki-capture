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
    public var geminiPath: String = ExecutableLocator.find("gemini") ?? ""
    public var codexModel: String = ""
    public var claudeModel: String = "sonnet"
    public var geminiModel: String = ""
    public var showInDock: Bool = true
    public var interfaceLanguage: AppLanguage = .system
    public var explanationLanguage: AppLanguage = .system
    public var resolvedExplanationLanguage: AppLanguage {
        (explanationLanguage == .system ? interfaceLanguage : explanationLanguage).resolved()
    }
    public var deck: String = ""
    public var noteType: String = "Anki Capture"
    public var ankiURL: String = "http://127.0.0.1:8765"
    public var ankiAPIKey: String = ""
    public var timeoutSeconds: Double = 120
    public var autoSave: Bool = true
    public var customInstructions: String = ""
    public init() {}
    public var model: String { model(for: provider) }
    public func model(for provider: AIProvider) -> String {
        switch provider { case .codex: codexModel; case .claude: claudeModel; case .gemini: geminiModel }
    }
    public mutating func setModel(_ value: String, for provider: AIProvider) {
        switch provider { case .codex: codexModel = value; case .claude: claudeModel = value; case .gemini: geminiModel = value }
    }
    public func executable(for provider: AIProvider) -> String {
        let path: String
        switch provider { case .codex: path = codexPath; case .claude: path = claudePath; case .gemini: path = geminiPath }
        return path.isEmpty ? (ExecutableLocator.find(provider.commandName) ?? "") : path
    }
    public mutating func setExecutable(_ path: String, for provider: AIProvider) {
        switch provider { case .codex: codexPath = path; case .claude: claudePath = path; case .gemini: geminiPath = path }
    }
    private enum CodingKeys: String, CodingKey {
        case provider, codexPath, claudePath, geminiPath, codexModel, claudeModel, geminiModel, showInDock
        case deck, noteType, ankiURL, ankiAPIKey, timeoutSeconds, autoSave, customInstructions
        case interfaceLanguage, explanationLanguage
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        interfaceLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .interfaceLanguage) ?? .system
        explanationLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .explanationLanguage) ?? .system
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? provider
        codexPath = try values.decodeIfPresent(String.self, forKey: .codexPath) ?? codexPath
        claudePath = try values.decodeIfPresent(String.self, forKey: .claudePath) ?? claudePath
        geminiPath = try values.decodeIfPresent(String.self, forKey: .geminiPath) ?? geminiPath
        codexModel = try values.decodeIfPresent(String.self, forKey: .codexModel) ?? codexModel
        claudeModel = try values.decodeIfPresent(String.self, forKey: .claudeModel) ?? claudeModel
        geminiModel = try values.decodeIfPresent(String.self, forKey: .geminiModel) ?? geminiModel
        showInDock = try values.decodeIfPresent(Bool.self, forKey: .showInDock) ?? showInDock
        deck = try values.decodeIfPresent(String.self, forKey: .deck) ?? deck
        noteType = try values.decodeIfPresent(String.self, forKey: .noteType) ?? noteType
        ankiURL = try values.decodeIfPresent(String.self, forKey: .ankiURL) ?? ankiURL
        ankiAPIKey = try values.decodeIfPresent(String.self, forKey: .ankiAPIKey) ?? ankiAPIKey
        timeoutSeconds = try values.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? timeoutSeconds
        autoSave = try values.decodeIfPresent(Bool.self, forKey: .autoSave) ?? autoSave
        customInstructions = try values.decodeIfPresent(String.self, forKey: .customInstructions) ?? customInstructions
    }
    public func validated() throws -> Self {
        guard let url = URL(string: ankiURL), url.scheme == "http",
              let host = url.host, ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw CaptureError.invalid("AnkiConnect 地址须为本机 HTTP 地址，例如 http://127.0.0.1:8765。")
        }
        guard (15...300).contains(timeoutSeconds), !noteType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              noteType.count <= 120, deck.count <= 200, codexModel.count <= 150, claudeModel.count <= 150, geminiModel.count <= 150,
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
        var dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.asdf/shims"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        // Finder-launched apps do not inherit a terminal's nvm/fnm shell setup.
        for (root, suffix) in [("\(home)/.nvm/versions/node", "bin"),
                               ("\(home)/.local/share/fnm/node-versions", "installation/bin"),
                               ("\(home)/Library/Application Support/fnm/node-versions", "installation/bin")] {
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            dirs += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { "\(root)/\($0)/\(suffix)" }
        }
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
