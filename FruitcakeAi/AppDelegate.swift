//
//  AppDelegate.swift
//  FruitcakeAi
//
//  Platform application delegate bridge — handles APNs device-token callbacks.
//  Wired into SwiftUI via UIApplicationDelegateAdaptor / NSApplicationDelegateAdaptor
//  in FruitcakeAiApp.
//

#if os(iOS)
import UIKit
private typealias PlatformAppDelegate = UIApplicationDelegate
#elseif os(macOS)
import AppKit
private typealias PlatformAppDelegate = NSApplicationDelegate
#endif

final class AppDelegate: NSObject, PlatformAppDelegate {

    // MARK: - APNs token registration

    #if os(iOS)
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await APNsManager.shared.uploadToken(hexToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
    #elseif os(macOS)
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
    #endif
}
