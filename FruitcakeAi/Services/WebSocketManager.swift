//
//  WebSocketManager.swift
//  FruitcakeAi
//
//  Manages a URLSessionWebSocketTask connection to one chat session.
//  Sends Authorization: Bearer on the HTTP upgrade request.
//
//  Usage:
//    let mgr = WebSocketManager()
//    mgr.connect(serverURL: url, sessionId: 5, token: jwt)
//    for await event in mgr.sendAndReceive("hello") { ... }
//    mgr.disconnect()
//

import Foundation
import Observation

// MARK: - Event model

enum WSEvent {
    case token(String)                          // partial chunk — append to streaming buffer
    case done(String, TaskDraft?)               // full response — store in SwiftData
    case personaSwitched(name: String, message: String)
    case error(String)
}

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting(sessionId: Int, connectionId: String)
    case connected(sessionId: Int, connectionId: String)
}

// MARK: - Manager

@MainActor
@Observable
final class WebSocketManager: NSObject, URLSessionWebSocketDelegate {

    private(set) var connectionState: WebSocketConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var taskConnectionIDs: [ObjectIdentifier: String] = [:]

    // The current response continuation — replaced per sendAndReceive call
    private var responseContinuation: AsyncStream<WSEvent>.Continuation?

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var connectionID: String {
        switch connectionState {
        case .disconnected:
            return ""
        case .connecting(_, let connectionId), .connected(_, let connectionId):
            return connectionId
        }
    }

    var connectedSessionID: Int? {
        switch connectionState {
        case .disconnected:
            return nil
        case .connecting(let sessionId, _), .connected(let sessionId, _):
            return sessionId
        }
    }

    var stateLabel: String {
        switch connectionState {
        case .disconnected:
            return "disconnected"
        case .connecting(let sessionId, let connectionId):
            return "connecting(session=\(sessionId),connection=\(connectionId))"
        case .connected(let sessionId, let connectionId):
            return "connected(session=\(sessionId),connection=\(connectionId))"
        }
    }

    private func transition(to newState: WebSocketConnectionState, reason: String) {
        let oldLabel = stateLabel
        if connectionState == newState {
            print("[ChatTrace] ws_state_transition_skipped state=\(oldLabel) reason=\(reason)")
            return
        }
        connectionState = newState
        let newLabel = stateLabel
        print("[ChatTrace] ws_state_transition from=\(oldLabel) to=\(newLabel) reason=\(reason)")
    }

    private func isCurrent(task: URLSessionWebSocketTask, connectionID: String) -> Bool {
        guard webSocketTask === task else { return false }
        switch connectionState {
        case .connecting(_, let currentConnectionID), .connected(_, let currentConnectionID):
            return currentConnectionID == connectionID
        case .disconnected:
            return false
        }
    }

    // MARK: - Connect

    func connect(serverURL: URL, sessionId: Int, token: String) {
        disconnect()

        guard let wsURL = makeWSURL(from: serverURL, sessionId: sessionId) else { return }
        let connectionID = UUID().uuidString

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        transition(to: .connecting(sessionId: sessionId, connectionId: connectionID), reason: "connect")
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: request)
        if let task = webSocketTask {
            taskConnectionIDs[ObjectIdentifier(task)] = connectionID
        }
        webSocketTask?.resume()
        print("[ChatTrace] ws_connect session=\(sessionId) connection_id=\(connectionID) url=\(wsURL.absoluteString)")

