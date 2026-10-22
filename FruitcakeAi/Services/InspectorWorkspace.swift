import Foundation
import Observation

// Resource identity is independent of presentation titles and of backend access.
// These references confer no permissions; providers reauthorize each activation.
enum InspectorContext: Hashable {
    case chat(Int?)
    case coding(String)
    case task(Int, Int?)
}

struct InspectorAccountScope: Hashable {
    let server: String
    let userID: Int
}

struct InspectorResourceID: Hashable {
    enum Provider: Hashable { case artifact, changes, review, changedFile, explorer, sourceFile }
    let provider: Provider
    let context: InspectorContext
    let resource: String
    let version: String?
    var rootID: String? = nil
}

enum InspectorResource {
    case explorer(InspectorDirectorySource)
    case sourceFile(InspectorDirectorySource, path: String)
    case artifact(ArtifactReference)
    case changes(CodingWorkspaceStore, sessionID: String)
    case review(CodingWorkspaceStore, sessionID: String, reviewID: String, captureID: String)
    case changedFile(CodingWorkspaceStore, sessionID: String, path: String)

    var identity: InspectorResourceID {
        switch self {
        case .explorer(let source):
            return .init(provider: .explorer, context: source.context, resource: "explorer", version: nil, rootID: source.root?.rootId)
        case .sourceFile(let source, let path):
            return .init(provider: .sourceFile, context: source.context, resource: path, version: source.basis, rootID: source.root?.rootId)
        case .artifact(let artifact):
            let context: InspectorContext
            switch artifact.origin {
            case .chat(let id): context = .chat(id)
            case .task(let id, let run): context = .task(id, run)
            }
            return .init(provider: .artifact, context: context, resource: artifact.chatImagePreview?.resourceID ?? artifact.path, version: nil, rootID: artifact.workspaceRootID)
        case .changes(_, let id):
            return .init(provider: .changes, context: .coding(id), resource: "changes", version: nil)
        case .review(_, let session, let review, let capture):
            return .init(provider: .review, context: .coding(session), resource: review, version: capture)
        case .changedFile(_, let session, let path):
            return .init(provider: .changedFile, context: .coding(session), resource: path, version: "current_worktree")
        }
    }

    var title: String {
        switch self {
        case .explorer(let source): source.isUserWorkspace ? "My Workspace" : "Explorer"
        case .sourceFile(_, let path): (path as NSString).lastPathComponent
        case .artifact(let value): value.title
        case .changes: "Live Changes"
        case .review(_, _, let id, _): "Review · \(id.prefix(6))"
        case .changedFile(_, _, let path): (path as NSString).lastPathComponent
        }
    }

    var symbol: String {
        switch self {
        case .explorer: "folder"
        case .sourceFile: "doc.text"
        case .artifact(let value): value.mediaType.hasPrefix("image/") ? "photo" : "doc.text"
        case .changes: "arrow.triangle.branch"
        case .review: "checklist"
        case .changedFile: "doc.text.magnifyingglass"
        }
    }

    var workspace: CodingWorkspaceStore? {
        switch self {
        case .artifact, .explorer, .sourceFile: nil
        case .changes(let store, _), .review(let store, _, _, _), .changedFile(let store, _, _): store
        }
    }
}

@Observable @MainActor
final class InspectorTab: Identifiable {
    let id = UUID()
    let resource: InspectorResource
    let ordinal: Int
    let review: CodingAIReviewStore?
    let explorer: InspectorExplorerStore?
    let file: InspectorFileStore?

    init(resource: InspectorResource, ordinal: Int) {
        self.resource = resource
        self.ordinal = ordinal
        if case .explorer(let source) = resource { explorer = InspectorExplorerStore(source: source) } else { explorer = nil }
        if case .sourceFile(let source, let path) = resource { file = InspectorFileStore(source: source, path: path) } else { file = nil }
        if case .review(let workspace, let session, _, _) = resource {
            review = workspace.makeInspectorReview(sessionID: session)
        } else { review = nil }
    }

    func suspend() { review?.suspend(); explorer?.suspend(); file?.suspend() }
}

@Observable @MainActor
private final class InspectorTabGroup {
    var tabs: [InspectorTab] = []
    var selectedID: UUID?
    var visible = false
    var closed: [InspectorResource] = []
}

