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
    case done(String)                           // full response — store in SwiftData
    case personaSwitched(name: String, message: String)
    case error(String)
}

// MARK: - Manager

@Observable
final class WebSocketManager: NSObject {

    private(set) var isConnected: Bool = false
    private(set) var connectionID: String = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // The current response continuation — replaced per sendAndReceive call
    private var responseContinuation: AsyncStream<WSEvent>.Continuation?

    // MARK: - Connect

    func connect(serverURL: URL, sessionId: Int, token: String) {
        disconnect()

        guard let wsURL = makeWSURL(from: serverURL, sessionId: sessionId) else { return }
        connectionID = UUID().uuidString

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        print("[ChatTrace] ws_connect session=\(sessionId) connection_id=\(connectionID) url=\(wsURL.absoluteString)")

        Task { await receiveLoop() }
    }

    // MARK: - Send and receive

    /// Sends a message and returns a fresh AsyncStream of events for this response.
    /// The stream finishes when a terminal event (.done, .error, .personaSwitched) arrives.
    func sendAndReceive(
        _ content: String,
        clientSendID: String,
        allowedTools: [String]? = nil,
        blockedTools: [String]? = nil
    ) throws -> AsyncStream<WSEvent> {
        guard let task = webSocketTask, isConnected else {
            return AsyncStream { $0.finish() }
        }

        // Finish any previous response stream
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
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let text = String(data: data, encoding: .utf8) ?? "{}"
        print("[ChatTrace] ws_send connection_id=\(connectionID) client_send_id=\(clientSendID) chars=\(content.count)")

        Task {
            try await task.send(.string(text))
        }

        return stream
    }

    // MARK: - Disconnect

    func disconnect() {
        if isConnected {
            print("[ChatTrace] ws_disconnect connection_id=\(connectionID)")
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        responseContinuation?.finish()
        responseContinuation = nil
        isConnected = false
        connectionID = ""
    }

    // MARK: - Receive loop

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while isConnected {
            do {
                let message = try await task.receive()
                if case .string(let text) = message {
                    handleIncoming(text)
                }
            } catch {
                // Connection closed or error
                responseContinuation?.finish()
                responseContinuation = nil
                isConnected = false
                break
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(WSPayload.self, from: data) else {
            return
        }

        switch payload.type {
        case "token":
            responseContinuation?.yield(.token(payload.content))

        case "done":
            responseContinuation?.yield(.done(payload.content))
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
}

// MARK: - Wire payload

private struct WSPayload: Decodable {
    let type: String
    let content: String
    let persona: String?
}
