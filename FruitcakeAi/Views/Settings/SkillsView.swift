import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SkillsView: View {
    @Environment(AuthManager.self) private var auth
    @State private var skills: [InstalledSkill] = []
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showImport = false
    @State private var documents: SkillDocuments?
    @State private var removing: InstalledSkill?

    var body: some View {
        SettingsPage(title: "Skills", subtitle: "Install reusable instructions and reference documents. Skills guide the assistant; they do not grant permissions.") {
            SettingsCard(title: "Installed Skills", systemImage: "books.vertical") {
                HStack {
                    Text("Import a folder containing SKILL.md and its supporting text files.")
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Button("Import Skill", systemImage: "plus") { showImport = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let errorMessage { Text(errorMessage).foregroundStyle(Theme.danger).textSelection(.enabled) }
                if !loading && skills.isEmpty {
                    ContentUnavailableView("No Skills Installed", systemImage: "books.vertical", description: Text("Import a skill bundle to add reusable guidance for your tools and workflows."))
                }
                ForEach(skills) { skill in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.name).font(.headline)
                                Text("\(skill.scope.capitalized) · \(skill.bundleFileCount ?? 0) bundled files · \(skill.isActive ? "Enabled" : "Disabled")")
                                    .font(.caption).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { skill.isActive }, set: { enabled in Task { await setEnabled(skill, enabled) } }))
                                .labelsHidden().disabled(busy)
                        }
                        Text(skill.description).font(.subheadline).foregroundStyle(Theme.textDim)
                        HStack {
                            Button("View Documents", systemImage: "doc.text") { Task { await inspect(skill) } }
                            Spacer()
                            Button("Remove", role: .destructive) { removing = skill }
                        }.disabled(busy)
                    }
                    .padding(14)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(busy)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showImport) { SkillImportView { await load() }.environment(auth) }
        .sheet(item: $documents) { SkillDocumentsView(files: $0.files) }
        .confirmationDialog("Remove this skill and its stored documents?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing {
                Button("Remove \(removing.name)", role: .destructive) { Task { await remove(removing) } }
            }
        } message: { Text("The source folder is not changed. You can import it again later.") }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { skills = try await APIClient(authManager: auth).request("/admin/skills"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func setEnabled(_ skill: InstalledSkill, _ enabled: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let _: InstalledSkill = try await APIClient(authManager: auth).request("/admin/skills/\(skill.id)", method: "PATCH", body: SkillEnabledRequest(isActive: enabled))
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
    private func inspect(_ skill: InstalledSkill) async {
        busy = true
        defer { busy = false }
        do { documents = try await APIClient(authManager: auth).request("/admin/skill-bundles/\(skill.id)") }
        catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ skill: InstalledSkill) async {
        removing = nil
        busy = true
        defer { busy = false }
        do { try await APIClient(authManager: auth).requestVoid("/admin/skills/\(skill.id)", method: "DELETE"); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SkillImportView: View {
    let onInstalled: () async -> Void
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var request = SkillBundleRequest(files: [:])
    @State private var preview: SkillBundlePreview?
    @State private var previewedRequest: SkillBundleRequest?
    @State private var selectedPath = "SKILL.md"
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var picking = false
    @State private var folderName = "No folder selected"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Skill").font(.title2.bold())
                    Text("A frozen copy is stored on the server. Your source files are never changed.").font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button("Cancel") { dismiss() }.disabled(busy)
            }
            HStack {
                Button("Choose Folder…", systemImage: "folder") { chooseFolder() }.disabled(busy)
                Text(folderName).foregroundStyle(Theme.textDim).lineLimit(1)
                Spacer()
                Picker("Available to", selection: $request.scope) {
                    Text("Everyone").tag("shared")
                    Text("Only Me").tag("personal")
                }.frame(maxWidth: 240).disabled(busy)
            }
            Toggle("Keep available when semantic matching is offline", isOn: $request.isPinned).disabled(busy)
                .font(.caption)
            if !request.files.isEmpty {
                SkillFileBrowser(files: request.files, selectedPath: $selectedPath)
            }
            if let preview, previewedRequest == request {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preview.name).font(.headline)
                    Text("\(preview.filePaths.count) documents · approximately \(preview.estimatedTokens) instruction tokens").font(.caption).foregroundStyle(Theme.textDim)
                    Text("Required tools: \(preview.requiredTools.isEmpty ? "None" : preview.requiredTools.joined(separator: ", "))").font(.caption).textSelection(.enabled)
                    if !preview.missingTools.isEmpty { Text("Unavailable tools: \(preview.missingTools.joined(separator: ", "))").foregroundStyle(Theme.danger) }
                    ForEach(preview.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(Theme.danger).font(.caption).textSelection(.enabled) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Validate Preview") { Task { await validate() } }.disabled(busy || request.files.isEmpty)
                Button("Install Skill") { Task { await install() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || preview?.canInstall != true || previewedRequest != request)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 800, minHeight: 620, idealHeight: 760)
        #endif
        .background(Theme.bg)
        .interactiveDismissDisabled(busy)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            do { try accept(result.get()) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the skill folder containing SKILL.md."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try accept(url) } catch { errorMessage = error.localizedDescription }
        #else
        picking = true
        #endif
    }
    private func accept(_ url: URL) throws {
        let files = try SkillFolderReader.read(url)
        request.files = files
        folderName = url.lastPathComponent
        preview = nil
        previewedRequest = nil
        selectedPath = "SKILL.md"
        errorMessage = nil
    }
    private func validate() async {
        let snapshot = request
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let result: SkillBundlePreview = try await APIClient(authManager: auth).request("/admin/skill-bundles/preview", method: "POST", body: snapshot, timeout: 60)
            guard request == snapshot else { return }
            preview = result
            previewedRequest = snapshot
        } catch { errorMessage = error.localizedDescription }
    }
    private func install() async {
        guard let preview, preview.canInstall, previewedRequest == request else { return }
        busy = true
        defer { busy = false }
        do {
            let _: SkillInstallResult = try await APIClient(authManager: auth).request("/admin/skill-bundles/install", method: "POST", body: SkillBundleInstall(request: request, hash: preview.previewHash), timeout: 60)
            await onInstalled()
            dismiss()
        } catch { errorMessage = error.localizedDescription + " Refresh installed skills before retrying an uncertain installation." }
    }
}

private struct SkillFileBrowser: View {
    let files: [String: String]
    @Binding var selectedPath: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Document", selection: $selectedPath) {
                ForEach(files.keys.sorted(), id: \.self) { Text($0).tag($0) }
            }
            ScrollView([.vertical, .horizontal]) {
                Text(files[selectedPath] ?? "Choose a document")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 8))
        }.frame(minHeight: 220)
    }
}

private struct SkillDocumentsView: View {
    let files: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath = "SKILL.md"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Installed Documents").font(.title2.bold()); Spacer(); Button("Close") { dismiss() } }
            SkillFileBrowser(files: files, selectedPath: $selectedPath)
        }.padding(24)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 600)
        #endif
        .background(Theme.bg)
    }
}
