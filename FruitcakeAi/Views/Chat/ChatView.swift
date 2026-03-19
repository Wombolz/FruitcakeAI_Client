//
//  ChatView.swift
//  FruitcakeAi
//
//  Main chat interface. NavigationSplitView with:
//  - Sidebar: conversation list (from backend GET /chat/sessions, cached in SwiftData)
//  - Detail: message thread + WebSocket streaming input
//
//  Persona switching: send "/persona <name>" as a message; the backend
//  returns {"type": "persona", "persona": "name"} and the session label updates.
//

import SwiftUI
import SwiftData

// MARK: - API response types

private struct SessionSummary: Codable, Identifiable {
    let id: Int
    let title: String?
    let persona: String
    let llmModel: String?

    var displayTitle: String { title ?? "Conversation \(id)" }
}

private struct CreateSessionResponse: Codable {
    let id: Int
    let title: String?
    let persona: String
}

private struct SessionHistoryResponse: Codable {
    let id: Int
    let title: String?
    let persona: String
    let messages: [HistoryMessage]
}

private struct HistoryMessage: Codable {
    let id: Int
    let role: String
    let content: String
    let createdAt: Date
}

private struct ChatToolsResponse: Decodable {
    let persona: String
    let tools: [String]
    let blockedTools: [String]
}

private struct ChatPersonaInfo: Decodable {
    let description: String?
    let tone: String?
    let blockedTools: [String]?
    let contentFilter: String?
}

private struct SessionToolOverrides {
    var allowedTools: [String] = []
    var blockedTools: [String] = []
}

// MARK: - ChatView

