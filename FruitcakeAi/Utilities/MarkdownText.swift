//
//  MarkdownText.swift
//  FruitcakeAi
//
//  Shared helper that converts plain text (with optional markdown) into an
//  AttributedString with clickable links. Preserves single newlines as
//  markdown line breaks and detects URLs via NSDataDetector.
//

import SwiftUI

enum MarkdownText {

    /// Parses `text` as markdown, preserving single newlines as line breaks
    /// and auto-linking any detected URLs.
    static func attributedString(from text: String) -> AttributedString {
        // Preserve single newlines as markdown line breaks (two trailing spaces + newline)
        // while keeping double newlines as paragraph breaks.
        let prepared = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n", with: "\u{0000}PARA\u{0000}")
            .replacingOccurrences(of: "\n", with: "  \n")
            .replacingOccurrences(of: "\u{0000}PARA\u{0000}", with: "\n\n")

        let base: NSAttributedString
        if let markdown = try? AttributedString(
            markdown: prepared,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            base = NSAttributedString(markdown)
        } else {
            base = NSAttributedString(string: text)
        }

        let mutable = NSMutableAttributedString(attributedString: base)
        let fullRange = NSRange(location: 0, length: (mutable.string as NSString).length)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: mutable.string, options: [], range: fullRange) { match, _, _ in
                guard let match, let url = match.url else { return }
                mutable.addAttribute(.link, value: url, range: match.range)
            }
        }
        return AttributedString(mutable)
    }
}
