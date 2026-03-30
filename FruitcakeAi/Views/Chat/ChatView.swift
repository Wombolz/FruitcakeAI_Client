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
    let sortOrder: Int?

    var displayTitle: String { title ?? "Conversation \(id)" }
}

private struct CreateSessionResponse: Codable {
    let id: Int
    let title: String?
    let persona: String
    let llmModel: String?
    let sortOrder: Int?
}

private struct SessionHistoryResponse: Codable {
    let id: Int
    let title: String?
    let persona: String
    let llmModel: String?
    let messages: [HistoryMessage]
}

private struct ChatSessionStatusResponse: Codable {
    let sessionId: Int
    let active: Bool
}

private struct ReorderSessionsBody: Encodable {
    let sessionIds: [Int]
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
    let displayName: String?
    let description: String?
    let tone: String?
    let blockedTools: [String]?
    let contentFilter: String?
}

private struct ChatModelOption: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String
    let label: String
    let isDefaultChat: Bool
    let isDefaultTaskSmall: Bool
    let isDefaultTaskLarge: Bool

    var displayLabel: String {
        if isDefaultChat {
            return "\(label) (Default)"
        }
        return label
    }

    var providerLabel: String {
        provider.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct ChatModelListResponse: Decodable {
    let models: [ChatModelOption]
}

private enum ChatReasoningOption: String, CaseIterable, Identifiable {
    case auto
    case fast
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .fast: return "Fast"
        case .deep: return "Deep"
        }
    }
}

private struct SessionToolOverrides {
    var allowedTools: [String] = []
    var blockedTools: [String] = []
}

private struct RecentSendRecord {
    let fingerprint: String
    let sentAt: Date
}

private let recentSendGuardWindowSeconds: TimeInterval = 300

// MARK: - ChatView

