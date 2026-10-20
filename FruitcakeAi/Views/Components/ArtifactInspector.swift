import SwiftUI
import PDFKit

struct ArtifactReference: Identifiable, Hashable {
    enum Origin: Hashable {
        case chat(sessionID: Int?)
        case task(taskID: Int, runID: Int?)
    }

    let id: String
    let path: String
    let filename: String
    let mediaType: String
    let title: String
    let origin: Origin
    var workspaceRootID: String? = nil
    var workspaceOwnerID: Int? = nil
}

struct ArtifactInspectorView: View {
    @Environment(AuthManager.self) private var authManager
    let artifact: ArtifactReference
    let isActive: Bool
    @Environment(ArtifactInspectorState.self) private var inspector

    @State private var data: Data?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var authorized = false
    @State private var refreshRevision = 0
    private struct LoadKey: Hashable { let active: Bool; let revision: Int }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(originLabel(artifact.origin)).font(Theme.mono(9)).foregroundStyle(Theme.textDim)
                    Text(artifact.path).font(Theme.mono(10)).lineLimit(2).textSelection(.enabled)
                }
                Spacer(minLength: 4)
                Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(isLoading)
                    .accessibilityLabel("Refresh artifact")
            }.padding(12)
            Divider()
            ZStack {
                content.opacity(authorized ? 1 : 0).allowsHitTesting(authorized).accessibilityHidden(!authorized)
                if isLoading { ProgressView("Loading artifact…") }
                else if let errorMessage {
                    ContentUnavailableView("Artifact Unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .task(id: LoadKey(active: isActive, revision: refreshRevision)) { if isActive, !Task.isCancelled { await loadSelectedArtifact() } }
    }

    @ViewBuilder
    private var content: some View {
        if let data {
            artifactContent(artifact, data: data)
        } else {
            ContentUnavailableView("No Artifact Selected", systemImage: "doc")
        }
    }

    @ViewBuilder
    private func artifactContent(_ artifact: ArtifactReference, data: Data) -> some View {
        if artifact.mediaType == "application/pdf" {
            PDFArtifactView(data: data)
        } else if artifact.mediaType.hasPrefix("image/"), let image = platformImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                image
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        } else if let text = String(data: data, encoding: .utf8) {
            ScrollView([.horizontal, .vertical]) {
                Text(renderedText(text, mediaType: artifact.mediaType, filename: artifact.filename))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
        } else {
            ContentUnavailableView(
                "Preview Not Supported",
                systemImage: "doc.badge.ellipsis",
                description: Text(artifact.filename)
            )
        }
    }

    private func renderedText(_ text: String, mediaType: String, filename: String) -> AttributedString {
        if mediaType == "text/markdown" || filename.lowercased().hasSuffix(".md"),
           let markdown = try? AttributedString(markdown: text) {
            return markdown
        }
        return AttributedString(text)
    }

    @MainActor
    private func loadSelectedArtifact() async {
        authorized = false
        errorMessage = nil
        let selected = artifact
        let account = inspector.account
        guard let baseURL = authManager.serverURL, let token = try? authManager.token() else {
            data = nil; errorMessage = "Not connected to the server."
            return
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(selected.workspaceRootID == nil ? "workspace/files" : "workspace/explorer/download"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "path", value: selected.path)]
        if let rootID = selected.workspaceRootID {
            guard selected.workspaceOwnerID == account?.userID else { data = nil; return }
            components?.queryItems?.append(URLQueryItem(name: "root_id", value: rootID))
        }
        guard let url = components?.url else {
            data = nil; errorMessage = "The artifact path is invalid."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        isLoading = true
        defer { isLoading = false; if !authorized, !Task.isCancelled { data = nil } }
        do {
            let (loaded, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, inspector.account == account, isActive else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "The server could not load this artifact."
                return
            }
            guard loaded.count <= 20_000_000 else {
                errorMessage = "This artifact is too large for the inline preview."
                return
            }
            if data != loaded { data = loaded }
            authorized = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, inspector.account == account else { return }
            errorMessage = "The artifact could not be loaded."
        }
    }

    private func originLabel(_ origin: ArtifactReference.Origin) -> String {
        switch origin {
        case .chat:
            return "CHAT ARTIFACT"
        case .task(let taskID, let runID):
            return runID.map { "TASK #\(taskID) · RUN #\($0)" } ?? "TASK #\(taskID)"
        }
    }

    private func platformImage(data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

#if os(macOS)
private struct PDFArtifactView: NSViewRepresentable {
    let data: Data
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            view.document = PDFDocument(data: data)
        }
    }
}
#else
private struct PDFArtifactView: UIViewRepresentable {
    let data: Data
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            view.document = PDFDocument(data: data)
        }
    }
}
#endif
