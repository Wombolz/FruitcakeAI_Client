//
//  MemoriesView.swift
//  FruitcakeAi
//
//  Navigation destination pushed from SettingsView.
//  Shows what the assistant knows about the current user, with type filtering,
//  full-text search, and swipe-to-delete.
//

import SwiftUI

// MARK: - MemoriesView

struct MemoriesView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var memories: [MemorySummary] = []
    @State private var filterType: String? = nil    // nil = All
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?

    // MARK: - Derived

    private var displayed: [MemorySummary] {
        memories.filter { memory in
            let matchesSearch = searchText.isEmpty ||
                memory.content.localizedCaseInsensitiveContains(searchText)
            return matchesSearch
        }
    }

    private var procedural: [MemorySummary] { displayed.filter { $0.memoryType == "procedural" } }
    private var semantic:   [MemorySummary] { displayed.filter { $0.memoryType == "semantic"   } }
    private var episodic:   [MemorySummary] { displayed.filter { $0.memoryType == "episodic"   } }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            filterChips
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            content
        }
        .navigationTitle("Memories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .searchable(text: $searchText, prompt: "Search memories")
        .task { await loadMemories() }
        .refreshable { await loadMemories() }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", type: nil)
                chipButton(label: "Procedural", type: "procedural")
                chipButton(label: "Semantic",   type: "semantic")
                chipButton(label: "Episodic",   type: "episodic")
            }
        }
    }

    private func chipButton(label: String, type: String?) -> some View {
        let selected = filterType == type
        return Button {
            filterType = type
            Task { await loadMemories() }
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && memories.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayed.isEmpty {
            emptyState
        } else {
            memoryList
        }
    }

    private var memoryList: some View {
        List {
            if !procedural.isEmpty {
                Section("Procedural") {
                    ForEach(procedural) { memory in
                        memoryRow(memory)
                    }
                }
            }
            if !semantic.isEmpty {
                Section("Semantic") {
                    ForEach(semantic) { memory in
                        memoryRow(memory)
                    }
                }
            }
            if !episodic.isEmpty {
                Section("Episodic") {
                    ForEach(episodic) { memory in
                        memoryRow(memory)
                    }
                }
            }
        }
    }

    private func memoryRow(_ memory: MemorySummary) -> some View {
        MemoryRow(memory: memory)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await deleteMemory(memory) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No memories yet" : "No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("As you chat, FruitcakeAI will remember facts, preferences, and routines.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: - Data

    private func loadMemories() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            memories = try await api.fetchMemories(type: filterType)
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
}

// MARK: - MemoryRow

private struct MemoryRow: View {

    let memory: MemorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.content)
                .font(.body)

            HStack(spacing: 8) {
                // Type badge
                Text(memory.typeAbbreviation)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(memory.typeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(memory.typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                // Importance dots
                Text(memory.importanceDots)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Relative age
                Text(memory.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Expiry (if set)
                if let expires = memory.expiresAt {
                    Text("· expires \(expires.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Tags
            if !memory.tags.isEmpty {
                tagRow
            }
        }
        .padding(.vertical, 2)
    }

    private var tagRow: some View {
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

// MARK: - Previews

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
        MemoryRow(memory: MemorySummary(
            id: 2,
            content: "Has a dentist appointment on March 15, 2026.",
            memoryType: "episodic",
            importance: 0.6,
            accessCount: 2,
            tags: ["appointment", "health"],
            createdAt: Date(timeIntervalSinceNow: -3600),
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: Date())
        ))
    }
}
