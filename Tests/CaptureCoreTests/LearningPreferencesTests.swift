import Foundation
import Testing
@testable import CaptureCore

private func learningPaths() throws -> StoragePaths {
    try StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("anki-learning-" + UUID().uuidString))
}
private func confirmedConfiguration() -> AppConfiguration {
    var config = AppConfiguration()
    config.deck = "Disposable tests"
    config.explanationLanguage = .chinese
    config.explanationLanguageConfirmed = true
    return config
}
private func learningCard(language: String? = "en", review: Bool = false, reason: String? = nil) -> VocabularyCard {
    .init(term: "salient", lemma: "salient", senseKey: "noticeable", meaningZh: "显著的", definitionEn: "Noticeable.",
          needsReview: review, sourceLanguage: language, reviewReason: reason)
}
private actor LearningGenerator: CardGenerating {
    let card: VocabularyCard
    var calls = 0
    var preferences: [LearningPreferences] = []
    init(_ card: VocabularyCard) { self.card = card }
    func generate(input: CaptureInput, provider: AIProvider, model: String, config: AppConfiguration) async throws -> VocabularyCard {
        calls += 1; preferences.append(config.learningPreferences)
        var output = card; output.term = input.text; output.lemma = input.text
        return output
    }
}
private actor LearningWriter: AnkiWriting {
    var calls = 0
    var offlineOnce: Bool
    init(offlineOnce: Bool = false) { self.offlineOnce = offlineOnce }
    func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult {
        calls += 1
        if offlineOnce { offlineOnce = false; throw CaptureError.unavailable("Offline test") }
        return .init(noteID: 4321, duplicate: false)
    }
}

@Test func firstCaptureRequiresExplicitLanguageConfirmation() async throws {
    let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
    var config = AppConfiguration(); config.deck = "Test"
    #expect(!config.explanationLanguageConfirmed)
    let store = try JobStore(paths: paths)
    await #expect(throws: CaptureError.self) { try await store.enqueue(CaptureInput(text: "salient"), config: config) }
    #expect(try await store.list().isEmpty)
    // Saving UI/Dock preferences must not silently count as confirmation, even across restarts.
    config.interfaceLanguage = .japanese; config.showInDock = false
    try config.save(to: paths)
    #expect(try AppConfiguration.load(from: paths).explanationLanguageConfirmed == false)
    config.explanationLanguage = .chinese; config.explanationLanguageConfirmed = true
    try config.save(to: paths)
    var restored = try AppConfiguration.load(from: paths)
    restored.interfaceLanguage = .english
    #expect(restored.resolvedExplanationLanguage == .chinese)
    #expect(try await store.enqueue(CaptureInput(text: "salient"), config: restored).explanationLanguage == .chinese)
}

