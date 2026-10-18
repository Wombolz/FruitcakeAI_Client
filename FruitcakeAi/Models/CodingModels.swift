import Foundation

struct CodingAvailability: Decodable {
    let enabled: Bool
    let mode: String
    let eventSchemaVersion: Int
    var managedCheckouts: Bool? = nil
    var approvedEdits: Bool? = nil
    var containerCommands: Bool? = nil
}

struct CodingCheckout: Decodable, Identifiable {
    let id: String
    let sessionId: String
    let canonicalPath: String
    let baselineCommit: String?
    var status: String
    let errorCode: String?
    var workspaceId: String? = nil
    var headCommit: String? = nil
    var branchName: String? = nil
    var isBusy: Bool { ["creating", "removing", "committing", "applying"].contains(status) }
}

struct CodingDeliveryPreview: Decodable {
    let action: String
    let checkoutId: String
    let head: String
    let diff: String
    let reviewHash: String
    var branch: String? = nil
    var sourcePath: String? = nil
    var sourceBranch: String? = nil
}

struct CodingDeliveryResult: Decodable { let action: String; let head: String; let checkoutId: String }

struct CodingWorkspace: Decodable, Identifiable {
    let id: String
    let userId: Int
    let canonicalPath: String
    let isActive: Bool
    var name: String { URL(fileURLWithPath: canonicalPath).lastPathComponent }
}

struct CodingModelOption: Decodable, Identifiable {
    let id: Int
    let label: String
    let modelId: String
}

struct CodingProjectOption: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct CodingSession: Decodable, Identifiable {
    let id: String
    let workspaceId: String
    let modelProfileId: Int?
    let projectId: Int?
    let title: String
    var status: String
    let contextGeneration: Int
    var editMode: Bool? = nil
    var commandMode: Bool? = nil
    var archivedAt: Date? = nil
    var isClosed: Bool { status == "closed" }
}

struct CodingRun: Decodable, Identifiable {
    let id: String
    let sessionId: String
    let clientRequestId: String?
    var status: String
    let prompt: String
    var responseText: String
    let contextGeneration: Int
    let lastEventSequence: Int
    let errorCode: String?
    let createdAt: Date
    var modelProfileId: Int? = nil
    var modelId: String? = nil
    var isActive: Bool { ["starting", "running", "waiting_approval", "stopping"].contains(status) }
}

struct CodingApproval: Decodable, Identifiable {
    let id: String
    let runId: String
    var status: String
    let title: String
    let message: String
    let expiresAt: Date?
    var change: CodingChangePreview? = nil
    var command: CodingCommandPreview? = nil
    var requestSequence: Int? = nil
    func isExpired(at date: Date) -> Bool { expiresAt.map { $0 <= date } ?? false }
    var isPending: Bool { status == "pending" && !isExpired(at: Date()) }

    static func requested(_ event: CodingEvent) -> Self? {
        var fields = event.payload
        fields["id"] = fields["approval_id"]
        fields["run_id"] = .string(event.runId)
        fields["status"] = .string("pending")
        fields["request_sequence"] = .int(event.sequence)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw CodingClientError(code: "invalid_approval", message: "Invalid approval deadline.")
        }
        return try? decoder.decode(Self.self, from: JSONEncoder().encode(fields))
    }
}

struct CodingChangePreview: Decodable, Identifiable {
    let id: String
    let path: String
    let diff: String
    let beforeHash: String?
    let afterHash: String
}

struct CodingCommandPreview: Decodable, Identifiable {
    let id: String
    let command: String
    let workingDirectory: String
    let timeoutSeconds: Int
    let image: String
    let network: String
    let filesystem: String
    let hash: String
    let status: String
    let result: CodingCommandResult?
}

struct CodingCommandResult: Decodable {
    let status: String
    let exitCode: Int?
    let stdout: String?
    let stderr: String?
    let outputTruncated: Bool?
    let errorCode: String?
}

struct CodingSavedChange: Decodable, Identifiable {
    let id: String
    let runId: String
    let path: String
    let diff: String
    let status: String
    let errorCode: String?
    let createdAt: Date
    let appliedAt: Date?
}

struct CodingEvent: Decodable {
    let schemaVersion: Int
    let runId: String
    let sequence: Int
    let kind: String
    let payload: [String: JSONValue]
    func text(_ key: String) -> String { payload[key]?.stringValue ?? "" }
}

struct CodingOperation: Identifiable {
    let id: String
    var tool: String
    var arguments = ""
    var output = ""
    var status = "running"
}

