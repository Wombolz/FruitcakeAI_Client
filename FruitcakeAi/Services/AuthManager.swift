//
//  AuthManager.swift
//  FruitcakeAi
//
//  Manages authentication state: login, token storage (Keychain), logout.
//  Injected into the SwiftUI environment as an @Observable singleton.
//

import Foundation
import Observation

@Observable
final class AuthManager {

    // MARK: - Published state

    private(set) var currentUser: UserProfile?
    private(set) var serverURL: URL?

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Init

    init() {
        // Restore server URL from Keychain so connectivity check works on launch
        if let stored = KeychainHelper.read(forKey: KeychainHelper.Keys.serverURL),
           let url = URL(string: stored) {
            serverURL = url
        }
    }

    // MARK: - Login

    func login(username: String, password: String, serverURL: URL) async throws {
        let url = serverURL.appendingPathComponent("/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverUnreachable
        }
        guard httpResponse.statusCode == 200 else {
            throw AuthError.invalidCredentials
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        KeychainHelper.save(tokens.accessToken, forKey: KeychainHelper.Keys.accessToken)
        KeychainHelper.save(tokens.refreshToken, forKey: KeychainHelper.Keys.refreshToken)
        KeychainHelper.save(serverURL.absoluteString, forKey: KeychainHelper.Keys.serverURL)

        self.serverURL = serverURL
        self.currentUser = try await fetchCurrentUser(serverURL: serverURL, token: tokens.accessToken)

        // If APNs registered before auth was available, retry registration/upload now.
        await APNsManager.shared.requestAndRegister()
        if let token = APNsManager.shared.deviceToken {
            await APNsManager.shared.uploadToken(token)
        }
    }

    // MARK: - Token access

    func token() throws -> String {
        guard let token = KeychainHelper.read(forKey: KeychainHelper.Keys.accessToken) else {
            throw AuthError.notAuthenticated
        }
        return token
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.accessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.refreshToken)
        currentUser = nil
    }

    // MARK: - Profile restore (on launch)

    func restoreSession() async {
        guard let serverURL,
              let token = KeychainHelper.read(forKey: KeychainHelper.Keys.accessToken) else {
            return
        }
        do {
            currentUser = try await fetchCurrentUser(serverURL: serverURL, token: token)
        } catch {
            // Token expired or server unreachable — stay logged out
        }
    }

    // MARK: - Private

    private func fetchCurrentUser(serverURL: URL, token: String) async throws -> UserProfile {
        let url = serverURL.appendingPathComponent("/auth/me")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.notAuthenticated
        }

        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
}

// MARK: - Supporting types

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case notAuthenticated
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid username or password"
        case .notAuthenticated:   "Not authenticated — please log in"
        case .serverUnreachable:  "Cannot reach server"
        }
    }
}
