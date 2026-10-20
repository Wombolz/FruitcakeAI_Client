import Foundation
import Testing
@testable import FruitcakeAi
#if os(macOS)
import SwiftUI
import AppKit
#endif

@MainActor private final class DirectoryFixture: InspectorDirectoryServing {
    var root = InspectorRoot(provider: "coding_checkout", rootId: "root", sessionId: "session", label: "Remote repository",
                             readOnly: true, byteLimit: 262144, lineLimit: 12000, entryLimit: 100)
    var directoryReads: [(String, Int)] = []
    var fileReads: [String] = []
    var entries: [String: [InspectorDirectoryEntry]] = [
        "": [.init(name: "src", path: "src", kind: .directory, sizeBytes: nil), .init(name: "README.md", path: "README.md", kind: .file, sizeBytes: 10)],
        "src": [.init(name: "file.py", path: "src/file.py", kind: .file, sizeBytes: 20)],
    ]
    var text = "def validate(value):\n    return value.strip()\n"
    var revision = "a"
    var deny = false
    var delayDirectory = false
    var directoryWaiter: CheckedContinuation<InspectorDirectoryPage, Error>?
    var delayFile = false
    var fileWaiter: CheckedContinuation<InspectorFileContent, Error>?
    var responseRoot: InspectorRoot?
    var wrongFilePath = false
    var wrongTextSize = false

    func source(context: InspectorContext = .coding("session")) -> InspectorDirectorySource {
        InspectorDirectorySource(context: context, root: root, provider: self)
    }
    func page(path: String, offset: Int = 0) -> InspectorDirectoryPage {
        let all = entries[path] ?? []
        let page = Array(all.dropFirst(offset).prefix(100))
        return .init(root: responseRoot ?? root, basis: "current_worktree", observedAt: Date(timeIntervalSince1970: 1_792_411_200), path: path,
                     version: String(repeating: revision, count: 64), entries: page,
                     nextOffset: offset + page.count < all.count ? offset + page.count : nil)
    }
    func file(path: String) -> InspectorFileContent {
        .init(root: responseRoot ?? root, basis: "current_worktree", observedAt: Date(timeIntervalSince1970: 1_792_411_200),
              path: wrongFilePath ? "other.py" : path, status: .text,
              byteCount: text.utf8.count + (wrongTextSize ? 1 : 0), version: String(repeating: revision, count: 64), text: text,
              lineCount: text.components(separatedBy: "\n").count)
    }
    func inspectorDirectory(root: InspectorRoot, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage {
        directoryReads.append((path, offset))
        if deny { throw CodingClientError(code: "workspace_denied", message: "Grant revoked", status: 403) }
        if delayDirectory { return try await withCheckedThrowingContinuation { directoryWaiter = $0 } }
        return page(path: path, offset: offset)
    }
    func inspectorFile(root: InspectorRoot, path: String) async throws -> InspectorFileContent {
        fileReads.append(path)
        if deny { throw CodingClientError(code: "workspace_denied", message: "Grant revoked", status: 403) }
        if delayFile { return try await withCheckedThrowingContinuation { fileWaiter = $0 } }
        return file(path: path)
    }
}

@Suite @MainActor struct InspectorFileTests {
    @Test func lazyExpansionAndNavigationRecheckTheSameBackendOwnedRoot() async throws {
        let api = DirectoryFixture(), state: InspectorExplorerStore
        state = InspectorExplorerStore(source: api.source())
        await state.activate()
        #expect(api.directoryReads.map(\.0) == [""])
        #expect(state.rows.count == 2 && state.directories["src"] == nil)
        await state.toggle("src")
        #expect(api.directoryReads.map(\.0) == ["", "src"])
        #expect(state.rows.map(\.id) == ["src", "src/file.py", "README.md"])
        state.suspend()
        await state.activate()
        #expect(api.directoryReads.map(\.0) == ["", "src", "", "src"])
        #expect(state.expanded.contains("src"))
        await state.toggle("src")
        #expect(state.directories["src"] == nil && !state.expanded.contains("src"))
        state.suspend()
    }

    @Test func fileTabsAreRootScopedPersistentAndDoNotReplaceReviewsOrOtherFiles() {
        let api = DirectoryFixture(), inspector = ArtifactInspectorState()
        inspector.setDestination("coding"); inspector.setCodingSession("session", active: true)
        let source = api.source()
        inspector.openExplorer(source)
        let explorer = inspector.selectedTab?.id
        inspector.openSourceFile(source, path: "src/file.py")
        let file = inspector.selectedTab?.id
        inspector.openSourceFile(source, path: "src/file.py")
        #expect(inspector.tabs.count == 2 && inspector.selectedTab?.id == file)
        let other = InspectorRoot(provider: "coding_checkout", rootId: "different-root", sessionId: "session", label: "Other",
                                  readOnly: true, byteLimit: 262144, lineLimit: 12000, entryLimit: 100)
        let otherSource = InspectorDirectorySource(context: .coding("session"), root: other, provider: api)
        inspector.openSourceFile(otherSource, path: "src/file.py")
        #expect(inspector.tabs.count == 3 && inspector.selectedTab?.id != file)
        inspector.select(explorer!)
        #expect(inspector.selectedTab?.explorer != nil)
        #expect(api.fileReads.isEmpty && api.directoryReads.isEmpty)
        inspector.close()
        inspector.show()
        #expect(inspector.selectedTab?.id == explorer)
        inspector.setDestination("chat")
        let count = inspector.allTabs.count
        inspector.openExplorer(source)
        #expect(inspector.allTabs.count == count && inspector.context != .coding("session"))
    }

