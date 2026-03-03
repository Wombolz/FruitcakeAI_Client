//
//  UserProfile.swift
//  FruitcakeAi
//
//  In-memory representation of the authenticated user (from GET /auth/me).
//  Not persisted to SwiftData — reconstructed from Keychain token on launch.
//

import Foundation

struct UserProfile: Codable, Equatable {
    let id: Int
    let username: String
    let email: String
    let fullName: String?
    let role: String
    let persona: String
    let libraryScopes: [String]
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, email, role, persona
        case fullName      = "full_name"
        case libraryScopes = "library_scopes"
        case isActive      = "is_active"
    }

    var isAdmin: Bool { role == "admin" }
    var isParent: Bool { role == "parent" || role == "admin" }
}
