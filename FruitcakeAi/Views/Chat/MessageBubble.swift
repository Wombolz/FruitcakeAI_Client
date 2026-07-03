//
//  MessageBubble.swift
//  FruitcakeAi
//
//  Renders a single chat message with Markdown support.
//  User messages: right-aligned, persona-accent-tinted surface.
//  Assistant messages: left-aligned console surface with accent framing;
//  evidence (when present) is fused onto the bottom of the same bubble
//  rather than rendered as a detached card underneath it.
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
            .frame(maxWidth: isUser ? 460 : 560, alignment: isUser ? .trailing : .leading)

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
            // One shape fused end-to-end: prose zone on top, evidence zone
            // (when present) fused onto the bottom behind a hairline divider
            // — reads as part of the response, not a separate debug card.
            VStack(alignment: .leading, spacing: 0) {
                prose
                if let evidence {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    EvidenceSection(evidence: evidence, expanded: $evidenceExpanded, accent: accent)
                }
            }
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

    private var prose: some View {
        markdownText
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.textMid)
            .lineSpacing(4)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
    }

    /// Muted source/tool line under assistant replies. Only renders when the
    /// backend attached tool-call metadata but nothing rose to the level of
    /// "meaningful" evidence (which would otherwise be fused onto the bubble).
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
}

// MARK: - Evidence (fused bubble zone)

