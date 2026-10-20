import Foundation

struct InspectorRoot: Decodable, Hashable {
    let provider: String
    let rootId: String
    let sessionId: String?
    var userId: Int? = nil
    let label: String
    let readOnly: Bool
    let byteLimit: Int
    let lineLimit: Int
    let entryLimit: Int
}

struct InspectorDirectoryEntry: Decodable, Identifiable, Equatable {
    enum Kind: String, Decodable { case directory, file }
    let name: String
    let path: String
    let kind: Kind
    let sizeBytes: Int?
    var id: String { path }
}

struct InspectorDirectoryPage: Decodable {
    let root: InspectorRoot
    let basis: String
    let observedAt: Date
    let path: String
    let version: String
    let entries: [InspectorDirectoryEntry]
    let nextOffset: Int?
}

struct InspectorFileContent: Decodable {
    enum Status: String, Decodable { case text, binary, oversized }
    let root: InspectorRoot
    let basis: String
    let observedAt: Date
    let path: String
    let status: Status
    let byteCount: Int
    let version: String?
    let text: String?
    let lineCount: Int?
}

@MainActor protocol InspectorDirectoryServing: AnyObject {
    func inspectorDirectory(root: InspectorRoot, path: String, offset: Int, version: String?) async throws -> InspectorDirectoryPage
    func inspectorFile(root: InspectorRoot, path: String) async throws -> InspectorFileContent
}

// This is a reference to a backend-owned grant, never a Mac filesystem path.
@MainActor final class InspectorDirectorySource {
    let context: InspectorContext
    let root: InspectorRoot?
    let unavailableReason: String?
    private let provider: (any InspectorDirectoryServing)?

    init(context: InspectorContext, root: InspectorRoot, provider: any InspectorDirectoryServing) {
        self.context = context; self.root = root; self.provider = provider; unavailableReason = nil
    }

    init(unavailable context: InspectorContext, reason: String) {
        self.context = context; root = nil; provider = nil; unavailableReason = reason
    }

    var isUserWorkspace: Bool { root?.provider == "user_workspace" }
    var basis: String { isUserWorkspace ? "user_workspace" : "current_worktree" }

    static func validPath(_ value: String, directory: Bool = false) -> Bool {
        if value.isEmpty { return directory }
        return value.utf8.count <= 1024 && !value.hasPrefix("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: { $0.value < 32 })
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func validate(_ value: InspectorRoot) throws {
        guard let root, root == value, root.readOnly, (1...262144).contains(root.byteLimit),
              (1...12000).contains(root.lineLimit), (1...100).contains(root.entryLimit) else { throw invalid() }
    }

    func directory(path: String, offset: Int = 0, version: String? = nil) async throws -> InspectorDirectoryPage {
        guard let root, let provider else { throw unavailable() }
        guard Self.validPath(path, directory: true), (0...4096).contains(offset) else { throw invalid() }
        let page = try await provider.inspectorDirectory(root: root, path: path, offset: offset, version: version)
        try Task.checkCancellation()
        try validate(page.root)
        guard page.basis == basis, page.path == path, page.version.count == 64,
              version == nil || page.version == version, page.entries.count <= root.entryLimit,
              Set(page.entries.map(\.path)).count == page.entries.count,
              page.entries.allSatisfy({ Self.validPath($0.path) && !$0.name.isEmpty && !$0.name.contains("/")
                  && $0.path == (path.isEmpty ? $0.name : path + "/" + $0.name) }),
              page.nextOffset == nil || (page.nextOffset == offset + page.entries.count && page.nextOffset! > offset && page.nextOffset! <= 4096) else { throw invalid() }
        return page
    }

    func file(path: String) async throws -> InspectorFileContent {
        guard let root, let provider else { throw unavailable() }
        guard Self.validPath(path) else { throw invalid() }
        let value = try await provider.inspectorFile(root: root, path: path)
        try Task.checkCancellation()
        try validate(value.root)
        guard value.basis == basis, value.path == path, value.byteCount >= 0 else { throw invalid() }
        if value.status == .text {
            guard let text = value.text, let version = value.version, version.count == 64,
                  text.utf8.count == value.byteCount, value.byteCount <= root.byteLimit, !text.contains("\0"),
                  value.lineCount == text.components(separatedBy: "\n").count,
                  value.lineCount! <= root.lineLimit else { throw invalid() }
        } else if value.text != nil || value.lineCount != nil { throw invalid() }
        return value
    }

    private func invalid() -> CodingClientError { .init(code: "invalid_inspection", message: "The backend returned mismatched or unbounded inspection content. Refresh Explorer.") }
    private func unavailable() -> CodingClientError { .init(code: "explorer_unavailable", message: unavailableReason ?? "No authorized directory root is attached.") }
}
