import SwiftUI

// One host owns selection/focus. Providers own requests, provenance and access.
struct WorkspaceInspectorView: View {
    @Environment(ArtifactInspectorState.self) private var inspector

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Theme.strokeUp).frame(height: 1)
            if let notice = inspector.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.caption)
                    Spacer(minLength: 4)
                    Button { inspector.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss inspector notice")
                }.foregroundStyle(Theme.textDim).padding(10)
            }
            ZStack {
                ForEach(inspector.allTabs) { tab in
                    let active = inspector.isVisible && inspector.selectedTab?.id == tab.id
                    tabContent(tab, active: active)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                        .zIndex(active ? 1 : 0)
                }
                if inspector.selectedTab == nil {
                    ContentUnavailableView("Nothing Open", systemImage: "sidebar.right",
                                           description: Text("Open an artifact, Changes or a saved review to inspect it here."))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg).foregroundStyle(Theme.text)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 3) {
                        ForEach(inspector.tabs) { tab in
                            HStack(spacing: 6) {
                                Button { inspector.select(tab.id) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: tab.resource.symbol)
                                        Text(tab.resource.title).lineLimit(1).truncationMode(.middle)
                                        if tab.review?.selected?.isActive == true {
                                            Circle().fill(Theme.codeAccent).frame(width: 5, height: 5).accessibilityLabel("Review in progress")
                                        }
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select \(tab.resource.title)")
                                .help(tab.resource.identity.resource)
                                .accessibilityAddTraits(inspector.selectedTab?.id == tab.id ? .isSelected : [])
                                Button { inspector.closeTab(tab.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                }.buttonStyle(.plain).accessibilityLabel("Close \(tab.resource.title) tab")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .frame(maxWidth: 190)
                            .background(inspector.selectedTab?.id == tab.id ? Theme.field : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(inspector.selectedTab?.id == tab.id ? Theme.strokeUp : .clear, lineWidth: 1))
                            .contextMenu {
                                Button("Close Tab") { inspector.closeTab(tab.id) }
                                Button("Close Other Tabs") { inspector.closeOthers(tab.id) }
                            }
                            .id(tab.id)
                        }
                    }.padding(5)
                }.scrollIndicators(.hidden)
                    .onChange(of: inspector.selectedTab?.id, initial: true) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
            }
            Menu {
                ForEach(inspector.tabs) { tab in
                    Button { inspector.select(tab.id) } label: {
                        Label(tab.resource.title, systemImage: inspector.selectedTab?.id == tab.id ? "checkmark" : tab.resource.symbol)
                    }
                }
                Divider()
                Button("Reopen Closed Tab") { inspector.reopenClosed() }.disabled(!inspector.canReopen)
                if let id = inspector.selectedTab?.id {
                    Button("Close Other Tabs") { inspector.closeOthers(id) }
                    Button("Close Selected Tab") { inspector.closeTab(id) }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Inspector tabs")
            Button { inspector.close() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain).help("Hide inspector; keep open tabs")
                .accessibilityLabel("Hide inspector")
                .padding(.trailing, 10)
        }.frame(height: 42)
    }

    @ViewBuilder private func tabContent(_ tab: InspectorTab, active: Bool) -> some View {
        switch tab.resource {
        case .explorer:
            if let explorer = tab.explorer { InspectorExplorerView(store: explorer, active: active) }
        case .sourceFile:
            if let file = tab.file { InspectorSourceFileView(store: file, active: active) }
        case .artifact(let artifact):
            ArtifactInspectorView(artifact: artifact, isActive: active)
        #if os(macOS)
        case .changes(let workspace, let sessionID):
            if workspace.selectedId == sessionID {
                CodingLiveRepositoryReview(store: workspace, close: { inspector.closeTab(tab.id) },
                                           openFile: { inspector.openChangedFile(workspace, sessionID: sessionID, path: $0.path) },
                                           isActive: active)
            }
        case .review(let workspace, let sessionID, let reviewID, let captureID):
            if let review = tab.review {
                InspectorReviewContent(workspace: workspace, review: review, sessionID: sessionID,
                                       reviewID: reviewID, captureID: captureID, active: active,
                                       close: { inspector.closeTab(tab.id) })
            }
        case .changedFile(let workspace, let sessionID, let path):
            InspectorChangedFileContent(workspace: workspace, sessionID: sessionID, path: path, active: active)
        #else
        case .changes, .review, .changedFile:
            ContentUnavailableView("Available on Mac", systemImage: "desktopcomputer")
        #endif
        }
    }
}