/// The bottom zone of the assistant bubble when evidence is present.
/// Header row uses the Tasks "console terminal" vocabulary (`)_` prompt +
/// mono label + health chip); body splits high-signal tool detail rows
/// from a demoted tier of raw tool-name tags below a hairline.
private struct EvidenceSection: View {
    let evidence: ChatEvidenceMetadata
    @Binding var expanded: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(evidence.toolDetails.enumerated()), id: \.offset) { index, detail in
                        if index > 0 {
                            Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                        }
                        EvidenceDetailRow(detail: detail, accent: accent)
                    }
                    if !evidence.toolNames.isEmpty || !lowSignalSummary.isEmpty {
                        lowSignalRow
                    }
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 10)
            }
        }
        .background(Color.black.opacity(0.22))
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .rotationEffect(expanded ? .zero : .degrees(-90))
                Text(")_")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(accent)
                Text("EVIDENCE")
                    .font(Theme.mono(10))
                    .kerning(1.6)
                    .foregroundStyle(Theme.textFaint)
                if evidence.grounded {
                    GroundedBadge()
                }
                Spacer(minLength: 8)
                if !summaryCountLabel.isEmpty {
                    Text(summaryCountLabel)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lowSignalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            HStack(alignment: .top, spacing: 6) {
                FlowChips(values: evidence.toolNames)
                Spacer(minLength: 8)
                if !lowSignalSummary.isEmpty {
                    Text(lowSignalSummary)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(.top, 11)
    }

    /// Single human count for the header ("3 sources") rather than a
    /// section-by-section readout.
    private var totalSourceCount: Int {
        if !evidence.sourceCounts.isEmpty { return evidence.sourceCounts.values.reduce(0, +) }
        return evidence.toolDetails.filter { $0.toolName == "fetch_page" }.count
    }

    private var summaryCountLabel: String {
        guard totalSourceCount > 0 else { return "" }
        return "\(totalSourceCount) source\(totalSourceCount == 1 ? "" : "s")"
    }

    private var lowSignalSummary: String {
        var parts: [String] = []
        if !evidence.toolNames.isEmpty {
            parts.append("\(evidence.toolNames.count) tool\(evidence.toolNames.count == 1 ? "" : "s")")
        }
        for key in evidence.sourceCounts.keys.sorted() {
            guard let count = evidence.sourceCounts[key], count > 0 else { continue }
            parts.append("\(count) \(key.replacingOccurrences(of: "_", with: " "))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Mirrors the task "OK" health chip (Views/Inbox/TaskRow.swift) — green,
/// mono, same radius/padding language — so evidence reads as the same
/// terminal-status vocabulary used on task cards.
private struct GroundedBadge: View {
    var body: some View {
        Text("GROUNDED")
            .font(Theme.mono(9, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.ok)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.ok.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// A single high-signal evidence row — a search action, a browsable source,
/// or a referenced document. Only the tools the mockup calls out get
/// dedicated treatment; any other tool falls back to a plain value line.
private struct EvidenceDetailRow: View {
    let detail: ChatEvidenceToolDetail
    let accent: Color

    @Environment(\.openURL) private var openURL

    private static let searchTools: Set<String> = [
        "web_search", "search_library", "search_my_feeds", "search_feeds"
    ]

    private var isSearch: Bool { Self.searchTools.contains(detail.toolName) }
    private var isFetch: Bool { detail.toolName == "fetch_page" }
    private var isDocument: Bool { detail.toolName == "summarize_document" }
    private var sourceURL: URL? { isFetch ? URL(string: detail.value) : nil }

    var body: some View {
        if let sourceURL {
            row
                .accessibilityAddTraits(.isLink)
                .accessibilityLabel(sourceURL.absoluteString)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 11) {
            iconTile
            label
            if isFetch {
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let sourceURL { openURL(sourceURL) }
        }
    }

    private var iconTile: some View {
        let symbol: String
        if isSearch {
            symbol = "magnifyingglass"
        } else if isDocument {
            symbol = "doc.text"
        } else if isFetch {
            symbol = Self.fetchIconSymbol(for: detail.sourceKind)
        } else {
            symbol = "globe"
        }
        let tint = isSearch ? accent : Theme.textMid
        let bg = isSearch ? accent.opacity(0.13) : Color.white.opacity(0.05)
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(bg, in: RoundedRectangle(cornerRadius: 6))
    }

    /// Per-source iconography beyond the generic globe, keyed off the
    /// backend's cheap URL-only `source_kind` hint (absent → globe).
    private static func fetchIconSymbol(for sourceKind: String?) -> String {
        switch sourceKind {
        case "pdf": return "doc.richtext"
        case "wiki": return "book.closed"
        default: return "globe"
        }
    }

    @ViewBuilder
    private var label: some View {
        if isSearch {
            (Text("Searched \(searchTargetLabel) for ").foregroundStyle(Theme.textMid)
                + Text("\"\(detail.value)\"").foregroundStyle(Theme.text))
                .font(.system(size: 12))
                .lineLimit(1)
        } else if isFetch, let sourceURL {
            VStack(alignment: .leading, spacing: 2) {
                if let title = detail.sourceTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(sourceURL.host ?? detail.value)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(detail.sourceTitle == nil ? accent : Theme.textMid)
                    let path = sourceURL.path
                    if !path.isEmpty, path != "/" {
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            Text(detail.value)
                .font(.system(size: 12))
                .foregroundStyle(isDocument ? Theme.text : Theme.textMid)
                .lineLimit(1)
        }
    }

    private var searchTargetLabel: String {
        switch detail.toolName {
        case "web_search": return "the web"
        case "search_library": return "your library"
        case "search_my_feeds", "search_feeds": return "your feeds"
        default: return "for"
        }
    }
}

/// Wrapping row of quiet mono tags — the demoted "everything else" tier
/// below the high-signal detail rows, deliberately quieter so the eye
/// lands on those rows first.
private struct FlowChips: View {
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunked(values, size: 3), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { value in
                        Text(value)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textMid)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                    }
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
    let groundedMsg = CachedMessage(
        role: "assistant",
        content: "September rate cut odds are trending toward **62%**, up **+0.8%** from yesterday.",
        toolCalls: ["web_search", "fetch_page"],
        evidence: ChatEvidenceMetadata(
            grounded: true,
            toolNames: ["web_search", "fetch_page"],
            sourceKinds: ["web"],
            sourceCounts: ["web": 2],
            toolDetails: [
                ChatEvidenceToolDetail(toolName: "web_search", detailKind: "query", label: "Query", value: "September rate cut odds"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://www.cmegroup.com/markets/interest-rates/fed-funds.html", sourceTitle: "CME FedWatch Tool", sourceKind: "web"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://www.reuters.com/markets/rates-bonds/fed-cut-odds", sourceKind: "web"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://en.wikipedia.org/wiki/Federal_funds_rate", sourceTitle: "Federal funds rate", sourceKind: "wiki")
            ]
        )
    )
    return ScrollView {
        VStack(spacing: 4) {
            MessageBubble(message: userMsg, personaKey: "family_assistant", evidenceExpanded: .constant(false))
            MessageBubble(message: asstMsg, personaKey: "family_assistant", personaDisplayName: "Family Assistant", evidenceExpanded: .constant(false))
            MessageBubble(message: groundedMsg, personaKey: "family_assistant", personaDisplayName: "Family Assistant", evidenceExpanded: .constant(true))
        }
        .padding(.vertical)
    }
    .background(Theme.bg)
}
