import Foundation

struct CodingReviewOptions: Decodable {
    struct PathOption: Decodable, Identifiable {
        let path: String
        let eligible: Bool
        var id: String { path }
    }
    struct Profile: Decodable, Identifiable {
        let id: Int
        let label: String
        let modelId: String
        let reasoningEfforts: [String]
    }
    let capturesEnabled: Bool
    let aiReviews: Bool
    let scope: String?
    let base: String?
    let head: String?
    let paths: [PathOption]?
    let pathCount: Int?
    let pathsLimited: Bool?
    let reviewerProfiles: [Profile]?
    let busy: Bool?
    let contentRetentionDays: Int?
}

struct CodingReviewRequest: Encodable, Equatable {
    let scope: String
    let paths: [String]
    let modelProfileId: Int
    let effort: String
    let clientRequestId: String
}

struct CodingReviewCapture: Decodable {
    struct File: Decodable, Identifiable {
        let path: String
        var id: String { path }
    }
    let id: String
    let sessionId: String
    let scope: String
    let status: String
    let createdAt: Date
    let expiresAt: Date
    let contentStatus: String?
    let applicability: String?
    let applicabilityObservedAt: Date?
    let base: String?
    let head: String?
    let limited: Bool?
    let omissionCounts: [String: Int]?
    let files: [File]?
    var canOpenDiff: Bool { status == "ready" && contentStatus == "available" }
}

struct CodingAIReview: Decodable, Identifiable {
    struct Model: Decodable { let modelId: String; let providerFamily: String }
    struct Reasoning: Decodable {
        let requested: String
        let resolved: String
        let sent: String?
        let rpcAcknowledged: Bool
        let runtimeReadback: String?
        let providerConfirmation: JSONValue?
        let runtimeVersion: String?
        let evidenceSource: String?
        let observedAt: Date?
    }
    struct Coverage: Decodable {
        let filesInScope: Int?
        let filesProvidedInPrompt: Int?
        let successfulCapturedReads: Int?
        let readUnavailable: Int?
        let readDenied: Int?
        let testsExecuted: Bool?
        let semanticCoverage: String?
    }
    let id: String
    let sessionId: String
    let checkoutId: String
    let captureId: String
    let modelProfileId: Int?
    let model: Model
    let reasoning: Reasoning
    let coverage: Coverage
    let limitations: [String]
    let summary: String
    let status: String
    let errorCode: String?
    let lastEventSequence: Int
    let createdAt: Date
    let finishedAt: Date?
    let findings: [CodingReviewFinding]?
    let capture: CodingReviewCapture?
    var isActive: Bool { ["capturing", "starting", "running", "waiting_approval", "stopping"].contains(status) }
    var qualification: String {
        var values: [String] = []
        if status != "completed" { values.append(isActive ? "In progress" : "Incomplete review; findings are partial") }
        if capture?.limited == true { values.append("Limited capture") }
        if capture?.contentStatus != "available" { values.append("Captured content \(capture?.contentStatus ?? "not loaded")") }
        if capture?.applicability != "current" { values.append("Applicability: \(capture?.applicability ?? "unknown")") }
        return values.joined(separator: " · ")
    }
}

struct CodingReviewFinding: Decodable, Identifiable {
    let id: String
    let captureId: String
    let severity: String
    let title: String
    let body: String
    let path: String
    let side: String
    let lineStart: Int
    let lineEnd: Int
    let evidence: String
    let disposition: String
    let reason: String?
    let updatedByUserId: Int?
    let updatedAt: Date?
    var severityLabel: String {
        switch severity { case "blocker": "Blocker"; case "should_fix": "Should Fix"; case "consider": "Consider"; default: "Unknown severity" }
    }
    var anchor: String { "\(path) · \(side) L\(lineStart)-\(lineEnd)" }
}

struct CodingReviewApproval: Decodable, Identifiable {
    let id: String
    let reviewId: String
    let status: String
    let path: String
    let side: String
    let createdAt: Date
    let resolvedAt: Date?
}

struct CodingReviewDiff: Decodable {
    let basis: String
    let captureId: String
    let scope: String
    let base: String
    let head: String
    let path: String
    let capturedAt: Date
    let patch: String
    let truncated: Bool
}

struct CodingReviewEvent: Decodable {
    let schemaVersion: Int
    let reviewId: String
    let sequence: Int
    let kind: String
    let payload: [String: JSONValue]
}

struct CodingReviewCursor {
    private(set) var sequence = 0
    mutating func accept(_ event: CodingReviewEvent, reviewId: String) throws -> Bool {
        guard event.schemaVersion == 1, event.reviewId == reviewId, event.sequence > 0 else {
            throw CodingClientError(code: "invalid_event", message: "Mismatched review event or unsupported schema.")
        }
        if event.sequence <= sequence { return false }
        guard event.sequence == sequence + 1 else {
            throw CodingClientError(code: "event_gap", message: "Review event history has a gap. Refresh to reconcile.")
        }
        sequence = event.sequence
        return true
    }
}
