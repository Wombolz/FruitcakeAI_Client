import Foundation
import Observation

@MainActor
protocol CodingServing: CodingReviewServing {
    func codingAvailability() async throws -> CodingAvailability
    func codingWorkspaces() async throws -> [CodingWorkspace]
    func codingModels() async throws -> [CodingModelOption]
    func codingProjects() async throws -> [CodingProjectOption]
    func codingSessions(offset: Int) async throws -> [CodingSession]
    func createCodingSession(workspaceId: String, modelId: Int, projectId: Int?, title: String) async throws -> CodingSession
    func codingRuns(sessionId: String, offset: Int) async throws -> [CodingRun]
    func codingRun(id: String) async throws -> CodingRun
    func submitCoding(sessionId: String, message: String, requestId: String) async throws -> CodingRun
    func stopCoding(runId: String) async throws
    func controlCoding(runId: String, action: String, message: String) async throws
    func codingApprovals(runId: String) async throws -> [CodingApproval]
    func resolveCodingApproval(id: String, approved: Bool, changeHash: String?) async throws
    func closeCodingSession(id: String) async throws
    func grantCodingWorkspace(userId: Int, path: String) async throws -> CodingWorkspace
    func createCodingRepository(userId: Int, path: String) async throws -> CodingWorkspace
    func codingReusableCheckouts() async throws -> [CodingCheckout]
    func codingSessionPage(offset: Int, archived: Bool) async throws -> [CodingSession]
    func createCodingSessionInCheckout(workspaceId: String, modelId: Int, projectId: Int?, title: String, checkoutId: String) async throws -> CodingSession
    func changeCodingModel(sessionId: String, modelId: Int) async throws -> CodingSession
    func archiveCodingSession(sessionId: String, archived: Bool) async throws -> CodingSession
    func deleteCodingSession(sessionId: String) async throws
    func previewCodingDelivery(sessionId: String, action: String, files: [String], message: String) async throws -> CodingDeliveryPreview
    func confirmCodingDelivery(sessionId: String, action: String, files: [String], message: String, hash: String) async throws -> CodingDeliveryResult
    func codingExplorerRoot(sessionId: String) async throws -> InspectorRoot
    func codingExplorerDirectory(sessionId: String, rootId: String, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage
    func codingExplorerFile(sessionId: String, rootId: String, path: String) async throws -> InspectorFileContent
    func codingRepository(sessionId: String) async throws -> CodingRepository
    func codingRepositoryDiff(sessionId: String, path: String) async throws -> CodingRepositoryDiff
    func codingCheckout(sessionId: String) async throws -> CodingCheckout?
    func createCodingCheckout(sessionId: String) async throws -> CodingCheckout
    func removeCodingCheckout(sessionId: String) async throws -> CodingCheckout
    func setCodingEditMode(sessionId: String, enabled: Bool) async throws -> CodingSession
    func setCodingCommandMode(sessionId: String, enabled: Bool) async throws -> CodingSession
    func resolveCodingCommand(id: String, approved: Bool, commandHash: String?) async throws
    func codingChanges(runId: String) async throws -> [CodingSavedChange]
    func streamCoding(runId: String, after: Int, follow: Bool, onEvent: @escaping @MainActor (CodingEvent) async throws -> Void) async throws
}

extension CodingServing {
    func codingExplorerRoot(sessionId: String) async throws -> InspectorRoot { throw CodingClientError(code: "unsupported", message: "Update the backend to use Explorer.") }
    func codingExplorerDirectory(sessionId: String, rootId: String, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage { throw CodingClientError(code: "unsupported", message: "Directory inspection is unavailable.") }
    func codingExplorerFile(sessionId: String, rootId: String, path: String) async throws -> InspectorFileContent { throw CodingClientError(code: "unsupported", message: "File inspection is unavailable.") }
    func codingReusableCheckouts() async throws -> [CodingCheckout] { [] }
    func codingSessionPage(offset: Int, archived: Bool) async throws -> [CodingSession] {
        if archived { return [] }
        return try await codingSessions(offset: offset)
    }
    func createCodingSessionInCheckout(workspaceId: String, modelId: Int, projectId: Int?, title: String, checkoutId: String) async throws -> CodingSession { throw CodingClientError(code: "unsupported", message: "Update the backend to continue a checkout.") }
    func changeCodingModel(sessionId: String, modelId: Int) async throws -> CodingSession { throw CodingClientError(code: "unsupported", message: "Model switching is unavailable.") }
    func archiveCodingSession(sessionId: String, archived: Bool) async throws -> CodingSession { throw CodingClientError(code: "unsupported", message: "Archiving is unavailable.") }
    func deleteCodingSession(sessionId: String) async throws { throw CodingClientError(code: "unsupported", message: "Session deletion is unavailable.") }
    func previewCodingDelivery(sessionId: String, action: String, files: [String], message: String) async throws -> CodingDeliveryPreview { throw CodingClientError(code: "unsupported", message: "Git delivery is unavailable.") }
    func confirmCodingDelivery(sessionId: String, action: String, files: [String], message: String, hash: String) async throws -> CodingDeliveryResult { throw CodingClientError(code: "unsupported", message: "Git delivery is unavailable.") }
    func createCodingRepository(userId: Int, path: String) async throws -> CodingWorkspace {
        throw CodingClientError(code: "unsupported", message: "Repository creation requires an updated backend and client adapter.")
    }
    func setCodingCommandMode(sessionId: String, enabled: Bool) async throws -> CodingSession {
        throw CodingClientError(code: "unsupported", message: "Container commands are unavailable in this client adapter.")
    }
    func resolveCodingCommand(id: String, approved: Bool, commandHash: String?) async throws {
        throw CodingClientError(code: "unsupported", message: "Container command approvals are unavailable in this client adapter.")
    }
}

@Observable @MainActor
final class CodingWorkspaceStore {
    struct DeliveryNotice {
        let title: String
        let detail: String
        let head: String

