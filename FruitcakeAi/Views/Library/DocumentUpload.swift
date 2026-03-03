//
//  DocumentUpload.swift
//  FruitcakeAi
//
//  File picker + scope selector + multipart upload to POST /library/ingest.
//  Works on both iOS (UIDocumentPicker via .fileImporter) and macOS (NSOpenPanel).
//  User ID comes from the JWT — not sent as a form field.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentUpload: View {

    /// Called after a successful upload so the caller can refresh the list.
    var onComplete: () async -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @State private var scope = "personal"
    @State private var pickedURL: URL?
    @State private var pickedName: String?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showFilePicker = false
    @State private var uploadProgress: Double = 0

    // Allowed types — PDF, plain text, Markdown, Word docs
    private let allowedTypes: [UTType] = [
        .pdf,
        .plainText,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                fileSection
                scopeSection
                if let error = uploadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                if isUploading {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Uploading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: uploadProgress)
                        }
                    }
                }
            }
            .navigationTitle("Upload Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        Task { await upload() }
                    }
                    .disabled(pickedURL == nil || isUploading)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileResult(result)
            }
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        Section("Document") {
            if let name = pickedName {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(name)
                        .lineLimit(1)
                    Spacer()
                    Button("Change") { showFilePicker = true }
                        .font(.caption)
                }
            } else {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose File", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private var scopeSection: some View {
        Section {
            Picker("Scope", selection: $scope) {
                Label("Personal", systemImage: "person.fill").tag("personal")
                Label("Family", systemImage: "person.2.fill").tag("family")
                Label("Shared", systemImage: "globe").tag("shared")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Visibility")
        } footer: {
            switch scope {
            case "family":  Text("Visible to all family members.")
            case "shared":  Text("Visible to everyone, including guests.")
            default:        Text("Only visible to you.")
            }
        }
    }

    // MARK: - Handlers

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                pickedURL = url
                pickedName = url.lastPathComponent
                uploadError = nil
            }
        case .failure(let error):
            uploadError = error.localizedDescription
        }
    }

    private func upload() async {
        guard let fileURL = pickedURL else { return }

        isUploading = true
        uploadError = nil
        uploadProgress = 0.1

        // Gain access to the security-scoped resource (sandboxed apps need this)
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: fileURL)
            uploadProgress = 0.4

            let api = APIClient(authManager: authManager)
            _ = try await api.upload(
                "/library/ingest",
                fileData: data,
                fileName: fileURL.lastPathComponent,
                mimeType: mimeType(for: fileURL),
                fields: ["scope": scope]
            )
            uploadProgress = 1.0

            await onComplete()
            dismiss()
        } catch {
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":          return "application/pdf"
        case "txt":          return "text/plain"
        case "md":           return "text/markdown"
        case "docx":         return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:             return "application/octet-stream"
        }
    }
}

#Preview {
    DocumentUpload { }
        .environment(AuthManager())
}
