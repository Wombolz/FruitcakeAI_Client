import Foundation
import Testing
@testable import FruitcakeAi

@MainActor
private func fixture<T: Decodable>(_ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: Data(text.utf8))
}

@MainActor
private func runFixture(_ status: String = "running", session: String = "a", request: String? = nil) throws -> CodingRun {
    try fixture("""
    {"id":"run-\(session)","session_id":"\(session)","client_request_id":\(request.map { "\"\($0)\"" } ?? "null"),"status":"\(status)","prompt":"Inspect","response_text":"\(status == "completed" ? "Hello world" : "")","context_generation":1,"last_event_sequence":5,"error_code":null,"created_at":"2026-10-16T12:00:00Z"}
    """)
}

@Test @MainActor func nonExpiringApprovalsDecodeFromRESTAndSSEAndRemainPending() throws {
    let approval: CodingApproval = try fixture("""
    {"id":"approval","run_id":"run-a","status":"pending","title":"Approve?","message":"Review first","expires_at":null}
    """)
    #expect(approval.expiresAt == nil)
    #expect(approval.isPending)
    #expect(!approval.isExpired(at: Date.distantFuture))
    let event = CodingEvent(schemaVersion: 1, runId: "run-a", sequence: 2, kind: "approval.requested", payload: [
        "approval_id": .string("approval"), "title": .string("Approve?"), "message": .string("Review first"), "expires_at": .null,
    ])
    let streamed = try #require(CodingApproval.requested(event))
    #expect(streamed.isPending)
    #expect(streamed.expiresAt == nil)
}

@Test @MainActor func finiteLegacyAndResolvedApprovalsKeepExistingBehavior() throws {
    let approval = CodingApproval(id: "approval", runId: "run-a", status: "pending", title: "Approve?", message: "", expiresAt: Date(timeIntervalSince1970: 0))
    #expect(!approval.isPending)
    #expect(approval.isExpired(at: Date()))
    var answered = CodingApproval(id: "answered", runId: "run-a", status: "approved", title: "Approve?", message: "", expiresAt: nil)
    #expect(!answered.isPending)
    answered.status = "cancelled"
    #expect(!answered.isPending)
}

@MainActor
private final class FakeCodingAPI: CodingServing {
    var sessionList: [CodingSession] = [
        CodingSession(id: "a", workspaceId: "w", modelProfileId: 1, projectId: nil, title: "A", status: "idle", contextGeneration: 1),
        CodingSession(id: "b", workspaceId: "w", modelProfileId: 1, projectId: nil, title: "B", status: "idle", contextGeneration: 1),
    ]
    var remote: [String: CodingRun] = [:]
    var submissions: [String] = []
    var streamCursors: [Int] = []
    var stops = 0
    var cancelObserved = false
    var failSubmissionOnce = false
    var failStreamOnce = false
    var holdStream = false
    var availability = true
    var mode = "read_only"
    var controls: [String] = []
    var failControl = false
    var approvalCalls: [(String, Bool)] = []
    var delayedHistory: CheckedContinuation<[CodingRun], Never>?
    var delaySessionA = false
    var delayedRepository: CheckedContinuation<CodingRepository, Never>?
    var delayRepository = false
    var delayedDiff: CheckedContinuation<CodingRepositoryDiff, Never>?
    var delayDiff = false
    var failRepository = false
    var repositoryReads = 0
    var checkoutSupport = true
    var checkouts: [String: CodingCheckout] = [:]
    var checkoutCreates: [String] = []
    var checkoutRemovals: [String] = []
    var failCheckoutCreateOnce = false
    var delayCheckout = false
    var delayedCheckout: CheckedContinuation<CodingCheckout?, Never>?
    var failModeResponse = false
    var recordedChanges: [CodingSavedChange] = []
    var delayChanges = false
    var delayedChanges: CheckedContinuation<[CodingSavedChange], Never>?
    var approvalReads = 0
    var commandApprovalCalls: [(String, Bool, String?)] = []
    var failCommandModeResponse = false
    var recordedApprovals: [CodingApproval] = []
    var streamRecords: [(String, [String: JSONValue])]?
    var repositoryCreations: [String] = []
    var failRepositoryCreation = false
    var modelChanges: [Int] = []
    var deliveryConfirms = 0
    var failDelivery = false
    var deliveryResult: CodingDeliveryResult?
    var delayDelivery = false
    var delayedDelivery: CheckedContinuation<CodingDeliveryResult, Never>?
    var joinedCheckouts: [String] = []

