import Foundation
import Testing
@testable import CaptureCore

private func temporaryPaths() throws -> StoragePaths {
    try StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("anki-capture-test-" + UUID().uuidString))
}
private func testConfiguration() -> AppConfiguration {
    var config = AppConfiguration(); config.deck = "Vocabulary"; return config
}
private let sample = VocabularyCard(term: "salient", lemma: "salient", senseKey: "most-noticeable",
    meaningZh: "显著的；突出的", definitionEn: "Most noticeable or important.", partOfSpeech: "adjective",
    exampleEn: "The paper highlights three salient findings.", exampleZh: "论文强调了三个显著发现。")

@Test func captureValidationAndNormalization() throws {
    #expect(throws: CaptureError.self) { try CaptureInput(text: " \n ") }
    #expect(throws: CaptureError.self) { try CaptureInput(text: String(repeating: "a", count: 201)) }
    let one = try CaptureInput(text: " In  Light Of ")
    let two = try CaptureInput(text: "in light of")
    #expect(one.fingerprint(deck: "A", noteType: "N") == two.fingerprint(deck: "A", noteType: "N"))
    #expect(one.fingerprint(deck: "A", noteType: "N") != one.fingerprint(deck: "B", noteType: "N"))
    let context = try CaptureInput(text: "in light of", context: "In light of the evidence, we changed our conclusion.")
    #expect(one.fingerprint(deck: "A", noteType: "N") != context.fingerprint(deck: "A", noteType: "N"))
}

@Test func configurationIsLocalAndPrivate() throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    var config = testConfiguration()
    config.ankiURL = "http://example.com:8765"
    #expect(throws: CaptureError.self) { try config.save(to: paths) }
    config.ankiURL = "http://127.0.0.1:8765"
    config.ankiAPIKey = "test-only"
    try config.save(to: paths)
    #expect(try AppConfiguration.load(from: paths) == config)
    let attributes = try FileManager.default.attributesOfItem(atPath: paths.config.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func existingConfigurationMigratesWithoutLosingDeckOrPreferences() throws {
    let original = Data(#"{"provider":"claude","deck":"Existing deck","autoSave":false,"codexPath":"/custom/codex","claudeModel":"opus"}"#.utf8)
    var config = try JSONDecoder().decode(AppConfiguration.self, from: original)
    #expect(config.deck == "Existing deck")
    #expect(config.provider == .claude)
    #expect(config.model == "opus")
    #expect(config.codexPath == "/custom/codex")
    #expect(config.autoSave == false)
    #expect(config.showInDock == true)
    config.showInDock = false
    config.setModel("custom-gemini", for: .gemini)
    config.setExecutable("/custom/gemini", for: .gemini)
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
    #expect(decoded.executable(for: .gemini) == "/custom/gemini")
}

@Test func authenticationStatusDoesNotExposeAccountDataOrAssumeSuccess() throws {
    let anonymous = ProviderConnections.parseAuthentication(provider: .claude, version: "test",
        result: .init(exitCode: 0, stdout: #"{"loggedIn":false,"email":"private@example.com"}"#, stderr: ""))
    #expect(anonymous.state == .signedOut)
    let connected = ProviderConnections.parseAuthentication(provider: .claude, version: "test",
        result: .init(exitCode: 0, stdout: #"{"loggedIn":true,"authMethod":"claude.ai","email":"private@example.com","apiKey":"secret-test"}"#, stderr: ""))
    #expect(connected.state == .connected)
    let encoded = try jsonString(connected)
    #expect(!encoded.contains("private@example.com"))
    #expect(!encoded.contains("secret-test"))
    let failed = ProviderConnections.parseAuthentication(provider: .codex, version: "test",
        result: .init(exitCode: 1, stdout: "ChatGPT login failed", stderr: ""))
    #expect(failed.state != .connected)
}

@Test func geminiEnvelopeAndToolPolicy() throws {
    let cardJSON = try jsonString(sample)
    let envelope = try JSONSerialization.data(withJSONObject: ["response": "```json\n" + cardJSON + "\n```", "stats": [:]])
    let result = try LocalCLIGenerator.decodeEnvelope(String(decoding: envelope, as: UTF8.self), provider: .gemini)
    #expect(try JSONDecoder().decode(VocabularyCard.self, from: result) == sample)
    #expect(throws: CaptureError.self) { try LocalCLIGenerator.decodeEnvelope(#"{"error":{"message":"auth failed"},"response":"{}"}"#, provider: .gemini) }
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try LocalCLIGenerator.prepareGeminiWorkspace(paths.runtime)
    let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.runtime.appendingPathComponent(".gemini/settings.json"))) as! [String: Any]
    #expect((settings["hooksConfig"] as? [String: Any])?["enabled"] as? Bool == false)
    #expect(((settings["tools"] as? [String: Any])?["core"] as? [String])?.isEmpty == true)
    let policy = try String(contentsOf: paths.runtime.appendingPathComponent("deny-tools.toml"), encoding: .utf8)
    #expect(policy.contains("toolName = \"*\""))
    #expect(policy.contains("decision = \"deny\""))
}

@Test func loginCommandTreatsExecutablePathAsOneArgument() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let fake = paths.root.appendingPathComponent("cli' $(echo NOT_EXECUTED)")
    try Data("#!/bin/sh\nprintf 'official-command:%s' \"$1\"\n".utf8).write(to: fake)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
    var config = AppConfiguration(); config.codexPath = fake.path
    let script = try LoginCommand.write(provider: .codex, config: config, paths: paths)
    let result = try await ProcessRunner.run(executable: "/bin/zsh", arguments: [script.path], directory: paths.runtime, timeout: 3)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("official-command:login"))
    #expect(!result.stdout.contains("NOT_EXECUTED"))
    #expect(!FileManager.default.fileExists(atPath: script.path))
}

@Test func concurrentEnqueueAndLeaseRecovery() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let store1 = try JobStore(paths: paths)
    let store2 = try JobStore(paths: paths)
    let input = try CaptureInput(text: "salient")
    let config = testConfiguration()
    let ids = try await withThrowingTaskGroup(of: String.self) { group in
        for index in 0..<20 {
            group.addTask { try await (index.isMultiple(of: 2) ? store1 : store2).enqueue(input, config: config).id }
        }
        var result: [String] = []
        for try await value in group { result.append(value) }
        return result
    }
    #expect(Set(ids).count == 1)
    #expect(try await store1.list().count == 1)
    let now = Date()
    let claimed = try #require(await store1.claimNext(now: now))
    #expect(try await store2.claimNext(now: now) == nil)
    let recovered = try #require(await store2.claimNext(now: now.addingTimeInterval(601)))
    #expect(claimed.id == recovered.id)
    #expect(recovered.attempts == 2)
}

private actor CountingGenerator: CardGenerating {
    var calls = 0
    func generate(input: CaptureInput, provider: AIProvider, model: String, config: AppConfiguration) async throws -> VocabularyCard {
        calls += 1; return sample
    }
}
private actor OfflineOnceWriter: AnkiWriting {
    var calls = 0
    func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult {
        calls += 1
        if calls == 1 { throw CaptureError.unavailable("Anki offline") }
        return .init(noteID: 12345, duplicate: false)
    }
}
private struct SuccessfulWriter: AnkiWriting {
    func save(card: VocabularyCard, job: CaptureJob) async throws -> AnkiWriteResult { .init(noteID: 9876, duplicate: false) }
}

@Test func ankiRetryPreservesGeneratedCardAcrossRestart() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let config = testConfiguration()
    let store = try JobStore(paths: paths)
    let generator = CountingGenerator()
    let writer = OfflineOnceWriter()
    let job = try await store.enqueue(CaptureInput(text: "salient"), config: config)
    try await QueueWorker(store: store, generator: generator).drain(config: config, writer: writer)
    #expect(try await store.get(job.id)?.status == .waitingForAnki)
    #expect(try await store.get(job.id)?.card == sample)
    let reopened = try JobStore(paths: paths)
    try await reopened.retry(job.id)
    try await QueueWorker(store: reopened, generator: generator).drain(config: config, writer: writer)
    #expect(try await reopened.get(job.id)?.status == .saved)
    #expect(try await reopened.get(job.id)?.noteID == 12345)
    #expect(await generator.calls == 1)
    #expect(await writer.calls == 2)
}

