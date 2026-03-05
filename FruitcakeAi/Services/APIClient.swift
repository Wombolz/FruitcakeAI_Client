//
//  APIClient.swift
//  FruitcakeAi
//
//  URLSession wrapper for the FruitcakeAI Python backend REST API.
//  Injects Authorization: Bearer on every request and maps HTTP errors
//  to typed Swift errors. All methods are async and throw APIError.
//

import Foundation

actor APIClient {

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
        guard let baseURL else { throw APIError.noServerConfigured }

        let boundary = UUID().uuidString
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
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
        guard let baseURL else { throw APIError.noServerConfigured }

        var req = URLRequest(url: baseURL.appendingPathComponent(path))
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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let d = fmt.date(from: s) { return d }
            fmt.formatOptions = [.withInternetDateTime]     // fallback: no fractional seconds
            if let d = fmt.date(from: s) { return d }
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

    func createTask(_ req: CreateTaskRequest) async throws -> TaskSummary {
        try await request("/tasks", method: "POST", body: req)
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

    // MARK: - Memories (Phase 4)

    func fetchMemories(type: String? = nil) async throws -> [MemorySummary] {
        let path = type.map { "/memories?type=\($0)" } ?? "/memories"
        return try await request(path)
    }

    func deleteMemory(_ id: Int) async throws {
        try await requestVoid("/memories/\(id)", method: "DELETE")
    }

    func updateMemoryImportance(_ id: Int, importance: Double) async throws {
        try await buildAndSendVoid("/memories/\(id)", method: "PATCH",
                                   body: ImportanceBody(importance: importance))
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
