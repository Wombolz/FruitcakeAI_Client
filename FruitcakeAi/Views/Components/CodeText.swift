import SwiftUI
#if os(macOS)
import AppKit
private typealias CodePlatformColor = NSColor
#else
import UIKit
private typealias CodePlatformColor = UIColor
#endif

enum CodeHighlight {
    static func native(_ text: String, tokens: [CodeToken], theme: CodeTheme,
                       foreground: UInt? = nil, fill: UInt? = nil) -> NSAttributedString {
        let base = foreground ?? theme.foreground
        let value = NSMutableAttributedString(string: text, attributes: [.foregroundColor: CodePlatformColor(Color(hex: base))])
        for token in tokens where token.range.location >= 0 && token.range.length > 0
            && NSMaxRange(token.range) <= value.length {
            value.addAttribute(.foregroundColor,
                               value: CodePlatformColor(Color(hex: theme.hex(for: token.kind, on: fill, fallback: base))), range: token.range)
        }
        return value
    }

    static func attributed(_ text: String, language: CodeLanguage, theme: CodeTheme,
                           foreground: UInt? = nil, fill: UInt? = nil) -> AttributedString {
        AttributedString(native(text, tokens: CodeSyntax.tokens(text, language: language), theme: theme, foreground: foreground, fill: fill))
    }
}

struct CodeSourceText: View {
    let text: String
    var language: CodeLanguage = .plain
    var size: CGFloat = 11
    var theme: CodeTheme
    var foreground: UInt? = nil
    var fill: UInt? = nil

    var body: some View {
        Text(CodeHighlight.attributed(text, language: language, theme: theme, foreground: foreground, fill: fill))
            .font(Theme.mono(size)).lineSpacing(0).textSelection(.enabled)
    }
}

struct CodeSnippet: View {
    let text: String
    var language = ""
    @AppStorage(CodeTheme.preferenceKey) private var themeID = CodeTheme.Preset.fruitcake.rawValue
    private var theme: CodeTheme { .resolve(themeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "CODE" : language.uppercased()).font(Theme.mono(9)).lineLimit(1)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { copy() }
                    .buttonStyle(.plain).font(.system(size: 10)).help("Copy code (does not execute it)")
            }.foregroundStyle(Color(hex: theme.secondary)).padding(9).background(Color(hex: theme.gutter))
            ScrollView(.horizontal) {
                CodeSourceText(text: text, language: .resolve(hint: language), theme: theme)
                    .fixedSize(horizontal: true, vertical: true).padding(10)
            }
        }.background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
    }
    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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

/// Shared fenced-code presentation. Prose still uses the existing safe inline parser.
struct MessageCodeBody: View {
    let text: String
    var body: some View {
        let blocks = CodingMessageBlock.parse(text)
        if !blocks.contains(where: \.isCode) { MessageProse(text: text) }
        else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { block in
                    if block.isCode { CodeSnippet(text: block.text, language: block.language) }
                    else {
                        let prose = block.text.trimmingCharacters(in: .newlines)
                        if !prose.isEmpty { MessageProse(text: prose) }
                    }
                }
            }
        }
    }
}

#if os(macOS)
@MainActor enum CodeTextStorageStyle {
    static func apply(_ view: NSTextView, tokens: [CodeToken], theme: CodeTheme) {
        guard let storage = view.textStorage else { return }
        let selection = view.selectedRanges
        let origin = view.enclosingScrollView?.contentView.bounds.origin
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                               .foregroundColor: NSColor(Color(hex: theme.foreground))], range: range)
        let styled = CodeHighlight.native(view.string, tokens: tokens, theme: theme)
        styled.enumerateAttribute(.foregroundColor, in: range) { color, range, _ in
            if let color { storage.addAttribute(.foregroundColor, value: color, range: range) }
        }
        storage.endEditing()
        view.backgroundColor = NSColor(Color(hex: theme.background))
        view.insertionPointColor = NSColor(Color(hex: theme.foreground))
        view.selectedTextAttributes = [.backgroundColor: NSColor(Color(hex: theme.selection)),
                                       .foregroundColor: NSColor(Color(hex: theme.foreground))]
        view.setSelectedRanges(selection, affinity: view.selectionAffinity, stillSelecting: false)
        if let origin, let scroll = view.enclosingScrollView {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
#endif
