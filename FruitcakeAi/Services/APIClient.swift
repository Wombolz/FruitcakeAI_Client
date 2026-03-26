//
//  APIClient.swift
//  FruitcakeAi
//
//  URLSession wrapper for the FruitcakeAI Python backend REST API.
//  Injects Authorization: Bearer on every request and maps HTTP errors
//  to typed Swift errors. All methods are async and throw APIError.
//

import Foundation

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
        try validate(response)
        return try decode(T.self, from: data)
    }

    // MARK: - Void request (no response body expected)

    func requestVoid(_ path: String, method: String) async throws {
        let req = try await buildRequest(path, method: method)
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response)
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
        try validate(response)
        return data
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

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: break
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 500...599: throw APIError.serverError(http.statusCode)
        default: throw APIError.httpError(http.statusCode)
        }
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

    func updateTaskModelOverride(_ id: Int, llmModelOverride: String?) async throws -> TaskSummary {
        try await request(
            "/tasks/\(id)",
            method: "PATCH",
            body: TaskModelOverridePatch(llmModelOverride: llmModelOverride)
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

    func updateChatRoutingPreference(_ preference: String) async throws {
        try await buildAndSendVoid(
            "/auth/me/preferences",
            method: "PATCH",
            body: ChatRoutingPreferenceBody(chatRoutingPreference: preference)
        )
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
private struct TaskModelOverridePatch: Encodable { let llmModelOverride: String? }

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
    case serverError(Int)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noServerConfigured: "No server URL configured. Add one in Settings."
        case .invalidResponse:    "Invalid response from server"
        case .unauthorized:       "Authentication required — please log in"
        case .notFound:           "Resource not found"
        case .serverError(let c): "Server error (\(c))"
        case .httpError(let c):   "HTTP error \(c)"
        }
    }
}
