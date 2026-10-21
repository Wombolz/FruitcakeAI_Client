import Foundation
import Testing
@testable import FruitcakeAi

@Suite @MainActor struct PersonaAuthoringTests {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func object(_ body: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
    }

    @Test func neutralDraftHasNoInheritedPersonalityOrAuthorityFields() throws {
        let draft = PersonaPersonality.neutral
        #expect(draft.personalityMode == "neutral" && draft.identity == "" && draft.tone == "")
        #expect(draft.validationMessage == nil)
        let value = try object(draft)
        #expect(value["blocked_tools"] == nil && value["library_scopes"] == nil && value["content_filter"] == nil)
        #expect(value["visual_identity"] != nil)
    }

    @Test func revisionRequestFlattensDraftAndSendsOptimisticVersion() throws {
        let value = try object(PersonaRevisionBody(draft: .neutral, expectedVersion: 7))
        #expect(value["expected_version"] as? Int == 7)
        #expect(value["display_name"] as? String == "New persona")
        #expect(value["draft"] == nil)
    }

    @Test func explicitEmptyAndInheritedFieldsRemainDifferentOnWire() throws {
        var inherited = PersonaPersonality.neutral
        inherited.personalityMode = "default"
        inherited.identity = nil
        inherited.tone = nil
        let empty = try object(PersonaPersonality.neutral)
        let base = try object(inherited)
        #expect(empty["identity"] as? String == "" && empty["tone"] as? String == "")
        #expect(base["identity"] == nil && base["tone"] == nil)
    }

    @Test func catalogAndPinnedOlderRevisionDecodeWithoutInventingUpdates() throws {
        let json = #"{"bundled":[{"persona":"neutral","revision":null,"personality":{"display_name":"Neutral","description":"","personality_mode":"neutral","identity":"","tone":"","behavior_instructions":[]}}],"custom":[],"offset":0,"limit":100,"default":{"selection":{"persona":"custom:fixture","revision":1,"personality":{"display_name":"Old Name","description":"","personality_mode":"neutral","identity":"","tone":"","behavior_instructions":[]}},"version":4}}"#
        let catalog = try decoder().decode(PersonaCatalog.self, from: Data(json.utf8))
        #expect(catalog.bundled[0].personality.visualIdentity == nil)
        #expect(catalog.defaultSelection.selection.revision == 1 && catalog.defaultSelection.version == 4)
        #expect(catalog.defaultSelection.selection.reference == PersonaReference(persona: "custom:fixture", revision: 1))
    }

    @Test func savedPersonaImagesAreReferencesNotInlinePromptOrFilesystemPaths() throws {
        var draft = PersonaPersonality.neutral
        draft.visualIdentity = .init(portraitAssetId: "11111111-1111-1111-1111-111111111111", sheetAssetId: nil)
        let value = try object(draft)
        let visual = try #require(value["visual_identity"] as? [String: Any])
        #expect(visual["portrait_asset_id"] as? String == "11111111-1111-1111-1111-111111111111")
        #expect(visual["data"] == nil && visual["path"] == nil)
    }

    @Test func editorStateProtectsBundledAndUnsavedTestOrDefaultActions() {
        let store = PersonaEditorStore()
        let bundled = PersonaEditorItem(id: "neutral", definitionId: nil, revision: nil, archived: false, personality: .neutral)
        store.items = [bundled]
        store.choose(bundled)
        store.model = "test-model"
        #expect(!store.canSave && store.canTest && !store.hasUnsavedChanges)
        let custom = PersonaEditorItem(id: "custom:fixture", definitionId: "fixture", revision: 3, archived: false, personality: .neutral)
        store.items.append(custom)
        store.choose(custom)
        #expect(store.canTest && !store.canSave)
        store.draft.tone = "formal"
        #expect(store.hasUnsavedChanges && store.canSave && !store.canTest)
        store.isBusy = true
        #expect(!store.canSave && !store.canTest)
        store.isBusy = false
        store.startNew()
        #expect(store.canSave && !store.canTest && store.savedReference == nil)
    }

    @Test func archivedAndOversizedDraftsCannotBeSavedOrTested() {
        let store = PersonaEditorStore()
        let archived = PersonaEditorItem(id: "custom:old", definitionId: "old", revision: 1, archived: true, personality: .neutral)
        store.items = [archived]
        store.choose(archived)
        store.model = "model"
        #expect(!store.canSave && !store.canTest)
        var draft = PersonaPersonality.neutral
        draft.behaviorInstructions = Array(repeating: String(repeating: "a", count: 1000), count: 24)
        #expect(draft.validationMessage != nil)
        draft = .neutral
        draft.displayName = "  "
        #expect(draft.validationMessage != nil)
        draft.displayName = String(repeating: "e\u{301}", count: 60)
        #expect(draft.validationMessage != nil) // 120 code points, matching backend limits
    }

    @Test func previewAndTestBodiesKeepRecallSeparateFromToolPermissions() throws {
        let ref = PersonaReference(persona: "neutral", revision: nil)
        let value = try object(PersonaTestBody(reference: ref, llmModel: "model", memoryRecallEnabled: false))
        #expect(value["memory_recall_enabled"] as? Bool == false)
        #expect(value["blocked_tools"] == nil && value["allowed_tools"] == nil)
        let preview = try object(PersonaPreviewBody(draft: .neutral, reference: nil))
        #expect(preview["draft"] != nil && preview["reference"] == nil)
    }
}
