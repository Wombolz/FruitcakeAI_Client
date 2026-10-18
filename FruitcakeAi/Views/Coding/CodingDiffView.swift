#if os(macOS)
import SwiftUI
import AppKit

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
    @State private var sectionIndex = 0
    @State private var unified = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Change stage", selection: $sectionIndex) {
                    ForEach(Array(diff.sections.enumerated()), id: \.offset) { index, section in
                        Text(section.kind.capitalized).tag(index)
                    }
                }.labelsHidden().fixedSize()
                Spacer(minLength: 8)
                Picker("Diff layout", selection: $unified) {
                    Text("Split").tag(false)
                    Text("Unified").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }.padding(8)
            if !diff.sections.isEmpty {
                let section = diff.sections[min(sectionIndex, diff.sections.count - 1)]
                let split = CodingSplitDiff.parse(section.text)
                if unified || split.rows.isEmpty {
                    ScrollView([.horizontal, .vertical]) {
                        Text(section.text.isEmpty ? "No textual diff available." : section.text)
                            .font(Theme.mono(11)).textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true).padding(12)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    splitBody(split, kind: section.kind)
                }
                if section.truncated || (!unified && split.truncated) {
                    Text(section.truncated ? "Git preview truncated. Use an external editor for the complete diff."
                         : "Split view limited to 1,500 rows. Switch to Unified for the full returned preview.")
                        .font(.system(size: 10)).foregroundStyle(Theme.onDevice).padding(6)
                }
            } else { Spacer() }
            Text("\(diff.basis == "approval" ? "Complete approval snapshot · see saved record for outcome" : diff.basis == "saved_change" ? "Saved host change record · not current worktree" : "Changed hunks only") · \(diff.observedAt.formatted(date: .omitted, time: .standard))")
                .font(Theme.mono(9)).foregroundStyle(Theme.textFaint).padding(6)
        }
        .onChange(of: diff.path) { _, _ in sectionIndex = 0 }
    }

    private func splitBody(_ split: CodingSplitDiff, kind: String) -> some View {
        GeometryReader { geometry in
            let columnWidth = max(1, (geometry.size.width - 1) / 2)
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Text(diff.basis != "current_worktree" ? "BEFORE · REVIEWED SNAPSHOT" : kind == "staged" ? "BEFORE · HEAD" : kind == "untracked" ? "BEFORE · EMPTY" : "BEFORE · INDEX")
                        .frame(width: columnWidth, alignment: .leading)
                    Text(diff.basis == "approval" ? "AFTER · PROPOSED" : diff.basis == "saved_change" ? "AFTER · APPROVED CONTENT (SEE STATUS)" : kind == "staged" ? "AFTER · INDEX" : "AFTER · WORKING TREE")
                        .frame(width: columnWidth, alignment: .leading)
                }.font(Theme.mono(9)).foregroundStyle(Theme.textDim).padding(.vertical, 6)
                // One vertical scroller keeps both sides aligned. Each side has
                // independent horizontal scrolling; no scroll-offset feedback loop.
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 1) {
                        codeColumn(split.rows, before: true, width: columnWidth)
                        codeColumn(split.rows, before: false, width: columnWidth)
                    }.background(Theme.strokeUp)
                }
            }
        }
    }

    private func codeColumn(_ rows: [CodingSplitDiff.Row], before: Bool, width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let number = before ? row.beforeNumber : row.afterNumber
                    let text = before ? row.before : row.after
                    HStack(spacing: 8) {
                        Text(number.map(String.init) ?? "").foregroundStyle(Theme.textFaint)
                            .frame(width: 38, alignment: .trailing)
                        Text(text ?? " ").foregroundStyle(row.kind == .hunk ? Theme.textDim : Theme.text)
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                    }
                    .font(Theme.mono(11)).frame(height: 18)
                    .frame(minWidth: width, alignment: .leading)
                    .background(row.kind == .change && text != nil
                                ? (before ? Color.red : Theme.ok).opacity(0.12) : Theme.bg)
                }
            }.frame(minWidth: width, alignment: .leading)
        }.frame(width: width, height: CGFloat(rows.count) * 18).background(Theme.bg)
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
