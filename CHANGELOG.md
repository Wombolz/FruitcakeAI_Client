# Changelog

## v0.2.3

- Added transient, resizable MCP App dashboards with detached macOS windows and compact durable launchers in chat history.
- Added standard MCP App lifecycle, read-only tool bridging, and native approval sheets for consequential app actions.
- Added safe one-shot approval and denial handling without exposing backend or extension credentials to embedded app content.
- Improved dashboard sizing, teardown, reopening, and host capability reporting for interactive companion apps.

## v0.2.2

- Added richer evidence-aware streaming chat with durable inline image artifacts and tool/source details that survive reloads.
- Added native cards for tables, charts, news, metrics, timelines, workspace files, places, and code.
- Added wider assistant responses plus resizable detached data windows with column resizing, filtering, sorting, clickable links, and CSV copy/export.
- Added explicit context handback from tables, chart selections, place cards, and file references into the originating chat session.
- Added account and model controls plus administrator-managed user settings.
- Improved structured-content sizing, multi-table rendering, contextual headings, and session persistence.

## v0.2.1

- fix chat model selector so the chosen model updates immediately without requiring a refresh
- keep per-session model display state aligned with optimistic updates and backend-confirmed session state
- avoid stale selector labels when switching between sessions or revisiting an existing chat

## v0.2.0

- alpha client release candidate
- native chat, inbox, library, and settings flows
- backend-backed chat sessions with WebSocket and REST messaging
- on-device fallback support through Apple FoundationModels
- local Calendar, Reminders, and Contacts tool integration
- persistent manual chat ordering and full message timestamps

## Pre-release Notes

This project is still in alpha. Expect active iteration and occasional breaking changes.
