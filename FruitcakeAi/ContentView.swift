//
//  ContentView.swift
//  FruitcakeAi
//
//  Root router.
//  • Unauthenticated → LoginView (credential entry, server URL)
//  • Authenticated   → MainTabView (persistent app navigation shell)
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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

// MARK: - Main navigation shell

private enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case chat
    case tasks
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .tasks: "Tasks"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .tasks: "checklist"
        case .library: "books.vertical.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainTabView: View {

    @Environment(ArtifactInspectorState.self) private var artifactInspector

    @State private var pendingApprovalCount = 0
    @State private var selectedDestination: AppDestination = .chat
    @State private var visitedDestinations: Set<AppDestination> = [.chat]
    @State private var openSessionId: Int? = nil
    @State private var artifactInspectorWidth: CGFloat = 480
    @State private var artifactInspectorLastDragX: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            destinationRail
            Rectangle()
                .fill(Theme.strokeUp)
                .frame(width: 1)
            destinationHost
            #else
            mobileTabView
            #endif

            #if os(macOS)
            if artifactInspector.isVisible {
                artifactInspectorResizeHandle
                ArtifactInspectorView()
                    .frame(width: artifactInspectorWidth)
            }
            #endif
        }
        .onChange(of: selectedDestination) { _, destination in
            visitedDestinations.insert(destination)
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { artifactInspector.isVisible },
            set: { if !$0 { artifactInspector.close() } }
        )) {
            ArtifactInspectorView()
        }
        #endif
    }

    @ViewBuilder
    private func destinationContent(_ destination: AppDestination) -> some View {
        switch destination {
        case .chat:
            ChatView(openSessionId: $openSessionId)
        case .tasks:
            InboxView(
                onCountChanged: { pendingApprovalCount = $0 },
                onReplyInChat: { sessionId in
                    openSessionId = sessionId
                    selectedDestination = .chat
                }
            )
        case .library:
            LibraryView()
        case .settings:
            SettingsView()
        }
    }

    #if os(iOS)
    private var mobileTabView: some View {
        TabView(selection: $selectedDestination) {
            Tab("Chat", systemImage: AppDestination.chat.systemImage, value: AppDestination.chat) {
                destinationContent(.chat)
            }
            Tab("Tasks", systemImage: AppDestination.tasks.systemImage, value: AppDestination.tasks) {
                destinationContent(.tasks)
            }
            .badge(pendingApprovalCount)
            Tab("Library", systemImage: AppDestination.library.systemImage, value: AppDestination.library) {
                destinationContent(.library)
            }
            Tab("Settings", systemImage: AppDestination.settings.systemImage, value: AppDestination.settings) {
                destinationContent(.settings)
            }
        }
    }
    #endif

    #if os(macOS)
    private var destinationHost: some View {
        ZStack {
            ForEach(AppDestination.allCases.filter { visitedDestinations.contains($0) }) { destination in
                destinationContent(destination)
                    .opacity(selectedDestination == destination ? 1 : 0)
                    .allowsHitTesting(selectedDestination == destination)
                    .accessibilityHidden(selectedDestination != destination)
                    .zIndex(selectedDestination == destination ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var destinationRail: some View {
        VStack(spacing: 8) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PersonaAccent.color(for: "family_assistant"))
                .frame(width: 36, height: 36)
                .padding(.bottom, 4)

            railButton(.chat)
            railButton(.tasks)
            railButton(.library)

            Spacer(minLength: 20)

            railButton(.settings)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    private func railButton(_ destination: AppDestination) -> some View {
        let isSelected = selectedDestination == destination

        return Button {
            visitedDestinations.insert(destination)
            selectedDestination = destination
        } label: {
            Image(systemName: destination.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : Theme.textDim)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            isSelected
                                ? PersonaAccent.color(for: "family_assistant").opacity(0.22)
                                : Color.clear
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if destination == .tasks, pendingApprovalCount > 0 {
                        Text(pendingApprovalCount > 99 ? "99+" : "\(pendingApprovalCount)")
                            .font(Theme.mono(8, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Theme.onDevice, in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(destination.title)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var artifactInspectorResizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Theme.strokeUp)
                .frame(width: 1)
            Rectangle()
                .fill(.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
        }
        .frame(width: 9)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let currentX = value.location.x
                    if let previousX = artifactInspectorLastDragX {
                        let delta = previousX - currentX
                        artifactInspectorWidth = min(1_200, max(340, artifactInspectorWidth + delta))
                    }
                    artifactInspectorLastDragX = currentX
                }
                .onEnded { _ in
                    artifactInspectorLastDragX = nil
                }
        )
    }
    #endif
}

// MARK: - Login

struct LoginView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = ""
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
                TextField("http://your-server:30417", text: $serverURL)
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
        .environment(ArtifactInspectorState())
        .modelContainer(
            for: [ServerConfig.self, CachedConversation.self, CachedMessage.self],
            inMemory: true
        )
}
