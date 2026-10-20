import Foundation
import Testing
import SwiftUI
#if os(macOS)
import AppKit
#endif
@testable import FruitcakeAi

@Suite @MainActor struct CodeAppearanceTests {
    @Test func preferenceIsVersionedWithSafeFallbackAndStableAppChrome() {
        #expect(CodeTheme.schemaVersion == 1)
        #expect(CodeTheme.resolve("missing-or-imported-theme") == .palette(.fruitcake))
        #expect(CodeTheme.resolve("paper").preset == .paper)
        #expect(CodeTheme.resolve("highContrast").preset == .highContrast)
        let chrome = Theme.bg
        for preset in CodeTheme.Preset.allCases {
            #expect(CodeTheme.palette(preset).preset == preset)
            #expect(Theme.bg == chrome)
        }
    }

    @Test func languageSelectionDoesNotGuessFromSourceOrExecuteHtml() {
        #expect(CodeLanguage.resolve(hint: "PYTHON") == .python)
        #expect(CodeLanguage.resolve(path: "src/Check.swift") == .swift)
        #expect(CodeLanguage.resolve(path: "app.ts") == .typescript)
        #expect(CodeLanguage.resolve(path: "package.json") == .json)
        #expect(CodeLanguage.resolve(hint: "bash") == .shell)
        #expect(CodeLanguage.resolve(path: "page.html") == .plain)
        #expect(CodeLanguage.resolve(hint: "unknown", path: "app.py") == .plain)
        #expect(CodeLanguage.resolve(path: "LICENSE") == .plain)
    }

    @Test func lexerRespectsMultilineCommentsStringsEscapesAndUnicodeOffsets() {
        let source = "// 🦎 note\r\nlet name = \"hi \\\"there\\\"\"\n/* outer /* nested */ still comment */\nstruct Room {}\n"
        let tokens = CodeSyntax.tokens(source, language: .swift)
        let comments = tokens.filter { $0.kind == .comment }.map { (source as NSString).substring(with: $0.range) }
        #expect(comments == ["// 🦎 note", "/* outer /* nested */ still comment */"])
        #expect(tokens.contains { $0.kind == .keyword && (source as NSString).substring(with: $0.range) == "let" })
        #expect(tokens.contains { $0.kind == .type && (source as NSString).substring(with: $0.range) == "Room" })
        #expect(tokens.filter { $0.kind == .string }.count == 1)
        let python = "value = '''first\n# not a comment\nlast'''\n# real comment\ndef check(value):\n    return 1e-3 + 2\n"
        let py = CodeSyntax.tokens(python, language: .python)
        #expect(py.filter { $0.kind == .comment }.count == 1)
        #expect(py.contains { $0.kind == .function && (python as NSString).substring(with: $0.range) == "check" })
        #expect(py.filter { $0.kind == .number }.map { (python as NSString).substring(with: $0.range) } == ["1e-3", "2"])
    }

    @Test func numbersDoNotConsumeOperatorsRangesOrMemberAccess() {
        let text = "1+2 0..<5 1.description 0xff 0b10 0o17 3.14 1e-3"
        let values = CodeSyntax.tokens(text, language: .swift).filter { $0.kind == .number }
            .map { (text as NSString).substring(with: $0.range) }
        #expect(values == ["1", "2", "0", "5", "1", "0xff", "0b10", "0o17", "3.14", "1e-3"])
    }

    @Test func jsonPropertiesAndShellQuotesHaveDistinctTokenKinds() {
        let json = "{\"name\": \"return\", \"enabled\": true, \"count\": 42}"
        let tokens = CodeSyntax.tokens(json, language: .json)
        #expect(tokens.filter { $0.kind == .property }.count == 3)
        #expect(tokens.filter { $0.kind == .keyword }.count == 1)
        #expect(tokens.filter { $0.kind == .string }.count == 1)
        let shell = "echo '# literal' # comment\nif true; then echo \"hi\"; fi\n"
        let sh = CodeSyntax.tokens(shell, language: .shell)
        #expect(sh.filter { $0.kind == .comment }.count == 1)
        #expect(sh.filter { $0.kind == .string }.count == 2)
    }

