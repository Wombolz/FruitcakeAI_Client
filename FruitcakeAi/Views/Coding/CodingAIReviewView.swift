#if os(macOS)
import SwiftUI

enum CodingReviewPage: String {
    case setup, history
}

struct CodingReviewSetup: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: CodingWorkspaceStore
    let openInspector: () -> Void
    @State private var scope = "checkout_changes"
    @State private var paths: Set<String> = []
    @State private var modelId = 0
    @State private var effort = "default"
    @State private var page: CodingReviewPage
    private var review: CodingAIReviewStore { workspace.aiReview }
    private var profile: CodingReviewOptions.Profile? { review.options?.reviewerProfiles?.first { $0.id == modelId } }

    init(workspace: CodingWorkspaceStore, initialPage: CodingReviewPage = .setup, openInspector: @escaping () -> Void) {
        self.workspace = workspace
        self.openInspector = openInspector
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Independent AI Review").font(.title2)
            HStack(spacing: 6) {
                ConsoleChip(text: "READ ONLY", accentDot: Theme.codeAccent)
                ConsoleChip(text: "FRESH CONTEXT")
            }
            Text("A fresh read-only reviewer sees a frozen capture, not your builder conversation. No edits, commands, tests or external tools. Start is explicit.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            Picker("Review page", selection: $page) {
                Text("New Review").tag(CodingReviewPage.setup)
                Text("History").tag(CodingReviewPage.history)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if page == .history { history }
                    else { setup }
                    if let error = review.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.onDevice).textSelection(.enabled)
                    }
                    if review.pending != nil {
                        Text("Start response is uncertain. Retry reconciles the same request; it does not start another review.")
                            .font(.caption).foregroundStyle(Theme.onDevice)
                        Button("Retry Same Review Request") { Task { await startPending() } }.disabled(review.acting)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if page == .setup {
                    Button("Start Review") {
                        Task {
                            if await review.start(scope: scope, paths: paths, modelId: modelId, effort: effort) {
                                openInspector(); dismiss()
                            }
                        }
                    }.buttonStyle(CodingActionStyle(emphasis: .primary)).disabled(!canStart)
                }
            }
        }.padding(24).frame(width: 580, height: 650)
            .background(Theme.bg).foregroundStyle(Theme.text).tint(Theme.codeAccent)
            .task(id: "\(page.rawValue):\(scope)") {
                guard page == .setup else { return }
                paths = []; await review.loadOptions(scope: scope)
            }
            .task { await review.loadHistory() }
            .onChange(of: modelId) { _, _ in effort = "default" }
    }

    private var canStart: Bool {
        workspace.canManageWorkspace && workspace.selected?.isClosed == false
        && workspace.checkout?.status == "ready" && !review.busy && !review.loading && !review.loadingOptions
        && review.options?.busy == false && review.options?.scope == scope
        && !paths.isEmpty && paths.count <= 128 && profile?.reasoningEfforts.contains(effort) == true
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Scope", selection: $scope) {
                Text("Checkout changes since baseline").tag("checkout_changes")
                Text("Uncommitted changes only").tag("uncommitted")
            }.disabled(review.pending != nil || review.acting)
            if workspace.checkout?.status != "ready" || workspace.selected?.isClosed != false {
                Text("A ready, open managed checkout is required. Source repositories are never used as a fallback.")
                    .foregroundStyle(Theme.onDevice).font(.caption)
            }
            if review.loadingOptions { ProgressView("Inspecting review options (no model call)") }
            if let options = review.options {
                Text("Base \((options.base ?? "unknown").prefix(12)) · HEAD \((options.head ?? "unknown").prefix(12))")
                    .font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                if options.busy == true || review.activeReview != nil {
                    Text("Checkout is busy. Finish or stop its work, then refresh options; reviews are not queued.")
                        .font(.caption).foregroundStyle(Theme.onDevice)
                }
                Picker("Reviewer model (builder unchanged)", selection: $modelId) {
                    Text("Choose a reviewer").tag(0)
                    ForEach(options.reviewerProfiles ?? []) { Text($0.label).tag($0.id) }
                }
                Picker("Requested reasoning", selection: $effort) {
                    ForEach(profile?.reasoningEfforts ?? ["default"], id: \.self) { Text($0.capitalized).tag($0) }
                }.disabled(profile == nil)
                Text("Choices come from the authorized profile and tested adapter. Runtime acknowledgement is not provider confirmation.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                HStack {
                    Text("\(paths.count) selected · at most 128 files").font(Theme.mono(10))
                    Spacer()
                    Button("Select Eligible") { paths = Set((options.paths ?? []).filter(\.eligible).prefix(128).map(\.path)) }
                    Button("Clear") { paths = [] }
                }
                ForEach(options.paths ?? []) { item in
                    Toggle(isOn: Binding(get: { paths.contains(item.path) }, set: { if $0 { paths.insert(item.path) } else { paths.remove(item.path) } })) {
                        Text(item.path).font(Theme.mono(11)).textSelection(.enabled)
                    }.toggleStyle(.checkbox).disabled(!item.eligible || review.pending != nil)
                }
                if options.paths?.isEmpty != false { Text("No changed paths in this scope.").foregroundStyle(Theme.textDim) }
                if options.pathsLimited == true { Text("Path inventory is limited. Narrow the scope before starting.").foregroundStyle(Theme.onDevice) }
                Text("Path eligibility is preliminary; unsupported files may fail capture. Captures are retained for \(options.contentRetentionDays ?? 30) days, subject to quotas. Opening this sheet creates no capture.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            Button("Refresh Options") { Task { paths = []; await review.loadOptions(scope: scope) } }
                .disabled(review.loadingOptions || review.pending != nil)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            if review.loading { ProgressView("Loading reviews") }
            if review.history.isEmpty, !review.loading { Text("No reviews for this conversation.").foregroundStyle(Theme.textDim) }
            ForEach(review.history) { item in
                Button {
                    Task { await review.select(item.id); if review.selected?.id == item.id { openInspector(); dismiss() } }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.model.modelId).font(.system(size: 12, weight: .medium))
                        HStack {
                            CodingStatusBadge(status: item.status, compact: true)
                            MessageTimestamp(date: item.createdAt).foregroundStyle(Theme.textDim)
                        }
                        if let findings = item.findings { Text("\(findings.count) findings reported").font(Theme.mono(10)).foregroundStyle(Theme.textDim) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .modifier(CodingCard(accent: review.selected?.id == item.id ? Theme.codeAccent : nil))
                }.buttonStyle(.plain).disabled(review.acting || review.pending != nil)
            }
            if review.hasMore { Button("Earlier Reviews") { Task { await review.loadHistory(more: true) } } }
        }
    }

    private func startPending() async {
        if await review.retryStart() { openInspector(); dismiss() }
    }
}