@Observable @MainActor
final class ArtifactInspectorState {
    private var groups: [InspectorContext: InspectorTabGroup] = [:]
    private var rememberedContexts: [String: InspectorContext] = [:]
    private var destination = "chat"
    private var chatSessionID: Int?
    private var codingSessionID: String?
    private var configured = false
    private var ordinal = 0
    private var closedOrder: [InspectorResourceID] = []
    private(set) var account: InspectorAccountScope?
    private(set) var context: InspectorContext? = .chat(nil)
    var notice: String?
    private(set) var workspaceDraftAttachment: WorkspaceDraftAttachment?

    private var group: InspectorTabGroup? { context.flatMap { groups[$0] } }
    var tabs: [InspectorTab] { group?.tabs ?? [] }
    var allTabs: [InspectorTab] { groups.values.flatMap(\.tabs).sorted { $0.ordinal < $1.ordinal } }
    var selectedTab: InspectorTab? { tabs.first { $0.id == group?.selectedID } }
    var hasSelection: Bool { !tabs.isEmpty }
    var isVisible: Bool { group?.visible == true && (hasSelection || notice != nil) }
    var canReopen: Bool { group?.closed.isEmpty == false }
    var selected: ArtifactReference? {
        guard case .artifact(let value) = selectedTab?.resource else { return nil }
        return value
    }
    var codingReview: CodingWorkspaceStore? { selectedTab?.resource.workspace }

    func configure(account: InspectorAccountScope?) {
        guard !configured || self.account != account else { return }
        configured = true
        allTabs.forEach { $0.suspend() }
        groups.removeAll(); rememberedContexts.removeAll(); closedOrder.removeAll()
        self.account = account
        workspaceDraftAttachment = nil
        notice = nil
        setDestination(destination)
    }

    func setDestination(_ value: String) {
        destination = value
        switch value {
        case "chat": setContext(.chat(chatSessionID))
        case "coding": setContext(codingSessionID.map(InspectorContext.coding))
        default: setContext(rememberedContexts[value])
        }
    }

    func setChatSession(_ id: Int?, active: Bool) {
        chatSessionID = id
        if active && destination == "chat" { setContext(.chat(id)) }
    }

    func setCodingSession(_ id: String?, active: Bool) {
        codingSessionID = id
        if active && destination == "coding" { setContext(id.map(InspectorContext.coding)) }
    }

    private func setContext(_ value: InspectorContext?) {
        if context != value { selectedTab?.suspend(); notice = nil; workspaceDraftAttachment = nil }
        context = value
    }

    func open(_ artifact: ArtifactReference) {
        var value = artifact
        if case .chat(nil) = artifact.origin {
            value = ArtifactReference(id: artifact.id, path: artifact.path, filename: artifact.filename,
                                      mediaType: artifact.mediaType, title: artifact.title, origin: .chat(sessionID: chatSessionID), workspaceRootID: artifact.workspaceRootID, workspaceOwnerID: artifact.workspaceOwnerID, chatImagePreview: artifact.chatImagePreview)
        }
        open(.artifact(value))
    }

    func openCoding(_ store: CodingWorkspaceStore) {
        guard let id = store.selectedId else { return }
        codingSessionID = id
        if store.aiReview.inspectorMode == "review" {
            guard let review = store.aiReview.selected, review.sessionId == id else { return }
            open(.review(store, sessionID: id, reviewID: review.id, captureID: review.captureId))
        } else { open(.changes(store, sessionID: id)) }
    }

    func openExplorer(_ source: InspectorDirectorySource) {
        guard context == source.context else { return }
        open(.explorer(source))
    }

    func openSourceFile(_ source: InspectorDirectorySource, path: String) {
        guard source.root != nil, context == source.context, InspectorDirectorySource.validPath(path) else { return }
        open(.sourceFile(source, path: path))
    }

