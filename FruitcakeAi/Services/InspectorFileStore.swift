import Foundation
import Observation

struct InspectorExplorerRow: Identifiable {
    enum Kind { case entry(InspectorDirectoryEntry), loading, more, error(String) }
    let id: String
    let directory: String
    let depth: Int
    let kind: Kind
}

@Observable @MainActor final class InspectorExplorerStore {
    struct Directory {
        let version: String
        var entries: [InspectorDirectoryEntry]
        var nextOffset: Int?
    }
    let source: InspectorDirectorySource
    private(set) var directories: [String: Directory] = [:]
    private(set) var expanded: Set<String> = []
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var validating = false
    private var validatingRows: [InspectorExplorerRow]?
    private var active = false
    private var generation = UUID()

    init(source: InspectorDirectorySource) { self.source = source }

    func suspend() { active = false; generation = UUID(); loading = []; validating = false; validatingRows = nil }

    func activate() async {
        guard !Task.isCancelled else { return }
        active = true; generation = UUID()
        let token = generation
        validatingRows = rows
        directories = [:]; errors = [:]; loading = []; validating = true
        await load("")
        await restoreExpanded()
        if token == generation { validatingRows = nil; validating = false }
    }

    func toggle(_ path: String) async {
        guard active else { return }
        if expanded.contains(path) {
            expanded = expanded.filter { $0 != path && !$0.hasPrefix(path + "/") }
            for key in directories.keys.filter({ $0 == path || $0.hasPrefix(path + "/") }) { directories[key] = nil }
        } else {
            expanded.insert(path)
            await load(path)
        }
    }

    func loadMore(_ path: String) async { await load(path, more: true); await restoreExpanded() }
    func retry(_ path: String) async { await load(path); await restoreExpanded() }

    private func restoreExpanded() async {
        for path in expanded.sorted(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            guard active, !Task.isCancelled else { return }
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            if directories[path] == nil, directories[parent]?.entries.contains(where: { $0.path == path && $0.kind == .directory }) == true {
                await load(path)
            }
        }
    }

    private func load(_ path: String, more: Bool = false) async {
        guard active, !Task.isCancelled, !loading.contains(path), path.isEmpty || expanded.contains(path) else { return }
        guard directories[path] != nil || directories.count < 64 else {
            errors[path] = "Collapse a folder before loading more (64 expanded directories)."; return
        }
        let previous = more ? directories[path] : nil
        if more && previous?.nextOffset == nil { return }
        let token = generation
        loading.insert(path); errors[path] = nil
        defer { if token == generation { loading.remove(path) } }
        do {
            let page = try await source.directory(path: path, offset: previous?.nextOffset ?? 0, version: previous?.version)
            guard active, token == generation, !Task.isCancelled, path.isEmpty || expanded.contains(path) else { return }
            let entries = (previous?.entries ?? []) + page.entries
            let otherCount = directories.filter { $0.key != path }.values.reduce(0) { $0 + $1.entries.count }
            guard otherCount + entries.count <= 4000, Set(entries.map(\.path)).count == entries.count else {
                errors[path] = "Collapse a folder before loading more (4,000 cached entries)."; return
            }
            directories[path] = Directory(version: page.version, entries: entries, nextOffset: page.nextOffset)
        } catch is CancellationError {} catch {
            guard active, token == generation else { return }
            let failure = error as? CodingClientError
            if [401, 403, 404].contains(failure?.status ?? 0) || failure?.code == "checkout_invalid" {
                directories = [:]; errors = ["": error.localizedDescription]
            } else { errors[path] = error.localizedDescription }
        }
    }

    var rows: [InspectorExplorerRow] {
        if let validatingRows { return validatingRows }
        var result: [InspectorExplorerRow] = []
        func append(_ path: String, depth: Int) {
            guard depth <= 32 else { return }
            for entry in directories[path]?.entries ?? [] {
                result.append(.init(id: entry.path, directory: path, depth: depth, kind: .entry(entry)))
                if entry.kind == .directory, expanded.contains(entry.path) { append(entry.path, depth: depth + 1) }
            }
            if loading.contains(path) { result.append(.init(id: path + "/:loading", directory: path, depth: depth, kind: .loading)) }
            if let error = errors[path] { result.append(.init(id: path + "/:error", directory: path, depth: depth, kind: .error(error))) }
            else if directories[path]?.nextOffset != nil { result.append(.init(id: path + "/:more", directory: path, depth: depth, kind: .more)) }
        }
        append("", depth: 0)
        return result
    }
}

@Observable @MainActor final class InspectorFileStore {
    let source: InspectorDirectorySource
    let path: String
    private(set) var content: InspectorFileContent?
    private(set) var error: String?
    private(set) var loading = false
    private(set) var changedSinceLastLoad = false
    private var generation = UUID()
    private var active = false

    init(source: InspectorDirectorySource, path: String) { self.source = source; self.path = path }
    func suspend() { active = false; generation = UUID(); loading = false }

    func activate() async {
        guard !Task.isCancelled else { return }
        active = true; generation = UUID()
        let token = generation
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let value = try await source.file(path: path)
            guard active, token == generation, !Task.isCancelled else { return }
            changedSinceLastLoad = content?.version != nil && content?.version != value.version
            content = value
        } catch is CancellationError {} catch {
            guard active, token == generation else { return }
            content = nil; self.error = error.localizedDescription
        }
    }
}
