//
//  MemoriesView.swift
//  FruitcakeAi
//
//  Shared memory surface for saved memories, review proposals,
//  and graph-memory navigation.
//

import SwiftUI
import UniformTypeIdentifiers

struct MemoriesView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var memories: [MemorySummary] = []
    @State private var proposals: [MemoryReviewProposal] = []
    @State private var selectedSurface: MemorySurface = .saved
    @State private var reviewFilter: ReviewStatusFilter = .pending
    @State private var filterType: String? = nil
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var showDeleteAllConfirmation = false
    @State private var isRunningAction = false
    @State private var exportDocument = MemoryExportDocument(data: Data())
    @State private var exportFilename = "fruitcakeai-memories"
    @State private var isExportingFile = false
    @State private var activeProposalID: Int?

    private var pendingProposalCount: Int {
        proposals.filter { $0.status == "pending" }.count
    }

    private var displayedMemories: [MemorySummary] {
        memories.filter { memory in
            let matchesType = filterType == nil || memory.memoryType == filterType
            let matchesSearch = searchText.isEmpty ||
                memory.content.localizedCaseInsensitiveContains(searchText) ||
                memory.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            return matchesType && matchesSearch
        }
    }

    private var procedural: [MemorySummary] { displayedMemories.filter { $0.memoryType == "procedural" } }
    private var semantic:   [MemorySummary] { displayedMemories.filter { $0.memoryType == "semantic"   } }
    private var episodic:   [MemorySummary] { displayedMemories.filter { $0.memoryType == "episodic"   } }

    private var filteredProposals: [MemoryReviewProposal] {
        proposals.filter { proposal in
            let matchesStatus = reviewFilter.matches(proposal.status)
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || proposalMatchesSearch(proposal)
            return matchesStatus && matchesSearch
        }
    }

    private var pendingProposals: [MemoryReviewProposal] { filteredProposals.filter { $0.status == "pending" } }
    private var approvedProposals: [MemoryReviewProposal] { filteredProposals.filter { $0.status == "approved" } }
    private var rejectedProposals: [MemoryReviewProposal] { filteredProposals.filter { $0.status == "rejected" } }

    var body: some View {
        VStack(spacing: 0) {
            surfacePicker
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if selectedSurface == .saved {
                graphMemoryLink
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                filterChips
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                reviewStatusChips
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()
            content
        }
        .navigationTitle("Memory")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .searchable(text: $searchText, prompt: selectedSurface == .saved ? "Search memories" : "Search memory review")
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete all memories?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await deleteAllMemories() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will deactivate all memories for your account. Export first if you want a copy.")
        }
        .fileExporter(
            isPresented: $isExportingFile,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
        }
        .alert("Memory Error", isPresented: Binding(
            get: { actionError != nil || loadError != nil },
            set: { if !$0 { actionError = nil; loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? loadError ?? "Unknown error")
        }
    }

    private var surfacePicker: some View {
        HStack(spacing: 8) {
            surfaceButton(label: "Saved", surface: .saved, badgeCount: nil)
            surfaceButton(label: "Review", surface: .review, badgeCount: pendingProposalCount)
        }
    }

    private func surfaceButton(label: String, surface: MemorySurface, badgeCount: Int?) -> some View {
        let selected = selectedSurface == surface
        return Button {
            selectedSurface = surface
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(selected ? Color.white.opacity(0.22) : Color.orange.opacity(0.16), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var graphMemoryLink: some View {
        NavigationLink {
            GraphMemoryView()
                .environment(authManager)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Graph Memory")
                        .font(.headline)
                    Text("Browse how Fruitcake connects people, places, projects, and facts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", type: nil)
                chipButton(label: "Procedural", type: "procedural")
                chipButton(label: "Semantic", type: "semantic")
                chipButton(label: "Episodic", type: "episodic")
            }
        }
    }

    private var reviewStatusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                reviewFilterButton(.pending)
                reviewFilterButton(.approved)
                reviewFilterButton(.rejected)
                reviewFilterButton(.all)
            }
        }
    }

    private func chipButton(label: String, type: String?) -> some View {
        let selected = filterType == type
        return Button {
            filterType = type
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? .white : .primary)
                .background(
                    selected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func reviewFilterButton(_ filter: ReviewStatusFilter) -> some View {
        let selected = reviewFilter == filter
        let count = filter.count(in: proposals)
        return Button {
            reviewFilter = filter
        } label: {
            HStack(spacing: 6) {
                Text(filter.label)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(selected ? Color.white.opacity(0.22) : Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if selectedSurface == .saved {
            savedContent
        } else {
            reviewContent
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if isLoading && memories.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedMemories.isEmpty {
            savedEmptyState
        } else {
            savedMemoryList
        }
    }

    private var savedMemoryList: some View {
        List {
            if !procedural.isEmpty {
                Section("Procedural") {
                    ForEach(procedural) { memory in
                        savedMemoryRow(memory)
                    }
                }
            }
            if !semantic.isEmpty {
                Section("Semantic") {
                    ForEach(semantic) { memory in
                        savedMemoryRow(memory)
                    }
                }
            }
            if !episodic.isEmpty {
                Section("Episodic") {
                    ForEach(episodic) { memory in
                        savedMemoryRow(memory)
                    }
                }
            }
        }
    }

    private func savedMemoryRow(_ memory: MemorySummary) -> some View {
        MemoryRow(memory: memory)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await deleteMemory(memory) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if isLoading && proposals.isEmpty {
            ProgressView("Loading review queue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredProposals.isEmpty {
            reviewEmptyState
        } else {
            reviewList
        }
    }

    private var reviewList: some View {
        List {
            if !pendingProposals.isEmpty {
                Section("Pending") {
                    ForEach(pendingProposals) { proposal in
                        MemoryReviewRow(
                            proposal: proposal,
                            isWorking: activeProposalID == proposal.id,
                            onApprove: { Task { await approveProposal(proposal) } },
                            onReject: { Task { await rejectProposal(proposal) } }
                        )
                    }
                }
            }
            if !approvedProposals.isEmpty {
                Section("Approved") {
                    ForEach(approvedProposals) { proposal in
                        MemoryReviewRow(
                            proposal: proposal,
                            isWorking: false,
                            onApprove: nil,
                            onReject: nil
                        )
                    }
                }
            }
            if !rejectedProposals.isEmpty {
                Section("Rejected") {
                    ForEach(rejectedProposals) { proposal in
                        MemoryReviewRow(
                            proposal: proposal,
                            isWorking: false,
                            onApprove: nil,
                            onReject: nil
                        )
                    }
                }
            }
        }
    }

    private var savedEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No memories yet" : "No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("As you chat, Fruitcake will remember facts, preferences, and routines.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    private var reviewEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.full")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(reviewFilter == .pending ? "No memory proposals waiting" : "No review items match this filter")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty
                 ? "Topic watchers and future document digests will surface memory suggestions here for approval."
                 : "Try a different search term or filter.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func proposalMatchesSearch(_ proposal: MemoryReviewProposal) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return proposal.content.localizedCaseInsensitiveContains(needle) ||
            (proposal.summaryReason?.localizedCaseInsensitiveContains(needle) ?? false) ||
            (proposal.topicDisplay?.localizedCaseInsensitiveContains(needle) ?? false) ||
            proposal.proposal.sourceNames.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
    }

    private func loadAll() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            async let loadedMemories = api.fetchMemories()
            async let loadedProposals = api.fetchMemoryReviewProposals()
            memories = try await loadedMemories
            proposals = try await loadedProposals
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteMemory(_ memory: MemorySummary) async {
        do {
            let api = APIClient(authManager: authManager)
            try await api.deleteMemory(memory.id)
            memories.removeAll { $0.id == memory.id }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func approveProposal(_ proposal: MemoryReviewProposal) async {
        activeProposalID = proposal.id
        defer { activeProposalID = nil }
        do {
            let api = APIClient(authManager: authManager)
            let response = try await api.approveMemoryReviewProposal(proposal.id)
            replaceProposal(response.proposal)
            if !memories.contains(where: { $0.id == response.memory.id }) {
                memories.insert(response.memory, at: 0)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func rejectProposal(_ proposal: MemoryReviewProposal) async {
        activeProposalID = proposal.id
        defer { activeProposalID = nil }
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.rejectMemoryReviewProposal(proposal.id)
            replaceProposal(updated)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func replaceProposal(_ proposal: MemoryReviewProposal) {
        if let idx = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[idx] = proposal
        } else {
            proposals.insert(proposal, at: 0)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectedSurface == .saved {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await exportMemories() }
                } label: {
                    Label("Export Memories", systemImage: "square.and.arrow.up")
                }
                .disabled(isLoading || isRunningAction)

                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All Memories", systemImage: "trash")
                }
                .disabled(memories.isEmpty || isLoading || isRunningAction)
            }
        }
    }

    private func exportMemories() async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            let data = try await api.exportMemories()
            exportDocument = MemoryExportDocument(data: data)
            exportFilename = "fruitcakeai-memories-\(timestampStamp())"
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteAllMemories() async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.bulkDeleteMemories()
            memories.removeAll()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func timestampStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private enum MemorySurface {
    case saved
    case review
}

private enum ReviewStatusFilter: CaseIterable {
    case pending
    case approved
    case rejected
    case all

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .all: return "All"
        }
    }

    func matches(_ status: String) -> Bool {
        switch self {
        case .pending: return status == "pending"
        case .approved: return status == "approved"
        case .rejected: return status == "rejected"
        case .all: return true
        }
    }

    func count(in proposals: [MemoryReviewProposal]) -> Int {
        proposals.filter { matches($0.status) }.count
    }
}

private struct MemoryRow: View {
    let memory: MemorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.content)
                .font(.body)

            HStack(spacing: 8) {
                Text(memory.typeAbbreviation)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(memory.typeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(memory.typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                Text(memory.importanceDots)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(memory.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let expires = memory.expiresAt {
                    Text("· expires \(expires.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !memory.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(memory.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MemoryReviewRow: View {
    let proposal: MemoryReviewProposal
    let isWorking: Bool
    let onApprove: (() -> Void)?
    let onReject: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(proposal.statusDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(proposal.statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(proposal.statusColor.opacity(0.12), in: Capsule())

                Text(proposal.memoryTypeDisplayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12), in: Capsule())

                Text(proposal.sourceDisplayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Spacer()

                Text("\(proposal.confidencePercent)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(proposal.content)
                .font(.body)

            if let topic = proposal.topicDisplay {
                Label(topic, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = proposal.summaryReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !proposal.proposal.sourceNames.isEmpty {
                Text(proposal.proposal.sourceNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !proposal.supportingURLValues.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(proposal.supportingURLValues.prefix(3)), id: \.absoluteString) { url in
                            Link(destination: url) {
                                Label(url.host ?? "Source", systemImage: "link")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if let createdAt = proposal.createdAt {
                    Text(createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let approvedMemoryId = proposal.approvedMemoryId {
                    Text("Approved as memory #\(approvedMemoryId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if proposal.isPending, let onApprove, let onReject {
                HStack(spacing: 10) {
                    Button { onApprove() } label: {
                        if isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)

                    Button(role: .destructive) { onReject() } label: {
                        Label("Reject", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MemoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview("Memories list") {
    NavigationStack {
        MemoriesView()
            .environment(AuthManager())
    }
}

#Preview("Memory row") {
    List {
        MemoryRow(memory: MemorySummary(
            id: 1,
            content: "Prefers concise answers without bullet points unless data-heavy.",
            memoryType: "procedural",
            importance: 0.8,
            accessCount: 12,
            tags: ["communication", "style"],
            createdAt: Date(timeIntervalSinceNow: -86400 * 3),
            expiresAt: nil
        ))
        MemoryReviewRow(
            proposal: MemoryReviewProposal(
                id: 8,
                proposalType: "flat_memory_create",
                sourceType: "topic_watcher",
                status: "pending",
                taskId: 53,
                taskRunId: 902,
                content: "On 2026-03-25, reports about Iran indicated renewed diplomatic talks and sanctions pressure.",
                confidence: 0.82,
                reason: "Strong watcher hit.",
                createdAt: Date(timeIntervalSinceNow: -1800),
                resolvedAt: nil,
                resolvedByUserId: nil,
                approvedMemoryId: nil,
                proposal: MemoryReviewProposalPayload(
                    proposalKey: "demo",
                    memoryType: "episodic",
                    content: "On 2026-03-25, reports about Iran indicated renewed diplomatic talks and sanctions pressure.",
                    topic: "Iran",
                    supportingUrls: ["https://example.com/iran"],
                    sourceNames: ["Reuters", "BBC"],
                    reason: "Strong watcher hit.",
                    confidence: 0.82
                )
            ),
            isWorking: false,
            onApprove: {},
            onReject: {}
        )
    }
}