#if os(macOS)
private struct InspectorReviewContent: View {
    let workspace: CodingWorkspaceStore
    let review: CodingAIReviewStore
    let sessionID: String
    let reviewID: String
    let captureID: String
    let active: Bool
    let close: () -> Void
    @State private var validating = true
    @State private var refreshRevision = 0
    private struct LoadKey: Hashable { let active: Bool; let revision: Int }

    var body: some View {
        ZStack {
            CodingAIReviewInspector(workspace: workspace, close: close,
                                    reviewOverride: review, expectedReviewID: reviewID, refreshAction: { refreshRevision += 1 })
                .opacity(!validating && review.selected?.id == reviewID && review.selected?.captureId == captureID ? 1 : 0)
                .allowsHitTesting(!validating && review.selected?.id == reviewID && review.selected?.captureId == captureID)
            if validating { ProgressView("Loading saved review") }
            else if review.selected?.id != reviewID || review.selected?.captureId != captureID {
                VStack(spacing: 12) {
                    ContentUnavailableView("Review Unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(review.error ?? "The saved review or capture is no longer accessible."))
                    Button("Retry") { refreshRevision += 1 }
                }
            }
        }
        .task(id: LoadKey(active: active, revision: refreshRevision)) {
            if active, !Task.isCancelled { await reload() } else { review.suspend() }
        }
        .onDisappear { review.suspend() }
    }

    private func reload() async {
        guard active, !Task.isCancelled, workspace.selectedId == sessionID else { return }
        validating = true
        await review.resume(reviewID: reviewID)
        guard !Task.isCancelled, active else { review.suspend(); return }
        if review.selected?.captureId != captureID { review.reset(sessionId: sessionID) }
        if review.error != nil, review.selected != nil {
            let message = review.error
            review.reset(sessionId: sessionID)
            review.error = message
        }
        validating = false
    }
}

private struct InspectorChangedFileContent: View {
    let workspace: CodingWorkspaceStore
    let sessionID: String
    let path: String
    let active: Bool
    @State private var diff: CodingRepositoryDiff?
    @State private var error: String?
    @State private var loading = false
    @State private var refreshRevision = 0
    private struct LoadKey: Hashable { let active: Bool; let revision: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Changed File", systemImage: "doc.text.magnifyingglass").font(.headline)
                Text(path).font(Theme.mono(11)).textSelection(.enabled)
                Text("Live checkout observation, not a captured review or full-source browser.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                if loading { ProgressView("Reading file changes") }
                else if let error { Text(error).font(.caption).foregroundStyle(Theme.onDevice) }
                else if let diff {
                    Text("Observed \(diff.observedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                    Text("Comparisons: " + diff.sections.map { $0.kind.capitalized }.joined(separator: ", "))
                        .font(.system(size: 12))
                    Button("View Diff Above Conversation", systemImage: "arrow.left.arrow.right") {
                        workspace.showObservedDiff(diff, sessionID: sessionID)
                    }.buttonStyle(CodingActionStyle())
                }
                Button("Refresh") { refreshRevision += 1 }.disabled(loading)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }.task(id: LoadKey(active: active, revision: refreshRevision)) { if active, !Task.isCancelled { await reload() } }
    }

    private func reload() async {
        guard active, !Task.isCancelled, workspace.selectedId == sessionID else { return }
        diff = nil; error = nil; loading = true
        defer { loading = false }
        do {
            let value = try await workspace.inspectChangedFile(sessionID: sessionID, path: path)
            guard !Task.isCancelled, active else { return }
            diff = value
        } catch is CancellationError {} catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
#endif
