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
import Observation
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

enum ApplicationToolbarCommand: Equatable {
    case toggleContextSidebar
    case chatNewConversation
    case chatNewIncognitoConversation
    case chatOpenExplorer
    case chatEditProfile
    case codingNewSession
    case codingRefresh
    case tasksCreate
    case libraryUpload
    case libraryLinkSource
    case librarySemanticSearch
}

@Observable
final class ApplicationToolbarState {
    private(set) var commandSequence = 0
    private(set) var command: ApplicationToolbarCommand?
    var chatProfileAvailable = false
    var librarySearchAvailable = false
    var libraryFilterText = ""
    var backendReachable = false
    func send(_ command: ApplicationToolbarCommand) {
        self.command = command
        commandSequence += 1
    }
}

@Observable
final class WorkspaceLayoutState {
    static let destinationRailWidth: CGFloat = 58
    static let destinationRailSeparatorWidth: CGFloat = 1
    static let chatSidebarMinimumWidth: CGFloat = 220
    static let chatSidebarMaximumWidth: CGFloat = 420
    static let inspectorMinimumWidth: CGFloat = 340
    static let inspectorMaximumWidth: CGFloat = 1_200

    private static let chatSidebarWidthKey = "workspace.chat.sidebar.width"
    private static let inspectorWidthKey = "workspace.inspector.width"

    var chatSidebarVisible = true
    var codingSidebarVisible = true
    var codingSidebarWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(codingSidebarWidth), forKey: "workspace.coding.sidebar.width") }
    }
    var inspectorVisible = false

    var chatSidebarWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(chatSidebarWidth), forKey: Self.chatSidebarWidthKey)
        }
    }

    var inspectorWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(inspectorWidth), forKey: Self.inspectorWidthKey)
        }
    }

    init() {
        let codingWidth = UserDefaults.standard.double(forKey: "workspace.coding.sidebar.width")
        codingSidebarWidth = Self.clamp(codingWidth > 0 ? CGFloat(codingWidth) : 280,
                                       minimum: Self.chatSidebarMinimumWidth, maximum: Self.chatSidebarMaximumWidth)
        let storedSidebarWidth = UserDefaults.standard.double(forKey: Self.chatSidebarWidthKey)
        let storedInspectorWidth = UserDefaults.standard.double(forKey: Self.inspectorWidthKey)
        chatSidebarWidth = Self.clamp(
            storedSidebarWidth > 0 ? CGFloat(storedSidebarWidth) : 280,
            minimum: Self.chatSidebarMinimumWidth,
            maximum: Self.chatSidebarMaximumWidth
        )
        inspectorWidth = Self.clamp(
            storedInspectorWidth > 0 ? CGFloat(storedInspectorWidth) : 480,
            minimum: Self.inspectorMinimumWidth,
            maximum: Self.inspectorMaximumWidth
        )
    }

    func setChatSidebarWidth(_ width: CGFloat) {
        chatSidebarWidth = Self.clamp(
            width,
            minimum: Self.chatSidebarMinimumWidth,
            maximum: Self.chatSidebarMaximumWidth
        )
    }

    func setCodingSidebarWidth(_ width: CGFloat) {
        codingSidebarWidth = Self.clamp(width, minimum: Self.chatSidebarMinimumWidth, maximum: Self.chatSidebarMaximumWidth)
    }

    func setInspectorWidth(_ width: CGFloat) {
        inspectorWidth = Self.clamp(
            width,
            minimum: Self.inspectorMinimumWidth,
            maximum: Self.inspectorMaximumWidth
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, value))
    }
}

private struct LibraryToolbarSearchField: View {
    @Bindable var state: ApplicationToolbarState

    var body: some View {
        TextField("Filter documents", text: $state.libraryFilterText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
            .accessibilityLabel("Filter library documents")
    }
}

private struct ApplicationToolbarStateKey: EnvironmentKey {
    static let defaultValue = ApplicationToolbarState()
}

private struct ApplicationDestinationActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct WorkspaceLayoutStateKey: EnvironmentKey {
    static let defaultValue = WorkspaceLayoutState()
}

#if os(macOS)
private struct FixedChatTitlebarControls: View {
    let isAdmin: Bool
    let newTitle: String
    let toggleSidebar: () -> Void
    let newConversation: () -> Void
    let newIncognitoConversation: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            titlebarButton(systemImage: "sidebar.left", action: toggleSidebar)
                .help("Show or hide sidebar")
                .accessibilityLabel("Show or hide sidebar")