    @Test func deniedAndMismatchedProviderContentCannotBypassTheSharedViewer() async throws {
        let api = DirectoryFixture(), source: InspectorDirectorySource
        source = api.source()
        for path in ["../outside", "/Users/someone/private", "src//file.py", "src/./file.py"] {
            await #expect(throws: CodingClientError.self) { try await source.file(path: path) }
        }
        #expect(api.fileReads.isEmpty)
        api.responseRoot = InspectorRoot(provider: "coding_checkout", rootId: "wrong-root", sessionId: "session", label: "Other",
                                        readOnly: true, byteLimit: 262144, lineLimit: 12000, entryLimit: 100)
        await #expect(throws: CodingClientError.self) { try await source.directory(path: "") }
        api.responseRoot = nil
        api.wrongFilePath = true
        await #expect(throws: CodingClientError.self) { try await source.file(path: "src/file.py") }
        api.wrongFilePath = false; api.wrongTextSize = true
        await #expect(throws: CodingClientError.self) { try await source.file(path: "src/file.py") }
        api.wrongTextSize = false
        api.entries[""] = [.init(name: "escape", path: "../escape", kind: .file, sizeBytes: 10)]
        await #expect(throws: CodingClientError.self) { try await source.directory(path: "") }
    }

    @Test func revocationClearsCachedDirectoryAndFileContentsWithoutFallback() async {
        let api = DirectoryFixture(), explorer: InspectorExplorerStore, file: InspectorFileStore
        explorer = InspectorExplorerStore(source: api.source())
        file = InspectorFileStore(source: api.source(), path: "src/file.py")
        await explorer.activate(); await file.activate()
        #expect(!explorer.directories.isEmpty && file.content?.text != nil)
        api.deny = true
        await explorer.activate(); await file.activate()
        #expect(explorer.directories.isEmpty && explorer.errors[""] != nil)
        #expect(file.content == nil && file.error != nil)
        explorer.suspend(); file.suspend()
    }

    @Test func closingATabDiscardsLateReadResults() async {
        let api = DirectoryFixture(), file: InspectorFileStore, explorer: InspectorExplorerStore
        file = InspectorFileStore(source: api.source(), path: "src/file.py")
        explorer = InspectorExplorerStore(source: api.source())
        api.delayFile = true; api.delayDirectory = true
        let reading = Task { await file.activate() }
        let listing = Task { await explorer.activate() }
        while api.fileWaiter == nil || api.directoryWaiter == nil { await Task.yield() }
        file.suspend(); explorer.suspend()
        api.fileWaiter?.resume(returning: api.file(path: "src/file.py"))
        api.directoryWaiter?.resume(returning: api.page(path: ""))
        await reading.value; await listing.value
        #expect(file.content == nil && file.error == nil && !file.loading)
        #expect(explorer.directories.isEmpty && explorer.errors.isEmpty && explorer.loading.isEmpty)
    }

    @Test func fileRefreshDisclosesChangedVersionAndPreservesCompleteLiteralText() async {
        let api = DirectoryFixture(), store: InspectorFileStore
        store = InspectorFileStore(source: api.source(), path: "src/file.py")
        api.text = "<script>notExecuted()</script>\n**not Markdown**\n"
        await store.activate()
        #expect(store.content?.text == api.text && !store.changedSinceLastLoad)
        store.suspend(); api.revision = "b"; api.text = "new complete source\n"
        await store.activate()
        #expect(store.changedSinceLastLoad && store.content?.text == api.text)
        #expect(api.fileReads == ["src/file.py", "src/file.py"])
        store.suspend()
    }

    @Test func paginationAppendsUniqueBoundedEntriesAndRejectsVersionChanges() async {
        let api = DirectoryFixture(), store: InspectorExplorerStore
        api.entries[""] = (0..<110).map { .init(name: "\($0).txt", path: "\($0).txt", kind: .file, sizeBytes: 1) }
        store = InspectorExplorerStore(source: api.source())
        await store.activate()
        #expect(store.directories[""]?.entries.count == 100)
        await store.loadMore("")
        #expect(store.directories[""]?.entries.count == 110 && store.directories[""]?.nextOffset == nil)
        await store.activate(); api.revision = "b"
        await store.loadMore("")
        #expect(store.errors[""] != nil && store.directories[""]?.entries.count == 100)
        store.suspend()
    }

    @Test func unavailableDirectoryProvidersDoNotInferAccessFromChatProjects() async {
        let inspector = ArtifactInspectorState()
        inspector.setChatSession(10, active: true)
        inspector.openExplorer(InspectorDirectorySource(unavailable: .chat(10), reason: "No provider available"))
        let store = inspector.selectedTab?.explorer
        #expect(store?.source.root == nil && store?.source.unavailableReason != nil)
        await #expect(throws: CodingClientError.self) { try await store!.source.directory(path: "") }
        #expect(inspector.context == .chat(10))
    }

    #if os(macOS)
    @Test(arguments: [300, 600]) func renderSharedExplorerAndLiteralSource(width: Int) async throws {
        let api = DirectoryFixture()
        let source = api.source(context: .chat(1))
        let explorer = InspectorExplorerStore(source: source)
        let file = InspectorFileStore(source: source, path: "src/file.py")
        await explorer.activate(); await explorer.toggle("src"); await file.activate()
        for (name, view) in [("tree", AnyView(InspectorExplorerView(store: explorer, active: false))),
                             ("source", AnyView(InspectorSourceFileView(store: file, active: false)))] {
            let host = NSHostingView(rootView: view.environment(ArtifactInspectorState())
                .frame(width: CGFloat(width), height: 460).environment(\.colorScheme, .dark))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 460)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-explorer-\(name)-\(width).png")
            try png.write(to: url)
            print("EXPLORER_FIXTURE: \(url.path)")
            #expect(png.count > 2000)
        }
        explorer.suspend(); file.suspend()
    }
    #endif
}