    func codingSessionPage(offset: Int, archived: Bool) async throws -> [CodingSession] {
        sessionList.filter { ($0.archivedAt != nil) == archived }
    }
    func codingReusableCheckouts() async throws -> [CodingCheckout] { Array(checkouts.values) }
    func createCodingSessionInCheckout(workspaceId: String, modelId: Int, projectId: Int?, title: String, checkoutId: String) async throws -> CodingSession {
        joinedCheckouts.append(checkoutId)
        let checkout = try #require(checkouts.values.first { $0.id == checkoutId })
        let created = CodingSession(id: "joined", workspaceId: workspaceId, modelProfileId: modelId, projectId: projectId, title: title, status: "idle", contextGeneration: 0)
        sessionList.append(created)
        checkouts[created.id] = CodingCheckout(id: checkout.id, sessionId: created.id, canonicalPath: checkout.canonicalPath, baselineCommit: checkout.baselineCommit, status: "ready", errorCode: nil)
        return created
    }
    func changeCodingModel(sessionId: String, modelId: Int) async throws -> CodingSession {
        modelChanges.append(modelId)
        let index = try #require(sessionList.firstIndex { $0.id == sessionId })
        let current = sessionList[index]
        sessionList[index] = CodingSession(id: current.id, workspaceId: current.workspaceId, modelProfileId: modelId, projectId: current.projectId, title: current.title, status: current.status, contextGeneration: current.contextGeneration, editMode: false, commandMode: false)
        return sessionList[index]
    }
    func archiveCodingSession(sessionId: String, archived: Bool) async throws -> CodingSession {
        let index = try #require(sessionList.firstIndex { $0.id == sessionId })
        sessionList[index].archivedAt = archived ? Date() : nil
        sessionList[index].status = archived ? "closed" : "idle"
        return sessionList[index]
    }
    func deleteCodingSession(sessionId: String) async throws { sessionList.removeAll { $0.id == sessionId } }
    func previewCodingDelivery(sessionId: String, action: String, files: [String], message: String) async throws -> CodingDeliveryPreview {
        let checkout = try #require(checkouts[sessionId])
        return CodingDeliveryPreview(action: action, checkoutId: checkout.id, head: "base", diff: "--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n", reviewHash: "reviewed")
    }
    func confirmCodingDelivery(sessionId: String, action: String, files: [String], message: String, hash: String) async throws -> CodingDeliveryResult {
        deliveryConfirms += 1
        if failDelivery { throw URLError(.networkConnectionLost) }
        if delayDelivery { return await withCheckedContinuation { delayedDelivery = $0 } }
        if let deliveryResult { return deliveryResult }
        return CodingDeliveryResult(action: action, head: "new", checkoutId: try #require(checkouts[sessionId]).id)
    }

    func codingAvailability() async throws -> CodingAvailability {
        CodingAvailability(enabled: availability, mode: mode, eventSchemaVersion: 1, managedCheckouts: checkoutSupport, approvedEdits: true, containerCommands: true)
    }
    func setCodingEditMode(sessionId: String, enabled: Bool) async throws -> CodingSession {
        let index = try #require(sessionList.firstIndex { $0.id == sessionId })
        sessionList[index].editMode = enabled
        if failModeResponse { throw URLError(.networkConnectionLost) }
        return sessionList[index]
    }
    func codingChanges(runId: String) async throws -> [CodingSavedChange] {
        if delayChanges { return await withCheckedContinuation { delayedChanges = $0 } }
        return recordedChanges
    }
    func setCodingCommandMode(sessionId: String, enabled: Bool) async throws -> CodingSession {
        let index = try #require(sessionList.firstIndex { $0.id == sessionId })
        sessionList[index].commandMode = enabled
        if failCommandModeResponse { throw URLError(.networkConnectionLost) }
        return sessionList[index]
    }
    func resolveCodingCommand(id: String, approved: Bool, commandHash: String?) async throws {
        commandApprovalCalls.append((id, approved, commandHash))
    }
    func codingWorkspaces() async throws -> [CodingWorkspace] { [CodingWorkspace(id: "w", userId: 2, canonicalPath: "/repo", isActive: true)] }
    func codingModels() async throws -> [CodingModelOption] { [CodingModelOption(id: 1, label: "Local fixture", modelId: "fixture")] }
    func codingProjects() async throws -> [CodingProjectOption] { [] }
    func codingCheckout(sessionId: String) async throws -> CodingCheckout? {
        if delayCheckout { return await withCheckedContinuation { delayedCheckout = $0 } }
        return checkouts[sessionId]
    }
    func createCodingCheckout(sessionId: String) async throws -> CodingCheckout {
        checkoutCreates.append(sessionId)
        let result = checkouts[sessionId] ?? CodingCheckout(id: "checkout-\(sessionId)", sessionId: sessionId,
            canonicalPath: "/managed/\(sessionId)", baselineCommit: "abc123", status: "ready", errorCode: nil)
        checkouts[sessionId] = result
        if failCheckoutCreateOnce { failCheckoutCreateOnce = false; throw URLError(.networkConnectionLost) }
        return result
    }
    func removeCodingCheckout(sessionId: String) async throws -> CodingCheckout {
        checkoutRemovals.append(sessionId)
        var result = try #require(checkouts[sessionId])
        result.status = "removed"; checkouts[sessionId] = result
        return result
    }
    func codingRepository(sessionId: String) async throws -> CodingRepository {
        repositoryReads += 1
        if failRepository { throw CodingClientError(code: "not_repository", message: "Choose a Git repository root.", status: 409) }
        if delayRepository { return await withCheckedContinuation { delayedRepository = $0 } }
        return repositoryFixture()
    }
    func codingRepositoryDiff(sessionId: String, path: String) async throws -> CodingRepositoryDiff {
        if delayDiff { return await withCheckedContinuation { delayedDiff = $0 } }
        return diffFixture(path)
    }
    func codingSessions(offset: Int) async throws -> [CodingSession] { offset == 0 ? sessionList : [] }
    func createCodingSession(workspaceId: String, modelId: Int, projectId: Int?, title: String) async throws -> CodingSession { sessionList[0] }
    func codingRuns(sessionId: String, offset: Int) async throws -> [CodingRun] {
        if delaySessionA && sessionId == "a" { return await withCheckedContinuation { delayedHistory = $0 } }
        return remote.values.filter { $0.sessionId == sessionId }
    }
    func codingRun(id: String) async throws -> CodingRun { try #require(remote[id]) }
    func submitCoding(sessionId: String, message: String, requestId: String) async throws -> CodingRun {
        submissions.append(requestId)
        let run = try runFixture("completed", session: sessionId, request: requestId)
        remote[run.id] = run
        if failSubmissionOnce { failSubmissionOnce = false; throw URLError(.networkConnectionLost) }
        return run
    }
    func stopCoding(runId: String) async throws { stops += 1; remote[runId]?.status = "cancelled" }
    func controlCoding(runId: String, action: String, message: String) async throws {
        controls.append(action)
        if failControl { throw URLError(.networkConnectionLost) }
    }
    func codingApprovals(runId: String) async throws -> [CodingApproval] { approvalReads += 1; return recordedApprovals }
    func resolveCodingApproval(id: String, approved: Bool, changeHash: String?) async throws { approvalCalls.append((id, approved)); approvalHashes.append(changeHash) }
    var approvalHashes: [String?] = []
    func closeCodingSession(id: String) async throws { sessionList[0].status = "closed" }
    func grantCodingWorkspace(userId: Int, path: String) async throws -> CodingWorkspace { CodingWorkspace(id: "w", userId: userId, canonicalPath: path, isActive: true) }
    func createCodingRepository(userId: Int, path: String) async throws -> CodingWorkspace {
        repositoryCreations.append(path)
        if failRepositoryCreation { throw CodingClientError(code: "request_conflict", message: "That folder already exists.") }
        return CodingWorkspace(id: "new-repository", userId: userId, canonicalPath: path, isActive: true)
    }
    func streamCoding(runId: String, after: Int, follow: Bool, onEvent: @escaping @MainActor (CodingEvent) async throws -> Void) async throws {
        streamCursors.append(after)
        if holdStream {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { cancelObserved = true; throw error }
            return
        }
        let records: [(String, [String: JSONValue])] = streamRecords ?? [
            ("run.accepted", [:]), ("assistant.text_delta", ["delta": .string("Hello")]),
            ("assistant.text_delta", ["delta": .string(" world")]),
            ("assistant.message", ["text": .string("Hello world")]), ("run.completed", [:]),
        ]
        for (index, record) in records.enumerated() where index + 1 > after {
            try await onEvent(CodingEvent(schemaVersion: 1, runId: runId, sequence: index + 1, kind: record.0, payload: record.1))
            if failStreamOnce && index == 1 { failStreamOnce = false; throw URLError(.networkConnectionLost) }
        }
        remote[runId]?.status = "completed"
        remote[runId]?.responseText = "Hello world"
    }
}

@MainActor
private func repositoryFixture() -> CodingRepository {
    CodingRepository(basis: "current_worktree", observedAt: Date(), head: "abc123", files: [
        CodingChangedFile(path: "file.txt", indexStatus: "M", worktreeStatus: "M", originalPath: nil),
        CodingChangedFile(path: "new&odd.txt", indexStatus: "?", worktreeStatus: "?", originalPath: nil),
    ])
}

@MainActor
private func diffFixture(_ path: String) -> CodingRepositoryDiff {
    CodingRepositoryDiff(basis: "current_worktree", observedAt: Date(), path: path, sections: [
        .init(kind: "staged", text: "@@ -1 +1 @@\n-old\n+new\n", truncated: false),
        .init(kind: "unstaged", text: "@@ -1 +1 @@\n-new\n+newest\n", truncated: true),
    ])
}

@Suite @MainActor
struct CodingWorkspaceTests {
    @Test func timelineInterleavesMessagesOperationsAndApprovalsWithoutSnapshotDuplicates() throws {
        var projection = CodingProjection()
        let records: [(String, [String: JSONValue])] = [
            ("assistant.text_delta", ["delta": .string("First")]),
            ("assistant.message", ["text": .string("First message")]),
            ("operation.started", ["operation_id": .string("op"), "tool": .string("read")]),
            ("approval.requested", ["approval_id": .string("approval")]),
            ("operation.completed", ["operation_id": .string("op"), "tool": .string("read"), "is_error": .bool(false)]),
            ("assistant.text_delta", ["delta": .string("Next")]),
            ("assistant.message", ["text": .string("Next message")]),
        ]
        for (index, record) in records.enumerated() {
            try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: index + 1, kind: record.0, payload: record.1), runId: "r")
        }
        #expect(projection.timeline.map(\.text) == ["First message", "op", "approval", "Next message"])
        #expect(projection.timeline.map(\.id) == [1, 3, 4, 6])
        #expect(projection.operations.count == 1)
        #expect(projection.operations[0].status == "completed")
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 7, kind: "assistant.message", payload: ["text": .string("Next message")]), runId: "r")
        #expect(projection.timeline.count == 4)
    }

    @Test func fragmentedSnapshotsStayInTheirOriginalTimelineBlock() throws {
        var projection = CodingProjection()
        let records: [(String, [String: JSONValue])] = [
            ("assistant.text_delta", ["delta": .string("partial")]),
            ("assistant.message", ["text": .string("")]),
            ("assistant.text_delta", ["delta": .string("complete ")]),
            ("assistant.text_delta", ["delta": .string("snapshot")]),
            ("operation.started", ["operation_id": .string("op"), "tool": .string("ls")]),
            ("assistant.message", ["text": .string("After the action")]),
        ]
        for (index, record) in records.enumerated() {
            try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: index + 1, kind: record.0, payload: record.1), runId: "r")
        }
        #expect(projection.timeline.map(\.text) == ["complete snapshot", "op", "After the action"])
    }

    @Test func approvalSnapshotsCannotRemoveNewRequestsOrRegressResolvedDecisions() async throws {
        let store = CodingWorkspaceStore(api: FakeCodingAPI())
        await store.refresh()
        var original: [CodingApproval] = []
        for index in 1...7 {
            let event = CodingEvent(schemaVersion: 1, runId: "r", sequence: index, kind: "approval.requested", payload: [
                "approval_id": .string("a\(index)"), "title": .string("Read \(index)?"), "message": .string("file\(index)"),
                "expires_at": .string("2099-10-16T12:00:00.123456+00:00"),
            ])
            original.append(try #require(CodingApproval.requested(event)))
            #expect(store.applyApprovalEvent(event))
        }
        #expect(store.approvals.map(\.id) == (1...7).map { "a\($0)" })
        store.applyApprovalEvent(CodingEvent(schemaVersion: 1, runId: "r", sequence: 8, kind: "approval.resolved", payload: ["approval_id": .string("a2"), "status": .string("approved")]))
        store.mergeApprovals(Array(original.prefix(3).reversed()), runId: "r")
        #expect(store.approvals.count == 7)
        #expect(store.approvals[1].status == "approved")
        #expect(store.approvals.filter(\.isPending).count == 6)
        store.suspend()
    }

    @Test func streamRendersSevenApprovalsWithoutPerRequestFetchOrClearingAtCompletion() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture()
        var records: [(String, [String: JSONValue])] = []
        for index in 1...7 {
            records.append(("approval.requested", ["approval_id": .string("a\(index)"), "title": .string("Read \(index)?"), "message": .string("file"), "expires_at": .string("2099-10-16T12:00:00Z")]))
        }
        for index in 1...7 { records.append(("approval.resolved", ["approval_id": .string("a\(index)"), "status": .string("approved")])) }
        records.append(("run.completed", [:]))
        api.streamRecords = records
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        for _ in 0..<200 {
            if store.connection == "Completed" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.approvals.count == 7)
        #expect(store.approvals.allSatisfy { $0.status == "approved" })
        #expect(store.projections["run-a"]?.timeline.filter { $0.kind == .approval }.count == 7)
        #expect(api.approvalReads == 2)
        store.suspend()
    }

    @Test func editModeIsExplicitAndLostResponseBlocksSubmissionUntilRefresh() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(!store.canSetEditMode)
        await store.createCheckout()
        #expect(store.canSetEditMode)
        #expect(!store.editingEnabled)
        store.draft = "Change"
        api.failModeResponse = true
        await store.setEditMode(true)
        #expect(!store.editModeKnown)
        #expect(!store.canSubmit)
        await store.refresh()
        #expect(store.editingEnabled)
        #expect(store.canSubmit)
        store.suspend()
    }

    @Test func containerCommandModeIsSeparateAndLostResponseRequiresReconciliation() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(!store.canSetCommandMode)
        await store.createCheckout()
        #expect(store.canSetCommandMode)
        #expect(!store.commandsEnabled && !store.editingEnabled)
        store.draft = "Run fixture"
        api.failCommandModeResponse = true
        await store.setCommandMode(true)
        #expect(!store.editModeKnown && !store.canSubmit)
        api.failCommandModeResponse = false
        await store.refresh()
        #expect(store.commandsEnabled && !store.editingEnabled)
        #expect(store.modeLabel.contains("writable checkout"))
        #expect(store.canSubmit)
        store.suspend()
    }

    @Test func commandApprovalDecodesAndUsesExactCommandHashNotFileApproval() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        let wire = #"{"id":"a","run_id":"run-a","status":"pending","title":"Approve container command?","message":"Checkout writable","expires_at":"2099-10-17T12:00:00Z","command":{"id":"c","command":"python --version","working_directory":".","timeout_seconds":120,"image":"sha256:fixture","network":"none","filesystem":"checkout_read_write","hash":"digest","status":"proposed"}}"#
        let approval: CodingApproval = try fixture(wire)
        #expect(approval.command?.command == "python --version")
        await store.resolve(approval, approved: true)
        #expect(api.approvalCalls.isEmpty)
        #expect(api.commandApprovalCalls.first?.0 == "a")
        #expect(api.commandApprovalCalls.first?.2 == "digest")
        await store.resolve(approval, approved: false)
        #expect(api.commandApprovalCalls.last?.2 == nil)
        store.suspend()
    }

    @Test func approvalRequiresReviewAndUsesTopDiffWithoutRepositoryFetch() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        let change = CodingChangePreview(id: "change", path: "file.txt", diff: "@@ -1 +1 @@\n-old\n+new\n", beforeHash: "a", afterHash: "b")
        let approval = CodingApproval(id: "approval", runId: "run-a", status: "pending", title: "Approve", message: "file.txt", expiresAt: Date().addingTimeInterval(60), change: change)
        await store.resolve(approval, approved: true)
        #expect(api.approvalCalls.isEmpty)
        store.reviewChange(change)
        #expect(store.diffVisible)
        #expect(store.repositoryDiff?.basis == "approval")
        #expect(store.repositoryDiff?.sections.first?.text == change.diff)
        #expect(api.repositoryReads == 0)
        await store.resolve(approval, approved: true)
        #expect(api.approvalCalls.count == 1)
        #expect(api.approvalHashes.last! == "b")
        await store.select("b")
        #expect(store.reviewedChanges.isEmpty)
        #expect(store.repositoryDiff == nil)
        store.suspend()
    }

    @Test func savedChangeStatusAndLateResponsesCannotCrossSessions() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        let run = try runFixture("completed")
        api.delayChanges = true
        let load = Task { await store.loadSavedChanges(run) }
        while api.delayedChanges == nil { await Task.yield() }
        await store.select("b")
        let change = CodingSavedChange(id: "c", runId: run.id, path: "file.txt", diff: "patch", status: "uncertain", errorCode: "backend_restart", createdAt: Date(), appliedAt: nil)
        api.delayedChanges?.resume(returning: [change])
        await load.value
        #expect(store.savedChanges.isEmpty)
        store.reviewSavedChange(change)
        #expect(store.repositoryDiff?.basis == "saved_change")
        #expect(store.repositoryDiff?.sections.first?.kind == "uncertain")
        store.suspend()
    }

    @Test func checkoutCreationIsExplicitAndExecutionPathNeverFallsBack() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(store.canCreateCheckout)
        #expect(api.checkoutCreates.isEmpty)
        await store.createCheckout()
        #expect(api.checkoutCreates == ["a"])
        #expect(store.executionPath == "/managed/a")
        store.draft = "Inspect"
        #expect(store.canSubmit)
        api.checkouts["a"]?.status = "failed"
        await store.select("a")
        #expect(!store.canSubmit)
        #expect(store.executionPath == "/managed/a")
        api.checkouts["a"]?.status = "removed"
        await store.select("a")
        #expect(store.executionPath == nil)
        #expect(!store.canSubmit)
        #expect(api.submissions.isEmpty)
    }

    @Test func sourceSessionCanCreateCheckoutAfterCompletedHistoryWithoutDiscardingConversation() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(store.runs.count == 1)
        #expect(store.canCreateCheckout)
        #expect(store.checkoutCreationBlockReason == nil)
        await store.createCheckout()
        #expect(api.checkoutCreates == ["a"])
        #expect(store.runs.first?.responseText == "Hello world")
        #expect(store.selectedId == "a")
        #expect(store.executionPath == "/managed/a")
        #expect(store.canSetEditMode)
        #expect(!store.editingEnabled)
        store.suspend()
    }

    @Test func checkoutTransitionExplainsActiveClosedAndInterruptedStates() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.runs = [try runFixture("running")]
        #expect(!store.canCreateCheckout)
        #expect(store.checkoutCreationBlockReason?.contains("active run") == true)
        await store.createCheckout()
        #expect(api.checkoutCreates.isEmpty)
        store.runs = [try runFixture("interrupted")]
        store.sessions[0].status = "interrupted"
        #expect(store.canCreateCheckout)
        store.sessions[0].status = "closed"
        #expect(!store.canCreateCheckout)
        #expect(store.checkoutCreationBlockReason?.contains("closed") == true)
        store.suspend()
    }

    @Test func lostCheckoutResponseRequiresReconciliationAndCleanRemovalIsExplicit() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        api.failCheckoutCreateOnce = true
        await store.createCheckout()
        store.draft = "Inspect"
        #expect(!store.checkoutLoaded)
        #expect(!store.canSubmit)
        #expect(store.executionPath == nil)
        await store.resume()
        #expect(store.checkout?.id == "checkout-a")
        #expect(api.checkoutCreates.count == 1)
        await store.closeSelected()
        await store.removeCheckout()
        #expect(api.checkoutRemovals == ["a"])
        #expect(store.checkout?.status == "removed")
        #expect(api.stops == 0)
    }

    @Test func lateCheckoutStatusDoesNotCrossSessionBoundaries() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        api.delayCheckout = true
        let previous = Task { await store.select("a") }
        while api.delayedCheckout == nil { await Task.yield() }
        let held = api.delayedCheckout
        api.delayCheckout = false
        await store.select("b")
        held?.resume(returning: CodingCheckout(id: "old", sessionId: "a", canonicalPath: "/old", baselineCommit: "abc", status: "ready", errorCode: nil))
        await previous.value
        #expect(store.selectedId == "b")
        #expect(store.checkout == nil)
        #expect(store.executionPath == "/repo")
    }

    @Test func checkoutWireRemainsCompatibleWithOlderReadOnlyStatus() throws {
        let old: CodingAvailability = try fixture(#"{"enabled":true,"mode":"read_only","event_schema_version":1}"#)
        #expect(old.managedCheckouts == nil)
        let checkout: CodingCheckout = try fixture(#"{"id":"c","session_id":"a","canonical_path":"/managed/a","baseline_commit":null,"status":"creating","error_code":null}"#)
        #expect(checkout.isBusy)
    }

    @Test func checkoutPollingReconcilesReadyStateWithoutSubmittingAPrompt() async throws {
        let api = FakeCodingAPI()
        api.checkouts["a"] = CodingCheckout(id: "c", sessionId: "a", canonicalPath: "/managed/a",
                                           baselineCommit: "abc", status: "creating", errorCode: nil)
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.draft = "Inspect"
        #expect(!store.canSubmit)
        #expect(store.executionPath == nil)
        api.checkouts["a"]?.status = "ready"
        let deadline = Date().addingTimeInterval(5)
        while store.checkout?.status != "ready", Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.checkout?.status == "ready")
        #expect(store.canSubmit)
        #expect(store.executionPath == "/managed/a")
        #expect(api.submissions.isEmpty)
        store.suspend()
    }

    @Test func splitDiffAlignsEditsAndPreservesSourceLineNumbers() {
        let split = CodingSplitDiff.parse("@@ -10,3 +20,4 @@\n context\n-old\n+new\n+extra\n last\n")
        #expect(!split.truncated)
        #expect(split.rows.count == 5)
        #expect(split.rows[1].beforeNumber == 10)
        #expect(split.rows[1].afterNumber == 20)
        #expect(split.rows[2].before == "old")
        #expect(split.rows[2].after == "new")
        #expect(split.rows[3].before == nil)
        #expect(split.rows[3].afterNumber == 22)
        #expect(split.rows[4].beforeNumber == 12)
        #expect(split.rows[4].afterNumber == 23)
    }

    @Test func splitDiffHandlesNewFilesMarkersMalformedHeadersAndBounds() {
        let added = CodingSplitDiff.parse("diff --git a/new b/new\n--- /dev/null\n+++ b/new\n@@ -0,0 +1,2 @@\n+first\n+second\n\\ No newline at end of file\n")
        #expect(added.rows.count == 3)
        #expect(added.rows.last?.before == nil)
        #expect(added.rows.last?.afterNumber == 2)
        #expect(added.rows.last?.after == "second")
        #expect(CodingSplitDiff.parse("Binary files a/file and b/file differ").rows.isEmpty)
        #expect(CodingSplitDiff.parse("@@ - + @@\n+bad\n").rows.isEmpty)
        #expect(CodingSplitDiff.parse("@@ -9223372036854775807 +1 @@\n-old\n+new\n").rows.isEmpty)
        let bounded = CodingSplitDiff.parse("@@ -0,0 +1,100 @@\n" + String(repeating: "+new\n", count: 100), limit: 10)
        #expect(bounded.rows.count == 10)
        #expect(bounded.truncated)
    }

    @Test func drawerSizingPreservesConversationSpaceWithoutFeedback() {
        #expect(CodingDiffDrawerSizing.height(preferred: 380, available: 600) == 380)
        #expect(CodingDiffDrawerSizing.height(preferred: 900, available: 1000) == 650)
        #expect(CodingDiffDrawerSizing.height(preferred: -100, available: 1000) == 160)
        #expect(CodingDiffDrawerSizing.height(preferred: 380, available: 300) == 80)
        #expect(CodingDiffDrawerSizing.height(preferred: 380, available: 0) == 0)
        #expect(CodingDiffDrawerSizing.height(preferred: .nan, available: 1000) == 380)
        let anchored = 300.0 + 40.0
        #expect(CodingDiffDrawerSizing.height(preferred: anchored, available: 1000) == CodingDiffDrawerSizing.height(preferred: anchored, available: 1000))
    }

    @Test func diffAndFileInspectorCloseIndependently() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        await store.refreshRepository()
        await store.reviewFile(try #require(store.repository?.files.first))
        #expect(!store.diffVisible)
        store.showDiff()
        let inspector = ArtifactInspectorState()
        inspector.openCoding(store)
        inspector.close()
        #expect(store.diffVisible)
        #expect(store.repositoryDiff != nil)
        store.closeDiff()
        #expect(store.repositoryDiff != nil)
        inspector.openCoding(store)
        #expect(inspector.isVisible)
        store.showDiff()
        await store.select("b")
        #expect(!store.diffVisible)
        #expect(store.repositoryDiff == nil)
        #expect(api.stops == 0)
    }

    @Test func refreshingRepositoryClosesStaleDiffWithoutStoppingRun() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        await store.refreshRepository()
        await store.reviewFile(try #require(store.repository?.files.first))
        store.showDiff()
        await store.refreshRepository()
        #expect(!store.diffVisible)
        #expect(store.repositoryDiff == nil)
        #expect(store.repository != nil)
        #expect(api.stops == 0)
    }

    @Test func codingChangesUsesTheSharedInspectorWithoutStoppingRuns() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        await store.refreshRepository()
        let inspector = ArtifactInspectorState()
        let document = ArtifactReference(id: "doc", path: "report.md", filename: "report.md",
                                         mediaType: "text/markdown", title: "Report", origin: .chat(sessionID: nil))
        inspector.open(document)
        inspector.openCoding(store)
        #expect(inspector.isVisible)
        #expect(inspector.hasSelection)
        #expect(inspector.codingReview === store)
        #expect(inspector.selected == document)
        let otherStore = CodingWorkspaceStore(api: FakeCodingAPI())
        inspector.closeCoding(for: otherStore)
        #expect(inspector.isVisible)
        inspector.open(document)
        #expect(inspector.codingReview == nil)
        #expect(store.repository == nil)
        #expect(inspector.selected == document)
        await store.refreshRepository()
        inspector.openCoding(store)
        inspector.closeCoding(for: store)
        #expect(!inspector.isVisible)
        #expect(inspector.codingReview == nil)
        #expect(store.repository == nil)
        #expect(api.stops == 0)
        #expect(api.submissions.isEmpty)
    }

    @Test func repositoryReviewIsExplicitAndIndependentOfSubmission() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(api.repositoryReads == 0)
        await store.refreshRepository()
        let file = try #require(store.repository?.files.first)
        #expect(file.statusLabel == "Staged M · Unstaged M")
        await store.reviewFile(file)
        #expect(store.repositoryDiff?.path == file.path)
        #expect(store.repositoryDiff?.sections.last?.truncated == true)
        #expect(api.submissions.isEmpty)
        #expect(api.stops == 0)
        api.failRepository = true
        await store.refreshRepository()
        #expect(store.repository == nil)
        #expect(store.repositoryDiff == nil)
        #expect(store.repositoryError != nil)
        #expect(store.errorMessage == nil)
        store.draft = "Inspect"
        #expect(store.canSubmit)
    }

    @Test func staleRepositoryAndDiffResultsCannotCrossSelectionsOrDismissal() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        api.delayRepository = true
        let old = Task { await store.refreshRepository() }
        while api.delayedRepository == nil { await Task.yield() }
        await store.select("b")
        api.delayedRepository?.resume(returning: repositoryFixture())
        await old.value
        #expect(store.repository == nil)
        #expect(!store.loadingRepository)
        api.delayRepository = false
        await store.refreshRepository()
        let files = try #require(store.repository?.files)
        api.delayDiff = true
        let first = Task { await store.reviewFile(files[0]) }
        while api.delayedDiff == nil { await Task.yield() }
        let pending = api.delayedDiff
        api.delayDiff = false
        await store.reviewFile(files[1])
        pending?.resume(returning: diffFixture(files[0].path))
        await first.value
        #expect(store.repositoryDiff?.path == files[1].path)
        api.delayDiff = true
        api.delayedDiff = nil
        let dismissed = Task { await store.reviewFile(files[0]) }
        while api.delayedDiff == nil { await Task.yield() }
        store.dismissRepository()
        api.delayedDiff?.resume(returning: diffFixture(files[0].path))
        await dismissed.value
        #expect(store.repositoryDiff == nil)
        #expect(store.repository == nil)
        #expect(!store.loadingDiff)
    }

    @Test func repositoryWireDecodesMixedChangesAndTruncation() throws {
        let result: CodingRepository = try fixture(#"{"basis":"current_worktree","observed_at":"2026-10-16T12:00:00Z","head":null,"files":[{"path":"new&odd.txt","index_status":"?","worktree_status":"?","original_path":null}]}"#)
        #expect(result.head == nil)
        #expect(result.files.first?.statusLabel == "Untracked")
        let diff: CodingRepositoryDiff = try fixture(#"{"basis":"current_worktree","observed_at":"2026-10-16T12:00:00Z","path":"file.txt","sections":[{"kind":"unstaged","text":"+new","truncated":true}]}"#)
        #expect(diff.sections.first?.truncated == true)
    }

    @Test func parsesSSECommentsMultilineAndUnknownFields() throws {
        var parser = CodingSSEParser()
        #expect(try parser.feed(": keep-alive") == nil)
        #expect(try parser.feed("") == nil)
        for line in ["id: 8", "event: assistant.message", "retry: 2000", "data: {\"value\":", "data: \"hello\"}"] {
            #expect(try parser.feed(line) == nil)
        }
        let parsed = try parser.feed("")
        let frame = try #require(parsed)
        #expect(frame.id == "8")
        #expect(frame.event == "assistant.message")
        #expect(String(data: frame.data, encoding: .utf8) == "{\"value\":\n\"hello\"}")
    }

    @Test func parserBoundsUnterminatedFrames() throws {
        var parser = CodingSSEParser()
        #expect(throws: CodingClientError.self) { try parser.feed("data: " + String(repeating: "x", count: 131073)) }
    }

    @Test func completeLargeApprovalSurvivesByteFramingAndDecoding() throws {
        let diff = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-" + String(repeating: "\u{e9}", count: 131072) + "\n+approved\n"
        let payload: [String: Any] = ["schema_version": 1, "run_id": "r", "sequence": 7,
            "kind": "approval.requested", "payload": ["approval_id": "approval", "title": "Approve file change?",
                "message": "fruitcake_edit: file", "expires_at": "2099-10-16T12:00:00Z",
                "change": ["id": "change", "path": "file", "diff": diff, "before_hash": "a", "after_hash": "b"]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = "id: 7\nevent: approval.requested\ndata: " + String(decoding: data, as: UTF8.self) + "\n\n"
        var parser = CodingSSEParser()
        var frames: [CodingSSEFrame] = []
        for byte in wire.utf8 {
            if let frame = try parser.feed(byte: byte) { frames.append(frame) }
        }
        #expect(frames.count == 1)
        let frame = try #require(frames.first)
        let decoded: CodingEvent = try fixture(String(decoding: frame.data, as: UTF8.self))
        let approval = try #require(CodingApproval.requested(decoded))
        #expect(approval.change?.diff == diff)
        #expect(approval.requestSequence == 7)
        // The larger allowance resets with the frame; ordinary events stay small.
        #expect(throws: CodingClientError.self) { try parser.feed("data: " + String(repeating: "x", count: 131073)) }
    }

    @Test func approvalFrameRemainsBounded() throws {
        var parser = CodingSSEParser()
        _ = try parser.feed("event: approval.requested")
        #expect(throws: CodingClientError.self) { try parser.feed("data: " + String(repeating: "x", count: 4 * 1024 * 1024 + 16 * 1024)) }
    }

    @Test func projectionDeduplicatesSnapshotsAndRejectsGaps() throws {
        var projection = CodingProjection()
        let delta = CodingEvent(schemaVersion: 1, runId: "r", sequence: 1, kind: "assistant.text_delta", payload: ["delta": .string("a")])
        try projection.apply(delta, runId: "r")
        try projection.apply(delta, runId: "r")
        #expect(projection.text == "a")
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 2, kind: "assistant.message", payload: ["text": .string("snapshot")]), runId: "r")
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 3, kind: "future.event", payload: [:]), runId: "r")
        #expect(projection.text == "snapshot")
        #expect(projection.cursor == 3)
        #expect(throws: CodingClientError.self) {
            try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 5, kind: "run.completed", payload: [:]), runId: "r")
        }
        #expect(throws: CodingClientError.self) {
            try projection.apply(CodingEvent(schemaVersion: 1, runId: "other", sequence: 4, kind: "run.completed", payload: [:]), runId: "r")
        }
    }

    @Test func decodesStructuredAndLegacyErrors() {
        let structured = CodingClientError.response(status: 409, data: Data(#"{"error":{"code":"session_busy","message":"Busy"},"trace_id":"id"}"#.utf8))
        #expect(structured.code == "session_busy")
        #expect(structured.message == "Busy")
        #expect(!structured.retryable)
        #expect(CodingClientError.response(status: 401, data: Data(#"{"error":"Sign in"}"#.utf8)).message == "Sign in")
        #expect(CodingClientError.response(status: 503, data: Data()).retryable)
    }

    @Test func retriesAmbiguousSubmissionWithOriginalIdentity() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.draft = "Inspect"
        api.failSubmissionOnce = true
        await store.submit()
        let pending = try #require(store.pending)
        #expect(!store.canSubmit)
        await store.retrySubmission()
        #expect(api.submissions == [pending.requestId, pending.requestId])
        #expect(store.pending == nil)
        #expect(store.runs.count == 1)
        #expect(store.draft.isEmpty)
        store.suspend()
    }

    @Test func reconnectReplaysOnlyUnappliedEvents() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture()
        api.failStreamOnce = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        for _ in 0..<250 {
            if store.runs.first?.status == "completed" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(api.streamCursors == [0, 2])
        #expect(store.projections["run-a"]?.text == "Hello world")
        #expect(store.runs.first?.responseText == "Hello world")
        #expect(store.runs.first?.status == "completed")
        store.suspend()
    }

    @Test func leavingWorkspaceDoesNotStopBackendRun() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture()
        api.holdStream = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        for _ in 0..<100 { if !api.streamCursors.isEmpty { break }; await Task.yield() }
        store.suspend()
        for _ in 0..<100 { if api.cancelObserved { break }; await Task.yield() }
        #expect(api.cancelObserved)
        #expect(api.stops == 0)
        #expect(store.activeRun?.id == "run-a")
    }

    @Test func lateSessionResponseCannotOverwriteNewSelection() async throws {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        api.delaySessionA = true
        let oldSelection = Task { await store.select("a") }
        for _ in 0..<100 { if api.delayedHistory != nil { break }; await Task.yield() }
        await store.select("b")
        api.delayedHistory?.resume(returning: [try runFixture("completed")])
        await oldSelection.value
        #expect(store.selectedId == "b")
        #expect(store.runs.isEmpty)
        store.suspend()
    }

    @Test func draftsStayWithTheirSessionAndDisabledBackendIsHonest() async {
        let api = FakeCodingAPI()
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.draft = "Draft A"
        await store.select("b")
        #expect(store.draft.isEmpty)
        store.draft = "Draft B"
        await store.select("a")
        #expect(store.draft == "Draft A")
        api.availability = false
        await store.refresh()
        #expect(!store.available)
        #expect(!store.canSubmit)
        api.availability = true
        api.mode = "write_enabled"
        await store.refresh()
        #expect(!store.available)
        store.suspend()
    }

    @Test func explicitStopTargetsTheVisibleActiveRun() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture()
        api.holdStream = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        await store.stop()
        #expect(api.stops == 1)
        #expect(store.runs.first?.status == "cancelled")
        store.suspend()
    }

    @Test func approvalDecisionUsesDurableIDAndControlIsNotRetried() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture()
        api.holdStream = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        let approval = CodingApproval(id: "durable-approval", runId: "run-a", status: "pending", title: "Read?", message: "file", expiresAt: Date().addingTimeInterval(60))
        await store.resolve(approval, approved: false)
        #expect(api.approvalCalls.first?.0 == "durable-approval")
        #expect(api.approvalCalls.first?.1 == false)
        api.failControl = true
        store.draft = "Focus here"
        await store.control("steer")
        #expect(api.controls == ["steer"])
        #expect(store.draft == "Focus here")
        #expect(store.errorMessage?.contains("not retried automatically") == true)
        store.suspend()
    }

    @Test func operationUpdatesAreSnapshotsNotDuplicateDeltas() throws {
        var projection = CodingProjection()
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 1, kind: "operation.started", payload: ["operation_id": .string("op"), "tool": .string("read")]), runId: "r")
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 2, kind: "operation.output", payload: ["operation_id": .string("op"), "text": .string("Hello"), "mode": .string("snapshot")]), runId: "r")
        try projection.apply(CodingEvent(schemaVersion: 1, runId: "r", sequence: 3, kind: "operation.completed", payload: ["operation_id": .string("op"), "text": .string("Hello world"), "is_error": .bool(false)]), runId: "r")
        #expect(projection.operations.count == 1)
        #expect(projection.operations.first?.output == "Hello world")
        #expect(projection.operations.first?.status == "completed")
    }

    @Test func byteParserBoundsPartialLinesAndRejectsInvalidUTF8() throws {
        var parser = CodingSSEParser()
        for byte: UInt8 in [0xFF, 0xFE] { _ = try parser.feed(byte: byte) }
        #expect(throws: CodingClientError.self) { try parser.feed(byte: 10) }
        var bounded = CodingSSEParser()
        for _ in 0..<131072 { _ = try bounded.feed(byte: 65) }
        #expect(throws: CodingClientError.self) { try bounded.feed(byte: 65) }
    }

    @Test func eventDecodingPreservesPayloadKeysAndNumericModelIdentity() throws {
        let event: CodingEvent = try fixture(#"{"schema_version":1,"run_id":"r","sequence":1,"kind":"session.ready","payload":{"context_reconstructed":true}}"#)
        var projection = CodingProjection()
        try projection.apply(event, runId: "r")
        #expect(projection.reconstructed)
        let model: CodingModelOption = try fixture(#"{"id":42,"label":"Local","model_id":"ollama_chat/fixture"}"#)
        #expect(model.id == 42)
        #expect(model.modelId == "ollama_chat/fixture")
    }
}

#if os(macOS)
import AppKit
import SwiftUI

@Suite @MainActor
struct CodingWorkspaceRenderingTests {
    @Test func rendersCheckoutActionAfterSourceConversationHistory() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        #expect(store.canCreateCheckout && !store.runs.isEmpty)
        let host = NSHostingView(rootView: CodingWorkspaceView(store: store)
            .environment(AuthManager()).environment(ArtifactInspectorState()).frame(width: 1180, height: 1000))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 1000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-coding-source-checkout-action.png"))
        #expect(png.count > 10000)
        store.suspend()
    }
    @Test func rendersOfflineCommandApprovalWithExplicitWritableCheckout() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        api.checkouts["a"] = CodingCheckout(id: "c", sessionId: "a", canonicalPath: "/managed/a",
                                           baselineCommit: "abc123", status: "ready", errorCode: nil)
        api.sessionList[0].commandMode = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.runs[0].status = "waiting_approval"
        let command = CodingCommandPreview(id: "command", command: "python -m unittest discover -v", workingDirectory: ".",
            timeoutSeconds: 120, image: "sha256:" + String(repeating: "a", count: 64), network: "none",
            filesystem: "checkout_read_write", hash: "digest", status: "proposed", result: nil)
        store.approvals = [CodingApproval(id: "approval", runId: "run-a", status: "pending", title: "Approve container command?",
            message: "Offline Docker command; the entire checkout is writable. Review the exact command before approving.",
            expiresAt: nil, command: command)]
        let host = NSHostingView(rootView: CodingWorkspaceView(store: store)
            .environment(AuthManager()).environment(ArtifactInspectorState()).frame(width: 1180, height: 1000))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 1000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-coding-container-command.png"))
        #expect(png.count > 10000)
        store.suspend()
    }
    @Test func rendersChronologicalTranscriptWithSevenApprovals() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.runs[0].status = "waiting_approval"
        var projection = CodingProjection()
        var sequence = 0
        func event(_ kind: String, _ payload: [String: JSONValue]) throws {
            sequence += 1
            let entry = CodingEvent(schemaVersion: 1, runId: "run-a", sequence: sequence, kind: kind, payload: payload)
            try projection.apply(entry, runId: "run-a")
            store.applyApprovalEvent(entry)
        }
        try event("assistant.message", ["text": .string("I will inspect the first three files.")])
        for index in 1...7 {
            if index == 4 { try event("assistant.message", ["text": .string("The first three reads are complete. Next I need four more files.")]) }
            try event("operation.started", ["operation_id": .string("op\(index)"), "tool": .string("read")])
            try event("approval.requested", ["approval_id": .string("a\(index)"), "title": .string("Read file \(index)?"), "message": .string("src/file\(index).swift"), "expires_at": .string("2099-10-16T12:00:00Z")])
            if index <= 3 {
                try event("approval.resolved", ["approval_id": .string("a\(index)"), "status": .string("approved")])
                try event("operation.completed", ["operation_id": .string("op\(index)"), "tool": .string("read"), "is_error": .bool(false)])
            }
        }
        store.projections["run-a"] = projection
        let host = NSHostingView(rootView: CodingWorkspaceView(store: store)
            .environment(AuthManager()).environment(ArtifactInspectorState()).frame(width: 1180, height: 1650))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 1650)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-coding-timeline.png"))
        #expect(png.count > 10000)
        #expect(store.approvals.count == 7)
        store.suspend()
    }

    @Test func rendersApprovedEditProposalInExistingDiffDrawer() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        api.checkouts["a"] = CodingCheckout(id: "c", sessionId: "a", canonicalPath: "/managed/a",
                                           baselineCommit: "abc123", status: "ready", errorCode: nil)
        api.sessionList[0].editMode = true
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        store.runs[0].status = "waiting_approval"
        let change = CodingChangePreview(id: "c", path: "fruitcake-note.txt",
                                        diff: "--- /dev/null\n+++ b/fruitcake-note.txt\n@@ -0,0 +1 @@\n+Approval test\n",
                                        beforeHash: nil, afterHash: String(repeating: "a", count: 64))
        store.approvals = [CodingApproval(id: "approval", runId: "run-a", status: "pending", title: "Approve file change?",
                                         message: "fruitcake_write: fruitcake-note.txt", expiresAt: Date().addingTimeInterval(120), change: change)]
        store.reviewChange(change)
        let host = NSHostingView(rootView: CodingWorkspaceView(store: store)
            .environment(AuthManager()).environment(ArtifactInspectorState()).frame(width: 1180, height: 1000))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 1000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-coding-approved-change.png"))
        #expect(png.count > 10000)
        store.suspend()
    }

    @Test(arguments: [340, 480, 900]) func rendersRepositoryFileInspector(width: Int) async throws {
        let store = CodingWorkspaceStore(api: FakeCodingAPI())
        await store.refresh()
        await store.refreshRepository()
        await store.reviewFile(try #require(store.repository?.files.first))
        let host = NSHostingView(rootView: CodingRepositoryReview(store: store, close: {}).frame(width: CGFloat(width), height: 760))
        host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 760)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-repository-inspector-\(width).png"))
        #expect(png.count > 10000)
        store.suspend()
    }
    @Test(arguments: [600, 1000]) func rendersDiffDrawerBeforeAndAfter(width: Int) async throws {
        let store = CodingWorkspaceStore(api: FakeCodingAPI())
        await store.refresh()
        await store.refreshRepository()
        await store.reviewFile(try #require(store.repository?.files.first))
        store.showDiff()
        let host = NSHostingView(rootView: CodingDiffDrawer(store: store, popOut: {}).frame(width: CGFloat(width), height: 380))
        host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 380)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-diff-drawer-\(width).png"))
        #expect(png.count > 10000)
        store.suspend()
    }
    @Test func rendersReadOnlyWorkspaceWithoutChangingChatLayout() async throws {
        let api = FakeCodingAPI()
        api.remote["run-a"] = try runFixture("completed")
        let store = CodingWorkspaceStore(api: api)
        await store.refresh()
        let view = CodingWorkspaceView(store: store)
            .environment(AuthManager())
            .environment(ArtifactInspectorState())
            .frame(width: 1180, height: 760)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-coding-workspace.png"))
        #expect(png.count > 10000)
        store.suspend()
    }
}
#endif

