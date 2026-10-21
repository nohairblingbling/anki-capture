import Foundation
import Testing
@testable import CaptureCore

@Test func languageSelectionAndFallback() throws {
    #expect(AppLanguage.system.resolved(preferredLanguages: ["ja-JP", "en-US"]) == .japanese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-TW", "en-US"]) == .chinese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB"]) == .english)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .english)
    #expect(AppLanguage.japanese.resolved(preferredLanguages: ["en-US"]) == .japanese)
    #expect(L10n.text("保存设置", language: .english) == "Save settings")
    #expect(L10n.text("保存设置", language: .japanese) == "設定を保存")
    #expect(L10n.text("保存设置", language: .chinese) == "保存设置")
    #expect(L10n.text("user-provided vocabulary", language: .japanese) == "user-provided vocabulary")
    var config = try JSONDecoder().decode(AppConfiguration.self, from: Data(#"{"deck":"Existing"}"#.utf8))
    #expect(config.interfaceLanguage == .system)
    #expect(config.explanationLanguage == .system)
    config.interfaceLanguage = .japanese
    #expect(config.resolvedExplanationLanguage == .japanese)
    config.explanationLanguage = .chinese
    #expect(config.resolvedExplanationLanguage == .chinese)
    #expect(try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(config)) == config)
}

@Test func multilingualPromptsPreserveSourceAndChooseExplanationLanguage() throws {
    var config = AppConfiguration()
    config.interfaceLanguage = .english
    config.explanationLanguage = .japanese
    for term in ["折り合い", "salient", "机会成本"] {
        let input = try CaptureInput(text: term)
        for provider in AIProvider.allCases {
            let request = try LocalCLIGenerator.invocation(input: input, provider: provider, model: "", config: config,
                schema: URL(fileURLWithPath: "/tmp/schema.json"), result: URL(fileURLWithPath: "/tmp/result.json"))
            #expect(request.prompt.contains("Use Japanese as the explanation language"))
            #expect(request.prompt.contains("Never translate term"))
            #expect(request.prompt.contains("for Japanese prefer a kana reading"))
            #expect(request.prompt.contains(term))
            #expect(!request.arguments.contains(term))
            #expect(!request.prompt.contains("English vocabulary card author"))
        }
    }
}

private actor LanguageRecordingGenerator: CardGenerating {
    var received: [AppLanguage] = []
    func generate(input: CaptureInput, provider: AIProvider, model: String, config: AppConfiguration) async throws -> VocabularyCard {
        received.append(config.resolvedExplanationLanguage)
        return .init(term: input.text, lemma: input.text, senseKey: "example", meaningZh: "a compromise", definitionEn: "互いに譲り合うこと。")
    }
}
private struct LanguageTestWriter: AnkiWriting {
    func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult { .init(noteID: 42, duplicate: false) }
}
@Test func queuedExplanationLanguageIsFrozenAndOldJobsStillDecode() async throws {
    let paths = try StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let store = try JobStore(paths: paths)
    var config = AppConfiguration(); config.deck = "Test only"; config.interfaceLanguage = .japanese; config.explanationLanguage = .english
    let job = try await store.enqueue(CaptureInput(text: "折り合い"), config: config)
    #expect(job.explanationLanguage == .english)
    var oldPayload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
    oldPayload.removeValue(forKey: "explanationLanguage")
    let old = try JSONDecoder().decode(CaptureJob.self, from: JSONSerialization.data(withJSONObject: oldPayload))
    #expect(old.explanationLanguage == nil)
    config.interfaceLanguage = .chinese; config.explanationLanguage = .japanese
    let generator = LanguageRecordingGenerator()
    try await QueueWorker(store: store, generator: generator).drain(config: config, writer: LanguageTestWriter())
    #expect(await generator.received == [.english])
    #expect(try await store.get(job.id)?.status == .saved)
    #expect(AnkiClient.noteFields(card: (try await store.get(job.id))!.card!, job: job)["Term"] == "折り合い")
}
@Test func authenticationFailureClassificationDoesNotDependOnLanguage() {
    for language in [AppLanguage.english, .chinese, .japanese] {
        let error = CaptureError.authentication(L10n.text("请先在终端完成这个 CLI 的登录。", language: language))
        #expect(ProviderConnections.verificationFailure(error, provider: .gemini).state == .signedOut)
        #expect(ProviderConnections.verificationFailure(CaptureError.process("quota"), provider: .gemini).state == .failed)
    }
}
