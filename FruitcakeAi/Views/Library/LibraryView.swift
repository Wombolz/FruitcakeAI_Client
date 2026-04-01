//
//  LibraryView.swift
//  FruitcakeAi
//
//  Document library: lists imported and linked documents, supports upload,
//  linked-source management, semantic search, pull-to-refresh, and delete.
//

import SwiftUI
import UniformTypeIdentifiers

private let librarySkipDirectoryNames: Set<String> = [
    ".git", ".hg", ".svn", ".venv", "venv", "node_modules", "__pycache__",
    ".pytest_cache", ".mypy_cache", "dist", "build"
]

// MARK: - API types

struct DocumentSummary: Codable, Identifiable {
    let id: Int
    let filename: String
    var scope: String
    let createdAt: String
    let processingStatus: String
    let contentType: String?
    let chunkCount: Int?
    let summary: String?
    let ingestJobStatus: String?
    let ingestAttemptCount: Int?
    let ingestLastError: String?
    let sourceMode: String?
    let sourceSyncStatus: String?
    let linkedSourceId: Int?
    let sourcePath: String?
    let sourceLastSeenAt: String?
    let sourceModifiedAt: String?

    var statusIcon: String {
        switch processingStatus {
        case "ready": return "checkmark.circle.fill"
        case "processing": return "clock.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "doc.fill"
        }
    }

    var statusColor: Color {
        switch processingStatus {
        case "ready": return .green
        case "processing": return .orange
        case "error": return .red
        default: return .secondary
        }
    }

    var scopeColor: Color {
        switch scope {
        case "family": return .purple
        case "shared": return .teal
        default: return .blue
        }
    }

    var isLinked: Bool { sourceMode == "linked" }

    var sourceStatusColor: Color {
        switch sourceSyncStatus {
        case "missing": return .red
        case "synced": return .green
        case "stale": return .orange
        default: return .secondary
        }
    }
}

struct LinkedSourceSummary: Codable, Identifiable {
    let id: Int
    let name: String
    let sourceType: String
    let rootPath: String
    let scope: String
    let syncStatus: String
    let errorMessage: String?
    let lastScannedAt: String?
    let excludedPaths: [String]
    let skippedEmptyCount: Int
    let documentCount: Int
    let readyDocumentCount: Int
    let missingDocumentCount: Int
    let createdAt: String

    var iconName: String {
        sourceType == "folder" ? "folder.fill" : "doc.text.fill"
    }

    var syncColor: Color {
        switch syncStatus {
        case "ready": return .green
        case "missing", "error": return .red
        case "pending": return .orange
        default: return .secondary
        }
    }
}

struct LinkedSourceResponse: Codable {
    let source: LinkedSourceSummary
    let sync: LinkedSourceSyncSummary?
    let tree: [LinkedSourceTreeNode]?
}

struct LinkedSourceSyncSummary: Codable {
    let created: Int
    let queued: Int
    let updated: Int
    let unchanged: Int
    let missing: Int
    let skippedEmpty: Int
    let removed: Int?
}

struct LinkedSourceTreeNode: Codable, Identifiable {
    let name: String
    let path: String
    let type: String
    let excluded: Bool
    let documentId: Int?
    let processingStatus: String?
    let sourceSyncStatus: String?
    let children: [LinkedSourceTreeNode]
    let childCount: Int

    var id: String { path }
    var isFolder: Bool { type == "folder" }
}

struct LinkedSourceDetailResponse: Codable {
    let source: LinkedSourceSummary
    let tree: [LinkedSourceTreeNode]
}

struct SemanticResult: Identifiable {
    let id = UUID()
    let text: String
    let score: Double
    let filename: String
}

struct ExclusionFolderRow: Identifiable {
    let id: String
    let path: String
    let name: String
    let depth: Int
}

// MARK: - LibraryView

