//
//  APIClient.swift
//  FruitcakeAi
//
//  URLSession wrapper for the FruitcakeAI Python backend REST API.
//  Injects Authorization: Bearer on every request and maps HTTP errors
//  to typed Swift errors. All methods are async and throw APIError.
//

import Foundation

struct WorkspaceUploadResponse: Decodable, Hashable {
    let path: String
    let filename: String
    let storedFilename: String
    let mediaType: String
    let sizeBytes: Int
    let isImage: Bool
}

struct MCPAppResourceResponse: Decodable, Hashable {
    let server: String
    let uri: String
    let mimeType: String
    let html: String
}

struct MCPAppToolCallRequest: Encodable {
    let server: String
    let resourceURI: String
    let tool: String
    let arguments: JSONValue
}

struct MCPAppToolCallResponse: Decodable {
    let state: String
    let server: String?
    let resourceURI: String?
    let tool: String?
    let result: JSONValue?
    let approval: MCPAppToolApproval?

    private enum CodingKeys: String, CodingKey {
        case state, server, tool, result, approval
        // The shared decoder normalizes resource_uri to resourceUri first.
        case resourceURI = "resourceUri"
    }
}

struct MCPAppToolApproval: Decodable {
    let id: Int
    let server: String
    let resourceURI: String
    let tool: String
    let title: String
    let reason: String
    let arguments: JSONValue
    let destructive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, server, tool, title, reason, arguments, destructive
        case resourceURI = "resourceUri"
    }
}

private struct MCPAppToolApprovalDecision: Encodable {
    let approved: Bool
}

@MainActor
final class APIClient {

    private let authManager: AuthManager

