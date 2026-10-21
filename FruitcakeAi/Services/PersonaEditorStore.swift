import Foundation
import Observation

@MainActor @Observable
final class PersonaEditorStore {
    var items: [PersonaEditorItem] = []
    var personalDefault: PersonaDefault?
    var selectedKey: String?
    var draft = PersonaPersonality.neutral
    private(set) var original = PersonaPersonality.neutral
    var history: [PersonaRevisionRecord] = []
    var hasMoreHistory = false
    var preview: PersonaPromptPreview?
    var models: [PersonaModelOption] = []
    var model = ""
    var recallMemories = false
    var isBusy = false
    var error: String?
    var status: String?
    var isLoaded = false
    private(set) var deletionPreview: PersonaDeletionPreview?
    private var deletionKey: String?

    var selectedItem: PersonaEditorItem? { items.first { $0.id == selectedKey } }
    var isBundled: Bool { selectedItem?.isBundled == true }
    var isArchived: Bool { selectedItem?.archived == true }
    var hasUnsavedChanges: Bool { draft != original }
    var canSave: Bool { !isBusy && !isBundled && !isArchived && draft.validationMessage == nil && (selectedKey == nil || hasUnsavedChanges) }
    var savedReference: PersonaReference? { selectedItem?.reference }
    var isDefault: Bool { savedReference != nil && savedReference == personalDefault?.selection.reference }
    var canTest: Bool { !isBusy && !hasUnsavedChanges && !isArchived && savedReference != nil && !model.isEmpty }

    func startNew() {
        cancelDeletion()
        selectedKey = nil
        draft = .neutral
        original = draft
        history = []
        hasMoreHistory = false
        preview = nil
        status = nil
        error = nil
    }

    func choose(_ item: PersonaEditorItem) {
        cancelDeletion()
        selectedKey = item.id
        draft = item.personality
        original = draft
        history = []
        hasMoreHistory = false
        preview = nil
        error = nil
        status = nil
    }

