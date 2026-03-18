//
//  ConnectivityMonitor.swift
//  FruitcakeAi
//
//  Pings GET /health every 30 seconds and publishes whether the
//  Python backend is reachable for any authenticated user or guest liveness check. Views observe isBackendReachable to
//  switch between full-backend mode and on-device fallback mode.
//

import Foundation
import Observation

@Observable
final class ConnectivityMonitor {

    // MARK: - State

    private(set) var isBackendReachable: Bool = false
    private(set) var lastChecked: Date?

    // MARK: - Dependencies

    private let authManager: AuthManager
    private var monitorTask: Task<Void, Never>?

    // MARK: - Init

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Lifecycle

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkHealth()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Trigger an immediate check (e.g. after the user changes server URL).
    func checkNow() {
        Task { await checkHealth() }
    }

    // MARK: - Private

    private func checkHealth() async {
        guard let serverURL = authManager.serverURL else {
            isBackendReachable = false
            return
        }

        let url = serverURL.appendingPathComponent("/health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        if let token = try? authManager.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastChecked = .now
            isBackendReachable = (200...299).contains(statusCode)
        } catch {
            lastChecked = .now
            isBackendReachable = false
        }
    }
}
