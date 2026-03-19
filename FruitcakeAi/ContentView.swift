//
//  ContentView.swift
//  FruitcakeAi
//
//  Root router.
//  • Unauthenticated → LoginView (credential entry, server URL)
//  • Authenticated   → MainTabView (Chat · Library · Settings)
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if authManager.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

// MARK: - Main tab container

struct MainTabView: View {

    @State private var pendingApprovalCount = 0
    @State private var selectedTab = "chat"
    @State private var openSessionId: Int? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: "chat") {
                ChatView(openSessionId: $openSessionId)
            }
            Tab("Inbox", systemImage: "envelope.badge.fill", value: "inbox") {
                InboxView(
                    onCountChanged: { pendingApprovalCount = $0 },
                    onReplyInChat: { sessionId in
                        openSessionId = sessionId
                        selectedTab = "chat"
                    }
                )
            }
            .badge(pendingApprovalCount)
            Tab("Library", systemImage: "books.vertical.fill", value: "library") {
                LibraryView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: "settings") {
                SettingsView()
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = "http://localhost:30417"
    @State private var loginError: String?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "birthday.cake")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: loading)

            Text("FruitcakeAI")
                .font(.largeTitle.bold())



            Spacer().frame(height: 8)

            VStack(spacing: 12) {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .textFieldStyle(.roundedBorder)

            if let loginError {
                Text(loginError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await signIn() }
            } label: {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading || username.isEmpty || password.isEmpty)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 380)
    }

    private func signIn() async {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else {
            loginError = "Invalid server URL"
            return
        }
        loading = true
        loginError = nil
        do {
            try await authManager.login(username: username, password: password, serverURL: url)
        } catch {
            loginError = error.localizedDescription
        }
        loading = false
    }
}

#Preview("Logged out") {
    LoginView()
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
}

#Preview("Main tabs") {
    MainTabView()
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
        .modelContainer(
            for: [ServerConfig.self, CachedConversation.self, CachedMessage.self],
            inMemory: true
        )
}
