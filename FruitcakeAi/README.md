# FruitcakeAI Client

A shared Apple client for **FruitcakeAI** that targets **iPhone and Mac** from one SwiftUI codebase.

This repository contains the native client only. The backend, agent runtime, MCP tools, memory system, and document pipeline live in the separate **FruitcakeAI** backend repository.

## What It Is

FruitcakeAI Client provides:

- Native chat, inbox, library, and settings UI
- WebSocket and REST connectivity to the FruitcakeAI backend
- On-device AI fallback via Apple FoundationModels (offline mode)
- Local tool integrations (Calendar, Reminders, Contacts)
- APNs push notification support (optional)
- A shared SwiftUI codebase for iOS and macOS

It is not a standalone assistant runtime. It depends on a running FruitcakeAI backend for chat history sync, tasks, memory, RAG, MCP-backed tools, and admin functionality.

## Repository Relationship

| Repo | Purpose |
|------|---------|
| `FruitcakeAI` | Backend — FastAPI, LiteLLM, LlamaIndex, MCP tools |
| `FruitcakeAI_Client` | Native Apple client — SwiftUI, iOS + macOS |

## Quick Start

### Prerequisites

- **Xcode 16+** (macOS 15 Sequoia or later)
- A running FruitcakeAI backend server
- An Apple Developer account (free or paid — needed for code signing)

### 1. Clone and configure signing

```bash
git clone https://github.com/Wombolz/FruitcakeAI_Client.git
cd FruitcakeAI_Client
cp Local.xcconfig.example Local.xcconfig
```

Edit `Local.xcconfig` with your values:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.FruitcakeAi
```

**Finding your Team ID:** Sign in at [developer.apple.com](https://developer.apple.com), go to Account → Membership → Team ID.

### 2. Open and build

1. Open `FruitcakeAi.xcodeproj` in Xcode.
2. Choose a destination: `My Mac`, an iPhone simulator, or a connected device.
3. Build and run (`Cmd+R`).

### 3. Connect to your backend

On the login screen, enter:
- **Server URL** — your backend address (e.g., `http://192.168.1.100:30417`)
- **Username / Password** — a user account from the backend

For local development on the same machine, use `http://localhost:30417`.

## Configuration

### `Local.xcconfig`

This file holds per-developer build settings and is **gitignored**. Each contributor creates their own from the provided template:

| Setting | Description |
|---------|-------------|
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | Unique reverse-domain app identifier |

### Push Notifications (Optional)

APNs push notifications require:

1. A **paid** Apple Developer account
2. The **Push Notifications** capability added in Xcode → Signing & Capabilities
3. APNs credentials configured on the backend (see backend repo docs)

If you skip this, the app works normally without push — you just won't get background task notifications. No code changes needed.

To enable APNs:
1. In Xcode, select the FruitcakeAi target → Signing & Capabilities
2. Click **+ Capability** → **Push Notifications**
3. This will add the `aps-environment` entitlement automatically

### On-Device AI (Offline Mode)

When the backend is unreachable, the app falls back to Apple's on-device FoundationModels framework. This requires:

- macOS 26+ or iOS 26+
- Apple Intelligence enabled on the device
- A compatible Apple Silicon device

Available offline: Calendar, Reminders, and Contacts tools. Document search, web/RSS, and task management require the backend.

## Project Structure

```
FruitcakeAi/
├── Models/              # Codable data types (Task, Memory, UserProfile, etc.)
├── Services/            # API client, auth, connectivity, WebSocket, on-device agent
├── Tools/               # On-device tool implementations (Calendar, Reminders, Contacts)
├── Utilities/           # Keychain helper, markdown text utilities
├── Views/
│   ├── Chat/            # Chat UI, message bubbles, streaming
│   ├── Components/      # Shared components (ConnectionStatus)
│   ├── Inbox/           # Task list, detail sheet, creation
│   ├── Library/         # Document browsing and upload
│   └── Settings/        # Settings, persona picker, memories
├── AppDelegate.swift    # APNs token handling
├── ContentView.swift    # Root router (login / main tabs)
├── FruitcakeAiApp.swift # App entry point, service initialization
└── FruitcakeAi.entitlements
```

## Backend Setup

See the `FruitcakeAI` backend repository for full setup instructions. The client expects:

- `GET /admin/health` — health check endpoint
- `POST /auth/token` — JWT authentication
- `GET/POST /chat/*` — chat sessions and messaging
- `GET/POST /tasks/*` — task management
- `GET /memories/*` — memory system
- `GET /documents/*` — document library
- `WebSocket /chat/sessions/{id}/ws` — streaming chat

Default backend port: `30417`

## Contributing

1. Fork and clone the repo
2. Create `Local.xcconfig` from the example template
3. Create a feature branch from `main`
4. Make your changes and verify the build succeeds
5. Open a pull request

## License

See [LICENSE](LICENSE) for details.
