import SwiftUI

struct CodeAppearanceView: View {
    @AppStorage(CodeTheme.preferenceKey) private var themeID = CodeTheme.Preset.fruitcake.rawValue
    private var selection: Binding<CodeTheme.Preset> {
        Binding(get: { CodeTheme.resolve(themeID).preset }, set: { themeID = $0.rawValue })
    }
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Code colors are independent of Fruitcake's application appearance.") {
            SettingsCard(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right") {
                Picker("Code theme", selection: selection) {
                    ForEach(CodeTheme.Preset.allCases) { preset in Text(preset.title).tag(preset) }
                }
                Text("Applies immediately to inspected files, Chat and Code blocks, and diff windows. Navigation, message styling and status colors stay unchanged.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                CodeSnippet(text: "import Foundation\n\n// Complete text; colors only.\nstruct Room {\n    let name: String\n    func label() -> String {\n        return \"Room: \\(name)\"\n    }\n}\nlet count = 42\n", language: "swift")
                CodeSnippet(text: "# A second language, same palette.\ndef available(rooms):\n    return [room for room in rooms if room.online]\n\nprint(available(rooms))\n", language: "python")
                Text("Local lexical highlighting: Swift, Python, JavaScript, TypeScript, JSON and shell. Unsupported languages remain plain text. Theme importing is planned separately.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
        }
    }
}