private final class CodingStreamURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let bytes = Array(": heartbeat\r\n\r\nid: 1\r\nevent: assistant.message\r\ndata: {\"text\":\"caf\u{e9}\"}\r\n\r\n".utf8)
        for start in stride(from: 0, to: bytes.count, by: 3) {
            client?.urlProtocol(self, didLoad: Data(bytes[start..<min(start + 3, bytes.count)]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite @MainActor
struct CodingSSETransportTests {
    @Test func byteFramingPreservesSSEBoundariesAndUTF8AcrossChunks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodingStreamURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, _) = try await session.bytes(from: URL(string: "https://coding-fixture.invalid/events")!)
        var parser = CodingSSEParser()
        var frames: [CodingSSEFrame] = []
        for try await byte in bytes {
            if let frame = try parser.feed(byte: byte) { frames.append(frame) }
        }
        #expect(frames.count == 1)
        #expect(frames.first?.id == "1")
        #expect(frames.first?.event == "assistant.message")
        #expect(frames.first.map { String(data: $0.data, encoding: .utf8) } == "{\"text\":\"caf\u{e9}\"}")
    }
}

@Test @MainActor func repositorySetupUsesNativeDirectoryAndCreationPanels() throws {
    let existing = try #require(CodingRepositorySetupMode.authorize.makePanel() as? NSOpenPanel)
    #expect(existing.canChooseDirectories)
    #expect(!existing.canChooseFiles)
    #expect(!existing.allowsMultipleSelection)
    #expect(!existing.canCreateDirectories)
    let creation = CodingRepositorySetupMode.create.makePanel()
    #expect(!(creation is NSOpenPanel))
    #expect(creation.nameFieldStringValue == "NewRepository")
    #expect(creation.canCreateDirectories)
}

@Test @MainActor func repositoryCreationRequiresExplicitActionAndDoesNotEnableExecution() async {
    let api = FakeCodingAPI()
    let store = CodingWorkspaceStore(api: api)
    await store.resume()
    #expect(api.repositoryCreations.isEmpty)
    store.errorMessage = "Old error"
    #expect(await store.grant(userId: 2, path: "/new/repository", createRepository: true))
    #expect(api.repositoryCreations == ["/new/repository"])
    #expect(store.workspaces.contains { $0.id == "new-repository" && $0.canonicalPath == "/new/repository" })
    #expect(store.errorMessage == nil)
    #expect(api.checkoutCreates.isEmpty)
    #expect(api.submissions.isEmpty)
    #expect(!store.actionInFlight)
    store.suspend()
}

@Test @MainActor func repositoryCreationFailureDoesNotAddGrantOrFallBackToAuthorization() async {
    let api = FakeCodingAPI()
    api.failRepositoryCreation = true
    let store = CodingWorkspaceStore(api: api)
    #expect(!(await store.grant(userId: 2, path: "/already/exists", createRepository: true)))
    #expect(store.workspaces.isEmpty)
    #expect(store.errorMessage?.contains("already exists") == true)
    #expect(!store.actionInFlight)
}

@Test @MainActor func modelSwitchAndSessionDeletionPreserveCheckout() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    await store.changeModel(2)
    #expect(store.selected?.modelProfileId == 2)
    #expect(api.modelChanges == [2])
    #expect(store.selected?.editMode == false)
    #expect(store.checkout?.id == "shared")
    await store.removeConversation(id: "a", delete: true)
    #expect(!store.sessions.contains { $0.id == "a" })
    #expect(api.checkouts["a"]?.id == "shared")
    store.suspend()
}

