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
    @Binding var evidenceExpanded: Bool

    private var isUser: Bool { message.isUser }
    private var accent: Color { PersonaAccent.color(for: personaKey) }
    private var evidence: ChatEvidenceMetadata? {
        guard let evidence = message.evidence, evidence.isMeaningful else { return nil }
        return evidence
    }
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

                evidenceBlock

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
        if !isUser, evidence == nil, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
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

    @ViewBuilder
    private var evidenceBlock: some View {
        if !isUser, let evidence {
            DisclosureGroup(isExpanded: $evidenceExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if !evidence.toolDetails.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.textFaint)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(evidence.toolDetails, id: \.self) { detail in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(detail.label)
                                                .font(Theme.mono(10))
                                                .foregroundStyle(Theme.textFaint)
                                            Text(detail.toolName.replacingOccurrences(of: "_", with: " "))
                                                .font(Theme.mono(10))
                                                .foregroundStyle(Theme.textDim)
                                        }
                                        Text(detail.value)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.textMid)
                                            .textSelection(.enabled)
                                            .lineLimit(3)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Theme.bg.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.stroke, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    if !evidence.sourceKinds.isEmpty {
                        evidenceSection(title: "Sources", values: evidence.sourceKinds.map(sourceLabel))
                    }
                    if !evidence.toolNames.isEmpty {
                        evidenceSection(title: "Tools", values: evidence.toolNames)
                    }
                    if !evidence.sourceCounts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Grounding")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.textFaint)
                            HStack(spacing: 8) {
                                ForEach(evidence.sourceCounts.keys.sorted(), id: \.self) { key in
                                    Text("\(sourceLabel(key)) \(evidence.sourceCounts[key] ?? 0)")
                                        .font(Theme.mono(10))
                                        .foregroundStyle(Theme.textDim)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.bg.opacity(0.55), in: Capsule())
                                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: evidence.grounded ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(evidenceSummaryLine(evidence))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textDim)
                    Spacer(minLength: 8)
                }
            }
            .tint(Theme.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func evidenceSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.textFaint)
            FlexibleChipRow(values: values)
        }
    }

    private func evidenceSummaryLine(_ evidence: ChatEvidenceMetadata) -> String {
        var parts: [String] = []
        if evidence.grounded {
            parts.append("Grounded")
        }
        if !evidence.sourceKinds.isEmpty {
            parts.append(evidence.sourceKinds.map(sourceLabel).joined(separator: " + "))
        }
        if !evidence.toolNames.isEmpty {
            parts.append("\(evidence.toolNames.count) tool\(evidence.toolNames.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Evidence" : parts.joined(separator: " · ")
    }

    private func sourceLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct FlexibleChipRow: View {
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunked(values, size: 3), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { value in
                        Text(value)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.bg.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ values: [String], size: Int) -> [[String]] {
        stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<min($0 + size, values.count)])
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
            MessageBubble(message: userMsg, personaKey: "family_assistant", evidenceExpanded: .constant(false))
            MessageBubble(message: asstMsg, personaKey: "family_assistant", personaDisplayName: "Family Assistant", evidenceExpanded: .constant(false))
        }
        .padding(.vertical)
    }
    .background(Theme.bg)
}
