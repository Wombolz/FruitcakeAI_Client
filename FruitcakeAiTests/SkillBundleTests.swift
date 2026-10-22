import Foundation
import Testing
@testable import FruitcakeAi

@Suite @MainActor struct SkillBundleTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func importsMainAndReferencesWithoutChangingSource() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let refs = root.appendingPathComponent("references", isDirectory: true)
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try "instructions".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "model defaults".write(to: refs.appendingPathComponent("model-settings.md"), atomically: true, encoding: .utf8)
        let files = try SkillFolderReader.read(root)
        #expect(files == ["SKILL.md": "instructions", "references/model-settings.md": "model defaults"])
        #expect(try String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8) == "instructions")
    }

    @Test func rejectsSymlinksScriptsAndMissingMain() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SkillFolderError.self) { try SkillFolderReader.read(root) }
        try "instructions".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("outside.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("SKILL.md"))
        #expect(throws: SkillFolderError.self) { try SkillFolderReader.read(root) }
        try FileManager.default.removeItem(at: link)
        try "print('no execution')".write(to: root.appendingPathComponent("run.py"), atomically: true, encoding: .utf8)
        #expect(throws: SkillFolderError.self) { try SkillFolderReader.read(root) }
    }

    @Test func boundedMainAndReferences() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try String(repeating: "x", count: 12_001).write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(throws: SkillFolderError.self) { try SkillFolderReader.read(root) }
        try "instructions".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 64_001).write(to: root.appendingPathComponent("large.md"), atomically: true, encoding: .utf8)
        #expect(throws: SkillFolderError.self) { try SkillFolderReader.read(root) }
    }

    @Test func wireFormatKeepsRelativePathsAndPreviewIdentity() throws {
        let request = SkillBundleRequest(files: ["SKILL.md": "body", "references/model_settings.md": "settings"], scope: "personal", isPinned: true)
        let body = SkillBundleInstall(request: request, hash: "reviewed-hash")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let value = try #require(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
        #expect(value["preview_hash"] as? String == "reviewed-hash")
        #expect(value["is_pinned"] as? Bool == true)
        #expect((value["files"] as? [String: String])?["references/model_settings.md"] == "settings")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(SkillDocuments.self, from: Data(#"{"id":1,"files":{"SKILL.md":"body","references/model_settings.md":"settings"}}"#.utf8))
        #expect(detail.files["references/model_settings.md"] == "settings")
    }
}
