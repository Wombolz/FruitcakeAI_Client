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
#if os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#else
import UIKit
private typealias PlatformImage = UIImage
#endif

struct ChatThreadMessage: Identifiable, Hashable {
    let id: UUID
    var serverMessageId: Int?
    var role: String
    var content: String
    var timestamp: Date
    var toolCalls: [String]?
    var isLocal: Bool
    var recalledMemoryIds: [Int]?
    var taskDraft: TaskDraft?
    var taskDraftStatus: String?
    var createdTaskId: Int?
    var evidence: ChatEvidenceMetadata?
    var contentBlocks: [ChatContentBlock]
    var artifacts: [ChatArtifactEnvelope]
    var activity: [ChatActivityItem]

    init(_ cached: CachedMessage) {
        self.id = cached.id
        self.serverMessageId = cached.serverMessageId
        self.role = cached.role
        self.content = cached.content
        self.timestamp = cached.timestamp
        self.toolCalls = cached.toolCalls
        self.isLocal = cached.isLocal
        self.recalledMemoryIds = cached.recalledMemoryIds
        self.taskDraft = cached.taskDraft
        self.taskDraftStatus = cached.taskDraftStatus
        self.createdTaskId = cached.createdTaskId
        self.evidence = cached.evidence
        self.contentBlocks = cached.contentBlocks
        self.artifacts = cached.artifacts
        self.activity = cached.activity
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}

// Keeps assistant prose and generated workspace images in the order supplied
// by the response. Unreferenced artifacts remain available as a fallback.
private enum ChatRichContentBlock: Hashable {
    case text(String)
    case image(ChatImageArtifact)
    case structured(ChatContentBlock)
}

private enum ChatRichContentParser {
    private struct Candidate {
        let range: Range<String.Index>
        let block: ChatRichContentBlock
    }

    static func blocks(
        content: String,
        artifacts: [ChatImageArtifact],
        structuredBlocks: [ChatContentBlock]
    ) -> [ChatRichContentBlock] {
        var candidates: [Candidate] = []
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in expression.matches(in: content, range: range) {
                guard let fullRange = Range(match.range, in: content),
                      let targetRange = Range(match.range(at: 2), in: content),
                      let artifact = matchArtifact(target: String(content[targetRange]), artifacts: artifacts)
                else { continue }
                candidates.append(Candidate(range: fullRange, block: .image(artifact)))
            }
        }

        for block in structuredBlocks where !block.sourceMarkdown.isEmpty {
            guard let tableRange = content.range(of: block.sourceMarkdown) else { continue }
            guard block.kind != nil else { continue }
            candidates.append(Candidate(range: tableRange, block: .structured(block)))
        }

        candidates.sort { lhs, rhs in
            if lhs.range.lowerBound == rhs.range.lowerBound {
                return lhs.range.upperBound < rhs.range.upperBound
            }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }

        var blocks: [ChatRichContentBlock] = []
        var cursor = content.startIndex
        var consumedPaths = Set<String>()

        for candidate in candidates where candidate.range.lowerBound >= cursor {
            let before = String(content[cursor..<candidate.range.lowerBound])
            if !before.isEmpty { blocks.append(.text(before)) }
            blocks.append(candidate.block)
            if case .image(let artifact) = candidate.block {
                consumedPaths.insert(artifact.id)
            }
            cursor = candidate.range.upperBound
        }

        if cursor < content.endIndex {
            blocks.append(.text(String(content[cursor...])))
        }
        if blocks.isEmpty { blocks.append(.text(content)) }

        // Older responses may expose artifacts only in metadata. Preserve
        // those images rather than dropping them when no inline marker exists.
        for artifact in artifacts where !consumedPaths.contains(artifact.id) {
            blocks.append(.image(artifact))
        }
        return blocks
    }