    func load(_ api: any PersonaEditorTransport) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await fetchCatalog(api)
            if let current = selectedItem { choose(current) }
            else if let first = items.first(where: { $0.id == personalDefault?.selection.persona }) ?? items.first { choose(first) }
            let response: PersonaModelCatalog = try await api.call("/chat/models")
            models = response.models
            if !models.contains(where: { $0.id == model }) { model = models.first?.id ?? "" }
            isLoaded = true
        } catch { self.error = message(error) }
    }

    private func fetchCatalog(_ api: any PersonaEditorTransport) async throws {
        var offset = 0
        var result: [PersonaEditorItem] = []
        while true {
            let page: PersonaCatalog = try await api.call("/personas?limit=100&offset=\(offset)")
            if offset == 0 {
                personalDefault = page.defaultSelection
                result = page.bundled.map { .init(id: $0.persona, definitionId: nil, revision: nil, archived: false, personality: $0.personality) }
            }
            result += page.custom.map { .init(id: $0.persona, definitionId: $0.id, revision: $0.version, archived: $0.archived, personality: $0.personality) }
            if page.custom.count < page.limit { break }
            offset += page.limit
        }
        items = result
    }

    func save(_ api: any PersonaEditorTransport) async {
        guard canSave else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let result: PersonaMutationResult
            if let item = selectedItem, let id = item.definitionId, let version = item.revision {
                result = try await api.call("/personas/\(id)", method: "PUT", body: PersonaRevisionBody(draft: draft, expectedVersion: version))
            } else {
                result = try await api.call("/personas", method: "POST", body: draft)
            }
            // Update local state before reloading so a refresh failure cannot duplicate a successful save.
            let saved = PersonaEditorItem(id: result.persona, definitionId: result.id, revision: result.version, archived: false, personality: draft)
            items.removeAll { $0.id == result.persona }
            items.append(saved)
            choose(saved)
            try await fetchCatalog(api)
            if let refreshed = selectedItem { choose(refreshed) }
            status = "Saved revision \(result.version). Existing chats and defaults keep their selected revision."
        } catch { self.error = message(error) }
    }

    func duplicate(_ api: any PersonaEditorTransport) async {
        guard let item = selectedItem, !isBusy, !item.archived else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let name = String(item.personality.displayName.prefix(93)) + " copy"
            let result: PersonaMutationResult = try await api.call("/personas/duplicate", method: "POST",
                body: PersonaDuplicateBody(persona: item.id, revision: item.revision, displayName: name))
            selectedKey = result.persona
            try await fetchCatalog(api)
            if let refreshed = selectedItem { choose(refreshed) }
            status = "Created an editable copy."
        } catch { self.error = message(error) }
    }

    func setDefault(_ api: any PersonaEditorTransport) async {
        guard let ref = savedReference, let current = personalDefault, !isBusy, !hasUnsavedChanges, !isArchived else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            personalDefault = try await api.call("/personas/default", method: "PUT",
                body: PersonaDefaultBody(persona: ref.persona, revision: ref.revision, expectedVersion: current.version))
            status = "Default updated for new chats. Existing conversations are unchanged."
        } catch { self.error = message(error) }
    }

    func archive(_ api: any PersonaEditorTransport) async {
        guard let item = selectedItem, let id = item.definitionId, let version = item.revision, !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await api.callVoid("/personas/\(id)/archive", method: "POST", body: PersonaVersionBody(expectedVersion: version))
            try await fetchCatalog(api)
            if let refreshed = selectedItem { choose(refreshed) }
            status = "Archived. Existing chats and saved revisions remain available."
        } catch { self.error = message(error) }
    }

    func cancelDeletion() {
        deletionPreview = nil
        deletionKey = nil
    }

    func prepareDeletion(_ api: any PersonaEditorTransport) async {
        guard let item = selectedItem, let id = item.definitionId, !isBusy, !hasUnsavedChanges else { return }
        cancelDeletion()
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let impact: PersonaDeletionPreview = try await api.call("/personas/\(id)/deletion-preview")
            guard selectedKey == item.id else { return }
            guard impact.expectedVersion == item.revision else {
                error = "Persona changed. Reload before deleting."
                return
            }
            deletionKey = item.id
            deletionPreview = impact
        } catch { self.error = message(error) }
    }

    func deletePersona(_ api: any PersonaEditorTransport) async {
        guard let item = selectedItem, let id = item.definitionId, let impact = deletionPreview,
              deletionKey == item.id, !isBusy, !hasUnsavedChanges else { return }
        isBusy = true
        error = nil
        defer { isBusy = false; cancelDeletion() }
        do {
            let result: PersonaDeletionResult = try await api.call("/personas/\(id)", method: "DELETE",
                body: PersonaDeletionBody(expectedVersion: impact.expectedVersion, confirmationToken: impact.confirmationToken))
            // Retire local state before refreshing: deletion may succeed even if the catalog reload fails.
            items.removeAll { $0.id == item.id }
            personalDefault = result.defaultSelection
            if let fallback = items.first(where: { $0.id == result.replacement.persona }) { choose(fallback) }
            else { startNew() }
            status = "Persona deleted. \(result.affectedConversations) conversations now use Personal Assistant. Messages are unchanged."
            try await fetchCatalog(api)
        } catch { self.error = message(error) }
    }

    func showPreview(_ api: any PersonaEditorTransport) async {
        guard !isBusy, draft.validationMessage == nil else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            preview = try await api.call("/personas/preview", method: "POST",
                body: PersonaPreviewBody(draft: isBundled ? nil : draft, reference: isBundled ? savedReference : nil))
        } catch { self.error = message(error) }
    }

    func loadHistory(_ api: any PersonaEditorTransport, before: Int? = nil) async {
        guard let id = selectedItem?.definitionId, !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let suffix = before.map { "?before=\($0)" } ?? ""
            let result: PersonaHistory = try await api.call("/personas/\(id)/revisions\(suffix)")
            history = before == nil ? result.revisions : history + result.revisions
            hasMoreHistory = result.revisions.count == 25
        } catch { self.error = message(error) }
    }

    func upload(_ api: any PersonaEditorTransport, data: Data, filename: String, sheet: Bool) async {
        guard !isBusy, !isBundled, !isArchived else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let asset = try await api.uploadPersonaImage(data, filename: filename)
            var visual = draft.visualIdentity ?? .init()
            if sheet { visual.sheetAssetId = asset.id } else { visual.portraitAssetId = asset.id }
            draft.visualIdentity = visual
            preview = nil
            status = "Reference attached to this draft. Save a revision to keep it with the persona."
        } catch { self.error = message(error) }
    }

    func createTest(_ api: any PersonaEditorTransport) async -> Int? {
        guard canTest, let ref = savedReference else { return nil }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let result: PersonaTestResult = try await api.call("/personas/test-conversations", method: "POST",
                body: PersonaTestBody(reference: ref, llmModel: model, memoryRecallEnabled: recallMemories))
            status = "Created a fresh test chat."
            return result.sessionId
        } catch { self.error = message(error); return nil }
    }

    private func message(_ error: Error) -> String {
        if case APIError.notFound = error {
            return "Persona authoring requires the persona backend branch and migrations 060/061. Your draft is retained."
        }
        return error.localizedDescription
    }
}