    @Test(arguments: CodeLanguage.allCases) func rangesAreOrderedValidAndRenderingPreservesEveryCharacter(language: CodeLanguage) {
        let text = "let café = \"🦎 \\n λ\"\r\n# comment\n/* nested */\nreturn f(1 + 2)\n\n"
        let tokens = CodeSyntax.tokens(text, language: language)
        var end = 0
        for token in tokens {
            #expect(token.range.location >= end && token.range.length > 0)
            #expect(NSMaxRange(token.range) <= (text as NSString).length)
            #expect(Range(token.range, in: text) != nil)
            end = NSMaxRange(token.range)
        }
        for preset in CodeTheme.Preset.allCases {
            let native = CodeHighlight.native(text, tokens: tokens, theme: .palette(preset))
            #expect(native.string == text)
            #expect(String(CodeHighlight.attributed(text, language: language, theme: .palette(preset)).characters) == text)
        }
    }

    @Test func unknownOversizedAndExcessiveTokenInputsFallBackWithoutTruncation() {
        #expect(CodeSyntax.tokens("<script>notExecutable()</script>", language: .plain).isEmpty)
        #expect(CodeSyntax.tokens(String(repeating: "#", count: CodeSyntax.byteLimit + 1), language: .python).isEmpty)
        #expect(CodeSyntax.tokens(String(repeating: "\n", count: CodeSyntax.lineLimit), language: .swift).isEmpty)
        #expect(CodeSyntax.tokens(String(repeating: "+ ", count: CodeSyntax.tokenLimit + 1), language: .swift).isEmpty)
        let text = String(repeating: "é", count: CodeSyntax.byteLimit / 2 + 1)
        #expect(CodeSyntax.tokens(text, language: .swift).isEmpty)
        #expect(String(CodeHighlight.attributed(text, language: .swift, theme: .palette(.paper)).characters) == text)
        #expect(CodeSyntax.tokens("", language: .swift).isEmpty)
    }

    @Test(arguments: CodeTheme.Preset.allCases) func palettesAndChangedRowFallbackMaintainContrast(preset: CodeTheme.Preset) {
        let theme = CodeTheme.palette(preset)
        #expect(CodeTheme.contrast(theme.foreground, theme.background) >= 4.5)
        #expect(CodeTheme.contrast(theme.secondary, theme.gutter) >= 4.5)
        #expect(CodeTheme.contrast(theme.foreground, theme.selection) >= 4.5)
        for token in CodeTokenKind.allCases {
            #expect(CodeTheme.contrast(theme.hex(for: token), theme.background) >= 4.5)
            for (fill, fallback) in [(theme.additionFill, theme.additionText), (theme.removalFill, theme.removalText)] {
                #expect(CodeTheme.contrast(fallback, fill) >= 4.5)
                #expect(CodeTheme.contrast(theme.findingMarker, fill) >= 3)
                #expect(CodeTheme.contrast(theme.hex(for: token, on: fill, fallback: fallback), fill) >= 4.5)
            }
        }
    }

