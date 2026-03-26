import SwiftUI

struct TokenUsageView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var events: [LLMUsageEventSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading && events.isEmpty {
                ProgressView("Loading token usage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, events.isEmpty {
                ContentUnavailableView {
                    Label("Could not load token usage", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { Task { await loadUsage() } }
                }
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No token usage yet",
                    systemImage: "number.circle",
                    description: Text("Recent chat and task LLM usage events will appear here.")
                )
            } else {
                List(events) { event in
                    LLMUsageEventRow(event: event)
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .navigationTitle("Token Usage")
        .task { await loadUsage() }
        .refreshable { await loadUsage() }
        .alert("Token Usage Error", isPresented: Binding(
            get: { loadError != nil && !events.isEmpty },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Unknown error")
        }
    }

    private func loadUsage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            events = try await api.fetchLLMUsageEvents(limit: 20)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct LLMUsageEventRow: View {
    let event: LLMUsageEventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(event.scopeLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(event.stageDisplay)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text(event.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(event.totalTokens) tok")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(event.costDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let createdAt = event.createdAt {
                    Text(createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        TokenUsageView()
            .environment(AuthManager())
    }
}