struct LibraryView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var documents: [DocumentSummary] = []
    @State private var linkedSources: [LinkedSourceSummary] = []
    @State private var sourceDetails: [Int: LinkedSourceDetailResponse] = [:]
    @State private var expandedSourceIDs: Set<Int> = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showUpload = false
    @State private var showLinkSource = false
    @State private var managingSourceID: Int?
    @State private var deleteError: String?
    @State private var sourceActionError: String?
    @State private var searchText = ""
    @State private var showSemanticSearch = false
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar { toolbarButtons }
                .refreshable { await loadLibraryData() }
                .searchable(text: $searchText, prompt: "Filter documents")
                .sheet(isPresented: $showUpload) {
                    DocumentUpload { await loadLibraryData() }
                }
                .sheet(isPresented: $showSemanticSearch) {
                    SemanticSearchSheet()
                }
                #if os(macOS)
                .sheet(isPresented: $showLinkSource) {
                    LinkedSourceSheet { await loadLibraryData() }
                }
                .sheet(isPresented: Binding(
                    get: { managingSourceID != nil },
                    set: { if !$0 { managingSourceID = nil } }
                )) {
                    if let managingSourceID,
                       let detail = sourceDetails[managingSourceID] {
                        LinkedSourceExclusionsSheet(
                            detail: detail,
                            onSave: { excludedPaths in
                                await saveExclusions(sourceID: managingSourceID, excludedPaths: excludedPaths)
                            }
                        )
                    }
                }
                .frame(minWidth: 400, idealWidth: 560, minHeight: 400, idealHeight: 520)
                #endif
                .task { await loadLibraryData() }
                .onDisappear { stopPolling() }
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if let deleteError {
                            banner(deleteError, color: .red)
                        }
                        if let sourceActionError {
                            banner(sourceActionError, color: .red)
                        }
                    }
                    .padding(.top, 8)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && documents.isEmpty && linkedSources.isEmpty {
            ProgressView("Loading library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError, documents.isEmpty && linkedSources.isEmpty {
            ContentUnavailableView {
                Label("Could not load library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadLibraryData() } }
            }
        } else if documents.isEmpty && linkedSources.isEmpty {
            ContentUnavailableView(
                "No library content",
                systemImage: "doc.badge.plus",
                description: Text("Upload a document or add a linked source to start indexing files.")
            )
        } else {
            documentList
        }
    }

    private var folderSourceIDs: Set<Int> {
        Set(linkedSources.filter { $0.sourceType == "folder" }.map(\.id))
    }

    private var filteredDocuments: [DocumentSummary] {
        let base = documents.filter { doc in
            guard let sourceID = doc.linkedSourceId else { return true }
            return !folderSourceIDs.contains(sourceID)
        }
        guard !searchText.isEmpty else { return base }
        return documents.filter {
            $0.filename.localizedCaseInsensitiveContains(searchText)
                || ($0.sourcePath?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var documentList: some View {
        List {
            if searchText.isEmpty {
                linkedSourceSections
            }

            if !filteredDocuments.isEmpty {
                Section(searchText.isEmpty ? "Documents" : "Search Results") {
                    ForEach(filteredDocuments) { doc in
                        DocumentRow(doc: doc)
                            .contextMenu {
                                Menu("Change Scope") {
                                    Button("Personal") { Task { await updateScope(doc, scope: "personal") } }
                                    Button("Family") { Task { await updateScope(doc, scope: "family") } }
                                    Button("Shared") { Task { await updateScope(doc, scope: "shared") } }
                                }
                                if doc.isLinked, let sourcePath = doc.sourcePath {
                                    Divider()
                                    Text(sourcePath)
                                }
                            }
                    }
                    .onDelete { offsets in
                        Task { await deleteDocuments(at: offsets) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linkedSourceSections: some View {
        if !linkedSources.filter({ $0.sourceType == "folder" }).isEmpty {
            Section("Linked Sources") {
                ForEach(linkedSources.filter { $0.sourceType == "folder" }) { source in
                    LinkedFolderSourceSection(
                        source: source,
                        detail: sourceDetails[source.id],
                        isExpanded: expandedSourceIDs.contains(source.id),
                        onToggleExpanded: { toggleExpanded(source.id) },
                        onRescan: { await rescan(source) },
                        onManage: { managingSourceID = source.id },
                        onExcludeFolder: { path in
                            await excludeFolder(sourceID: source.id, path: path)
                        }
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(macOS)
            Button {
                showLinkSource = true
            } label: {
                Label("Link Source", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .disabled(!connectivity.isBackendReachable)
            #endif

            Button {
                showUpload = true
            } label: {
                Label("Upload", systemImage: "plus")
            }
            .disabled(!connectivity.isBackendReachable)

            Button {
                showSemanticSearch = true
            } label: {
                Label("Semantic Search", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(documents.isEmpty)
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .background(color)
            .clipShape(Capsule())
    }

    private func toggleExpanded(_ sourceID: Int) {
        if expandedSourceIDs.contains(sourceID) {
            expandedSourceIDs.remove(sourceID)
        } else {
            expandedSourceIDs.insert(sourceID)
        }
    }

    private func loadLibraryData() async {
        isLoading = true
        loadError = nil
        let api = APIClient(authManager: authManager)
        do {
            async let docsTask: [DocumentSummary] = api.request("/library/documents")
            async let sourcesTask = api.fetchLinkedSources()
            let fetchedDocs = try await docsTask
            let fetchedSources = try await sourcesTask
            documents = fetchedDocs
            linkedSources = fetchedSources
            await loadSourceDetails(for: fetchedSources.filter { $0.sourceType == "folder" })
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
        startPollingIfNeeded()
    }

    private func loadSourceDetails(for sources: [LinkedSourceSummary]) async {
        let api = APIClient(authManager: authManager)
        var details: [Int: LinkedSourceDetailResponse] = [:]
        for source in sources {
            if let detail: LinkedSourceDetailResponse = try? await api.fetchLinkedSource(source.id) {
                details[source.id] = detail
            }
        }
        sourceDetails = details
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
        documents[idx].scope = scope
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
            documents[idx].scope = oldScope
        }
    }

    private func rescan(_ source: LinkedSourceSummary) async {
        let api = APIClient(authManager: authManager)
        do {
            let response = try await api.rescanLinkedSource(source.id)
            applySourceResponse(response)
            await refreshDocuments()
        } catch {
            showSourceError("Failed to rescan \"\(source.name)\".")
        }
    }

    private func saveExclusions(sourceID: Int, excludedPaths: [String]) async {
        let api = APIClient(authManager: authManager)
        do {
            let detail = try await api.updateLinkedSourceExclusions(sourceID, excludedPaths: excludedPaths)
            applySourceDetail(detail)
            await refreshDocuments()
            managingSourceID = nil
        } catch {
            showSourceError("Failed to update linked source exclusions.")
        }
    }

    private func excludeFolder(sourceID: Int, path: String) async {
        guard let current = sourceDetails[sourceID]?.source else { return }
        var excluded = current.excludedPaths
        if !excluded.contains(path) {
            excluded.append(path)
        }
        await saveExclusions(sourceID: sourceID, excludedPaths: excluded.sorted())
    }

    private func refreshDocuments() async {
        let api = APIClient(authManager: authManager)
        if let fetchedDocs: [DocumentSummary] = try? await api.request("/library/documents") {
            documents = fetchedDocs
        }
        if let fetchedSources = try? await api.fetchLinkedSources() {
            linkedSources = fetchedSources
        }
        await loadSourceDetails(for: linkedSources.filter { $0.sourceType == "folder" })
    }

    private func applySourceResponse(_ response: LinkedSourceResponse) {
        if let idx = linkedSources.firstIndex(where: { $0.id == response.source.id }) {
            linkedSources[idx] = response.source
        } else {
            linkedSources.append(response.source)
        }
        if let tree = response.tree {
            sourceDetails[response.source.id] = LinkedSourceDetailResponse(source: response.source, tree: tree)
        }
    }

    private func applySourceDetail(_ detail: LinkedSourceDetailResponse) {
        if let idx = linkedSources.firstIndex(where: { $0.id == detail.source.id }) {
            linkedSources[idx] = detail.source
        }
        sourceDetails[detail.source.id] = detail
    }

    private func showSourceError(_ message: String) {
        sourceActionError = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            sourceActionError = nil
        }
    }

    private func startPollingIfNeeded() {
        guard documents.contains(where: { $0.processingStatus == "processing" }) else { return }
        guard pollingTask?.isCancelled ?? true else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshDocuments()
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

// MARK: - Rows

private struct DocumentRow: View {
    let doc: DocumentSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: doc.isLinked ? "link.circle.fill" : "doc.text.fill")
                .font(.title3)
                .foregroundStyle(doc.isLinked ? .teal : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(doc.filename)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(doc.scope.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(doc.scopeColor.opacity(0.12))
                        .foregroundStyle(doc.scopeColor)
                        .clipShape(Capsule())

                    if doc.isLinked {
                        Text(doc.sourceSyncStatus?.capitalized ?? "Linked")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(doc.sourceStatusColor.opacity(0.12))
                            .foregroundStyle(doc.sourceStatusColor)
                            .clipShape(Capsule())
                    }

                    Image(systemName: doc.statusIcon)
                        .font(.caption)
                        .foregroundStyle(doc.statusColor)

                    Text(doc.processingStatus.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let sourcePath = doc.sourcePath, doc.isLinked {
                    Text(sourcePath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LinkedFolderSourceSection: View {
    let source: LinkedSourceSummary
    let detail: LinkedSourceDetailResponse?
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onRescan: () async -> Void
    let onManage: () -> Void
    let onExcludeFolder: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: source.iconName)
                    .font(.title3)
                    .foregroundStyle(source.syncColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.body.weight(.medium))
                    Text(source.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(source.readyDocumentCount)/\(source.documentCount) ready")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if source.skippedEmptyCount > 0 {
                            Text("\(source.skippedEmptyCount) empty skipped")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                Button("Manage") { onManage() }
                    .buttonStyle(.borderless)
                Button("Rescan") {
                    Task { await onRescan() }
                }
                .buttonStyle(.bordered)
            }

            if isExpanded {
                if let detail {
                    if detail.tree.isEmpty {
                        Text("No indexed files yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 36)
                    } else {
                        LinkedSourceTreeList(nodes: detail.tree, onExcludeFolder: onExcludeFolder)
                            .padding(.leading, 36)
                    }
                } else {
                    ProgressView()
                        .padding(.leading, 36)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LinkedSourceTreeList: View {
    let nodes: [LinkedSourceTreeNode]
    let onExcludeFolder: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                LinkedSourceTreeNodeView(node: node, depth: 0, onExcludeFolder: onExcludeFolder)
            }
        }
    }
}

private struct LinkedSourceTreeNodeView: View {
    let node: LinkedSourceTreeNode
    let depth: Int
    let onExcludeFolder: (String) async -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if node.isFolder {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: node.isFolder ? "folder.fill" : "doc.text")
                    .foregroundStyle(node.excluded ? .red : .secondary)
                Text(node.name)
                    .font(.subheadline)
                    .foregroundStyle(node.excluded ? .secondary : .primary)

                if node.excluded {
                    Text("Excluded")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }

                Spacer()

                if node.isFolder && !node.excluded {
                    Button("Exclude") {
                        Task { await onExcludeFolder(node.path) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.leading, CGFloat(depth) * 16)

            if node.isFolder && isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    LinkedSourceTreeNodeView(node: child, depth: depth + 1, onExcludeFolder: onExcludeFolder)
                }
            }
        }
    }
}

#if os(macOS)
private struct LinkedSourceSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var onComplete: () async -> Void

    @State private var sourceKind = "folder"
    @State private var scope = "personal"
    @State private var selectedPath: String?
    @State private var selectableFolders: [SelectableFolder] = []
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var showFilePicker = false
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Source Type") {
                    Picker("Type", selection: $sourceKind) {
                        Text("Folder / Repo").tag("folder")
                        Text("Single File").tag("file")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Path") {
                    HStack {
                        Text(selectedPath ?? "No path selected")
                            .foregroundStyle(selectedPath == nil ? .secondary : .primary)
                            .lineLimit(2)
                        Spacer()
                        Button(sourceKind == "folder" ? "Choose Folder" : "Choose File") {
                            if sourceKind == "folder" {
                                showFolderPicker = true
                            } else {
                                showFilePicker = true
                            }
                        }
                    }
                }

                if sourceKind == "folder" && !selectableFolders.isEmpty {
                    Section {
                        ForEach($selectableFolders) { $folder in
                            Toggle(isOn: $folder.isIncluded) {
                                Text(folder.path)
                                    .padding(.leading, CGFloat(folder.depth) * 14)
                            }
                            .toggleStyle(.checkbox)
                        }
                    } header: {
                        Text("Included Folders")
                    } footer: {
                        Text("Deselect folders you do not want indexed. Their contents will be skipped on import and future rescans.")
                    }
                }

                Section("Visibility") {
                    Picker("Scope", selection: $scope) {
                        Label("Personal", systemImage: "person.fill").tag("personal")
                        Label("Family", systemImage: "person.2.fill").tag("family")
                        Label("Shared", systemImage: "globe").tag("shared")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Text("Linked sources only work when the backend can read the selected absolute path. Use this on the machine hosting Fruitcake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Link Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await submit() }
                    }
                    .disabled(selectedPath == nil || isSubmitting)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFilePickerResult(result)
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPickerResult(result)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 460)
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedPath = urls.first?.path
            selectableFolders = []
            errorText = nil
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func handleFolderPickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedPath = url.path
            selectableFolders = enumerateSelectableFolders(rootURL: url)
            errorText = nil
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func submit() async {
        guard let selectedPath else { return }
        isSubmitting = true
        errorText = nil
        let api = APIClient(authManager: authManager)
        do {
            if sourceKind == "folder" {
                let excludedPaths = selectableFolders.filter { !$0.isIncluded }.map(\.path)
                _ = try await api.linkFolderSource(path: selectedPath, scope: scope, excludedPaths: excludedPaths)
            } else {
                _ = try await api.linkFileSource(path: selectedPath, scope: scope)
            }
            await onComplete()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isSubmitting = false
    }

    private func enumerateSelectableFolders(rootURL: URL) -> [SelectableFolder] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var folders: [SelectableFolder] = []
        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }
            let relative = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if relative.isEmpty { continue }
            let parts = relative.split(separator: "/")
            if parts.contains(where: { librarySkipDirectoryNames.contains(String($0)) }) {
                continue
            }
            folders.append(
                SelectableFolder(
                    id: relative,
                    path: relative,
                    depth: max(parts.count - 1, 0),
                    isIncluded: true
                )
            )
        }
        return folders.sorted { $0.path < $1.path }
    }
}

private struct SelectableFolder: Identifiable {
    let id: String
    let path: String
    let depth: Int
    var isIncluded: Bool
}

private struct LinkedSourceExclusionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let detail: LinkedSourceDetailResponse
    let onSave: ([String]) async -> Void

    @State private var folders: [ExclusionFolderRow] = []
    @State private var excludedPaths: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.source.name)
                        .font(.headline)
                    Text(detail.source.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Divider()

                Text("Included Folders")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                List(folders) { folder in
                    Toggle(isOn: Binding(
                        get: { !excludedPaths.contains(folder.path) },
                        set: { isIncluded in
                            if isIncluded {
                                excludedPaths.remove(folder.path)
                            } else {
                                excludedPaths.insert(folder.path)
                            }
                        }
                    )) {
                        Text(folder.path)
                            .padding(.leading, CGFloat(folder.depth) * 14)
                    }
                    .toggleStyle(.checkbox)
                }

                Text("Turning a folder off removes its indexed files immediately and keeps it excluded on future rescans.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Manage Folders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            await onSave(Array(excludedPaths).sorted())
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                folders = collectFolderRows(from: detail.tree)
                excludedPaths = Set(detail.source.excludedPaths)
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 460)
    }

    private func collectFolderRows(from nodes: [LinkedSourceTreeNode], depth: Int = 0) -> [ExclusionFolderRow] {
        var rows: [ExclusionFolderRow] = []
        for node in nodes where node.isFolder {
            rows.append(ExclusionFolderRow(id: node.path, path: node.path, name: node.name, depth: depth))
            rows.append(contentsOf: collectFolderRows(from: node.children, depth: depth + 1))
        }
        return rows
    }
}
#endif

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
