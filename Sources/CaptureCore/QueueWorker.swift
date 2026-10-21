import Foundation

public actor QueueWorker {
    private let store: JobStore
    private let generator: any CardGenerating
    private var running = false
    public init(store: JobStore, generator: any CardGenerating) { self.store = store; self.generator = generator }

    public func drain(config: AppConfiguration, writer: (any AnkiWriting)? = nil) async throws {
        guard !running else { return }
        running = true
        defer { running = false }
        while let job = try await store.claimNext() {
            do {
                var card: VocabularyCard
                if let existing = job.card {
                    card = existing
                    // Old ambiguous offline cards also require confirmation, but never re-prompt after approval.
                    if card.needsReview && job.reviewConfirmed != true {
                        try await store.generated(job.id, card: card, review: true)
                        continue
                    }
                }
                else {
                    var generationConfig = config
                    generationConfig.explanationLanguage = job.explanationLanguage ?? .chinese
                    generationConfig.learningPreferences = job.learningPreferences ?? LearningPreferences()
                    card = try await generator.generate(input: job.input, provider: job.provider, model: job.model, config: generationConfig)
                    card = CardReviewPolicy.prepared(card, input: job.input, explanationLanguage: generationConfig.resolvedExplanationLanguage)
                    let review = !job.autoSave || card.needsReview
                    try await store.generated(job.id, card: card, review: review)
                    if review { continue }
                }
                let client: any AnkiWriting = try writer ?? AnkiClient(config: config)
                let result = try await client.save(card: card, job: job)
                try await store.finish(job.id, status: result.duplicate ? .duplicate : .saved, noteID: result.noteID)
            } catch CaptureError.unavailable(let message) {
                try await store.finish(job.id, status: .waitingForAnki, error: message, retryAfter: 20)
            } catch {
                try await store.finish(job.id, status: .failed, error: error.localizedDescription)
            }
        }
    }
}
