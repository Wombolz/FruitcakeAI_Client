# FruitcakeAI Client

A shared Apple client for **FruitcakeAI** that targets **iPhone and Mac** from one SwiftUI codebase.

This repository contains the native client only. The backend, agent runtime, MCP tools, memory system, and document pipeline live in the separate **FruitcakeAI** backend repository.

## What It Is

FruitcakeAI Client provides:

- native chat, inbox, library, and settings UI
- APNs device registration and notification handling
- WebSocket and REST connectivity to the FruitcakeAI backend
- local Apple-framework integrations where supported
- a shared SwiftUI codebase for iOS and macOS

It is not a standalone assistant runtime. It depends on a running FruitcakeAI backend for chat history sync, tasks, memory, RAG, MCP-backed tools, and admin functionality.

## Repository Relationship

- Backend/runtime repo: `FruitcakeAI`
- Shared Apple client repo: `FruitcakeAI_Client`

The client is intentionally named for the Apple platform as a whole, not iPhone only. The current Xcode project supports iOS and macOS from the same codebase.

## Quick Start

### Prerequisites

- Xcode 16+
- A running FruitcakeAI backend server
- An Apple developer account only if you want to test APNs on device

### Open and run

1. Open `FruitcakeAi.xcodeproj` in Xcode.
2. Choose a supported destination (`iPhone Simulator`, device, or `My Mac`).
3. Build and run.
4. In Settings, set the backend server URL.
5. Log in with a backend user account.

## Backend Setup

Set up and run the backend from the `FruitcakeAI` repo.

Expected local backend default:

- `http://localhost:8000`

For a second machine or phone on LAN, point the client to the reachable backend host/IP instead.

## Current Scope

- Shared SwiftUI app for iOS and macOS
- Task inbox and approval UX
- Chat with REST + WebSocket paths
- Library browsing and uploads
- Persona/settings management
- APNs integration for Apple devices

## Documentation

- Backend repo docs live in `FruitcakeAI/Docs/`
- Architecture notes in this repo remain implementation-oriented and client-specific

## Rollback / Rename Notes

This repo was prepared for the Phase 5.6 repository realignment. If a rename causes remote issues, restore the previous remote URL temporarily and use the pre-realignment checkpoint tag until docs and tooling are consistent.