@Test func previewRequiresExplicitRelease() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    var config = testConfiguration(); config.autoSave = false
    let store = try JobStore(paths: paths)
    let generator = CountingGenerator()
    let worker = QueueWorker(store: store, generator: generator)
    let job = try await store.enqueue(CaptureInput(text: "salient"), config: config)
    try await worker.drain(config: config, writer: SuccessfulWriter())
    #expect(try await store.get(job.id)?.status == .review)
    #expect(try await store.claimNext() == nil)
    var edited = sample; edited.meaningZh = "突出的"
    try await store.replaceReviewCard(job.id, card: edited)
    try await store.retry(job.id)
    try await worker.drain(config: config, writer: SuccessfulWriter())
    #expect(try await store.get(job.id)?.status == .saved)
    #expect(try await store.get(job.id)?.card?.meaningZh == "突出的")
    #expect(await generator.calls == 1)
}

@Test func sourceAndAIHTMLAreEscaped() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let job = try await JobStore(paths: paths).enqueue(CaptureInput(text: "salient", context: "<img src=x onerror=alert(1)>", source: "A & B"), config: testConfiguration())
    var card = sample; card.meaningZh = "<script>alert('x')</script>"
    let fields = AnkiClient.noteFields(card: card, job: job)
    #expect(fields["Meaning"]?.contains("<script>") == false)
    #expect(fields["Context"]?.contains("<img") == false)
    #expect(fields["Source"] == "A &amp; B")
    #expect(fields["CaptureKey"] == card.captureKey(deck: job.deck, noteType: job.noteType))
    #expect(card.captureKey(deck: "A", noteType: "N") != card.captureKey(deck: "B", noteType: "N"))
}