struct ChatView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(OnDeviceAgent.self) private var onDeviceAgent
    @Environment(\.modelContext) private var modelContext

    /// Set from InboxView's "Reply in Chat" to auto-navigate to a session.
    @Binding var openSessionId: Int?

    @Query(sort: \CachedConversation.lastActivity, order: .reverse)
    private var localConversations: [CachedConversation]

    // MARK: State

    @State private var sessions: [SessionSummary] = []
    @State private var selectedSession: SessionSummary?
    @State private var selectedConversation: CachedConversation?

    @State private var messages: [CachedMessage] = []
    @State private var streamingContent: String = ""
    @State private var showToolIndicator: Bool = false

    @State private var inputText: String = ""
    @State private var loadingError: String?
    @State private var deleteError: String?
    @State private var renameError: String?
    @State private var isSending: Bool = false
    @State private var renameTarget: SessionSummary?
    @State private var renameInput: String = ""
    @State private var showProfileSheet: Bool = false
    @State private var availablePersonas: [String] = []
    @State private var availableTools: [String] = []
    @State private var sessionToolOverrides: [Int: SessionToolOverrides] = [:]
    @State private var profilePersona: String = "family_assistant"
    @State private var profileAllowedCSV: String = ""
    @State private var profileBlockedCSV: String = ""
    @State private var profileError: String?

    @State private var wsManager = WebSocketManager()

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("FruitcakeAI")
                .toolbar { sidebarToolbar }
        } detail: {
            if let session = selectedSession {
                detailView(session: session)
            } else {
                ContentUnavailableView(
                    "Select a conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a conversation from the sidebar or start a new one.")
                )
            }
        }
        .task {
            await loadSessions()
            await loadChatCapabilities()
        }
        .onChange(of: connectivity.isBackendReachable) { _, reachable in
            guard reachable else { return }
            Task {
                await loadSessions()
                await loadChatCapabilities()
            }
        }
        .onChange(of: selectedSession?.id) { _, newId in
            guard let newId else { return }
            Task { await switchSession(sessionId: newId) }
        }
        .onChange(of: openSessionId) { _, id in
            guard let id else { return }
            openSessionId = nil
            // Reload sessions then select the new one
            Task {
                await loadSessions()
                if let match = sessions.first(where: { $0.id == id }) {
                    selectedSession = match
                }
            }
        }
        .overlay(alignment: .top) {
            if let deleteError {
                Text(deleteError)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $renameTarget) { session in
            NavigationStack {
                Form {
                    Section("Title") {
                        TextField("Conversation title", text: $renameInput)
                    }
                    if let renameError {
                        Section {
                            Text(renameError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("Rename Conversation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            renameError = nil
                            renameTarget = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await renameSession(session) }
                        }
                        .disabled(renameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            NavigationStack {
                Form {
                    Section("Persona") {
                        Picker("Persona", selection: $profilePersona) {
                            ForEach(availablePersonas, id: \.self) { persona in
                                Text(persona.replacingOccurrences(of: "_", with: " ").capitalized).tag(persona)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Section("Allowed Tools (comma separated)") {
                        TextField("search_library, web_search", text: $profileAllowedCSV)
                    }
                    Section("Blocked Tools (comma separated)") {
                        TextField("fetch_page", text: $profileBlockedCSV)
                    }
                    if !availableTools.isEmpty {
                        Section("Available Tools") {
                            Text(availableTools.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let profileError {
                        Section {
                            Text(profileError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("Chat Profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            profileError = nil
                            showProfileSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveProfileSettings() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSession) {
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                    Text(session.persona.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(session)
                .contextMenu {
                    Button("Rename") {
                        renameInput = session.displayTitle
                        renameError = nil
                        renameTarget = session
                    }
                    Button("Delete", role: .destructive) {
                        Task { await deleteSession(session) }
                    }
                }
            }
            .onDelete { offsets in
                Task { await deleteSessions(at: offsets) }
            }
            .onMove { source, destination in
                sessions.move(fromOffsets: source, toOffset: destination)
            }
        }
        .overlay {
            if sessions.isEmpty && connectivity.isBackendReachable {
                ContentUnavailableView(
                    "No conversations",
                    systemImage: "bubble.left",
                    description: Text("Tap + to start a new conversation.")
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await createSession() }
            } label: {
                Label("New Conversation", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                prepareProfileEditor()
                showProfileSheet = true
            } label: {
                Label("Profile", systemImage: "slider.horizontal.3")
            }
            .disabled(selectedSession == nil)
        }
        ToolbarItem(placement: .navigation) {
            Button("Sign out") { authManager.logout() }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailView(session: SessionSummary) -> some View {
        VStack(spacing: 0) {
            ConnectionStatus()

            // Message thread
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg, persona: session.persona)
                                .id(msg.id)
                        }

                        // Streaming in-progress
                        if showToolIndicator && streamingContent.isEmpty {
                            ToolCallIndicator()
                                .id("indicator")
                        }
                        if !streamingContent.isEmpty {
                            streamingBubble
                                .id("streaming")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: streamingContent) { _, _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: showToolIndicator) { _, _ in
                    withAnimation { proxy.scrollTo("indicator", anchor: .bottom) }
                }
            }

            Divider()

            inputBar(sessionId: session.id)
        }
        .navigationTitle(session.displayTitle)
        #if os(macOS)
        .navigationSubtitle(session.persona.replacingOccurrences(of: "_", with: " ").capitalized)
        #endif
    }

    private var streamingBubble: some View {
        HStack(alignment: .bottom) {
            Text(streamingContent)
                .textSelection(.enabled)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.secondary.opacity(0.12))
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18, topTrailingRadius: 18
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Spacer(minLength: 48)
        }
    }

    // MARK: - Input bar

    @ViewBuilder
    private func inputBar(sessionId: Int) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $inputText, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)
                .onSubmit { sendIfReady(sessionId: sessionId) }

            Button {
                sendIfReady(sessionId: sessionId)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    private func sendIfReady(sessionId: Int) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        Task { await sendMessage(text, sessionId: sessionId) }
    }

    // MARK: - Networking

    private func loadSessions() async {
        guard connectivity.isBackendReachable,
              let _ = try? authManager.token(),
              let _ = authManager.serverURL else { return }

        let api = APIClient(authManager: authManager)
        do {
            sessions = try await api.request("/chat/sessions")
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func loadChatCapabilities() async {
        guard connectivity.isBackendReachable else { return }
        let api = APIClient(authManager: authManager)
        do {
            let personas: [String: ChatPersonaInfo] = try await api.request("/chat/personas")
            availablePersonas = personas.keys.sorted()
            let toolsResp: ChatToolsResponse = try await api.request("/chat/tools")
            availableTools = toolsResp.tools.sorted()
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func prepareProfileEditor() {
        guard let selected = selectedSession else { return }
        profilePersona = selected.persona
        let overrides = sessionToolOverrides[selected.id] ?? SessionToolOverrides()
        profileAllowedCSV = overrides.allowedTools.joined(separator: ", ")
        profileBlockedCSV = overrides.blockedTools.joined(separator: ", ")
        profileError = nil
    }

    private func saveProfileSettings() async {
        guard let selected = selectedSession else { return }
        guard connectivity.isBackendReachable else {
            profileError = "Backend is not reachable."
            return
        }

        let parsedAllowed = parseCSV(profileAllowedCSV)
        let parsedBlocked = parseCSV(profileBlockedCSV)
        sessionToolOverrides[selected.id] = SessionToolOverrides(
            allowedTools: parsedAllowed,
            blockedTools: parsedBlocked
        )

        struct PersonaBody: Encodable { let persona: String }
        let api = APIClient(authManager: authManager)
        do {
            let updated: SessionSummary = try await api.request(
                "/chat/sessions/\(selected.id)/persona",
                method: "PATCH",
                body: PersonaBody(persona: profilePersona)
            )
            if let idx = sessions.firstIndex(where: { $0.id == selected.id }) {
                sessions[idx] = updated
            }
            if selectedSession?.id == selected.id {
                selectedSession = updated
            }
            if selectedConversation?.serverSessionId == selected.id {
                selectedConversation?.persona = updated.persona
                try? modelContext.save()
            }
            profileError = nil
            showProfileSheet = false
        } catch {
            profileError = "Could not save chat profile."
        }
    }

    private func parseCSV(_ value: String) -> [String] {
        Array(
            Set(
                value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    private func createSession() async {
        let api = APIClient(authManager: authManager)
        do {
            let created: CreateSessionResponse = try await api.request(
                "/chat/sessions",
                method: "POST",
                body: EmptyBody()
            )
            let summary = SessionSummary(
                id: created.id,
                title: created.title,
                persona: created.persona,
                llmModel: nil
            )
            sessions.insert(summary, at: 0)
            selectedSession = summary

            // Mirror in SwiftData
            let conv = CachedConversation(
                serverSessionId: created.id,
                title: created.title ?? "New conversation",
                persona: created.persona
            )
            modelContext.insert(conv)
            selectedConversation = conv
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func deleteSession(_ session: SessionSummary) async {
        // Attempt server delete first — if it fails, leave the session in the sidebar
        if connectivity.isBackendReachable {
            let api = APIClient(authManager: authManager)
            do {
                try await api.requestVoid("/chat/sessions/\(session.id)", method: "DELETE")
            } catch {
                deleteError = "Could not delete conversation"
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    deleteError = nil
                }
                return
            }
        }

        // Server confirmed deletion (or offline) — now remove locally
        if selectedSession?.id == session.id {
            selectedSession = nil
            selectedConversation = nil
            messages = []
            wsManager.disconnect()
        }

        withAnimation {
            sessions.removeAll { $0.id == session.id }
        }

        if let cached = localConversations.first(where: { $0.serverSessionId == session.id }) {
            modelContext.delete(cached)
            try? modelContext.save()
        }
    }

    private func renameSession(_ session: SessionSummary) async {
        let newTitle = renameInput.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else {
            renameError = "Title cannot be blank."
            return
        }
        guard connectivity.isBackendReachable else {
            renameError = "Backend is not reachable."
            return
        }

        struct RenameBody: Encodable { let title: String }
        let api = APIClient(authManager: authManager)
        do {
            let updated: SessionSummary = try await api.request(
                "/chat/sessions/\(session.id)",
                method: "PATCH",
                body: RenameBody(title: newTitle)
            )

            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx] = updated
            }
            if selectedSession?.id == session.id {
                selectedSession = updated
            }
            if let cached = localConversations.first(where: { $0.serverSessionId == session.id }) {
                cached.title = updated.displayTitle
                try? modelContext.save()
            }
            if selectedConversation?.serverSessionId == session.id {
                selectedConversation?.title = updated.displayTitle
            }

            renameError = nil
            renameTarget = nil
        } catch {
            renameError = "Could not rename conversation."
        }
    }

    private func deleteSessions(at offsets: IndexSet) async {
        // Snapshot the sessions to delete before indices shift
        let toDelete = offsets.map { sessions[$0] }
        for session in toDelete {
            await deleteSession(session)
        }
    }

    private func switchSession(sessionId: Int) async {
        wsManager.disconnect()
        messages = []
        streamingContent = ""
        showToolIndicator = false
        loadingError = nil

        // Find or create SwiftData conversation
        if let existing = localConversations.first(where: { $0.serverSessionId == sessionId }) {
            selectedConversation = existing
            messages = existing.sortedMessages
        } else if let session = sessions.first(where: { $0.id == sessionId }) {
            let conv = CachedConversation(serverSessionId: sessionId, title: session.displayTitle, persona: session.persona)
            modelContext.insert(conv)
            selectedConversation = conv
        }

        // Load history from backend
        let api = APIClient(authManager: authManager)
        do {
            let history: SessionHistoryResponse = try await api.request("/chat/sessions/\(sessionId)")
            messages = history.messages.map {
                CachedMessage(
                    serverMessageId: $0.id,
                    role: $0.role,
                    content: $0.content,
                    timestamp: $0.createdAt
                )
            }
        } catch {
            loadingError = error.localizedDescription
        }

        // Connect WebSocket
        guard let token = try? authManager.token(),
              let serverURL = authManager.serverURL else { return }

        wsManager.connect(serverURL: serverURL, sessionId: sessionId, token: token)
    }

    private func sendMessage(_ text: String, sessionId: Int) async {
        isSending = true
        showToolIndicator = true
        streamingContent = ""
        loadingError = nil
        let overrides = sessionToolOverrides[sessionId] ?? SessionToolOverrides()

        // Optimistic user message
        let userMsg = CachedMessage(role: "user", content: text)
        messages.append(userMsg)
        selectedConversation?.messages.append(userMsg)
        selectedConversation?.lastActivity = .now

        // Offline → on-device FoundationModels fallback
        guard connectivity.isBackendReachable else {
            await sendViaOnDevice(text)
            isSending = false
            showToolIndicator = false
            return
        }

        guard wsManager.isConnected else {
            // Backend reachable but WebSocket not yet connected → REST POST
            await sendViaREST(text, sessionId: sessionId, overrides: overrides)
            isSending = false
            showToolIndicator = false
            return
        }

        let responseStream: AsyncStream<WSEvent>
        do {
            responseStream = try wsManager.sendAndReceive(
                text,
                allowedTools: overrides.allowedTools,
                blockedTools: overrides.blockedTools
            )
        } catch {
            loadingError = error.localizedDescription
            isSending = false
            showToolIndicator = false
            return
        }

        // Consume events for this response. The stream finishes after
        // a terminal event (.done, .error, .personaSwitched).
        var fullResponse = ""
        eventLoop: for await event in responseStream {
            switch event {
            case .token(let chunk):
                showToolIndicator = false
                streamingContent += chunk
                fullResponse += chunk

            case .done(let complete):
                let finalResponse = complete.isEmpty ? fullResponse : complete
                fullResponse = finalResponse
                streamingContent = ""
                showToolIndicator = false

                let assistantMsg = CachedMessage(role: "assistant", content: finalResponse)
                messages.append(assistantMsg)
                selectedConversation?.messages.append(assistantMsg)
                selectedConversation?.lastActivity = .now

                isSending = false
                break eventLoop

            case .personaSwitched(let name, let message):
                // Update session label in sidebar
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    let old = sessions[idx]
                    sessions[idx] = SessionSummary(id: old.id, title: old.title, persona: name, llmModel: old.llmModel)
                    if selectedSession?.id == sessionId {
                        selectedSession = sessions[idx]
                    }
                }
                selectedConversation?.persona = name

                let sysMsg = CachedMessage(role: "assistant", content: message)
                messages.append(sysMsg)
                streamingContent = ""
                showToolIndicator = false
                isSending = false
                break eventLoop

            case .error(let msg):
                loadingError = msg
                streamingContent = ""
                showToolIndicator = false
                isSending = false
                break eventLoop
            }
        }
    }

    private func sendViaOnDevice(_ text: String) async {
        var fullResponse = ""

        for await chunk in onDeviceAgent.stream(text) {
            showToolIndicator = false
            streamingContent += chunk
            fullResponse += chunk
        }

        streamingContent = ""
        showToolIndicator = false

        let assistantMsg = CachedMessage(role: "assistant", content: fullResponse, isLocal: true)
        messages.append(assistantMsg)
        selectedConversation?.messages.append(assistantMsg)
        selectedConversation?.lastActivity = .now
    }

    private func sendViaREST(_ text: String, sessionId: Int, overrides: SessionToolOverrides) async {
        struct SendBody: Encodable {
            let content: String
            let allowedTools: [String]?
            let blockedTools: [String]?
        }
        struct SendResponse: Decodable { let role: String; let content: String }
        let api = APIClient(authManager: authManager)
        do {
            let resp: SendResponse = try await api.request(
                "/chat/sessions/\(sessionId)/messages",
                method: "POST",
                body: SendBody(
                    content: text,
                    allowedTools: overrides.allowedTools.isEmpty ? nil : overrides.allowedTools,
                    blockedTools: overrides.blockedTools.isEmpty ? nil : overrides.blockedTools
                ),
                timeout: 120
            )
            let msg = CachedMessage(role: resp.role, content: resp.content)
            messages.append(msg)
            selectedConversation?.messages.append(msg)
            selectedConversation?.lastActivity = .now
        } catch {
            loadingError = error.localizedDescription
        }
    }
}

// MARK: - Helpers

private struct EmptyBody: Encodable {}

// Hashable + Equatable for NavigationSplitView selection
extension SessionSummary: Hashable, Equatable {
    static func == (lhs: SessionSummary, rhs: SessionSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    ChatView(openSessionId: .constant(nil))
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
        .environment(OnDeviceAgent())
        .modelContainer(for: [CachedConversation.self, CachedMessage.self], inMemory: true)
}
