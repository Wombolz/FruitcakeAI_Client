#if os(macOS)
import SwiftUI
import AppKit

enum CodingRepositorySetupMode: String, Identifiable {
    case create, authorize
    var id: String { rawValue }
    var title: String { self == .create ? "Create Repository" : "Authorize Repository" }

    @MainActor func makePanel() -> NSSavePanel {
        let panel: NSSavePanel
        if self == .create {
            let save = NSSavePanel()
            save.nameFieldStringValue = "NewRepository"
            save.nameFieldLabel = "Repository name:"
            save.prompt = "Choose Location"
            save.canCreateDirectories = true
            panel = save
        } else {
            let open = NSOpenPanel()
            open.canChooseDirectories = true
            open.canChooseFiles = false
            open.allowsMultipleSelection = false
            open.canCreateDirectories = false
            open.prompt = "Choose Repository"
            panel = open
        }
        panel.title = title
        panel.message = self == .create ? "Choose a new folder name. Git setup happens only after Create & Authorize." : "Select the repository root, not its .git folder."
        return panel
    }
}

struct CodingWorkspaceView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.applicationDestinationIsActive) private var isActive
    @Environment(\.applicationToolbarState) private var toolbar
    @Environment(\.workspaceLayoutState) private var layout
    @Environment(ArtifactInspectorState.self) private var inspector
    @State private var store: CodingWorkspaceStore?
    @State private var showingNew = false
    @State private var openingExplorer = false
    @State private var showingReview = false
    @State private var reviewPage = CodingReviewPage.setup
    @State private var repositorySetup: CodingRepositorySetupMode?
    @State private var lastDragX: CGFloat?
    @State private var diffDragStartHeight: Double?
    @AppStorage("workspace.coding.diff.height") private var diffHeight = 380.0
    @State private var diffWindow: CodingDiffWindowController?
    @State private var confirmingCheckout = false
    @State private var confirmingRemoval = false
    @State private var confirmingEdits = false
    @State private var confirmingCommands = false
    @State private var confirmingDelete = false
    @State private var checkoutDetailsExpanded = false
    @State private var deletingSessionId: String?

    init(store: CodingWorkspaceStore? = nil) {
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            if let store { workspace(store) }
            else { ProgressView("Loading coding workspace") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .tint(Theme.codeAccent)
        .task {
            if store == nil { store = CodingWorkspaceStore(api: APIClient(authManager: auth)) }
            if isActive { await store?.resume() }
        }
        .onChange(of: store?.selectedId) { _, id in
            inspector.setCodingSession(id, active: isActive)
        }
        .onChange(of: isActive) { _, active in
            inspector.setCodingSession(store?.selectedId, active: active)
            if active { Task { await store?.resume() } }
            else {
                store?.suspend()
            }
        }
        .onDisappear {
            if let store { inspector.closeCoding(for: store); store.suspend() }
            diffWindow?.close(); diffWindow = nil
        }
        .onChange(of: toolbar.commandSequence) { _, _ in
            guard isActive else { return }
            switch toolbar.command {
            case .toggleContextSidebar: layout.codingSidebarVisible.toggle()
            case .codingNewSession: showingNew = true
            case .codingRefresh: Task { await store?.resume() }
            default: break
            }
        }
        .sheet(isPresented: $showingNew) {
            if let store { CodingSessionSetup(store: store) }
        }
        .sheet(isPresented: $showingReview) {
            if let store {
                CodingReviewSetup(workspace: store, initialPage: reviewPage) {
                    store.aiReview.inspectorMode = "review"
                    inspector.openCoding(store)
                }
            }
        }
        .sheet(item: $repositorySetup) { mode in
            if let store, let user = auth.currentUser { CodingGrantSheet(store: store, userId: user.id, mode: mode) }
        }
        .confirmationDialog("Delete this coding conversation?", isPresented: $confirmingDelete) {
            Button("Delete Conversation", role: .destructive) {
                if let id = deletingSessionId, let store { Task { await store.removeConversation(id: id, delete: true) } }
            }
        } message: {
            Text("Removes the conversation from the app. Checkout files and commits are kept. Backend history and approval records are retained for provenance; this is not secure erasure. Stop active work first.")
        }
        .confirmationDialog("Create an isolated checkout?", isPresented: $confirmingCheckout) {
            Button("Create Isolated Checkout") { if let store { Task { await store.createCheckout() } } }
        } message: {
            Text("Creates a detached worktree at the source repository's current commit, not a named branch. Your conversation is kept; the source runtime is retired and the next run starts in the checkout. Uncommitted and ignored files are not copied. The repository needs an existing Git commit. Then choose Enable Approved Edits to edit; creating the checkout alone does not enable writes.")
        }
        .confirmationDialog("Enable offline container commands?", isPresented: $confirmingCommands) {
            Button("Enable Container Commands") { if let store { Task { await store.setCommandMode(true) } } }
        } message: {
            Text("Each command requires review and approval. Commands run in a separate Linux Docker container with ONLY this checkout mounted writable. They can change or delete any checkout file, without separate file-edit approvals. Networking, personal folders, credentials, and the Docker socket are not provided. Commands cannot build macOS-native targets. Host Bash remains disabled.")
        }
        .confirmationDialog("Remove this clean checkout?", isPresented: $confirmingRemoval) {
            Button("Remove Clean Checkout", role: .destructive) { if let store { Task { await store.removeCheckout() } } }
        } message: {
            Text("Only this session's disposable checkout is removed. Local changes, including ignored files, prevent removal. The source repository is never removed.")
        }
        .confirmationDialog("Enable approved edits in this checkout?", isPresented: $confirmingEdits) {
            Button("Enable Approved Edits") { if let store { Task { await store.setEditMode(true) } } }
        } message: {
            Text("Fruitcake will ask you to review each complete, bounded file change before applying it to this isolated checkout. This enables file proposals only. Commands require their separate opt-in and approval; commits and source delivery remain separate explicit actions.")
        }
    }

    private func workspace(_ store: CodingWorkspaceStore) -> some View {
        HStack(spacing: 0) {
            if layout.codingSidebarVisible {
                sidebar(store)
                    .frame(width: layout.codingSidebarWidth)
                    .background(Theme.sidebar)
                Rectangle().fill(Theme.strokeUp).frame(width: 1)
                    .overlay {
                        Color.clear.frame(width: 9).contentShape(Rectangle())
                            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    if let previous = lastDragX { layout.setCodingSidebarWidth(layout.codingSidebarWidth + value.location.x - previous) }
                                    lastDragX = value.location.x
                                }
                                .onEnded { _ in lastDragX = nil })
                    }
            }
            VStack(spacing: 0) {
                header(store)
                if store.selected != nil { checkoutStatus(store) }
                if let notice = store.deliveryNotice {
                    CodingDeliveryNoticeBanner(notice: notice, dismiss: store.dismissDeliveryNotice)
                }
                if let error = store.errorMessage {
                    HStack(alignment: .top) {
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        Button("Dismiss", systemImage: "xmark") { store.errorMessage = nil }.labelStyle(.iconOnly)
                    }
                    .foregroundStyle(Theme.onDevice).padding(12).background(Theme.onDevice.opacity(0.08))
                }
                if store.loading && !store.available { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if !store.available {
                    ContentUnavailableView {
                        Label("Coding unavailable", systemImage: "chevron.left.forwardslash.chevron.right")
                    } description: {
                        Text("Enable the coding runtime on the backend after applying migrations through 057 and configuring an installed Pi executable. Source sessions are read-only; isolated checkouts support explicit edit, command, and Git delivery actions.")
                    } actions: { Button("Check Again") { Task { await store.resume() } } }
                } else if store.selected == nil {
                    ContentUnavailableView {
                        Label("Inspect a repository", systemImage: "folder.badge.gearshape")
                    } description: { Text("Start a read-only session with an explicitly authorized repository and local model. Chat projects do not grant repository access.") }
                    actions: {
                        Button("New Coding Session") { showingNew = true }
                            .disabled(store.models.isEmpty || !store.workspaces.contains { $0.isActive })
                        if auth.currentUser?.isAdmin == true {
                            Button("Create Repository") { repositorySetup = .create }
                            Button("Authorize Repository") { repositorySetup = .authorize }
                        }
                    }
                } else {
                    conversation(store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversation(_ store: CodingWorkspaceStore) -> some View {
        GeometryReader { geometry in
            let drawerHeight = CodingDiffDrawerSizing.height(preferred: diffHeight, available: geometry.size.height)
            VStack(spacing: 0) {
                if store.diffVisible || store.deliveryAction != nil, drawerHeight >= 160 {
                    Group {
                        if let action = store.deliveryAction, let sessionId = store.selectedId {
                            CodingDeliveryPanel(store: store, sessionId: sessionId, action: action) { diff in
                                if diffWindow == nil { diffWindow = CodingDiffWindowController() }
                                diffWindow?.show(diff)
                            }.id(sessionId + action)
                        } else { CodingDiffDrawer(store: store, popOut: { openDiffWindow(store) }) }
                    }
                        .frame(height: drawerHeight).clipped()
                    ZStack {
                        Theme.composer
                        Capsule().fill(Theme.textFaint.opacity(0.65)).frame(width: 44, height: 3)
                    }
                    .frame(height: 10).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if diffDragStartHeight == nil {
                                diffDragStartHeight = CodingDiffDrawerSizing.height(preferred: diffHeight, available: geometry.size.height)
                            }
                            diffHeight = CodingDiffDrawerSizing.height(
                                preferred: (diffDragStartHeight ?? diffHeight) + value.translation.height,
                                available: geometry.size.height)
                        }
                        .onEnded { _ in diffDragStartHeight = nil })
                    .help("Drag to resize the diff panel")
                } else if store.diffVisible || store.deliveryAction != nil {
                    HStack {
                        Text("Enlarge the window or pop out the diff.").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        Spacer(minLength: 4)
                        Button { openDiffWindow(store) } label: { Image(systemName: "macwindow.on.rectangle") }
                            .disabled(store.repositoryDiff == nil).help("Open diff window")
                        Button { store.closeDiff(); store.deliveryAction = nil } label: { Image(systemName: "xmark") }.help("Close diff panel")
                    }.padding(8).frame(height: 44)
                }
                transcript(store)
                composer(store)
            }
        }
        .onChange(of: store.diffVisible) { _, _ in diffDragStartHeight = nil }
    }

    private func openDiffWindow(_ store: CodingWorkspaceStore) {
        guard let diff = store.repositoryDiff else { return }
        if diffWindow == nil { diffWindow = CodingDiffWindowController() }
        diffWindow?.show(diff)
        store.closeDiff()
    }

    private func sidebar(_ store: CodingWorkspaceStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CODING SESSIONS").font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                Spacer()
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("New read-only coding session").disabled(!store.available)
            }.padding(.horizontal, 14).padding(.top, 14)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.sessions) { session in
                        Button { Task { await store.select(session.id) } } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                CodingStatusBadge(status: session.status, compact: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(store.selectedId == session.id ? Theme.codeAccent.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(store.showingArchived ? "Restore Conversation" : "Archive Conversation") {
                                Task { await store.removeConversation(id: session.id, delete: false, archived: !store.showingArchived) }
                            }
                            Button("Delete Conversation", role: .destructive) { deletingSessionId = session.id; confirmingDelete = true }
                        }
                    }
                    if store.hasMoreSessions { Button("Load More Sessions") { Task { await store.moreSessions() } }.disabled(store.loading) }
                }.padding(.horizontal, 8)
            }
            Button(store.showingArchived ? "Show Conversations" : "Show Archived", systemImage: "archivebox") {
                Task { await store.toggleArchivedSessions() }
            }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 14).disabled(store.actionInFlight || store.pending != nil)
            if auth.currentUser?.isAdmin == true {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Create Repository", systemImage: "folder.badge.plus") { repositorySetup = .create }
                    Button("Authorize Repository", systemImage: "folder") { repositorySetup = .authorize }
                }.buttonStyle(.plain).font(.system(size: 12)).padding(14).disabled(!store.available)
            }
        }.foregroundStyle(Theme.text)
    }

    private func header(_ store: CodingWorkspaceStore) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.gearshape").font(.system(size: 16))
                .foregroundStyle(Theme.codeAccent).frame(width: 34, height: 34)
                .background(Theme.codeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.selected?.title ?? "Coding workspace").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(store.checkout?.canonicalPath ?? store.workspace?.canonicalPath ?? store.connection)
                    .font(Theme.mono(10)).foregroundStyle(Theme.textDim).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                headerActions(store).labelStyle(.titleAndIcon)
                headerActions(store).labelStyle(.iconOnly)
            }
        }
        .foregroundStyle(Theme.text).padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.strokeUp).frame(height: 1) }
    }

    private func headerActions(_ store: CodingWorkspaceStore) -> some View {
        HStack(spacing: 6) {
            if store.selected != nil {
                Button("Explorer", systemImage: "folder") {
                    guard !openingExplorer else { return }
                    openingExplorer = true
                    Task {
                        defer { openingExplorer = false }
                        let sessionID = store.selectedId
                        if let source = await store.explorerSource(), store.selectedId == sessionID, isActive {
                            inspector.openExplorer(source)
                        }
                    }
                }
                .disabled(openingExplorer || !store.available || store.checkout?.status != "ready")
                .help("Browse the ready managed checkout without granting edits or model access")
                Button("Changes", systemImage: "doc.text.magnifyingglass") {
                    store.aiReview.inspectorMode = "changes"
                    inspector.openCoding(store)
                }
                    .disabled(!store.available || store.workspace?.isActive != true || store.executionPath == nil || (store.checkout != nil && store.checkout?.status != "ready"))
                    .help("Inspect live Git changes without an AI model call")
                HStack(spacing: 4) {
                    Button("Review", systemImage: "checkmark.bubble") {
                        Task {
                            let sessionId = store.selectedId
                            let reopened = await store.aiReview.reopen()
                            guard store.selectedId == sessionId, isActive else { return }
                            if reopened { inspector.openCoding(store) }
                            else {
                                reviewPage = store.aiReview.error == nil ? .setup : .history
                                showingReview = true
                            }
                        }
                    }
                    .help("Reopen saved review findings without another model call; set up a review if none exist")
                    Menu {
                        Button("New Review\u{2026}") { reviewPage = .setup; showingReview = true }
                        Button("Review History\u{2026}") { reviewPage = .history; showingReview = true }
                    } label: { Image(systemName: "chevron.down") }
                    .menuIndicator(.hidden).fixedSize().help("New review or saved review history")
                }
                .disabled(!store.available || !store.aiReview.enabled || store.aiReview.loading)
            }
            if let path = store.executionPath {
                Menu {
                    Button("Open Local Folder") { open(path) }
                    Button("Open in Visual Studio Code") { open(path, application: "com.microsoft.VSCode") }
                    Button("Open in Xcode") { open(path, application: "com.apple.dt.Xcode") }
                } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Open the matching repository path on this Mac")
            }
            Button { Task { await store.resume() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(store.loading || store.actionInFlight).help("Refresh and reconcile coding state")
            if store.selected != nil {
                Menu {
                    Menu("Switch Model (resets edit/command opt-ins)") {
                        ForEach(store.models) { model in
                            Button(model.label + (model.id == store.selected?.modelProfileId ? " (current)" : "")) {
                                Task { await store.changeModel(model.id) }
                            }.disabled(model.id == store.selected?.modelProfileId)
                        }
                    }.disabled(!store.canManageWorkspace || store.selected?.isClosed != false)
                    if store.checkout?.status == "ready" {
                        Button("Create Commit…") { store.deliveryAction = "commit" }.disabled(!store.canManageWorkspace)
                        if auth.currentUser?.isAdmin == true {
                            Button("Apply Commits to Source…") { store.deliveryAction = "apply" }.disabled(!store.canManageWorkspace)
                        }
                    }
                    Divider()
                    Button("Close Coding Session") { Task { await store.closeSelected() } }
                        .disabled(store.aiReview.busy || store.activeRun != nil || store.selected?.isClosed == true || store.actionInFlight || store.pending != nil || store.checkout?.isBusy == true)
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .buttonStyle(CodingActionStyle()).controlSize(.small)
    }

    private func checkoutStatus(_ store: CodingWorkspaceStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { checkoutIdentity(store); Spacer(minLength: 8); checkoutActions(store) }
                VStack(alignment: .leading, spacing: 8) { checkoutIdentity(store); checkoutActions(store) }
            }
            if let error = store.checkout?.errorCode {
                Label(error == "checkout_dirty" ? "Checkout retained: it contains local changes, untracked files, or ignored files."
                      : "Checkout needs attention: \(error). The source repository will not be used as a fallback.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Theme.onDevice).textSelection(.enabled)
            }
            if store.checkout == nil {
                Text(store.checkoutCreationBlockReason ?? "To edit, create an isolated checkout, then enable approved edits. Your conversation is preserved; Git needs an existing commit.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            DisclosureGroup("Checkout details", isExpanded: $checkoutDetailsExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    if let baseline = store.checkout?.baselineCommit { Text("Baseline \(baseline.prefix(12))") }
                    if let branch = store.checkout?.branchName { Text("\(branch) · HEAD \((store.checkout?.headCommit ?? "").prefix(12))") }
                    Text(store.checkout?.canonicalPath ?? store.workspace?.canonicalPath ?? "Checking execution location")
                }.font(Theme.mono(10)).foregroundStyle(Theme.textDim).textSelection(.enabled).padding(.top, 4)
            }.font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(Theme.composer)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.strokeUp).frame(height: 1) }
    }

    private func checkoutIdentity(_ store: CodingWorkspaceStore) -> some View {
        HStack(spacing: 8) {
            Text(store.checkout != nil ? "Isolated checkout" : "Source repository").font(.system(size: 12, weight: .medium))
            if let checkout = store.checkout { CodingStatusBadge(status: checkout.status, compact: true) }
            ConsoleChip(text: store.commandsEnabled ? "OFFLINE · CHECKOUT WRITABLE" : store.editingEnabled ? "APPROVED EDITS" : "READ ONLY",
                        accentDot: store.commandsEnabled ? Theme.onDevice : Theme.codeAccent)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func checkoutActions(_ store: CodingWorkspaceStore) -> some View {
        HStack(spacing: 8) {
            if store.supportsApprovedEdits, store.checkout?.status == "ready", store.selected?.isClosed == false {
                Button(store.editingEnabled ? "Disable Edits" : "Enable Approved Edits") {
                    if store.editingEnabled { Task { await store.setEditMode(false) } }
                    else { confirmingEdits = true }
                }.disabled(!store.canSetEditMode)
            }
            if store.checkout == nil {
                Button("Create Isolated Checkout") { confirmingCheckout = true }
                    .disabled(!store.canCreateCheckout)
                    .help(store.checkoutCreationBlockReason ?? "Keep this conversation and move future runs to a separate checkout")
            } else if store.checkout?.isBusy == true {
                ProgressView().controlSize(.small)
            } else if store.selected?.isClosed == true, let checkout = store.checkout, checkout.status != "removed" {
                Button("Remove Clean Checkout") { confirmingRemoval = true }.disabled(store.actionInFlight)
            }
            if store.supportsContainerCommands, store.checkout?.status == "ready", store.selected?.isClosed == false {
                Button(store.commandsEnabled ? "Disable Commands" : "Enable Container Commands") {
                    if store.commandsEnabled { Task { await store.setCommandMode(false) } }
                    else { confirmingCommands = true }
                }.disabled(!store.canSetCommandMode)
            }
        }
        .buttonStyle(CodingActionStyle()).fixedSize(horizontal: true, vertical: false)
    }

    private func transcript(_ store: CodingWorkspaceStore) -> some View {
        CodingTranscriptScrollView(latestRunID: store.runs.last?.id) {
            LazyVStack(alignment: .leading, spacing: 22) {
                if store.hasMoreRuns { Button("Load Earlier Runs") { Task { await store.moreRuns() } }.disabled(store.loadingRuns) }
                if store.loadingRuns { ProgressView("Loading run history") }
                if store.runs.isEmpty && !store.loadingRuns {
                    Text(store.commandsEnabled ? "Ask for a change or a test. File proposals and offline container commands each require your approval."
                         : store.editingEnabled ? "Ask for a small file change. Every change needs your approval; commands need a separate opt-in."
                         : "Ask the agent to inspect this repository. It can read and search authorized files. Enable approved edits in an isolated checkout to propose changes.")
                        .foregroundStyle(Theme.textDim).padding(.vertical, 40)
                }
                ForEach(store.runs) { run in
                    CodingRunCard(run: run, projection: store.projections[run.id], approvals: store.approvals.filter { $0.runId == run.id },
                                  actionInFlight: store.actionInFlight,
                                  loadOperations: { Task { await store.loadOperations(run) } },
                                  savedChanges: store.savedChanges[run.id],
                                  supportsChanges: store.supportsApprovedEdits,
                                  reviewedChanges: store.reviewedChanges,
                                  loadChanges: { Task { await store.loadSavedChanges(run) } },
                                  reviewChange: { store.reviewChange($0) },
                                  reviewSavedChange: { store.reviewSavedChange($0) },
                                  resolve: { approval, approved in Task { await store.resolve(approval, approved: approved) } })
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(store.selectedId)
    }

    private func composer(_ store: CodingWorkspaceStore) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 10) {
            if store.pending != nil {
                HStack {
                    Text("Submission not confirmed. Retry uses the original request ID.").font(.system(size: 12))
                    Spacer()
                    Button("Retry Submission") { Task { await store.retrySubmission() } }.disabled(store.actionInFlight)
                }.foregroundStyle(Theme.onDevice)
            }
            TextField("Ask about this repository...", text: $store.draft, axis: .vertical)
                .lineLimit(2...7).textFieldStyle(.plain).padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.strokeUp))
                .disabled(store.pending != nil || store.selected?.isClosed == true)
            HStack {
                Text(store.connection).font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                Spacer()
                if let active = store.activeRun {
                    Menu("Send Guidance") {
                        Button("Steer Current Run") { Task { await store.control("steer") } }
                        Button("Queue Follow-up") { Task { await store.control("follow_up") } }
                    }.disabled(store.actionInFlight || store.draft.isEmpty || active.status == "stopping")
                    Button("Stop", systemImage: "stop.fill") { Task { await store.stop() } }
                        .disabled(store.actionInFlight || active.status == "stopping")
                } else {
                    Button("Send", systemImage: "arrow.up") { Task { await store.submit() } }
                        .buttonStyle(CodingActionStyle(emphasis: .primary)).disabled(!store.canSubmit)
                }
            }
        }
        .padding(16).background(Theme.composer)
        .overlay(alignment: .top) { Rectangle().fill(Theme.strokeUp).frame(height: 1) }
    }

    private func open(_ path: String, application: String? = nil) {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            store?.errorMessage = "This repository path is on the backend and does not exist on this Mac. No local editor was opened."
            return
        }
        let url = URL(fileURLWithPath: path)
        if let application {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application) else {
                store?.errorMessage = "The selected editor is not installed on this Mac."
                return
            }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, error in
                if let error { Task { @MainActor in store?.errorMessage = error.localizedDescription } }
            }
        } else { NSWorkspace.shared.open(url) }
    }
}

