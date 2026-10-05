import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ConnectedAccountsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var integrations: [UserIntegrationSummary] = []
    @State private var isLoading = true
    @State private var workingProvider: String?
    @State private var errorMessage: String?
    @State private var showAppleSheet = false
    @State private var oauthSession = OAuthWebSession()

    private var google: UserIntegrationSummary? {
        integrations.first { $0.provider == "google" && $0.service == "calendar" }
    }

    private var apple: UserIntegrationSummary? {
        integrations.first { $0.provider == "apple" && $0.service == "calendar" }
    }

    var body: some View {
        SettingsPage(title: "Connected Accounts", subtitle: "Connect services to your account. Credentials stay encrypted on the Fruitcake server.") {
            if isLoading {
                ProgressView("Checking connections…")
            } else {
                integrationCard(
                    title: "Google Calendar",
                    provider: "google",
                    symbol: "calendar.badge.clock",
                    integration: google,
                    connect: { Task { await connectGoogle() } }
                )

                integrationCard(
                    title: "Apple Calendar",
                    provider: "apple",
                    symbol: "calendar",
                    integration: apple,
                    connect: { showAppleSheet = true }
                )

                SettingsCard(title: "Privacy boundary", systemImage: "lock.shield") {
                    Text("Connections belong to this Fruitcake account. Administrators can inspect connection health, but credentials are never returned to the client after submission.")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAppleSheet) {
            AppleCalendarConnectionSheet { request in
                await connectApple(request)
            }
        }
    }

    private func integrationCard(
        title: String,
        provider: String,
        symbol: String,
        integration: UserIntegrationSummary?,
        connect: @escaping () -> Void
    ) -> some View {
        SettingsCard(title: title, systemImage: symbol) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(integration?.isConnected == true ? Theme.ok : Theme.textFaint)
                            .frame(width: 8, height: 8)
                        Text(integration?.isConnected == true ? "Connected" : "Not connected")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let account = integration?.accountIdentifier, !account.isEmpty {
                        Text(account)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textDim)
                    }
                    if let error = integration?.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if workingProvider == provider {
                    ProgressView()
                        .controlSize(.small)
                } else if let integration, integration.isConnected {
                    if provider == "google" {
                        Button("Refresh") { Task { await refresh(integration) } }
                            .buttonStyle(.bordered)
                    }
                    Button("Disconnect", role: .destructive) {
                        Task { await disconnect(integration) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect", action: connect)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            integrations = try await APIClient(authManager: authManager).fetchUserIntegrations()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func connectApple(_ request: AppleCalendarConnectionRequest) async -> Bool {
        workingProvider = "apple"
        errorMessage = nil
        defer { workingProvider = nil }
        do {
            let updated = try await APIClient(authManager: authManager).connectAppleCalendar(request)
            replace(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func connectGoogle() async {
        workingProvider = "google"
        errorMessage = nil
        defer { workingProvider = nil }
        do {
            let verifier = PKCE.makeVerifier()
            let challenge = PKCE.challenge(for: verifier)
            let response = try await APIClient(authManager: authManager)
                .beginGoogleCalendarAuthorization(codeChallenge: challenge)
            let callbackURL = try await oauthSession.authenticate(with: response.authorizationUrl)
            let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let code = query.first(where: { $0.name == "code" })?.value,
                  let state = query.first(where: { $0.name == "state" })?.value else {
                throw OAuthConnectionError.missingCallbackValues
            }
            let updated = try await APIClient(authManager: authManager)
                .completeGoogleCalendarAuthorization(
                    code: code,
                    state: state,
                    codeVerifier: verifier
                )
            replace(updated)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh(_ integration: UserIntegrationSummary) async {
        workingProvider = integration.provider
        errorMessage = nil
        defer { workingProvider = nil }
        do {
            replace(try await APIClient(authManager: authManager).refreshIntegration(integration.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect(_ integration: UserIntegrationSummary) async {
        workingProvider = integration.provider
        errorMessage = nil
        defer { workingProvider = nil }
        do {
            replace(try await APIClient(authManager: authManager).disconnectIntegration(integration.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ integration: UserIntegrationSummary) {
        integrations.removeAll { $0.id == integration.id || ($0.provider == integration.provider && $0.service == integration.service) }
        integrations.append(integration)
    }
}

private struct AppleCalendarConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var appPassword = ""
    @State private var serverURL = "https://caldav.icloud.com"
    @State private var defaultCalendar = "home"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    let connect: (AppleCalendarConnectionRequest) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Account") {
                    TextField("Apple ID email", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("App-specific password", text: $appPassword)
                    TextField("Default calendar", text: $defaultCalendar)
                }
                Section("Advanced") {
                    TextField("CalDAV server", text: $serverURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect Apple Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConnecting ? "Verifying…" : "Connect") {
                        Task { await submit() }
                    }
                    .disabled(isConnecting || username.isEmpty || appPassword.isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 390)
    }

    private func submit() async {
        isConnecting = true
        errorMessage = nil
        let success = await connect(AppleCalendarConnectionRequest(
            username: username,
            appPassword: appPassword,
            url: serverURL,
            defaultCalendar: defaultCalendar
        ))
        isConnecting = false
        if success {
            dismiss()
        } else {
            errorMessage = "Fruitcake could not verify these calendar credentials."
        }
    }
}

private enum PKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(result == errSecSuccess)
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum OAuthConnectionError: LocalizedError {
    case missingRedirectScheme
    case missingCallbackValues

    var errorDescription: String? {
        switch self {
        case .missingRedirectScheme:
            return "The server's Google OAuth redirect URL is not configured with a callback scheme."
        case .missingCallbackValues:
            return "Google did not return the information needed to finish connecting."
        }
    }
}

@MainActor
private final class OAuthWebSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(with authorizationURL: URL) async throws -> URL {
        let query = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let redirect = query.first(where: { $0.name == "redirect_uri" })?.value,
              let callbackScheme = URL(string: redirect)?.scheme else {
            throw OAuthConnectionError.missingRedirectScheme
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthConnectionError.missingCallbackValues)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIWindow()
        #endif
    }
}