    private var baseURL: URL? { authManager.serverURL }

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Generic JSON request

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 15
    ) async throws -> T {
        let req = try await buildRequest(path, method: method, body: body, timeout: timeout)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response, data: data)
        return try decode(T.self, from: data)
    }

    // MARK: - Void request (no response body expected)

    func requestVoid(
        _ path: String,
        method: String,
        body: (any Encodable)? = nil
    ) async throws {
        let req = try await buildRequest(path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response, data: data)
    }

    // MARK: - Multipart file upload

    func upload(
        _ path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fields: [String: String] = [:]
    ) async throws -> Data {
        let url = try resolvedURL(for: path)

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(try authManager.token())",
                     forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        var body = Data()
        for (key, value) in fields {
            body.appendMultipartField(name: key, value: value, boundary: boundary)
        }
        body.appendMultipartFile(name: "file", fileName: fileName,
                                 mimeType: mimeType, data: fileData,
                                 boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response, data: data)
        return data
    }

    func uploadWorkspaceFile(
        fileData: Data,
        fileName: String,
        mimeType: String,
        targetDir: String = "uploads/chat"
    ) async throws -> WorkspaceUploadResponse {
        let data = try await upload(
            "/workspace/uploads",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            fields: ["target_dir": targetDir]
        )
        return try decode(WorkspaceUploadResponse.self, from: data)
    }

    func fetchMCPAppResource(server: String, uri: String) async throws -> MCPAppResourceResponse {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "server", value: server),
            URLQueryItem(name: "uri", value: uri),
        ]
        guard let query = components.percentEncodedQuery else {
            throw APIError.invalidResponse
        }
        return try await request(
            "/artifacts/mcp-app-resource?\(query)",
            timeout: 30
        )
    }

    func callMCPAppTool(
        server: String,
        resourceURI: String,
        tool: String,
        arguments: JSONValue
    ) async throws -> MCPAppToolCallResponse {
        try await request(
            "/artifacts/mcp-app-tool",
            method: "POST",
            body: MCPAppToolCallRequest(
                server: server,
                resourceURI: resourceURI,
                tool: tool,
                arguments: arguments
            ),
            timeout: 45
        )
    }

    func resolveMCPAppToolApproval(
        approvalID: Int,
        approved: Bool
    ) async throws -> MCPAppToolCallResponse {
        try await request(
            "/artifacts/mcp-app-tool/\(approvalID)/approval",
            method: "POST",
            body: MCPAppToolApprovalDecision(approved: approved),
            timeout: 60
        )
    }

    // MARK: - Private helpers

    private func buildRequest(
        _ path: String,
        method: String,
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 15
    ) async throws -> URLRequest {
        var req = URLRequest(url: try resolvedURL(for: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(try authManager.token())",
                     forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    private func resolvedURL(for path: String) throws -> URL {
        guard let baseURL else { throw APIError.noServerConfigured }

        let rawPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let components = URLComponents(string: rawPath) else {
            throw APIError.invalidResponse
        }

        var url = baseURL
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleanPath.isEmpty {
            url.appendPathComponent(cleanPath)
        }
        if let query = components.percentEncodedQuery, !query.isEmpty {
            var resolved = URLComponents(url: url, resolvingAgainstBaseURL: false)
            resolved?.percentEncodedQuery = query
            if let finalURL = resolved?.url {
                return finalURL
            }
        }
        return url
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let message = data.flatMap { extractErrorMessage(from: $0) }
        switch http.statusCode {
        case 200...299: break
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 500...599: throw APIError.serverError(http.statusCode, message)
        default: throw APIError.httpError(http.statusCode, message)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
            if let error = object["error"] as? String, !error.isEmpty {
                return error
            }
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFractional.date(from: s) { return d }

            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let d = withoutFractional.date(from: s) { return d }

            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "Cannot decode date: \(s)"))
        }
        return try decoder.decode(type, from: data)
    }

    // MARK: - Tasks (Phase 4)

    func fetchTasks() async throws -> [TaskSummary] {
        try await request("/tasks")
    }

    func fetchTask(_ id: Int) async throws -> TaskSummary {
        try await request("/tasks/\(id)")
    }

    func fetchTaskSteps(_ id: Int) async throws -> [TaskStepSummary] {
        try await request("/tasks/\(id)/steps")
    }

    func createTask(_ req: CreateTaskRequest) async throws -> TaskSummary {
        try await request("/tasks", method: "POST", body: req)
    }

    func updateTask(_ id: Int, _ req: TaskUpdateRequest) async throws -> TaskSummary {
        try await request("/tasks/\(id)", method: "PATCH", body: req)
    }

    func updateTaskModelOverride(_ id: Int, llmModelOverride: String?) async throws -> TaskSummary {
        try await request(
            "/tasks/\(id)",
            method: "PATCH",
            body: TaskModelOverridePatch(llmModelOverride: llmModelOverride)
        )
    }

    func fetchLinkedSources() async throws -> [LinkedSourceSummary] {
        try await request("/library/sources")
    }

    func linkFileSource(path: String, scope: String) async throws -> LinkedSourceResponse {
        try await request(
            "/library/link-file",
            method: "POST",
            body: LinkSourceBody(path: path, scope: scope, excludedPaths: [])
        )
    }

    func linkFolderSource(path: String, scope: String, excludedPaths: [String]) async throws -> LinkedSourceResponse {
        try await request(
            "/library/link-folder",
            method: "POST",
            body: LinkSourceBody(path: path, scope: scope, excludedPaths: excludedPaths)
        )
    }

    func rescanLinkedSource(_ id: Int) async throws -> LinkedSourceResponse {
        try await request("/library/sources/\(id)/rescan", method: "POST")
    }

    func fetchLinkedSource(_ id: Int) async throws -> LinkedSourceDetailResponse {
        try await request("/library/sources/\(id)")
    }

    func updateLinkedSourceExclusions(_ id: Int, excludedPaths: [String]) async throws -> LinkedSourceDetailResponse {
        try await request(
            "/library/sources/\(id)",
            method: "PATCH",
            body: LinkedSourceExclusionBody(excludedPaths: excludedPaths)
        )
    }

    func approveTask(_ id: Int, approved: Bool) async throws {
        try await buildAndSendVoid("/tasks/\(id)", method: "PATCH",
                                   body: ApproveBody(approved: approved))
    }

    func deleteTask(_ id: Int) async throws {
        try await requestVoid("/tasks/\(id)", method: "DELETE")
    }

    func runTask(_ id: Int) async throws {
        try await requestVoid("/tasks/\(id)/run", method: "POST")
    }

    func stopTask(_ id: Int) async throws {
        try await requestVoid("/tasks/\(id)/stop", method: "POST")
    }

    func resetTask(_ id: Int) async throws {
        try await requestVoid("/tasks/\(id)/reset", method: "POST")
    }

    func duplicateTaskDraft(_ id: Int) async throws -> DuplicateTaskDraftResponse {
        try await request("/tasks/\(id)/duplicate-draft", method: "POST")
    }

    func acceptTaskDraft(messageId: Int, existingTaskId: Int? = nil) async throws -> AcceptTaskDraftResponse {
        struct AcceptDraftBody: Encodable {
            let existingTaskId: Int?
        }
        return try await request(
            "/chat/messages/\(messageId)/task-draft/accept",
            method: "POST",
            body: AcceptDraftBody(existingTaskId: existingTaskId)
        )
    }

    func denyTaskDraft(messageId: Int) async throws -> DenyTaskDraftResponse {
        try await request("/chat/messages/\(messageId)/task-draft/deny", method: "POST")
    }

    func exportTaskResult(
        _ id: Int,
        path: String,
        artifactType: String = "final_output",
        overwrite: Bool = true
    ) async throws -> TaskResultExportResponse {
        try await request(
            "/tasks/\(id)/export-result-file",
            method: "POST",
            body: TaskResultExportBody(path: path, artifactType: artifactType, overwrite: overwrite)
        )
    }

    func ensureAgentInstances() async throws -> [AgentInstanceSummary] {
        try await request("/tasks/agent-instances/ensure-defaults", method: "POST")
    }

    func fetchAgentInstances() async throws -> [AgentInstanceSummary] {
        try await request("/tasks/agent-instances")
    }

    func createAgentInstance(_ requestBody: AgentInstanceCreateRequest) async throws -> AgentInstanceSummary {
        try await request("/tasks/agent-instances", method: "POST", body: requestBody)
    }

    func updateAgentInstance(_ instanceID: Int, patch: AgentInstanceUpdateRequest) async throws -> AgentInstanceSummary {
        try await request("/tasks/agent-instances/\(instanceID)", method: "PATCH", body: patch)
    }

    func reconcileAgentInstance(_ instanceID: Int, recreateMissing: Bool = true) async throws -> AgentInstanceSummary {
        try await request(
            "/tasks/agent-instances/\(instanceID)/reconcile",
            method: "POST",
            body: AgentInstanceReconcileRequest(recreateMissing: recreateMissing)
        )
    }

    func fetchAgentPresetCategories() async throws -> AgentPresetCategoryResponse {
        try await request("/chat/agents")
    }

    // MARK: - Memories (Phase 4)

    func fetchMemories(type: String? = nil) async throws -> [MemorySummary] {
        let path = type.map { "/memories?type=\($0)" } ?? "/memories"
        return try await request(path)
    }

    func exportMemories() async throws -> Data {
        let req = try await buildRequest("/memories/export", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response)
        return data
    }

    func deleteMemory(_ id: Int) async throws {
        try await requestVoid("/memories/\(id)", method: "DELETE")
    }

    func bulkDeleteMemories() async throws -> MemoryBulkDeleteResponse {
        try await request("/memories/bulk-delete", method: "POST")
    }

    func updateMemoryImportance(_ id: Int, importance: Double) async throws {
        try await buildAndSendVoid("/memories/\(id)", method: "PATCH",
                                   body: ImportanceBody(importance: importance))
    }

    func fetchMemoryReviewProposals() async throws -> [MemoryReviewProposal] {
        try await request("/memories/review")
    }

    func fetchMemoryReviewProposal(_ id: Int) async throws -> MemoryReviewProposal {
        try await request("/memories/review/\(id)")
    }

    func approveMemoryReviewProposal(_ id: Int) async throws -> MemoryReviewApprovalResponse {
        try await request("/memories/review/\(id)/approve", method: "POST")
    }

    func rejectMemoryReviewProposal(_ id: Int) async throws -> MemoryReviewProposal {
        try await request("/memories/review/\(id)/reject", method: "POST")
    }

    func fetchLLMUsageEvents(limit: Int = 20) async throws -> [LLMUsageEventSummary] {
        try await request("/memories/usage?limit=\(limit)")
    }

    func fetchSecrets() async throws -> [SecretSummary] {
        try await request("/secrets")
    }

    func createSecret(name: String, provider: String, value: String) async throws -> SecretSummary {
        try await request(
            "/secrets",
            method: "POST",
            body: SecretCreateBody(name: name, value: value, provider: provider)
        )
    }

    func updateSecret(_ id: Int, name: String, provider: String, isActive: Bool) async throws -> SecretSummary {
        try await request(
            "/secrets/\(id)",
            method: "PATCH",
            body: SecretUpdateBody(name: name, provider: provider, isActive: isActive)
        )
    }

    func rotateSecret(_ id: Int, value: String) async throws -> SecretSummary {
        try await request(
            "/secrets/\(id)/rotate",
            method: "POST",
            body: SecretRotateBody(value: value)
        )
    }


    func fetchSecretAccessEvents(_ id: Int, limit: Int = 10) async throws -> [SecretAccessEventSummary] {
        try await request("/secrets/\(id)/access-events?limit=\(limit)")
    }

    func updateChatRoutingPreference(_ preference: String) async throws {
        try await buildAndSendVoid(
            "/auth/me/preferences",
            method: "PATCH",
            body: ChatRoutingPreferenceBody(chatRoutingPreference: preference)
        )
    }

    // MARK: - User settings and integrations

    func fetchUserAssistantSettings() async throws -> UserAssistantSettings {
        try await request("/settings/me")
    }

    func updateUserAssistantSettings(
        _ patch: UserAssistantSettingsPatch
    ) async throws -> UserAssistantSettings {
        try await request("/settings/me", method: "PATCH", body: patch)
    }

    func fetchAssistantModelProfiles() async throws -> [AssistantModelProfile] {
        let response: AssistantModelListResponse = try await request("/llm/models")
        return response.models
    }

    func fetchAdminModelProfiles() async throws -> [AssistantModelProfile] {
        let response: AdminModelProfileListResponse = try await request("/admin/model-profiles")
        return response.profiles
    }

    func updateAdminModelProfile(
        _ profileID: String,
        patch: AdminModelProfilePatch
    ) async throws -> AssistantModelProfile {
        try await request(
            "/admin/model-profiles/\(profileID)",
            method: "PATCH",
            body: patch
        )
    }

    func fetchAdminUsers() async throws -> [AdminUserProfile] {
        try await request("/admin/users")
    }

    func createAdminUser(_ body: AdminUserCreate) async throws -> AdminUserProfile {
        try await request("/admin/users", method: "POST", body: body)
    }

    func updateAdminUser(_ userID: Int, patch: AdminUserPatch) async throws -> AdminUserProfile {
        try await request("/admin/users/\(userID)", method: "PATCH", body: patch)
    }

    func fetchAdminUserModelAccess(_ userID: Int) async throws -> AdminUserModelAccess {
        try await request("/admin/users/\(userID)/model-access")
    }

    func updateAdminUserModelAccess(
        _ userID: Int,
        allowedProfileIDs: [String]
    ) async throws -> AdminUserModelAccess {
        try await request(
            "/admin/users/\(userID)/model-access",
            method: "PUT",
            body: AdminUserModelAccessPatch(allowedProfileIds: allowedProfileIDs)
        )
    }

    func fetchUserIntegrations() async throws -> [UserIntegrationSummary] {
        let response: UserIntegrationListResponse = try await request("/integrations")
        return response.integrations
    }

    func connectAppleCalendar(
        _ connection: AppleCalendarConnectionRequest
    ) async throws -> UserIntegrationSummary {
        try await request(
            "/integrations/apple/calendar/connect",
            method: "POST",
            body: connection,
            timeout: 30
        )
    }

    func beginGoogleCalendarAuthorization(
        codeChallenge: String
    ) async throws -> GoogleCalendarAuthorizationResponse {
        let encoded = codeChallenge.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? codeChallenge
        return try await request("/integrations/google/calendar/auth-url?code_challenge=\(encoded)")
    }

    func completeGoogleCalendarAuthorization(
        code: String,
        state: String,
        codeVerifier: String
    ) async throws -> UserIntegrationSummary {
        try await request(
            "/integrations/google/calendar/callback",
            method: "POST",
            body: GoogleCalendarCallbackRequest(
                code: code,
                state: state,
                codeVerifier: codeVerifier
            ),
            timeout: 30
        )
    }

    func refreshIntegration(_ id: String) async throws -> UserIntegrationSummary {
        try await request("/integrations/\(id)/refresh", method: "POST")
    }

    func disconnectIntegration(_ id: String) async throws -> UserIntegrationSummary {
        try await request("/integrations/\(id)/disconnect", method: "POST")
    }

    // MARK: - Graph Memory (Phase 7.3)

    func fetchGraphMemoryEntities() async throws -> [GraphMemoryEntity] {
        try await request("/memories/graph/entities")
    }

    func searchGraphMemoryEntities(query: String) async throws -> [GraphMemoryEntity] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await request("/memories/graph/search?q=\(encoded)")
    }

    func fetchGraphMemoryNode(_ entityID: Int) async throws -> GraphMemoryNode {
        try await request("/memories/graph/entities/\(entityID)")
    }

    func updateGraphMemoryEntity(_ entityID: Int, patch: GraphMemoryEntityPatch) async throws -> GraphMemoryEntityDetail {
        try await request("/memories/graph/entities/\(entityID)", method: "PATCH", body: patch)
    }

    func deactivateGraphMemoryEntity(_ entityID: Int) async throws {
        try await requestVoid("/memories/graph/entities/\(entityID)", method: "DELETE")
    }

    func updateGraphMemoryObservation(_ observationID: Int, patch: GraphMemoryObservationPatch) async throws -> GraphMemoryObservation {
        try await request("/memories/graph/observations/\(observationID)", method: "PATCH", body: patch)
    }

    func deactivateGraphMemoryObservation(_ observationID: Int) async throws {
        try await requestVoid("/memories/graph/observations/\(observationID)", method: "DELETE")
    }

    // MARK: - Task audit + Chat session helpers (Phase 4.5)

    func fetchTaskAudit(_ id: Int) async throws -> TaskAuditOut {
        try await request("/tasks/\(id)/audit")
    }

    func createChatSession(title: String) async throws -> Int {
        struct Body: Encodable { let title: String }
        struct Resp: Decodable { let id: Int }
        let resp: Resp = try await request("/chat/sessions", method: "POST",
                                           body: Body(title: title))
        return resp.id
    }

    func sendTestPush(title: String, body: String) async throws -> String {
        struct Req: Encodable { let title: String; let body: String }
        struct Resp: Decodable {
            let ok: Bool
            let attempted: Int
            let delivered: Int
            let message: String
        }
        let resp: Resp = try await request(
            "/admin/push/test",
            method: "POST",
            body: Req(title: title, body: body)
        )
        return resp.message
    }

    func sendMessage(sessionId: Int, content: String) async throws {
        struct Body: Encodable { let content: String }
        try await buildAndSendVoid("/chat/sessions/\(sessionId)/messages",
                                   method: "POST", body: Body(content: content))
    }

    // MARK: - Private body-carrying void helper

    private func buildAndSendVoid(_ path: String, method: String,
                                   body: some Encodable) async throws {
        let req = try await buildRequest(path, method: method, body: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response)
    }
}

