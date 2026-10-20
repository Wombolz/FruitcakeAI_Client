import SwiftUI

struct InspectorExplorerView: View {
    let store: InspectorExplorerStore
    let active: Bool
    @Environment(ArtifactInspectorState.self) private var inspector
    @State private var refreshRevision = 0
    private struct LoadKey: Hashable { let active: Bool; let revision: Int }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(store.source.root?.label ?? "Workspace Explorer", systemImage: "folder").font(.system(size: 13, weight: .semibold))
                    if let root = store.source.root {
                        Text("\(store.source.isUserWorkspace ? "MY WORKSPACE" : "CHECKOUT") \(root.rootId.prefix(8)) · READ ONLY").font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                    }
                }
                Spacer(minLength: 4)
                if store.source.root != nil {
                    Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(store.validating).accessibilityLabel("Refresh Explorer")
                }
            }.padding(12)
            Divider()
            if let reason = store.source.unavailableReason {
                ContentUnavailableView("No Attached Directory", systemImage: "folder.badge.questionmark", description: Text(reason))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.rows) { row in
                            rowView(row).padding(.leading, CGFloat(min(row.depth, 16)) * 12)
                        }
                        if store.rows.isEmpty && !store.validating {
                            Text("No eligible entries in this directory.").font(.caption).foregroundStyle(Theme.textDim).padding(12)
                        }
                    }.padding(8)
                }
                .opacity(store.validating ? 0 : 1)
                .allowsHitTesting(!store.validating)
                .accessibilityHidden(store.validating)
                .overlay { if store.validating { ProgressView("Rechecking directory access") } }
                Text("Hidden, sensitive and linked paths are excluded; Code also applies Git ignores. Opening a file does not attach it to Chat or grant edits.")
                    .font(.system(size: 10)).foregroundStyle(Theme.textDim).padding(12)
            }
        }
        .background(Theme.bg).foregroundStyle(Theme.text)
        .task(id: LoadKey(active: active, revision: refreshRevision)) {
            if active, store.source.root != nil { await store.activate() } else { store.suspend() }
        }
        .onDisappear { store.suspend() }
    }

    @ViewBuilder private func rowView(_ row: InspectorExplorerRow) -> some View {
        switch row.kind {
        case .entry(let entry):
            Button {
                if entry.kind == .directory { Task { await store.toggle(entry.path) } }
                else { inspector.openSourceFile(store.source, path: entry.path) }
            } label: {
                HStack(spacing: 7) {
                    if entry.kind == .directory {
                        Image(systemName: store.expanded.contains(entry.path) ? "chevron.down" : "chevron.right").font(.system(size: 9)).frame(width: 9)
                    } else { Color.clear.frame(width: 9, height: 1) }
                    Image(systemName: entry.kind == .directory ? "folder" : "doc.text").foregroundStyle(Theme.textDim)
                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                }.padding(.horizontal, 6).padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain).help(entry.path)
                .accessibilityLabel(entry.kind == .directory ? "\(store.expanded.contains(entry.path) ? "Collapse" : "Expand") \(entry.name)" : "Open \(entry.name) read-only")
        case .loading:
            ProgressView("Loading").controlSize(.small).font(.caption).padding(8)
        case .more:
            Button("Load Next 100 Entries") { Task { await store.loadMore(row.directory) } }
                .font(.caption).padding(8).disabled(store.loading.contains(row.directory))
        case .error(let message):
            VStack(alignment: .leading, spacing: 7) {
                Text(message).font(.caption).foregroundStyle(Theme.onDevice).textSelection(.enabled)
                Button("Retry Directory") { Task { await store.retry(row.directory) } }.font(.caption)
            }.padding(8)
        }
    }
}

struct InspectorSourceFileView: View {
    @Environment(ArtifactInspectorState.self) private var inspector
    let store: InspectorFileStore
    let active: Bool
    @State private var refreshRevision = 0
    @State private var findRequest = 0
    private struct LoadKey: Hashable { let active: Bool; let revision: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Pinned File · Read Only", systemImage: "pin").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 4)
                    Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(store.loading).accessibilityLabel("Refresh file")
                }
                Text(store.path).font(Theme.mono(11)).textSelection(.enabled)
                if store.source.isUserWorkspace, let content = store.content, !store.loading, store.error == nil {
                    WorkspaceFileActions(source: store.source, path: store.path, sizeBytes: content.byteCount)
                    if ["pdf", "png", "jpg", "jpeg", "gif", "webp"].contains((store.path as NSString).pathExtension.lowercased()), content.byteCount <= 20_000_000 {
                        Button("Open Preview", systemImage: "doc.viewfinder") { inspector.openWorkspacePreview(source: store.source, path: store.path) }
                            .buttonStyle(.plain).font(.system(size: 11))
                    }
                }

