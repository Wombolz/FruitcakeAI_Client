import Foundation
import Testing
#if os(macOS)
import AppKit
import SwiftUI
#endif
@testable import FruitcakeAi

@MainActor private final class PersonaTransportFixture: PersonaEditorTransport {
    struct Call { let path: String; let method: String; let body: [String: Any] }
    var responses: [Result<Data, Error>] = []
    var calls: [Call] = []

    func send<T: Decodable>(_ path: String, method: String, body: (any Encodable)?) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encoded = try body.map { try encoder.encode($0) }
        let values = try encoded.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        calls.append(.init(path: path, method: method, body: values ?? [:]))
        let data = try responses.removeFirst().get()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    func sendVoid(_ path: String, method: String, body: (any Encodable)?) async throws {
        calls.append(.init(path: path, method: method, body: [:]))
        _ = try responses.removeFirst().get()
    }
    func uploadPersonaImage(_ data: Data, filename: String) async throws -> PersonaImageAsset {
        try await send("/personas/assets", method: "POST", body: nil)
    }
}

@Suite @MainActor struct PersonaEditorStoreTests {
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func style(_ value: PersonaPersonality) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }
    private func prepared() -> PersonaEditorStore {
        let store = PersonaEditorStore()
        let item = PersonaEditorItem(id: "custom:fixture", definitionId: "fixture", revision: 2, archived: false, personality: .neutral)
        store.items = [item]
        store.choose(item)
        store.model = "fixture-model"
        return store
    }
    private func catalog(version: Int, personality: PersonaPersonality) throws -> Data {
        let preset = try style(.neutral)
        return try data(["bundled": [], "custom": [["id": "fixture", "persona": "custom:fixture", "version": version,
            "archived": false, "personality": try style(personality)]], "offset": 0, "limit": 100,
            "default": ["version": 1, "selection": ["persona": "neutral", "revision": NSNull(), "personality": preset]]])
    }

    @Test func staleSavePreservesDraftAndRevisionInsteadOfReloadingOverIt() async throws {
        let store = prepared()
        store.draft.tone = "formal"
        let transport = PersonaTransportFixture()
        transport.responses = [.failure(APIError.httpError(409, "Persona changed; reload before saving."))]
        await store.save(transport)
        #expect(store.draft.tone == "formal" && store.hasUnsavedChanges)
        #expect(store.savedReference?.revision == 2 && store.error != nil && !store.isBusy)
        #expect(transport.calls.count == 1 && transport.calls[0].path == "/personas/fixture")
        #expect(transport.calls[0].body["expected_version"] as? Int == 2)
    }

    @Test func successfulSaveAdvancesOnlyEditedHeadNotDefaultOrExistingChat() async throws {
        let store = prepared()
        store.draft.tone = "formal"
        let expected = store.draft
        let transport = PersonaTransportFixture()
        transport.responses = [.success(try data(["id": "fixture", "persona": "custom:fixture", "version": 3, "archived": false])),
                               .success(try catalog(version: 3, personality: expected))]
        await store.save(transport)
        #expect(store.savedReference?.revision == 3 && !store.hasUnsavedChanges && !store.canSave)
        #expect(store.personalDefault?.selection.persona == "neutral")
        #expect(store.status?.contains("Saved revision 3") == true)
        #expect(!transport.calls.contains { $0.path == "/personas/default" || $0.path.contains("/chat/sessions/") })
    }

    @Test func postSaveRefreshFailureDoesNotOfferAnotherCreate() async throws {
        let store = PersonaEditorStore()
        let transport = PersonaTransportFixture()
        transport.responses = [.success(try data(["id": "new-id", "persona": "custom:new-id", "version": 1, "archived": false])),
                               .failure(APIError.httpError(503, "Refresh unavailable"))]
        await store.save(transport)
        #expect(store.savedReference?.persona == "custom:new-id" && store.savedReference?.revision == 1)
        #expect(!store.canSave && !store.hasUnsavedChanges && store.error != nil)
        await store.save(transport)
        #expect(transport.calls.count == 2)
    }

    @Test func attachedTurnaroundChangesDraftOnlyUntilSaved() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        let id = "11111111-1111-1111-1111-111111111111"
        transport.responses = [.success(try data(["id": id, "sha256": String(repeating: "a", count: 64), "width": 10, "height": 10, "size_bytes": 100]))]
        await store.upload(transport, data: Data([1]), filename: "turnaround.png", sheet: true)
        #expect(store.draft.visualIdentity?.sheetAssetId == id && store.hasUnsavedChanges)
        #expect(store.original.visualIdentity?.sheetAssetId == nil && store.savedReference?.revision == 2)
        #expect(!store.canTest && transport.calls.count == 1)
    }

    @Test func testConversationUsesSavedReferenceExplicitModelAndRecallChoice() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        transport.responses = [.success(try data(["session_id": 31]))]
        let id = await store.createTest(transport)
        #expect(id == 31 && transport.calls.count == 1)
        let sent = transport.calls[0]
        #expect(sent.path == "/personas/test-conversations")
        #expect(sent.body["llm_model"] as? String == "fixture-model")
        #expect(sent.body["memory_recall_enabled"] as? Bool == false)
        let ref = try #require(sent.body["reference"] as? [String: Any])
        #expect(ref["revision"] as? Int == 2)
        #expect(sent.body["allowed_tools"] == nil && sent.body["draft"] == nil)
    }

    private func deletionImpact(version: Int = 2) throws -> Data {
        try data(["expected_version": version, "affected_conversations": 4, "resets_default": true,
                  "confirmation_token": String(repeating: "a", count: 64)])
    }

    private func deletionResult() throws -> Data {
        let assistant: [String: Any] = ["persona": "family_assistant", "revision": NSNull(), "personality": try style(.neutral)]
        return try data(["affected_conversations": 4, "resets_default": true, "replacement": assistant,
                         "default": ["version": 3, "selection": assistant]])
    }

    @Test func deletionRequiresPreviewAndExplicitConfirmationAndRecoversFromRefreshFailure() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        await store.deletePersona(transport)
        #expect(transport.calls.isEmpty)
        transport.responses = [.success(try deletionImpact()), .success(try deletionResult()),
                               .failure(APIError.httpError(503, "Catalog unavailable"))]
        await store.prepareDeletion(transport)
        #expect(store.deletionPreview?.affectedConversations == 4 && store.deletionPreview?.resetsDefault == true)
        #expect(transport.calls.count == 1 && transport.calls[0].method == "GET")
        await store.deletePersona(transport)
        #expect(transport.calls[1].method == "DELETE" && transport.calls[1].path == "/personas/fixture")
        #expect(transport.calls[1].body["expected_version"] as? Int == 2)
        #expect(transport.calls[1].body["confirmation_token"] as? String == String(repeating: "a", count: 64))
        #expect(!store.items.contains { $0.id == "custom:fixture" })
        #expect(store.history.isEmpty && store.preview == nil && store.deletionPreview == nil)
        #expect(store.personalDefault?.selection.persona == "family_assistant" && store.personalDefault?.version == 3)
        #expect(store.status?.contains("Persona deleted") == true && store.error != nil)
        await store.deletePersona(transport)
        #expect(transport.calls.count == 3)
    }

    @Test func failedDeletionPreservesPersonaButRequiresFreshConfirmation() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        transport.responses = [.success(try deletionImpact()), .failure(APIError.httpError(409, "Finish the active chat."))]
        await store.prepareDeletion(transport)
        await store.deletePersona(transport)
        #expect(store.savedReference?.persona == "custom:fixture" && store.items.count == 1)
        #expect(store.error != nil && store.deletionPreview == nil && !store.isBusy)
        await store.deletePersona(transport)
        #expect(transport.calls.count == 2)
    }

    @Test func changedSelectionOrRevisionInvalidatesDeletionConfirmation() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        transport.responses = [.success(try deletionImpact())]
        await store.prepareDeletion(transport)
        store.startNew()
        await store.deletePersona(transport)
        #expect(transport.calls.count == 1 && store.deletionPreview == nil)
        let item = PersonaEditorItem(id: "custom:fixture", definitionId: "fixture", revision: 1, archived: false, personality: .neutral)
        store.items = [item]
        store.choose(item)
        transport.responses = [.success(try deletionImpact())]
        await store.prepareDeletion(transport)
        #expect(store.deletionPreview == nil && store.error?.contains("Reload") == true)
    }

    @Test func deletionDoesNotDiscardUnsavedDraftOrAllowBuiltInDeletion() async throws {
        let store = prepared()
        let transport = PersonaTransportFixture()
        store.draft.tone = "Unsaved"
        await store.prepareDeletion(transport)
        #expect(transport.calls.isEmpty && store.hasUnsavedChanges)
        let builtIn = PersonaEditorItem(id: "neutral", definitionId: nil, revision: nil, archived: false, personality: .neutral)
        store.items = [builtIn]
        store.choose(builtIn)
        await store.prepareDeletion(transport)
        #expect(transport.calls.isEmpty && store.deletionPreview == nil)
    }

    #if os(macOS)
    @Test(arguments: [CGFloat(375), CGFloat(1200)])
    func rendersEditorAtCompactAndWideWidthsWithoutNetwork(width: CGFloat) throws {
        let store = prepared()
        store.isLoaded = true
        store.models = [.init(id: "fixture-model", label: "Fixture model")]
        let root = PersonaPicker(embedded: true, store: store).environment(AuthManager()).frame(width: width, height: 800)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        host.layoutSubtreeIfNeeded()
        let pdf = host.dataWithPDF(inside: host.bounds)
        #expect(!pdf.isEmpty && host.frame.width == width)
    }
    #endif
}