            if isAdmin {
                Menu {
                    Button("New Conversation", systemImage: "plus", action: newConversation)
                    Button(
                        "New Incognito Session",
                        systemImage: "eyeglasses.slash",
                        action: newIncognitoConversation
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 9)
                    .background(.white.opacity(0.055), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                } primaryAction: {
                    newConversation()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New conversation")
            } else {
                titlebarButton(systemImage: "square.and.pencil", action: newConversation)
                    .help(newTitle)
                    .accessibilityLabel(newTitle)
            }
        }
        .fixedSize()
    }

    private func titlebarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.055), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatTitlebarIdentity: View {
    let title: String
    var body: some View {
        HStack(spacing: 28) {
            Rectangle()
                .fill(Theme.strokeUp)
                .frame(width: 1, height: 36)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .fixedSize()
    }
}

private final class TitlebarWindowProbeView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}

private struct WorkspaceTitlebarHost: NSViewRepresentable {
    let isActive: Bool
    let title: String
    let isAdmin: Bool
    let sidebarVisible: Bool
    let sidebarWidth: CGFloat
    let inspectorVisible: Bool
    let inspectorWidth: CGFloat
    let toggleSidebar: () -> Void
    let newConversation: () -> Void
    let newIncognitoConversation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TitlebarWindowProbeView {
        let probe = TitlebarWindowProbeView(frame: .zero)
        configure(probe, coordinator: context.coordinator)
        return probe
    }

    func updateNSView(_ nsView: TitlebarWindowProbeView, context: Context) {
        configure(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: TitlebarWindowProbeView, coordinator: Coordinator) {
        nsView.windowDidChange = nil
        coordinator.remove()
    }

    private func configure(_ probe: TitlebarWindowProbeView, coordinator: Coordinator) {
        let install: @MainActor (NSWindow?) -> Void = { window in
            coordinator.install(
                in: window,
                isActive: isActive,
                title: title,
                controls: controls,
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                inspectorVisible: inspectorVisible,
                inspectorWidth: inspectorWidth
            )
        }
        probe.windowDidChange = { window in
            Task { @MainActor in install(window) }
        }
        if let window = probe.window {
            Task { @MainActor in install(window) }
        }
    }

    private var controls: FixedChatTitlebarControls {
        FixedChatTitlebarControls(
            isAdmin: isAdmin,
            newTitle: title == "Code" ? "New coding session" : "New conversation",
            toggleSidebar: toggleSidebar,
            newConversation: newConversation,
            newIncognitoConversation: newIncognitoConversation
        )
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var controlsView: NSHostingView<FixedChatTitlebarControls>?
        private var identityView: NSHostingView<ChatTitlebarIdentity>?
        private var identityLeadingConstraint: NSLayoutConstraint?
        private var identityTrailingConstraint: NSLayoutConstraint?

        func install(
            in window: NSWindow?,
            isActive: Bool,
            title: String,
            controls: FixedChatTitlebarControls,
            sidebarVisible: Bool,
            sidebarWidth: CGFloat,
            inspectorVisible: Bool,
            inspectorWidth: CGFloat
        ) {
            guard isActive else {
                remove()
                return
            }
            guard let window else { return }

            if self.window !== window {
                remove()
            }

            if let controlsView {
                controlsView.rootView = controls
                identityView?.rootView = ChatTitlebarIdentity(title: title)
                updateLayout(
                    sidebarVisible: sidebarVisible,
                    sidebarWidth: sidebarWidth,
                    inspectorVisible: inspectorVisible,
                    inspectorWidth: inspectorWidth
                )
                return
            }

            guard
                let zoomButton = window.standardWindowButton(.zoomButton),
                let titlebar = zoomButton.superview
            else { return }

            let controlsView = NSHostingView(rootView: controls)
            controlsView.translatesAutoresizingMaskIntoConstraints = false
            titlebar.addSubview(controlsView)

            let identityView = NSHostingView(rootView: ChatTitlebarIdentity(title: title))
            identityView.translatesAutoresizingMaskIntoConstraints = false
            titlebar.addSubview(identityView)
            let identityLeadingConstraint = identityView.leadingAnchor.constraint(
                equalTo: titlebar.leadingAnchor,
                constant: 205
            )
            let identityTrailingConstraint = identityView.trailingAnchor.constraint(
                lessThanOrEqualTo: titlebar.trailingAnchor,
                constant: -80
            )
            identityTrailingConstraint.priority = .defaultHigh

            NSLayoutConstraint.activate([
                controlsView.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 14),
                controlsView.centerYAnchor.constraint(equalTo: zoomButton.centerYAnchor),
                identityLeadingConstraint,
                identityTrailingConstraint,
                identityView.centerYAnchor.constraint(equalTo: zoomButton.centerYAnchor)
            ])

            self.window = window
            self.controlsView = controlsView
            self.identityView = identityView
            self.identityLeadingConstraint = identityLeadingConstraint
            self.identityTrailingConstraint = identityTrailingConstraint
            updateLayout(
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                inspectorVisible: inspectorVisible,
                inspectorWidth: inspectorWidth
            )
        }

        private func updateLayout(
            sidebarVisible: Bool,
            sidebarWidth: CGFloat,
            inspectorVisible: Bool,
            inspectorWidth: CGFloat
        ) {
            guard
                let titlebar = identityView?.superview,
                let controlsView
            else { return }

            titlebar.layoutSubtreeIfNeeded()
            let collapsedX = controlsView.frame.maxX + 18
            let sidebarEdge = WorkspaceLayoutState.destinationRailWidth
                + WorkspaceLayoutState.destinationRailSeparatorWidth
                + sidebarWidth
            let identityX = sidebarVisible ? max(sidebarEdge, collapsedX) : collapsedX
            let trailingReservation = inspectorVisible ? inspectorWidth + 16 : 80

            identityLeadingConstraint?.constant = identityX
            identityTrailingConstraint?.constant = -trailingReservation
            titlebar.needsLayout = true
            titlebar.layoutSubtreeIfNeeded()
        }

        func remove() {
            controlsView?.removeFromSuperview()
            identityView?.removeFromSuperview()
            controlsView = nil
            identityView = nil
            identityLeadingConstraint = nil
            identityTrailingConstraint = nil
            window = nil
        }
    }
}
#endif

extension EnvironmentValues {
    var applicationToolbarState: ApplicationToolbarState {
        get { self[ApplicationToolbarStateKey.self] }
        set { self[ApplicationToolbarStateKey.self] = newValue }
    }

