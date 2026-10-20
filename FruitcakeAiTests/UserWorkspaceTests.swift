import Foundation
import Testing
#if os(macOS)
import SwiftUI
import AppKit
#endif
@testable import FruitcakeAi

@MainActor private final class UserWorkspaceFixture: UserWorkspaceServing {
    var root = InspectorRoot(provider: "user_workspace", rootId: String(repeating: "a", count: 64), sessionId: nil, userId: 7,
                             label: "My Workspace", readOnly: true, byteLimit: 262144, lineLimit: 12000, entryLimit: 100)
    var reads: [String] = []
    var waiter: CheckedContinuation<InspectorFileContent, Error>?
    var delay = false
    var mismatchedBasis = false
    func workspaceExplorerRoot() async throws -> InspectorRoot { root }
    func workspaceDownload(rootID: String, path: String) async throws -> Data { Data("not sent to model".utf8) }
    func inspectorDirectory(root: InspectorRoot, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage {
        reads.append(path)
        return .init(root: self.root, basis: "user_workspace", observedAt: .now, path: path, version: String(repeating: "b", count: 64),
            entries: [.init(name: "report.md", path: "report.md", kind: .file, sizeBytes: 9)], nextOffset: nil)
    }
    func value(path: String) -> InspectorFileContent {
        .init(root: root, basis: mismatchedBasis ? "current_worktree" : "user_workspace", observedAt: .now, path: path,
              status: .text, byteCount: 9, version: String(repeating: "c", count: 64), text: "# Report\n", lineCount: 2)
    }
    func inspectorFile(root: InspectorRoot, path: String) async throws -> InspectorFileContent {
        reads.append(path)
        if delay { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return value(path: path)
    }
}

@Suite @MainActor struct UserWorkspaceTests {
    private let account = InspectorAccountScope(server: "https://fruitcake.test", userID: 7)

    @Test func userWorkspaceIsIndependentOfCodingButOpeningFilesNeverStagesChatContent() async throws {
        let api = UserWorkspaceFixture(), inspector = ArtifactInspectorState()
        inspector.configure(account: account); inspector.setChatSession(10, active: true)
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(10), currentAccount: { inspector.account })
        inspector.openExplorer(source)
        #expect(inspector.selectedTab?.resource.title == "My Workspace")
        let page = try await source.directory(path: "")
        #expect(page.entries.map(\.name) == ["report.md"])
        inspector.openSourceFile(source, path: "report.md")
        #expect(inspector.workspaceDraftAttachment == nil)
        let file = try #require(inspector.selectedTab?.file)
        await file.activate()
        #expect(file.content?.text == "# Report\n")
        #expect(inspector.workspaceDraftAttachment == nil)
        inspector.stageWorkspaceAttachment(source: source, path: "report.md", sizeBytes: 9)
        #expect(inspector.workspaceDraftAttachment?.sessionID == 10)
        #expect(inspector.takeWorkspaceAttachment(sessionID: 11, account: account) == nil)
        #expect(inspector.takeWorkspaceAttachment(sessionID: 10, account: account)?.path == "report.md")
        #expect(inspector.takeWorkspaceAttachment(sessionID: 10, account: account) == nil)
        file.suspend()
    }

    @Test func rootProviderOwnerAndBasisAreNotInterchangeable() async throws {
        let api = UserWorkspaceFixture()
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(1), currentAccount: { self.account })
        api.mismatchedBasis = true
        await #expect(throws: CodingClientError.self) { try await source.file(path: "report.md") }
        api.root.userId = 8
        await #expect(throws: CodingClientError.self) {
            try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(1), currentAccount: { self.account })
        }
        await #expect(throws: CodingClientError.self) {
            try await UserWorkspaceProvider.source(api: api, account: account, context: .coding("repo"), currentAccount: { self.account })
        }
    }

    @Test func attachmentToolPathsPreserveRealWorkspaceSubfolders() async throws {
        let api = UserWorkspaceFixture(), inspector = ArtifactInspectorState()
        inspector.configure(account: account); inspector.setChatSession(10, active: true)
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(10), currentAccount: { inspector.account })
        for path in ["report.txt", "workspace/report.txt", "workspace/7/report.txt"] {
            inspector.stageWorkspaceAttachment(source: source, path: path, sizeBytes: 9)
            let attachment = try #require(inspector.takeWorkspaceAttachment(sessionID: 10, account: account))
            #expect(attachment.path == path)
            #expect(attachment.toolPath == "workspace/7/\(path)")
        }
        for path in ["report.txt ", "workspace/report.txt\u{00a0}"] {
            #expect(!WorkspaceDraftAttachment.supportsToolReference(path))
            inspector.stageWorkspaceAttachment(source: source, path: path, sizeBytes: 9)
            #expect(inspector.workspaceDraftAttachment == nil)
        }
    }

    @Test func accountChangeRejectsDelayedReadAndDoesNotOpenAnotherConversation() async throws {
        let api = UserWorkspaceFixture(), inspector = ArtifactInspectorState()
        inspector.configure(account: account); inspector.setChatSession(10, active: true)
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(10), currentAccount: { inspector.account })
        api.delay = true
        let reading = Task { try await source.file(path: "report.md") }
        while api.waiter == nil { await Task.yield() }
        inspector.configure(account: .init(server: "https://other.test", userID: 7))
        api.waiter?.resume(returning: api.value(path: "report.md"))
        await #expect(throws: CodingClientError.self) { try await reading.value }
        #expect(inspector.allTabs.isEmpty && inspector.workspaceDraftAttachment == nil)
        inspector.setChatSession(11, active: true)
        inspector.openExplorer(source)
        #expect(inspector.tabs.isEmpty)
    }

    @Test func attachmentsAndPreviewsCannotBeStagedAcrossContextsOrByRepositoryRoots() async throws {
        let api = UserWorkspaceFixture(), inspector = ArtifactInspectorState()
        inspector.configure(account: account); inspector.setChatSession(10, active: true)
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(10), currentAccount: { inspector.account })
        inspector.stageWorkspaceAttachment(source: source, path: "../outside", sizeBytes: 9)
        #expect(inspector.workspaceDraftAttachment == nil)
        inspector.openWorkspacePreview(source: source, path: "page.html")
        #expect(inspector.tabs.isEmpty)
        inspector.openWorkspacePreview(source: source, path: "report.pdf")
        #expect(inspector.selected?.workspaceRootID == api.root.rootId)
        #expect(inspector.selected?.workspaceOwnerID == 7)
        inspector.stageWorkspaceAttachment(source: source, path: "report.md", sizeBytes: 9)
        inspector.setChatSession(11, active: true)
        #expect(inspector.workspaceDraftAttachment == nil)
        inspector.stageWorkspaceAttachment(source: source, path: "report.md", sizeBytes: 9)
        #expect(inspector.workspaceDraftAttachment == nil)
    }
    #if os(macOS)
    @Test(arguments: [300, 600]) func renderWorkspaceBrowserAndExplicitFileActions(width: Int) async throws {
        let api = UserWorkspaceFixture(), inspector = ArtifactInspectorState()
        inspector.configure(account: account); inspector.setChatSession(10, active: true)
        let source = try await UserWorkspaceProvider.source(api: api, account: account, context: .chat(10), currentAccount: { inspector.account })
        let tree = InspectorExplorerStore(source: source), file = InspectorFileStore(source: source, path: "report.md")
        await tree.activate(); await file.activate()
        for (name, view) in [("tree", AnyView(InspectorExplorerView(store: tree, active: false))),
                             ("file", AnyView(InspectorSourceFileView(store: file, active: false)))] {
            let host = NSHostingView(rootView: view.environment(inspector).environment(AuthManager())
                .frame(width: CGFloat(width), height: 540).environment(\.colorScheme, .dark))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 540)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-my-workspace-\(name)-\(width).png")
            try data.write(to: url)
            print("MY_WORKSPACE_FIXTURE: \(url.path)")
            #expect(data.count > 2000)
        }
        tree.suspend(); file.suspend()
    }
    #endif

}