    func openWorkspacePreview(source: InspectorDirectorySource, path: String) {
        guard source.isUserWorkspace, source.context == context, let root = source.root,
              root.userId == account?.userID, case .chat(let sessionID) = context,
              InspectorDirectorySource.validPath(path) else { return }
        let file = path as NSString
        let mediaType: String
        switch file.pathExtension.lowercased() {
        case "pdf": mediaType = "application/pdf"
        case "png": mediaType = "image/png"
        case "jpg", "jpeg": mediaType = "image/jpeg"
        case "gif": mediaType = "image/gif"
        case "webp": mediaType = "image/webp"
        default: return
        }
        open(ArtifactReference(id: "workspace:\(root.rootId):\(path)", path: path, filename: file.lastPathComponent,
            mediaType: mediaType, title: file.lastPathComponent, origin: .chat(sessionID: sessionID),
            workspaceRootID: root.rootId, workspaceOwnerID: root.userId))
    }

    func stageWorkspaceAttachment(source: InspectorDirectorySource, path: String, sizeBytes: Int) {
        guard let account, source.isUserWorkspace, source.root?.userId == account.userID,
              source.context == context, case .chat(let sessionID) = context, let sessionID,
              InspectorDirectorySource.validPath(path), WorkspaceDraftAttachment.supportsToolReference(path), sizeBytes >= 0 else { return }
        workspaceDraftAttachment = .init(account: account, sessionID: sessionID, path: path, sizeBytes: sizeBytes)
    }

    func takeWorkspaceAttachment(sessionID: Int, account: InspectorAccountScope) -> WorkspaceDraftAttachment? {
        guard let value = workspaceDraftAttachment, value.account == account, self.account == account,
              value.sessionID == sessionID, context == .chat(sessionID) else { return nil }
        workspaceDraftAttachment = nil
        return value
    }

    func openChangedFile(_ store: CodingWorkspaceStore, sessionID: String, path: String) {
        guard store.selectedId == sessionID, store.repository?.files.contains(where: { $0.path == path }) == true else { return }
        open(.changedFile(store, sessionID: sessionID, path: path))
    }

    private func open(_ resource: InspectorResource) {
        guard !configured || account != nil else { return }
        let key = resource.identity.context
        setContext(key)
        rememberedContexts[destination] = key
        let group = groups[key] ?? InspectorTabGroup()
        groups[key] = group
        if let tab = group.tabs.first(where: { $0.resource.identity == resource.identity }) {
            select(tab.id); group.visible = true; return
        }
        guard group.tabs.count < 12, allTabs.count < 32 else {
            notice = "Close a tab before opening another (12 per conversation, 32 total)."
            group.visible = true
            return
        }
        ordinal += 1
        let tab = InspectorTab(resource: resource, ordinal: ordinal)
        group.tabs.append(tab)
        select(tab.id); group.visible = true
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if group?.selectedID != id { selectedTab?.suspend() }
        group?.selectedID = id
        notice = nil
    }

    func show() { if hasSelection || notice != nil { group?.visible = true } else { reopenClosed() } }
    func close() { selectedTab?.suspend(); group?.visible = false }

    func closeCoding(for store: CodingWorkspaceStore) {
        guard codingReview === store else { return }
        close()
    }

    func closeTab(_ id: UUID) {
        guard let group, let index = group.tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = group.tabs.remove(at: index)
        tab.suspend()
        group.closed.removeAll { $0.identity == tab.resource.identity }
        group.closed.append(tab.resource)
        closedOrder.removeAll { $0 == tab.resource.identity }
        closedOrder.append(tab.resource.identity)
        if closedOrder.count > 32 {
            let expired = closedOrder.removeFirst()
            for value in groups.values { value.closed.removeAll { $0.identity == expired } }
        }
        if group.closed.count > 12 { group.closed.removeFirst() }
        if group.selectedID == id {
            group.selectedID = group.tabs.isEmpty ? nil : group.tabs[min(index, group.tabs.count - 1)].id
        }
        if group.tabs.isEmpty { group.visible = false }
        notice = nil
    }

    func closeOthers(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for tab in tabs where tab.id != id { closeTab(tab.id) }
        select(id)
    }

    func reopenClosed() {
        guard let group, let resource = group.closed.last else { return }
        guard group.tabs.count < 12, allTabs.count < 32 else { notice = "Close a tab before reopening another."; return }
        group.closed.removeLast()
        closedOrder.removeAll { $0 == resource.identity }
        open(resource)
    }
}
