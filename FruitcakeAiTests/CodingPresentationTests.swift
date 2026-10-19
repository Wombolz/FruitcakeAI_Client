#if os(macOS)
import Foundation
import Testing
import SwiftUI
import AppKit
@testable import FruitcakeAi

@Suite @MainActor struct CodingPresentationTests {
    @Test func timestampsFollowLogicalMessagesAndSurviveReplay() throws {
        let start = Date(timeIntervalSince1970: 1_792_411_200)
        let events = [
            CodingEvent(schemaVersion: 1, runId: "r", sequence: 1, kind: "assistant.text_delta", payload: ["delta": .string("First")], occurredAt: start),
            CodingEvent(schemaVersion: 1, runId: "r", sequence: 2, kind: "assistant.text_delta", payload: ["delta": .string(" response")], occurredAt: start.addingTimeInterval(2)),
            CodingEvent(schemaVersion: 1, runId: "r", sequence: 3, kind: "assistant.message", payload: ["text": .string("First response")], occurredAt: start.addingTimeInterval(4)),
            CodingEvent(schemaVersion: 1, runId: "r", sequence: 4, kind: "user.steered", payload: ["message": .string("Check the edge case")], occurredAt: start.addingTimeInterval(20)),
            CodingEvent(schemaVersion: 1, runId: "r", sequence: 5, kind: "assistant.message", payload: ["text": .string("Second response")], occurredAt: start.addingTimeInterval(30)),
        ]
        var live = CodingProjection(), replay = CodingProjection()
        try live.apply(events[0], runId: "r")
        #expect(live.timeline[0].timestampIsProvisional)
        for event in events.dropFirst() { try live.apply(event, runId: "r") }
        for event in events { try replay.apply(event, runId: "r") }
        #expect(live.timeline.map(\.occurredAt) == [start.addingTimeInterval(4), start.addingTimeInterval(20), start.addingTimeInterval(30)])
        #expect(live.timeline.map(\.occurredAt) == replay.timeline.map(\.occurredAt))
        #expect(live.timeline.allSatisfy { !$0.timestampIsProvisional })
        try live.apply(events.last!, runId: "r")
        #expect(live.timeline.count == 3)
    }

