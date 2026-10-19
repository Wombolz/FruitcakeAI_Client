import Foundation
import Testing
@testable import FruitcakeAi

private func decodeReview<T: Decodable>(_ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: Data(text.utf8))
}

private let findingJSON = #"{"id":"finding","capture_id":"capture","severity":"should_fix","title":"Validate input","body":"Empty names are accepted.","path":"src/a&b.py","side":"after","line_start":2,"line_end":2,"evidence":"return value","disposition":"open","reason":null,"updated_by_user_id":null,"updated_at":null}"#

func reviewJSON(id: String = "review", session: String = "session", status: String = "completed", content: String = "available", applicability: String = "current") -> String {
    """
    {"id":"\(id)","session_id":"\(session)","checkout_id":"checkout","capture_id":"capture","model_profile_id":2,
    "model":{"model_id":"local/reviewer","provider_family":"ollama"},
    "reasoning":{"requested":"high","resolved":"high","sent":"high","rpc_acknowledged":true,"runtime_readback":"high","provider_confirmation":null,"runtime_version":"1.3.0"},
    "coverage":{"files_in_scope":1,"files_provided_in_prompt":1,"successful_captured_reads":1,"tests_executed":false,"semantic_coverage":"unknown"},
    "limitations":[],"summary":"Check the validation boundary.","status":"\(status)","error_code":null,"last_event_sequence":4,"created_at":"2026-10-19T12:00:00Z","finished_at":null,
    "findings":[\(findingJSON)],
    "capture":{"id":"capture","session_id":"\(session)","scope":"checkout_changes","status":"ready","created_at":"2026-10-19T12:00:00Z","expires_at":"2026-11-19T12:00:00Z","content_status":"\(content)","applicability":"\(applicability)","base":"aaa","head":"bbb","limited":false,"files":[{"path":"src/a&b.py"}]}}
    """
}

@MainActor private final class ReviewAPI: CodingReviewServing {
    var detail: CodingAIReview = try! decodeReview(reviewJSON())
    var requests: [CodingReviewRequest] = []
    var failStartOnce = false
    var optionReads = 0
    var historyReads = 0
    var historyRecords: [CodingAIReview]?
    var reviewDetails: [String: CodingAIReview] = [:]
    var delayDetail = false
    var detailWaiter: CheckedContinuation<CodingAIReview, Error>?
    var delayHistory = false
    var historyWaiter: CheckedContinuation<[CodingAIReview], Error>?
    var diffReads = 0
    var stopped: [String] = []
    var decisions: [(String, Bool)] = []
    var dispositions: [(String, String?)] = []
    var approvalRecords: [CodingReviewApproval] = []
    var delayOptions = false
    var optionWaiter: CheckedContinuation<CodingReviewOptions, Error>?
    var scope = "checkout_changes"
    func options(scope: String) throws -> CodingReviewOptions {
        try decodeReview("""
        {"captures_enabled":true,"ai_reviews":true,"scope":"\(scope)","base":"aaa","head":"bbb","paths":[{"path":"src/a&b.py","eligible":true},{"path":".env","eligible":false}],"path_count":2,"paths_limited":false,"reviewer_profiles":[{"id":2,"label":"Independent reviewer","model_id":"local/reviewer","reasoning_efforts":["default","high"]}],"busy":false,"content_retention_days":30}
        """)
    }
    func codingReviewOptions(sessionId: String, scope: String) async throws -> CodingReviewOptions {
        optionReads += 1
        if delayOptions { return try await withCheckedThrowingContinuation { optionWaiter = $0 } }
        return try options(scope: scope)
    }
    func codingReviews(sessionId: String, offset: Int) async throws -> [CodingAIReview] {
        historyReads += 1
        if delayHistory { return try await withCheckedThrowingContinuation { historyWaiter = $0 } }
        return historyRecords ?? [detail]
    }
    func startCodingReview(sessionId: String, request: CodingReviewRequest) async throws -> CodingAIReview {
        requests.append(request)
        if failStartOnce { failStartOnce = false; throw URLError(.networkConnectionLost) }
        return detail
    }
    func codingReview(id: String) async throws -> CodingAIReview {
        if delayDetail { return try await withCheckedThrowingContinuation { detailWaiter = $0 } }
        return reviewDetails[id] ?? detail
    }
    func codingReviewApprovals(id: String) async throws -> [CodingReviewApproval] { approvalRecords }
    func stopCodingReview(id: String) async throws { stopped.append(id); detail = try decodeReview(reviewJSON(status: "cancelled")) }
    func resolveCodingReviewApproval(reviewId: String, approvalId: String, approved: Bool) async throws { decisions.append((approvalId, approved)) }
    func setCodingFinding(reviewId: String, findingId: String, disposition: String, reason: String?) async throws -> CodingReviewFinding {
        dispositions.append((disposition, reason)); return try decodeReview(findingJSON)
    }
    func codingCapturedDiff(captureId: String, path: String) async throws -> CodingReviewDiff {
        diffReads += 1
        return CodingReviewDiff(basis: "review_capture", captureId: captureId, scope: "checkout_changes", base: "aaa", head: "bbb", path: path,
            capturedAt: Date(), patch: "@@ -1,2 +1,2 @@\n value\n-old\n+return value\n", truncated: false)
    }
    func streamCodingReview(id: String, after: Int, onEvent: @escaping @MainActor (CodingReviewEvent) async throws -> Void) async throws {
        // A suspended fixture stream never performs inference or starts a backend.
        try await Task.sleep(for: .seconds(3600))
    }
}

@Suite @MainActor struct CodingReviewTests {
    @Test func exactTabReactivationDoesNotFallBackToLatestReviewOrRunInference() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        api.reviewDetails["older"] = try decodeReview(reviewJSON(id: "older"))
        await review.resume(reviewID: "older")
        review.tab = "files"
        review.suspend()
        api.detail = try decodeReview(reviewJSON(id: "newer"))
        await review.resume(reviewID: "older")
        #expect(review.selected?.id == "older" && review.tab == "files")
        #expect(api.historyReads == 0 && api.requests.isEmpty && api.stopped.isEmpty)
        review.suspend()
    }

    @Test func closingTabInvalidatesItsDelayedActivationWithoutStoppingBackendWork() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        api.delayDetail = true
        let activation = Task { await review.resume(reviewID: "review") }
        while api.detailWaiter == nil { await Task.yield() }
        review.suspend()
        api.detailWaiter?.resume(returning: api.detail)
        await activation.value
        #expect(review.selected == nil && review.approvals.isEmpty)
        #expect(api.stopped.isEmpty && api.requests.isEmpty)
    }

    @Test func reopenLoadsSavedFindingsWithoutStartingAnotherReview() async throws {
        let api = ReviewAPI()
        let review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        #expect(await review.reopen())
        #expect(review.selected?.id == "review" && review.selected?.findings?.count == 1)
        #expect(review.inspectorMode == "review" && review.tab == "findings")
        #expect(api.historyReads == 1 && api.requests.isEmpty && api.dispositions.isEmpty)
        review.suspend()
    }

    @Test func navigationRestoresReviewAndTabForEachConversation() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        await review.select("review")
        review.tab = "findings"
        review.suspend()
        review.reset(sessionId: "other")
        api.detail = try decodeReview(reviewJSON(id: "other-review", session: "other"))
        await review.resume()
        review.tab = "files"
        review.reset(sessionId: "session")
        api.detail = try decodeReview(reviewJSON())
        await review.resume()
        #expect(review.selected?.id == "review" && review.tab == "findings")
        review.reset(sessionId: "other")
        api.detail = try decodeReview(reviewJSON(id: "other-review", session: "other"))
        await review.resume()
        #expect(review.selected?.id == "other-review" && review.tab == "files")
        #expect(api.requests.isEmpty && api.dispositions.isEmpty)
        review.suspend()
    }

    @Test func olderSelectedReviewIsRecoveredOutsideFirstHistoryPage() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        let older: CodingAIReview = try decodeReview(reviewJSON(id: "older"))
        let newer: CodingAIReview = try decodeReview(reviewJSON(id: "newer"))
        api.reviewDetails = ["older": older, "newer": newer]
        api.historyRecords = [newer]
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        await review.select("older")
        review.tab = "findings"
        review.reset(sessionId: "other"); review.reset(sessionId: "session")
        #expect(await review.reopen())
        #expect(review.selected?.id == "older" && review.tab == "findings")
        #expect(api.requests.isEmpty)
        review.suspend()
    }

    @Test func delayedReopenCannotOpenAnotherConversationsInspector() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        api.delayHistory = true
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        let reopen = Task { await review.reopen() }
        for _ in 0..<100 where api.historyWaiter == nil { await Task.yield() }
        let waiter = try #require(api.historyWaiter)
        review.reset(sessionId: "other")
        waiter.resume(returning: [api.detail])
        #expect(await reopen.value == false)
        #expect(review.selected == nil && review.history.isEmpty && review.inspectorMode == "changes")
        #expect(api.requests.isEmpty)
        review.suspend()
    }

    @Test func emptyHistoryDoesNotFabricateOrStartAReview() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        api.historyRecords = []
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        #expect(await review.reopen() == false)
        #expect(review.selected == nil && api.requests.isEmpty)
        review.suspend()
    }

    @Test func disablingReviewsClearsNavigationBookmarks() async throws {
        let api = ReviewAPI(), review: CodingAIReviewStore
        let older: CodingAIReview = try decodeReview(reviewJSON(id: "older"))
        let newer: CodingAIReview = try decodeReview(reviewJSON(id: "newer"))
        api.reviewDetails = ["older": older, "newer": newer]
        review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        await review.select("older")
        review.setEnabled(false); review.setEnabled(true)
        api.historyRecords = [newer]
        #expect(await review.reopen())
        #expect(review.selected?.id == "newer" && api.requests.isEmpty)
        review.suspend()
    }

    @Test func oldCapabilityMissingMeansUnavailable() throws {
        let old: CodingAvailability = try decodeReview(#"{"enabled":true,"mode":"read_only","event_schema_version":1}"#)
        #expect(old.aiReviews != true)
    }

    @Test func snapshotAndReasoningDecodeWithoutProviderConfirmation() throws {
        let item: CodingAIReview = try decodeReview(reviewJSON(applicability: "stale"))
        #expect(item.reasoning.runtimeReadback == "high")
        #expect(item.reasoning.providerConfirmation == nil || item.reasoning.providerConfirmation == .null)
        #expect(item.capture?.canOpenDiff == true)
        #expect(item.qualification.contains("stale"))
        #expect(item.findings?.first?.anchor == "src/a&b.py · after L2-2")
    }

    @Test(arguments: ["failed", "cancelled", "interrupted", "waiting_approval"])
    func incompleteStatesNeverAppearClean(_ status: String) throws {
        let item: CodingAIReview = try decodeReview(reviewJSON(status: status))
        #expect(!item.qualification.isEmpty)
        #expect(item.findings?.count == 1)
    }

    @Test func expiredEvidenceNeverFetchesLiveDiff() async throws {
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(content: "expired"))
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        let diff = await store.diff(path: "src/a&b.py")
        #expect(diff == nil && api.diffReads == 0)
    }

    @Test func staleDiffRetainsCaptureAndAnchorIdentity() async throws {
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(applicability: "stale"))
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        let finding = try #require(store.selected?.findings?.first)
        let diff = try #require(await store.diff(path: finding.path, finding: finding))
        #expect(diff.captureId == "capture" && diff.basis == "review_capture")
        #expect(diff.reviewAnchorStart == 2 && diff.reviewAnchorSide == "after")
        #expect(diff.reviewQualification?.contains("stale") == true)
    }

    @Test func openingSetupNeverStartsAndUnsupportedEffortCannotSubmit() async throws {
        let api = ReviewAPI()
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.loadOptions(scope: "checkout_changes")
        #expect(store.options?.reviewerProfiles?.count == 1)
        let started = await store.start(scope: "checkout_changes", paths: ["src/a&b.py"], modelId: 2, effort: "minimal")
        #expect(!started && api.requests.isEmpty)
    }

    @Test func uncertainStartRetriesExactKeyAndSelections() async throws {
        let api = ReviewAPI(), store: CodingAIReviewStore
        api.failStartOnce = true
        store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.loadOptions(scope: "checkout_changes")
        #expect(await store.start(scope: "checkout_changes", paths: ["src/a&b.py"], modelId: 2, effort: "high") == false)
        #expect(store.pending != nil && store.busy)
        #expect(await store.retryStart())
        #expect(api.requests.count == 2 && api.requests[0] == api.requests[1])
        #expect(store.pending == nil && store.selected?.modelProfileId == 2)
    }

    @Test func delayedOptionsCannotCrossSessionBoundary() async throws {
        let api = ReviewAPI()
        api.delayOptions = true
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        let load = Task { await store.loadOptions(scope: "checkout_changes") }
        for _ in 0..<100 where api.optionWaiter == nil { await Task.yield() }
        let waiter = try #require(api.optionWaiter)
        store.reset(sessionId: "other")
        waiter.resume(returning: try api.options(scope: "checkout_changes"))
        await load.value
        #expect(store.options == nil && !store.loadingOptions)
    }

    @Test func reviewStopAndDismissalAreNotBuilderActions() async throws {
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(status: "waiting_approval"))
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        let finding = try #require(store.selected?.findings?.first)
        await store.disposition(finding, dismiss: true, reason: "  ")
        #expect(api.dispositions.isEmpty)
        await store.disposition(finding, dismiss: true, reason: "Expected invariant")
        #expect(api.dispositions.first?.1 == "Expected invariant")
        await store.stop()
        #expect(api.stopped == ["review"] && store.selected?.status == "cancelled")
        store.suspend()
    }

    @Test func correctionIsBoundedHistoricalTextAndNeverSubmitted() async throws {
        let api = ReviewAPI(), store: CodingAIReviewStore
        store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        let finding = try #require(store.selected?.findings?.first)
        let draft = try #require(await store.correction(finding))
        #expect(draft.contains("Finding: finding") && draft.contains("Capture: capture"))
        #expect(draft.contains("return value") && draft.unicodeScalars.count <= 10000)
        #expect(api.requests.isEmpty && api.dispositions.isEmpty)
    }

    @Test func approvalIdentityAndNonExpiringHumanWait() async throws {
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(status: "waiting_approval"))
        let approval: CodingReviewApproval = try decodeReview(#"{"id":"approval","review_id":"review","status":"pending","path":"src/a&b.py","side":"before","created_at":"2026-10-19T12:00:00Z","resolved_at":null,"expires_at":null}"#)
        api.approvalRecords = [approval]
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        #expect(store.approvals.first?.status == "pending")
        await store.resolve(approval, approved: false)
        #expect(api.decisions.first?.0 == "approval" && api.decisions.first?.1 == false)
        store.suspend()
    }

    @Test func foreignReviewResponseFailsClosed() async throws {
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(session: "other"))
        let store = CodingAIReviewStore(api: api)
        store.setEnabled(true); store.reset(sessionId: "session")
        await store.select("review")
        #expect(store.selected == nil && store.error != nil)
    }

    @Test func replayCursorDeduplicatesAndRejectsGapAndForeignReview() throws {
        var cursor = CodingReviewCursor()
        let event = CodingReviewEvent(schemaVersion: 1, reviewId: "review", sequence: 1, kind: "review.finding", payload: [:])
        #expect(try cursor.accept(event, reviewId: "review"))
        #expect(try cursor.accept(event, reviewId: "review") == false)
        #expect(throws: CodingClientError.self) { try cursor.accept(event, reviewId: "another") }
        #expect(throws: CodingClientError.self) {
            try cursor.accept(CodingReviewEvent(schemaVersion: 1, reviewId: "review", sequence: 3, kind: "review.completed", payload: [:]), reviewId: "review")
        }
    }
}

#if os(macOS)
import AppKit
import SwiftUI

@Suite @MainActor struct CodingReviewRenderingTests {
    @Test func renderRetainedDiffWithHistoricalAnchor() async throws {
        // Pure view fixture, not full-window geometry or signed-in acceptance.
        let api = ReviewAPI()
        api.detail = try decodeReview(reviewJSON(applicability: "stale"))
        let review = CodingAIReviewStore(api: api)
        review.setEnabled(true); review.reset(sessionId: "session")
        await review.select("review")
        let finding = try #require(review.selected?.findings?.first)
        let diff = try #require(await review.diff(path: finding.path, finding: finding))
        let host = NSHostingView(rootView: CodingDiffPreview(diff: diff).frame(width: 900, height: 400))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        review.suspend()
    }
}
#endif