struct CodingRepositoryReview: View {
    let store: CodingWorkspaceStore
    let close: () -> Void

    var body: some View {
        if store.aiReview.inspectorMode == "review", store.aiReview.enabled {
            CodingAIReviewInspector(workspace: store, close: close)
        } else {
            CodingLiveRepositoryReview(store: store, close: close)
        }
    }
}

struct CodingLiveRepositoryReview: View {
    let store: CodingWorkspaceStore
    let close: () -> Void
    var openFile: ((CodingChangedFile) -> Void)? = nil
    var isActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(PersonaAccent.color(for: "family_assistant"))
                Text("Changed Files").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                Button { Task { await store.refreshRepository() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(store.loadingRepository)
                    .help("Refresh repository changes").accessibilityLabel("Refresh repository changes")
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close Live Changes tab").accessibilityLabel("Close Live Changes tab")
            }.padding(14)
            Rectangle().fill(Theme.strokeUp).frame(height: 1)
            if let error = store.repositoryError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.onDevice)
                    .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if store.loadingRepository {
                ProgressView("Reading repository state").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let repository = store.repository {
                if openFile != nil {
                    fileList(repository).frame(maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            fileList(repository).frame(height: max(100, geometry.size.height * 0.5))
                            Rectangle().fill(Theme.strokeUp).frame(height: 1)
                            fileDetails(repository)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("HEAD \(repository.head.map { String($0.prefix(12)) } ?? "unborn")")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(repository.files.count) changed files").lineLimit(1)
                    }
                    Text("Observed \(repository.observedAt.formatted(date: .abbreviated, time: .standard))")
                }.font(Theme.mono(10)).foregroundStyle(Theme.textDim).padding(12)
            } else {
                Text("Refresh to load repository changes.").font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(14)
                Spacer()
            }
            Text("Read-only live repository state, not a saved checkpoint or agent-run attribution.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim).padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg).foregroundStyle(Theme.text)
        .task(id: isActive) {
            if isActive { await store.refreshRepository(preserveDiff: true) }
        }
    }

    private func fileList(_ repository: CodingRepository) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if repository.files.isEmpty {
                    Text("No tracked or untracked changes.").font(.system(size: 12))
                        .foregroundStyle(Theme.textDim).padding(12)
                }
                ForEach(repository.files) { file in
                    Button { if let openFile { openFile(file) } else { Task { await store.reviewFile(file) } } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(file.path).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(file.statusLabel).font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                            if let original = file.originalPath {
                                Text("From \(original)").font(Theme.mono(10)).foregroundStyle(Theme.textDim).lineLimit(1)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.reviewedPath == file.path ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(8)
        }
    }

    private func fileDetails(_ repository: CodingRepository) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let file = repository.files.first(where: { $0.path == store.reviewedPath }) {
                    Text("FILE DETAILS").font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                    Text(file.path).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                    Text(file.statusLabel).font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                    if store.loadingDiff { ProgressView("Reading file changes") }
                    else if let diff = store.repositoryDiff {
                        Text("Comparisons: " + diff.sections.map { $0.kind.capitalized }.joined(separator: ", "))
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        Button("View Diff", systemImage: "arrow.left.arrow.right") { store.showDiff() }
                        Text("Opens a before/after comparison above the conversation. Expand it into a resizable window from there.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                } else {
                    Text("Select a changed file to inspect its details, then open its diff above the conversation.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CodingRunCard: View {
    let run: CodingRun
    let projection: CodingProjection?
    let approvals: [CodingApproval]
    let actionInFlight: Bool
    let loadOperations: () -> Void
    let savedChanges: [CodingSavedChange]?
    let supportsChanges: Bool
    let reviewedChanges: Set<String>
    let loadChanges: () -> Void
    let reviewChange: (CodingChangePreview) -> Void
    let reviewSavedChange: (CodingSavedChange) -> Void
    let resolve: (CodingApproval, Bool) -> Void
    @State private var detailsExpanded = false
    @State private var requestedHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CodingUserMessageBubble(text: run.prompt, occurredAt: run.createdAt)
            agentContent
                .frame(maxWidth: Theme.chatAssistantMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            // Visible historical messages need their persisted timeline/times,
            // not a single run summary masquerading as the full conversation.
            if !run.isActive && projection == nil && !requestedHistory {
                requestedHistory = true
                loadOperations()
            }
        }
    }

    private var agentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CodingStatusBadge(status: run.status)
                if let model = run.modelId { Text(model).font(Theme.mono(10)).lineLimit(1).truncationMode(.middle) }
                if run.isActive { ProgressView().controlSize(.small) }
                let pendingCount = approvals.filter(\.isPending).count
                if run.isActive, pendingCount > 0 { Text("\(pendingCount) pending approval\(pendingCount == 1 ? "" : "s")").font(Theme.mono(10)) }
                if let code = run.errorCode { Text(code).font(Theme.mono(10)).foregroundStyle(Theme.onDevice) }
            }.foregroundStyle(Theme.textDim)
            if projection?.reconstructed == true {
                Label("Context reconstructed from bounded prior excerpts, not restored process memory.", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11)).foregroundStyle(Theme.onDevice).padding(.vertical, 4)
            }
            if projection?.hasAssistantText != true, !run.responseText.isEmpty {
                CodingAssistantMessage(text: run.responseText)
                Text("Message timing unavailable in this summary. Run started \(run.createdAt.formatted(Theme.messageTimestampFormat)).")
                    .font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
            }
            if let projection {
                ForEach(projection.timeline) { entry in
                    switch entry.kind {
                    case .assistant:
                        if !entry.text.isEmpty { CodingAssistantMessage(text: entry.text, occurredAt: entry.occurredAt, provisional: entry.timestampIsProvisional) }
                    case .control:
                        CodingUserMessageBubble(text: entry.text, occurredAt: entry.occurredAt)
                    case .operation:
                        if let operation = projection.operations.first(where: { $0.id == entry.text }) { operationRow(operation) }
                    case .approval:
                        if let approval = approvals.first(where: { $0.id == entry.text }) { approvalRow(approval) }
                        else { Text("Loading approval details...").font(Theme.mono(11)).foregroundStyle(Theme.textDim) }
                    }
                }
            }
            let placed = Set((projection?.timeline ?? []).filter { $0.kind == .approval }.map(\.text))
            ForEach(approvals.filter { !placed.contains($0.id) }) { approvalRow($0) }
            if !run.isActive {
                runDetails
            }
        }
    }

    private var runDetails: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Refresh History", systemImage: "arrow.clockwise", action: loadOperations)
                    if supportsChanges { Button("Refresh Changes", action: loadChanges) }
                }.buttonStyle(CodingActionStyle())
                if supportsChanges, let savedChanges {
                    if savedChanges.isEmpty {
                        Text("No host-applied change records for this run. Container-command changes are separate.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    ForEach(savedChanges) { change in
                        Button { reviewSavedChange(change) } label: {
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(Theme.codeAccent)
                                Text(change.path).lineLimit(2)
                                Spacer(minLength: 4)
                                CodingStatusBadge(status: change.status, compact: true)
                            }.font(Theme.mono(11)).padding(.vertical, 4)
                        }.buttonStyle(.plain)
                        if let error = change.errorCode { Text(error).font(Theme.mono(10)).foregroundStyle(Theme.onDevice) }
                    }
                }
            }.padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(Theme.textDim)
                Text("Run details").font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                if let projection { Text("\(projection.operations.count) operations").font(Theme.mono(10)).foregroundStyle(Theme.textDim) }
                if let savedChanges { Text("\(savedChanges.count) host changes").font(Theme.mono(10)).foregroundStyle(Theme.textDim) }
            }
        }
        .padding(10).modifier(CodingCard())
        .onChange(of: detailsExpanded) { _, expanded in
            guard expanded else { return }
            if projection == nil { loadOperations() }
            if supportsChanges && savedChanges == nil { loadChanges() }
        }
    }

    private func operationRow(_ operation: CodingOperation) -> some View {
        DisclosureGroup {
            if !operation.arguments.isEmpty { operationText("ARGUMENTS", text: operation.arguments) }
            if !operation.output.isEmpty { operationText("OUTPUT", text: operation.output) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(Theme.codeAccent)
                Text(operation.tool)
                Spacer()
                CodingStatusBadge(status: operation.status, compact: true)
            }
        }.font(Theme.mono(11)).padding(10).modifier(CodingCard())
    }

    private func operationText(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.mono(9)).foregroundStyle(Theme.textDim)
            ScrollView([.horizontal, .vertical]) {
                Text(text).font(Theme.mono(11)).foregroundStyle(Theme.textMid)
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true).padding(8)
            }.frame(height: min(240, max(40, CGFloat(text.components(separatedBy: "\n").count) * 16 + 16)))
                .background(Theme.composer, in: RoundedRectangle(cornerRadius: 6))
        }.padding(.top, 8)
    }

    private func approvalRow(_ approval: CodingApproval) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let pending = approval.status == "pending" && !approval.isExpired(at: context.date) && run.isActive
            VStack(alignment: .leading, spacing: 8) {
                if pending {
                    HStack {
                        Label(approval.title, systemImage: "hand.raised").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        CodingStatusBadge(status: "waiting_approval", compact: true)
                    }
                    if approval.expiresAt == nil {
                        Text("Waiting for you. No approval timeout.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    approvalDetails(approval)
                    HStack {
                        Button("Deny") { resolve(approval, false) }
                            .buttonStyle(CodingActionStyle())
                        Button(approval.command != nil ? "Approve Command" : approval.change == nil ? "Allow Read" : "Approve Change") { resolve(approval, true) }
                            .buttonStyle(CodingActionStyle(emphasis: .primary))
                            .disabled(approval.change.map { !reviewedChanges.contains($0.id) } ?? false)
                    }.disabled(actionInFlight)
                } else {
                    DisclosureGroup { approvalDetails(approval) } label: {
                        HStack {
                            Text(approval.title).font(.system(size: 12, weight: .medium))
                            Spacer()
                            CodingStatusBadge(status: approval.status == "pending" ? (approval.isExpired(at: context.date) ? "expired" : "run ended") : approval.status, compact: true)
                        }
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CodingCard(accent: pending ? Theme.onDevice : nil))
        }
    }

    private func approvalDetails(_ approval: CodingApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.message).font(.system(size: 12)).textSelection(.enabled)
            if let command = approval.command {
                Text(command.command).font(Theme.mono(11)).textSelection(.enabled)
                Text("/workspace/\(command.workingDirectory) · \(command.timeoutSeconds)s · network: \(command.network) · checkout writable")
                    .font(Theme.mono(10)).foregroundStyle(Theme.onDevice)
                Text("Image: \(command.image)").font(Theme.mono(9)).textSelection(.enabled)
                if let result = command.result {
                    Text("\(result.status) · exit \(result.exitCode.map(String.init) ?? "unknown")").font(Theme.mono(10))
                    if let stdout = result.stdout, !stdout.isEmpty { Text(stdout).font(Theme.mono(10)).textSelection(.enabled) }
                    if let stderr = result.stderr, !stderr.isEmpty { Text(stderr).font(Theme.mono(10)).textSelection(.enabled) }
                    if result.outputTruncated == true { Text("Saved output capped at 64 KiB per stream.").font(Theme.mono(10)) }
                    if let error = result.errorCode { Text(error).font(Theme.mono(10)).foregroundStyle(Theme.onDevice) }
                }
            }
            if let change = approval.change {
                Text(change.beforeHash == nil ? "CREATE FILE" : "REPLACE FILE CONTENT").font(Theme.mono(10))
                Button("Review Proposed Diff") { reviewChange(change) }
                Text("Complete bounded change · approval applies only to these exact bytes.")
                    .font(Theme.mono(10)).foregroundStyle(Theme.textDim)
            }
        }
    }
}

private struct CodingSessionSetup: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CodingWorkspaceStore
    @State private var workspaceId = ""
    @State private var modelId = 0
    @State private var projectId = 0
    @State private var title = "Repository inspection"
    @State private var checkoutId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Coding Session").font(.title2)
            Text("Sessions start read-only. Create an isolated checkout from the session to enable approved edits or container commands. Repository grants are separate from chat projects; only local tool-capable models are listed.")
                .foregroundStyle(Theme.textDim)
            Form {
                TextField("Title", text: $title)
                Picker("Repository", selection: $workspaceId) {
                    Text("Select an authorized repository").tag("")
                    ForEach(store.workspaces.filter { $0.isActive }) { Text($0.canonicalPath).tag($0.id) }
                }
                Picker("Working copy", selection: $checkoutId) {
                    Text("Source repository (read-only)").tag("")
                    ForEach(store.reusableCheckouts.filter { $0.workspaceId == workspaceId && $0.status == "ready" }) { checkout in
                        Text("Continue \(checkout.branchName ?? String(checkout.id.prefix(8)))").tag(checkout.id)
                    }
                }
                Picker("Local model", selection: $modelId) {
                    Text("Select a model").tag(0)
                    ForEach(store.models) { Text($0.label).tag($0.id) }
                }
                Picker("Project", selection: $projectId) {
                    Text("No project").tag(0)
                    ForEach(store.projects) { Text($0.name).tag($0.id) }
                }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(Theme.onDevice).font(.caption).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Session") {
                    Task { if await store.create(workspaceId: workspaceId, modelId: modelId, projectId: projectId == 0 ? nil : projectId, title: title, checkoutId: checkoutId.isEmpty ? nil : checkoutId) { dismiss() } }
                }.disabled(workspaceId.isEmpty || modelId == 0 || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 255 || store.actionInFlight || store.pending != nil)
            }
        }.padding(24).frame(width: 530).background(Theme.bg)
            .task { await store.loadReusableCheckouts() }
            .onChange(of: workspaceId) { _, _ in checkoutId = "" }
    }
}