        guard let task = webSocketTask else { return }
        Task { await receiveLoop(task: task, connectionID: connectionID) }
    }

    // MARK: - Send and receive

    /// Sends a message and returns a fresh AsyncStream of events for this response.
    /// The stream finishes when a terminal event (.done, .error, .personaSwitched) arrives.
    /// Send errors are surfaced as a `.error` event rather than thrown or swallowed.
    func sendAndReceive(
        _ content: String,
        clientSendID: String,
        allowedTools: [String]? = nil,
        blockedTools: [String]? = nil
    ) async -> AsyncStream<WSEvent> {
        guard let task = webSocketTask else {
            return AsyncStream { $0.finish() }
        }
        guard case .connected = connectionState else {
            return AsyncStream { $0.finish() }
        }

        // Finish any previous response stream before starting a new one
        print("[ChatTrace] ws_response_stream_replace connection_id=\(connectionID) client_send_id=\(clientSendID) had_existing=\(responseContinuation != nil)")
        responseContinuation?.finish()

        let (stream, continuation) = AsyncStream<WSEvent>.makeStream()
        responseContinuation = continuation

        var payload: [String: Any] = ["content": content, "client_send_id": clientSendID]
        if let allowedTools, !allowedTools.isEmpty {
            payload["allowed_tools"] = allowedTools
        }
        if let blockedTools, !blockedTools.isEmpty {
            payload["blocked_tools"] = blockedTools
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: data, encoding: .utf8) else {
            continuation.yield(.error("Failed to encode send payload"))
            continuation.finish()
            responseContinuation = nil
            return stream
        }

        print("[ChatTrace] ws_send connection_id=\(connectionID) client_send_id=\(clientSendID) chars=\(content.count)")

        do {
            try await task.send(.string(text))
        } catch {
            print("[ChatTrace] ws_send_error connection_id=\(connectionID) client_send_id=\(clientSendID) error=\(error.localizedDescription)")
            transition(to: .disconnected, reason: "send_error")
            continuation.yield(.error("WebSocket send failed: \(error.localizedDescription)"))
            continuation.finish()
            responseContinuation = nil
        }

        return stream
    }

    // MARK: - Disconnect

    func disconnect() {
        if case .disconnected = connectionState {
            // no-op
        } else {
            print("[ChatTrace] ws_disconnect connection_id=\(connectionID)")
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        responseContinuation?.finish()
        responseContinuation = nil
        transition(to: .disconnected, reason: "disconnect")
    }

    func ensureConnected(serverURL: URL, sessionId: Int, token: String, timeoutSeconds: Double = 1.0) async -> Bool {
        switch connectionState {
        case .connected(let currentSessionId, _ ) where currentSessionId == sessionId:
            print("[ChatTrace] ws_ensure_connect_reuse_connected session=\(sessionId) connection_id=\(connectionID)")
            return true
        case .connecting(let currentSessionId, _ ) where currentSessionId == sessionId:
            print("[ChatTrace] ws_ensure_connect_wait_connecting session=\(sessionId) connection_id=\(connectionID)")
        default:
            print("[ChatTrace] ws_ensure_connect_initiate_reconnect target_session=\(sessionId) current_state=\(stateLabel)")
            connect(serverURL: serverURL, sessionId: sessionId, token: token)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            switch connectionState {
            case .connected(let currentSessionId, let currentConnectionId) where currentSessionId == sessionId:
                print("[ChatTrace] ws_ensure_connect_ready session=\(sessionId) connection_id=\(currentConnectionId)")
                return true
            case .connecting(let currentSessionId, _ ) where currentSessionId == sessionId:
                break
            default:
                print("[ChatTrace] ws_ensure_connect_aborted session=\(sessionId) state=\(stateLabel)")
                return false
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        print("[ChatTrace] ws_ensure_connect_timeout session=\(sessionId) state=\(stateLabel)")
        return false
    }

    // MARK: - Receive loop

    private func receiveLoop(task: URLSessionWebSocketTask, connectionID: String) async {
        print("[ChatTrace] ws_receive_loop_start connection_id=\(connectionID)")
        while true {
            do {
                let message = try await task.receive()
                guard isCurrent(task: task, connectionID: connectionID) else {
                    print("[ChatTrace] ws_receive_loop_stale_exit connection_id=\(connectionID) current_connection_id=\(self.connectionID)")
                    return
                }
                if case .string(let text) = message {
                    handleIncoming(text)
                }
            } catch {
                guard isCurrent(task: task, connectionID: connectionID) else {
                    print("[ChatTrace] ws_receive_loop_stale_error_exit connection_id=\(connectionID) current_connection_id=\(self.connectionID)")
                    return
                }
                print("[ChatTrace] ws_receive_loop_error connection_id=\(connectionID) error=\(error.localizedDescription)")
                // Connection closed or error
                responseContinuation?.finish()
                responseContinuation = nil
                transition(to: .disconnected, reason: "receive_loop_error")
                break
            }
        }
        print("[ChatTrace] ws_receive_loop_end connection_id=\(connectionID) state=\(stateLabel)")
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFractional.date(from: s) { return d }
            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let d = withoutFractional.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "Cannot decode date: \(s)"))
        }
        guard let payload = try? decoder.decode(WSPayload.self, from: data) else {
            return
        }

        if responseContinuation == nil {
            print("[ChatTrace] ws_post_terminal_frame_ignored connection_id=\(connectionID) type=\(payload.type) chars=\(payload.content.count)")
            return
        }

        print("[ChatTrace] ws_incoming connection_id=\(connectionID) type=\(payload.type) chars=\(payload.content.count)")

        switch payload.type {
        case "token":
            responseContinuation?.yield(.token(payload.content))

        case "done":
            responseContinuation?.yield(.done(payload.content, payload.metadata?.taskDraft))
            responseContinuation?.finish()
            responseContinuation = nil

        case "persona":
            let name = payload.persona ?? ""
            responseContinuation?.yield(.personaSwitched(name: name, message: payload.content))
            responseContinuation?.finish()
            responseContinuation = nil

        case "error":
            responseContinuation?.yield(.error(payload.content))
            responseContinuation?.finish()
            responseContinuation = nil

        default:
            break
        }
    }

    // MARK: - URL helper

    private func makeWSURL(from serverURL: URL, sessionId: Int) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/chat/sessions/\(sessionId)/ws"
        return components.url
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            guard self.webSocketTask === webSocketTask else { return }
            guard case .connecting(let sessionId, let connectionID) = self.connectionState else { return }
            self.transition(to: .connected(sessionId: sessionId, connectionId: connectionID), reason: "delegate_open")
            print("[ChatTrace] ws_open connection_id=\(connectionID)")
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            let taskID = ObjectIdentifier(webSocketTask)
            let closingConnectionID = self.taskConnectionIDs[taskID] ?? self.connectionID
            if self.webSocketTask === webSocketTask {
                self.taskConnectionIDs.removeValue(forKey: taskID)
            }
            guard self.webSocketTask === webSocketTask || !closingConnectionID.isEmpty else { return }
            self.transition(to: .disconnected, reason: "delegate_close")
            print("[ChatTrace] ws_closed connection_id=\(closingConnectionID) close_code=\(closeCode.rawValue)")
        }
    }
}

// MARK: - Wire payload

private struct WSPayload: Decodable {
    let type: String
    let content: String
    let persona: String?
    let metadata: WSPayloadMetadata?
}

private struct WSPayloadMetadata: Decodable {
    let taskDraft: TaskDraft?

    private enum CodingKeys: String, CodingKey {
        case taskDraft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            taskDraft = try container.decodeIfPresent(TaskDraft.self, forKey: .taskDraft)
        } catch {
            print("[ChatTrace] ws_task_draft_decode_error: \(error)")
            taskDraft = nil
        }
    }
}