@Test @MainActor func newSessionContinuesExactCheckoutAndArchiveCanBeRestored() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    #expect(await store.create(workspaceId: "w", modelId: 1, projectId: nil, title: "Review", checkoutId: "shared"))
    #expect(api.joinedCheckouts == ["shared"])
    #expect(store.selectedId == "joined")
    #expect(store.checkout?.canonicalPath == "/managed/shared")
    await store.removeConversation(id: "joined", delete: false)
    #expect(!store.sessions.contains { $0.id == "joined" })
    await store.toggleArchivedSessions()
    #expect(store.sessions.map(\.id) == ["joined"])
    await store.removeConversation(id: "joined", delete: false, archived: false)
    await store.toggleArchivedSessions()
    #expect(store.sessions.contains { $0.id == "joined" })
    store.suspend()
}

@Test @MainActor func confirmedCommitShowsSessionScopedDismissibleFeedback() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    let preview = try #require(await store.previewDelivery(sessionId: "a", action: "commit", files: ["file.txt"], message: "Change"))
    #expect(store.deliveryNotice == nil)
    #expect(await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change"))
    #expect(store.deliveryNotice?.title == "Committed locally · new")
    #expect(store.deliveryNotice?.detail.contains("Not yet applied") == true)
    await store.refresh()
    #expect(store.deliveryNotice?.head == "new")
    await store.select("b")
    #expect(store.deliveryNotice == nil)
    await store.select("a")
    #expect(store.deliveryNotice?.head == "new")
    store.dismissDeliveryNotice()
    await store.select("a")
    #expect(store.deliveryNotice == nil)
    store.suspend()
}