struct CodingAIReviewInspector: View {
    let workspace: CodingWorkspaceStore
    let close: () -> Void
    var reviewOverride: CodingAIReviewStore? = nil
    var expectedReviewID: String? = nil
    var refreshAction: (() -> Void)? = nil
    @State private var dismissing: CodingReviewFinding?
    @State private var reason = ""
    private var review: CodingAIReviewStore { reviewOverride ?? workspace.aiReview }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Review").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    if let refreshAction { refreshAction() }
                    else { Task { if let expectedReviewID { await review.resume(reviewID: expectedReviewID) } else { await review.loadHistory() } } }
                } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(review.loading).help("Refresh review and applicability")
                Button(action: close) { Image(systemName: "xmark") }.help("Close review inspector")
            }.buttonStyle(.plain).padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = review.error {
                        HStack(alignment: .top) {
                            Text(error).font(.caption).foregroundStyle(Theme.onDevice).textSelection(.enabled)
                            Button { review.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }
                    }
                    if let item = review.selected {
                        summary(item)
                        approvals(item)
                        Picker("Review contents", selection: Binding(get: { review.tab }, set: { review.tab = $0 })) {
                            Text("Files").tag("files")
                            Text("Findings").tag("findings")
                        }.pickerStyle(.segmented)
                        if review.tab == "files" { files(item) } else { findings(item) }
                    } else {
                        Text("No review selected. Use Review in the workspace header to reopen saved results, or its menu for Review History and New Review.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Theme.bg).foregroundStyle(Theme.text).tint(Theme.codeAccent)
            .sheet(item: $dismissing) { finding in
                VStack(alignment: .leading, spacing: 14) {
                    Text("Dismiss Finding").font(.title2)
                    Text(finding.title).font(.headline)
                    Text("This records a disposition on this historical review. It does not mark the code fixed or carry to a new review.").font(.caption)
                    TextField("Reason (required, up to 2,000 characters)", text: $reason, axis: .vertical).lineLimit(3...7)
                    if let error = review.error { Text(error).font(.caption).foregroundStyle(Theme.onDevice) }
                    HStack {
                        Button("Cancel") { dismissing = nil }.disabled(review.acting)
                        Spacer()
                        Button("Dismiss Finding") {
                            Task {
                                review.error = nil
                                await review.disposition(finding, dismiss: true, reason: reason)
                                if review.error == nil { dismissing = nil }
                            }
                        }.disabled(review.acting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 2000)
                    }
                }.padding(24).frame(width: 460).background(Theme.bg)
                    .interactiveDismissDisabled(review.acting)
            }
    }

    private func summary(_ item: CodingAIReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CodingStatusBadge(status: item.status)
                if item.isActive { ProgressView().controlSize(.small) }
                Spacer()
                if item.isActive { Button("Stop Review") { Task { await review.stop() } }.disabled(review.acting) }
            }
            Text(item.model.modelId).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
            if !item.qualification.isEmpty {
                Label(item.qualification, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.onDevice)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.onDevice.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = item.errorCode { Text(error).font(Theme.mono(10)).foregroundStyle(Theme.onDevice) }
            if let findings = item.findings {
                Text("\(findings.count) findings · \(findings.filter { $0.disposition == "open" }.count) open · \(findings.filter { $0.disposition == "dismissed" }.count) dismissed")
                    .font(.system(size: 12, weight: .medium))
            }
            if !item.summary.isEmpty {
                DisclosureGroup("Review summary") { MessageProse(text: item.summary).font(.system(size: 12)).padding(.top, 6) }
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Text("Capture \(item.captureId.prefix(12)) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(Theme.mono(10)).foregroundStyle(Theme.textDim)
            if let capture = item.capture {
                Text("Base \((capture.base ?? "unknown").prefix(12)) · HEAD \((capture.head ?? "unknown").prefix(12))")
                    .font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                if let observed = capture.applicabilityObservedAt {
                    Text("Applicability checked \(observed.formatted(date: .omitted, time: .standard))").font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                }
            }
            DisclosureGroup("Reasoning And Coverage") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Requested: \(item.reasoning.requested) · Resolved: \(item.reasoning.resolved)")
                    Text("Sent: \(item.reasoning.sent ?? "not sent") · RPC acknowledged: \(item.reasoning.rpcAcknowledged ? "yes" : "no")")
                    Text("Runtime readback: \(item.reasoning.runtimeReadback ?? "unknown") · Version: \(item.reasoning.runtimeVersion ?? "unknown")")
                    Text("Provider confirmation: \(item.reasoning.providerConfirmation == nil || item.reasoning.providerConfirmation == .null ? "unconfirmed" : "reported (not independently verified)")")
                    if let source = item.reasoning.evidenceSource { Text("Evidence: \(source)") }
                    if let observed = item.reasoning.observedAt { Text("Observed: \(observed.formatted())") }
                    Text("Files in scope: \(count(item.coverage.filesInScope)) · In prompt: \(count(item.coverage.filesProvidedInPrompt))")
                    Text("Successful captured reads: \(count(item.coverage.successfulCapturedReads)) · Unavailable: \(count(item.coverage.readUnavailable)) · Denied: \(count(item.coverage.readDenied))")
                    Text("Tests: not executed by reviewer. Semantic coverage: unknown. Counts are not proof of a complete review.")
                    ForEach(Array(item.limitations.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(Theme.onDevice) }
                    if let omissions = item.capture?.omissionCounts {
                        ForEach(omissions.keys.sorted(), id: \.self) { key in Text("Excluded \(key): \(omissions[key] ?? 0)") }
                    }
                }.font(.system(size: 11)).foregroundStyle(Theme.textDim).textSelection(.enabled)
            }.font(.system(size: 12))
        }.padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
    }

    private func count(_ value: Int?) -> String { value.map(String.init) ?? "not recorded" }

    private func approvals(_ item: CodingAIReview) -> some View {
        ForEach(review.approvals.filter { $0.status == "pending" }) { approval in
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow Captured Read?").font(.system(size: 12, weight: .semibold))
                Text("\(approval.path) · \(approval.side)").font(Theme.mono(11)).textSelection(.enabled)
                Text("Only retained bytes. Waiting for you; no approval timeout.").font(.caption).foregroundStyle(Theme.textDim)
                HStack {
                    Button("Deny") { Task { await review.resolve(approval, approved: false) } }
                    Button("Allow Read") { Task { await review.resolve(approval, approved: true) } }
                }.disabled(review.acting || !item.isActive)
            }.padding(10).background(Theme.onDevice.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func files(_ item: CodingAIReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Captured files, not current repository changes.").font(.caption).foregroundStyle(Theme.textDim)
            ForEach(item.capture?.files ?? []) { file in
                VStack(alignment: .leading, spacing: 8) {
                    Label(file.path, systemImage: "doc.text").font(Theme.mono(11)).textSelection(.enabled)
                    Button("Show Reviewed Diff", systemImage: "arrow.left.arrow.right") { showDiff(file.path) }
                        .buttonStyle(CodingActionStyle()).disabled(item.capture?.canOpenDiff != true)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).modifier(CodingCard())
            }
            if item.capture?.canOpenDiff != true {
                Text("Captured content is unavailable or expired. Findings remain historical; live files are not substituted.")
                    .font(.caption).foregroundStyle(Theme.onDevice)
            }
        }
    }

    private func findings(_ item: CodingAIReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.findings?.isEmpty != false {
                Text(item.isActive ? "No findings reported yet." : "No findings reported.").font(.system(size: 12, weight: .medium))
                Text("This is not a clean-code certificate.").font(.caption).foregroundStyle(Theme.textDim)
            }
            ForEach(item.findings ?? []) { finding in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(finding.severityLabel, systemImage: finding.severity == "blocker" ? "exclamationmark.octagon" : "flag")
                            .font(Theme.mono(10)).foregroundStyle(severityColor(finding.severity))
                        Spacer(minLength: 4)
                        Text(finding.disposition.capitalized).font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                    }
                    Text(finding.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(finding.anchor).font(Theme.mono(10)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                    MessageProse(text: finding.body).font(.system(size: 12)).foregroundStyle(Theme.textMid).lineSpacing(3)
                    DisclosureGroup("Captured evidence") {
                        Text(finding.evidence).font(Theme.mono(11)).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.composer, in: RoundedRectangle(cornerRadius: 6))
                    }.font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    if finding.reason != nil || finding.updatedAt != nil {
                        DisclosureGroup("Disposition history") {
                            VStack(alignment: .leading, spacing: 6) {
                                if let reason = finding.reason { MessageProse(text: reason).font(.system(size: 12)).lineSpacing(3) }
                                if let date = finding.updatedAt {
                                    Text("Updated \(date.formatted()) · user \(finding.updatedByUserId.map(String.init) ?? "unknown")")
                                        .font(Theme.mono(10))
                                }
                                Text("Recorded disposition, not independent verification that the code is fixed.").font(.system(size: 11))
                            }.foregroundStyle(Theme.textDim).padding(.top, 6)
                        }.font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    Button("Show Reviewed Diff") { showDiff(finding.path, finding: finding) }.disabled(item.capture?.canOpenDiff != true)
                        .buttonStyle(CodingActionStyle())
                    Button("Draft Correction") { Task { await workspace.draftCorrection(finding, review: review) } }
                        .buttonStyle(CodingActionStyle())
                        .disabled(review.acting || workspace.selected?.isClosed != false || workspace.pending != nil)
                        .help("Appends a bounded draft to the builder composer. Does not send, edit or resolve anything.")
                    if finding.disposition == "dismissed" {
                        Button("Reopen Finding") { Task { await review.disposition(finding, dismiss: false, reason: nil) } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.codeAccent).disabled(review.acting)
                    } else {
                        Button("Dismiss With Reason…") { reason = ""; dismissing = finding }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textDim).disabled(review.acting)
                    }
                }.textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(CodingCard(accent: finding.disposition == "open" ? severityColor(finding.severity) : nil))
            }
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "blocker": Theme.danger
        case "should_fix": Theme.onDevice
        default: Theme.textDim
        }
    }

    private func showDiff(_ path: String, finding: CodingReviewFinding? = nil) {
        Task { if let diff = await review.diff(path: path, finding: finding) { workspace.showCapturedDiff(diff, review: review) } }
    }
}
#endif
