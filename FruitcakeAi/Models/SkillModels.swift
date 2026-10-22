import Foundation

struct InstalledSkill: Decodable, Identifiable {
    let id: Int
    let slug: String
    let name: String
    let description: String
    let scope: String
    let isActive: Bool
    let isPinned: Bool
    let bundleFileCount: Int?
    let installedByUsername: String?
}

struct SkillBundleRequest: Encodable, Equatable {
    var files: [String: String]
    var scope: String = "shared"
    var isPinned: Bool = false
}

struct SkillBundlePreview: Decodable {
    let name: String
    let slug: String
    let description: String
    let requiredTools: [String]
    let missingTools: [String]
    let estimatedTokens: Int
    let warnings: [String]
    let previewHash: String
    let filePaths: [String]
    let canInstall: Bool
}

struct SkillBundleInstall: Encodable {
    let files: [String: String]
    let scope: String
    let isPinned: Bool
    let previewHash: String

    init(request: SkillBundleRequest, hash: String) {
        files = request.files
        scope = request.scope
        isPinned = request.isPinned
        previewHash = hash
    }
}

struct SkillInstallResult: Decodable { let id: Int; let name: String; let slug: String }
struct SkillDocuments: Decodable, Identifiable { let id: Int; let files: [String: String] }
struct SkillEnabledRequest: Encodable { let isActive: Bool }

struct SkillFolderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum SkillFolderReader {
    static func read(_ folder: URL) throws -> [String: String] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let root = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else {
            throw SkillFolderError(message: "Choose the actual folder containing SKILL.md, not a shortcut.")
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw SkillFolderError(message: "This folder could not be opened.") }
        var files: [String: String] = [:]
        var total = 0
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw SkillFolderError(message: "Skill bundles cannot contain symbolic links.")
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, ["md", "txt"].contains(url.pathExtension.lowercased()) else {
                throw SkillFolderError(message: "Only Markdown and text documents are supported. Scripts and binary files are not imported.")
            }
            guard files.count < 32, let size = values.fileSize, size <= 64_000, total + size <= 512_000 else {
                throw SkillFolderError(message: "Choose a bundle with at most 32 files, 64 KB per file and 512 KB total.")
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 64_000, total + data.count <= 512_000,
                  let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                throw SkillFolderError(message: "Skill documents must be bounded UTF-8 text files.")
            }
            let prefix = folder.standardizedFileURL.path + "/"
            guard url.standardizedFileURL.path.hasPrefix(prefix) else {
                throw SkillFolderError(message: "A document is outside the selected folder.")
            }
            files[String(url.standardizedFileURL.path.dropFirst(prefix.count))] = text
            total += data.count
        }
        if let enumerationError { throw enumerationError }
        guard let main = files["SKILL.md"], main.count <= 12_000 else {
            throw SkillFolderError(message: "Choose the folder containing SKILL.md (at most 12,000 characters).")
        }
        return files
    }
}
