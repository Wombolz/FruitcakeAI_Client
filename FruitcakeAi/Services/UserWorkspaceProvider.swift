import Foundation

@MainActor protocol UserWorkspaceServing: InspectorDirectoryServing {
    func workspaceExplorerRoot() async throws -> InspectorRoot
    func workspaceDownload(rootID: String, path: String) async throws -> Data
}

@MainActor final class UserWorkspaceProvider: InspectorDirectoryServing {
    private let api: any UserWorkspaceServing
    private let root: InspectorRoot
    private let account: InspectorAccountScope
    private let currentAccount: () -> InspectorAccountScope?

    private init(api: any UserWorkspaceServing, root: InspectorRoot, account: InspectorAccountScope,
                 currentAccount: @escaping () -> InspectorAccountScope?) {
        self.api = api; self.root = root; self.account = account; self.currentAccount = currentAccount
    }

    static func source(api: any UserWorkspaceServing, account: InspectorAccountScope, context: InspectorContext,
                       currentAccount: @escaping () -> InspectorAccountScope?) async throws -> InspectorDirectorySource {
        guard case .chat = context, currentAccount() == account else { throw denied() }
        let root = try await api.workspaceExplorerRoot()
        guard currentAccount() == account, root.provider == "user_workspace", root.userId == account.userID,
              root.sessionId == nil, root.rootId.count == 64, root.readOnly else { throw denied() }
        let provider = Self(api: api, root: root, account: account, currentAccount: currentAccount)
        return InspectorDirectorySource(context: context, root: root, provider: provider)
    }

    private func check(_ reference: InspectorRoot) throws {
        guard currentAccount() == account, reference == root else { throw Self.denied() }
    }
    func inspectorDirectory(root: InspectorRoot, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage {
        try check(root)
        let page = try await api.inspectorDirectory(root: root, path: path, offset: offset, version: version)
        try Task.checkCancellation(); try check(page.root)
        return page
    }
    func inspectorFile(root: InspectorRoot, path: String) async throws -> InspectorFileContent {
        try check(root)
        let file = try await api.inspectorFile(root: root, path: path)
        try Task.checkCancellation(); try check(file.root)
        return file
    }
    private static func denied() -> CodingClientError {
        .init(code: "workspace_denied", message: "The user or server changed. Open My Workspace again.")
    }
}

struct WorkspaceDraftAttachment: Identifiable, Equatable {
    let id = UUID()
    let account: InspectorAccountScope
    let sessionID: Int
    let path: String
    let sizeBytes: Int

    // Disambiguate a real workspace/ subfolder from the filesystem tool's
    // legacy workspace/<user>/ prefix without exposing an absolute host path.
    var toolPath: String { "workspace/\(account.userID)/\(path)" }
}
