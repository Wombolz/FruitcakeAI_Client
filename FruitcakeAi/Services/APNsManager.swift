//
//  APNsManager.swift
//  FruitcakeAi
//
//  Manages push-notification permission and device-token registration.
//
//  Flow:
//    1. FruitcakeAiApp calls requestAndRegister() after session restore (or login).
//    2. If permission is granted, registerForRemoteNotifications() fires.
//    3. AppDelegate receives didRegisterForRemoteNotificationsWithDeviceToken(_:).
//    4. AppDelegate calls APNsManager.shared.uploadToken(_:).
//    5. uploadToken reads the auth JWT + server URL from Keychain and POSTs
//       to POST /devices/register — no dependency on live AuthManager state.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import UserNotifications

@Observable
final class APNsManager {

    static let shared = APNsManager()
    private init() {}

    // MARK: - State

    private(set) var deviceToken: String?

    // MARK: - Permission + registration

    /// Request notification permission (if not already decided) and register with APNs.
    /// Safe to call on every launch.
    func requestAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus != .denied else { return }

        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else {
                return
            }
        }

        await MainActor.run {
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }

    // MARK: - Token upload

    /// Called by AppDelegate when APNs delivers the device token.
    /// Reads auth credentials from Keychain and registers the token with the backend.
    func uploadToken(_ hexToken: String) async {
        deviceToken = hexToken

        guard
            let serverURLStr = KeychainHelper.read(forKey: KeychainHelper.Keys.serverURL),
            let serverURL    = URL(string: serverURLStr),
            let authToken    = KeychainHelper.read(forKey: KeychainHelper.Keys.accessToken)
        else {
            // Not yet authenticated — token will be uploaded on next launch after login
            print("[APNs] Skipping upload: no auth token in Keychain")
            return
        }

        let url = serverURL.appendingPathComponent("/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)",  forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let body: [String: String] = ["token": hexToken, "environment": environment]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                print("[APNs] Token registered: \(hexToken.prefix(8))…")
            } else {
                print("[APNs] Unexpected response: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            print("[APNs] Token upload failed: \(error.localizedDescription)")
        }
    }
}