        init(result: CodingDeliveryResult, preview: CodingDeliveryPreview) {
            head = result.head
            let shortHead = String(result.head.prefix(12))
            if result.action == "apply" {
                let branch = preview.sourceBranch?.replacingOccurrences(of: "refs/heads/", with: "") ?? "source"
                title = "Applied to \(branch) · \(shortHead)"
                detail = "\(preview.sourcePath ?? "Source repository")\nThis conversation remains in its isolated checkout."
            } else {
                title = "Committed locally · \(shortHead)"
                detail = "Branch: \(preview.branch ?? "managed checkout"). Not yet applied to the source repository."
            }
        }
    }

    struct PendingSubmission {
        let sessionId: String
        let message: String
        let requestId: String
    }

    private let api: any CodingServing
    let aiReview: CodingAIReviewStore
    private var observer: Task<Void, Never>?
    private var checkoutObserver: Task<Void, Never>?
    private var selectionGeneration = UUID()
    private var observing = true
    private var drafts: [String: String] = [:]
    private var reviewGeneration = UUID()
    private var diffGeneration = UUID()
    private var unknownEditModes: Set<String> = []
    private var approvalStates: [String: String] = [:]
    private var deliveryNotices: [String: DeliveryNotice] = [:]
    private(set) var repository: CodingRepository?
    private(set) var repositoryDiff: CodingRepositoryDiff?
    private(set) var repositoryError: String?
    private(set) var loadingRepository = false
    private(set) var loadingDiff = false
    private(set) var reviewedPath: String?
    private(set) var diffVisible = false
    private(set) var checkout: CodingCheckout?
    private(set) var checkoutLoaded = false
    private(set) var supportsCheckouts = false
    private(set) var supportsApprovedEdits = false
    private(set) var supportsContainerCommands = false
    private(set) var editModeKnown = true
    private(set) var reviewedChanges: Set<String> = []
    private(set) var savedChanges: [String: [CodingSavedChange]] = [:]
    var available = false
    var loading = false
    var loadingRuns = false
    var actionInFlight = false
    var errorMessage: String?
    var connection = "Not connected"
    var sessions: [CodingSession] = []
    var workspaces: [CodingWorkspace] = []
    var reusableCheckouts: [CodingCheckout] = []
    var showingArchived = false
    var deliveryAction: String?
    var models: [CodingModelOption] = []
    var projects: [CodingProjectOption] = []
    var selectedId: String?
    var runs: [CodingRun] = []
    var approvals: [CodingApproval] = []
    var projections: [String: CodingProjection] = [:]
    var draft = ""
    private(set) var pending: PendingSubmission?
    var hasMoreSessions = false
    var hasMoreRuns = false

    init(api: any CodingServing) { self.api = api; aiReview = CodingAIReviewStore(api: api) }
    var selected: CodingSession? { sessions.first { $0.id == selectedId } }
    var deliveryNotice: DeliveryNotice? { selectedId.flatMap { deliveryNotices[$0] } }

