import Foundation
import ArgumentParser
import CaptureCore

struct CommonOptions: ParsableArguments {
    @Option(help: "Local data folder; defaults to ~/Library/Application Support/AnkiCapture") var dataDir: String?
    var paths: StoragePaths { get throws { try StoragePaths(root: dataDir.map { URL(fileURLWithPath: $0) }) } }
}

@main
struct AnkiCaptureCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "anki-capture", abstract: "Capture multilingual Anki cards using your local Codex, Claude Code, or Gemini CLI.",
        version: "0.5.0", subcommands: [Doctor.self, Connections.self, Configure.self, Decks.self, Models.self, Setup.self,
                                      Generate.self, Add.self, Jobs.self, Retry.self, Undo.self, Run.self], defaultSubcommand: Doctor.self)
}

struct Connections: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the three official CLIs; --verify makes one AI request without writing to Anki.")
    @OptionGroup var common: CommonOptions
    @Option(help: "Test codex / claude / gemini using its saved model.") var verify: String?
    @Option(help: "Print the official sign-in command for a provider.") var loginCommand: String?
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        L10n.language = config.interfaceLanguage
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
    static let configuration = CommandConfiguration(abstract: "Check local CLI authentication and AnkiConnect.")
    @OptionGroup var common: CommonOptions
    @Flag var json = false
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        L10n.language = config.interfaceLanguage
        let items = await Diagnostics.check(config: config, paths: paths)
        if json { print(try jsonString(items)) }
        else { for item in items { print("\(item.ok ? "✓" : "·") \(L10n.text(item.name)): \(L10n.text(item.detail))") } }
        if !items.contains(where: { $0.name == config.provider.title + " 登录" && $0.ok }) { throw ExitCode(2) }
        if !items.contains(where: { $0.name == "AnkiConnect" && $0.ok })
            || !items.contains(where: { $0.name == "目标牌组" && $0.ok }) { throw ExitCode(3) }
    }
}

struct Configure: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Save deck, provider, model, and language preferences.")
    @OptionGroup var common: CommonOptions
    @Option var deck: String?
    @Option(help: "Interface language: system / en / zh-Hans / ja") var language: String?
    @Option(help: "Confirm and remember an independent explanation language: en / zh-Hans / ja") var explanationLanguage: String?
    @Option(help: "Optional study language hints, comma-separated: en,zh,ja. Use an empty string to clear.") var studyLanguages: String?
    @Option(help: "Explanation level: automatic / beginner / intermediate / advanced") var learningLevel: String?
    @Option var provider: String?
    @Option var model: String?
    @Option var noteType: String?
    @Option var codexPath: String?
    @Option var claudePath: String?
    @Option var geminiPath: String?
    @Option(help: "Show the Dock icon: true / false") var showInDock: Bool?
    @Option var ankiUrl: String?
    @Flag(help: "Require review before adding generated cards.") var preview = false
    @Flag(help: "Automatically add generated cards to Anki.") var autoSave = false
    mutating func run() throws {
        let paths = try common.paths
        var config = try AppConfiguration.load(from: paths)
        if let provider {
            guard let value = AIProvider(rawValue: provider) else { throw ValidationError("provider must be codex, claude, or gemini.") }
            config.provider = value
        }
        if let language {
            guard let value = AppLanguage(rawValue: language) else { throw ValidationError("language must be system, en, zh-Hans, or ja.") }
            config.interfaceLanguage = value
        }
        if let explanationLanguage {
            guard let value = AppLanguage(rawValue: explanationLanguage), value != .system else { throw ValidationError("explanation-language must be en, zh-Hans, or ja; it is independent of the interface.") }
            config.explanationLanguage = value
            config.explanationLanguageConfirmed = true
        }
        if let studyLanguages {
            let codes = studyLanguages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let values = codes.compactMap(StudyLanguage.init(rawValue:))
            guard values.count == codes.count else { throw ValidationError("study-languages must be comma-separated en, zh, ja, or empty.") }
            config.learningPreferences.languages = Set(values)
        }
        if let learningLevel {
            guard let value = LearningLevel(rawValue: learningLevel) else { throw ValidationError("learning-level must be automatic, beginner, intermediate, or advanced.") }
            config.learningPreferences.level = value
        }
        if let deck { config.deck = deck }
        if let model { config.setModel(model, for: config.provider) }
        if let noteType { config.noteType = noteType }
        if let codexPath { config.codexPath = codexPath }
        if let claudePath { config.claudePath = claudePath }
        if let geminiPath { config.geminiPath = geminiPath }
        if let showInDock { config.showInDock = showInDock }
        if let ankiUrl { config.ankiURL = ankiUrl }
        guard !(preview && autoSave) else { throw ValidationError("Choose either preview or auto-save.") }
        if preview { config.autoSave = false }; if autoSave { config.autoSave = true }
        try config.save(to: paths)
        print("Saved: \(config.provider.title) / \(config.model.isEmpty ? "CLI default" : config.model) → \(config.deck.isEmpty ? "No deck selected" : config.deck)")
    }
}

