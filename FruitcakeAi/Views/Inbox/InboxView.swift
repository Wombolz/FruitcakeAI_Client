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

    // MARK: - Derived

    private var pendingApprovals: [TaskSummary] {
        tasks.filter { $0.isPendingApproval }
    }

    private var recentTasks: [TaskSummary] {
        tasks
            .filter { !$0.isPendingApproval }
            .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
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
            }
            .refreshable { await loadTasks() }
            .task { await loadTasks() }
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
            tasks.removeAll { $0.id == task.id }
            onCountChanged(pendingApprovals.count)
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
}

// MARK: - Preview

#Preview {
    InboxView()
        .environment(AuthManager())
}
