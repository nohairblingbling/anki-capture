import Foundation
import CryptoKit

public enum CaptureError: LocalizedError {
    case invalid(String)
    case process(String)
    case authentication(String)
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .process(let message), .authentication(let message), .unavailable(let message): return L10n.text(message)
        }
    }
}

public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case codex, claude, gemini
    public var title: String {
        switch self { case .codex: "Codex"; case .claude: "Claude Code"; case .gemini: "Gemini" }
    }
    public var commandName: String { self == .claude ? "claude" : rawValue }
    public var loginArguments: [String] {
        switch self { case .codex: ["login"]; case .claude: ["auth", "login"]; case .gemini: [] }
    }
    public var installationURL: URL {
        switch self {
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: URL(string: "https://code.claude.com/docs/en/setup")!
        case .gemini: URL(string: "https://geminicli.com/docs/get-started/installation/")!
        }
    }
    public var modelSuggestions: [String] {
        switch self {
        case .codex: ExecutableLocator.codexModels()
        case .claude: ["sonnet", "opus", "haiku"]
        case .gemini: ["auto", "pro", "flash"]
        }
    }
}

public struct CaptureInput: Codable, Sendable {
    public var text: String
    public var context: String
    public var source: String
    public var sourceApp: String
    public init(text: String, context: String = "", source: String = "", sourceApp: String = "") throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200, value.split(whereSeparator: \.isWhitespace).count <= 25 else {
            throw CaptureError.invalid("请选择一个单词或短语（最多 200 个字符、25 个单词）。")
        }
        guard context.count <= 6000, source.count <= 2000 else {
            throw CaptureError.invalid("上下文或来源过长。请缩短后重试。")
        }
        self.text = value
        self.context = context.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.sourceApp = sourceApp
    }
    public func fingerprint(deck: String, noteType: String) -> String {
        stableHash([normalized(text), normalized(context), deck, noteType].joined(separator: "\u{0}"))
    }
}

public struct VocabularyCard: Codable, Equatable, Sendable {
    public var term: String
    public var lemma: String
    public var senseKey: String
    public var meaningZh: String
    public var definitionEn: String
    public var partOfSpeech: String
    public var pronunciation: String
    public var exampleEn: String
    public var exampleZh: String
    public var needsReview: Bool
    enum CodingKeys: String, CodingKey {
        case term, lemma, pronunciation
        case senseKey = "sense_key", meaningZh = "meaning_zh", definitionEn = "definition_en"
        case partOfSpeech = "part_of_speech", exampleEn = "example_en", exampleZh = "example_zh"
        case needsReview = "needs_review"
    }
    public init(term: String, lemma: String, senseKey: String, meaningZh: String, definitionEn: String,
                partOfSpeech: String = "", pronunciation: String = "", exampleEn: String = "",
                exampleZh: String = "", needsReview: Bool = false) {
        self.term = term; self.lemma = lemma; self.senseKey = senseKey; self.meaningZh = meaningZh
        self.definitionEn = definitionEn; self.partOfSpeech = partOfSpeech; self.pronunciation = pronunciation
        self.exampleEn = exampleEn; self.exampleZh = exampleZh; self.needsReview = needsReview
    }
    public func validated() throws -> Self {
        for value in [term, lemma, senseKey, meaningZh, definitionEn] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CaptureError.invalid("AI 返回的字卡缺少必要字段。")
            }
        }
        guard term.count <= 200, lemma.count <= 200, senseKey.count <= 150,
              [meaningZh, definitionEn, partOfSpeech, pronunciation, exampleEn, exampleZh].allSatisfy({ $0.count <= 2000 }) else {
            throw CaptureError.invalid("AI 返回的字卡字段过长。")
        }
        return self
    }
    public func captureKey(deck: String, noteType: String) -> String {
        // Keep the historical namespace for existing notes; this is not a language restriction.
        "AC1-" + stableHash(["en", normalized(lemma), normalized(senseKey), deck, noteType].joined(separator: "\u{0}"))
    }
    public static let schema = #"""
    {"type":"object","properties":{"term":{"type":"string"},"lemma":{"type":"string"},"sense_key":{"type":"string"},"meaning_zh":{"type":"string"},"definition_en":{"type":"string"},"part_of_speech":{"type":"string"},"pronunciation":{"type":"string"},"example_en":{"type":"string"},"example_zh":{"type":"string"},"needs_review":{"type":"boolean"}},"required":["term","lemma","sense_key","meaning_zh","definition_en","part_of_speech","pronunciation","example_en","example_zh","needs_review"],"additionalProperties":false}
    """#
}

public enum JobStatus: String, Codable, Sendable {
    case queued, generating, review, ready, saving, waitingForAnki, saved, duplicate, failed, undone
    public var title: String {
        switch self {
        case .queued: return "等待生成"
        case .generating: return "正在生成"
        case .review: return "等待预览确认"
        case .ready, .saving: return "正在写入"
        case .waitingForAnki: return "等待 Anki"
        case .saved: return "已加入 Anki"
        case .duplicate: return "已存在"
        case .failed: return "处理失败"
        case .undone: return "已撤销"
        }
    }
}

public struct CaptureJob: Identifiable, Codable, Sendable {
    public var id: String
    public var input: CaptureInput
    public var deck: String
    public var noteType: String
    public var provider: AIProvider
    public var model: String
    public var autoSave: Bool
    public var status: JobStatus
    public var card: VocabularyCard?
    public var noteID: Int64?
    public var error: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var attempts: Int
    /// Nil in pre-0.3 jobs: preserve their original Chinese explanation behavior.
    public var explanationLanguage: AppLanguage? = nil
}

public func stableHash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

public func normalized(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

public func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