    func dismissDeliveryNotice() {
        if let selectedId { deliveryNotices.removeValue(forKey: selectedId) }
    }
    var workspace: CodingWorkspace? { workspaces.first { $0.id == selected?.workspaceId } }
    var activeRun: CodingRun? { runs.last { $0.isActive } }
    var editingEnabled: Bool { selected?.editMode == true }
    var commandsEnabled: Bool { selected?.commandMode == true }
    var modeLabel: String { commandsEnabled ? "container commands · writable checkout · offline" : editingEnabled ? "approved edits" : "read only" }
    var canSetCommandMode: Bool {
        !aiReview.busy && supportsContainerCommands && available && checkoutLoaded && checkout?.status == "ready"
        && selected != nil && selected?.isClosed == false && activeRun == nil && workspace?.isActive == true
        && !actionInFlight && !loadingRuns && pending == nil && editModeKnown
    }
    var canSetEditMode: Bool {
        !aiReview.busy && supportsApprovedEdits && available && checkoutLoaded && checkout?.status == "ready"
        && selected != nil && selected?.isClosed == false && activeRun == nil && workspace?.isActive == true
        && !actionInFlight && !loadingRuns && pending == nil && editModeKnown
    }
    var executionPath: String? {
        if let checkout { return ["ready", "failed"].contains(checkout.status) ? checkout.canonicalPath : nil }
        return !supportsCheckouts || checkoutLoaded ? workspace?.canonicalPath : nil
    }
    var canCreateCheckout: Bool {
        checkoutCreationBlockReason == nil
    }
    var checkoutCreationBlockReason: String? {
        guard !aiReview.busy else { return "Finish or stop the review before changing this checkout." }
        guard available else { return "Connect to the coding backend before creating a checkout." }
        guard supportsCheckouts else { return "This backend does not support isolated checkouts. Update and restart it." }
        guard let selected else { return "Choose or create a coding session for this repository first." }
        guard !selected.isClosed else { return "This session is closed. Create a new session for another checkout." }
        guard workspace?.isActive == true else { return "This repository's access grant is unavailable or inactive." }
        guard !loadingRuns && checkoutLoaded else { return "Loading checkout status. Refresh if it does not finish." }
        guard checkout == nil else { return "This session already has an isolated checkout." }
        guard activeRun == nil && ["idle", "interrupted"].contains(selected.status) else { return "Stop or finish the active run before creating an isolated checkout." }
        guard pending == nil else { return "Reconcile the pending submission before changing the execution location." }
        guard !actionInFlight && !loading else { return "Wait for the current action to finish." }
        return nil
    }
    var canSubmit: Bool {
        !aiReview.busy && available && !loading && !actionInFlight && !loadingRuns && pending == nil && selected != nil
        && deliveryAction == nil
        && selected?.isClosed == false && workspace?.isActive == true && activeRun == nil
        && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.unicodeScalars.count <= 32000
        && (!supportsCheckouts || checkoutLoaded) && (checkout == nil || checkout?.status == "ready") && editModeKnown
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        errorMessage = nil
        do {
            let status = try await api.codingAvailability()
            supportsCheckouts = status.managedCheckouts == true
            supportsApprovedEdits = status.approvedEdits == true
            supportsContainerCommands = status.containerCommands == true
            aiReview.setEnabled(status.aiReviews == true)
            guard status.enabled, status.eventSchemaVersion == 1, status.mode == "read_only" else {
                available = false
                suspend()
                connection = status.enabled ? "Unsupported coding mode or event schema" : "Coding is disabled on this backend"
                return
            }
            async let grants = api.codingWorkspaces()
            async let choices = api.codingModels()
            async let history = api.codingSessionPage(offset: 0, archived: showingArchived)
            async let projectChoices = api.codingProjects()
            let values = try await (grants, choices, history, projectChoices)
            let previous = selected
            workspaces = values.0; models = values.1; sessions = values.2; projects = values.3
            unknownEditModes.subtract(Set(sessions.map(\.id)))
            if let previous, !sessions.contains(where: { $0.id == previous.id }) { sessions.append(previous) }
            available = true
            hasMoreSessions = sessions.count == 100
            connection = "Ready"
            if let selectedId, sessions.contains(where: { $0.id == selectedId }) {
                await select(selectedId)
            } else if let first = sessions.first { await select(first.id) }
        } catch is CancellationError { return }
        catch {
            if let failure = error as? CodingClientError, failure.status == 404 {
                errorMessage = "This backend does not expose the coding API. Restart the backend from the coding-runtime branch after applying migrations through 057."
            } else { errorMessage = error.localizedDescription }
            connection = "Connection unavailable"
        }
    }

    func moreSessions() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.codingSessionPage(offset: sessions.count, archived: showingArchived)
            let known = Set(sessions.map(\.id))
            sessions += page.filter { !known.contains($0.id) }
            hasMoreSessions = page.count == 100
        } catch { errorMessage = error.localizedDescription }
    }

    func select(_ id: String) async {
        guard aiReview.pending == nil || selectedId == id else {
            errorMessage = "Reconcile the pending review start before switching sessions."
            return
        }
        guard pending == nil || pending?.sessionId == id else {
            errorMessage = "Resolve the pending submission before switching sessions. Retry uses its original request ID."
            return
        }
        deliveryAction = nil
        observer?.cancel()
        checkoutObserver?.cancel(); checkoutObserver = nil
        checkout = nil; checkoutLoaded = false
        dismissRepository()
        let generation = UUID()
        selectionGeneration = generation
        if selectedId != id {
            if let selectedId { drafts[selectedId] = draft }
            draft = drafts[id] ?? ""
        }
        if aiReview.sessionId != id { aiReview.reset(sessionId: id) }
        selectedId = id; runs = []; approvals = []; projections = [:]; approvalStates = [:]
        savedChanges = [:]; reviewedChanges = []; editModeKnown = !unknownEditModes.contains(id)
        connection = "Loading session"
        loadingRuns = true
        defer { if selectionGeneration == generation { loadingRuns = false } }
        do {
            let page = try await api.codingRuns(sessionId: id, offset: 0)
            let currentCheckout = supportsCheckouts ? try await api.codingCheckout(sessionId: id) : nil
            guard selectionGeneration == generation else { return }
            guard currentCheckout == nil || currentCheckout?.sessionId == id else {
                throw CodingClientError(code: "invalid_checkout", message: "The backend returned another session's checkout.")
            }
            checkout = currentCheckout; checkoutLoaded = true
            runs = page.reversed()
            hasMoreRuns = page.count == 100
            reconcilePending()
            if let activeRun { observe(activeRun.id, generation: generation) }
            else { connection = selected?.isClosed == true ? "Closed" : "Ready - \(modeLabel)" }
            if checkout?.isBusy == true { observeCheckout(sessionId: id, generation: generation) }
            if aiReview.enabled { await aiReview.resume() }
        } catch is CancellationError { return }
        catch { if selectionGeneration == generation { errorMessage = error.localizedDescription } }
    }

    func createCheckout() async {
        guard canCreateCheckout, let id = selectedId else { return }
        await checkoutAction(sessionId: id, removing: false)
    }

