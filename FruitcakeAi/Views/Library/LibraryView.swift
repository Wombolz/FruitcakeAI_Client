//
//  LibraryView.swift
//  FruitcakeAi
//
//  Document library: lists all documents owned by the current user
//  (GET /library/documents), shows scope badge, supports pull-to-refresh
//  and swipe-to-delete (DELETE /library/documents/{id}).
//

import SwiftUI

// MARK: - API types

struct DocumentSummary: Codable, Identifiable {
    let id: Int
    let filename: String
    var scope: String           // var: allows optimistic scope updates
    let createdAt: String
    let processingStatus: String
    // No CodingKeys — APIClient.decode() uses convertFromSnakeCase,
    // which converts "created_at" → createdAt and "processing_status" → processingStatus
    // automatically. Explicit snake_case CodingKeys conflict with that strategy.

    var statusIcon: String {
        switch processingStatus {
        case "ready":      return "checkmark.circle.fill"
        case "processing": return "clock.fill"
        case "error":      return "exclamationmark.triangle.fill"
        default:           return "doc.fill"
        }
    }

    var statusColor: Color {
        switch processingStatus {
        case "ready":      return .green
        case "processing": return .orange
        case "error":      return .red
        default:           return .secondary
        }
    }

    var scopeColor: Color {
        switch scope {
        case "family":  return .purple
        case "shared":  return .teal
        default:        return .blue    // personal
        }
    }
}

struct SemanticResult: Identifiable {
    let id = UUID()
    let text: String
    let score: Double
    let filename: String
}

// MARK: - LibraryView

struct LibraryView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var documents: [DocumentSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showUpload = false
    @State private var deleteError: String?
    @State private var searchText = ""
    @State private var showSemanticSearch = false
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar { toolbarButtons }
                .refreshable { await loadDocuments() }
                .searchable(text: $searchText, prompt: "Filter documents")
                .sheet(isPresented: $showUpload) {
                    DocumentUpload { await loadDocuments() }
                }
                .sheet(isPresented: $showSemanticSearch) {
                    SemanticSearchSheet()
                }
                .task { await loadDocuments() }
                .onDisappear { stopPolling() }
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
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if isLoading && documents.isEmpty {
            ProgressView("Loading library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError, documents.isEmpty {
            ContentUnavailableView {
                Label("Could not load library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadDocuments() } }
            }
        } else if documents.isEmpty {
            ContentUnavailableView(
                "No documents",
                systemImage: "doc.badge.plus",
                description: Text("Upload a document and it will appear here after processing.")
            )
        } else {
            documentList
        }
    }

    private var filteredDocuments: [DocumentSummary] {
        guard !searchText.isEmpty else { return documents }
        return documents.filter {
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var documentList: some View {
        List {
            ForEach(filteredDocuments) { doc in
                DocumentRow(doc: doc)
                    .contextMenu {
                        Menu("Change Scope") {
                            Button("Personal") { Task { await updateScope(doc, scope: "personal") } }
                            Button("Family")   { Task { await updateScope(doc, scope: "family") } }
                            Button("Shared")   { Task { await updateScope(doc, scope: "shared") } }
                        }
                    }
            }
            .onDelete { offsets in
                Task { await deleteDocuments(at: offsets) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showUpload = true
            } label: {
                Label("Upload", systemImage: "plus")
            }
            .disabled(!connectivity.isBackendReachable)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showSemanticSearch = true
            } label: {
                Label("Semantic Search", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(documents.isEmpty)
        }
    }

    // MARK: - Networking

    private func loadDocuments() async {
        isLoading = true
        loadError = nil
        let api = APIClient(authManager: authManager)
        do {
            documents = try await api.request("/library/documents")
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
        startPollingIfNeeded()
    }

    private func deleteDocuments(at offsets: IndexSet) async {
        let toDelete = offsets.map { filteredDocuments[$0] }
        let api = APIClient(authManager: authManager)

        for doc in toDelete {
            do {
                try await api.requestVoid("/library/documents/\(doc.id)", method: "DELETE")
                withAnimation {
                    documents.removeAll { $0.id == doc.id }
                }
            } catch {
                deleteError = "Failed to delete \"\(doc.filename)\""
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    deleteError = nil
                }
            }
        }
    }

    private func updateScope(_ doc: DocumentSummary, scope: String) async {
        guard let idx = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        let oldScope = documents[idx].scope
        documents[idx].scope = scope  // optimistic update
        struct ScopeBody: Encodable { let scope: String }
        struct ScopeResponse: Decodable { let id: Int; let scope: String }
        let api = APIClient(authManager: authManager)
        do {
            _ = try await api.request(
                "/library/documents/\(doc.id)",
                method: "PATCH",
                body: ScopeBody(scope: scope)
            ) as ScopeResponse
        } catch {
            documents[idx].scope = oldScope  // revert on failure
        }
    }

    // MARK: - Polling

    private func startPollingIfNeeded() {
        guard documents.contains(where: { $0.processingStatus == "processing" }) else { return }
        guard pollingTask?.isCancelled ?? true else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                let api = APIClient(authManager: authManager)
                if let fetched: [DocumentSummary] = try? await api.request("/library/documents") {
                    documents = fetched
                }
                if !documents.contains(where: { $0.processingStatus == "processing" }) {
                    break
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

// MARK: - Document row

private struct DocumentRow: View {
    let doc: DocumentSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(doc.filename)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Scope badge
                    Text(doc.scope.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(doc.scopeColor.opacity(0.12))
                        .foregroundStyle(doc.scopeColor)
                        .clipShape(Capsule())

                    // Processing status
                    Image(systemName: doc.statusIcon)
                        .font(.caption)
                        .foregroundStyle(doc.statusColor)

                    Text(doc.processingStatus.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Semantic Search Sheet

private struct SemanticSearchSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SemanticResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            List(results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.text)
                        .font(.body)
                        .lineLimit(4)
                    Text(String(format: "Score: %.2f", result.score))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if let searchError {
                    ContentUnavailableView(
                        "Search failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(searchError)
                    )
                } else if results.isEmpty && !isSearching {
                    ContentUnavailableView(
                        "Search your library",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Enter a query above to find relevant passages")
                    )
                }
            }
            .overlay(alignment: .top) {
                if isSearching {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .searchable(text: $query, prompt: "Ask anything about your documents")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .navigationTitle("Semantic Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 560, minHeight: 400, idealHeight: 520)
    }

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            struct QueryResult: Decodable {
                let text: String
                let score: Double
                let metadata: [String: String]
            }
            struct QueryResponse: Decodable {
                let results: [QueryResult]
            }
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let response: QueryResponse = try await APIClient(authManager: authManager)
                .request("/library/query?q=\(encoded)&top_k=10")
            results = response.results.map {
                SemanticResult(text: $0.text, score: $0.score,
                               filename: $0.metadata["filename"] ?? "Unknown")
            }
        } catch {
            searchError = error.localizedDescription
        }
    }
}

#Preview {
    LibraryView()
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
}
