//
//  PersonaPicker.swift
//  FruitcakeAi
//
//  Persona browser used standalone or embedded inside Settings.
//

import SwiftUI

struct PersonaInfo: Codable {
    let displayName: String?
    let description: String?
    let tone: String?
    let blockedTools: [String]?
    let contentFilter: String?
}

struct PersonaPicker: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let embedded: Bool

    @State private var personas: [String: PersonaInfo] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedPersona: String = UserDefaults.standard.string(forKey: "preferred_persona") ?? "family_assistant"

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        Group {
            if embedded {
                content
                    .navigationTitle("Personas")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.large)
                    #endif
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Personas")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.large)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
                .frame(minWidth: 400, idealWidth: 500, minHeight: 400, idealHeight: 550)
            }
        }
        .task { await loadPersonas() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading personas…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView {
                Label("Could not load personas", systemImage: "person.slash")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadPersonas() } }
            }
        } else {
            personaList
        }
    }

    private var personaList: some View {
        List(personas.keys.sorted(), id: \.self) { name in
            if let info = personas[name] {
                PersonaRow(
                    name: name,
                    info: info,
                    isSelected: name == selectedPersona
                ) {
                    selectPersona(name)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func selectPersona(_ name: String) {
        selectedPersona = name
        UserDefaults.standard.set(name, forKey: "preferred_persona")
    }

    private func loadPersonas() async {
        isLoading = true
        loadError = nil
        let api = APIClient(authManager: authManager)
        do {
            personas = try await api.request("/chat/personas")
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PersonaRow: View {

    let name: String
    let info: PersonaInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var displayName: String {
        if let displayName = info.displayName, !displayName.isEmpty {
            return displayName
        }
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let description = info.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let tone = info.tone, !tone.isEmpty {
                        Badge(text: tone, icon: "waveform", color: .blue)
                    }
                    if info.contentFilter == "strict" {
                        Badge(text: "Filtered access", icon: "shield.fill", color: .green)
                    }
                    if let blocked = info.blockedTools, !blocked.isEmpty {
                        Badge(
                            text: "\(blocked.count) tools restricted",
                            icon: "minus.circle",
                            color: .orange
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct Badge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

#Preview {
    PersonaPicker()
        .environment(AuthManager())
}