    #if os(macOS)
    @Test func livePreferenceRestylesExistingSourceViewWithoutReplacingItsDocument() async throws {
        let suite = "CodeAppearanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fruitcake", forKey: CodeTheme.preferenceKey)
        let text = String(repeating: "let room = \"Lab\"\n", count: 300)
        let host = NSHostingView(rootView: InspectorSourceTextView(text: text, version: "same-version", language: .swift, findRequest: 0)
            .defaultAppStorage(defaults).frame(width: 320, height: 220))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        host.layoutSubtreeIfNeeded()
        func descendant<T: NSView>(_ view: NSView, _ type: T.Type) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { descendant($0, type) }.first
        }
        let scroll = try #require(descendant(host, NSScrollView.self))
        let view = try #require(scroll.documentView as? NSTextView)
        let storage = try #require(view.textStorage)
        view.setSelectedRange(NSRange(location: 4, length: 4))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 240))
        let origin = scroll.contentView.bounds.origin, selection = view.selectedRanges
        defaults.set("paper", forKey: CodeTheme.preferenceKey)
        let expected = NSColor(Color(hex: CodeTheme.palette(.paper).background))
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if view.backgroundColor == expected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view.backgroundColor == expected)
        #expect(descendant(host, NSScrollView.self) === scroll)
        #expect(scroll.documentView === view && view.textStorage === storage)
        #expect(view.string == text && view.selectedRanges == selection)
        #expect(scroll.contentView.bounds.origin == origin)
    }

    @Test func textAttributeOnlyThemeUpdatesKeepSelectionScrollAndFindConfiguration() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 1200, height: 8000))
        scroll.documentView = view
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        let text = String(repeating: "let room = \"🦎 Lab\"\n", count: 300)
        view.string = text
        view.setSelectedRange(NSRange(location: 4, length: 4))
        scroll.contentView.scroll(to: NSPoint(x: 30, y: 280))
        let origin = scroll.contentView.bounds.origin, selection = view.selectedRanges
        let storage = try #require(view.textStorage)
        let tokens = CodeSyntax.tokens(text, language: .swift)
        for preset in CodeTheme.Preset.allCases {
            CodeTextStorageStyle.apply(view, tokens: tokens, theme: .palette(preset))
            #expect(view.textStorage === storage)
            #expect(view.string == text && !view.isEditable)
            #expect(view.selectedRanges == selection)
            #expect(scroll.contentView.bounds.origin == origin)
            #expect(view.usesFindBar && view.isIncrementalSearchingEnabled)
            let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            #expect(color == NSColor(Color(hex: CodeTheme.palette(preset).keyword)))
        }
        view.string = ""
        CodeTextStorageStyle.apply(view, tokens: [], theme: .palette(.paper))
        #expect(view.string.isEmpty)
    }

    @Test(arguments: CodeTheme.Preset.allCases) func renderAppearanceAndActualDiff(preset: CodeTheme.Preset) throws {
        let suite = "CodeAppearanceRender.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(preset.rawValue, forKey: CodeTheme.preferenceKey)
        let settings = NSHostingView(rootView: CodeAppearanceView().defaultAppStorage(defaults)
            .frame(width: 820, height: 860).environment(\.colorScheme, .dark))
        try saveRender(settings, name: "settings-\(preset.rawValue)", width: 820, height: 860)
        let diff = CodingRepositoryDiff(basis: "review_capture", observedAt: Date(timeIntervalSince1970: 1_792_411_200), path: "validation.py",
            sections: [.init(kind: "captured", text: "--- a/validation.py\n+++ b/validation.py\n@@ -1,2 +1,2 @@\n def valid(value):\n-    return False\n+    return value is not None\n", truncated: false)],
            captureId: "fixture-capture", base: "base", head: "head", reviewAnchorSide: "after", reviewAnchorStart: 2, reviewAnchorEnd: 2)
        for unified in [false, true] {
            let host = NSHostingView(rootView: CodingDiffPreview(diff: diff, initialUnified: unified).defaultAppStorage(defaults)
                .frame(width: 820, height: 340).environment(\.colorScheme, .dark))
            try saveRender(host, name: "diff-\(preset.rawValue)-\(unified)", width: 820, height: 340)
        }
    }

    private func saveRender<V: View>(_ host: NSHostingView<V>, name: String, width: Int, height: Int) throws {
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-code-\(name).png")
        try png.write(to: url)
        print("CODE_APPEARANCE_FIXTURE: \(url.path)")
        #expect(png.count > 2000)
    }

    @Test(arguments: CodeTheme.Preset.allCases, [320, 680]) func renderCodePalette(preset: CodeTheme.Preset, width: Int) throws {
        let theme = CodeTheme.palette(preset)
        let text = "// Read-only preview\nstruct Room {\n    let name: String\n    func label() -> String {\n        return \"Room\"\n    }\n}\nlet count = 42\n"
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
            Text(preset.title).font(Theme.mono(11)).foregroundStyle(Color(hex: theme.secondary)).padding(10)
            CodeSourceText(text: text, language: .swift, size: 12, theme: theme).padding(12)
            CodeSourceText(text: "+ let valid = true", language: .swift, size: 12, theme: theme,
                           foreground: theme.additionText, fill: theme.additionFill)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: theme.additionFill))
            CodeSourceText(text: "- let valid = false", language: .swift, size: 12, theme: theme,
                           foreground: theme.removalText, fill: theme.removalFill)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: theme.removalFill))
        }.frame(width: CGFloat(width), alignment: .leading).background(Color(hex: theme.background)))
        host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-code-theme-\(preset.rawValue)-\(width).png")
        try png.write(to: url)
        print("CODE_THEME_FIXTURE: \(url.path)")
        #expect(png.count > 2000)
    }
    #endif
}