@Test @MainActor func confirmedApplyShowsDestinationAndRetainsCheckout() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    let preview = CodingDeliveryPreview(action: "apply", checkoutId: "shared", head: "new", diff: "diff", reviewHash: "reviewed", sourcePath: "/source/repository", sourceBranch: "refs/heads/main")
    #expect(await store.confirmDelivery(sessionId: "a", preview: preview, files: [], message: ""))
    #expect(store.deliveryNotice?.title == "Applied to main · new")
    #expect(store.deliveryNotice?.detail.contains("/source/repository") == true)
    #expect(store.deliveryNotice?.detail.contains("remains in its isolated checkout") == true)
    #expect(store.executionPath == "/managed/shared")
    store.suspend()
}

@Test @MainActor func failedOrMismatchedDeliveryDoesNotReportSuccess() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    let preview = try #require(await store.previewDelivery(sessionId: "a", action: "commit", files: ["file.txt"], message: "Change"))
    api.failDelivery = true
    #expect(!(await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change")))
    #expect(store.deliveryNotice == nil)
    api.failDelivery = false
    api.deliveryResult = CodingDeliveryResult(action: "apply", head: "new", checkoutId: "other")
    #expect(!(await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change")))
    #expect(store.deliveryNotice == nil)
    #expect(store.errorMessage?.contains("unexpected") == true)
    store.suspend()
}