struct ChatView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(OnDeviceAgent.self) private var onDeviceAgent
    @Environment(\.modelContext) private var modelContext

    /// Set from InboxView's "Reply in Chat" to auto-navigate to a session.
    @Binding var openSessionId: Int?

    @Query
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
    @State private var sendClaimed: Bool = false
    @State private var activeClientSendID: String?
    @State private var activeSendTask: Task<Void, Never>?
    @State private var sessionStatusTask: Task<Void, Never>?
    @State private var sendTraceSequence: Int = 0
    @State private var recentSendBySession: [Int: RecentSendRecord] = [:]
    @State private var renameTarget: SessionSummary?
    @State private var renameInput: String = ""
    @State private var showProfileSheet: Bool = false
    @State private var availablePersonas: [String] = []
    @State private var availablePersonaInfo: [String: ChatPersonaInfo] = [:]
    @State private var availableTools: [String] = []
    @State private var availableModels: [ChatModelOption] = []
    @State private var sessionToolOverrides: [Int: SessionToolOverrides] = [:]
    @State private var profilePersona: String = "family_assistant"
    @State private var profileAllowedCSV: String = ""
    @State private var profileBlockedCSV: String = ""
    @State private var profileError: String?

    @State private var wsManager = WebSocketManager()

    private func personaDisplayName(_ key: String) -> String {
        if let info = availablePersonaInfo[key], let displayName = info.displayName, !displayName.isEmpty {
            return displayName
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func sessionIndex(for session: SessionSummary) -> Int? {
        sessions.firstIndex(where: { $0.id == session.id })
    }

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
            trace("selected_session_changed new_id=\(newId.map(String.init) ?? "nil") ws_state=\(wsManager.stateLabel)")
            guard let newId else { return }
            Task { await switchSession(sessionId: newId) }
        }
        .onChange(of: isSending) { _, newValue in
            trace("is_sending_changed value=\(newValue)")
        }
        .onChange(of: sendClaimed) { _, newValue in
            trace("send_claimed_changed value=\(newValue)")
        }
        .onChange(of: activeClientSendID) { _, newValue in
            trace("active_client_send_id_changed value=\(newValue ?? "nil")")
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
                                Text(personaDisplayName(persona)).tag(persona)
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
                sessionRow(session)
            }
            .onDelete { offsets in
                Task { await deleteSessions(sessions, at: offsets) }
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

    @ViewBuilder
    private func sessionRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(personaDisplayName(session.persona))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let index = sessionIndex(for: session) {
                HStack(spacing: 2) {
                    Button {
                        moveSession(session, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        moveSession(session, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == sessions.count - 1)
                }
                .foregroundStyle(.secondary)
            }
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
                            MessageBubble(message: msg, persona: personaDisplayName(session.persona))
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
        .navigationSubtitle(personaDisplayName(session.persona))
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
        VStack(alignment: .leading, spacing: 8) {
            TextField("Message…", text: $inputText, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)
                .onSubmit { sendIfReady(sessionId: sessionId) }

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    modelMenu(sessionId: sessionId)
                    reasoningMenu()
                }

                Spacer(minLength: 0)

                Button {
                    sendIfReady(sessionId: sessionId)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func modelMenu(sessionId: Int) -> some View {
        Menu {
            ForEach(availableModels) { model in
                Button {
                    Task { await updateSessionModel(sessionId: sessionId, modelID: model.id) }
                } label: {
                    if currentSessionModelID == model.id {
                        Label("\(model.displayLabel) · \(model.providerLabel)", systemImage: "checkmark")
                    } else {
                        Text("\(model.displayLabel) · \(model.providerLabel)")
                    }
                }
            }
        } label: {
            composerMenuLabel(title: "Model", value: currentSessionModelLabel)
        }
        .disabled(isSending || availableModels.isEmpty)
    }

    @ViewBuilder
    private func reasoningMenu() -> some View {
        Menu {
            ForEach(ChatReasoningOption.allCases) { option in
                Button {
                    Task { await updateReasoningPreference(option.rawValue) }
                } label: {
                    if currentReasoningPreference == option.rawValue {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            composerMenuLabel(title: "Reasoning", value: currentReasoningLabel)
        }
        .disabled(isSending)
    }

    private func composerMenuLabel(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    private var currentSessionModelID: String {
        selectedSession?.llmModel
        ?? availableModels.first(where: { $0.isDefaultChat })?.id
        ?? availableModels.first?.id
        ?? ""
    }

    private var currentSessionModelLabel: String {
        availableModels.first(where: { $0.id == currentSessionModelID })?.displayLabel
        ?? (currentSessionModelID.isEmpty ? "Model" : currentSessionModelID)
    }

    private var currentReasoningPreference: String {
        authManager.currentUser?.chatRoutingPreference ?? "auto"
    }

    private var currentReasoningLabel: String {
        ChatReasoningOption(rawValue: currentReasoningPreference)?.title ?? "Automatic"
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isSending && !sendClaimed
    }

    private func trace(_ message: String) {
        print("[ChatTrace] \(message)")
    }

    private func normalizedPromptFingerprint(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func sendIfReady(sessionId: Int) {
        guard canSend else { return }
        sendTraceSequence += 1
        let sendSeq = sendTraceSequence
        let text = inputText.trimmingCharacters(in: .whitespaces)
        let fingerprint = normalizedPromptFingerprint(text)
        trace("send_if_ready_enter seq=\(sendSeq) session=\(sessionId) chars=\(text.count) fingerprint=\(fingerprint.prefix(24)) isSending=\(isSending) sendClaimed=\(sendClaimed) ws_state=\(wsManager.stateLabel)")
        if let recent = recentSendBySession[sessionId],
           recent.fingerprint == fingerprint,
           Date().timeIntervalSince(recent.sentAt) < recentSendGuardWindowSeconds {
            trace("send_blocked_duplicate seq=\(sendSeq) session=\(sessionId) chars=\(text.count) seconds_since_last=\(Int(Date().timeIntervalSince(recent.sentAt)))")
            loadingError = "Message already sent. Wait before resending."
            Task {
                try? await Task.sleep(for: .seconds(3))
                if loadingError == "Message already sent. Wait before resending." {
                    loadingError = nil
                }
            }
            return
        }
        sendClaimed = true
        recentSendBySession[sessionId] = RecentSendRecord(fingerprint: fingerprint, sentAt: Date())
        let clientSendID = UUID().uuidString
        trace("send_if_ready_claimed seq=\(sendSeq) session=\(sessionId) client_send_id=\(clientSendID) chars=\(text.count) ws_state=\(wsManager.stateLabel)")
        inputText = ""
        activeClientSendID = clientSendID
        activeSendTask = Task {
            await sendMessage(text, sessionId: sessionId, clientSendID: clientSendID, sendSequence: sendSeq)
        }
        trace("active_send_task_assigned seq=\(sendSeq) session=\(sessionId) client_send_id=\(clientSendID)")
    }

    // MARK: - Networking

    @MainActor
    private func loadSessions() async {
        guard connectivity.isBackendReachable,
              let _ = try? authManager.token(),
              let _ = authManager.serverURL else { return }

        let api = APIClient(authManager: authManager)
        do {
            let loaded: [SessionSummary] = try await api.request("/chat/sessions")
            applySessionList(loaded)
        } catch {
            loadingError = error.localizedDescription
        }
    }

    @MainActor
    private func loadChatCapabilities() async {
        guard connectivity.isBackendReachable else { return }
        let api = APIClient(authManager: authManager)
        do {
            let personas: [String: ChatPersonaInfo] = try await api.request("/chat/personas")
            availablePersonaInfo = personas
            availablePersonas = personas.keys.sorted()
            let toolsResp: ChatToolsResponse = try await api.request("/chat/tools")
            availableTools = toolsResp.tools.sorted()
            let modelsResp: ChatModelListResponse = try await api.request("/llm/models")
            availableModels = modelsResp.models
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func applySessionList(_ newSessions: [SessionSummary]) {
        sessions = newSessions
        if let selectedId = selectedSession?.id,
           let updated = newSessions.first(where: { $0.id == selectedId }) {
            selectedSession = updated
        }
    }

    private func moveSession(_ session: SessionSummary, by offset: Int) {
        guard let currentIndex = sessionIndex(for: session) else { return }
        let targetIndex = currentIndex + offset
        guard targetIndex >= 0, targetIndex < sessions.count else { return }

        var reordered = sessions
        let moved = reordered.remove(at: currentIndex)
        reordered.insert(moved, at: targetIndex)
        applySessionList(reordered)
        Task { await saveSessionOrder(reordered) }
    }

    private func deleteSessions(_ sourceSessions: [SessionSummary], at offsets: IndexSet) async {
        let toDelete = offsets.map { sourceSessions[$0] }
        for session in toDelete {
            await deleteSession(session)
        }
    }

    @MainActor
    private func saveSessionOrder(_ reorderedSessions: [SessionSummary]) async {
        guard connectivity.isBackendReachable else {
            loadingError = "Backend is not reachable."
            return
        }

        let api = APIClient(authManager: authManager)
        do {
            let updated: [SessionSummary] = try await api.request(
                "/chat/sessions/order",
                method: "PATCH",
                body: ReorderSessionsBody(sessionIds: reorderedSessions.map(\.id))
            )
            applySessionList(updated)
        } catch {
            loadingError = "Could not save conversation order."
            await loadSessions()
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

    @MainActor
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
            if let idx = sessions.firstIndex(where: { $0.id == selected.id }) { sessions[idx] = updated }
            if selectedSession?.id == selected.id { selectedSession = updated }
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

    @MainActor
    private func updateSessionModel(sessionId: Int, modelID: String) async {
        guard connectivity.isBackendReachable else {
            loadingError = "Backend is not reachable."
            return
        }

        struct ModelBody: Encodable { let llmModel: String }
        let api = APIClient(authManager: authManager)
        do {
            let updated: SessionSummary = try await api.request(
                "/chat/sessions/\(sessionId)/model",
                method: "PATCH",
                body: ModelBody(llmModel: modelID)
            )
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[idx] = updated }
            if selectedSession?.id == sessionId { selectedSession = updated }
        } catch {
            loadingError = "Could not save model selection."
        }
    }

    @MainActor
    private func updateReasoningPreference(_ preference: String) async {
        guard connectivity.isBackendReachable else {
            loadingError = "Backend is not reachable."
            return
        }

        let api = APIClient(authManager: authManager)
        do {
            try await api.updateChatRoutingPreference(preference)
            try await authManager.refreshCurrentUser()
        } catch {
            loadingError = "Could not save reasoning preference."
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

    @MainActor
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
                llmModel: created.llmModel,
                sortOrder: created.sortOrder
            )
            applySessionList([summary] + sessions.filter { $0.id != summary.id })
            selectedSession = sessions.first(where: { $0.id == summary.id }) ?? summary

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

    @MainActor
    private func deleteSession(_ session: SessionSummary) async {
        // Attempt server delete first — if it fails, leave the session in the sidebar
        if connectivity.isBackendReachable {
            let api = APIClient(authManager: authManager)
            do {
                try await api.requestVoid("/chat/sessions/\(session.id)", method: "DELETE")
            } catch {
                let errorText = "Could not delete conversation"
                deleteError = errorText
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if deleteError == errorText {
                        deleteError = nil
                    }
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

    @MainActor
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

            if let idx = sessions.firstIndex(where: { $0.id == session.id }) { sessions[idx] = updated }
            if selectedSession?.id == session.id { selectedSession = updated }
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

    @MainActor
    private func switchSession(sessionId: Int) async {
        trace("switch_session_start session=\(sessionId) active_send=\(activeSendTask != nil) isSending=\(isSending) ws_state=\(wsManager.stateLabel)")
        sessionStatusTask?.cancel()
        sessionStatusTask = nil
        wsManager.disconnect()
        messages = []
        streamingContent = ""
        showToolIndicator = false
        isSending = false
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

        do {
            let history = try await loadSessionHistory(sessionId: sessionId)
            let status = try await loadSessionStatus(sessionId: sessionId)
            let hasDetachedRun = status.active && activeSendTask == nil
            isSending = hasDetachedRun
            showToolIndicator = hasDetachedRun && history.messages.last?.role != "assistant"
            if hasDetachedRun {
                startDetachedRunPolling(sessionId: sessionId)
            }
        } catch {
            loadingError = error.localizedDescription
        }

        // Connect WebSocket
        guard let token = try? authManager.token(),
              let serverURL = authManager.serverURL else { return }

        wsManager.connect(serverURL: serverURL, sessionId: sessionId, token: token)
        trace("switch_session_end session=\(sessionId) active_send=\(activeSendTask != nil) isSending=\(isSending) ws_state=\(wsManager.stateLabel)")
    }

    @MainActor
    private func loadSessionHistory(sessionId: Int) async throws -> SessionHistoryResponse {
        let api = APIClient(authManager: authManager)
        let history: SessionHistoryResponse = try await api.request("/chat/sessions/\(sessionId)")
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            let existing = sessions[idx]
            let updated = SessionSummary(
                id: existing.id,
                title: history.title ?? existing.title,
                persona: history.persona,
                llmModel: history.llmModel,
                sortOrder: existing.sortOrder
            )
            sessions[idx] = updated
            if selectedSession?.id == sessionId {
                selectedSession = updated
            }
        }
        let mappedMessages = history.messages.map {
            CachedMessage(
                serverMessageId: $0.id,
                role: $0.role,
                content: $0.content,
                timestamp: $0.createdAt
            )
        }
        if selectedSession?.id == sessionId {
            messages = mappedMessages
        }
        if selectedConversation?.serverSessionId == sessionId {
            selectedConversation?.messages = mappedMessages
            selectedConversation?.lastActivity = mappedMessages.last?.timestamp ?? selectedConversation?.lastActivity ?? .now
            try? modelContext.save()
        }
        return history
    }

    @MainActor
    private func loadSessionStatus(sessionId: Int) async throws -> ChatSessionStatusResponse {
        let api = APIClient(authManager: authManager)
        return try await api.request("/chat/sessions/\(sessionId)/status")
    }

    @MainActor
    private func startDetachedRunPolling(sessionId: Int) {
        sessionStatusTask?.cancel()
        sessionStatusTask = Task {
            while !Task.isCancelled, selectedSession?.id == sessionId {
                do {
                    let status = try await loadSessionStatus(sessionId: sessionId)
                    _ = try await loadSessionHistory(sessionId: sessionId)
                    if !status.active {
                        isSending = false
                        showToolIndicator = false
                        sessionStatusTask = nil
                        break
                    }
                    isSending = true
                    if messages.last?.role != "assistant" {
                        showToolIndicator = true
                    }
                } catch {
                    loadingError = error.localizedDescription
                    isSending = false
                    showToolIndicator = false
                    sessionStatusTask = nil
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor
    private func sendMessage(_ text: String, sessionId: Int, clientSendID: String, sendSequence: Int) async {
        defer {
            trace("send_message_exit seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) isSending=\(isSending) sendClaimed=\(sendClaimed) ws_state=\(wsManager.stateLabel)")
            isSending = false
            sendClaimed = false
            showToolIndicator = false
            activeClientSendID = nil
            activeSendTask = nil
            streamingContent = ""
        }
        isSending = true
        showToolIndicator = true
        streamingContent = ""
        loadingError = nil
        trace("send_message_enter seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) ws_state=\(wsManager.stateLabel)")
        let overrides = sessionToolOverrides[sessionId] ?? SessionToolOverrides()

        // Optimistic user message
        let userMsg = CachedMessage(role: "user", content: text)
        messages.append(userMsg)
        selectedConversation?.messages.append(userMsg)
        selectedConversation?.lastActivity = .now

        // Offline → on-device FoundationModels fallback
        guard connectivity.isBackendReachable else {
            trace("send_path seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) path=on_device reason=backend_unreachable")
            await sendViaOnDevice(text)
            return
        }

        guard let token = try? authManager.token(),
              let serverURL = authManager.serverURL else {
            trace("send_path seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) path=rest reason=missing_auth_or_server_url connection_id=\(wsManager.connectionID)")
            await sendViaREST(text, sessionId: sessionId, clientSendID: clientSendID, overrides: overrides)
            return
        }

        let websocketReady = await wsManager.ensureConnected(
            serverURL: serverURL,
            sessionId: sessionId,
            token: token,
            timeoutSeconds: 1.0
        )
        guard websocketReady else {
            trace("send_path seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) path=rest reason=ws_not_ready connection_id=\(wsManager.connectionID)")
            await sendViaREST(text, sessionId: sessionId, clientSendID: clientSendID, overrides: overrides)
            return
        }

        trace("send_path seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) path=websocket connection_id=\(wsManager.connectionID)")

        // Capture connection identity before suspending. Events arriving for a
        // stale connection (e.g. after switchSession disconnects mid-send) are
        // discarded rather than written to the new session's messages.
        let expectedConnectionID = wsManager.connectionID
        let responseStream = await wsManager.sendAndReceive(
            text,
            clientSendID: clientSendID,
            allowedTools: overrides.allowedTools,
            blockedTools: overrides.blockedTools
        )

        // Consume events for this response. The stream finishes after
        // a terminal event (.done, .error, .personaSwitched).
        var fullResponse = ""
        eventLoop: for await event in responseStream {
            guard !Task.isCancelled else { break eventLoop }
            guard wsManager.connectionID == expectedConnectionID else {
                trace("ws_stale_event_discarded seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) connection_id=\(wsManager.connectionID) expected=\(expectedConnectionID)")
                break eventLoop
            }
            switch event {
            case .token(let chunk):
                trace("send_message_event seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) type=token chars=\(chunk.count)")
                showToolIndicator = false
                streamingContent += chunk
                fullResponse += chunk

            case .done(let complete):
                trace("send_message_event seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) type=done chars=\(complete.count)")
                let finalResponse = complete.isEmpty ? fullResponse : complete
                fullResponse = finalResponse
                streamingContent = ""
                showToolIndicator = false

                let assistantMsg = CachedMessage(role: "assistant", content: finalResponse)
                messages.append(assistantMsg)
                selectedConversation?.messages.append(assistantMsg)
                selectedConversation?.lastActivity = .now

                break eventLoop

            case .personaSwitched(let name, let message):
                trace("send_message_event seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) type=persona persona=\(name)")
                // Update session label in sidebar
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    let old = sessions[idx]
                    sessions[idx] = SessionSummary(
                        id: old.id,
                        title: old.title,
                        persona: name,
                        llmModel: old.llmModel,
                        sortOrder: old.sortOrder
                    )
                    if selectedSession?.id == sessionId {
                        selectedSession = sessions[idx]
                    }
                }
                selectedConversation?.persona = name

                let sysMsg = CachedMessage(role: "assistant", content: message)
                messages.append(sysMsg)
                break eventLoop

            case .error(let msg):
                trace("send_message_event seq=\(sendSequence) session=\(sessionId) client_send_id=\(clientSendID) type=error message=\(msg)")
                loadingError = msg
                break eventLoop
            }
        }
    }

    @MainActor
    private func sendViaOnDevice(_ text: String) async {
        var fullResponse = ""

        for await chunk in onDeviceAgent.stream(text) {
            guard !Task.isCancelled else { break }
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

    @MainActor
    private func sendViaREST(_ text: String, sessionId: Int, clientSendID: String, overrides: SessionToolOverrides) async {
        struct SendBody: Encodable {
            let content: String
            let clientSendId: String
            let allowedTools: [String]?
            let blockedTools: [String]?
        }
        struct SendResponse: Decodable { let role: String; let content: String }
        let api = APIClient(authManager: authManager)
        trace("rest_send_start session=\(sessionId) client_send_id=\(clientSendID) chars=\(text.count)")
        do {
            let resp: SendResponse = try await api.request(
                "/chat/sessions/\(sessionId)/messages",
                method: "POST",
                body: SendBody(
                    content: text,
                    clientSendId: clientSendID,
                    allowedTools: overrides.allowedTools.isEmpty ? nil : overrides.allowedTools,
                    blockedTools: overrides.blockedTools.isEmpty ? nil : overrides.blockedTools
                ),
                timeout: 120
            )
            trace("rest_send_done session=\(sessionId) client_send_id=\(clientSendID) response_chars=\(resp.content.count)")
            let msg = CachedMessage(role: resp.role, content: resp.content)
            messages.append(msg)
            selectedConversation?.messages.append(msg)
            selectedConversation?.lastActivity = .now
        } catch {
            trace("rest_send_error session=\(sessionId) client_send_id=\(clientSendID) error=\(error.localizedDescription)")
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
