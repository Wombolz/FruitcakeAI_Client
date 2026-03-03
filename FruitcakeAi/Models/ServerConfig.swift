//
//  ServerConfig.swift
//  FruitcakeAi
//
//  SwiftData model for backend connection settings.
//  Server URL is also mirrored to Keychain via AuthManager at login;
//  this model persists it across reinstalls and exposes it to SwiftUI queries.
//

import Foundation
import SwiftData

@Model
final class ServerConfig {
    var serverURL: String
    var isDefault: Bool

    init(serverURL: String, isDefault: Bool = false) {
        self.serverURL = serverURL
        self.isDefault = isDefault
    }

    var url: URL? { URL(string: serverURL) }
}