@Test @MainActor func lateDeliveryFeedbackDoesNotPullUserBackToPreviousSession() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    let preview = try #require(await store.previewDelivery(sessionId: "a", action: "commit", files: ["file.txt"], message: "Change"))
    api.delayDelivery = true
    let confirmation = Task { await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change") }
    while api.delayedDelivery == nil { await Task.yield() }
    await store.select("b")
    api.delayedDelivery?.resume(returning: CodingDeliveryResult(action: "commit", head: "new", checkoutId: "shared"))
    #expect(await confirmation.value)
    #expect(store.selectedId == "b")
    #expect(store.deliveryNotice == nil)
    await store.select("a")
    #expect(store.deliveryNotice?.head == "new")
    store.suspend()
}

@Test @MainActor func deliveryDoesNotCrossSessionSelectionOrRetryLostConfirmation() async throws {
    let api = FakeCodingAPI()
    api.checkouts["a"] = CodingCheckout(id: "shared", sessionId: "a", canonicalPath: "/managed/shared", baselineCommit: "base", status: "ready", errorCode: nil)
    let store = CodingWorkspaceStore(api: api)
    await store.refresh()
    let preview = try #require(await store.previewDelivery(sessionId: "a", action: "commit", files: ["file.txt"], message: "Change"))
    await store.select("b")
    #expect(!(await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change")))
    #expect(api.deliveryConfirms == 0)
    await store.select("a")
    api.failDelivery = true
    #expect(!(await store.confirmDelivery(sessionId: "a", preview: preview, files: ["file.txt"], message: "Change")))
    #expect(api.deliveryConfirms == 1)
    #expect(store.errorMessage?.contains("inspection") == true)
    store.suspend()
}