// MARK: - Phase 4 body helpers (file-private)

private struct ApproveBody: Encodable { let approved: Bool }
private struct ImportanceBody: Encodable { let importance: Double }
private struct ChatRoutingPreferenceBody: Encodable { let chatRoutingPreference: String }
private struct SecretCreateBody: Encodable { let name: String; let value: String; let provider: String }
private struct SecretUpdateBody: Encodable { let name: String; let provider: String; let isActive: Bool }
private struct SecretRotateBody: Encodable { let value: String }
private struct LinkSourceBody: Encodable {
    let path: String
    let scope: String
    let excludedPaths: [String]
}
private struct LinkedSourceExclusionBody: Encodable { let excludedPaths: [String] }
private struct TaskResultExportBody: Encodable {
    let path: String
    let artifactType: String
    let overwrite: Bool
}
private struct TaskModelOverridePatch: Encodable {
    let llmModelOverride: String?

    enum CodingKeys: String, CodingKey {
        case llmModelOverride = "llm_model_override"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let llmModelOverride {
            try container.encode(llmModelOverride, forKey: .llmModelOverride)
        } else {
            try container.encodeNil(forKey: .llmModelOverride)
        }
    }
}

// MARK: - Data multipart helpers

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        append(contentsOf: header.utf8)
        append(contentsOf: value.utf8)
        append(contentsOf: "\r\n".utf8)
    }

    mutating func appendMultipartFile(
        name: String,
        fileName: String,
        mimeType: String,
        data fileData: Data,
        boundary: String
    ) {
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        append(contentsOf: header.utf8)
        append(fileData)
        append(contentsOf: "\r\n".utf8)
    }
}