    func removeCheckout() async {
        guard !aiReview.busy, let id = selectedId, selected?.isClosed == true, checkout != nil,
              checkout?.isBusy == false, !actionInFlight else { return }
        await checkoutAction(sessionId: id, removing: true)
    }

    private func checkoutAction(sessionId: String, removing: Bool) async {
        let generation = selectionGeneration
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let result = removing ? try await api.removeCodingCheckout(sessionId: sessionId)
                                  : try await api.createCodingCheckout(sessionId: sessionId)
            guard generation == selectionGeneration, selectedId == sessionId else { return }
            guard result.sessionId == sessionId else {
                throw CodingClientError(code: "invalid_checkout", message: "The backend returned another session's checkout.")
            }
            checkout = result; checkoutLoaded = true
            dismissRepository()
            if result.isBusy { observeCheckout(sessionId: sessionId, generation: generation) }
        } catch {
            guard generation == selectionGeneration else { return }
            errorMessage = error.localizedDescription + " Refresh to reconcile checkout state; the session-bound operation is safe to retry."
            checkoutLoaded = false
        }
    }

    private func observeCheckout(sessionId: String, generation: UUID) {
        checkoutObserver?.cancel()
        checkoutObserver = Task { [weak self] in
            guard let self else { return }
            do {
                for _ in 0..<45 {
                    try await Task.sleep(for: .seconds(2))
                    let result = try await api.codingCheckout(sessionId: sessionId)
                    guard generation == selectionGeneration, selectedId == sessionId else { return }
                    guard result?.sessionId == sessionId else {
                        checkoutLoaded = false
                        throw CodingClientError(code: "invalid_checkout", message: "The managed checkout status disappeared or changed identity.")
                    }
                    checkout = result; checkoutLoaded = true
                    if result?.isBusy != true { return }
                }
                errorMessage = "Checkout is taking longer than expected. Refresh to check its durable status."
            } catch is CancellationError { return }
            catch {
                if Task.isCancelled { return }
                if generation == selectionGeneration { errorMessage = "Checkout status is unavailable. Refresh to reconnect." }
            }
        }
    }

    func dismissRepository() {
        reviewGeneration = UUID(); diffGeneration = UUID()
        repository = nil; repositoryDiff = nil; repositoryError = nil; reviewedPath = nil
        loadingRepository = false; loadingDiff = false
        diffVisible = false
    }

    func showDiff() {
        guard reviewedPath != nil else { return }
        diffVisible = true
    }

    func closeDiff() { diffVisible = false }

    func makeInspectorReview(sessionID: String) -> CodingAIReviewStore {
        let review = CodingAIReviewStore(api: api)
        review.setEnabled(aiReview.enabled)
        review.reset(sessionId: sessionID)
        review.suspend()
        return review
    }

    func inspectChangedFile(sessionID: String, path: String) async throws -> CodingRepositoryDiff {
        guard selectedId == sessionID else { throw CancellationError() }
        let generation = selectionGeneration
        let value = try await api.codingRepositoryDiff(sessionId: sessionID, path: path)
        guard !Task.isCancelled, generation == selectionGeneration, selectedId == sessionID else { throw CancellationError() }
        guard value.basis == "current_worktree", value.path == path else {
            throw CodingClientError(code: "invalid_repository", message: "The backend returned a mismatched file preview.")
        }
        return value
    }

    func showObservedDiff(_ value: CodingRepositoryDiff, sessionID: String) {
        guard selectedId == sessionID, value.basis == "current_worktree" else { return }
        diffGeneration = UUID(); loadingDiff = false; repositoryError = nil
        reviewedPath = value.path; repositoryDiff = value; diffVisible = true
        deliveryAction = nil
    }

    func showCapturedDiff(_ diff: CodingRepositoryDiff, review source: CodingAIReviewStore? = nil) {
        let review = source ?? aiReview
        guard let sessionID = selectedId, review.sessionId == sessionID,
              let captureID = review.selected?.captureId,
              diff.basis == "review_capture", diff.captureId == captureID else { return }
        diffGeneration = UUID(); loadingDiff = false; repositoryError = nil
        reviewedPath = diff.path; repositoryDiff = diff; diffVisible = true
        deliveryAction = nil
    }

    func draftCorrection(_ finding: CodingReviewFinding, review source: CodingAIReviewStore? = nil) async {
        let review = source ?? aiReview
        guard review.sessionId == selectedId else { return }
        let generation = selectionGeneration
        guard let text = await review.correction(finding), generation == selectionGeneration else { return }
        let combined = draft.isEmpty ? text : draft + "\n\n" + text
        guard combined.unicodeScalars.count <= 32000 else {
            review.error = "The composer has insufficient room. Your existing draft was left unchanged."
            return
        }
        draft = combined
    }

    func reviewChange(_ change: CodingChangePreview) {
        presentStoredDiff(path: change.path, diff: change.diff, basis: "approval", at: Date(), kind: "proposed")
        reviewedChanges.insert(change.id)
    }

    func reviewSavedChange(_ change: CodingSavedChange) {
        presentStoredDiff(path: change.path, diff: change.diff, basis: "saved_change", at: change.appliedAt ?? change.createdAt, kind: change.status)
    }

    private func presentStoredDiff(path: String, diff: String, basis: String, at: Date, kind: String) {
        diffGeneration = UUID()
        loadingDiff = false; repositoryError = nil; reviewedPath = path
        repositoryDiff = CodingRepositoryDiff(basis: basis, observedAt: at, path: path,
                                             sections: [.init(kind: kind, text: diff, truncated: false)])
        diffVisible = true
    }

    func setEditMode(_ enabled: Bool) async {
        guard canSetEditMode, let id = selectedId else { return }
        let generation = selectionGeneration
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let result = try await api.setCodingEditMode(sessionId: id, enabled: enabled)
            guard generation == selectionGeneration else { return }
            guard result.id == id, result.editMode == enabled else {
                throw CodingClientError(code: "invalid_mode", message: "The backend returned mismatched edit-mode state.")
            }
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index] = result }
            connection = "Ready - \(modeLabel)"
        } catch {
            unknownEditModes.insert(id)
            if generation == selectionGeneration {
                editModeKnown = false
                errorMessage = "Edit-mode response was lost or refused. Refresh to reconcile before submitting."
            }
        }
    }

    func setCommandMode(_ enabled: Bool) async {
        guard canSetCommandMode, let id = selectedId else { return }
        let generation = selectionGeneration
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let result = try await api.setCodingCommandMode(sessionId: id, enabled: enabled)
            guard generation == selectionGeneration else { return }
            guard result.id == id, result.commandMode == enabled else {
                throw CodingClientError(code: "invalid_mode", message: "The backend returned mismatched command-mode state.")
            }
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index] = result }
            connection = "Ready - \(modeLabel)"
        } catch {
            unknownEditModes.insert(id)
            if generation == selectionGeneration {
                editModeKnown = false
                errorMessage = "Command-mode response was lost or refused. Refresh to reconcile before submitting. \(error.localizedDescription)"
            }
        }
    }

    func loadSavedChanges(_ run: CodingRun) async {
        guard supportsApprovedEdits, run.sessionId == selectedId else { return }
        let generation = selectionGeneration
        do {
            let records = try await api.codingChanges(runId: run.id)
            guard generation == selectionGeneration else { return }
            guard records.allSatisfy({ $0.runId == run.id }) else {
                throw CodingClientError(code: "invalid_changes", message: "The backend returned another run's changes.")
            }
            savedChanges[run.id] = records
        } catch { if generation == selectionGeneration { errorMessage = error.localizedDescription } }
    }

    func releaseRepositoryInspector() {
        if !diffVisible { dismissRepository() }
    }

    func refreshRepository(preserveDiff: Bool = false) async {
        guard let id = selectedId, available, workspace?.isActive == true, !loadingRepository else { return }
        if preserveDiff {
            reviewGeneration = UUID(); repository = nil; repositoryError = nil
        } else { dismissRepository() }
        let generation = reviewGeneration
        loadingRepository = true
        defer { if reviewGeneration == generation { loadingRepository = false } }
        do {
            let result = try await api.codingRepository(sessionId: id)
            guard reviewGeneration == generation, selectedId == id else { return }
            guard result.basis == "current_worktree" else {
                throw CodingClientError(code: "invalid_repository", message: "Unsupported repository review format.")
            }
            repository = result
        } catch is CancellationError { return }
        catch {
            if reviewGeneration == generation {
                if let status = (error as? CodingClientError)?.status, [401, 403, 404].contains(status) { dismissRepository() }
                repositoryError = repositoryMessage(error)
            }
        }
    }

    func reviewFile(_ file: CodingChangedFile) async {
        guard let id = selectedId, repository?.files.contains(where: { $0.id == file.id }) == true else { return }
        let review = reviewGeneration
        let generation = UUID()
        diffGeneration = generation
        reviewedPath = file.path; repositoryDiff = nil; repositoryError = nil; loadingDiff = true
        defer { if diffGeneration == generation { loadingDiff = false } }
        do {
            let result = try await api.codingRepositoryDiff(sessionId: id, path: file.path)
            guard reviewGeneration == review, diffGeneration == generation, selectedId == id else { return }
            guard result.basis == "current_worktree", result.path == file.path else {
                throw CodingClientError(code: "invalid_repository", message: "The backend returned a mismatched file preview.")
            }
            repositoryDiff = result
        } catch is CancellationError { return }
        catch { if reviewGeneration == review, diffGeneration == generation { repositoryError = repositoryMessage(error) } }
    }

    private func repositoryMessage(_ error: Error) -> String {
        if let failure = error as? CodingClientError, failure.status == 404 {
            return "Repository review is unavailable on this backend, or this coding session is no longer accessible. Update the backend and refresh."
        }
        return error.localizedDescription
    }

    func moreRuns() async {
        guard let id = selectedId, !loadingRuns else { return }
        let generation = selectionGeneration
        loadingRuns = true
        defer { if generation == selectionGeneration { loadingRuns = false } }
        do {
            let page = try await api.codingRuns(sessionId: id, offset: runs.count)
            guard generation == selectionGeneration else { return }
            let known = Set(runs.map(\.id))
            runs = page.reversed().filter { !known.contains($0.id) } + runs
            hasMoreRuns = page.count == 100
        } catch { errorMessage = error.localizedDescription }
    }

    func create(workspaceId: String, modelId: Int, projectId: Int?, title: String, checkoutId: String? = nil) async -> Bool {
        guard !actionInFlight, pending == nil else { return false }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let created: CodingSession
            if let checkoutId { created = try await api.createCodingSessionInCheckout(workspaceId: workspaceId, modelId: modelId, projectId: projectId, title: title, checkoutId: checkoutId) }
            else { created = try await api.createCodingSession(workspaceId: workspaceId, modelId: modelId, projectId: projectId, title: title) }
            if showingArchived { showingArchived = false; sessions = [] }
            sessions.insert(created, at: 0)
            await select(created.id)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func submit() async {
        guard canSubmit, let id = selectedId else { return }
        pending = PendingSubmission(sessionId: id, message: draft, requestId: UUID().uuidString)
        await retrySubmission()
    }

    func retrySubmission() async {
        guard let request = pending, !actionInFlight else { return }
        actionInFlight = true; errorMessage = nil
        defer { actionInFlight = false }
        do {
            let run = try await api.submitCoding(sessionId: request.sessionId, message: request.message, requestId: request.requestId)
            pending = nil; draft = ""
            if selectedId == request.sessionId {
                replace(run)
                if run.isActive { observe(run.id, generation: selectionGeneration) }
            }
        } catch is CancellationError {
            errorMessage = "Submission was interrupted. Retry safely with the same request ID."
        } catch {
            errorMessage = error.localizedDescription
            if let failure = error as? CodingClientError, let status = failure.status, (400...499).contains(status) {
                pending = nil
            }
        }
    }

    func stop() async {
        guard let run = activeRun, !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do { try await api.stopCoding(runId: run.id); replaceIfSelected(try await api.codingRun(id: run.id)) }
        catch { errorMessage = error.localizedDescription }
    }

    func control(_ action: String) async {
        guard let run = activeRun, !actionInFlight, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let message = draft
        actionInFlight = true
        defer { actionInFlight = false }
        do { try await api.controlCoding(runId: run.id, action: action, message: message); if draft == message { draft = "" } }
        catch { errorMessage = "\(error.localizedDescription) Controls are not retried automatically; check the event history before resending." }
    }

    func resolve(_ approval: CodingApproval, approved: Bool) async {
        guard !actionInFlight else { return }
        guard !approved || approval.change == nil || reviewedChanges.contains(approval.change!.id) else {
            errorMessage = "Review the complete proposed diff before approving this change."
            return
        }
        actionInFlight = true
        let generation = selectionGeneration
        defer { actionInFlight = false }
        do {
            if let command = approval.command {
                try await api.resolveCodingCommand(id: approval.id, approved: approved, commandHash: approved ? command.hash : nil)
            } else {
                try await api.resolveCodingApproval(id: approval.id, approved: approved, changeHash: approved ? approval.change?.afterHash : nil)
            }
        }
        catch { if generation == selectionGeneration { errorMessage = error.localizedDescription } }
        if let current = try? await api.codingApprovals(runId: approval.runId), generation == selectionGeneration {
            mergeApprovals(current, runId: approval.runId)
        }
    }

    func mergeApprovals(_ records: [CodingApproval], runId: String) {
        for var record in records where record.runId == runId {
            let index = approvals.firstIndex { $0.id == record.id }
            if let state = approvalStates[record.id], state != "pending" { record.status = state }
            if let index {
                if approvals[index].status != "pending", record.status == "pending" { record.status = approvals[index].status }
                record.requestSequence = record.requestSequence ?? approvals[index].requestSequence
                approvals[index] = record
            } else { approvals.append(record) }
            if record.status != "pending" { approvalStates[record.id] = record.status }
        }
        approvals.sort { ($0.requestSequence ?? Int.max) < ($1.requestSequence ?? Int.max) }
    }

    @discardableResult
    func applyApprovalEvent(_ event: CodingEvent) -> Bool {
        if event.kind == "approval.requested", let approval = CodingApproval.requested(event) {
            mergeApprovals([approval], runId: event.runId)
            return true
        }
        if event.kind == "approval.resolved" {
            let id = event.text("approval_id")
            let status = event.text("status").isEmpty
                ? (event.payload["approved"] == .bool(true) ? "approved" : "denied") : event.text("status")
            approvalStates[id] = status
            if let index = approvals.firstIndex(where: { $0.id == id && $0.runId == event.runId }) { approvals[index].status = status }
            return true
        }
        return false
    }

    func closeSelected() async {
        guard !aiReview.busy, let id = selectedId, activeRun == nil, !actionInFlight, pending == nil else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await api.closeCodingSession(id: id)
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index].status = "closed" }
        } catch { errorMessage = error.localizedDescription }
    }

    var canManageWorkspace: Bool {
        !aiReview.busy && available && selected != nil && !actionInFlight && !loading && !loadingRuns
        && activeRun == nil && pending == nil && checkout?.isBusy != true
        && ["idle", "interrupted", "closed"].contains(selected?.status ?? "")
    }

    func loadReusableCheckouts() async {
        do { reusableCheckouts = try await api.codingReusableCheckouts() }
        catch { errorMessage = error.localizedDescription }
    }

    func deliveryFiles(sessionId: String) async -> [CodingChangedFile] {
        do { return try await api.codingRepository(sessionId: sessionId).files }
        catch { errorMessage = error.localizedDescription; return [] }
    }

    func changeModel(_ modelId: Int) async {
        guard canManageWorkspace, selected?.isClosed == false, let id = selectedId else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let result = try await api.changeCodingModel(sessionId: id, modelId: modelId)
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index] = result }
            await select(id)
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleArchivedSessions() async {
        guard !actionInFlight, pending == nil else { return }
        showingArchived.toggle()
        clearSelectedConversation()
        sessions = []
        await refresh()
    }

    private func clearSelectedConversation() {
        aiReview.reset(sessionId: nil)
        observer?.cancel(); checkoutObserver?.cancel()
        selectionGeneration = UUID()
        selectedId = nil; runs = []; approvals = []; projections = [:]
        deliveryAction = nil
        checkout = nil; checkoutLoaded = false
        dismissRepository()
        draft = ""
    }

    func removeConversation(id: String, delete: Bool, archived: Bool = true) async {
        guard !actionInFlight, pending == nil, id != selectedId || !aiReview.busy else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            if delete { try await api.deleteCodingSession(sessionId: id) }
            else { _ = try await api.archiveCodingSession(sessionId: id, archived: archived) }
            let removedSelection = selectedId == id
            if removedSelection { clearSelectedConversation() }
            sessions.removeAll { $0.id == id }
            if removedSelection, let first = sessions.first { await select(first.id) }
        } catch { errorMessage = error.localizedDescription }
    }

    func previewDelivery(sessionId: String, action: String, files: [String], message: String) async -> CodingDeliveryPreview? {
        guard canManageWorkspace, selectedId == sessionId else { return nil }
        actionInFlight = true; errorMessage = nil
        defer { actionInFlight = false }
        do {
            let result = try await api.previewCodingDelivery(sessionId: sessionId, action: action, files: files, message: message)
            guard selectedId == sessionId, result.checkoutId == checkout?.id else { return nil }
            return result
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func confirmDelivery(sessionId: String, preview: CodingDeliveryPreview, files: [String], message: String) async -> Bool {
        guard canManageWorkspace, selectedId == sessionId, checkout?.id == preview.checkoutId else { return false }
        actionInFlight = true; errorMessage = nil
        let generation = selectionGeneration
        defer { actionInFlight = false }
        do {
            let result = try await api.confirmCodingDelivery(sessionId: sessionId, action: preview.action, files: files, message: message, hash: preview.reviewHash)
            guard result.checkoutId == preview.checkoutId, result.action == preview.action else {
                throw CodingClientError(code: "invalid_delivery", message: "The backend returned an unexpected Git delivery result.")
            }
            deliveryNotices[sessionId] = DeliveryNotice(result: result, preview: preview)
            if selectedId == sessionId, selectionGeneration == generation { await select(sessionId) }
            return true
        } catch {
            let message = error.localizedDescription
            if selectedId == sessionId, selectionGeneration == generation {
                await select(sessionId)
                if selectedId == sessionId {
                    errorMessage = message + " Refresh and review again before retrying; the previous outcome may need inspection."
                }
            }
            return false
        }
    }

    func grant(userId: Int, path: String, createRepository: Bool = false) async -> Bool {
        guard !actionInFlight else { return false }
        actionInFlight = true
        errorMessage = nil
        defer { actionInFlight = false }
        do {
            let granted: CodingWorkspace
            if createRepository { granted = try await api.createCodingRepository(userId: userId, path: path) }
            else { granted = try await api.grantCodingWorkspace(userId: userId, path: path) }
            workspaces.removeAll { $0.id == granted.id }; workspaces.append(granted)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func loadOperations(_ run: CodingRun) async {
        guard !run.isActive, run.sessionId == selectedId else { return }
        let generation = selectionGeneration
        var projection = CodingProjection()
        do {
            try await api.streamCoding(runId: run.id, after: 0, follow: false) { event in
                guard self.selectionGeneration == generation else { throw CancellationError() }
                try projection.apply(event, runId: run.id)
            }
            guard selectionGeneration == generation else { return }
            projections[run.id] = projection
            if let records = try? await api.codingApprovals(runId: run.id), selectionGeneration == generation {
                mergeApprovals(records, runId: run.id)
            }
        } catch is CancellationError { return }
        catch { if selectionGeneration == generation { errorMessage = error.localizedDescription } }
    }

    func suspend() {
        aiReview.suspend()
        observing = false; observer?.cancel(); observer = nil
        checkoutObserver?.cancel(); checkoutObserver = nil
        dismissRepository()
    }
    func resume() async {
        observing = true
        await refresh()
    }

    private func reconcilePending() {
        if let pending, runs.contains(where: { $0.clientRequestId == pending.requestId }) {
            self.pending = nil; draft = ""
        }
    }
    private func replace(_ run: CodingRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run }
        else { runs.append(run) }
        if !run.isActive, var projection = projections[run.id] {
            for index in projection.operations.indices where projection.operations[index].status == "running" {
                projection.operations[index].status = "not finalized"
            }
            projections[run.id] = projection
        }
        if let index = sessions.firstIndex(where: { $0.id == run.sessionId }), !sessions[index].isClosed {
            sessions[index].status = run.isActive ? run.status : (run.status == "interrupted" ? "interrupted" : "idle")
        }
    }
    private func replaceIfSelected(_ run: CodingRun) { if run.sessionId == selectedId { replace(run) } }

    private func observe(_ id: String, generation: UUID) {
        observer?.cancel()
        guard observing else { return }
        observer = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<5 {
                guard !Task.isCancelled, selectionGeneration == generation else { return }
                connection = attempt == 0 ? "Connecting" : "Reconnecting (\(attempt)/4)"
                do {
                    let currentApprovals = try await api.codingApprovals(runId: id)
                    try Task.checkCancellation()
                    guard selectionGeneration == generation else { return }
                    mergeApprovals(currentApprovals, runId: id)
                    try await api.streamCoding(runId: id, after: projections[id]?.cursor ?? 0, follow: true) { [weak self] event in
                        guard let self, self.selectionGeneration == generation, !Task.isCancelled else { throw CancellationError() }
                        var projection = self.projections[id] ?? CodingProjection()
                        try projection.apply(event, runId: id)
                        self.projections[id] = projection
                        let appliedApproval = self.applyApprovalEvent(event)
                        self.connection = "Live - \(self.modeLabel)"
                        if let index = self.runs.firstIndex(where: { $0.id == id }) {
                            switch event.kind {
                            case "run.started": self.runs[index].status = "running"
                            case "approval.requested": self.runs[index].status = "waiting_approval"
                            case "command.started":
                                if ["running", "waiting_approval"].contains(event.text("run_status")) { self.runs[index].status = event.text("run_status") }
                            case "run.stopping": self.runs[index].status = "stopping"
                            case "approval.resolved":
                                if self.runs[index].status == "waiting_approval" {
                                    self.runs[index].status = self.approvals.contains(where: { $0.runId == id && $0.isPending }) ? "waiting_approval" : "running"
                                }
                            default: break
                            }
                        }
                        if (event.kind == "approval.requested" && !appliedApproval) || event.kind == "command.recorded" {
                            let current = try await self.api.codingApprovals(runId: id)
                            if self.selectionGeneration == generation { self.mergeApprovals(current, runId: id) }
                        }
                    }
                    try Task.checkCancellation()
                    let current = try await api.codingRun(id: id)
                    guard selectionGeneration == generation else { return }
                    replace(current)
                    if !current.isActive {
                        connection = current.status.capitalized
                        if let records = try? await api.codingApprovals(runId: id), selectionGeneration == generation { mergeApprovals(records, runId: id) }
                        return
                    }
                    throw CodingClientError(code: "incomplete_stream", message: "The event connection ended while the run is still active.")
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, selectionGeneration == generation else { return }
                    if let current = try? await api.codingRun(id: id), selectionGeneration == generation {
                        replace(current)
                        if !current.isActive {
                            connection = current.status.capitalized
                            if let records = try? await api.codingApprovals(runId: id), selectionGeneration == generation { mergeApprovals(records, runId: id) }
                            return
                        }
                    }
                    let retryable = (error as? CodingClientError)?.retryable ?? (error is URLError)
                    if !retryable || attempt == 4 {
                        errorMessage = error.localizedDescription
                        connection = "Disconnected - run may still be active. Refresh to reconcile."
                        return
                    }
                    do { try await Task.sleep(for: .seconds(min(16, 1 << attempt))) }
                    catch { return }
                }
            }
        }
    }
}

extension CodingWorkspaceStore: InspectorDirectoryServing {
    func explorerSource() async -> InspectorDirectorySource? {
        guard let id = selectedId else { return nil }
        let generation = selectionGeneration
        do {
            let root = try await api.codingExplorerRoot(sessionId: id)
            guard !Task.isCancelled, generation == selectionGeneration, selectedId == id else { return nil }
            guard root.provider == "coding_checkout", root.sessionId == id, root.readOnly,
                  root.rootId == checkout?.id, checkout?.status == "ready" else {
                throw CodingClientError(code: "checkout_invalid", message: "Explorer checkout changed. Refresh the workspace and open Explorer again.")
            }
            return InspectorDirectorySource(context: .coding(id), root: root, provider: self)
        } catch {
            if !Task.isCancelled, generation == selectionGeneration {
                errorMessage = (error as? CodingClientError)?.code == "http_404"
                    ? "Explorer requires the updated backend. Restart the intended backend checkout, then refresh Code."
                    : error.localizedDescription
            }
            return nil
        }
    }

    private func requireExplorerRoot(_ root: InspectorRoot) throws {
        guard root.provider == "coding_checkout", root.sessionId == selectedId,
              root.rootId == checkout?.id, checkout?.status == "ready", workspace?.isActive == true else {
            throw CodingClientError(code: "checkout_invalid", message: "This file tab belongs to another or unavailable checkout. Open Explorer again.")
        }
    }

    func inspectorDirectory(root: InspectorRoot, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage {
        try requireExplorerRoot(root)
        let generation = selectionGeneration
        let value = try await api.codingExplorerDirectory(sessionId: root.sessionId, rootId: root.rootId, path: path, offset: offset, version: version)
        guard !Task.isCancelled, generation == selectionGeneration else { throw CancellationError() }
        try requireExplorerRoot(root)
        return value
    }

    func inspectorFile(root: InspectorRoot, path: String) async throws -> InspectorFileContent {
        try requireExplorerRoot(root)
        let generation = selectionGeneration
        let value = try await api.codingExplorerFile(sessionId: root.sessionId, rootId: root.rootId, path: path)
        guard !Task.isCancelled, generation == selectionGeneration else { throw CancellationError() }
        try requireExplorerRoot(root)
        return value
    }
}