    private static func matchArtifact(target: String, artifacts: [ChatImageArtifact]) -> ChatImageArtifact? {
        let decodedTarget = target.removingPercentEncoding ?? target
        let targetURL = URL(string: decodedTarget)
        let targetPath: String
        if let queryPath = URLComponents(string: decodedTarget)?.queryItems?.first(where: { $0.name == "path" })?.value {
            targetPath = queryPath
        } else {
            targetPath = targetURL?.path ?? decodedTarget
        }
        let targetName = URL(fileURLWithPath: targetPath).lastPathComponent

        return artifacts.first { artifact in
            guard !artifact.path.isEmpty else { return false }
            let artifactPath = artifact.path.removingPercentEncoding ?? artifact.path
            let artifactName = URL(fileURLWithPath: artifactPath).lastPathComponent
            return decodedTarget == artifactPath
                || targetPath == artifactPath
                || targetName == artifactName
                || targetPath.hasSuffix("/\(artifactPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        }
    }
}

struct MessageBubble: View {

    let message: ChatThreadMessage
    var personaKey: String = ""
    var personaDisplayName: String = ""    // shown as label above assistant messages
    @Binding var evidenceExpanded: Bool
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)? = nil
    var onOpenAppArtifact: ((ChatArtifactEnvelope) -> Void)? = nil

    private var isUser: Bool { message.isUser }
    private var accent: Color { PersonaAccent.color(for: personaKey) }
    private var evidence: ChatEvidenceMetadata? {
        guard let evidence = message.evidence, evidence.isMeaningful else { return nil }
        return evidence
    }

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
                    MessageTimestamp(date: message.timestamp)
                }
                .foregroundStyle(message.isLocal ? Theme.onDevice : Theme.textFaint)
                .padding(.horizontal, 4)
            }
            .frame(
                maxWidth: isUser ? Theme.chatUserMaxWidth : Theme.chatAssistantMaxWidth,
                alignment: isUser ? .trailing : .leading
            )

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            markdownText(text: message.content)
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
                // Interactive apps are the primary response surface. Put them
                // ahead of model-generated fallback prose/tables so they do
                // not appear missing below a long synthesized answer.
                ForEach(Array(interactiveArtifacts.enumerated()), id: \.offset) { _, artifact in
                    ChatArtifactBlockView(
                        artifact: artifact,
                        accent: accent,
                        onOpenMCPApp: onOpenAppArtifact
                    )
                }
                ForEach(Array(richContentBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        prose(text: text)
                    case .image(let artifact):
                        ChatImageAttachmentSection(artifacts: [artifact], accent: accent, messageID: message.serverMessageId, allArtifacts: imageArtifacts)
                    case .structured(let block):
                        ChatStructuredContentBlockView(
                            block: block,
                            accent: accent,
                            fallbackSources: timelineFallbackSources,
                            onContextHandback: onContextHandback
                        )
                    }
                }
                ForEach(Array(supplementalArtifacts.enumerated()), id: \.offset) { _, artifact in
                    ChatArtifactBlockView(artifact: artifact, accent: accent)
                }
                if let evidence {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    EvidenceSection(
                        evidence: evidence,
                        activity: message.activity,
                        expanded: $evidenceExpanded,
                        accent: accent
                    )
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

    private func prose(text: String) -> some View {
        markdownText(text: text)
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.textMid)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
    }

    private var imageArtifacts: [ChatImageArtifact] {
        evidence?.imageArtifacts ?? []
    }

    private var timelineFallbackSources: [ChatNewsSource] {
        var seen = Set<String>()
        return (evidence?.citations ?? []).compactMap { citation in
            guard let url = citation.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty,
                  seen.insert(url).inserted
            else { return nil }
            return ChatNewsSource(label: citation.displayTitle, url: url)
        }
    }

    private var richContentBlocks: [ChatRichContentBlock] {
        ChatRichContentParser.blocks(
            content: message.content,
            artifacts: imageArtifacts,
            structuredBlocks: message.contentBlocks
        )
    }

    private var interactiveArtifacts: [ChatArtifactEnvelope] {
        message.artifacts.filter { $0.type == "core.mcp_app" }
    }

    private var supplementalArtifacts: [ChatArtifactEnvelope] {
        message.artifacts.filter { $0.type != "core.mcp_app" }
    }

    /// Muted source/tool line under assistant replies. Only renders when the
    /// backend attached tool-call metadata but nothing rose to the level of
    /// "meaningful" evidence (which would otherwise be fused onto the bubble).
    /// Also carries the memory-recall chip: what the assistant remembered
    /// going into this turn, kept at the same muted weight as tool names.
    @ViewBuilder
    private var metaLine: some View {
        let recalledCount = (!isUser ? message.recalledMemoryIds?.count : nil) ?? 0
        let showToolLine = !isUser && evidence == nil && !(message.toolCalls ?? []).isEmpty
        if showToolLine || recalledCount > 0 {
            HStack(spacing: 8) {
                if recalledCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 9))
                        Text(recalledCount == 1 ? "1 memory" : "\(recalledCount) memories")
                            .font(Theme.mono(10))
                    }
                    .foregroundStyle(Theme.textFaint)
                    .help("Memories recalled into context for this reply")
                }
                if showToolLine, let toolCalls = message.toolCalls {
                    Text(toolCalls.joined(separator: " · "))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func markdownText(text: String) -> some View {
        MessageCodeBody(text: text)
    }
}


// MARK: - Image attachments

