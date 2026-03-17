# FruitcakeAI v5 — Native Swift Client Architecture

**Context**: This document describes the native iOS/macOS Swift client that replaces the React frontend in Phase 3 of the FruitcakeAI v5 roadmap. The Python backend (FastAPI + LiteLLM + LlamaIndex RAG + MCP tools) is built separately and unchanged. This client consumes its API.

**Repository**: `FruitcakeAI_Client`  
**Backend Repository**: `FruitcakeAI`

---

## Two-Tier Architecture

```
┌─────────────────────────────────────────────────┐
│            Native Swift App (Xcode)             │
│                                                 │
│  SwiftUI Views                                  │
│  ├── ChatView (conversation UI)                 │
│  ├── LibraryView (document management)          │
│  ├── SettingsView (persona, server config)      │
│  └── CalendarView (native EventKit)             │
│                                                 │
│  Services Layer                                 │
│  ├── APIClient (REST calls to Python backend)   │
│  ├── WebSocketManager (streaming chat)          │
│  ├── AuthManager (JWT token handling)           │
│  └── OnDeviceAgent (FoundationModels fallback)  │
│                                                 │
│  Local Data                                     │
│  ├── SwiftData (cached conversations, prefs)    │
│  └── Keychain (JWT tokens, server credentials)  │
└────────────────┬────────────────────────────────┘
                 │ WebSocket + REST (over LAN or localhost)
┌────────────────▼────────────────────────────────┐
│         Python Backend (unchanged)              │
│         FastAPI + Agent Core + RAG + MCP        │
└─────────────────────────────────────────────────┘
```

The Swift app is a **client only**. All RAG, agent orchestration, MCP tool dispatch, and document storage happen on the Python backend. The Swift client adds native Apple integrations and an on-device fallback for when the backend is unreachable.

---

## Backend API Contract

The Swift client talks to these backend endpoints (built in Phases 1-2):

```
POST /auth/register          → Create account
POST /auth/login             → Returns { access_token, refresh_token }
GET  /auth/me                → Current user info

POST /chat/sessions          → Create chat session (with persona)
POST /chat/sessions/{id}/messages → Send message, get LLM response
WS   /chat/ws/{session_id}   → WebSocket streaming chat

POST /library/ingest         → Upload document (multipart + scope)
GET  /library/query?q=...    → Semantic search with citations
GET  /library/documents      → List user's documents
DELETE /library/documents/{id}

GET  /admin/tools            → List registered MCP tools
GET  /admin/health           → Backend dependency status
GET  /admin/users            → User management (admin only)
```

All endpoints require `Authorization: Bearer <jwt_token>` except `/auth/login` and `/auth/register`.

---

## On-Device Fallback (Apple FoundationModels)

When the Python backend is unreachable (server off, away from home), the app falls back to Apple's on-device language model via the FoundationModels framework.

### Capabilities in fallback mode
- Text summarization, understanding, creative writing
- Structured generation via `@Generable` macro
- Tool calling for local data (EventKit calendar, Contacts, Reminders)

### Limitations in fallback mode
- **4096 token context window** — suitable for short tasks, not long conversations
- **No RAG** — document search requires the backend's pgvector + LlamaIndex
- **No MCP tools** — web research, RSS, etc. require the backend
- **No conversation history sync** — conversations in fallback mode are local only
- Requires Apple Intelligence enabled on device

### On-device tool example (EventKit calendar)

```swift
import FoundationModels
import EventKit

struct CalendarLookup: Tool {
    let name = "checkCalendar"
    let description = "Find upcoming calendar events"

    @Generable
    struct Arguments {
        @Guide(description: "Number of days ahead to check", .range(1...14))
        var daysAhead: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let store = EKEventStore()
        let start = Date.now
        let end = Calendar.current.date(byAdding: .day,
                                         value: arguments.daysAhead,
                                         to: start)!
        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        )
        let events = store.events(matching: predicate)
        return events.map {
            "\($0.title ?? "Untitled") - \($0.startDate.formatted())"
        }.joined(separator: "\n")
    }
}
```

### Availability check

```swift
import FoundationModels

let model = SystemLanguageModel.default

switch model.availability {
case .available:
    // Use on-device model
case .unavailable(.deviceNotEligible):
    // Show "requires Apple Intelligence" message
case .unavailable(.appleIntelligenceNotEnabled):
    // Prompt user to enable Apple Intelligence in Settings
case .unavailable(.modelNotReady):
    // Model is downloading
case .unavailable(_):
    // Unavailable for other reasons
}
```

---

## Native Apple Integrations

These integrations work regardless of backend connectivity and provide capabilities the Python backend cannot match:

| Integration | Framework | What it provides |
|-------------|-----------|-----------------|
| Calendar | EventKit | Direct read/write to Apple Calendar, no OAuth needed |
| Reminders | EventKit | Create/read reminders from same event store |
| Contacts | Contacts framework | Local contact lookup for the on-device agent |
| Notifications | UserNotifications | Push/local alerts for reminders and events |
| Shortcuts/Siri | App Intents | "Hey Siri, ask Fruitcake..." voice access |
| Widgets | WidgetKit | At-a-glance family info on home screen |
| Files | FileProvider / UIDocumentPicker | iCloud and local file access for document upload |

**Important**: EventKit requires `NSCalendarsFullAccessUsageDescription` in Info.plist and a call to `EKEventStore.requestFullAccessToEvents()` before reading events. Contacts requires `NSContactsUsageDescription`.

---

## Networking Layer

### REST API Client

Uses `URLSession` with async/await. All requests include the JWT bearer token from Keychain.

