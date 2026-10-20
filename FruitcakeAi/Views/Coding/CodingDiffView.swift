#if os(macOS)
import SwiftUI
import AppKit

enum CodingDiffTone: Equatable {
    case addition, removal, context, header

    static func unified(_ line: String) -> Self {
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") || line.hasPrefix("@@")
            || line.hasPrefix("diff --git ") || line.hasPrefix("index ") { return .header }
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .removal }
        return .context
    }

    var foreground: Color { Color(hex: foreground(in: .palette(.fruitcake))) }
    var background: Color { Color(hex: background(in: .palette(.fruitcake))) }

    func foreground(in theme: CodeTheme) -> UInt {
        switch self {
        case .addition: theme.additionText
        case .removal: theme.removalText
        case .header: theme.secondary
        case .context: theme.foreground
        }
    }
    func background(in theme: CodeTheme) -> UInt {
        switch self {
        case .addition: theme.additionFill
        case .removal: theme.removalFill
        case .header: theme.gutter
        case .context: theme.background
        }
    }

}

struct CodingDiffDrawer: View {
    let store: CodingWorkspaceStore
    let popOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.textDim)
                Text(store.reviewedPath ?? "Diff").font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button(action: popOut) { Image(systemName: "macwindow.on.rectangle") }
                    .buttonStyle(.plain).disabled(store.repositoryDiff == nil)
                    .help("Open diff in a resizable window").accessibilityLabel("Open diff window")
                Button { store.closeDiff() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close diff panel").accessibilityLabel("Close diff panel")
            }.padding(10)
            Rectangle().fill(Theme.strokeUp).frame(height: 1)
            if store.loadingDiff {
                ProgressView("Reading diff").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff = store.repositoryDiff {
                CodingDiffPreview(diff: diff)
            } else {
                Text(store.repositoryError ?? "Select a changed file in the right inspector.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.background(Theme.bg).foregroundStyle(Theme.text)
    }
}

struct CodingDiffPreview: View {
    let diff: CodingRepositoryDiff
    @AppStorage(CodeTheme.preferenceKey) private var codeThemeID = CodeTheme.Preset.fruitcake.rawValue
    private var codeTheme: CodeTheme { .resolve(codeThemeID) }
    @State private var sectionIndex = 0
    @State private var unified = false

    init(diff: CodingRepositoryDiff, initialUnified: Bool = false) {
        self.diff = diff
        _unified = State(initialValue: initialUnified)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let capture = diff.captureId {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REVIEWED CAPTURE \(capture.prefix(12)) · Base \((diff.base ?? "unknown").prefix(12)) · HEAD \((diff.head ?? "unknown").prefix(12))")
                        .font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                    if let side = diff.reviewAnchorSide, let start = diff.reviewAnchorStart, let end = diff.reviewAnchorEnd {
                        Text("Finding anchor: \(side) L\(start)-\(end) · retained snapshot, not live code").font(Theme.mono(10))
                    }
                    if let text = diff.reviewQualification, !text.isEmpty { Text(text).font(.caption).foregroundStyle(Theme.onDevice) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack(spacing: 10) {
                Picker("Change stage", selection: $sectionIndex) {
                    ForEach(Array(diff.sections.enumerated()), id: \.offset) { index, section in
                        Text(section.kind.capitalized).tag(index)
                    }
                }.labelsHidden().fixedSize()
                Button {
                    guard !diff.sections.isEmpty else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diff.sections[min(sectionIndex, diff.sections.count - 1)].text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).disabled(diff.sections.isEmpty)
                    .help("Copy the complete returned diff text").accessibilityLabel("Copy diff")
                Spacer(minLength: 8)
                Picker("Diff layout", selection: $unified) {
                    Text("Split").tag(false)
                    Text("Unified").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }.padding(8)
            if !diff.sections.isEmpty {
                let section = diff.sections[min(sectionIndex, diff.sections.count - 1)]
                let split = CodingSplitDiff.parse(section.text)
                if let side = diff.reviewAnchorSide, let line = diff.reviewAnchorStart,
                   !split.rows.contains(where: { (side == "before" ? $0.beforeNumber : $0.afterNumber) == line }) {
                    Text("Finding anchor is outside the displayed hunks or split-view limit. Its captured evidence remains in Findings; no live file is substituted.")
                        .font(.system(size: 10)).foregroundStyle(Theme.onDevice).padding(6)
                }
                if unified || split.rows.isEmpty {
                    unifiedBody(section.text)
                } else {
                    splitBody(split, kind: section.kind)
                }
                if section.truncated || (!unified && split.truncated) {
                    Text(section.truncated ? "Git preview truncated. Use an external editor for the complete diff."
                         : "Split view limited to 1,500 rows. Switch to Unified for the full returned preview.")
                        .font(.system(size: 10)).foregroundStyle(Theme.onDevice).padding(6)
                }
            } else { Spacer() }
            Text("\(diff.basis == "review_capture" ? "Frozen reviewed diff · no live-file substitution" : diff.basis == "approval" ? "Complete approval snapshot · see saved record for outcome" : diff.basis == "saved_change" ? "Saved host change record · not current worktree" : "Changed hunks only") · \(diff.observedAt.formatted(date: .omitted, time: .standard))")
                .font(Theme.mono(9)).foregroundStyle(Theme.textFaint).padding(6)
        }
        .onChange(of: diff.path) { _, _ in sectionIndex = 0 }
        .background(Theme.bg).foregroundStyle(Theme.text).tint(Theme.codeAccent)
    }

    private func splitBody(_ split: CodingSplitDiff, kind: String) -> some View {
        GeometryReader { geometry in
            let columnWidth = max(1, (geometry.size.width - 1) / 2)
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Text(diff.basis != "current_worktree" ? "BEFORE · REVIEWED SNAPSHOT" : kind == "staged" ? "BEFORE · HEAD" : kind == "untracked" ? "BEFORE · EMPTY" : "BEFORE · INDEX")
                        .frame(width: columnWidth, alignment: .leading)
                    Text(diff.basis == "review_capture" ? "AFTER · REVIEWED SNAPSHOT" : diff.basis == "approval" ? "AFTER · PROPOSED" : diff.basis == "saved_change" ? "AFTER · APPROVED CONTENT (SEE STATUS)" : kind == "staged" ? "AFTER · INDEX" : "AFTER · WORKING TREE")
                        .frame(width: columnWidth, alignment: .leading)
                }.font(Theme.mono(9)).foregroundStyle(Theme.textDim).padding(.vertical, 6)
                // One vertical scroller keeps both sides aligned. Each side has
                // independent horizontal scrolling; no scroll-offset feedback loop.
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 1) {
                            codeColumn(split.rows, before: true, width: columnWidth)
                            codeColumn(split.rows, before: false, width: columnWidth)
                        }.background(Color(hex: codeTheme.secondary).opacity(0.25))
                    }.background(Color(hex: codeTheme.background)).task(id: anchorIdentity) {
                        if let side = diff.reviewAnchorSide, let line = diff.reviewAnchorStart {
                            proxy.scrollTo("\(side)-\(line)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var anchorIdentity: String { "\(diff.captureId ?? ""):\(diff.path):\(diff.reviewAnchorSide ?? ""):\(diff.reviewAnchorStart ?? 0)" }

    // Hunks are fragments, not complete files: lexical state is local to each
    // displayed line. We never fetch live source to color a retained capture.
    private func diffText(_ text: String, tone: CodingDiffTone, unified: Bool) -> some View {
        let prefix = unified && tone != .header && !text.isEmpty ? String(text.prefix(1)) : ""
        let source = prefix.isEmpty ? text : String(text.dropFirst())
        let language: CodeLanguage = tone == .header ? .plain : .resolve(path: diff.path)
        let colored = CodeHighlight.attributed(source, language: language, theme: codeTheme,
                                              foreground: tone.foreground(in: codeTheme), fill: tone.background(in: codeTheme))
        var marker = AttributedString(prefix)
        marker.foregroundColor = Color(hex: tone.foreground(in: codeTheme))
        return Text(marker + colored).font(Theme.mono(11))
    }

    private func unifiedBody(_ text: String) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((text.isEmpty ? "No textual diff available." : text).components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        let tone = CodingDiffTone.unified(line)
                        diffText(line.isEmpty ? " " : line, tone: tone, unified: true)
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12).frame(height: 20)
                            .frame(minWidth: max(1, geometry.size.width), alignment: .leading)
                            .background(Color(hex: tone.background(in: codeTheme)))
                    }
                }
            }.background(Color(hex: codeTheme.background))
        }
    }

    private func codeColumn(_ rows: [CodingSplitDiff.Row], before: Bool, width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let number = before ? row.beforeNumber : row.afterNumber
                    let text = before ? row.before : row.after
                    let changed = row.kind == .change && text != nil
                    let tone: CodingDiffTone = changed ? (before ? .removal : .addition) : row.kind == .hunk ? .header : .context
                    let anchored = diff.reviewAnchorSide == (before ? "before" : "after")
                        && number.map { $0 >= (diff.reviewAnchorStart ?? Int.max) && $0 <= (diff.reviewAnchorEnd ?? -1) } == true
                    HStack(spacing: 8) {
                        Text(number.map(String.init) ?? "").foregroundStyle(Color(hex: changed ? tone.foreground(in: codeTheme) : codeTheme.secondary))
                            .frame(width: 38, alignment: .trailing)
                        Text(changed ? (before ? "-" : "+") : " ").foregroundStyle(Color(hex: tone.foreground(in: codeTheme))).frame(width: 8)
                        diffText(text ?? " ", tone: tone, unified: false)
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                    }
                    .font(Theme.mono(11)).frame(height: 18)
                    .frame(minWidth: width, alignment: .leading)
                    .background(Color(hex: tone.background(in: codeTheme)))
                    .overlay(alignment: .leading) {
                        if anchored { Rectangle().fill(Color(hex: codeTheme.findingMarker)).frame(width: 3) }
                    }
                    .overlay(Rectangle().stroke(anchored ? Color(hex: codeTheme.findingMarker).opacity(0.65) : .clear, lineWidth: 1))
                    .id(number.map { "\(before ? "before" : "after")-\($0)" } ?? "\(before ? "before" : "after")-row-\(index)")
                }
            }.frame(minWidth: width, alignment: .leading)
        }.frame(width: width, height: CGFloat(rows.count) * 18).background(Color(hex: codeTheme.background))
    }
}

@MainActor
final class CodingDiffWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Repository Diff"
        window.contentMinSize = NSSize(width: 600, height: 300)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("coding.diff.window")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ diff: CodingRepositoryDiff) {
        window?.title = "Diff: \(diff.path)"
        window?.contentViewController = NSHostingController(rootView:
            VStack(spacing: 0) {
                Text("Read-only snapshot · \(diff.path) · \(diff.observedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim).padding(10)
                CodingDiffPreview(diff: diff)
            }.background(Theme.bg).foregroundStyle(Theme.text))
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif
