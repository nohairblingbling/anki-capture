import Foundation
import Testing
@testable import CaptureCore

private final class DeckProtocol: URLProtocol, @unchecked Sendable {
    enum Mode { case normal, apiError, offline, invalidID, missingDeck }
    static var mode = Mode.normal
    static var names: [String: Int64] = [:]
    static var requestedNames: [String] = []
    static var requests = 0
    static var canonicalName: String?
    static func reset() {
        mode = .normal; names = [:]; requestedNames = []; requests = 0; canonicalName = nil
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests += 1
        if Self.mode == .offline { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        do {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var result: Any = NSNull()
            var error: Any = NSNull()
            switch body["action"] as? String {
            case "createDeck":
                let name = (body["params"] as! [String: Any])["deck"] as! String
                Self.requestedNames.append(name)
                if Self.mode == .apiError { error = "Test creation failure" }
                else if Self.mode == .invalidID { result = 0 }
                else {
                    let canonical = Self.canonicalName ?? name
                    let id = Self.names[canonical] ?? Int64(7000 + Self.names.count)
                    if Self.mode != .missingDeck { Self.names[canonical] = id }
                    result = id
                }
            case "deckNamesAndIds": result = Self.names
            default: throw CaptureError.invalid("Unexpected deck API call")
            }
            let response = try JSONSerialization.data(withJSONObject: ["result": result, "error": error])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@Suite(.serialized) struct DeckCreationTests {
    private func client() throws -> (AnkiClient, URLSession) {
        DeckProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeckProtocol.self]
        let session = URLSession(configuration: config)
        return (try AnkiClient(config: AppConfiguration(), session: session), session)
    }

    @Test func invalidNamesNeverReachAnki() async throws {
        let (client, session) = try client(); defer { session.invalidateAndCancel() }
        for name in ["", "   ", "Parent::::Child", "Parent::", "::Child", "A\nB", "A\u{0}B", String(repeating: "x", count: 201)] {
            await #expect(throws: CaptureError.self) { try await client.createDeck(named: name) }
        }
        #expect(DeckProtocol.requests == 0)
    }

    @Test func multilingualSubdeckCreationIsIdempotent() async throws {
        let (client, session) = try client(); defer { session.invalidateAndCancel() }
        let first = try await client.createDeck(named: "  日本語 :: 読書  ")
        let second = try await client.createDeck(named: "日本語::読書")
        #expect(first == second)
        #expect(first.name == "日本語::読書")
        #expect(DeckProtocol.names.count == 1)
        #expect(DeckProtocol.requestedNames == ["日本語::読書", "日本語::読書"])
        #expect(try AnkiClient.validatedDeckName(" Reading & notes 📚 ") == "Reading & notes 📚")
    }

    @Test func selectionUsesCanonicalNameReturnedByAnki() async throws {
        let (client, session) = try client(); defer { session.invalidateAndCancel() }
        DeckProtocol.canonicalName = "English"
        let deck = try await client.createDeck(named: "english")
        #expect(deck.name == "English")
        #expect(deck.id == 7000)
    }

    @Test func failedOrInvalidCreationIsNotReportedAsSuccess() async throws {
        let (client, session) = try client(); defer { session.invalidateAndCancel() }
        for mode in [DeckProtocol.Mode.apiError, .invalidID, .missingDeck] {
            DeckProtocol.mode = mode
            await #expect(throws: CaptureError.self) { try await client.createDeck(named: "Test") }
            #expect(DeckProtocol.names.isEmpty)
        }
    }

    @Test func offlineCreationReturnsRecoverableError() async throws {
        let (client, session) = try client(); defer { session.invalidateAndCancel() }
        DeckProtocol.mode = .offline
        do { _ = try await client.createDeck(named: "Test"); Issue.record("Expected connection failure") }
        catch CaptureError.unavailable { }
        catch { Issue.record("Expected a recoverable Anki connection error") }
        #expect(DeckProtocol.names.isEmpty)
    }
}
