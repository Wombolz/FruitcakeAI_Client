//
//  InboxView.swift
//  FruitcakeAi
//
//  Task list: two sections (Needs Approval, Recent), pull-to-refresh,
//  approval/rejection flow, and task creation sheet.
//

import SwiftUI

struct InboxView: View {

    @Environment(AuthManager.self) private var authManager

    /// Called after every load so the tab bar badge stays in sync.
    var onCountChanged: (Int) -> Void = { _ in }
    /// Called when the user taps "Reply in Chat". Receives the new chat session ID.
    var onReplyInChat: ((Int) -> Void)? = nil

    @State private var tasks: [TaskSummary] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var loadError: String?
    @State private var isVisible = false

    // MARK: - Derived

    private var pendingApprovals: [TaskSummary] {
        tasks
            .filter { $0.isPendingApproval }
            .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
    }

    private var recentTasks: [TaskSummary] {
        tasks
            .filter { !$0.isPendingApproval }
            .sorted {
                let lhsRank = statusRank($0.status)
                let rhsRank = statusRank($1.status)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast)
            }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tasks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                TaskCreateSheet {
                    Task { await loadTasks() }
                }
                .environment(authManager)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
            .refreshable { await loadTasks() }
            .task { await loadTasks() }
            .task(id: isVisible) {
                guard isVisible else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { break }
                    await loadTasks()
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .overlay {
                if let error = loadError {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        List {
            if !pendingApprovals.isEmpty {
                Section {
                    ForEach(pendingApprovals) { task in
                        TaskRow(
                            task: task,
                            onApprove: { Task { await approve(task, approved: true) } },
                            onReject:  { Task { await approve(task, approved: false) } },
                            onStop:    { Task { await stop(task) } },
                            onRun:     { Task { await run(task) } },
                            onReset:   { Task { await reset(task) } },
                            onDelete:  { Task { await delete(task) } }
                        )
                    }
                } header: {
                    Label("Needs Approval", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Recent") {
                ForEach(recentTasks) { task in
                    TaskRow(
                        task: task,
                        onStop:        { Task { await stop(task) } },
                        onRun:         { Task { await run(task) } },
                        onReset:       { Task { await reset(task) } },
                        onDelete:      { Task { await delete(task) } },
                        onReplyInChat: { Task { await replyInChat(task) } }
                    )
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No tasks yet")
                .font(.title2.weight(.semibold))

            Text("Create a task and FruitcakeAI will run it on schedule and deliver results here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showCreate = true
            } label: {
                Label("Create Task", systemImage: "plus")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Data loading

    private func loadTasks() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let api = APIClient(authManager: authManager)
            tasks = try await api.fetchTasks()
            onCountChanged(pendingApprovals.count)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func approve(_ task: TaskSummary, approved: Bool) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.approveTask(task.id, approved: approved)
            await loadTasks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ task: TaskSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.deleteTask(task.id)
            await loadTasks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func stop(_ task: TaskSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.stopTask(task.id)
            await loadTasks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func run(_ task: TaskSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.runTask(task.id)
            await loadTasks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reset(_ task: TaskSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.resetTask(task.id)
            await loadTasks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func replyInChat(_ task: TaskSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            let sessionId = try await api.createChatSession(title: "[Task] \(task.title)")
            if let result = task.result {
                try await api.sendMessage(
                    sessionId: sessionId,
                    content: "Regarding task '\(task.title)':\n\n\(result)"
                )
            }
            onReplyInChat?(sessionId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func statusRank(_ status: String) -> Int {
        switch status {
        case "running", "pending":
            return 0
        case "completed", "failed", "cancelled":
            return 1
        default:
            return 2
        }
    }
}

// MARK: - Preview

#Preview {
    InboxView()
        .environment(AuthManager())
}
