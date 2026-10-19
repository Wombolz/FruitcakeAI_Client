#if os(macOS)
import SwiftUI
import AppKit

enum CodingStatusTone: Equatable {
    case neutral, active, attention, success, failure

    static func forStatus(_ status: String) -> Self {
        switch status {
        case "starting", "running", "creating", "committing", "applying": .active
        case "waiting_approval", "stopping", "interrupted", "expired": .attention
        case "completed", "approved", "applied": .success
        case "failed", "error", "denied": .failure
        default: .neutral
        }
    }

    var color: Color {
        switch self {
        case .neutral: Theme.textDim
        case .active: Theme.codeAccent
        case .attention: Theme.onDevice
        case .success: Theme.ok
        case .failure: Theme.danger
        }
    }
}

struct CodingStatusBadge: View {
    let status: String
    var compact = false

    var body: some View {
        let color = CodingStatusTone.forStatus(status).color
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(Theme.mono(compact ? 9 : 10)).lineLimit(1)
        }
        .foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4)
        .background(color.opacity(0.09), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        .accessibilityLabel("Status: \(status.replacingOccurrences(of: "_", with: " "))")
    }
}

struct CodingActionStyle: ButtonStyle {
    enum Emphasis: Equatable { case secondary, primary }
    var emphasis: Emphasis = .secondary
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(emphasis == .primary ? Theme.text : Theme.textMid)
            .background(emphasis == .primary ? Theme.codeAccent.opacity(configuration.isPressed ? 0.55 : 0.85)
                        : (configuration.isPressed ? Theme.titlebar : Theme.field), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(emphasis == .primary ? Theme.codeAccent : Theme.strokeUp, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct CodingCard: ViewModifier {
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content.background(Theme.card)
            .overlay(alignment: .leading) {
                if let accent { Rectangle().fill(accent).frame(width: 2) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent?.opacity(0.25) ?? Theme.stroke, lineWidth: 1))
    }
}

struct CodingMessageBlock: Identifiable {
    let id: Int
    let text: String
    let isCode: Bool
    let language: String

    static func parse(_ text: String) -> [Self] {
        var blocks: [Self] = [], buffer = "", fence: String?, language = ""
        func flush(code: Bool) {
            guard code || !buffer.isEmpty else { return }
            blocks.append(.init(id: blocks.count, text: buffer, isCode: code, language: code ? language : ""))
            buffer = ""
        }
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let current = fence {
                if marker.count >= current.count && marker.allSatisfy({ $0 == current.first }) {
                    flush(code: true); fence = nil; language = ""; continue
                }
            } else if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                flush(code: false)
                let delimiter = String(marker.prefix { $0 == marker.first })
                fence = delimiter
                language = String(marker.dropFirst(delimiter.count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            buffer += line + (index < lines.count - 1 ? "\n" : "")
        }
        flush(code: fence != nil)
        return blocks
    }
}

struct CodingMessageBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(CodingMessageBlock.parse(text)) { block in
                if block.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(block.language.isEmpty ? "CODE" : block.language.uppercased()).font(Theme.mono(9))
                            Spacer()
                            Button("Copy", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(block.text, forType: .string)
                            }.buttonStyle(.plain).font(.system(size: 10)).help("Copy code (does not execute it)")
                        }.foregroundStyle(Theme.textDim).padding(9)
                        Rectangle().fill(Theme.stroke).frame(height: 1)
                        ScrollView(.horizontal) {
                            Text(block.text.isEmpty ? " " : block.text).font(Theme.mono(11))
                                .foregroundStyle(Theme.textMid).textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true).padding(10)
                        }
                    }.background(Theme.composer, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
                } else {
                    let prose = block.text.trimmingCharacters(in: .newlines)
                    if !prose.isEmpty {
                        MessageProse(text: prose).font(.system(size: 13.5))
                            .foregroundStyle(Theme.textMid).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.tint(Theme.codeAccent)
    }
}

struct CodingAssistantMessage: View {
    let text: String
    var occurredAt: Date? = nil
    var provisional = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coding Assistant").font(Theme.mono(10.5)).foregroundStyle(Theme.textFaint).padding(.leading, 4)
            CodingMessageBody(text: text).padding(.horizontal, 15).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bubble)
                .overlay(alignment: .leading) { Theme.codeAccent.opacity(0.55).frame(width: 2) }
                .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 4,
                                 bottomTrailingRadius: 14, topTrailingRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
            if let occurredAt {
                MessageTimestamp(date: occurredAt, provisional: provisional)
                    .foregroundStyle(Theme.textFaint).padding(.horizontal, 4)
            }
        }
    }
}
#endif
