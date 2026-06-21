//
//  ChatHeaderBar.swift
//  FruitcakeAi
//
//  Persona-forward header replacing the default navigationTitle/subtitle
//  presentation: avatar, persona name + tone, model + reasoning chips,
//  and a connection/on-device indicator.
//

import SwiftUI

struct ChatHeaderBar: View {
    let personaKey: String
    let personaDisplayName: String
    let personaTone: String?
    let modelLabel: String
    let reasoningLabel: String
    let isConnected: Bool

    private var accent: Color { PersonaAccent.color(for: personaKey) }

    var body: some View {
        HStack(spacing: 12) {
            PersonaAvatar(personaKey: personaKey, displayName: personaDisplayName, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(personaDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let personaTone, !personaTone.isEmpty {
                    Text(personaTone)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim)
                }
            }

            Spacer(minLength: 12)

            ConsoleChip(text: modelLabel)
            ConsoleChip(text: "◇ \(reasoningLabel)")

            Divider().frame(height: 18)

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Theme.online : Theme.onDevice)
                    .frame(width: 7, height: 7)
                    .shadow(color: (isConnected ? Theme.online : Theme.onDevice).opacity(0.7), radius: 4)
                Text(isConnected ? "Connected" : "On-device")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.bg)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)
        .tint(accent)
    }
}

#Preview {
    VStack(spacing: 0) {
        ChatHeaderBar(
            personaKey: "family_assistant",
            personaDisplayName: "Family Assistant",
            personaTone: "Neutral · cites sources",
            modelLabel: "GPT-5.1 (Default)",
            reasoningLabel: "Automatic",
            isConnected: true
        )
        ChatHeaderBar(
            personaKey: "news_researcher",
            personaDisplayName: "News Researcher",
            personaTone: nil,
            modelLabel: "Claude Sonnet",
            reasoningLabel: "Deep",
            isConnected: false
        )
    }
    .background(Theme.bg)
}
