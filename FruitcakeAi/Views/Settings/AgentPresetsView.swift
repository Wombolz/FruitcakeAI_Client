import SwiftUI

struct AgentPresetsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var presets: [ManagedAgentPresetSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedPreset: ManagedAgentPresetSummary?
    @State private var selectedTask: TaskSummary?

    var body: some View {
        List {
            if let loadError, !loadError.isEmpty {
                Section {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(presets) { preset in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.displayName)
                                    .font(.headline)
                                Text("\(preset.categoryLabel) • \(preset.backgroundLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(
                                get: { preset.enabled },
                                set: { newValue in
                                    Task { await toggleEnabled(preset, enabled: newValue) }
                                }
                            ))
                            .labelsHidden()
                        }

                        Text(preset.whenToUse)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label(preset.scheduleLabel, systemImage: "clock")
                            if let linkedTask = preset.linkedTask {
                                Label(linkedTask.status.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "checklist")
                            } else {
                                Label("No backing task", systemImage: "exclamationmark.triangle")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let latestRun = preset.latestRun {
                            Text("Latest run: \(latestRun.statusLabel) • \(latestRun.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Edit") {
                                selectedPreset = preset
                            }
                            .buttonStyle(.bordered)

                            Button("Open Task") {
                                Task { await openTask(preset) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(preset.linkedTask == nil)

                            Button("Run Now") {
                                Task { await runNow(preset) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(preset.linkedTask == nil)

                            Button("Recreate") {
                                Task { await recreateTask(preset) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if isLoading && presets.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Agents")
        .task { await loadPresets() }
        .sheet(item: $selectedPreset) { preset in
            ManagedAgentPresetEditorSheet(preset: preset) {
                await loadPresets()
            }
            .environment(authManager)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(
                task: task,
                onStop: { Task { await taskAction(.stop, taskID: task.id) } },
                onRun: { Task { await taskAction(.run, taskID: task.id) } },
                onReset: { Task { await taskAction(.reset, taskID: task.id) } },
                onUpdated: {
                    Task { await loadPresets() }
                }
            )
            .environment(authManager)
        }
    }

    private func loadPresets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            presets = try await api.ensureManagedAgentPresets()
                .sorted { $0.displayName < $1.displayName }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func toggleEnabled(_ preset: ManagedAgentPresetSummary, enabled: Bool) async {
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateManagedAgentPreset(
                preset.presetId,
                patch: ManagedAgentPresetUpdateRequest(enabled: enabled, autoMaintainTask: nil, schedule: nil, activeHoursStart: nil, activeHoursEnd: nil, activeHoursTz: nil, contextPaths: nil, params: nil)
            )
            await loadPresets()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func openTask(_ preset: ManagedAgentPresetSummary) async {
        guard let taskID = preset.linkedTask?.id else { return }
        do {
            let api = APIClient(authManager: authManager)
            selectedTask = try await api.fetchTask(taskID)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func runNow(_ preset: ManagedAgentPresetSummary) async {
        guard let taskID = preset.linkedTask?.id else { return }
        do {
            let api = APIClient(authManager: authManager)
            try await api.runTask(taskID)
            await loadPresets()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func recreateTask(_ preset: ManagedAgentPresetSummary) async {
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.reconcileManagedAgentPreset(preset.presetId, recreateMissing: true)
            await loadPresets()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private enum TaskAction {
        case run
        case stop
        case reset
    }

    private func taskAction(_ action: TaskAction, taskID: Int) async {
        do {
            let api = APIClient(authManager: authManager)
            switch action {
            case .run:
                try await api.runTask(taskID)
            case .stop:
                try await api.stopTask(taskID)
            case .reset:
                try await api.resetTask(taskID)
            }
            if let refreshed = try? await api.fetchTask(taskID) {
                selectedTask = refreshed
            }
            await loadPresets()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ManagedAgentPresetEditorSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let preset: ManagedAgentPresetSummary
    let onSaved: () async -> Void

    @State private var enabled: Bool
    @State private var autoMaintainTask: Bool
    @State private var schedule: String
    @State private var activeHoursStart: String
    @State private var activeHoursEnd: String
    @State private var activeHoursTz: String
    @State private var contextPathsText: String

    @State private var includedScopesText: String = ""
    @State private var staleThresholdHours: Int = 24
    @State private var autoRescanLinkedSources = false
    @State private var summaryVerbosity = "compact"

    @State private var outputPath = ""
    @State private var includedRootsText = ""
    @State private var ignoredPathsText = ""
    @State private var refreshAfterSyncOnly = false

    @State private var lookbackHours: Int = 24
    @State private var maxRuns: Int = 8
    @State private var problematicOnly = true
    @State private var emitAllClear = true

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(preset: ManagedAgentPresetSummary, onSaved: @escaping () async -> Void) {
        self.preset = preset
        self.onSaved = onSaved
        _enabled = State(initialValue: preset.enabled)
        _autoMaintainTask = State(initialValue: preset.autoMaintainTask)
        _schedule = State(initialValue: preset.schedule ?? "")
        _activeHoursStart = State(initialValue: preset.activeHoursStart ?? "")
        _activeHoursEnd = State(initialValue: preset.activeHoursEnd ?? "")
        _activeHoursTz = State(initialValue: preset.activeHoursTz ?? "")
        _contextPathsText = State(initialValue: preset.contextPaths.joined(separator: "\n"))

        let params = preset.params
        _includedScopesText = State(initialValue: params["included_scopes"]?.stringArrayValue.joined(separator: ", ") ?? "")
        _staleThresholdHours = State(initialValue: params["stale_threshold_hours"]?.intValue ?? 24)
        _autoRescanLinkedSources = State(initialValue: params["auto_rescan_linked_sources"]?.boolValue ?? false)
        _summaryVerbosity = State(initialValue: params["summary_verbosity"]?.stringValue ?? "compact")

        _outputPath = State(initialValue: params["output_path"]?.stringValue ?? "")
        _includedRootsText = State(initialValue: params["included_roots"]?.stringArrayValue.joined(separator: "\n") ?? "")
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
                Section("Preset") {
                    Toggle("Enabled", isOn: $enabled)
                    Toggle("Auto-maintain backing task", isOn: $autoMaintainTask)
                    TextField("Schedule", text: $schedule)
                    TextField("Active start (HH:MM)", text: $activeHoursStart)
                    TextField("Active end (HH:MM)", text: $activeHoursEnd)
                    TextField("Active hours timezone", text: $activeHoursTz)
                }

                Section("Context Files") {
                    TextEditor(text: $contextPathsText)
                        .frame(minHeight: 100)
                    Text("One path per line. These files are preloaded before the agent falls back to search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if preset.presetId == "document_sync_manager" {
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

                if preset.presetId == "repo_map_manager" {
                    Section("Repo Map") {
                        TextField("Output path", text: $outputPath)
                        TextField("Included roots", text: $includedRootsText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                        TextField("Ignored paths", text: $ignoredPathsText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                        Toggle("Refresh only after sync", isOn: $refreshAfterSyncOnly)
                    }
                }

                if preset.presetId == "recent_run_analyzer" {
                    Section("Recent Run Analysis") {
                        Stepper("Lookback: \(lookbackHours)h", value: $lookbackHours, in: 1...168)
                        Stepper("Max runs: \(maxRuns)", value: $maxRuns, in: 1...50)
                        Toggle("Only problematic runs", isOn: $problematicOnly)
                        Toggle("Emit all-clear summary", isOn: $emitAllClear)
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(preset.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateManagedAgentPreset(
                preset.presetId,
                patch: ManagedAgentPresetUpdateRequest(
                    enabled: enabled,
                    autoMaintainTask: autoMaintainTask,
                    schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursStart: activeHoursStart.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursEnd: activeHoursEnd.trimmingCharacters(in: .whitespacesAndNewlines),
                    activeHoursTz: activeHoursTz.trimmingCharacters(in: .whitespacesAndNewlines),
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
        switch preset.presetId {
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
                "included_roots": .array(lines(from: includedRootsText).map(StringCodable.string)),
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
            return preset.params.mapValues { $0.stringCodableValue }
        }
    }

    private func lines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func csvItems(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
