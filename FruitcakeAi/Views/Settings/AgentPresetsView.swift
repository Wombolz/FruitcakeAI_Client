import SwiftUI
import UniformTypeIdentifiers

private struct AgentSettingsModelOption: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String
    let label: String
    let isDefaultChat: Bool
    let isDefaultTaskSmall: Bool
    let isDefaultTaskLarge: Bool

    var displayLabel: String {
        if isDefaultTaskSmall || isDefaultTaskLarge {
            return "\(label) (Default task)"
        }
        return label
    }

    var providerLabel: String {
        provider.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct AgentSettingsModelListResponse: Decodable {
    let models: [AgentSettingsModelOption]
}

struct AgentPresetsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var instances: [AgentInstanceSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedInstance: AgentInstanceSummary?
    @State private var selectedTask: TaskSummary?
    @State private var showingCreateSheet = false
    @State private var isVisible = false

    var body: some View {
        List {
            if let loadError, !loadError.isEmpty {
                Section {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(instances) { instance in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(instance.displayName)
                                    .font(.headline)
                                Text("\(instance.categoryLabel) • \(instance.backgroundLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(
                                get: { instance.enabled },
                                set: { newValue in Task { await toggleEnabled(instance, enabled: newValue) } }
                            ))
                            .labelsHidden()
                        }

                        Text(instance.whenToUse)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label(instance.scheduleLabel, systemImage: "clock")
                            if let linkedTask = instance.linkedTask {
                                Label(linkedTask.status.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "checklist")
                            } else {
                                Label("No backing task", systemImage: "exclamationmark.triangle")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let latestRun = instance.latestRun {
                            Text("Latest run: \(latestRun.statusLabel) • \(latestRun.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Edit") { selectedInstance = instance }
                                .buttonStyle(.bordered)
                            Button("Open Task") { Task { await openTask(instance) } }
                                .buttonStyle(.bordered)
                                .disabled(instance.linkedTask == nil)
                            Button("Run Now") { Task { await runNow(instance) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(instance.linkedTask == nil)
                            Button("Recreate") { Task { await recreateTask(instance) } }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if isLoading && instances.isEmpty { ProgressView() }
        }
        .refreshable { await loadInstances() }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreateSheet = true } label: {
                    Label("New Agent", systemImage: "plus")
                }
            }
        }
        .task { await loadInstances() }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await loadInstances()
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .sheet(item: $selectedInstance) { instance in
            AgentInstanceEditorSheet(instance: instance) {
                await loadInstances()
            }
            .environment(authManager)
        }
        .sheet(isPresented: $showingCreateSheet) {
            AgentInstanceCreateSheet {
                await loadInstances()
            }
            .environment(authManager)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(
                task: task,
                onStop: { Task { await taskAction(.stop, taskID: task.id) } },
                onRun: { Task { await taskAction(.run, taskID: task.id) } },
                onReset: { Task { await taskAction(.reset, taskID: task.id) } },
                onUpdated: { Task { await loadInstances() } }
            )
            .environment(authManager)
        }
    }

    private func loadInstances() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            // Try ensure-defaults first; fall back to plain GET if the backend 500s
            let fetched: [AgentInstanceSummary]
            do {
                fetched = try await api.ensureAgentInstances()
            } catch {
                fetched = try await api.fetchAgentInstances()
            }
            instances = fetched.sorted { $0.displayName < $1.displayName }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func toggleEnabled(_ instance: AgentInstanceSummary, enabled: Bool) async {
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateAgentInstance(
                instance.id,
                patch: AgentInstanceUpdateRequest(
                    displayName: nil, enabled: enabled, autoMaintainTask: nil, schedule: nil,
                    activeHoursStart: nil, activeHoursEnd: nil, activeHoursTz: nil, llmModelOverride: nil, contextPaths: nil, params: nil
                )
            )
            await loadInstances()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func openTask(_ instance: AgentInstanceSummary) async {
        guard let taskID = instance.linkedTask?.id else { return }
        do {
            let api = APIClient(authManager: authManager)
            selectedTask = try await api.fetchTask(taskID)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func runNow(_ instance: AgentInstanceSummary) async {
        guard let taskID = instance.linkedTask?.id else { return }
        do {
            let api = APIClient(authManager: authManager)
            try await api.runTask(taskID)
            await loadInstances()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func recreateTask(_ instance: AgentInstanceSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.reconcileAgentInstance(instance.id, recreateMissing: true)
            await loadInstances()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private enum TaskAction { case run, stop, reset }

    private func taskAction(_ action: TaskAction, taskID: Int) async {
        do {
            let api = APIClient(authManager: authManager)
            switch action {
            case .run: try await api.runTask(taskID)
            case .stop: try await api.stopTask(taskID)
            case .reset: try await api.resetTask(taskID)
            }
            if let refreshed = try? await api.fetchTask(taskID) { selectedTask = refreshed }
            await loadInstances()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct AgentInstanceEditorSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let instance: AgentInstanceSummary
    let onSaved: () async -> Void

    @State private var displayName: String
    @State private var enabled: Bool
    @State private var autoMaintainTask: Bool
    @State private var schedule: String
    @State private var activeHoursStart: String
    @State private var activeHoursEnd: String
    @State private var activeHoursTz: String
    @State private var contextPathsText: String
    @State private var availableModels: [AgentSettingsModelOption] = []
    @State private var selectedModelOverride: String

    @State private var includedScopesText: String = ""
    @State private var staleThresholdHours: Int = 24
    @State private var autoRescanLinkedSources = false
    @State private var summaryVerbosity = "compact"

    @State private var outputPath = ""
    @State private var includedRoots: [String] = []
    @State private var ignoredPathsText = ""
    @State private var refreshAfterSyncOnly = false
    @State private var showIncludedRootPicker = false

    @State private var lookbackHours: Int = 24
    @State private var maxRuns: Int = 8
    @State private var problematicOnly = true
    @State private var emitAllClear = true

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(instance: AgentInstanceSummary, onSaved: @escaping () async -> Void) {
        self.instance = instance
        self.onSaved = onSaved
        _displayName = State(initialValue: instance.displayName)
        _enabled = State(initialValue: instance.enabled)
        _autoMaintainTask = State(initialValue: instance.autoMaintainTask)
        _schedule = State(initialValue: instance.schedule ?? "")
        _activeHoursStart = State(initialValue: instance.activeHoursStart ?? "")
        _activeHoursEnd = State(initialValue: instance.activeHoursEnd ?? "")
        _activeHoursTz = State(initialValue: instance.activeHoursTz ?? "")
        _contextPathsText = State(initialValue: instance.contextPaths.joined(separator: "\n"))
        _selectedModelOverride = State(initialValue: instance.llmModelOverride ?? "")

        let params = instance.params
        _includedScopesText = State(initialValue: params["included_scopes"]?.stringArrayValue.joined(separator: ", ") ?? "")
        _staleThresholdHours = State(initialValue: params["stale_threshold_hours"]?.intValue ?? 24)
        _autoRescanLinkedSources = State(initialValue: params["auto_rescan_linked_sources"]?.boolValue ?? false)
        _summaryVerbosity = State(initialValue: params["summary_verbosity"]?.stringValue ?? "compact")
        _outputPath = State(initialValue: params["output_path"]?.stringValue ?? "")
        _includedRoots = State(initialValue: params["included_roots"]?.stringArrayValue ?? [])
        _ignoredPathsText = State(initialValue: params["ignored_paths"]?.stringArrayValue.joined(separator: "\n") ?? "")
        _refreshAfterSyncOnly = State(initialValue: params["refresh_after_sync_only"]?.boolValue ?? false)
        _lookbackHours = State(initialValue: params["lookback_hours"]?.intValue ?? 24)
        _maxRuns = State(initialValue: params["max_runs"]?.intValue ?? 8)
        _problematicOnly = State(initialValue: params["problematic_only"]?.boolValue ?? true)
        _emitAllClear = State(initialValue: params["emit_all_clear"]?.boolValue ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instance") {
                    TextField("Name", text: $displayName)
                    Toggle("Enabled", isOn: $enabled)
                    Toggle("Auto-maintain backing task", isOn: $autoMaintainTask)
                    TextField("Schedule", text: $schedule)
                    TextField("Active start (HH:MM)", text: $activeHoursStart)
                    TextField("Active end (HH:MM)", text: $activeHoursEnd)
                    TextField("Active hours timezone", text: $activeHoursTz)
                }

                Section {
                    Picker("LLM", selection: $selectedModelOverride) {
                        Text("Automatic").tag("")
                        ForEach(availableModels) { model in
                            Text("\(model.providerLabel) · \(model.displayLabel)").tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Model")
                } footer: {
                    Text("Choose a default model override for this agent instance's backing task.")
                }

                instanceFields

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(instance.displayName)
            .task { await loadModels() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .fileImporter(
            isPresented: $showIncludedRootPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleIncludedRootResult(result)
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 520, idealHeight: 680)
    }

    @ViewBuilder
    private var instanceFields: some View {
        Section("Context Files") {
            TextEditor(text: $contextPathsText)
                .frame(minHeight: 80, maxHeight: 140)
                .font(.system(.caption, design: .monospaced))
            Text("One path per line. These files are preloaded before the agent falls back to search.")
                .font(.caption).foregroundStyle(.secondary)
        }

        if instance.presetId == "document_sync_manager" {
            Section("Document Sync") {
                TextField("Included scopes", text: $includedScopesText)
                Stepper("Stale threshold: \(staleThresholdHours)h", value: $staleThresholdHours, in: 1...168)
                Toggle("Auto-rescan linked sources", isOn: $autoRescanLinkedSources)
                Picker("Summary verbosity", selection: $summaryVerbosity) {
                    Text("Compact").tag("compact")
                    Text("Detailed").tag("detailed")
                }
            }
        }

        if instance.presetId == "repo_map_manager" {
            Section {
                TextField("Output path", text: $outputPath)

                Button {
                    showIncludedRootPicker = true
                } label: {
                    Label(includedRoots.isEmpty ? "Choose Repo Roots" : "Add Repo Roots", systemImage: "folder.badge.plus")
                }

                if !includedRoots.isEmpty {
                    ForEach(includedRoots, id: \.self) { root in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(root)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                removeIncludedRoot(root)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Ignored paths", text: $ignoredPathsText, axis: .vertical).lineLimit(3, reservesSpace: true)
                Toggle("Refresh only after sync", isOn: $refreshAfterSyncOnly)
            } header: {
                Text("Repo Map")
            } footer: {
                Text("Folder access still depends on the current approved-roots security configuration.")
            }
        }

        if instance.presetId == "recent_run_analyzer" {
            Section("Recent Run Analysis") {
                Stepper("Lookback: \(lookbackHours)h", value: $lookbackHours, in: 1...168)
                Stepper("Max runs: \(maxRuns)", value: $maxRuns, in: 1...50)
                Toggle("Only problematic runs", isOn: $problematicOnly)
                Toggle("Emit all-clear summary", isOn: $emitAllClear)
            }
        }
    }

    private func loadModels() async {
        do {
            let api = APIClient(authManager: authManager)
            let response: AgentSettingsModelListResponse = try await api.request("/llm/models")
            availableModels = response.models
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleIncludedRootResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            mergeIncludedRoots(urls.map(\.path))
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func mergeIncludedRoots(_ roots: [String]) {
        var merged = includedRoots
        for root in roots where !merged.contains(root) {
            merged.append(root)
        }
        includedRoots = merged.sorted()
    }

    private func removeIncludedRoot(_ root: String) {
        includedRoots.removeAll { $0 == root }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateAgentInstance(
                instance.id,
                patch: AgentInstanceUpdateRequest(
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    enabled: enabled,
                    autoMaintainTask: autoMaintainTask,
                    schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursStart: activeHoursStart.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursEnd: activeHoursEnd.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursTz: activeHoursTz.trimmingCharacters(in: .whitespacesAndNewlines),
                    llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
                    contextPaths: lines(from: contextPathsText),
                    params: buildParams()
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildParams() -> [String: StringCodable] {
        switch instance.presetId {
        case "document_sync_manager":
            return [
                "included_scopes": .array(csvItems(from: includedScopesText).map(StringCodable.string)),
                "stale_threshold_hours": .int(staleThresholdHours),
                "auto_rescan_linked_sources": .bool(autoRescanLinkedSources),
                "summary_verbosity": .string(summaryVerbosity),
            ]
        case "repo_map_manager":
            return [
                "output_path": .string(outputPath.trimmingCharacters(in: .whitespacesAndNewlines)),
                "included_roots": .array(includedRoots.map(StringCodable.string)),
                "ignored_paths": .array(lines(from: ignoredPathsText).map(StringCodable.string)),
                "refresh_after_sync_only": .bool(refreshAfterSyncOnly),
            ]
        case "recent_run_analyzer":
            return [
                "lookback_hours": .int(lookbackHours),
                "max_runs": .int(maxRuns),
                "problematic_only": .bool(problematicOnly),
                "emit_all_clear": .bool(emitAllClear),
            ]
        default:
            return instance.params.mapValues { $0.stringCodableValue }
        }
    }
}

private struct AgentInstanceCreateSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let onCreated: () async -> Void

    @State private var categories: [AgentPresetCategoryGroup] = []
    @State private var selectedPresetID: String = ""
    @State private var displayName: String = ""
    @State private var schedule: String = ""
    @State private var activeHoursTz: String = ""
    @State private var contextPaths: [String] = []
    @State private var showContextFilePicker = false
    @State private var outputPath = ""
    @State private var includedRoots: [String] = []
    @State private var ignoredPathsText = ""
    @State private var refreshAfterSyncOnly = false
    @State private var showIncludedRootPicker = false
    @State private var availableModels: [AgentSettingsModelOption] = []
    @State private var selectedModelOverride = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    Picker("Agent Type", selection: $selectedPresetID) {
                        ForEach(categories) { category in
                            Section(category.displayName) {
                                ForEach(category.presets) { preset in
                                    Text(preset.displayName).tag(preset.id)
                                }
                            }
                        }
                    }

                    if let preset = selectedPreset {
                        Text(preset.whenToUse)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                        Text(preset.backgroundLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Instance") {
                    TextField("Name", text: $displayName)
                    TextField("Schedule", text: $schedule)
                    TextField("Active hours timezone", text: $activeHoursTz)
                }

                Section {
                    Picker("LLM", selection: $selectedModelOverride) {
                        Text("Automatic").tag("")
                        ForEach(availableModels) { model in
                            Text("\(model.providerLabel) · \(model.displayLabel)").tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Model")
                } footer: {
                    Text("Choose a default model override for this agent instance's backing task.")
                }

                presetSpecificCreateFields

                Section {
                    Button {
                        showContextFilePicker = true
                    } label: {
                        Label(contextPaths.isEmpty ? "Choose Context Files" : "Add Context Files", systemImage: "doc.badge.plus")
                    }

                    if !contextPaths.isEmpty {
                        ForEach(contextPaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(role: .destructive) {
                                    removeContextPath(path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Context Files")
                } footer: {
                    Text("Selected context files are preloaded before the agent falls back to search.")
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Agent")
            .task {
                await loadCategories()
                await loadModels()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(isSaving || selectedPresetID.isEmpty || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .fileImporter(
            isPresented: $showContextFilePicker,
            allowedContentTypes: Self.contextFileTypes,
            allowsMultipleSelection: true
        ) { result in
            handleContextFileResult(result)
        }
        .fileImporter(
            isPresented: $showIncludedRootPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleIncludedRootResult(result)
        }
        .frame(minWidth: 460, idealWidth: 620, minHeight: 500, idealHeight: 620)
    }

    @ViewBuilder
    private var presetSpecificCreateFields: some View {
        if selectedPresetID == "repo_map_manager" {
            Section {
                TextField("Output path", text: $outputPath)

                Button {
                    showIncludedRootPicker = true
                } label: {
                    Label(includedRoots.isEmpty ? "Choose Repo Roots" : "Add Repo Roots", systemImage: "folder.badge.plus")
                }

                if !includedRoots.isEmpty {
                    ForEach(includedRoots, id: \.self) { root in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(root)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                removeIncludedRoot(root)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Ignored paths", text: $ignoredPathsText, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                Toggle("Refresh only after sync", isOn: $refreshAfterSyncOnly)
            } header: {
                Text("Repo Map")
            } footer: {
                Text("Folder access still depends on the current approved-roots security configuration.")
            }
        }
    }

    private var selectedPreset: AgentPresetOption? {
        categories.flatMap(\.presets).first(where: { $0.id == selectedPresetID })
    }

    private func loadCategories() async {
        do {
            let api = APIClient(authManager: authManager)
            let response = try await api.fetchAgentPresetCategories()
            categories = response.categories
            if selectedPresetID.isEmpty {
                selectedPresetID = categories.flatMap(\.presets).first?.id ?? ""
            }
            if displayName.isEmpty, let preset = categories.flatMap(\.presets).first(where: { $0.id == selectedPresetID }) {
                displayName = preset.displayName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadModels() async {
        do {
            let api = APIClient(authManager: authManager)
            let response: AgentSettingsModelListResponse = try await api.request("/llm/models")
            availableModels = response.models
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var contextFileTypes: [UTType] {
        [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "txt") ?? .plainText,
            UTType(filenameExtension: "py") ?? .sourceCode,
            UTType(filenameExtension: "swift") ?? .sourceCode,
            UTType(filenameExtension: "json") ?? .json,
            UTType(filenameExtension: "yaml") ?? .data,
            UTType(filenameExtension: "yml") ?? .data,
            .plainText,
            .sourceCode,
            .data,
        ]
    }

    private func handleContextFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let mapped = urls.map(\.path)
            var merged = contextPaths
            for path in mapped where !merged.contains(path) {
                merged.append(path)
            }
            contextPaths = merged.sorted()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func removeContextPath(_ path: String) {
        contextPaths.removeAll { $0 == path }
    }

    private func handleIncludedRootResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            mergeIncludedRoots(urls.map(\.path))
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func mergeIncludedRoots(_ roots: [String]) {
        var merged = includedRoots
        for root in roots where !merged.contains(root) {
            merged.append(root)
        }
        includedRoots = merged.sorted()
    }

    private func removeIncludedRoot(_ root: String) {
        includedRoots.removeAll { $0 == root }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.createAgentInstance(
                AgentInstanceCreateRequest(
                    presetId: selectedPresetID,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    enabled: true,
                    autoMaintainTask: true,
                    schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursStart: nil,
                    activeHoursEnd: nil,
                    activeHoursTz: activeHoursTz.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : activeHoursTz.trimmingCharacters(in: .whitespacesAndNewlines),
                    llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
                    contextPaths: contextPaths.isEmpty ? nil : contextPaths,
                    params: buildCreateParams()
                )
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildCreateParams() -> [String: StringCodable]? {
        switch selectedPresetID {
        case "repo_map_manager":
            return [
                "output_path": .string(outputPath.trimmingCharacters(in: .whitespacesAndNewlines)),
                "included_roots": .array(includedRoots.map(StringCodable.string)),
                "ignored_paths": .array(lines(from: ignoredPathsText).map(StringCodable.string)),
                "refresh_after_sync_only": .bool(refreshAfterSyncOnly),
            ]
        default:
            return nil
        }
    }
}

private func lines(from text: String) -> [String] {
    text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

private func csvItems(from text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
