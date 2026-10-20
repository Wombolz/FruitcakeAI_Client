import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceDownloadDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct WorkspaceFileActions: View {
    let source: InspectorDirectorySource
    let path: String
    let sizeBytes: Int
    @Environment(AuthManager.self) private var auth
    @Environment(ArtifactInspectorState.self) private var inspector
    @State private var downloading = false
    @State private var document: WorkspaceDownloadDocument?
    @State private var exporting = false
    @State private var error: String?

    var body: some View {
        if source.isUserWorkspace {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Button("Attach to Chat", systemImage: "paperclip") {
                        inspector.stageWorkspaceAttachment(source: source, path: path, sizeBytes: sizeBytes)
                    }.disabled(!canAttach)
                        .help(WorkspaceDraftAttachment.supportsToolReference(path)
                              ? "Add a file reference to the draft. Nothing is sent until you send the message."
                              : "Files ending in whitespace can be downloaded, but cannot be attached with the current workspace tools.")
                    Button(downloading ? "Downloading" : "Download", systemImage: "arrow.down.to.line") { Task { await download() } }
                        .disabled(downloading || sizeBytes > 20_000_000)
                }.buttonStyle(.plain).font(.system(size: 11))
                if let error { Text(error).font(.caption).foregroundStyle(Theme.onDevice) }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .data,
                          defaultFilename: (path as NSString).lastPathComponent) { result in
                document = nil
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .onChange(of: inspector.account) { _, _ in document = nil; exporting = false }
            .onChange(of: inspector.context) { _, _ in document = nil; exporting = false }
        }
    }

    private var canAttach: Bool {
        guard WorkspaceDraftAttachment.supportsToolReference(path) else { return false }
        if case .chat(let id) = inspector.context { return id != nil && source.context == inspector.context }
        return false
    }
    @MainActor private func download() async {
        guard !downloading, let account = inspector.account, source.context == inspector.context,
              let root = source.root, root.userId == account.userID else { return }
        downloading = true; error = nil
        defer { downloading = false }
        do {
            let data = try await APIClient(authManager: auth).workspaceDownload(rootID: root.rootId, path: path)
            guard !Task.isCancelled, inspector.account == account, inspector.context == source.context else { return }
            document = .init(data: data); exporting = true
        } catch {
            guard !Task.isCancelled, inspector.account == account, inspector.context == source.context else { return }
            self.error = error.localizedDescription
        }
    }
}