```swift
class APIClient {
    let baseURL: URL       // e.g. http://192.168.1.100:30417
    let authManager: AuthManager

    func sendMessage(sessionId: UUID, content: String) async throws -> ChatResponse {
        var request = URLRequest(url: baseURL.appending(
            path: "/chat/sessions/\(sessionId)/messages"
        ))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await authManager.token())",
                        forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["content": content])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }
}
```

### WebSocket Streaming

Uses `URLSessionWebSocketTask` for streaming chat responses token-by-token.

```swift
class WebSocketManager {
    private var webSocket: URLSessionWebSocketTask?

    func connect(serverURL: URL, token: String) {
        var request = URLRequest(url: serverURL)
        request.setValue("Bearer \(token)",
                        forHTTPHeaderField: "Authorization")
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
    }

    func receiveStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                while let message = try? await webSocket?.receive() {
                    if case .string(let text) = message {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

### Auth Manager

Stores JWT tokens in Keychain. Handles login, token refresh, and expiry.

```swift
class AuthManager {
    func login(username: String, password: String, serverURL: URL) async throws {
        // POST /auth/login → store access_token + refresh_token in Keychain
    }

    func token() async throws -> String {
        // Return cached token, refresh if expired
    }

    var isAuthenticated: Bool { /* check Keychain */ }
}
```

---

## Hybrid Connectivity Model

The app detects whether the backend is reachable and adjusts capabilities accordingly.

```
Backend reachable?
├── YES → Full mode
│   ├── Chat via WebSocket (streaming)
│   ├── RAG document search
│   ├── All MCP tools (calendar, web, RSS)
│   ├── Multi-user persona system
│   └── Conversation history synced to server
│
└── NO → Fallback mode
    ├── On-device FoundationModels (4096 token limit)
    ├── Local tools only (EventKit, Contacts)
    ├── No RAG, no web search, no RSS
    ├── Conversations stored locally in SwiftData
    └── UI shows clear "offline" indicator
```

The connection status should be checked periodically (e.g. ping `/admin/health`) and the UI should clearly indicate which mode is active.

---

## Data Layer

### SwiftData Models (local persistence)

```swift
@Model
class CachedMessage {
    var id: UUID
    var sessionId: UUID
    var role: String          // "user" or "assistant"
    var content: String
    var timestamp: Date
    var toolCalls: [String]?  // Tool names invoked, for UI indicators
    var isLocal: Bool         // true if created in fallback mode
}

@Model
class CachedConversation {
    var id: UUID
    var title: String
    var persona: String
    var lastActivity: Date
    var messages: [CachedMessage]
}

@Model
class ServerConfig {
    var serverURL: String     // e.g. "http://192.168.1.100:30417"
    var isDefault: Bool
}
```

### Keychain

Store JWT tokens and server credentials in Keychain, never in SwiftData or UserDefaults.

---

## Project Structure

```
FruitcakeAI_Client/
├── App/
│   └── FruitcakeAiApp.swift
├── Models/
│   ├── Message.swift              // SwiftData model for cached messages
│   ├── Conversation.swift         // SwiftData model for conversations
│   ├── UserProfile.swift          // Current user, persona, role
│   └── ServerConfig.swift         // Backend connection settings
├── Services/
│   ├── APIClient.swift            // REST calls to Python backend
│   ├── WebSocketManager.swift     // Streaming chat via WebSocket
│   ├── AuthManager.swift          // JWT login, token refresh, Keychain
│   ├── OnDeviceAgent.swift        // FoundationModels fallback agent
│   └── ConnectivityMonitor.swift  // Backend reachability detection
├── Tools/                         // On-device Tool protocol implementations
│   ├── CalendarTool.swift         // EventKit calendar lookup
│   ├── ReminderTool.swift         // EventKit reminders
│   └── ContactsTool.swift         // Contacts framework lookup
├── Views/
│   ├── Chat/
│   │   ├── ChatView.swift         // Main chat interface
│   │   ├── MessageBubble.swift    // Individual message rendering
│   │   └── ToolCallIndicator.swift // "Searching library..." status
│   ├── Library/
│   │   ├── LibraryView.swift      // Document list from backend
│   │   └── DocumentUpload.swift   // File picker + multipart upload
│   ├── Settings/
│   │   ├── SettingsView.swift     // Server URL, account management
│   │   └── PersonaPicker.swift    // Switch persona (dropdown)
│   └── Components/
│       └── ConnectionStatus.swift // Online/offline banner
└── Utilities/
    └── KeychainHelper.swift       // Keychain read/write wrapper
```

---

## How This Fits the Roadmap

- **Phases 1-2**: Build the Python backend as planned. No Swift work needed.
- **Phase 3**: Replace "React Frontend API Migration" with this native Swift client. The React frontend becomes optional (web-only access).
- **Phase 3 addition**: Implement on-device fallback and native Apple integrations (EventKit, Contacts, Notifications).
- **Future**: App Intents for Siri, WidgetKit for home screen widgets, background sync when returning to connectivity.

---

## Implementation Order (Phase 3)

1. **Networking**: `APIClient`, `AuthManager`, `WebSocketManager` — connect to the working backend
2. **Chat UI**: `ChatView`, `MessageBubble`, streaming display — core user experience
3. **Library**: Document list + upload — connects to RAG backend
4. **Settings**: Server config, persona picker — multi-user support
5. **On-device fallback**: `OnDeviceAgent`, `CalendarTool` — offline capability
6. **Polish**: Connection status indicator, tool call visualization, error handling
