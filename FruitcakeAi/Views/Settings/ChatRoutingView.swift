import SwiftUI

struct ChatRoutingView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var selectedPreference: String = "auto"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $selectedPreference) {
                    Text("Automatic").tag("auto")
                    Text("Fast").tag("fast")
                    Text("Deep").tag("deep")
                }
                .pickerStyle(.inline)
                .disabled(isSaving)

                if isSaving {
                    ProgressView("Saving…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Chat Routing")
            } footer: {
                Text(footerText)
            }

            Section {
                LabeledContent("Selected Mode", value: modeLabel(for: selectedPreference))
            } header: {
                Text("Current Behavior")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Routing")
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .onAppear {
            selectedPreference = authManager.currentUser?.chatRoutingPreference ?? "auto"
        }
        .onChange(of: authManager.currentUser?.chatRoutingPreference) { _, newValue in
            guard let newValue else { return }
            selectedPreference = newValue
        }
        .onChange(of: selectedPreference) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Task { await savePreference(newValue) }
        }
    }

    private var footerText: String {
        switch selectedPreference {
        case "fast":
            return "Fast keeps chat on the simpler path for quicker responses. It may do less deep tool orchestration."
        case "deep":
            return "Deep forces orchestrated chat for stronger multi-step reasoning and tool use. It may take longer and use more tokens."
        default:
            return "Automatic chooses between fast and deep behavior based on the request."
        }
    }

    private func modeLabel(for value: String) -> String {
        switch value {
        case "fast": return "Fast"
        case "deep": return "Deep"
        default: return "Automatic"
        }
    }

    private func savePreference(_ preference: String) async {
        guard authManager.currentUser != nil else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let api = APIClient(authManager: authManager)
            try await api.updateChatRoutingPreference(preference)
            try await authManager.refreshCurrentUser()
        } catch {
            errorMessage = "Could not save routing preference: \(error.localizedDescription)"
            selectedPreference = authManager.currentUser?.chatRoutingPreference ?? "auto"
        }
    }
}

#Preview {
    ChatRoutingView()
        .environment(AuthManager())
}
