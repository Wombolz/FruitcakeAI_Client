#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FruitcakeAi

@MainActor
private func scrollGeometry(height: CGFloat = 1000, viewport: CGFloat = 400, offset: CGFloat = 600, width: CGFloat = 700) -> CodingTranscriptGeometry {
    CodingTranscriptGeometry(contentSize: CGSize(width: width, height: height),
        viewportSize: CGSize(width: width, height: viewport), offsetY: offset,
        bottomDistance: max(0, height - offset - viewport))
}

@Test @MainActor func codingTranscriptFollowsStreamingHeightWithoutScrollFeedback() {
    let scroll = CodingTranscriptScrollState()
    let bottom = scrollGeometry()
    let growing = scrollGeometry(height: 1200)
    scroll.geometryChanged(from: bottom, to: growing)
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 1)
    let pinned = scrollGeometry(height: 1200, offset: 800)
    scroll.geometryChanged(from: growing, to: pinned)
    scroll.geometryChanged(from: pinned, to: pinned)
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 1)
}

@Test @MainActor func codingTranscriptKeepsBottomWhenDiffOpensClosesOrChangesWidth() {
    let scroll = CodingTranscriptScrollState()
    let bottom = scrollGeometry()
    let drawer = scrollGeometry(viewport: 180)
    scroll.geometryChanged(from: bottom, to: drawer)
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 1)
    let pinned = scrollGeometry(viewport: 180, offset: 820)
    scroll.geometryChanged(from: drawer, to: pinned)
    let expanded = scrollGeometry(viewport: 600, offset: 400)
    scroll.geometryChanged(from: pinned, to: expanded)
    scroll.geometryChanged(from: expanded, to: scrollGeometry(viewport: 600, offset: 400, width: 500))
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 3)
}

@Test @MainActor func codingTranscriptDoesNotPullReaderDownDuringStreamingOrResize() {
    let scroll = CodingTranscriptScrollState()
    let bottom = scrollGeometry()
    let reading = scrollGeometry(offset: 200)
    scroll.phaseChanged(from: .idle, to: .interacting, geometry: bottom)
    scroll.geometryChanged(from: bottom, to: reading)
    scroll.phaseChanged(from: .interacting, to: .idle, geometry: reading)
    #expect(!scroll.followsBottom)
    let growing = scrollGeometry(height: 1200, offset: 200)
    scroll.geometryChanged(from: reading, to: growing)
    scroll.geometryChanged(from: growing, to: scrollGeometry(height: 1200, viewport: 180, offset: 200))
    #expect(!scroll.followsBottom)
    #expect(scroll.pinRevision == 0)
    scroll.jumpToLatest()
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 1)
}

@Test @MainActor func codingTranscriptHonorsKeyboardScrollAndResumesAtBottom() {
    let scroll = CodingTranscriptScrollState()
    let bottom = scrollGeometry()
    let reading = scrollGeometry(offset: 200)
    scroll.geometryChanged(from: bottom, to: reading)
    #expect(!scroll.followsBottom)
    scroll.geometryChanged(from: reading, to: bottom)
    #expect(scroll.followsBottom)
    #expect(scroll.pinRevision == 0)
}

@Observable @MainActor
private final class TranscriptLayoutFixture {
    let scroll = CodingTranscriptScrollState()
    var rows = 40
    var latestRunID = "first"
}

private struct TranscriptLayoutView: View {
    let fixture: TranscriptLayoutFixture
    var body: some View {
        CodingTranscriptScrollView(scroll: fixture.scroll, latestRunID: fixture.latestRunID) {
            LazyVStack(spacing: 0) {
                ForEach(0..<fixture.rows, id: \.self) { index in
                    Text("Transcript entry \(index)").frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }.background(Theme.bg)
    }
}

@MainActor
private func firstScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for child in view.subviews {
        if let scroll = firstScrollView(in: child) { return scroll }
    }
    return nil
}

@MainActor
private func settleLayout(_ host: NSView, until condition: () -> Bool) async throws {
    for _ in 0..<150 {
        host.layoutSubtreeIfNeeded()
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Transcript layout did not settle")
}

@Test @MainActor func actualTranscriptScrollViewFollowsGrowthAndDrawerResize() async throws {
    let fixture = TranscriptLayoutFixture()
    let host = NSHostingView(rootView: TranscriptLayoutView(fixture: fixture))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func distanceToBottom() -> CGFloat {
        guard let scroll = firstScrollView(in: host), let document = scroll.documentView else { return .infinity }
        return max(0, document.frame.height - scroll.contentView.bounds.maxY)
    }
    try await settleLayout(host) { firstScrollView(in: host)?.documentView?.frame.height ?? 0 > 2000 && distanceToBottom() <= 2 }
    #expect(distanceToBottom() <= 2)
    fixture.rows = 45
    try await settleLayout(host) { firstScrollView(in: host)?.documentView?.frame.height ?? 0 > 2600 && distanceToBottom() <= 2 }
    #expect(distanceToBottom() <= 2)
    window.setContentSize(NSSize(width: 700, height: 220))
    try await settleLayout(host) { firstScrollView(in: host)?.contentView.bounds.height ?? 0 < 250 && distanceToBottom() <= 2 }
    #expect(fixture.scroll.followsBottom)
    #expect(distanceToBottom() <= 2)
    window.setContentSize(NSSize(width: 700, height: 500))
    try await settleLayout(host) { firstScrollView(in: host)?.contentView.bounds.height ?? 0 > 450 && distanceToBottom() <= 2 }
    #expect(distanceToBottom() <= 2)
    let nativeScroll = try #require(firstScrollView(in: host))
    nativeScroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
    nativeScroll.reflectScrolledClipView(nativeScroll.contentView)
    try await settleLayout(host) { !fixture.scroll.followsBottom }
    fixture.rows = 48
    try await settleLayout(host) { nativeScroll.documentView?.frame.height ?? 0 > 2800 }
    #expect(abs(nativeScroll.contentView.bounds.minY - 500) <= 2)
    window.setContentSize(NSSize(width: 700, height: 220))
    try await settleLayout(host) { nativeScroll.contentView.bounds.height < 250 }
    #expect(!fixture.scroll.followsBottom)
    #expect(abs(nativeScroll.contentView.bounds.minY - 500) <= 2)
    fixture.scroll.jumpToLatest()
    try await settleLayout(host) { distanceToBottom() <= 2 }
    #expect(distanceToBottom() <= 2)
    nativeScroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
    nativeScroll.reflectScrolledClipView(nativeScroll.contentView)
    try await settleLayout(host) { !fixture.scroll.followsBottom }
    fixture.latestRunID = "new-user-submission"
    try await settleLayout(host) { fixture.scroll.followsBottom && distanceToBottom() <= 2 }
    #expect(distanceToBottom() <= 2)
}
#endif