struct CodingChangedFile: Decodable, Identifiable {
    let path: String
    let indexStatus: String
    let worktreeStatus: String
    let originalPath: String?
    var id: String { path }
    var statusLabel: String {
        if indexStatus == "?" { return "Untracked" }
        return [indexStatus != " " ? "Staged \(indexStatus)" : nil,
                worktreeStatus != " " ? "Unstaged \(worktreeStatus)" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct CodingRepository: Decodable {
    let basis: String
    let observedAt: Date
    let head: String?
    let files: [CodingChangedFile]
}

struct CodingRepositoryDiff: Decodable {
    struct Section: Decodable {
        let kind: String
        let text: String
        let truncated: Bool
    }
    let basis: String
    let observedAt: Date
    let path: String
    let sections: [Section]
}

struct CodingTimelineEntry: Identifiable {
    enum Kind { case assistant, operation, approval, control }
    let id: Int
    let kind: Kind
    var text: String
}

struct CodingProjection {
    var cursor = 0
    var text = ""
    var operations: [CodingOperation] = []
    var controls: [String] = []
    var reconstructed = false
    var timeline: [CodingTimelineEntry] = []
    private var streamingTextIndex: Int?
    var hasAssistantText: Bool { timeline.contains { $0.kind == .assistant && !$0.text.isEmpty } }

    mutating func apply(_ event: CodingEvent, runId: String) throws {
        guard event.schemaVersion == 1, event.runId == runId, event.sequence > 0 else {
            throw CodingClientError(code: "invalid_event", message: "The coding stream returned an incompatible event.")
        }
        guard event.sequence > cursor else { return }
        guard event.sequence == cursor + 1 else {
            throw CodingClientError(code: "event_gap", message: "Coding events are out of sequence. Reload this session to replay them.")
        }
        switch event.kind {
        case "assistant.text_delta":
            text += event.text("delta")
            if streamingTextIndex == nil {
                timeline.append(.init(id: event.sequence, kind: .assistant, text: ""))
                streamingTextIndex = timeline.count - 1
            }
            timeline[streamingTextIndex!].text += event.text("delta")
        case "assistant.message":
            text = event.text("text")
            if let index = streamingTextIndex { timeline[index].text = text }
            else {
                timeline.append(.init(id: event.sequence, kind: .assistant, text: text))
                streamingTextIndex = timeline.count - 1
            }
            // Empty snapshot/reset + deltas is how oversized messages are
            // persisted. Keep that block open until its fragments arrive.
            if !text.isEmpty { streamingTextIndex = nil }
        case "session.ready": reconstructed = event.payload["context_reconstructed"] == .bool(true)
        case "user.steered", "user.follow_up":
            let value = (event.kind == "user.steered" ? "Steering: " : "Follow-up: ") + event.text("message")
            controls.append(value)
            timeline.append(.init(id: event.sequence, kind: .control, text: value))
        case "approval.requested":
            let id = event.text("approval_id")
            if !id.isEmpty, !timeline.contains(where: { $0.kind == .approval && $0.text == id }) {
                timeline.append(.init(id: event.sequence, kind: .approval, text: id))
            }
        case "operation.started", "operation.output", "operation.completed":
            let id = event.text("operation_id")
            guard !id.isEmpty else { break }
            let index: Int
            if let existing = operations.firstIndex(where: { $0.id == id }) { index = existing }
            else {
                operations.append(CodingOperation(id: id, tool: event.text("tool")))
                index = operations.count - 1
                streamingTextIndex = nil
                timeline.append(.init(id: event.sequence, kind: .operation, text: id))
            }
            if event.kind == "operation.started" {
                operations[index].arguments = event.text("arguments")
            } else {
                let output = event.text("text")
                // Pi update payloads are snapshots unless explicitly marked as deltas.
                if event.text("mode") == "delta" { operations[index].output += output }
                else if !output.isEmpty { operations[index].output = output }
                if event.kind == "operation.completed" {
                    operations[index].status = event.payload["is_error"] == .bool(true) ? "failed" : "completed"
                }
            }
        default: break // Unknown kinds still advance the durable cursor.
        }
        cursor = event.sequence
    }
}

struct CodingClientError: LocalizedError {
    let code: String
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
    var retryable: Bool {
        guard let status else { return code == "stream_unavailable" || code == "incomplete_stream" }
        return status >= 500 || status == 429
    }

    static func response(status: Int, data: Data) -> Self {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let detail = object["error"] ?? object["detail"]
        let fields = detail as? [String: Any]
        return Self(code: fields?["code"] as? String ?? "http_\(status)",
                    message: fields?["message"] as? String ?? detail as? String ?? "Coding request failed (HTTP \(status)).",
                    status: status)
    }
}

struct CodingSSEFrame {
    let id: String?
    let event: String
    let data: Data
}

struct CodingSSEParser {
    private var id: String?
    private var event = "message"
    private var data: [String] = []
    private var size = 0
    private var lineBytes: [UInt8] = []
    private var skipLF = false

    // Approval diffs are complete review evidence, not ordinary tool previews.
    private var byteLimit: Int { event == "approval.requested" ? 4 * 1024 * 1024 + 16 * 1024 : 131_072 }

    mutating func feed(byte: UInt8) throws -> CodingSSEFrame? {
        if skipLF && byte == 10 { skipLF = false; return nil }
        skipLF = false
        if byte == 10 || byte == 13 {
            guard let line = String(bytes: lineBytes, encoding: .utf8) else {
                throw CodingClientError(code: "invalid_stream", message: "Coding events contain invalid UTF-8.")
            }
            lineBytes.removeAll(keepingCapacity: true)
            let frame = try feed(line)
            skipLF = byte == 13
            return frame
        }
        guard lineBytes.count + size < byteLimit else {
            throw CodingClientError(code: "event_limit", message: "A coding event exceeded the client limit.")
        }
        lineBytes.append(byte)
        return nil
    }

    mutating func feed(_ line: String) throws -> CodingSSEFrame? {
        size += line.utf8.count
        guard size <= byteLimit else {
            throw CodingClientError(code: "event_limit", message: "A coding event exceeded the client limit.")
        }
        if line.isEmpty {
            defer { self = CodingSSEParser() }
            guard !data.isEmpty else { return nil }
            return CodingSSEFrame(id: id, event: event, data: Data(data.joined(separator: "\n").utf8))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let value = parts.count == 2 ? String(parts[1]).replacingOccurrences(of: #"^ "#, with: "", options: .regularExpression) : ""
        switch parts[0] {
        case "id": if !value.contains("\0") { id = value }
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }
}

struct CodingDiffDrawerSizing {
    static func height(preferred: Double, available: Double) -> Double {
        guard available.isFinite, available > 0 else { return 0 }
        let maximum = max(0, min(available * 0.65, available - 220))
        return min(maximum, max(min(160, maximum), preferred.isFinite ? preferred : 380))
    }
}

struct CodingSplitDiff {
    struct Row {
        enum Kind { case hunk, context, change }
        let kind: Kind
        let beforeNumber: Int?
        let before: String?
        let afterNumber: Int?
        let after: String?
    }
    let rows: [Row]
    let truncated: Bool

    static func parse(_ patch: String, limit: Int = 1500) -> Self {
        var rows: [Row] = []
        var removed: [(Int, String)] = []
        var added: [(Int, String)] = []
        var before = 0, after = 0
        var inHunk = false
        var truncated = false
        let bound = max(1, limit)
        func append(_ row: Row) {
            if rows.count < bound { rows.append(row) } else { truncated = true }
        }
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                let left = index < removed.count ? removed[index] : nil
                let right = index < added.count ? added[index] : nil
                append(Row(kind: .change, beforeNumber: left?.0, before: left?.1, afterNumber: right?.0, after: right?.1))
            }
            removed.removeAll(keepingCapacity: true); added.removeAll(keepingCapacity: true)
        }
        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@ ") {
                flush()
                let parts = line.split(separator: " ")
                guard parts.count >= 4, parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
                      let oldToken = parts[1].dropFirst().split(separator: ",").first,
                      let newToken = parts[2].dropFirst().split(separator: ",").first,
                      let oldStart = Int(oldToken), let newStart = Int(newToken),
                      oldStart >= 0, newStart >= 0, oldStart < Int.max / 2, newStart < Int.max / 2 else {
                    inHunk = false
                    continue
                }
                before = oldStart; after = newStart; inHunk = true
                append(Row(kind: .hunk, beforeNumber: nil, before: line, afterNumber: nil, after: line))
            } else if inHunk, line.hasPrefix("-") {
                removed.append((before, String(line.dropFirst()))); before += 1
            } else if inHunk, line.hasPrefix("+") {
                added.append((after, String(line.dropFirst()))); after += 1
            } else if inHunk, line.hasPrefix(" ") {
                flush()
                append(Row(kind: .context, beforeNumber: before, before: String(line.dropFirst()), afterNumber: after, after: String(line.dropFirst())))
                before += 1; after += 1
            } else if line.hasPrefix("diff --git ") {
                flush(); inHunk = false
            }
            // Newline markers and patch metadata aren't source lines. The
            // original unified preview remains available without interpretation.
            if truncated || removed.count + added.count > bound * 2 {
                truncated = true
                break
            }
        }
        flush()
        return Self(rows: rows, truncated: truncated)
    }
}
