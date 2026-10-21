import Foundation

struct PersonaVisualIdentity: Codable, Equatable {
    var portraitAssetId: String?
    var sheetAssetId: String?
}

struct PersonaPersonality: Codable, Equatable {
    var displayName: String
    var description: String
    var personalityMode: String
    var identity: String?
    var tone: String?
    var behaviorInstructions: [String]
    var visualIdentity: PersonaVisualIdentity?

    static var neutral: Self {
        .init(displayName: "New persona", description: "", personalityMode: "neutral", identity: "", tone: "",
              behaviorInstructions: [], visualIdentity: .init())
    }

    var validationMessage: String? {
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName != displayName.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "Enter a name without leading or trailing spaces."
        }
        if displayName.unicodeScalars.count > 100 || description.unicodeScalars.count > 1000 || (identity?.unicodeScalars.count ?? 0) > 2000 || (tone?.unicodeScalars.count ?? 0) > 300 {
            return "Name, description, identity or tone exceeds its character limit."
        }
        if behaviorInstructions.count > 24 || behaviorInstructions.contains(where: { $0.unicodeScalars.count > 1000 }) {
            return "Use at most 24 instructions, each up to 1000 characters."
        }
        let text = [displayName, description, identity ?? "", tone ?? ""] + behaviorInstructions
        if text.reduce(0, { $0 + $1.utf8.count }) > 16384 { return "Persona text exceeds 16 KiB." }
        if text.contains(where: { $0.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" && $0 != "\t" }) }) {
            return "Remove unsupported control characters."
        }
        return nil
    }
}

struct PersonaReference: Codable, Equatable {
    let persona: String
    let revision: Int?
}

struct PersonaSnapshot: Decodable, Equatable {
    let persona: String
    let revision: Int?
    let personality: PersonaPersonality
    var reference: PersonaReference { .init(persona: persona, revision: revision) }
}

struct PersonaDefault: Decodable {
    let selection: PersonaSnapshot
    let version: Int
}

struct PersonaDefinitionRecord: Decodable, Identifiable {
    let id: String
    let persona: String
    let version: Int
    let archived: Bool
    let personality: PersonaPersonality
}

struct PersonaCatalog: Decodable {
    let bundled: [PersonaSnapshot]
    let custom: [PersonaDefinitionRecord]
    let offset: Int
    let limit: Int
    let defaultSelection: PersonaDefault
    enum CodingKeys: String, CodingKey {
        case bundled, custom, offset, limit
        case defaultSelection = "default"
    }
}

struct PersonaMutationResult: Decodable {
    let id: String
    let persona: String
    let version: Int
    let archived: Bool
}

struct PersonaRevisionRecord: Decodable, Identifiable {
    let version: Int
    let personality: PersonaPersonality
    var id: Int { version }
}

struct PersonaHistory: Decodable { let revisions: [PersonaRevisionRecord] }
struct PersonaPromptLayer: Decodable, Identifiable {
    let source: String
    let content: String
    var id: String { source }
    var title: String { source.replacingOccurrences(of: "_", with: " ").capitalized }
}
struct PersonaPromptPreview: Decodable {
    let layers: [PersonaPromptLayer]
    let tools: [String]
    let blockedTools: [String]
    let contentFilter: String
    let exclusions: [String]
    let visualGenerationAvailable: Bool
}
struct PersonaImageAsset: Decodable {
    let id: String
    let sha256: String
    let width: Int
    let height: Int
    let sizeBytes: Int
}
struct PersonaTestOptions: Decodable { let memoryRecallEnabled: Bool }
struct PersonaSessionSelection: Decodable {
    let selection: PersonaSnapshot
    let version: Int
    let updateAvailable: Bool
    let archived: Bool
    let testOptions: PersonaTestOptions?
}
struct PersonaTestResult: Decodable { let sessionId: Int }
struct PersonaModelOption: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
}
struct PersonaModelCatalog: Decodable { let models: [PersonaModelOption] }

struct PersonaRevisionBody: Encodable {
    let draft: PersonaPersonality
    let expectedVersion: Int
    func encode(to encoder: Encoder) throws {
        try draft.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expectedVersion, forKey: .expectedVersion)
    }
    private enum CodingKeys: String, CodingKey { case expectedVersion }
}
struct PersonaDefaultBody: Encodable {
    let persona: String
    let revision: Int?
    let expectedVersion: Int
}
struct PersonaSessionBody: Encodable {
    let persona: String
    let revision: Int?
    let expectedVersion: Int?
}
struct PersonaVersionBody: Encodable { let expectedVersion: Int }
struct PersonaDeletionPreview: Decodable {
    let expectedVersion: Int
    let affectedConversations: Int
    let resetsDefault: Bool
    let confirmationToken: String
}
struct PersonaDeletionBody: Encodable {
    let expectedVersion: Int
    let confirmationToken: String
}
struct PersonaDeletionResult: Decodable {
    let affectedConversations: Int
    let resetsDefault: Bool
    let replacement: PersonaSnapshot
    let defaultSelection: PersonaDefault
    enum CodingKeys: String, CodingKey {
        case affectedConversations, resetsDefault, replacement
        case defaultSelection = "default"
    }
}
struct PersonaPreviewBody: Encodable {
    let draft: PersonaPersonality?
    let reference: PersonaReference?
}
struct PersonaTestBody: Encodable {
    let reference: PersonaReference
    let llmModel: String
    let memoryRecallEnabled: Bool
}
struct PersonaDuplicateBody: Encodable {
    let persona: String
    let revision: Int?
    let displayName: String
}

struct PersonaEditorItem: Identifiable {
    let id: String
    let definitionId: String?
    let revision: Int?
    let archived: Bool
    let personality: PersonaPersonality
    var isBundled: Bool { definitionId == nil }
    var reference: PersonaReference { .init(persona: id, revision: revision) }
}
