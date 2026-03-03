//
//  MessageBubble.swift
//  FruitcakeAi
//
//  Renders a single chat message with Markdown support.
//  User messages: right-aligned accent bubble.
//  Assistant messages: left-aligned neutral bubble with optional persona label.
//

import SwiftUI

struct MessageBubble: View {

    let message: CachedMessage
    var persona: String = ""           // shown as label above assistant messages

    private var isUser: Bool { message.isUser }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {

                // Role / persona label (assistant only)
                if !isUser {
                    Text(persona.isEmpty ? "Assistant" : persona.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                // Message content with Markdown rendering
                markdownText
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(isUser ? Color.accentColor : Color.secondary.opacity(0.12))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                            .corners(
                                topLeft: 18,
                                topRight: 18,
                                bottomLeft: isUser ? 18 : 4,
                                bottomRight: isUser ? 4 : 18
                            )
                    )

                // Timestamp + local indicator
                HStack(spacing: 4) {
                    if message.isLocal {
                        Image(systemName: "iphone")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
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

// MARK: - Asymmetric rounded corners helper

private extension Shape where Self == RoundedRectangle {
    func corners(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some Shape {
        self
    }
}

// SwiftUI doesn't have a built-in per-corner shape — use UnevenRoundedRectangle (iOS 16+)
private extension View {
    @ViewBuilder
    func clipShape(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: topLeft,
                bottomLeadingRadius: bottomLeft,
                bottomTrailingRadius: bottomRight,
                topTrailingRadius: topRight
            )
        )
    }
}

private extension RoundedRectangle {
    func corners(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeft,
            bottomLeadingRadius: bottomLeft,
            bottomTrailingRadius: bottomRight,
            topTrailingRadius: topRight
        )
    }
}

#Preview {
    let userMsg = CachedMessage(role: "user", content: "What's on my calendar today?")
    let asstMsg = CachedMessage(
        role: "assistant",
        content: "You have **three events** today:\n1. 9 AM — School run\n2. 12 PM — Lunch\n3. 6 PM — Family dinner"
    )
    return ScrollView {
        VStack(spacing: 4) {
            MessageBubble(message: userMsg)
            MessageBubble(message: asstMsg, persona: "family_assistant")
        }
        .padding(.vertical)
    }
}