    @Test func legacyEventsDoNotInventMessageTimes() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(CodingEvent.self, from: Data(#"{"schema_version":1,"run_id":"r","sequence":1,"kind":"assistant.message","payload":{"text":"Legacy"}}"#.utf8))
        var projection = CodingProjection()
        try projection.apply(event, runId: "r")
        #expect(event.occurredAt == nil && projection.timeline.first?.occurredAt == nil)
        let timed = try decoder.decode(CodingEvent.self, from: Data(#"{"schema_version":1,"run_id":"r","sequence":2,"kind":"assistant.message","payload":{"text":"Timed"},"occurred_at":"2026-10-19T16:00:00Z"}"#.utf8))
        try projection.apply(timed, runId: "r")
        #expect(projection.timeline.last?.occurredAt == timed.occurredAt && timed.occurredAt != nil)
    }

    @Test func fragmentedSnapshotKeepsOneMessageAndItsStoredTime() throws {
        var projection = CodingProjection()
        let date = Date(timeIntervalSince1970: 100)
        for (index, record) in [("assistant.text_delta", "draft"), ("assistant.message", ""), ("assistant.text_delta", "full "), ("assistant.text_delta", "answer")].enumerated() {
            try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: index + 1, kind: record.0,
                payload: [record.0 == "assistant.message" ? "text" : "delta": .string(record.1)], occurredAt: date.addingTimeInterval(Double(index))), runId: "r")
        }
        #expect(projection.timeline.count == 1 && projection.timeline[0].text == "full answer")
        #expect(projection.timeline[0].occurredAt == date.addingTimeInterval(1))
        #expect(!projection.timeline[0].timestampIsProvisional)
    }

    @Test func fencedCodeIsNotInterpretedAsExecutableOrHtml() {
        let blocks = CodingMessageBlock.parse("**Summary**\n```html\n<script>noExecution()</script>\n```\nDone.")
        #expect(blocks.count == 3)
        #expect(blocks[0].text == "**Summary**\n" && !blocks[0].isCode)
        #expect(blocks[1].language == "html" && blocks[1].text == "<script>noExecution()</script>\n" && blocks[1].isCode)
        #expect(blocks[2].text == "Done.")
        let streaming = CodingMessageBlock.parse("~~~python\nprint('partial')")
        #expect(streaming.count == 1 && streaming[0].isCode && streaming[0].text == "print('partial')")
        let nested = CodingMessageBlock.parse("````text\n```\n````")
        #expect(nested.count == 1 && nested[0].text == "```\n")
    }

    @Test func unifiedDiffDistinguishesHeadersFromChangedSource() {
        #expect(CodingDiffTone.unified("+++ b/file.py") == .header)
        #expect(CodingDiffTone.unified("--- a/file.py") == .header)
        #expect(CodingDiffTone.unified("@@ -1 +1 @@") == .header)
        #expect(CodingDiffTone.unified("++++source") == .addition)
        #expect(CodingDiffTone.unified("---source") == .removal)
        #expect(CodingDiffTone.unified("+") == .addition)
        #expect(CodingDiffTone.unified("-") == .removal)
        #expect(CodingDiffTone.unified(" context") == .context)
    }

    @Test func statusesDoNotPresentWaitingOrInterruptedAsSuccess() {
        #expect(CodingStatusTone.forStatus("waiting_approval") == .attention)
        #expect(CodingStatusTone.forStatus("interrupted") == .attention)
        #expect(CodingStatusTone.forStatus("failed") == .failure)
        #expect(CodingStatusTone.forStatus("completed") == .success)
        #expect(CodingStatusTone.forStatus("running") == .active)
        #expect(CodingStatusTone.forStatus("unknown") == .neutral)
    }

    @Test func diffTextKeepsReadableContrastOnStrongerFills() throws {
        func luminance(_ color: Color) throws -> Double {
            let color = try #require(NSColor(color).usingColorSpace(.sRGB))
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        }
        for pair in [(Theme.diffAdditionText, Theme.diffAdditionFill), (Theme.diffRemovalText, Theme.diffRemovalFill)] {
            let foreground = try luminance(pair.0), background = try luminance(pair.1)
            #expect((foreground + 0.05) / (background + 0.05) >= 4.5)
        }
    }

    @Test(arguments: [360, 640, 1100]) func renderMessagePolish(width: Int) throws {
        let date = Date(timeIntervalSince1970: 1_792_411_200)
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
            CodingUserMessageBubble(text: "Review the validation and add a regression test.", occurredAt: date)
            HStack { CodingStatusBadge(status: "completed"); Text("local/reviewer").font(Theme.mono(10)).foregroundStyle(Theme.textDim) }
            CodingAssistantMessage(text: "**Validation checked.** Added a regression test.\n\n```python\nassert load(empty_path) == {}\n```\nNo commands were run in this view fixture.", occurredAt: date.addingTimeInterval(30))
            HStack { CodingStatusBadge(status: "waiting_approval"); CodingStatusBadge(status: "failed") }
        }.padding(16).frame(width: CGFloat(width)).background(Theme.bg).environment(\.colorScheme, .dark))
        let height = host.fittingSize.height
        host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: height)
        try save(host, name: "fruitcake-polish-messages-\(width)")
    }

    @Test(arguments: [false, true]) func renderBrightDiff(unified: Bool) throws {
        let diff = CodingRepositoryDiff(basis: "review_capture", observedAt: Date(timeIntervalSince1970: 1_792_411_200), path: "validation.py",
            sections: [.init(kind: "captured", text: "--- a/validation.py\n+++ b/validation.py\n@@ -1,3 +1,4 @@\n def load(path):\n-    return json.loads(path.read_text())\n+    text = path.read_text().strip()\n+    return json.loads(text) if text else {}\n \n", truncated: false)],
            captureId: "fixture-capture", base: "base", head: "head", reviewAnchorSide: "after", reviewAnchorStart: 3, reviewAnchorEnd: 3)
        let host = NSHostingView(rootView: CodingDiffPreview(diff: diff, initialUnified: unified).frame(width: 1000, height: 340).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 340)
        try save(host, name: "fruitcake-polish-diff-\(unified ? "unified" : "split")")
    }

    private func save<V: View>(_ host: NSHostingView<V>, name: String) throws {
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("POLISH_FIXTURE: \(url.path)")
        #expect(png.count > 2000)
    }
}
#endif