/// Reusable assistant image artifact zone. It is intentionally independent
/// from ComfyUI: any tool that returns workspace-relative image artifacts can
/// render through the same card once the backend emits `imageArtifacts`.
private struct ChatImageAttachmentSection: View {
    let artifacts: [ChatImageArtifact]
    let accent: Color
    let messageID: Int?
    let allArtifacts: [ChatImageArtifact]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(artifacts) { artifact in
                ChatImageAttachmentCard(artifact: artifact, accent: accent,
                    preview: previewReference(for: artifact))
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
    }

    private func previewReference(for artifact: ChatImageArtifact) -> ChatImagePreviewReference? {
        guard artifact.path.isEmpty, artifact.assetId != nil, let messageID,
              let index = allArtifacts.firstIndex(where: { $0.id == artifact.id }) else { return nil }
        return .init(messageID: messageID, imageIndex: index)
    }
}

private struct ChatImageAttachmentCard: View {
    let artifact: ChatImageArtifact
    let accent: Color
    let preview: ChatImagePreviewReference?
    @Environment(ArtifactInspectorState.self) private var inspector
    @State private var copied = false
    @State private var decodedSize: CGSize?

    private var size: CGSize {
        ChatImagePresentation.size(width: decodedSize.map { Double($0.width) } ?? artifact.width.map(Double.init),
                                   height: decodedSize.map { Double($0.height) } ?? artifact.height.map(Double.init))
    }
    private var title: String { artifact.title ?? artifact.prompt ?? "Generated image" }
    private var canOpen: Bool { !artifact.path.isEmpty || preview != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: openImage) {
                AuthenticatedChatImageView(path: artifact.path, preview: preview, decodedSize: $decodedSize)
                    .aspectRatio(size.width / size.height, contentMode: .fit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .help("Open image in inspector")
            .accessibilityLabel("Open \(title) in inspector")

            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text).lineLimit(2)
                if let prompt = artifact.prompt, prompt != title {
                    Text(prompt).font(.system(size: 11.5)).foregroundStyle(Theme.textDim).lineLimit(2)
                }
                Text(metadata).font(Theme.mono(10)).foregroundStyle(Theme.textDim).lineLimit(2)
                HStack {
                    Button(action: openImage) {
                        Label("Open", systemImage: "sidebar.right")
                    }.disabled(!canOpen)
                    Spacer(minLength: 8)
                    Button(copied ? "Copied" : artifact.path.isEmpty ? "Copy reference" : "Copy path") {
                        let reference = artifact.path.isEmpty ? artifact.assetId ?? "" : artifact.path
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reference, forType: .string)
                        #else
                        UIPasteboard.general.string = reference
                        #endif
                        copied = true
                    }
                }.buttonStyle(.plain).font(Theme.mono(10.5)).foregroundStyle(accent)
            }.padding(10)
        }
        .frame(idealWidth: size.width, maxWidth: size.width, alignment: .leading)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
    }

    private var metadata: String {
        var parts: [String] = []
        if let workflow = artifact.workflow { parts.append(workflow) }
        if let width = artifact.width, let height = artifact.height { parts.append("\(width) x \(height)") }
        if let seed = artifact.seed { parts.append("seed \(seed)") }
        return parts.joined(separator: " · ")
    }

    private func openImage() {
        guard canOpen else { return }
        inspector.open(ArtifactReference(id: artifact.id, path: artifact.path,
            filename: artifact.path.isEmpty ? "Generated image" : (artifact.path as NSString).lastPathComponent,
            mediaType: "image/*", title: title, origin: .chat(sessionID: nil), chatImagePreview: preview))
    }
}

private struct AuthenticatedChatImageView: View {
    let path: String
    let preview: ChatImagePreviewReference?
    @Binding var decodedSize: CGSize?
    @Environment(AuthManager.self) private var authManager
    @Environment(ArtifactInspectorState.self) private var inspector
    @State private var image: PlatformImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedAccount: InspectorAccountScope?

    private struct LoadKey: Hashable {
        let account: InspectorAccountScope?
        let path: String
        let preview: ChatImagePreviewReference?
    }

