import SwiftUI

struct UserAdministrationView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var users: [AdminUserProfile] = []
    @State private var editingUser: AdminUserProfile?
    @State private var showingCreate = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        SettingsPage(
            title: "Users & Access",
            subtitle: "Manage household identities and model access without opening private conversations or documents."
        ) {
            HStack {
                Text("\(users.count) account\(users.count == 1 ? "" : "s")")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Button("New User", systemImage: "person.badge.plus") { showingCreate = true }
                    .buttonStyle(.borderedProminent)
            }

            if isLoading {
                ProgressView("Loading users…")
            } else {
                ForEach(users) { user in
                    SettingsCard(
                        title: user.fullName?.isEmpty == false ? user.fullName! : user.username,
                        systemImage: user.isActive ? "person.crop.circle.fill" : "person.crop.circle.badge.xmark"
                    ) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("@\(user.username) · \(user.email)")
                                    .font(.callout)
                                HStack(spacing: 7) {
                                    SettingsCapabilityChip(label: user.role.uppercased(), enabled: user.isActive)
                                    SettingsCapabilityChip(
                                        label: user.persona.replacingOccurrences(of: "_", with: " ").uppercased(),
                                        enabled: true
                                    )
                                    if !user.isActive {
                                        SettingsCapabilityChip(label: "SUSPENDED", enabled: false)
                                    }
                                }
                                Text(user.libraryScopes.isEmpty ? "No library scopes" : user.libraryScopes.joined(separator: " · "))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            Spacer()
                            Button("Manage") { editingUser = user }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .task { await load() }
        .sheet(item: $editingUser) { user in
            UserAccessEditor(user: user) { updated in
                replace(updated)
            }
            .environment(authManager)
        }
        .sheet(isPresented: $showingCreate) {
            UserCreateSheet { created in
                users.append(created)
                users.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            }
            .environment(authManager)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await APIClient(authManager: authManager).fetchAdminUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ user: AdminUserProfile) {
        if let index = users.firstIndex(where: { $0.id == user.id }) { users[index] = user }
    }
}

private struct UserAccessEditor: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserProfile
    let didSave: (AdminUserProfile) -> Void

    @State private var role: String
    @State private var persona: String
    @State private var routing: String
    @State private var libraryScopes: String
    @State private var calendarAccess: String
    @State private var isActive: Bool
    @State private var models: [AdminUserModelAccessItem] = []
    @State private var allowed = Set<String>()
    @State private var policyMode = "deployment_default"
    @State private var isLoadingModels = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(user: AdminUserProfile, didSave: @escaping (AdminUserProfile) -> Void) {
        self.user = user
        self.didSave = didSave
        _role = State(initialValue: user.role)
        _persona = State(initialValue: user.persona)
        _routing = State(initialValue: user.chatRoutingPreference)
        _libraryScopes = State(initialValue: user.libraryScopes.joined(separator: ", "))
        _calendarAccess = State(initialValue: user.calendarAccess.joined(separator: ", "))
        _isActive = State(initialValue: user.isActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Username", value: user.username)
                    LabeledContent("Email", value: user.email)
                    Picker("Role", selection: $role) {
                        ForEach(["admin", "parent", "restricted", "guest"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Persona", text: $persona)
                    Picker("Chat routing", selection: $routing) {
                        Text("Automatic").tag("auto")
                        Text("Fast").tag("fast")
                        Text("Deep").tag("deep")
                    }
                    Toggle("Account active", isOn: $isActive)
                }
                Section("Capabilities") {
                    TextField("Library scopes · comma separated", text: $libraryScopes)
                    TextField("Calendar access · comma separated", text: $calendarAccess)
                }
                Section {
                    if isLoadingModels {
                        ProgressView("Loading model access…")
                    } else {
                        Text(policyMode == "deployment_default" ? "Using deployment defaults until saved." : "Explicit access policy")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(models) { model in
                            Toggle(isOn: Binding(
                                get: { allowed.contains(model.profileId) },
                                set: { value in
                                    if value { allowed.insert(model.profileId) } else { allowed.remove(model.profileId) }
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(model.displayName)
                                    Text(model.modelId).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!model.enabled)
                        }
                    }
                } header: { Text("Model access") }
                  footer: { Text("Changes affect new model choices and the next message in an open chat.") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Manage \(user.username)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || isLoadingModels || persona.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { await loadModels() }
        }
        .frame(minWidth: 600, minHeight: 700)
    }

    private func loadModels() async {
        do {
            let result = try await APIClient(authManager: authManager).fetchAdminUserModelAccess(user.id)
            models = result.models
            allowed = Set(result.models.filter(\.allowed).map(\.profileId))
            policyMode = result.policyMode
        } catch { errorMessage = error.localizedDescription }
        isLoadingModels = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.updateAdminUser(user.id, patch: AdminUserPatch(
                role: role,
                persona: persona.trimmingCharacters(in: .whitespacesAndNewlines),
                chatRoutingPreference: routing,
                libraryScopes: split(libraryScopes),
                calendarAccess: split(calendarAccess),
                isActive: isActive
            ))
            _ = try await api.updateAdminUserModelAccess(user.id, allowedProfileIDs: Array(allowed).sorted())
            didSave(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct UserCreateSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let didCreate: (AdminUserProfile) -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var role = "parent"
    @State private var persona = "family_assistant"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Username", text: $username)
                    TextField("Email", text: $email)
                    SecureField("Temporary password", text: $password)
                    TextField("Full name", text: $fullName)
                }
                Section("Access") {
                    Picker("Role", selection: $role) {
                        ForEach(["admin", "parent", "restricted", "guest"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Persona", text: $persona)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("New User")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(isSaving || username.isEmpty || email.isEmpty || password.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await APIClient(authManager: authManager).createAdminUser(AdminUserCreate(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullName,
                role: role,
                persona: persona,
                chatRoutingPreference: "auto",
                libraryScopes: ["family_docs"],
                calendarAccess: []
            ))
            didCreate(created)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private func split(_ value: String) -> [String] {
    value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
