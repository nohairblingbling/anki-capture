import Foundation
import ArgumentParser
import CaptureCore

struct CommonOptions: ParsableArguments {
    @Option(help: "本地数据目录；默认 ~/Library/Application Support/AnkiCapture") var dataDir: String?
    var paths: StoragePaths { get throws { try StoragePaths(root: dataDir.map { URL(fileURLWithPath: $0) }) } }
}

@main
struct AnkiCaptureCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "anki-capture", abstract: "通过本机 Codex / Claude Code / Gemini 生成英语字卡并加入 Anki。",
        version: "0.2.0", subcommands: [Doctor.self, Connections.self, Configure.self, Decks.self, Models.self, Setup.self,
                                      Generate.self, Add.self, Jobs.self, Retry.self, Undo.self, Run.self], defaultSubcommand: Doctor.self)
}

struct Connections: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "检查三个官方 CLI；--verify 会发出一次制卡请求，不写入 Anki。")
    @OptionGroup var common: CommonOptions
    @Option(help: "主动验证 codex / claude / gemini，使用该服务保存的模型。") var verify: String?
    @Option(help: "显示某个服务的官方登录命令。") var loginCommand: String?
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        if let loginCommand {
            let provider = try selectedProvider(loginCommand, fallback: config.provider)
            let executable = config.executable(for: provider)
            print(LoginCommand.display(provider: provider, executable: executable.isEmpty ? provider.commandName : executable))
            return
        }
        var statuses = await ProviderConnections.checkAll(config: config, paths: paths)
        if let verify {
            let provider = try selectedProvider(verify, fallback: config.provider)
            let value = await ProviderConnections.verify(provider, config: config, paths: paths)
            statuses.removeAll { $0.provider == provider }; statuses.append(value)
            print(try jsonString(statuses))
            if value.state != .connected { throw ExitCode(2) }
        } else { print(try jsonString(statuses)) }
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "检查本机 CLI 登录和 AnkiConnect。")
    @OptionGroup var common: CommonOptions
    @Flag var json = false
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        let items = await Diagnostics.check(config: config, paths: paths)
        if json { print(try jsonString(items)) }
        else { for item in items { print("\(item.ok ? "✓" : "·") \(item.name)：\(item.detail)") } }
        if !items.contains(where: { $0.name == config.provider.title + " 登录" && $0.ok }) { throw ExitCode(2) }
        if !items.contains(where: { $0.name == "AnkiConnect" && $0.ok })
            || !items.contains(where: { $0.name == "目标牌组" && $0.ok }) { throw ExitCode(3) }
    }
}

struct Configure: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "保存牌组、服务和模型设置。")
    @OptionGroup var common: CommonOptions
    @Option var deck: String?
    @Option var provider: String?
    @Option var model: String?
    @Option var noteType: String?
    @Option var codexPath: String?
    @Option var claudePath: String?
    @Option var geminiPath: String?
    @Option(help: "显示 Dock 图标：true / false") var showInDock: Bool?
    @Option var ankiUrl: String?
    @Flag(help: "生成后等待预览确认。") var preview = false
    @Flag(help: "生成后自动写入 Anki。") var autoSave = false
    mutating func run() throws {
        let paths = try common.paths
        var config = try AppConfiguration.load(from: paths)
        if let provider {
            guard let value = AIProvider(rawValue: provider) else { throw ValidationError("provider 必须为 codex、claude 或 gemini。") }
            config.provider = value
        }
        if let deck { config.deck = deck }
        if let model { config.setModel(model, for: config.provider) }
        if let noteType { config.noteType = noteType }
        if let codexPath { config.codexPath = codexPath }
        if let claudePath { config.claudePath = claudePath }
        if let geminiPath { config.geminiPath = geminiPath }
        if let showInDock { config.showInDock = showInDock }
        if let ankiUrl { config.ankiURL = ankiUrl }
        guard !(preview && autoSave) else { throw ValidationError("preview 和 auto-save 只能选择一个。") }
        if preview { config.autoSave = false }; if autoSave { config.autoSave = true }
        try config.save(to: paths)
        print("已保存：\(config.provider.title) / \(config.model.isEmpty ? "CLI 默认模型" : config.model) → \(config.deck.isEmpty ? "尚未选择牌组" : config.deck)")
    }
}

