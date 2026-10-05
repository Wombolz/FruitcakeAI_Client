import Foundation

struct ResolvedSetting<Value: Decodable & Equatable>: Decodable, Equatable {
    let value: Value?
    let source: String
}

struct UserAssistantSettings: Decodable, Equatable {
    let publicId: String
    let version: Int
    let defaultChatModel: ResolvedSetting<String>
    let modelProfileId: ResolvedSetting<String>
    let defaultVisionModel: ResolvedSetting<String>
    let visionModelProfileId: ResolvedSetting<String>
    let reasoningEffort: ResolvedSetting<String>
    let chatRoutingPreference: ResolvedSetting<String>
    let timezone: ResolvedSetting<String>
    let activeHoursStart: ResolvedSetting<String>
    let activeHoursEnd: ResolvedSetting<String>
    let notificationsEnabled: ResolvedSetting<Bool>
    let deliveryEnabled: ResolvedSetting<Bool>
    let appearance: ResolvedSetting<String>
    let reduceMotion: ResolvedSetting<Bool>
}

struct UserAssistantSettingsPatch: Encodable {
    var expectedVersion: Int?
    var preferredModelProfileId: String?
    var preferredVisionModelProfileId: String?
    var preferredReasoningEffort: String?
    var chatRoutingPreference: String?
    var timezone: String?
    var activeHoursStart: String?
    var activeHoursEnd: String?
    var notificationsEnabled: Bool?
    var deliveryEnabled: Bool?
    var appearance: String?
    var reduceMotion: Bool?
}

struct ModelCapabilities: Decodable, Hashable {
    let text: Bool
    let vision: Bool
    let tools: Bool
    let thinking: Bool
    let nativeStreaming: Bool
}

struct AssistantModelProfile: Decodable, Identifiable, Hashable {
    let id: String
    let profileId: String
    let modelId: String
    let provider: String
    let label: String
    let displayName: String
    let providerFamily: String
    let enabled: Bool
    let isLocal: Bool
    let capabilities: ModelCapabilities
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String?
    let toolMode: String
    let allowedTools: [String]
    let blockedTools: [String]
    let keepAlive: String?

    var providerLabel: String {
        isLocal ? "Local" : providerFamily.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct AssistantModelListResponse: Decodable {
    let models: [AssistantModelProfile]
}

struct AdminModelProfileListResponse: Decodable {
    let profiles: [AssistantModelProfile]
}

struct AdminModelProfilePatch: Encodable {
    var displayName: String?
    var enabled: Bool?
    var supportsText: Bool?
    var supportsVision: Bool?
    var supportsTools: Bool?
    var supportsThinking: Bool?
    var supportsNativeStreaming: Bool?
    var reasoningEfforts: [String]?
    var defaultReasoningEffort: String?
    var toolMode: String?
    var allowedTools: [String]?
    var blockedTools: [String]?
    var keepAlive: String?
}

struct UserIntegrationListResponse: Decodable {
    let integrations: [UserIntegrationSummary]
}

struct UserIntegrationSummary: Decodable, Identifiable, Equatable {
    struct Configuration: Decodable, Equatable {
        let url: String?
        let username: String?
        let defaultCalendar: String?
    }

    let id: String
    let provider: String
    let service: String
    let status: String
    let accountIdentifier: String?
    let scopes: [String]
    let config: Configuration
    let expiresAt: Date?
    let lastSuccessAt: Date?
    let errorClass: String?
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date

    var isConnected: Bool { status == "connected" }
}

struct AppleCalendarConnectionRequest: Encodable {
    let username: String
    let appPassword: String
    let url: String
    let defaultCalendar: String
}

struct GoogleCalendarAuthorizationResponse: Decodable {
    let authorizationUrl: URL
}

struct GoogleCalendarCallbackRequest: Encodable {
    let code: String
    let state: String
    let codeVerifier: String
}