#if os(macOS)
@Test @MainActor func rendersGitConfirmationWithLongSourcePathAtNarrowWidth() async throws {
    let notice = CodingWorkspaceStore.DeliveryNotice(
        result: CodingDeliveryResult(action: "apply", head: "62e3a762655be3abf166ca8ff9a6e758ead335ae", checkoutId: "shared"),
        preview: CodingDeliveryPreview(action: "apply", checkoutId: "shared", head: "62e3a76", diff: "", reviewHash: "reviewed", sourcePath: "/Users/operator/Development/A long repository directory name/Repository", sourceBranch: "refs/heads/main"))
    let host = NSHostingView(rootView: CodingDeliveryNoticeBanner(notice: notice, dismiss: {}).frame(width: 440).background(Theme.bg))
    let height = host.fittingSize.height
    #expect(height > 60)
    host.frame = NSRect(x: 0, y: 0, width: 440, height: height)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-git-confirmation.png"))
}

@Test @MainActor func rendersDeliveryPanelInNarrowAndWideTopDrawer() async throws {
    let store = CodingWorkspaceStore(api: FakeCodingAPI())
    await store.refresh()
    for width in [600.0, 1180.0] {
        let view = CodingDeliveryPanel(store: store, sessionId: "a", action: "commit", popOut: { _ in })
            .frame(width: width, height: 380)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 380)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fruitcake-delivery-panel-\(Int(width)).png"))
        #expect(bitmap.pixelsWide >= Int(width))
    }
    store.suspend()
}
#endif
