//
//  OnDeviceAgent.swift
//  FruitcakeAi
//
//  On-device AI fallback using Apple's FoundationModels framework.
//  Activated automatically when ConnectivityMonitor.isBackendReachable == false.
//
//  Capabilities in fallback mode:
//    ✅ Calendar lookup   (CalendarTool)
//    ✅ Reminders         (ReminderTool)
//    ✅ Contacts lookup   (ContactsTool)
//    ❌ Document search   (requires backend pgvector)
//    ❌ Web / RSS         (requires backend MCP tools)
//    ❌ Conversation sync (local only, isLocal = true)
//

import Foundation
import FoundationModels
import Observation

// MARK: - Model availability

enum OnDeviceAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String? {
        if case .unavailable(let msg) = self { return msg }
        return nil
    }
}

// MARK: - OnDeviceAgent

@Observable
final class OnDeviceAgent {

    private(set) var availability: OnDeviceAvailability = .unavailable("On-device AI requires macOS 26 or later.")

    // Opaque storage for LanguageModelSession (avoids top—level @available)
    private var _session: Any?

    // MARK: - Availability check

    func checkAvailability() {
        if #available(macOS 26.0, iOS 26.0, *) {
            _checkAvailabilityImpl()
        } else {
            availability = .unavailable("On-device AI requires macOS 26 or later.")
        }
    }

    // MARK: - Reset session (call when user switches conversations or reconnects)

    func resetSession() {
        _session = nil
    }

    // MARK: - Stream a response

    /// Returns an `AsyncStream<String>` that yields token chunks, mirroring
    /// the WebSocket `.token` events from the backend so ChatView needs no
    /// special-casing for offline mode.
    func stream(_ userMessage: String) -> AsyncStream<String> {
        // Guard: model must be available
        if case .unavailable(let msg) = availability {
            return AsyncStream { continuation in
                continuation.yield(msg)
                continuation.finish()
            }
        }

        guard #available(macOS 26.0, iOS 26.0, *) else {
            return AsyncStream { continuation in
                continuation.yield("On-device AI requires macOS 26 or later.")
                continuation.finish()
            }
        }

        return _streamImpl(userMessage)
    }

    // MARK: - Private implementation (macOS 26+)

    @available(macOS 26.0, iOS 26.0, *)
    private func _checkAvailabilityImpl() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            availability = .unavailable(_unavailableMessage(for: reason))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func _streamImpl(_ userMessage: String) -> AsyncStream<String> {
        let instructions = Instructions("""
        You are FruitcakeAI, a family assistant running in offline mode because the home server is unreachable.
        You have access to three local tools: calendar events, reminders, and contacts.
        Document search, web research, and RSS feeds are not available offline — say so clearly if asked.
        Keep responses concise and helpful. If you use a tool, summarise the results naturally.
        """)

        // Lazily create a session scoped to the current offline conversation
        if _session == nil {
            _session = LanguageModelSession(
                model: .default,
                tools: [CalendarTool(), ReminderTool(), ContactsTool()],
                instructions: instructions
            )
        }

        guard let session = _session as? LanguageModelSession else {
            return AsyncStream { continuation in
                continuation.yield("Could not start on-device session.")
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(to: userMessage)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                } catch {
                    continuation.yield("\n\n*On-device error: \(error.localizedDescription)*")
                }
                continuation.finish()
            }
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func _unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. On-device AI is unavailable."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Go to Settings → Apple Intelligence & Siri to enable it."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again in a few minutes."
        default:
            return "On-device AI is temporarily unavailable."
        }
    }
}