@Test func providerInvocationsKeepSelectionOutOfArguments() throws {
    let input = try CaptureInput(text: "in light of")
    let config = testConfiguration()
    for provider in AIProvider.allCases {
        let invocation = try LocalCLIGenerator.invocation(input: input, provider: provider, model: "custom-model",
            config: config, schema: URL(fileURLWithPath: "/tmp/schema.json"), result: URL(fileURLWithPath: "/tmp/result.json"))
        #expect(!invocation.arguments.contains(input.text))
        #expect(invocation.arguments.contains("custom-model"))
        #expect(invocation.prompt.contains("untrusted DATA"))
        #expect(!invocation.arguments.contains("--bare"))
        #expect(!invocation.arguments.contains("--dangerously-skip-permissions"))
    }
}

@Test func processRunnerDoesNotInterpretShellSyntax() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let marker = paths.root.appendingPathComponent("should-not-exist").path
    let argument = "$(touch '\(marker)'); `whoami`"
    let output = try await ProcessRunner.run(executable: "/bin/echo", arguments: [argument], directory: paths.runtime, timeout: 2)
    #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == argument)
    #expect(!FileManager.default.fileExists(atPath: marker))
}

@Test func processTimeoutReturnsWithoutWaitingForLongChild() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let start = Date()
    await #expect(throws: CaptureError.self) {
        try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["10"], directory: paths.runtime, timeout: 0.1)
    }
    #expect(Date().timeIntervalSince(start) < 4)
}

private final class MockAnkiProtocol: URLProtocol, @unchecked Sendable {
    static var existing: [Int64] = []
    static var added = 0
    static var fields: [String: String] = [:]
    static var tags: [String] = []
    static var reps = 0
    static var deleted = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            var requestData = request.httpBody ?? Data()
            if requestData.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count <= 0 { break }
                    requestData.append(buffer, count: count)
                }
            }
            let body = try JSONSerialization.jsonObject(with: requestData) as! [String: Any]
            let params = body["params"] as? [String: Any] ?? [:]
            let result: Any
            switch body["action"] as? String {
            case "deckNames": result = ["Vocabulary"]
            case "modelNames": result = ["Anki Capture"]
            case "modelFieldNames": result = AnkiClient.fields
            case "findNotes": result = Self.existing
            case "addNote":
                Self.added += 1; Self.existing = [1234]
                Self.fields = ((params["note"] as? [String: Any])?["fields"] as? [String: String]) ?? [:]
                Self.tags = ((params["note"] as? [String: Any])?["tags"] as? [String]) ?? []
                result = 1234
            case "notesInfo":
                result = [["noteId": 1234, "tags": Self.tags, "cards": [5678], "fields": Self.fields.mapValues { ["value": $0] }]] as [[String: Any]]
            case "cardsInfo": result = [["reps": Self.reps]]
            case "deleteNotes": Self.deleted += 1; Self.existing = []; result = NSNull()
            default: throw CaptureError.invalid("Unexpected mocked action")
            }
            let data = try JSONSerialization.data(withJSONObject: ["result": result, "error": NSNull()])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@Suite(.serialized) struct AnkiTransportTests {
    @Test func repeatedWriteCreatesOneNote() async throws {
        MockAnkiProtocol.existing = []; MockAnkiProtocol.added = 0
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockAnkiProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let job = try await JobStore(paths: paths).enqueue(CaptureInput(text: "salient"), config: testConfiguration())
        let client = try AnkiClient(config: testConfiguration(), session: session)
        let first = try await client.save(card: sample, job: job)
        let second = try await client.save(card: sample, job: job)
        #expect(first.noteID == 1234)
        #expect(!first.duplicate)
        #expect(second.duplicate)
        #expect(MockAnkiProtocol.added == 1)
        #expect(MockAnkiProtocol.fields["Term"] == "salient")
    }
    @Test func undoDeletesOnlyOwnedUnreviewedNote() async throws {
        MockAnkiProtocol.existing = []; MockAnkiProtocol.reps = 0; MockAnkiProtocol.deleted = 0
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [MockAnkiProtocol.self]
        let session = URLSession(configuration: sessionConfig); defer { session.invalidateAndCancel() }
        let paths = try temporaryPaths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var job = try await JobStore(paths: paths).enqueue(CaptureInput(text: "salient"), config: testConfiguration())
        let client = try AnkiClient(config: testConfiguration(), session: session)
        let result = try await client.save(card: sample, job: job)
        job.noteID = result.noteID; job.card = sample; job.status = .saved
        MockAnkiProtocol.reps = 1
        await #expect(throws: CaptureError.self) { try await client.undo(job) }
        #expect(MockAnkiProtocol.deleted == 0)
        MockAnkiProtocol.reps = 0
        MockAnkiProtocol.tags = []
        await #expect(throws: CaptureError.self) { try await client.undo(job) }
        #expect(MockAnkiProtocol.deleted == 0)
        MockAnkiProtocol.tags = ["anki_capture_id::" + job.id]
        try await client.undo(job)
        #expect(MockAnkiProtocol.deleted == 1)
    }
}
