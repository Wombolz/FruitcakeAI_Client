import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Kept for callers that decode the legacy public bundled-persona catalog.
struct PersonaInfo: Codable {
    let displayName: String?
    let description: String?
    let tone: String?
    let blockedTools: [String]?
    let contentFilter: String?
}

struct PersonaPicker: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var store: PersonaEditorStore
    let embedded: Bool
    var onOpenTest: ((Int) -> Void)?
    @State private var pendingAction: PendingAction?
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var showImporter = false
    @State private var importingSheet = false
    @State private var showPreview = false
    @State private var historicalRevision: PersonaRevisionRecord?

    private enum PendingAction { case new, select(String), reload, duplicate }

    @MainActor init(embedded: Bool = false, store: PersonaEditorStore? = nil, onOpenTest: ((Int) -> Void)? = nil) {
        self.embedded = embedded
        self.onOpenTest = onOpenTest
        _store = State(initialValue: store ?? PersonaEditorStore())
    }

    private var api: APIClient { APIClient(authManager: authManager) }

    var body: some View {
        Group {
            if embedded { page }
            else {
                NavigationStack {
                    page.toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 500, idealWidth: 1000, minHeight: 550, idealHeight: 800)
                #endif
                .interactiveDismissDisabled(store.hasUnsavedChanges)
            }
        }
        .task { if !store.isLoaded && !store.hasUnsavedChanges { await store.load(api) } }
        .onChange(of: store.draft) { _, _ in store.preview = nil }
        .confirmationDialog("Discard unsaved persona changes?", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                if let action = pendingAction { pendingAction = nil; perform(action) }
            }
            Button("Keep Editing", role: .cancel) { pendingAction = nil }
        }
        .confirmationDialog("Archive this persona?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive Persona", role: .destructive) { Task { await store.archive(api) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Existing chats and saved revisions are retained. Choose another default first if needed.") }
        .confirmationDialog("Delete this persona permanently?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Persona", role: .destructive) { Task { await store.deletePersona(api) } }
            Button("Cancel", role: .cancel) { store.cancelDeletion() }
        } message: {
            if let impact = store.deletionPreview {
                Text("Delete \"\(store.selectedItem?.personality.displayName ?? "this persona")\" and all its revisions? \(impact.affectedConversations) conversations will use Personal Assistant going forward."
                    + (impact.resetsDefault ? " Your default for new chats will also change to Personal Assistant." : "")
                    + " Existing messages stay unchanged. Saved persona instructions and unshared reference images will be removed. Messages and backups may still contain persona details.")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.png, .jpeg, UTType(filenameExtension: "webp") ?? .image]) { result in
            switch result {
            case .success(let url):
                Task { await importImage(url, sheet: importingSheet) }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let preview = store.preview {
                            Text("Static prompt preview").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Not included: " + preview.exclusions.joined(separator: ", ") + ".")
                                .font(.caption).foregroundStyle(Theme.textDim)
                            ForEach(preview.layers) { layer in
                                SettingsCard(title: layer.title, systemImage: "text.alignleft") {
                                    Text(layer.content.isEmpty ? "No content in this layer." : layer.content)
                                        .font(Theme.mono(11)).textSelection(.enabled)
                                }
                            }
                        }
                    }.padding(24).frame(maxWidth: 900, alignment: .leading)
                }.background(Theme.bg)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreview = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 800, minHeight: 450, idealHeight: 700)
            #endif
        }
        .sheet(item: $historicalRevision) { revision in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Revision \(revision.version)").font(.title2.weight(.semibold))
                        Text(revision.personality.displayName).font(.headline)
                        Text(revision.personality.description)
                        Text(revision.personality.identity ?? "").textSelection(.enabled)
                        Text(revision.personality.tone ?? "").textSelection(.enabled)
                        ForEach(Array(revision.personality.behaviorInstructions.enumerated()), id: \.offset) { _, instruction in
                            Text(instruction).textSelection(.enabled)
                        }
                        visualReferences(revision.personality, editable: false)
                    }.padding(24).foregroundStyle(Theme.textMid)
                }.background(Theme.bg)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { historicalRevision = nil } } }
            }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 650, minHeight: 450, idealHeight: 650)
            #endif
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Personas").font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    if store.isBusy { ProgressView().controlSize(.small) }
                    Button { request(.reload) } label: { Image(systemName: "arrow.clockwise") }.help("Reload personas")
                    Button { request(.new) } label: { Label("New", systemImage: "plus") }
                        .accessibilityLabel("New Persona").buttonStyle(.borderedProminent).tint(Theme.codeAccent)
                }
                Text("Shape the personality. Keep permissions separate.").font(.callout).foregroundStyle(Theme.textDim)
            }.padding(24).disabled(store.isBusy)
            Divider().overlay(Theme.stroke)
            GeometryReader { geometry in
                if geometry.size.width >= 850 {
                    HStack(spacing: 0) {
                        catalog.frame(width: 230)
                        Divider().overlay(Theme.stroke)
                        editor
                    }
                } else {
                    VStack(spacing: 0) {
                        Menu {
                            Button("New Persona") { request(.new) }
                            ForEach(store.items) { item in
                                Button(item.personality.displayName + (item.archived ? " (Archived)" : "")) { request(.select(item.id)) }
                            }
                        } label: {
                            HStack {
                                Label(store.selectedItem?.personality.displayName ?? "New persona", systemImage: "person.crop.square")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                            }.padding(16)
                        }.disabled(store.isBusy)
                        editor
                    }
                }
            }
        }
        .background(Theme.bg)
        #if os(iOS)
        .navigationTitle("Personas")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var catalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                catalogSection("BUILT-IN", items: store.items.filter(\.isBundled))
                catalogSection("YOUR PERSONAS", items: store.items.filter { !$0.isBundled })
                if store.items.filter({ !$0.isBundled }).isEmpty {
                    Text("Start with Neutral, or duplicate a preset.").font(.caption).foregroundStyle(Theme.textDim).padding(8)
                }
                if let value = store.personalDefault {
                    Text("New chats use \(value.selection.personality.displayName)" + (value.selection.revision.map { " · v\($0)" } ?? "") + ".")
                        .font(.caption).foregroundStyle(Theme.textDim).padding(.top, 18)
                }
            }.padding(14)
        }.background(Theme.sidebar).disabled(store.isBusy)
    }

    private func catalogSection(_ title: String, items: [PersonaEditorItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.mono(10)).foregroundStyle(Theme.textFaint).padding(.top, 12)
            ForEach(items) { item in
                Button { request(.select(item.id)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.personality.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        HStack(spacing: 6) {
                            Text(item.isBundled ? "Read-only" : "Revision \(item.revision ?? 1)")
                            if item.archived { Text("Archived") }
                            if item.reference == store.personalDefault?.selection.reference { Image(systemName: "checkmark.circle.fill") }
                        }.font(.caption2).foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(store.selectedKey == item.id ? Theme.codeAccent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.selectedKey == item.id ? Theme.codeAccent.opacity(0.5) : .clear))
                }.buttonStyle(.plain)
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = store.error { notice(error, error: true) }
                if let status = store.status { notice(status, error: false) }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.selectedItem?.personality.displayName ?? "Create a persona").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(store.isBundled ? "Protected preset · duplicate to experiment" : store.isArchived ? "Archived · history retained" : "Saved revisions never silently change existing chats")
                            .font(.caption).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    if store.selectedItem != nil {
                        Button("Duplicate") { request(.duplicate) }.disabled(store.isArchived || store.isBusy)
                    }
                    Button("Save Revision") { Task { await store.save(api) } }
                        .buttonStyle(.borderedProminent).tint(Theme.codeAccent).disabled(!store.canSave)
                }
                if let validation = store.draft.validationMessage { Text(validation).font(.caption).foregroundStyle(Theme.danger) }
                personalityFields.disabled(store.isBundled || store.isArchived || store.isBusy)
                visualReferences(store.draft, editable: !store.isBundled && !store.isArchived).disabled(store.isBusy)
                SettingsCard(title: "Prompt & Access", systemImage: "shield.lefthalf.filled") {
                    Text("Personality cannot grant tools or remove account restrictions. Preview uses current account policy, without history or recalled memory.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                    Button("Preview Prompt & Effective Tools") {
                        Task { await store.showPreview(api); showPreview = store.preview != nil }
                    }.disabled(store.isBusy || store.isArchived || store.draft.validationMessage != nil)
                    if let preview = store.preview {
                        Text("\(preview.tools.count) available tools · \(preview.blockedTools.count) blocked" + (preview.contentFilter == "strict" ? " · Restricted content policy" : ""))
                            .font(Theme.mono(10)).foregroundStyle(Theme.codeAccent)
                        DisclosureGroup("Effective tools") { Text(preview.tools.joined(separator: ", ")).font(Theme.mono(11)).textSelection(.enabled) }
                        if !preview.blockedTools.isEmpty {
                            DisclosureGroup("Blocked tools") { Text(preview.blockedTools.joined(separator: ", ")).font(Theme.mono(11)).textSelection(.enabled) }
                        }
                    }
                }
                testCard
                if let item = store.selectedItem {
                    SettingsCard(title: "Lifecycle", systemImage: "clock.arrow.circlepath") {
                        ViewThatFits(in: .horizontal) {
                            HStack { lifecycleButtons(item) }
                            VStack(alignment: .leading, spacing: 10) { lifecycleButtons(item) }
                        }
                        if store.hasUnsavedChanges { Text("Save or discard the draft before selecting a default or starting a test.").font(.caption) }
                        ForEach(store.history) { revision in
                            Button("View revision \(revision.version) · \(revision.personality.displayName)") { historicalRevision = revision }
                                .font(.caption)
                        }
                        if store.hasMoreHistory, let oldest = store.history.last?.version {
                            Button("Load Older Revisions") { Task { await store.loadHistory(api, before: oldest) } }.disabled(store.isBusy)
                        }
                        Text("Archiving retains saved revisions and existing chats. Replacing an image does not change older revisions.")
                            .font(.caption).foregroundStyle(Theme.textDim)
                        if !item.isBundled {
                            Text("Deleting switches affected chats to Personal Assistant and removes saved persona instructions. Existing messages remain unchanged.")
                                .font(.caption).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func lifecycleButtons(_ item: PersonaEditorItem) -> some View {
        Button(store.isDefault ? "Current Default" : "Use for New Chats") { Task { await store.setDefault(api) } }
            .disabled(store.isBusy || store.hasUnsavedChanges || store.isDefault || item.archived)
        if !item.isBundled {
            Button("Revision History") { Task { await store.loadHistory(api) } }.disabled(store.isBusy)
            Button("Archive", role: .destructive) { confirmArchive = true }
                .disabled(store.isBusy || item.archived || store.hasUnsavedChanges)
            Button("Delete…", role: .destructive) {
                Task { await store.prepareDeletion(api); confirmDelete = store.deletionPreview != nil }
            }.disabled(store.isBusy || store.hasUnsavedChanges)
        }
    }

    private var personalityFields: some View {
        VStack(spacing: 18) {
            SettingsCard(title: "Identity & Voice", systemImage: "person.text.rectangle") {
                TextField("Display name", text: $store.draft.displayName).textFieldStyle(.roundedBorder)
                TextField("Description", text: $store.draft.description, axis: .vertical).textFieldStyle(.roundedBorder)
                Picker("Base style", selection: $store.draft.personalityMode) {
                    Text("Neutral / blank slate").tag("neutral")
                    Text("Personal Assistant defaults").tag("default")
                }
                textField("Assistant identity", value: $store.draft.identity, limit: 2000)
                textField("Tone", value: $store.draft.tone, limit: 300)
                Text("Inherited fields are resolved once when saving. Explicitly empty fields remain empty.").font(.caption).foregroundStyle(Theme.textDim)
            }
            SettingsCard(title: "Behavioral Instructions", systemImage: "text.alignleft") {
                ForEach(store.draft.behaviorInstructions.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        TextField("Instruction \(index + 1)", text: Binding(
                            get: { store.draft.behaviorInstructions.indices.contains(index) ? store.draft.behaviorInstructions[index] : "" },
                            set: { if store.draft.behaviorInstructions.indices.contains(index) { store.draft.behaviorInstructions[index] = $0 } }
                        ), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button { if store.draft.behaviorInstructions.indices.contains(index) { store.draft.behaviorInstructions.remove(at: index) } } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove instruction \(index + 1)")
                    }
                }
                Button { store.draft.behaviorInstructions.append("") } label: { Label("Add Instruction", systemImage: "plus") }
                    .disabled(store.draft.behaviorInstructions.count >= 24)
                Text("Up to 24 instructions, 1000 characters each. Application rules and approvals remain in effect.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func textField(_ title: String, value: Binding<String?>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Inherit \(title.lowercased()) on save", isOn: Binding(get: { value.wrappedValue == nil }, set: { value.wrappedValue = $0 ? nil : "" }))
                .font(.caption)
            if value.wrappedValue != nil {
                TextField("\(title) · optional, \(limit) characters", text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func visualReferences(_ personality: PersonaPersonality, editable: Bool) -> some View {
        SettingsCard(title: "Visual Identity", systemImage: "photo.on.rectangle.angled") {
            Text("Attach a portrait, a visual character sheet or a turnaround image. No character.md is required.")
                .font(.caption).foregroundStyle(Theme.textDim)
            visualSlot("Portrait", id: personality.visualIdentity?.portraitAssetId, sheet: false, editable: editable)
            visualSlot("Character Sheet / Turnaround", id: personality.visualIdentity?.sheetAssetId, sheet: true, editable: editable)
            Text("Private, versioned references · PNG, JPEG or still WebP · up to 8 MiB and 4 megapixels. Removing a reference affects the draft, not saved history.")
                .font(.caption).foregroundStyle(Theme.textDim)
            Label("Image-generation handoff is not enabled until the MCP reference-image adapter is verified. References are not sent with ordinary chats.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(Theme.textDim)
        }
    }

    private func visualSlot(_ title: String, id: String?, sheet: Bool, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if editable {
                    Button(id == nil ? "Choose Image…" : "Replace…") { importingSheet = sheet; showImporter = true }
                    if id != nil {
                        Button("Remove", role: .destructive) {
                            var visual = store.draft.visualIdentity ?? .init()
                            if sheet { visual.sheetAssetId = nil } else { visual.portraitAssetId = nil }
                            store.draft.visualIdentity = visual
                        }
                    }
                }
            }
            if let id { PersonaReferencePreview(assetId: id).environment(authManager) }
            else { Text("No reference attached").font(.caption).foregroundStyle(Theme.textFaint) }
        }.padding(12).background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
    }

    private var testCard: some View {
        SettingsCard(title: "Try a Fresh Conversation", systemImage: "bubble.left.and.bubble.right") {
            Picker("Model", selection: $store.model) {
                if store.models.isEmpty { Text("No model available").tag("") }
                ForEach(store.models) { model in Text(model.label).tag(model.id) }
            }.disabled(store.isBusy)
            Toggle("Include automatic memory recall", isOn: $store.recallMemories).disabled(store.isBusy)
            Text("Off starts without recalled-memory injection. It does not disable memory-writing tools, explicit memory searches or other side effects. Normal access checks and approvals still apply.")
                .font(.caption).foregroundStyle(Theme.textDim)
            Button("Open Fresh Test Chat") {
                Task { if let id = await store.createTest(api) { onOpenTest?(id) } }
            }.disabled(!store.canTest)
            if store.hasUnsavedChanges || store.savedReference == nil {
                Text("Save this draft first to test a specific, reproducible revision.").font(.caption).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func notice(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: error ? "exclamationmark.triangle" : "checkmark.circle")
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            Button { if error { store.error = nil } else { store.status = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }.foregroundStyle(error ? Theme.danger : Theme.ok).padding(12)
            .background((error ? Theme.danger : Theme.ok).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func request(_ action: PendingAction) {
        if store.hasUnsavedChanges { pendingAction = action } else { perform(action) }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .new: store.startNew()
        case .select(let key): if let item = store.items.first(where: { $0.id == key }) { store.choose(item) }
        case .reload: Task { await store.load(api) }
        case .duplicate: Task { await store.duplicate(api) }
        }
    }

    private func importImage(_ url: URL, sheet: Bool) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 8 * 1024 * 1024 else {
                store.error = "Choose an image file of at most 8 MiB."
                return
            }
            let data = try Data(contentsOf: url)
            await store.upload(api, data: data, filename: url.lastPathComponent, sheet: sheet)
        } catch { store.error = error.localizedDescription }
    }
}

private struct PersonaReferencePreview: View {
    @Environment(AuthManager.self) private var authManager
    let assetId: String
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        Group {
            #if os(macOS)
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
            else { placeholder }
            #else
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
            else { placeholder }
            #endif
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 220)
        .task(id: assetId) {
            data = nil
            failed = false
            do {
                let loaded = try await APIClient(authManager: authManager).personaImage(assetId)
                if !Task.isCancelled { data = loaded }
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
            Text(failed ? "Reference unavailable" : "Loading reference…").font(.caption)
        }.foregroundStyle(Theme.textDim)
    }
}