                if let root = store.source.root {
                    Text("\(root.provider) · \(root.rootId.prefix(8)) · live observation")
                        .font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                }
                if let content = store.content, store.error == nil {
                    HStack {
                        Text("\(content.byteCount) bytes · \(content.lineCount.map { "\($0) lines" } ?? content.status.rawValue)")
                        Spacer(minLength: 4)
                        if content.text != nil {
                            Button("Find", systemImage: "magnifyingglass") { findRequest += 1 }
                            Button("Copy", systemImage: "doc.on.doc") { copy(content.text ?? "") }
                        }
                    }.font(.system(size: 10)).foregroundStyle(Theme.textDim).buttonStyle(.plain).disabled(store.loading)
                    Text("Observed \(content.observedAt.formatted(date: .abbreviated, time: .standard)) · version \(content.version.map { String($0.prefix(10)) } ?? "not read")")
                        .font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                    if store.changedSinceLastLoad {
                        Text("File changed since the previous observation. This tab now shows the refreshed bytes.")
                            .font(.caption).foregroundStyle(Theme.onDevice)
                    }
                }
            }.padding(12)
            Divider()
            ZStack {
                if let content = store.content, let text = content.text {
                    #if os(macOS)
                    InspectorSourceTextView(text: text, version: content.version ?? "", language: .resolve(path: store.path), findRequest: findRequest)
                        .opacity(store.loading || store.error != nil ? 0 : 1)
                        .allowsHitTesting(!store.loading && store.error == nil)
                        .accessibilityHidden(store.loading || store.error != nil)
                    #else
                    InspectorPortableSourceText(text: text, path: store.path)
                    #endif
                }
                if store.loading { ProgressView("Rechecking file access") }
                else if let error = store.error {
                    ContentUnavailableView("File Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let content = store.content, content.status != .text {
                    ContentUnavailableView(content.status == .binary ? "Binary File" : "File Too Large", systemImage: "doc",
                                           description: Text(store.source.isUserWorkspace ? "Use Download to save this file, or Open Preview for supported images and PDFs. Complete text previews are limited to 256 KiB and 12,000 lines." : "Only complete UTF-8 text up to 256 KiB and 12,000 lines is displayed. No truncated source is substituted."))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg).foregroundStyle(Theme.text)
        .task(id: LoadKey(active: active, revision: refreshRevision)) {
            if active { await store.activate() } else { store.suspend() }
        }
        .onDisappear { store.suspend() }
    }

    private func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

private struct InspectorPortableSourceText: View {
    let text: String
    let path: String
    @AppStorage(CodeTheme.preferenceKey) private var themeID = CodeTheme.Preset.fruitcake.rawValue
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            CodeSourceText(text: text, language: .resolve(path: path), size: 12, theme: .resolve(themeID)).padding()
        }.background(Color(hex: CodeTheme.resolve(themeID).background))
    }
}

#if os(macOS)
struct InspectorSourceTextView: NSViewRepresentable {
    let text: String
    let version: String
    let language: CodeLanguage
    let findRequest: Int
    @AppStorage(CodeTheme.preferenceKey) private var themeID = CodeTheme.Preset.fruitcake.rawValue

    final class Coordinator {
        var version: String?
        var text: String?
        var language: CodeLanguage?
        var theme: CodeTheme?
        var tokens: [CodeToken] = []
        var findRequest = 0
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor(Theme.bg)
        scroll.wantsLayer = true; scroll.layer?.masksToBounds = true
        let view = NSTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false; view.allowsUndo = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = NSColor(Theme.text); view.backgroundColor = NSColor(Theme.bg)
        view.textContainerInset = NSSize(width: 10, height: 12)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: 10_000_000, height: 10_000_000)
        view.textContainer?.containerSize = view.maxSize
        view.textContainer?.widthTracksTextView = false
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        scroll.documentView = view
        scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        scroll.verticalRulerView = InspectorLineRuler(scrollView: scroll, textView: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let theme = CodeTheme.resolve(themeID)
        let documentChanged = coordinator.version != version || coordinator.text != text
        let languageChanged = coordinator.language != language
        if documentChanged {
            coordinator.version = version
            coordinator.text = text
            view.string = text
            (scroll.verticalRulerView as? InspectorLineRuler)?.setText(text)
        }
        if documentChanged || languageChanged {
            coordinator.language = language
            coordinator.tokens = CodeSyntax.tokens(text, language: language)
        }
        if documentChanged || languageChanged || coordinator.theme != theme {
            coordinator.theme = theme
            CodeTextStorageStyle.apply(view, tokens: coordinator.tokens, theme: theme)
            scroll.backgroundColor = NSColor(Color(hex: theme.background))
            (scroll.verticalRulerView as? InspectorLineRuler)?.theme = theme
        }
        if documentChanged { view.sizeToFit() }
        if findRequest != context.coordinator.findRequest {
            context.coordinator.findRequest = findRequest
            scroll.window?.makeFirstResponder(view)
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.showFindInterface.rawValue
            view.performTextFinderAction(action)
        }
    }
}

private final class InspectorLineRuler: NSRulerView {
    private var starts = [0]
    var theme = CodeTheme.palette(.fruitcake) { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView; ruleThickness = 46
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: String) {
        starts = [0]
        for (index, scalar) in text.utf16.enumerated() where scalar == 10 { starts.append(index + 1) }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(Color(hex: theme.gutter)).setFill(); bounds.fill()
        guard let view = clientView as? NSTextView, let manager = view.layoutManager, let container = view.textContainer else { return }
        var visible = view.visibleRect
        visible.origin.x -= view.textContainerOrigin.x; visible.origin.y -= view.textContainerOrigin.y
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(Color(hex: theme.secondary)), .paragraphStyle: paragraph]
        manager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, glyphRange, _ in
            let character = manager.characterIndexForGlyph(at: glyphRange.location)
            var lower = 0, upper = self.starts.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if self.starts[middle] <= character { lower = middle + 1 } else { upper = middle }
            }
            let y = line.minY + view.textContainerOrigin.y - view.visibleRect.minY
            String(max(1, lower)).draw(in: NSRect(x: 0, y: y, width: self.ruleThickness - 8, height: line.height), withAttributes: attributes)
        }
        if manager.extraLineFragmentTextContainer != nil {
            let extra = manager.extraLineFragmentRect
            let y = extra.minY + view.textContainerOrigin.y - view.visibleRect.minY
            if y + extra.height >= 0 && y < bounds.height {
                String(starts.count).draw(in: NSRect(x: 0, y: y, width: ruleThickness - 8, height: extra.height), withAttributes: attributes)
            }
        }
    }
}
#endif
