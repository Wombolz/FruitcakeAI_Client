import Foundation

@MainActor protocol PersonaEditorTransport {
    func send<T: Decodable>(_ path: String, method: String, body: (any Encodable)?) async throws -> T
    func sendVoid(_ path: String, method: String, body: (any Encodable)?) async throws
    func uploadPersonaImage(_ data: Data, filename: String) async throws -> PersonaImageAsset
}

extension PersonaEditorTransport {
    func call<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil) async throws -> T {
        try await send(path, method: method, body: body)
    }
    func callVoid(_ path: String, method: String, body: (any Encodable)? = nil) async throws {
        try await sendVoid(path, method: method, body: body)
    }
}

extension APIClient: PersonaEditorTransport {
    func send<T: Decodable>(_ path: String, method: String, body: (any Encodable)?) async throws -> T {
        try await request(path, method: method, body: body, timeout: 15)
    }
    func sendVoid(_ path: String, method: String, body: (any Encodable)?) async throws {
        try await requestVoid(path, method: method, body: body)
    }
}
