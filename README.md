# FruitcakeAI Client

**A self-hosted AI agent platform for households and small teams.**
**Local-first. Private by default.**

FruitcakeAI Client is the native Apple client for **FruitcakeAI**.

It targets **iPhone and Mac** from one SwiftUI codebase and depends on a running FruitcakeAI backend for synchronized chat, tasks, memory, document access, and server-backed tools.

This repository contains the client only. The backend lives in the separate `FruitcakeAI` repository.

## Alpha Status

This repo is being opened as an **alpha**.

That means:

- behavior and APIs may still change quickly
- setup is still opinionated toward local/self-hosted development
- some features depend on backend capabilities that are still evolving
- bug reports are welcome
- broad outside co-development is not the default workflow yet

If you are evaluating the project, expect active iteration rather than long-term stability guarantees.

## What It Includes

- native chat, inbox, library, and settings UI
- WebSocket and REST connectivity to the FruitcakeAI backend
- on-device AI fallback via Apple FoundationModels
- local Calendar, Reminders, and Contacts tools
- optional APNs push notification support
- a shared SwiftUI codebase for iOS and macOS

## Repository Relationship

| Repo | Purpose |
|------|---------|
| `FruitcakeAI` | Backend: FastAPI, agent runtime, memory, MCP tools, documents, tasks |
| `FruitcakeAI_Client` | Apple client: SwiftUI, iOS + macOS |

## Quick Start

### Prerequisites

- Xcode 16+
- macOS 15 or later for development
- a running FruitcakeAI backend server
- an Apple Developer account for signing

### 1. Clone and configure signing

```bash
git clone https://github.com/Wombolz/FruitcakeAI_Client.git
cd FruitcakeAI_Client
cp Local.xcconfig.example Local.xcconfig
```

Edit `Local.xcconfig`:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.FruitcakeAi
```

### 2. Open and build

1. Open `FruitcakeAi.xcodeproj` in Xcode.
2. Choose a destination such as `My Mac`, an iPhone simulator, or a connected device.
3. Build and run with `Cmd+R`.

### 3. Connect to your backend

On the login screen, enter:

- `Server URL`: for example `http://192.168.1.100:30417`
- `Username / Password`: a valid backend user account

For local development on the same machine, use `http://localhost:30417`.

## Configuration

### `Local.xcconfig`

This file is gitignored and holds per-developer build settings.

| Setting | Description |
|---------|-------------|
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | Unique reverse-domain app identifier |

### Push Notifications

APNs support is optional and requires:

1. a paid Apple Developer account
2. the Push Notifications capability enabled in Xcode
3. APNs credentials configured on the backend

If you skip this, the app still works normally without push notifications.

### On-Device AI

When the backend is unavailable, the app can fall back to Apple FoundationModels.

Requirements:

- macOS 26+ or iOS 26+
- Apple Intelligence enabled
- compatible Apple Silicon hardware

Available offline:

- Calendar
- Reminders
- Contacts

Backend-required:

- synchronized chat history
- tasks
- memories
- documents
- web or RSS-backed features

## Known Limits

- This is a backend-dependent client, not a standalone assistant runtime.
- Shared Google and Apple integration identity is currently enforced by the backend application, not isolated per user.
- Per-user Google and Apple integration access is planned, but it is not the current development priority.
- Some capabilities depend on backend versions that may still change during alpha.
- Public bug reports are welcome, but the project is not yet broadly open to unsolicited large code contributions.

## Project Structure

```text
FruitcakeAi/
├── Models/
├── Services/
├── Tools/
├── Utilities/
├── Views/
├── AppDelegate.swift
├── ContentView.swift
├── FruitcakeAiApp.swift
└── FruitcakeAi.entitlements
```

## Public Project Docs

- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## License

See [LICENSE](LICENSE).
