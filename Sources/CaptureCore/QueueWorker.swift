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
                let card: VocabularyCard
                if let existing = job.card { card = existing }
                else {
                    card = try await generator.generate(input: job.input, provider: job.provider, model: job.model, config: config)
                    try await store.generated(job.id, card: card, review: !job.autoSave)
                    if !job.autoSave { continue }
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