struct Decks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出当前 Anki 用户的牌组。")
    @OptionGroup var common: CommonOptions
    mutating func run() async throws {
        let client = try AnkiClient(config: AppConfiguration.load(from: common.paths))
        print(try jsonString(await client.deckNames()))
    }
}
struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "显示本机 Codex 缓存中的模型候选（实际访问权限需调用验证）。")
    mutating func run() throws {
        print(try jsonString(["codex_cached": ExecutableLocator.codexModels(), "claude_aliases": AIProvider.claude.modelSuggestions, "gemini_aliases": AIProvider.gemini.modelSuggestions]))
    }
}
struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "在 Anki 中初始化专用字卡笔记类型。")
    @OptionGroup var common: CommonOptions
    mutating func run() async throws {
        let config = try AppConfiguration.load(from: common.paths)
        let client = try AnkiClient(config: config)
        guard try await client.deckNames().contains(config.deck) else { throw ValidationError("请先配置一个现有牌组。") }
        try await client.ensureNoteType(config.noteType)
        print("字卡模板已就绪：\(config.noteType)")
    }
}
struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "仅生成字卡 JSON，供验证和预览使用。")
    @OptionGroup var common: CommonOptions
    @Argument var text: String
    @Option var context = ""
    @Option var source = ""
    @Option var provider: String?
    @Option var model: String?
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        let selected = try selectedProvider(provider, fallback: config.provider)
        let input = try CaptureInput(text: text, context: context, source: source, sourceApp: "CLI")
        let card = try await LocalCLIGenerator(paths: paths).generate(input: input, provider: selected,
            model: model ?? config.model(for: selected), config: config)
        print(try jsonString(card))
    }
}
struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "添加单词/短语；任务先持久化，再生成和写卡。")
    @OptionGroup var common: CommonOptions
    @Argument(help: "省略时从标准输入读取。") var text: String?
    @Option var context = ""
    @Option var source = ""
    @Option var deck: String?
    @Option var provider: String?
    @Option var model: String?
    @Flag var queueOnly = false
    @Flag(help: "本次生成后等待预览确认。") var preview = false
    mutating func run() async throws {
        let paths = try common.paths
        var config = try AppConfiguration.load(from: paths)
        if let deck { config.deck = deck }
        config.provider = try selectedProvider(provider, fallback: config.provider)
        if let model { config.setModel(model, for: config.provider) }
        if preview { config.autoSave = false }
        let term = text ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        let input = try CaptureInput(text: term, context: context, source: source, sourceApp: "CLI")
        let store = try JobStore(paths: paths)
        let job = try await store.enqueue(input, config: config.validated())
        if !queueOnly { try await QueueWorker(store: store, generator: LocalCLIGenerator(paths: paths)).drain(config: config) }
        if let current = try await store.get(job.id) {
            print(try jsonString(current))
            if current.status == .failed { throw ExitCode(1) }
        }
    }
}
struct Jobs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "查看本地任务和生成结果。")
    @OptionGroup var common: CommonOptions
    @Option var limit = 30
    mutating func run() async throws { print(try jsonString(await JobStore(paths: common.paths).list(limit: limit))) }
}
struct Retry: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "重试失败任务或确认预览字卡；已生成内容会复用。")
    @OptionGroup var common: CommonOptions
    @Argument var id: String
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        let store = try JobStore(paths: paths)
        try await store.retry(id)
        try await QueueWorker(store: store, generator: LocalCLIGenerator(paths: paths)).drain(config: config)
        print(try jsonString(await store.get(id)))
    }
}
struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "处理待办队列；--watch 持续处理等待 Anki 的任务。")
    @OptionGroup var common: CommonOptions
    @Flag var watch = false
    mutating func run() async throws {
        let paths = try common.paths
        let store = try JobStore(paths: paths)
        let worker = QueueWorker(store: store, generator: LocalCLIGenerator(paths: paths))
        repeat {
            try await worker.drain(config: AppConfiguration.load(from: paths))
            if watch { try await Task.sleep(for: .seconds(3)) }
        } while watch
        print(try jsonString(await store.list(limit: 30)))
    }
}
struct Undo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "撤销本任务新建、尚无复习记录的字卡；需 --yes。")
    @OptionGroup var common: CommonOptions
    @Argument var id: String
    @Flag var yes = false
    mutating func run() async throws {
        guard yes else { throw ValidationError("此操作会删除该任务新建的笔记和卡片。确认后加 --yes。") }
        let paths = try common.paths
        let store = try JobStore(paths: paths)
        guard let job = try await store.get(id) else { throw ValidationError("找不到任务。") }
        try await AnkiClient(config: AppConfiguration.load(from: paths)).undo(job)
        try await store.finish(id, status: .undone)
        print(try jsonString(await store.get(id)))
    }
}
private func selectedProvider(_ name: String?, fallback: AIProvider) throws -> AIProvider {
    guard let name else { return fallback }
    guard let provider = AIProvider(rawValue: name) else { throw ValidationError("provider 必须为 codex、claude 或 gemini。") }
    return provider
}
