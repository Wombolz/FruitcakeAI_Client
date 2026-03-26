import SwiftUI

struct SecretsView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var secrets: [SecretSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var activeSheet: SecretEditorSheet?

    var body: some View {
        Group {
            if isLoading && secrets.isEmpty {
                ProgressView("Loading secrets…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, secrets.isEmpty {
                ContentUnavailableView {
                    Label("Could not load secrets", systemImage: "key.slash")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { Task { await loadSecrets() } }
                }
            } else if secrets.isEmpty {
                ContentUnavailableView(
                    "No secrets yet",
                    systemImage: "key",
                    description: Text("Add API keys here for authenticated integrations like N2YO.")
                )
            } else {
                List {
                    ForEach(secrets) { secret in
                        SecretRow(
                            secret: secret,
                            onEdit: { activeSheet = .edit(secret) },
                            onRotate: { activeSheet = .rotate(secret) },
                            onToggleActive: { isActive in
                                Task { await updateSecret(secret, isActive: isActive) }
                            }
                        )
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .navigationTitle("Secrets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .create
                } label: {
                    Label("Add Secret", systemImage: "plus")
                }
            }
        }
        .task { await loadSecrets() }
        .refreshable { await loadSecrets() }
        .alert("Secrets Error", isPresented: Binding(
            get: { loadError != nil && !secrets.isEmpty },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Unknown error")
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .create:
                    SecretCreateForm { name, provider, value in
                        await createSecret(name: name, provider: provider, value: value)
                    }
                case .edit(let secret):
                    SecretEditForm(secret: secret) { name, provider, isActive in
                        await saveSecret(secret, name: name, provider: provider, isActive: isActive)
                    }
                case .rotate(let secret):
                    SecretRotateForm(secret: secret) { value in
                        await rotateSecret(secret, value: value)
                    }
                }
            }
            .environment(authManager)
            .frame(minWidth: 360, idealWidth: 480, minHeight: 300, idealHeight: 400)
        }
    }

    private func loadSecrets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            secrets = try await api.fetchSecrets()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func createSecret(name: String, provider: String, value: String) async {
        do {
            let api = APIClient(authManager: authManager)
            let created = try await api.createSecret(name: name, provider: provider, value: value)
            secrets.insert(created, at: 0)
            secrets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadError = nil
            activeSheet = nil
        } catch {
            loadError = "Could not create secret: \(error.localizedDescription)"
        }
    }

    private func saveSecret(_ secret: SecretSummary, name: String, provider: String, isActive: Bool) async {
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.updateSecret(secret.id, name: name, provider: provider, isActive: isActive)
            replaceSecret(updated)
            loadError = nil
            activeSheet = nil
        } catch {
            loadError = "Could not update secret: \(error.localizedDescription)"
        }
    }

    private func updateSecret(_ secret: SecretSummary, isActive: Bool) async {
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.updateSecret(secret.id, name: secret.name, provider: secret.provider, isActive: isActive)
            replaceSecret(updated)
            loadError = nil
        } catch {
            loadError = "Could not update secret: \(error.localizedDescription)"
        }
    }

    private func rotateSecret(_ secret: SecretSummary, value: String) async {
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.rotateSecret(secret.id, value: value)
            replaceSecret(updated)
            loadError = nil
            activeSheet = nil
        } catch {
            loadError = "Could not rotate secret: \(error.localizedDescription)"
        }
    }

    private func replaceSecret(_ updated: SecretSummary) {
        if let index = secrets.firstIndex(where: { $0.id == updated.id }) {
            secrets[index] = updated
        } else {
            secrets.append(updated)
        }
        secrets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private enum SecretEditorSheet: Identifiable {
    case create
    case edit(SecretSummary)
    case rotate(SecretSummary)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let secret):
            return "edit-\(secret.id)"
        case .rotate(let secret):
            return "rotate-\(secret.id)"
        }
    }
}

private struct SecretRow: View {
    let secret: SecretSummary
    let onEdit: () -> Void
    let onRotate: () -> Void
    let onToggleActive: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(secret.name)
                        .font(.subheadline.weight(.semibold))
                    Text(secret.providerDisplay)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text(secret.maskedPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let lastUsedAt = secret.lastUsedAt {
                    Text("Last used \(lastUsedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            Menu {
                Button("Edit", action: onEdit)
                Button("Rotate", action: onRotate)
                Button(secret.isActive ? "Disable" : "Enable") {
                    onToggleActive(!secret.isActive)
                }
            } label: {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(secret.isActive ? "Active" : "Disabled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secret.isActive ? .green : .secondary)
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct SecretCreateForm: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var provider = ""
    @State private var value = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSave: (String, String, String) async -> Void

    var body: some View {
        Form {
            Section("Secret") {
                TextField("Name", text: $name)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                TextField("Provider", text: $provider)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Value", text: $value)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Secret")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.isEmpty)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = value
        guard !trimmedName.isEmpty, !rawValue.isEmpty else {
            errorMessage = "Name and value are required."
            return
        }
        await onSave(trimmedName, trimmedProvider, rawValue)
    }
}

private struct SecretEditForm: View {
    @Environment(\.dismiss) private var dismiss

    let secret: SecretSummary
    let onSave: (String, String, Bool) async -> Void

    @State private var name = ""
    @State private var provider = ""
    @State private var isActive = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Secret") {
                TextField("Name", text: $name)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                TextField("Provider", text: $provider)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Toggle("Active", isOn: $isActive)
                LabeledContent("Stored Value", value: secret.maskedPreview)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Secret")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            name = secret.name
            provider = secret.provider
            isActive = secret.isActive
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }
        await onSave(trimmedName, provider.trimmingCharacters(in: .whitespacesAndNewlines), isActive)
    }
}

private struct SecretRotateForm: View {
    @Environment(\.dismiss) private var dismiss

    let secret: SecretSummary
    let onSave: (String) async -> Void

    @State private var value = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Rotate Value") {
                LabeledContent("Secret", value: secret.name)
                SecureField("New Value", text: $value)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Rotate Secret")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || value.isEmpty)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard !value.isEmpty else {
            errorMessage = "Value is required."
            return
        }
        await onSave(value)
    }
}

#Preview {
    NavigationStack {
        SecretsView()
            .environment(AuthManager())
    }
}
