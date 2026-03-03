//
//  FruitcakeAiApp.swift
//  FruitcakeAi
//

import SwiftUI
import SwiftData

@main
struct FruitcakeAiApp: App {

    // MARK: - Services (shared singletons)

    @State private var authManager = AuthManager()
    @State private var connectivityMonitor: ConnectivityMonitor
    @State private var onDeviceAgent = OnDeviceAgent()

    // MARK: - SwiftData

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ServerConfig.self,
            CachedConversation.self,
            CachedMessage.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Init

    init() {
        let auth = AuthManager()
        _authManager = State(initialValue: auth)
        _connectivityMonitor = State(initialValue: ConnectivityMonitor(authManager: auth))
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(connectivityMonitor)
                .environment(onDeviceAgent)
                .task {
                    // Restore session from Keychain on launch
                    await authManager.restoreSession()
                    connectivityMonitor.start()
                    onDeviceAgent.checkAvailability()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