struct CodingDeliveryNoticeBanner: View {
    let notice: CodingWorkspaceStore.DeliveryNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST GIT ACTION").font(Theme.mono(9)).foregroundStyle(Theme.textFaint)
                Text(notice.title).font(.system(size: 12, weight: .semibold))
                Text(notice.detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Commit: \(notice.head)")
            Button("Dismiss Git confirmation", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
        }
        .foregroundStyle(Theme.text).padding(12).background(Theme.ok.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

struct CodingDeliveryPanel: View {
    @Bindable var store: CodingWorkspaceStore
    let sessionId: String
    let action: String
    let popOut: (CodingRepositoryDiff) -> Void
    @State private var files: [CodingChangedFile] = []
    @State private var selectedFiles: Set<String> = []
    @State private var message = ""
    @State private var preview: CodingDeliveryPreview?
    @State private var previewTime = Date()
    @State private var loadingFiles = false

    private var diff: CodingRepositoryDiff? {
        guard let preview else { return nil }
        return CodingRepositoryDiff(basis: "approval", observedAt: previewTime, path: action == "commit" ? "Selected commit" : "Apply committed changes",
            sections: [.init(kind: "proposed", text: preview.diff, truncated: false)])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(action == "commit" ? "CREATE LOCAL COMMIT" : "APPLY COMMITS TO SOURCE").font(Theme.mono(10))
                Spacer()
                Button { if let diff { popOut(diff) } } label: { Image(systemName: "macwindow.on.rectangle") }
                    .disabled(diff == nil).help("Open review in a resizable window")
                Button { store.deliveryAction = nil } label: { Image(systemName: "xmark") }.disabled(store.actionInFlight)
            }.padding(10)
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if action == "commit" {
                            TextField("Commit message", text: $message).textFieldStyle(.roundedBorder)
                            Text("Select working files to commit. Existing staged changes are not consumed.").font(.caption).foregroundStyle(Theme.textDim)
                            if loadingFiles { ProgressView() }
                            ForEach(files) { file in
                                Toggle(file.path, isOn: Binding(get: { selectedFiles.contains(file.path) }, set: {
                                    if $0 { selectedFiles.insert(file.path) } else { selectedFiles.remove(file.path) }
                                    preview = nil
                                })).toggleStyle(.checkbox).font(Theme.mono(10))
                            }
                        } else {
                            Text("Apply committed changes only. Uncommitted checkout files stay here. The original folder must be completely clean; divergent history requires an external Git client.")
                                .font(.caption).foregroundStyle(Theme.textDim)
                            if let preview {
                                Text(preview.sourcePath ?? "").font(Theme.mono(10)).textSelection(.enabled)
                                Text(preview.sourceBranch ?? "").font(Theme.mono(10))
                            }
                        }
                        Button("Generate Review") {
                            Task { preview = await store.previewDelivery(sessionId: sessionId, action: action, files: selectedFiles.sorted(), message: message); previewTime = Date() }
                        }.disabled(!store.canManageWorkspace || (action == "commit" && (selectedFiles.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                        if let preview {
                            Text("\(action == "commit" ? "Base" : "Apply through") \(preview.head.prefix(12))").font(Theme.mono(10))
                            Button(action == "commit" ? "Confirm Local Commit" : "Confirm Apply to Source") {
                                Task {
                                    if await store.confirmDelivery(sessionId: sessionId, preview: preview, files: selectedFiles.sorted(), message: message) {
                                        store.deliveryAction = nil
                                    }
                                }
                            }.disabled(!store.canManageWorkspace)
                        }
                        if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(Theme.onDevice).textSelection(.enabled) }
                    }.padding(12)
                }.frame(width: 230)
                Divider()
                if let diff { CodingDiffPreview(diff: diff) }
                else {
                    Text("Generate a review, inspect the exact diff, then confirm. No remote push or automatic merge.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.background(Theme.bg).foregroundStyle(Theme.text)
            .task { loadingFiles = true; files = await store.deliveryFiles(sessionId: sessionId); loadingFiles = false }
            .onChange(of: message) { _, _ in preview = nil }
    }
}

private struct CodingGrantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CodingWorkspaceStore
    let userId: Int
    let mode: CodingRepositorySetupMode
    @State private var path = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title).font(.title2)
            Text(mode == .create
                 ? "Choose a name and location for a new local Git repository. After you confirm, Fruitcake creates a new folder, adds an empty initial commit, and authorizes it. Existing folders are never overwritten. Nothing is published online."
                 : "Choose the top-level folder of an existing Git repository with an initial commit. Fruitcake validates it before authorizing read access; no files are changed.")
                .foregroundStyle(Theme.textDim)
            Text("The folder chooser browses this Mac. Your backend must run on this Mac too.")
                .font(.caption).foregroundStyle(Theme.textDim)
            HStack(alignment: .top) {
                Text(path.isEmpty ? "No location selected" : path)
                    .font(Theme.mono(11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button(mode == .create ? "Choose Name & Location…" : "Browse…") { chooseLocation() }
                    .disabled(store.actionInFlight)
            }
            Text("Next, create a coding session. Sessions start read-only; isolated checkouts, approved edits, and commands remain separate opt-ins.")
                .font(.caption).foregroundStyle(Theme.textDim)
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(Theme.onDevice).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.disabled(store.actionInFlight)
                Spacer()
                Button(mode == .create ? "Create & Authorize" : "Authorize Read Access") {
                    Task { if await store.grant(userId: userId, path: path, createRepository: mode == .create) { dismiss() } }
                }.disabled(path.isEmpty || store.actionInFlight)
            }
        }.padding(24).frame(width: 530).background(Theme.bg)
            .interactiveDismissDisabled(store.actionInFlight)
            .onAppear { store.errorMessage = nil }
    }

    private func chooseLocation() {
        let panel = mode.makePanel()
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            path = url.path
            store.errorMessage = nil
        }
    }
}
#endif
