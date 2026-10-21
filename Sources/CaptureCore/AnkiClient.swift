import Foundation

public protocol AnkiWriting: Sendable {
    func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult
}
public struct AnkiWriteResult: Sendable {
    public let noteID: Int64
    public let duplicate: Bool
    public init(noteID: Int64, duplicate: Bool) { self.noteID = noteID; self.duplicate = duplicate }
}

public struct AnkiClient: AnkiWriting {
    private let endpoint: URL
    private let key: String
    private let session: URLSession
    public init(config: AppConfiguration, session: URLSession = .shared) throws {
        let config = try config.validated()
        endpoint = URL(string: config.ankiURL)!
        key = config.ankiAPIKey; self.session = session
    }
    public func call<T: Decodable>(_ action: String, params: [String: Any] = [:]) async throws -> T {
        var body: [String: Any] = ["action": action, "version": 6, "params": params]
        if !key.isEmpty { body["key"] = key }
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        do {
            let response: URLResponse
            (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw CaptureError.invalid("AnkiConnect HTTP 响应异常。")
            }
        } catch let error as URLError {
            throw CaptureError.unavailable("无法连接 AnkiConnect。请打开 Anki，安装插件 2055492159 并重启。任务已保留。\(error.code == .timedOut ? " 请求超时。" : "")")
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope.keys.contains("result"), envelope.keys.contains("error") else {
            throw CaptureError.invalid("本地服务未返回 AnkiConnect API v6 响应。")
        }
        if let error = envelope["error"] as? String { throw CaptureError.invalid("AnkiConnect：" + error) }
        let encoded = try JSONSerialization.data(withJSONObject: envelope["result"]!, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: encoded)
    }
    public func deckNames() async throws -> [String] {
        let names: [String] = try await call("deckNames")
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public static let fields = ["CaptureKey", "Term", "Meaning", "Definition", "PartOfSpeech", "Pronunciation", "Example", "ExampleMeaning", "Context", "Source", "CapturedAt"]
    public func ensureNoteType(_ name: String) async throws {
        let names: [String] = try await call("modelNames")
        if names.contains(name) {
            let fields: [String] = try await call("modelFieldNames", params: ["modelName": name])
            guard fields == Self.fields else { throw CaptureError.invalid("笔记类型“\(name)”的字段与 Anki Capture 不匹配，请设置一个新的专用笔记类型名称。") }
            return
        }
        let _: [String: JSONValue] = try await call("createModel", params: [
            "modelName": name, "inOrderFields": Self.fields, "css": Self.css,
            "cardTemplates": [["Name": "Vocabulary", "Front": Self.front, "Back": Self.back]]
        ])
    }
    public func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult {
        guard try await deckNames().contains(job.deck) else { throw CaptureError.invalid("目标牌组“\(job.deck)”不存在，请在设置中重新选择。") }
        try await ensureNoteType(job.noteType)
        let captureKey = card.captureKey(deck: job.deck, noteType: job.noteType)
        // The first field is a deterministic key, making retries after a timeout idempotent.
        let escapedModel = job.noteType.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let query = "note:\"\(escapedModel)\" CaptureKey:\(captureKey)"
        let existing: [Int64] = try await call("findNotes", params: ["query": query])
        if let id = existing.first { return .init(noteID: id, duplicate: true) }
        let note: [String: Any] = [
            "deckName": job.deck, "modelName": job.noteType, "fields": Self.noteFields(card: card, job: job),
            "options": ["allowDuplicate": false],
            "tags": ["anki_capture", "anki_capture_id::" + job.id] + (card.needsReview ? ["anki_capture_check"] : [])
        ]
        do {
            let id: Int64 = try await call("addNote", params: ["note": note])
            return .init(noteID: id, duplicate: false)
        } catch {
            // A concurrent worker may have completed the same semantic card after our check.
            if let ids: [Int64] = try? await call("findNotes", params: ["query": query]), let id = ids.first {
                return .init(noteID: id, duplicate: true)
            }
            throw error
        }
    }
    public func undo(_ job: CaptureJob) async throws {
        guard job.status == .saved, let noteID = job.noteID, let card = job.card else {
            throw CaptureError.invalid("只能撤销由本任务新建的字卡。")
        }
        struct NoteInfo: Decodable {
            struct Field: Decodable { let value: String }
            let noteId: Int64; let tags: [String]; let cards: [Int64]; let fields: [String: Field]
        }
        struct CardInfo: Decodable { let reps: Int }
        let notes: [NoteInfo] = try await call("notesInfo", params: ["notes": [noteID]])
        guard let note = notes.first, note.noteId == noteID,
              note.tags.contains("anki_capture_id::" + job.id),
              note.fields["CaptureKey"]?.value == card.captureKey(deck: job.deck, noteType: job.noteType) else {
            throw CaptureError.invalid("无法确认这条笔记属于本任务，请在 Anki 中查看。")
        }
        let cards: [CardInfo] = try await call("cardsInfo", params: ["cards": note.cards])
        guard cards.allSatisfy({ $0.reps == 0 }) else { throw CaptureError.invalid("这张字卡已产生复习记录，请在 Anki 中管理。") }
        let _: Int? = try await call("deleteNotes", params: ["notes": [noteID]])
    }
    public static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;").replacingOccurrences(of: "\n", with: "<br>")
    }
    public static func noteFields(card: VocabularyCard, job: CaptureJob) -> [String: String] {
        let date = ISO8601DateFormatter().string(from: job.createdAt)
        let raw = [card.captureKey(deck: job.deck, noteType: job.noteType), card.term, card.meaningZh, card.definitionEn,
                   card.partOfSpeech, card.pronunciation, card.exampleEn, card.exampleZh,
                   job.input.context, job.input.source, date]
        return Dictionary(uniqueKeysWithValues: zip(fields, raw.map(escapeHTML)))
    }
    public static let css = """
    .card { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 22px; text-align: left; color: #27292e; background: #faf9f6; max-width: 680px; margin: 0 auto; padding: 36px; line-height: 1.65; }
    .term { font-size: 38px; font-weight: 650; line-height: 1.3; margin-bottom: 10px; }
    .meta, .source { font-size: 14px; opacity: .6; } .meaning { font-size: 26px; font-weight: 600; }
    .context, .example { margin: 24px 0; padding-left: 16px; border-left: 3px solid #8b9e93; }
    .translation { opacity: .7; font-size: 18px; } hr { border: 0; border-top: 1px solid #9995; margin: 28px 0; }
    .nightMode.card { color: #e9e8e3; background: #202322; }
    """
    public static let front = """
    <div class="term">{{Term}}</div>
    {{#Context}}<div class="context">{{Context}}</div>{{/Context}}
    """
    public static let back = """
    {{FrontSide}}<hr id="answer">
    <div class="meta">{{PartOfSpeech}} {{Pronunciation}}</div>
    <div class="meaning">{{Meaning}}</div><div>{{Definition}}</div>
    {{#Example}}<div class="example">{{Example}}<div class="translation">{{ExampleMeaning}}</div></div>{{/Example}}
    {{#Source}}<div class="source">{{Source}}</div>{{/Source}}
    """
}

// createModel returns an object whose properties vary with the Anki version.
public struct JSONValue: Decodable, Sendable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { return }
        if (try? value.decode(String.self)) != nil || (try? value.decode(Double.self)) != nil || (try? value.decode(Bool.self)) != nil { return }
        if (try? value.decode([JSONValue].self)) != nil || (try? value.decode([String: JSONValue].self)) != nil { return }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported JSON value")
    }
}
