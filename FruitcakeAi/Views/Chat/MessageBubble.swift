//
//  MessageBubble.swift
//  FruitcakeAi
//
//  Renders a single chat message with Markdown support.
//  User messages: right-aligned, persona-accent-tinted surface.
//  Assistant messages: left-aligned console surface with accent framing.
//

import SwiftUI

struct MessageBubble: View {

    let message: CachedMessage
    var personaKey: String = ""
    var personaDisplayName: String = ""    // shown as label above assistant messages

    private var isUser: Bool { message.isUser }
    private var accent: Color { PersonaAccent.color(for: personaKey) }
    private static let timestampFormat: Date.FormatStyle =
        .dateTime.month(.abbreviated).day().hour().minute()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {

                // Role / persona label (assistant only)
                if !isUser {
                    Text(personaDisplayName.isEmpty ? "Assistant" : personaDisplayName)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 4)
                }

                bubbleContent

                metaLine

                // Timestamp + local indicator
                HStack(spacing: 4) {
                    if message.isLocal {
                        Image(systemName: "iphone")
                            .imageScale(.small)
                        Text("On-device")
                            .font(Theme.mono(10))
                    }
                    Text(message.timestamp.formatted(Self.timestampFormat))
                        .font(Theme.mono(10))
                }
                .foregroundStyle(message.isLocal ? Theme.onDevice : Theme.textFaint)
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: isUser ? 460 : 540, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            markdownText
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(accent.opacity(0.14))
                .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                  bottomTrailingRadius: 4, topTrailingRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(accent.opacity(0.30), lineWidth: 1)
                )
        } else {
            markdownText
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textMid)
                .lineSpacing(4)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(Theme.bubble)
                .overlay(alignment: .leading) {
                    accent.opacity(0.55).frame(width: 2)
                }
                .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 4,
                                  bottomTrailingRadius: 14, topTrailingRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1)
                )
        }
    }

    /// Muted source/tool line under assistant replies. Only renders when the
    /// backend has actually attached tool-call metadata to this message —
    /// never fabricated when absent.
    @ViewBuilder
    private var metaLine: some View {
        if !isUser, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            Text(toolCalls.joined(separator: " · "))
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.textFaint)
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private var markdownText: some View {
        if let attributed = try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    let userMsg = CachedMessage(role: "user", content: "What's on my calendar today?")
    let asstMsg = CachedMessage(
        role: "assistant",
        content: "You have **three events** today:\n1. 9 AM — School run\n2. 12 PM — Lunch\n3. 6 PM — Family dinner",
        toolCalls: ["calendar_read"]
    )
    return ScrollView {
        VStack(spacing: 4) {
            MessageBubble(message: userMsg, personaKey: "family_assistant")
            MessageBubble(message: asstMsg, personaKey: "family_assistant", personaDisplayName: "Family Assistant")
        }
        .padding(.vertical)
    }
    .background(Theme.bg)
}