    var body: some View {
        ZStack {
            if let image, loadedAccount == inspector.account {
                #if os(macOS)
                Image(nsImage: image).resizable().scaledToFit()
                #else
                Image(uiImage: image).resizable().scaledToFit()
                #endif
            } else if isLoading {
                ProgressView().controlSize(.small).tint(Theme.textMid)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 24))
                    Text(errorMessage ?? "Image preview unavailable")
                        .font(Theme.mono(10.5)).multilineTextAlignment(.center)
                    if preview != nil || path.isEmpty {
                        Text("Saved in ImageLab. No workspace export was made.")
                            .font(.system(size: 11)).multilineTextAlignment(.center)
                    }
                }.foregroundStyle(Theme.textDim).padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: LoadKey(account: inspector.account, path: path, preview: preview)) { await load() }
    }

    @MainActor private func load() async {
        image = nil
        decodedSize = nil
        errorMessage = nil
        let account = inspector.account
        guard let baseURL = authManager.serverURL, let token = try? authManager.token(),
              let request = ChatImagePresentation.request(baseURL: baseURL, token: token, path: path, preview: preview) else {
            errorMessage = path.isEmpty ? "Private preview not available yet" : "Not connected"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, inspector.account == account else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  http.mimeType?.hasPrefix("image/") == true, data.count <= 20_000_000,
                  let loaded = PlatformImage(data: data) else {
                errorMessage = preview == nil ? "Image unavailable" : "Private preview unavailable. ImageLab preview support or account access is required."
                return
            }
            image = loaded
            loadedAccount = account
            decodedSize = loaded.size
        } catch {
            guard !Task.isCancelled, inspector.account == account else { return }
            errorMessage = "Image preview could not be loaded"
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
    let activity: [ChatActivityItem]
    @Binding var expanded: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    if !activity.isEmpty {
                        ActivityRows(items: activity, accent: accent)
                        if !evidence.toolDetails.isEmpty {
                            Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                        }
                    }
                    ForEach(Array(evidence.toolDetails.enumerated()), id: \.offset) { index, detail in
                        if index > 0 {
                            Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                        }
                        EvidenceDetailRow(detail: detail, accent: accent)
                    }
                    if !evidence.citations.isEmpty {
                        if !evidence.toolDetails.isEmpty {
                            Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                        }
                        CitationRows(items: evidence.citations, accent: accent)
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
        if !evidence.citations.isEmpty { return evidence.citations.count }
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

private struct CitationRows: View {
    let items: [ChatEvidenceCitation]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SOURCES")
                .font(Theme.mono(9.5, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(Theme.textFaint)
            ForEach(items.prefix(12)) { item in
                if let rawURL = item.url, let url = URL(string: rawURL) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)
                                Text(sourceLine(for: item, url: url))
                                    .font(Theme.mono(9.5))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accent)
                        Text(item.displayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func sourceLine(for item: ChatEvidenceCitation, url: URL) -> String {
        [item.source, url.host, item.publishedAt]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }
}

private struct ActivityRows: View {
    let items: [ChatActivityItem]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ACTIVITY")
                .font(Theme.mono(9.5, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(Theme.textFaint)
            ForEach(items.prefix(8)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(accent.opacity(0.8))
                        .frame(width: 4, height: 4)
                    Text(item.displayText)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 10)
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
        "web_search", "web_context", "search_library", "search_my_feeds",
        "search_my_feeds_timeline", "search_feeds"
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
        case "web_search", "web_context": return "the web"
        case "search_library": return "your library"
        case "search_my_feeds", "search_my_feeds_timeline", "search_feeds": return "your feeds"
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
            toolNames: ["web_search", "fetch_page", "generate_image"],
            sourceKinds: ["web", "image"],
            sourceCounts: ["web": 2, "image": 1],
            toolDetails: [
                ChatEvidenceToolDetail(toolName: "web_search", detailKind: "query", label: "Query", value: "September rate cut odds"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://www.cmegroup.com/markets/interest-rates/fed-funds.html", sourceTitle: "CME FedWatch Tool", sourceKind: "web"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://www.reuters.com/markets/rates-bonds/fed-cut-odds", sourceKind: "web"),
                ChatEvidenceToolDetail(toolName: "fetch_page", detailKind: "url", label: "Page", value: "https://en.wikipedia.org/wiki/Federal_funds_rate", sourceTitle: "Federal funds rate", sourceKind: "wiki")
            ],
            imageArtifacts: [
                ChatImageArtifact(path: "generated_images/example.png", title: "Generated image", prompt: "A tiny robot baking a cake", workflow: "sdxl_basic", seed: 123, width: 1024, height: 1024, sourceTool: "generate_image")
            ]
        )
    )
    return ScrollView {
        VStack(spacing: 4) {
            MessageBubble(message: ChatThreadMessage(userMsg), personaKey: "family_assistant", evidenceExpanded: .constant(false))
            MessageBubble(message: ChatThreadMessage(asstMsg), personaKey: "family_assistant", personaDisplayName: "Family Assistant", evidenceExpanded: .constant(false))
            MessageBubble(message: ChatThreadMessage(groundedMsg), personaKey: "family_assistant", personaDisplayName: "Family Assistant", evidenceExpanded: .constant(true))
        }
        .padding(.vertical)
    }
    .background(Theme.bg)
}