    var applicationDestinationIsActive: Bool {
        get { self[ApplicationDestinationActiveKey.self] }
        set { self[ApplicationDestinationActiveKey.self] = newValue }
    }

    var workspaceLayoutState: WorkspaceLayoutState {
        get { self[WorkspaceLayoutStateKey.self] }
        set { self[WorkspaceLayoutStateKey.self] = newValue }
    }
}

private enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case chat
    case coding
    case tasks
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .coding: "Code"
        case .tasks: "Tasks"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .tasks: "checklist"
        case .library: "books.vertical.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainTabView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ArtifactInspectorState.self) private var artifactInspector

    @State private var pendingApprovalCount = 0
    @State private var selectedDestination: AppDestination = .chat
    @State private var visitedDestinations: Set<AppDestination> = [.chat]
    @State private var applicationToolbarState = ApplicationToolbarState()
    @State private var workspaceLayoutState = WorkspaceLayoutState()
    @State private var openSessionId: Int? = nil
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
            }
            WorkspaceInspectorView()
                .frame(width: workspaceLayoutState.inspectorWidth)
                .frame(width: artifactInspector.isVisible ? workspaceLayoutState.inspectorWidth : 0)
                .clipped()
                .allowsHitTesting(artifactInspector.isVisible)
                .accessibilityHidden(!artifactInspector.isVisible)
            #endif
        }
        .environment(\.applicationToolbarState, applicationToolbarState)
        .environment(\.workspaceLayoutState, workspaceLayoutState)
        #if os(macOS)
        .navigationTitle(selectedDestination == .chat || selectedDestination == .coding ? "" : selectedDestination.title)
        .toolbar { applicationToolbar }
        .background {
            WorkspaceTitlebarHost(
                isActive: selectedDestination == .chat || selectedDestination == .coding,
                title: selectedDestination.title,
                isAdmin: selectedDestination == .chat && authManager.currentUser?.isAdmin == true,
                sidebarVisible: selectedDestination == .coding ? workspaceLayoutState.codingSidebarVisible : workspaceLayoutState.chatSidebarVisible,
                sidebarWidth: selectedDestination == .coding ? workspaceLayoutState.codingSidebarWidth : workspaceLayoutState.chatSidebarWidth,
                inspectorVisible: artifactInspector.isVisible,
                inspectorWidth: workspaceLayoutState.inspectorWidth,
                toggleSidebar: {
                    applicationToolbarState.send(.toggleContextSidebar)
                },
                newConversation: {
                    applicationToolbarState.send(selectedDestination == .coding ? .codingNewSession : .chatNewConversation)
                },
                newIncognitoConversation: {
                    applicationToolbarState.send(.chatNewIncognitoConversation)
                }
            )
            .allowsHitTesting(false)
        }
        #endif
        .onChange(of: selectedDestination) { _, destination in
            visitedDestinations.insert(destination)
            artifactInspector.setDestination(destination.rawValue)
        }
        .onDisappear { artifactInspector.configure(account: nil) }
        .onChange(of: inspectorAccount, initial: true) { _, account in
            artifactInspector.configure(account: account)
        }
        .onChange(of: artifactInspector.isVisible, initial: true) { _, isVisible in
            workspaceLayoutState.inspectorVisible = isVisible
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { artifactInspector.isVisible },
            set: { if !$0 { artifactInspector.close() } }
        )) {
            WorkspaceInspectorView()
        }
        #endif
    }

    private var inspectorAccount: InspectorAccountScope? {
        guard let server = authManager.serverURL, let user = authManager.currentUser else { return nil }
        return InspectorAccountScope(server: server.absoluteString, userID: user.id)
    }

    @ViewBuilder
    private func destinationContent(_ destination: AppDestination) -> some View {
        switch destination {
        case .chat:
            ChatView(openSessionId: $openSessionId)
        case .coding:
            #if os(macOS)
            CodingWorkspaceView()
            #else
            ContentUnavailableView("Coding is available on Mac", systemImage: "desktopcomputer")
            #endif
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
            let account = inspectorAccount
            SettingsView(onOpenPersonaTest: { sessionId in
                guard account == inspectorAccount else { return }
                openSessionId = sessionId
                selectedDestination = .chat
            })
            .id(account)
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
    @ToolbarContentBuilder
    private var applicationToolbar: some ToolbarContent {
        if selectedDestination == .settings {
            ToolbarItem(placement: .navigation) {
                Button {
                    applicationToolbarState.send(.toggleContextSidebar)
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Show or hide sidebar")
                .accessibilityLabel("Show or hide sidebar")
            }
        }

        switch selectedDestination {
        case .coding:
            ToolbarItem(placement: .automatic) {
                Button {
                    applicationToolbarState.send(.codingRefresh)
                } label: {
                    Label("Refresh Coding Workspace", systemImage: "arrow.clockwise")
                }
                .help("Refresh coding workspace")
            }
        case .chat:
            ToolbarItem(placement: .automatic) {
                Button { applicationToolbarState.send(.chatOpenExplorer) } label: { Label("My Workspace", systemImage: "folder") }
                    .help("Browse your Fruitcake workspace files; opening a file does not attach it to Chat")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    applicationToolbarState.send(.chatEditProfile)
                } label: {
                    Label("Conversation Profile", systemImage: "slider.horizontal.3")
                }
                .disabled(!applicationToolbarState.chatProfileAvailable)
                .help("Conversation profile")
            }

        case .tasks:
            ToolbarItem(placement: .primaryAction) {
                Button {
                    applicationToolbarState.send(.tasksCreate)
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New task")
            }

        case .library:
            ToolbarItem(placement: .automatic) {
                LibraryToolbarSearchField(state: applicationToolbarState)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Upload Document", systemImage: "doc.badge.plus") {
                        applicationToolbarState.send(.libraryUpload)
                    }
                    .disabled(!applicationToolbarState.backendReachable)

                    Button("Link Source", systemImage: "point.3.connected.trianglepath.dotted") {
                        applicationToolbarState.send(.libraryLinkSource)
                    }
                    .disabled(!applicationToolbarState.backendReachable)
                } label: {
                    Label("Add to Library", systemImage: "plus")
                }
                .help("Add to library")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    applicationToolbarState.send(.librarySemanticSearch)
                } label: {
                    Label("Semantic Search", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(!applicationToolbarState.librarySearchAvailable)
                .help("Semantic search")
            }

        case .settings:
            ToolbarItem(placement: .automatic) {
                EmptyView()
            }
        }

        if artifactInspector.hasSelection || artifactInspector.canReopen || artifactInspector.notice != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if artifactInspector.isVisible {
                        artifactInspector.close()
                    } else {
                        artifactInspector.show()
                    }
                } label: {
                    Label(
                        artifactInspector.isVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.right"
                    )
                }
                .help(artifactInspector.isVisible ? "Hide inspector" : "Show inspector")
            }
        }
    }

    private var destinationHost: some View {
        ZStack {
            ForEach(AppDestination.allCases.filter { visitedDestinations.contains($0) }) { destination in
                destinationContent(destination)
                    .environment(\.applicationDestinationIsActive, selectedDestination == destination)
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
            if authManager.currentUser?.isParent == true {
                railButton(.coding)
            }
            railButton(.tasks)
            railButton(.library)

            Spacer(minLength: 20)

            railButton(.settings)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
            .frame(width: WorkspaceLayoutState.destinationRailWidth)
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
                        workspaceLayoutState.setInspectorWidth(
                            workspaceLayoutState.inspectorWidth + delta
                        )
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
