//
//  AppDelegate.swift
//  FruitcakeAi
//
//  NSApplicationDelegate bridge — handles APNs device-token callbacks on macOS.
//  Wired into SwiftUI via @NSApplicationDelegateAdaptor in FruitcakeAiApp.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - APNs token registration

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await APNsManager.shared.uploadToken(hexToken)
        }
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}
