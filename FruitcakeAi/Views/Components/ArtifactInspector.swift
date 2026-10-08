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
}

@Observable
final class ArtifactInspectorState {
    var selected: ArtifactReference?
    var isVisible = false

    func open(_ artifact: ArtifactReference) {
        selected = artifact
        isVisible = true
    }

    func close() {
        isVisible = false
    }
}

struct ArtifactInspectorView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ArtifactInspectorState.self) private var inspector

    @State private var data: Data?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .task(id: inspector.selected?.id) {
            await loadSelectedArtifact()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(PersonaAccent.color(for: "family_assistant"))
            VStack(alignment: .leading, spacing: 2) {
                Text(inspector.selected?.title ?? "Artifact")
                    .font(.headline)
                    .lineLimit(1)
                if let selected = inspector.selected {
                    Text(originLabel(selected.origin))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer()
            Button {
                inspector.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close artifact inspector")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading artifact…")
        } else if let errorMessage {
            ContentUnavailableView(
                "Artifact Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if let selected = inspector.selected, let data {
            artifactContent(selected, data: data)
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
        data = nil
        errorMessage = nil
        guard let selected = inspector.selected else { return }
        guard let baseURL = authManager.serverURL, let token = try? authManager.token() else {
            errorMessage = "Not connected to the server."
            return
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("workspace/files"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "path", value: selected.path)]
        guard let url = components?.url else {
            errorMessage = "The artifact path is invalid."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        isLoading = true
        defer { isLoading = false }
        do {
            let (loaded, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "The server could not load this artifact."
                return
            }
            guard loaded.count <= 20_000_000 else {
                errorMessage = "This artifact is too large for the inline preview."
                return
            }
            data = loaded
        } catch is CancellationError {
            return
        } catch {
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

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#else
private struct PDFArtifactView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#endif
