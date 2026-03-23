//
//  GraphMemoryView.swift
//  FruitcakeAi
//
//  Settings > Memories > Graph Memory.
//  Browse graph entities, inspect one node, and edit/deactivate entities
//  and observations without exposing admin diagnostics.
//

import SwiftUI

struct GraphMemoryView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var entities: [GraphMemoryEntity] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasLoaded = false

    private var displayedEntities: [GraphMemoryEntity] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return entities
        }
        return entities.filter { entity in
            entity.name.localizedCaseInsensitiveContains(searchText) ||
            entity.entityType.localizedCaseInsensitiveContains(searchText) ||
            entity.aliases.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        List {
            if isLoading && !hasLoaded {
                ProgressView("Loading graph memory…")
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let loadError, entities.isEmpty {
                ContentUnavailableView {
                    Label("Could not load graph memory", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { Task { await loadEntities() } }
                }
                .listRowSeparator(.hidden)
            } else if displayedEntities.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No graph memory yet" : "No graph matches",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(
                        searchText.isEmpty
                        ? "This is the relationship layer on top of memories. It helps Fruitcake understand how people, places, projects, and facts connect."
                        : "Try a different entity name, alias, or type."
                    )
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(displayedEntities) { entity in
                    NavigationLink {
                        GraphMemoryDetailView(entityID: entity.id)
                            .environment(authManager)
                    } label: {
                        GraphMemoryEntityRow(entity: entity)
                    }
                }
            }
        }
        .navigationTitle("Graph Memory")
        .searchable(text: $searchText, prompt: "Search entities")
        .task { await loadEntities() }
        .refreshable { await loadEntities() }
        .onSubmit(of: .search) {
            Task { await loadEntities() }
        }
        .alert("Graph Memory Error", isPresented: Binding(
            get: { loadError != nil && !isLoading },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Unknown error")
        }
    }

    private func loadEntities() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let api = APIClient(authManager: authManager)
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entities = try await api.fetchGraphMemoryEntities()
            } else {
                entities = try await api.searchGraphMemoryEntities(query: searchText)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct GraphMemoryEntityRow: View {
    let entity: GraphMemoryEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entity.name)
                    .font(.headline)
                Spacer()
                Text(entity.displayType)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12), in: Capsule())
            }

            if !entity.aliases.isEmpty {
                Text(entity.aliases.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Label("\(entity.relationCount)", systemImage: "link")
                Label("\(entity.observationCount)", systemImage: "text.alignleft")
                Label("\(Int((entity.confidence * 100).rounded()))%", systemImage: "gauge")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct GraphMemoryDetailView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let entityID: Int

    @State private var node: GraphMemoryNode?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var entityDraft: GraphMemoryEntityPatch?
    @State private var observationDraft: GraphMemoryObservationPatch?
    @State private var editingObservationID: Int?
    @State private var showEntityEditor = false
    @State private var showObservationEditor = false
    @State private var showEntityDeactivateConfirmation = false
    @State private var observationToDeactivate: GraphMemoryObservation?
    @State private var isRunningAction = false

    var body: some View {
        List {
            if isLoading && node == nil {
                ProgressView("Loading entity…")
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let loadError, node == nil {
                ContentUnavailableView {
                    Label("Could not load entity", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { Task { await loadNode() } }
                }
                .listRowSeparator(.hidden)
            } else if let node {
                Section("Entity") {
                    LabeledContent("Name", value: node.entity.name)
                    LabeledContent("Type", value: node.entity.displayType)
                    LabeledContent("Aliases", value: node.entity.aliases.isEmpty ? "None" : node.entity.aliases.joined(separator: ", "))
                    LabeledContent("Confidence", value: "\(Int((node.entity.confidence * 100).rounded()))%")
                }

                if !node.relations.isEmpty {
                    Section("Relations") {
                        ForEach(node.relations) { relation in
                            NavigationLink {
                                GraphMemoryDetailView(
                                    entityID: relation.fromEntity.id == node.entity.id ? relation.toEntity.id : relation.fromEntity.id
                                )
                                .environment(authManager)
                            } label: {
                                GraphMemoryRelationRow(
                                    relation: relation,
                                    currentEntityID: node.entity.id
                                )
                            }
                        }
                    }
                }

                Section("Observations") {
                    if node.observations.isEmpty {
                        Text("No active observations for this entity.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(node.observations) { observation in
                            GraphMemoryObservationRow(observation: observation)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        observationToDeactivate = observation
                                    } label: {
                                        Label("Deactivate", systemImage: "trash")
                                    }

                                    Button {
                                        observationDraft = GraphMemoryObservationPatch(
                                            content: observation.content,
                                            observedAt: observation.observedAt,
                                            confidence: observation.confidence
                                        )
                                        editingObservationID = observation.id
                                        showObservationEditor = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(node?.entity.name ?? "Graph Entity")
        .toolbar {
            if node != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        guard let entity = node?.entity else { return }
                        entityDraft = GraphMemoryEntityPatch(
                            name: entity.name,
                            entityType: entity.entityType,
                            aliases: entity.aliases,
                            confidence: entity.confidence
                        )
                        showEntityEditor = true
                    } label: {
                        Label("Edit Entity", systemImage: "pencil")
                    }
                    .disabled(isRunningAction)

                    Button(role: .destructive) {
                        showEntityDeactivateConfirmation = true
                    } label: {
                        Label("Deactivate Entity", systemImage: "trash")
                    }
                    .disabled(isRunningAction)
                }
            }
        }
        .task { await loadNode() }
        .refreshable { await loadNode() }
        .sheet(isPresented: $showEntityEditor) {
            if let entityDraft {
                GraphMemoryEntityEditSheet(
                    draft: entityDraft,
                    onSave: { draft in
                        Task { await updateEntity(draft) }
                    }
                )
            }
        }
        .sheet(isPresented: $showObservationEditor) {
            if let observationDraft, let editingObservationID {
                GraphMemoryObservationEditSheet(
                    draft: observationDraft,
                    onSave: { draft in
                        Task { await updateObservation(id: editingObservationID, draft: draft) }
                    }
                )
            }
        }
        .confirmationDialog(
            "Deactivate entity?",
            isPresented: $showEntityDeactivateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                Task { await deactivateEntity() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will soft-remove the entity from the normal graph-memory view.")
        }
        .confirmationDialog(
            "Deactivate observation?",
            isPresented: Binding(
                get: { observationToDeactivate != nil },
                set: { if !$0 { observationToDeactivate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                guard let observation = observationToDeactivate else { return }
                Task { await deactivateObservation(id: observation.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will soft-remove the observation from the normal graph-memory view.")
        }
        .alert("Graph Memory Error", isPresented: Binding(
            get: { loadError != nil && !isLoading },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Unknown error")
        }
    }

    private func loadNode() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            node = try await api.fetchGraphMemoryNode(entityID)
            loadError = nil
        } catch {
            node = nil
            loadError = error.localizedDescription
        }
    }

    private func updateEntity(_ draft: GraphMemoryEntityPatch) async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateGraphMemoryEntity(entityID, patch: draft)
            showEntityEditor = false
            entityDraft = nil
            await loadNode()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func updateObservation(id: Int, draft: GraphMemoryObservationPatch) async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateGraphMemoryObservation(id, patch: draft)
            showObservationEditor = false
            observationDraft = nil
            editingObservationID = nil
            await loadNode()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deactivateEntity() async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            try await api.deactivateGraphMemoryEntity(entityID)
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deactivateObservation(id: Int) async {
        isRunningAction = true
        defer { isRunningAction = false }
        do {
            let api = APIClient(authManager: authManager)
            try await api.deactivateGraphMemoryObservation(id)
            observationToDeactivate = nil
            await loadNode()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct GraphMemoryRelationRow: View {
    let relation: GraphMemoryRelation
    let currentEntityID: Int

    private var otherName: String {
        relation.fromEntity.id == currentEntityID ? relation.toEntity.name : relation.fromEntity.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(relation.fromEntity.name) \(relation.displayRelationType) \(relation.toEntity.name)")
                .font(.body)
            HStack(spacing: 12) {
                Text(otherName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(Int((relation.confidence * 100).rounded()))%", systemImage: "gauge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GraphMemoryObservationRow: View {
    let observation: GraphMemoryObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(observation.content?.isEmpty == false ? observation.content! : observation.provenanceLabel)
                .font(.body)
            HStack(spacing: 12) {
                if let observedAt = observation.observedAt {
                    Label(observedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                Label("\(Int((observation.confidence * 100).rounded()))%", systemImage: "gauge")
                if observation.content == nil || observation.content?.isEmpty == true {
                    Text(observation.provenanceLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct GraphMemoryEntityEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var draft: GraphMemoryEntityPatch
    let onSave: (GraphMemoryEntityPatch) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)
                TextField("Type", text: $draft.entityType)
                TextField(
                    "Aliases (comma separated)",
                    text: Binding(
                        get: { draft.aliases.joined(separator: ", ") },
                        set: { draft = GraphMemoryEntityPatch(
                            name: draft.name,
                            entityType: draft.entityType,
                            aliases: $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                            confidence: draft.confidence
                        ) }
                    )
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence")
                    Slider(value: $draft.confidence, in: 0...1)
                    Text("\(Int((draft.confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Entity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 480, minHeight: 350, idealHeight: 420)
    }
}

private struct GraphMemoryObservationEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var draft: GraphMemoryObservationPatch
    let onSave: (GraphMemoryObservationPatch) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    "Observation",
                    text: Binding(
                        get: { draft.content ?? "" },
                        set: { draft = GraphMemoryObservationPatch(content: $0.isEmpty ? nil : $0, observedAt: draft.observedAt, confidence: draft.confidence) }
                    ),
                    axis: .vertical
                )
                DatePicker(
                    "Observed At",
                    selection: Binding(
                        get: { draft.observedAt ?? Date() },
                        set: { draft = GraphMemoryObservationPatch(content: draft.content, observedAt: $0, confidence: draft.confidence) }
                    ),
                    displayedComponents: [.date]
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence")
                    Slider(value: $draft.confidence, in: 0...1)
                    Text("\(Int((draft.confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Observation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 480, minHeight: 400, idealHeight: 480)
    }
}