@Test func oldLanguageSettingsMigrateWithoutRepeatedOnboarding() throws {
    let explicit = try JSONDecoder().decode(AppConfiguration.self, from: Data(#"{"interfaceLanguage":"ja","explanationLanguage":"zh-Hans","deck":"Existing"}"#.utf8))
    #expect(explicit.explanationLanguageConfirmed)
    #expect(explicit.explanationLanguage == .chinese)
    let sameAsInterface = try JSONDecoder().decode(AppConfiguration.self, from: Data(#"{"interfaceLanguage":"ja","explanationLanguage":"system","deck":"Existing"}"#.utf8))
    #expect(!sameAsInterface.explanationLanguageConfirmed)
    #expect(sameAsInterface.explanationLanguage == .japanese)
    #expect(sameAsInterface.deck == "Existing")
    let preLanguages = try JSONDecoder().decode(AppConfiguration.self, from: Data(#"{"deck":"Existing"}"#.utf8))
    #expect(preLanguages.explanationLanguage == .chinese)
    #expect(!preLanguages.explanationLanguageConfirmed)
    var incomplete = confirmedConfiguration(); incomplete.explanationLanguageConfirmed = false
    let restored = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(incomplete))
    #expect(!restored.explanationLanguageConfirmed)
}

@Test func learningHintsAreFrozenAndNeverRestrictLanguages() async throws {
    let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
    let store = try JobStore(paths: paths)
    var config = confirmedConfiguration()
    config.learningPreferences.languages = [.english, .japanese]; config.learningPreferences.level = .beginner
    let job = try await store.enqueue(CaptureInput(text: "bonjour"), config: config)
    config.learningPreferences.languages = [.chinese]; config.learningPreferences.level = .advanced
    let generator = LearningGenerator(learningCard(language: "fr"))
    try await QueueWorker(store: store, generator: generator).drain(config: config, writer: LearningWriter())
    #expect(await generator.preferences.first == job.learningPreferences)
    #expect(try await store.get(job.id)?.status == .saved)
    let prompt = try LocalCLIGenerator.invocation(input: job.input, provider: .codex, model: "", config: config,
        schema: paths.runtime.appendingPathComponent("schema.json"), result: paths.runtime.appendingPathComponent("result.json")).prompt
    #expect(prompt.contains("never a language whitelist"))
    #expect(prompt.contains("Learner level: advanced"))
    #expect(prompt.contains("review_reason"))
}

@Test func uncertainCardsOverrideAutoSave() async throws {
    for card in [learningCard(review: true), learningCard(language: "und"), learningCard(language: nil),
                 learningCard(language: "not a language"), learningCard(reason: "Multiple meanings need context.")] {
        let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try JobStore(paths: paths)
        let config = confirmedConfiguration()
        let job = try await store.enqueue(CaptureInput(text: "salient"), config: config)
        let writer = LearningWriter()
        try await QueueWorker(store: store, generator: LearningGenerator(card)).drain(config: config, writer: writer)
        let result = try #require(await store.get(job.id))
        #expect(result.status == .review)
        #expect(result.card?.needsReview == true)
        #expect(result.card?.reviewReason?.isEmpty == false)
        #expect(await writer.calls == 0)
        #expect(try await store.claimNext() == nil)
    }
}

@Test func hanWordsWithoutContextNeedReviewDespiteLanguageHints() throws {
    let card = learningCard(language: "ja")
    let ambiguous = CardReviewPolicy.prepared(card, input: try CaptureInput(text: "手紙"), explanationLanguage: .english)
    #expect(ambiguous.needsReview)
    #expect(ambiguous.reviewReason?.contains("Chinese or Japanese") == true)
    let redundant = CardReviewPolicy.prepared(card, input: try CaptureInput(text: "手紙", context: "手紙"), explanationLanguage: .english)
    #expect(redundant.needsReview)
    let contextual = CardReviewPolicy.prepared(card, input: try CaptureInput(text: "手紙", context: "友達に手紙を書きました。"), explanationLanguage: .chinese)
    #expect(!contextual.needsReview)
    let kana = CardReviewPolicy.prepared(card, input: try CaptureInput(text: "折り合い"), explanationLanguage: .chinese)
    #expect(!kana.needsReview)
}

@Test func confirmedReviewSurvivesOfflineRetryAndRestart() async throws {
    let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
    let store = try JobStore(paths: paths)
    let config = confirmedConfiguration()
    let job = try await store.enqueue(CaptureInput(text: "salient"), config: config)
    let generator = LearningGenerator(learningCard(review: true, reason: "Confirm this meaning."))
    let writer = LearningWriter(offlineOnce: true)
    let worker = QueueWorker(store: store, generator: generator)
    try await worker.drain(config: config, writer: writer)
    #expect(await writer.calls == 0)
    var edited = try #require(await store.get(job.id)?.card); edited.meaningZh = "编辑后的释义"
    try await store.replaceReviewCard(job.id, card: edited)
    try await store.retry(job.id)
    try await worker.drain(config: config, writer: writer)
    #expect(try await store.get(job.id)?.status == .waitingForAnki)
    let reopened = try JobStore(paths: paths)
    #expect(try await reopened.get(job.id)?.reviewConfirmed == true)
    try await reopened.retry(job.id)
    try await QueueWorker(store: reopened, generator: generator).drain(config: config, writer: writer)
    #expect(try await reopened.get(job.id)?.status == .saved)
    #expect(try await reopened.get(job.id)?.card?.meaningZh == "编辑后的释义")
    #expect(await generator.calls == 1)
    #expect(await writer.calls == 2)
}

@Test func olderCardAndJobPayloadsStayReadableAndKeepDeduplicationKeys() async throws {
    let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
    let store = try JobStore(paths: paths)
    let job = try await store.enqueue(CaptureInput(text: "salient"), config: confirmedConfiguration())
    var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
    old.removeValue(forKey: "learningPreferences"); old.removeValue(forKey: "reviewConfirmed")
    let decoded = try JSONDecoder().decode(CaptureJob.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(decoded.learningPreferences == nil && decoded.reviewConfirmed == nil)
    var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(learningCard())) as! [String: Any]
    payload.removeValue(forKey: "source_language"); payload.removeValue(forKey: "review_reason")
    let card = try JSONDecoder().decode(VocabularyCard.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(card.sourceLanguage == nil && card.reviewReason == nil)
    #expect(card.captureKey(deck: job.deck, noteType: job.noteType) == learningCard().captureKey(deck: job.deck, noteType: job.noteType))
}

@Test func olderAmbiguousOfflineCardWaitsForConfirmationWithoutRegeneration() async throws {
    let paths = try learningPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
    let store = try JobStore(paths: paths)
    let config = confirmedConfiguration()
    let job = try await store.enqueue(CaptureInput(text: "salient"), config: config)
    _ = try await store.claimNext()
    // Reproduce a pre-0.4 automatic capture retained while Anki was unavailable.
    try await store.generated(job.id, card: learningCard(language: nil, review: true), review: false)
    try await store.finish(job.id, status: .waitingForAnki)
    let generator = LearningGenerator(learningCard())
    let writer = LearningWriter()
    let worker = QueueWorker(store: store, generator: generator)
    try await worker.drain(config: config, writer: writer)
    #expect(try await store.get(job.id)?.status == .review)
    #expect(await writer.calls == 0)
    try await store.retry(job.id)
    try await worker.drain(config: config, writer: writer)
    #expect(try await store.get(job.id)?.status == .saved)
    #expect(await generator.calls == 0)
    #expect(await writer.calls == 1)
}