// MARK: - Error types

enum APIError: LocalizedError {
    case noServerConfigured
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(Int, String?)
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .noServerConfigured: return "No server URL configured. Add one in Settings."
        case .invalidResponse:    return "Invalid response from server"
        case .unauthorized:       return "Authentication required — please log in"
        case .notFound:           return "Resource not found"
        case .serverError(let c, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Server error (\(c))"
        case .httpError(let c, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "HTTP error \(c)"
        }
    }
}

// MARK: - Read-only coding API

extension APIClient: CodingServing {
    func codingExplorerRoot(sessionId: String) async throws -> InspectorRoot {
        try await codingBrowserRequest("/coding/sessions/\(sessionId)/explorer")
    }
    func codingExplorerDirectory(sessionId: String, rootId: String, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "root_id", value: rootId), URLQueryItem(name: "path", value: path),
                            URLQueryItem(name: "offset", value: String(offset))]
        if let version { query.queryItems?.append(URLQueryItem(name: "version", value: version)) }
        return try await codingBrowserRequest("/coding/sessions/\(sessionId)/explorer/directory?\(query.percentEncodedQuery ?? "")")
    }
    func codingExplorerFile(sessionId: String, rootId: String, path: String) async throws -> InspectorFileContent {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "root_id", value: rootId), URLQueryItem(name: "path", value: path)]
        return try await codingBrowserRequest("/coding/sessions/\(sessionId)/explorer/file?\(query.percentEncodedQuery ?? "")")
    }
    private func codingBrowserRequest<T: Decodable>(_ path: String) async throws -> T {
        var request = try await buildRequest(path, method: "GET", timeout: 45)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateCoding(response, data: data)
        guard data.count <= 2 * 1024 * 1024 else { throw CodingClientError(code: "inspection_limit", message: "Inspection response exceeds the client display limit.") }
        return try decode(T.self, from: data)
    }
    func codingReviewOptions(sessionId: String, scope: String) async throws -> CodingReviewOptions {
        let query = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await codingRequest("/coding/sessions/\(sessionId)/review-options?scope=\(query)", timeout: 45)
    }
    func startCodingReview(sessionId: String, request: CodingReviewRequest) async throws -> CodingAIReview {
        try await codingRequest("/coding/sessions/\(sessionId)/reviews", method: "POST", body: request, timeout: 45)
    }
    func codingReviews(sessionId: String, offset: Int) async throws -> [CodingAIReview] {
        try await codingRequest("/coding/sessions/\(sessionId)/reviews?limit=50&offset=\(offset)")
    }
    func codingReview(id: String) async throws -> CodingAIReview { try await codingRequest("/coding/reviews/\(id)", timeout: 45) }
    func stopCodingReview(id: String) async throws {
        struct Result: Decodable { let stopRequested: Bool }
        let _: Result = try await codingRequest("/coding/reviews/\(id)/stop", method: "POST", timeout: 45)
    }
    func codingReviewApprovals(id: String) async throws -> [CodingReviewApproval] { try await codingRequest("/coding/reviews/\(id)/approvals") }
    func resolveCodingReviewApproval(reviewId: String, approvalId: String, approved: Bool) async throws {
        struct Body: Encodable { let approved: Bool }
        try await codingVoid("/coding/reviews/\(reviewId)/approvals/\(approvalId)/resolve", body: Body(approved: approved))
    }
    func setCodingFinding(reviewId: String, findingId: String, disposition: String, reason: String?) async throws -> CodingReviewFinding {
        struct Body: Encodable { let disposition: String; let reason: String? }
        return try await codingRequest("/coding/reviews/\(reviewId)/findings/\(findingId)", method: "PATCH", body: Body(disposition: disposition, reason: reason))
    }
    func codingCapturedDiff(captureId: String, path: String) async throws -> CodingReviewDiff {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "path", value: path)]
        return try await codingRequest("/coding/review-captures/\(captureId)/diff?\(query.percentEncodedQuery ?? "")", timeout: 45)
    }
    func streamCodingReview(id: String, after: Int, onEvent: @escaping @MainActor (CodingReviewEvent) async throws -> Void) async throws {
        var request = try await buildRequest("/coding/reviews/\(id)/events?after=\(after)&follow=true", method: "GET", timeout: 60)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(String(after), forHTTPHeaderField: "Last-Event-ID")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count >= 8192 { break } }
            throw CodingClientError.response(status: http.statusCode, data: data)
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
            throw CodingClientError(code: "invalid_stream", message: "The backend did not return a review event stream.")
        }
        var parser = CodingSSEParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard let frame = try parser.feed(byte: byte) else { continue }
            if frame.event == "stream.error" {
                let fields = try JSONDecoder().decode([String: String].self, from: frame.data)
                throw CodingClientError(code: fields["code"] ?? "stream_unavailable", message: fields["message"] ?? "Review stream interrupted.")
            }
            let event = try decode(CodingReviewEvent.self, from: frame.data)
            guard frame.id == String(event.sequence), frame.event == event.kind, event.reviewId == id else {
                throw CodingClientError(code: "invalid_event", message: "The review stream returned a mismatched event.")
            }
            try await onEvent(event)
        }
    }
    func codingAvailability() async throws -> CodingAvailability { try await codingRequest("/coding/status") }
    func codingWorkspaces() async throws -> [CodingWorkspace] { try await codingRequest("/coding/workspaces") }
    func codingModels() async throws -> [CodingModelOption] { try await codingRequest("/coding/models") }
    func codingProjects() async throws -> [CodingProjectOption] { try await codingRequest("/projects") }
    func codingSessions(offset: Int) async throws -> [CodingSession] {
        try await codingRequest("/coding/sessions?limit=100&offset=\(offset)")
    }
    func createCodingSession(workspaceId: String, modelId: Int, projectId: Int?, title: String) async throws -> CodingSession {
        struct Body: Encodable { let workspaceId: String; let modelProfileId: Int; let projectId: Int?; let title: String }
        return try await codingRequest("/coding/sessions", method: "POST",
            body: Body(workspaceId: workspaceId, modelProfileId: modelId, projectId: projectId, title: title))
    }
    func codingRuns(sessionId: String, offset: Int) async throws -> [CodingRun] {
        try await codingRequest("/coding/sessions/\(sessionId)/runs?limit=100&offset=\(offset)")
    }
    func codingReusableCheckouts() async throws -> [CodingCheckout] { try await codingRequest("/coding/checkouts") }
    func codingSessionPage(offset: Int, archived: Bool) async throws -> [CodingSession] {
        try await codingRequest("/coding/sessions?limit=100&offset=\(offset)&archived=\(archived)")
    }
    func createCodingSessionInCheckout(workspaceId: String, modelId: Int, projectId: Int?, title: String, checkoutId: String) async throws -> CodingSession {
        struct Body: Encodable { let workspaceId: String; let modelProfileId: Int; let projectId: Int?; let title: String; let checkoutId: String }
        return try await codingRequest("/coding/sessions", method: "POST", body: Body(workspaceId: workspaceId, modelProfileId: modelId, projectId: projectId, title: title, checkoutId: checkoutId))
    }
    func changeCodingModel(sessionId: String, modelId: Int) async throws -> CodingSession {
        struct Body: Encodable { let modelProfileId: Int }
        return try await codingRequest("/coding/sessions/\(sessionId)/model", method: "POST", body: Body(modelProfileId: modelId))
    }
    func archiveCodingSession(sessionId: String, archived: Bool) async throws -> CodingSession {
        struct Body: Encodable { let archived: Bool }
        return try await codingRequest("/coding/sessions/\(sessionId)/archive", method: "POST", body: Body(archived: archived))
    }
    func deleteCodingSession(sessionId: String) async throws {
        let request = try await buildRequest("/coding/sessions/\(sessionId)", method: "DELETE", timeout: 45)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateCoding(response, data: data)
    }
    private struct CodingDeliveryBody: Encodable { let action: String; let files: [String]; let message: String; let reviewHash: String? }
    func previewCodingDelivery(sessionId: String, action: String, files: [String], message: String) async throws -> CodingDeliveryPreview {
        try await codingRequest("/coding/sessions/\(sessionId)/delivery", method: "POST", body: CodingDeliveryBody(action: action, files: files, message: message, reviewHash: nil), timeout: 75)
    }
    func confirmCodingDelivery(sessionId: String, action: String, files: [String], message: String, hash: String) async throws -> CodingDeliveryResult {
        try await codingRequest("/coding/sessions/\(sessionId)/delivery", method: "POST", body: CodingDeliveryBody(action: action, files: files, message: message, reviewHash: hash), timeout: 75)
    }
    func codingRun(id: String) async throws -> CodingRun { try await codingRequest("/coding/runs/\(id)") }
    func setCodingEditMode(sessionId: String, enabled: Bool) async throws -> CodingSession {
        struct Body: Encodable { let enabled: Bool }
        return try await codingRequest("/coding/sessions/\(sessionId)/edit-mode", method: "POST", body: Body(enabled: enabled))
    }
    func setCodingCommandMode(sessionId: String, enabled: Bool) async throws -> CodingSession {
        struct Body: Encodable { let enabled: Bool }
        return try await codingRequest("/coding/sessions/\(sessionId)/command-mode", method: "POST", body: Body(enabled: enabled))
    }
    func resolveCodingCommand(id: String, approved: Bool, commandHash: String?) async throws {
        struct Body: Encodable { let approved: Bool; let commandHash: String? }
        try await codingVoid("/coding/approvals/\(id)/resolve", body: Body(approved: approved, commandHash: commandHash))
    }
    func codingChanges(runId: String) async throws -> [CodingSavedChange] {
        try await codingRequest("/coding/runs/\(runId)/changes")
    }
    func codingCheckout(sessionId: String) async throws -> CodingCheckout? {
        try await codingRequest("/coding/sessions/\(sessionId)/checkout")
    }
    func createCodingCheckout(sessionId: String) async throws -> CodingCheckout {
        try await codingRequest("/coding/sessions/\(sessionId)/checkout", method: "POST")
    }
    func removeCodingCheckout(sessionId: String) async throws -> CodingCheckout {
        try await codingRequest("/coding/sessions/\(sessionId)/checkout/remove", method: "POST")
    }
    func codingRepository(sessionId: String) async throws -> CodingRepository {
        try await codingRequest("/coding/sessions/\(sessionId)/repository", timeout: 20)
    }
    func codingRepositoryDiff(sessionId: String, path: String) async throws -> CodingRepositoryDiff {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return try await codingRequest("/coding/sessions/\(sessionId)/repository/diff?path=\(encoded)", timeout: 20)
    }
    func submitCoding(sessionId: String, message: String, requestId: String) async throws -> CodingRun {
        struct Body: Encodable { let message: String; let clientRequestId: String }
        return try await codingRequest("/coding/sessions/\(sessionId)/runs", method: "POST",
            body: Body(message: message, clientRequestId: requestId))
    }
    func stopCoding(runId: String) async throws {
        struct Result: Decodable { let stopRequested: Bool }
        let _: Result = try await codingRequest("/coding/runs/\(runId)/stop", method: "POST", timeout: 45)
    }
    func controlCoding(runId: String, action: String, message: String) async throws {
        struct Body: Encodable { let action: String; let message: String }
        try await codingVoid("/coding/runs/\(runId)/control", body: Body(action: action, message: message))
    }
    func codingApprovals(runId: String) async throws -> [CodingApproval] {
        try await codingRequest("/coding/runs/\(runId)/approvals")
    }
    func resolveCodingApproval(id: String, approved: Bool, changeHash: String?) async throws {
        struct Body: Encodable { let approved: Bool; let changeHash: String? }
        try await codingVoid("/coding/approvals/\(id)/resolve", body: Body(approved: approved, changeHash: changeHash))
    }
    func closeCodingSession(id: String) async throws { try await codingVoid("/coding/sessions/\(id)/close") }
    func grantCodingWorkspace(userId: Int, path: String) async throws -> CodingWorkspace {
        struct Body: Encodable { let userId: Int; let path: String; let requireRepository: Bool }
        return try await codingRequest("/coding/workspaces", method: "POST", body: Body(userId: userId, path: path, requireRepository: true))
    }
    func createCodingRepository(userId: Int, path: String) async throws -> CodingWorkspace {
        struct Body: Encodable { let userId: Int; let path: String }
        return try await codingRequest("/coding/repositories", method: "POST", body: Body(userId: userId, path: path), timeout: 45)
    }

    private func codingRequest<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil, timeout: TimeInterval = 15) async throws -> T {
        let request = try await buildRequest(path, method: method, body: body, timeout: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateCoding(response, data: data)
        return try decode(T.self, from: data)
    }
    private func codingVoid(_ path: String, body: (any Encodable)? = nil) async throws {
        let request = try await buildRequest(path, method: "POST", body: body, timeout: 45)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateCoding(response, data: data)
    }
    private func validateCoding(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw CodingClientError.response(status: http.statusCode, data: data)
        }
    }

    func streamCoding(runId: String, after: Int, follow: Bool, onEvent: @escaping @MainActor (CodingEvent) async throws -> Void) async throws {
        var request = try await buildRequest("/coding/runs/\(runId)/events?after=\(after)&follow=\(follow)", method: "GET", timeout: 60)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte); if body.count >= 8192 { break } }
            throw CodingClientError.response(status: http.statusCode, data: body)
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
            throw CodingClientError(code: "invalid_stream", message: "The backend did not return a coding event stream.")
        }
        var parser = CodingSSEParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard let frame = try parser.feed(byte: byte) else { continue }
            if frame.event == "stream.error" {
                let fields = try JSONDecoder().decode([String: String].self, from: frame.data)
                throw CodingClientError(code: fields["code"] ?? "stream_unavailable", message: fields["message"] ?? "Coding stream interrupted.")
            }
            let event = try decode(CodingEvent.self, from: frame.data)
            guard frame.id == String(event.sequence), frame.event == event.kind, event.runId == runId else {
                throw CodingClientError(code: "invalid_event", message: "The coding stream returned a mismatched event.")
            }
            try await onEvent(event)
        }
    }
}