struct Decks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List or create decks in the current Anki profile.")
    @OptionGroup var common: CommonOptions
    @Option(help: "Create a deck; use Parent::Child for a subdeck. Existing decks are reused.") var create: String?
    @Flag(help: "Remember the created deck as the capture destination. Requires --create.") var select = false
    mutating func run() async throws {
        guard !select || create != nil else { throw ValidationError("--select requires --create.") }
        let paths = try common.paths
        var config = try AppConfiguration.load(from: paths)
        L10n.language = config.interfaceLanguage
        let client = try AnkiClient(config: config)
        if let create {
            let deck = try await client.createDeck(named: create)
            if select { config.deck = deck.name; try config.save(to: paths) }
            print(try jsonString(deck))
        } else { print(try jsonString(await client.deckNames())) }
    }
}
struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List cached Codex models and provider aliases; model access requires testing.")
    mutating func run() throws {
        print(try jsonString(["codex_cached": ExecutableLocator.codexModels(), "claude_aliases": AIProvider.claude.modelSuggestions, "gemini_aliases": AIProvider.gemini.modelSuggestions]))
    }
}
struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Initialize the dedicated Anki note type.")
    @OptionGroup var common: CommonOptions
    mutating func run() async throws {
        let config = try AppConfiguration.load(from: common.paths)
        let client = try AnkiClient(config: config)
        guard try await client.deckNames().contains(config.deck) else { throw ValidationError("Configure an existing Anki deck first.") }
        try await client.ensureNoteType(config.noteType)
        print("Note type ready: \(config.noteType)")
    }
}
struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Generate card JSON without writing to Anki.")
    @OptionGroup var common: CommonOptions
    @Argument var text: String
    @Option var context = ""
    @Option var source = ""
    @Option var provider: String?
    @Option var model: String?
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        L10n.language = config.interfaceLanguage
        let selected = try selectedProvider(provider, fallback: config.provider)
        try config.requireLearningPreferences()
        let input = try CaptureInput(text: text, context: context, source: source, sourceApp: "CLI")
        let generated = try await LocalCLIGenerator(paths: paths).generate(input: input, provider: selected,
            model: model ?? config.model(for: selected), config: config)
        let card = CardReviewPolicy.prepared(generated, input: input, explanationLanguage: config.resolvedExplanationLanguage)
        print(try jsonString(card))
    }
}
struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture a word, phrase, or short concept; persist before generating and adding.")
    @OptionGroup var common: CommonOptions
    @Argument(help: "Read from stdin when omitted.") var text: String?
    @Option var context = ""
    @Option var source = ""
    @Option var deck: String?
    @Option var provider: String?
    @Option var model: String?
    @Flag var queueOnly = false
    @Flag(help: "Require review before adding this generated card.") var preview = false
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
    static let configuration = CommandConfiguration(abstract: "View local captures and generated cards.")
    @OptionGroup var common: CommonOptions
    @Option var limit = 30
    mutating func run() async throws { print(try jsonString(await JobStore(paths: common.paths).list(limit: limit))) }
}
struct Retry: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Retry a failed capture or confirm a reviewed card; reuse generated content.")
    @OptionGroup var common: CommonOptions
    @Argument var id: String
    mutating func run() async throws {
        let paths = try common.paths
        let config = try AppConfiguration.load(from: paths)
        L10n.language = config.interfaceLanguage
        let store = try JobStore(paths: paths)
        try await store.retry(id)
        try await QueueWorker(store: store, generator: LocalCLIGenerator(paths: paths)).drain(config: config)
        print(try jsonString(await store.get(id)))
    }
}
struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Process the queue; --watch keeps retrying captures waiting for Anki.")
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
    static let configuration = CommandConfiguration(abstract: "Undo cards created by this capture with no review history; requires --yes.")
    @OptionGroup var common: CommonOptions
    @Argument var id: String
    @Flag var yes = false
    mutating func run() async throws {
        guard yes else { throw ValidationError("This deletes the note and cards created by this capture. Use --yes to confirm.") }
        let paths = try common.paths
        let store = try JobStore(paths: paths)
        guard let job = try await store.get(id) else { throw ValidationError("Capture not found.") }
        try await AnkiClient(config: AppConfiguration.load(from: paths)).undo(job)
        try await store.finish(id, status: .undone)
        print(try jsonString(await store.get(id)))
    }
}
private func selectedProvider(_ name: String?, fallback: AIProvider) throws -> AIProvider {
    guard let name else { return fallback }
    guard let provider = AIProvider(rawValue: name) else { throw ValidationError("provider must be codex, claude, or gemini.") }
    return provider
}
