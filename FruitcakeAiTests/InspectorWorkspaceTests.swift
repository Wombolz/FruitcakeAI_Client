import Foundation
import Testing
@testable import FruitcakeAi
#if os(macOS)
import SwiftUI
import AppKit
#endif

@Suite @MainActor struct InspectorWorkspaceTests {
    private func artifact(_ path: String = "report.md", session: Int? = 1, title: String = "Report") -> ArtifactReference {
        .init(id: UUID().uuidString, path: path, filename: path, mediaType: "text/markdown", title: title, origin: .chat(sessionID: session))
    }

    @Test func identityUsesProviderOriginAndPathNotTitleOrMessageID() {
        let state = ArtifactInspectorState()
        state.setChatSession(1, active: true)
        state.open(artifact())
        let original = state.selectedTab?.id
        state.open(artifact(title: "Another label for the same resource"))
        #expect(state.tabs.count == 1 && state.selectedTab?.id == original)
        state.open(artifact("other.md"))
        #expect(state.tabs.count == 2)
        state.setChatSession(2, active: true)
        #expect(state.tabs.isEmpty && !state.isVisible)
        state.open(artifact(session: 2))
        #expect(state.tabs.count == 1 && state.selectedTab?.id != original)
        state.setChatSession(1, active: true)
        #expect(state.tabs.count == 2 && state.isVisible)
    }

    @Test func hideRetainsTabsCloseReleasesTabAndReopenUsesFreshViewIdentity() throws {
        let state = ArtifactInspectorState()
        state.open(artifact())
        let id = try #require(state.selectedTab?.id)
        state.close()
        #expect(!state.isVisible && state.tabs.count == 1)
        state.show()
        #expect(state.isVisible && state.selectedTab?.id == id)
        state.closeTab(id)
        #expect(!state.isVisible && state.tabs.isEmpty && state.canReopen)
        state.show()
        #expect(state.isVisible && state.tabs.count == 1)
        #expect(state.selectedTab?.id != id && !state.canReopen)
    }

    @Test func closeOthersOverflowAndSelectionRemainDeterministic() throws {
        let state = ArtifactInspectorState()
        for index in 0..<12 { state.open(artifact("\(index).md")) }
        let chosen = state.tabs[4].id
        state.select(chosen)
        state.open(artifact("overflow.md"))
        #expect(state.tabs.count == 12 && state.selectedTab?.id == chosen && state.notice != nil)
        state.closeOthers(chosen)
        #expect(state.tabs.count == 1 && state.selectedTab?.id == chosen)
        state.reopenClosed()
        #expect(state.tabs.count == 2 && state.selectedTab?.id != chosen)
        let current = state.selectedTab?.id
        state.select(UUID())
        #expect(state.selectedTab?.id == current)
    }

    @Test func accountOrServerChangesClearBothOpenAndClosedReferences() {
        let state = ArtifactInspectorState()
        let first = InspectorAccountScope(server: "http://localhost:8000", userID: 1)
        state.configure(account: first)
        state.open(artifact())
        let id = state.selectedTab!.id
        state.closeTab(id)
        state.configure(account: first)
        #expect(state.canReopen)
        state.configure(account: .init(server: first.server, userID: 2))
        #expect(state.allTabs.isEmpty && !state.canReopen)
        state.open(artifact())
        state.configure(account: .init(server: "http://localhost:9000", userID: 2))
        #expect(state.allTabs.isEmpty && !state.canReopen)
        state.open(artifact())
        state.configure(account: nil)
        state.open(artifact())
        #expect(state.allTabs.isEmpty && !state.isVisible)
    }

    @Test func implicitChatOriginResolvesToConversationAndInactiveNavigationCannotStealFocus() {
        let state = ArtifactInspectorState()
        state.setChatSession(10, active: true)
        state.open(artifact(session: nil))
        #expect(state.selected?.origin == .chat(sessionID: 10))
        let chatID = state.selectedTab?.id
        state.setDestination("tasks")
        let task = ArtifactReference(id: "task", path: "report.md", filename: "report.md", mediaType: "text/plain", title: "Report", origin: .task(taskID: 3, runID: 4))
        state.open(task)
        state.setChatSession(11, active: false)
        #expect(state.context == .task(3, 4) && state.selected?.origin == task.origin)
        state.setDestination("chat")
        #expect(state.context == .chat(11) && state.tabs.isEmpty)
        state.setChatSession(10, active: true)
        #expect(state.selectedTab?.id == chatID)
        state.setDestination("tasks")
        #expect(state.selected?.origin == task.origin)
    }

    @Test func closedHistoryAndOpenContentHaveGlobalBounds() {
        let state = ArtifactInspectorState()
        for index in 0..<32 {
            state.setChatSession(index, active: true)
            state.open(artifact(session: index))
        }
        #expect(state.allTabs.count == 32)
        state.open(artifact("extra.md", session: 31))
        #expect(state.allTabs.count == 32 && state.notice != nil)
        state.setChatSession(33, active: true)
        state.open(artifact(session: 33))
        #expect(state.tabs.isEmpty && state.isVisible && state.notice != nil)
        for index in 0..<32 {
            state.setChatSession(index, active: true)
            state.closeTab(state.tabs[0].id)
        }
        #expect(state.allTabs.isEmpty)
        state.setChatSession(100, active: true)
        state.open(artifact(session: 100))
        state.closeTab(state.tabs[0].id)
        state.setChatSession(0, active: true)
        #expect(!state.canReopen)
    }

    #if os(macOS)
    @Test(arguments: [300, 560]) func renderSharedTabsAtNarrowAndWideWidths(width: Int) throws {
        let state = ArtifactInspectorState()
        state.setChatSession(1, active: true)
        for index in 1...6 { state.open(artifact("document-\(index).md", title: "Long document title \(index)")) }
        state.select(state.tabs[0].id)
        state.close() // Synthetic chrome fixture: no server/token/content request.
        let host = NSHostingView(rootView: WorkspaceInspectorView()
            .environment(state).environment(AuthManager())
            .frame(width: CGFloat(width), height: 500).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 500)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-inspector-tabs-\(width).png")
        try png.write(to: url)
        print("INSPECTOR_FIXTURE: \(url.path)")
        #expect(png.count > 2000)
    }
    #endif
}
