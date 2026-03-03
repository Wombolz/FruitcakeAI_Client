# 🍰 FruitcakeAI v5 — Rebuild Roadmap

**Version**: 5.1  
**Status**: Phase 1 Complete ✅ · Phase 2 Complete ✅ · Phase 3 Complete ✅ · Sprint 3.7 Complete ✅
**Philosophy**: Agent-first. The AI orchestrates the tools — not the other way around.  
**Build Location**: `/Users/jwomble/Development/fruitcake_v5/`  
**Last Updated**: March 2026

---

## Executive Summary

FruitcakeAI v5 is a clean rebuild that preserves the best ideas from v3/v4 — hybrid RAG retrieval, multi-user/persona support, MCP tool integration — while discarding the complexity that made v3/v4 cumbersome: the ServiceOrchestrator, PolicyRouter, intent detection keyword system, and enterprise-scale infrastructure aspirations.

The core mental model shift:

> **v3/v4**: A platform that contains an AI  
> **v5**: An AI agent that has tools

Orchestration moves from hand-written rules into the LLM itself. New capabilities are added via MCP configuration, not code. Multi-user support is injected context, not an enforcement layer.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              React Frontend                 │
│         (keep existing — rewire API)        │
└─────────────────────┬───────────────────────┘
                      │ WebSocket / REST
┌─────────────────────▼───────────────────────┐
│           FastAPI — Thin Layer              │
│   Auth (JWT) · File Upload · Chat API       │
│   User/Session Management                  │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│              Agent Core                     │
│   LiteLLM (model-agnostic)                  │
│   System prompt = user context + persona    │
│   Tool-calling drives all orchestration     │
└──────┬───────────┬───────────┬──────────────┘
       │           │           │
┌──────▼───┐ ┌─────▼────┐ ┌───▼─────────────┐
│   RAG    │ │Calendar  │ │  Web / RSS / etc │
│LlamaIndex│ │  MCP     │ │   MCP Servers    │
│pgvector  │ │          │ │ (Docker, stdio)  │
└──────┬───┘ └──────────┘ └─────────────────┘
       │
┌──────▼────────────────────┐
│   PostgreSQL + pgvector   │
│   Redis (optional, Phase 4)│
└───────────────────────────┘
```

---

## Project Structure

```
fruitcake_v5/
├── app/
│   ├── main.py                    # FastAPI app, startup, routers
│   ├── config.py                  # Pydantic settings from .env
│   ├── auth/
│   │   ├── router.py              # /auth/login, /auth/me, /auth/register
│   │   ├── models.py              # User, Session DB models
│   │   └── jwt.py                 # JWT encode/decode helpers
│   ├── agent/
│   │   ├── core.py                # Agent loop — LiteLLM + tool dispatch
│   │   ├── context.py             # UserContext builder (persona injection)
│   │   ├── tools.py               # Tool registry (wraps MCP + internal tools)
│   │   └── prompts.py             # System prompt templates
│   ├── rag/
│   │   ├── service.py             # LlamaIndex setup, query engine
│   │   ├── ingest.py              # Document ingestion pipeline
│   │   ├── retriever.py           # Hybrid BM25 + vector + RRF
│   │   └── config.yaml            # LlamaIndex configuration
│   ├── mcp/
│   │   ├── client.py              # MCP stdio/Docker client (from v4)
│   │   ├── registry.py            # Auto-discovery from mcp_config.yaml
│   │   └── servers/
│   │       ├── mcp_config.yaml    # All MCP server definitions
│   │       ├── calendar.py        # Calendar MCP wrapper
│   │       ├── web_research.py    # Web research MCP wrapper
│   │       └── rss.py             # RSS MCP wrapper
│   ├── api/
│   │   ├── chat.py                # /chat/sessions, /chat/messages (WebSocket)
│   │   ├── library.py             # /library/ingest, /library/query
│   │   └── admin.py               # /admin/health, /admin/metrics (simple)
│   └── db/
│       ├── models.py              # SQLAlchemy models (users, sessions, docs)
│       ├── session.py             # Async DB session
│       └── migrations/            # Alembic migrations
├── frontend/                      # Existing React app (rewire API calls)
├── config/
│   ├── mcp_config.yaml            # MCP server definitions
│   ├── personas.yaml              # User persona definitions
│   └── users.yaml                 # Default user seed config
├── tests/
│   ├── test_agent.py
│   ├── test_rag.py
│   ├── test_auth.py
│   └── test_mcp.py
├── scripts/
│   ├── start.sh                   # One-command startup (includes Ollama health check)
│   └── reset.sh                   # Wipe and reseed DB for development
├── docker-compose.yml
├── .env / .env.example
├── requirements.txt
└── README.md
```

---

## ⚠️ Ground Truth: Verified Working Configuration

This is the actual working setup as of Phase 1 completion. All code examples in this document reflect these findings — not the original roadmap sketches.

### Hardware
- **Machine**: M1 Max, 64GB RAM (macOS)
- **Verified LLM**: `qwen2.5:14b` via Ollama ✅
- **Attempted**: `llama3.3:70b` (~43GB) — **crashes Ollama** due to memory pressure alongside embedding model + macOS overhead. May work with all other apps closed, or use `qwen2.5:32b` (~20GB) as a middle-ground option.

### LiteLLM / Ollama Critical Notes

**Use `ollama_chat/` prefix, not `ollama/`**
```env
# ✅ CORRECT — uses /api/chat, supports tool/function calling
LLM_MODEL=ollama_chat/qwen2.5:14b

# ❌ WRONG — uses /api/generate, tool calls silently broken
LLM_MODEL=ollama/qwen2.5:14b
```

**Always pass `api_base` explicitly**  
LiteLLM may attempt cloud endpoints without it. Use the `_litellm_kwargs()` helper in `app/agent/core.py` which strips the `/v1` suffix:
```python
def _litellm_kwargs(self) -> dict:
    base = settings.local_api_base.rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3]
    return {"api_base": base, "model": settings.llm_model}
```

**Check `message.tool_calls`, not `finish_reason`**  
Ollama with qwen2.5:14b returns `finish_reason="stop"` even when tool calls are present. The agent loop must check directly:
```python
# ✅ CORRECT
while message.tool_calls:
    ...

# ❌ WRONG — misses tool calls with Ollama
while response.choices[0].finish_reason == "tool_calls":
    ...
```

**`_normalize_tool_calls()` is required**  
After `message.model_dump(exclude_none=True)`, the `arguments` field is converted from a JSON string to a Python dict. On the next LiteLLM call, the token counter crashes: `TypeError: can only concatenate str (not "dict") to str`. Fix: re-serialize before appending to history:
```python
def _normalize_tool_calls(message_dict: dict) -> dict:
    if "tool_calls" in message_dict:
        for tc in message_dict["tool_calls"]:
            if isinstance(tc.get("function", {}).get("arguments"), dict):
                tc["function"]["arguments"] = json.dumps(
                    tc["function"]["arguments"]
                )
    return message_dict
```

### Package Versions (requirements.txt — actual)
```
litellm>=1.82.0          # 1.55.3 has token_counter crash with Ollama tool schemas
bcrypt>=3.1,<4.1
email-validator>=2.0
aiosqlite>=0.19.0
```

> ⚠️ **Known conflict**: `litellm>=1.82.0` pulls `openai>=2.24.0`, which conflicts with `llama-index-llms-openai` requiring `openai<2`. Since we disable LlamaIndex's LLM entirely (`Settings.llm = None`), this is currently harmless. Resolve in Sprint 2.1 with a package pin.

### Alembic Configuration
```ini
# alembic.ini — must use asyncpg, not psycopg2
sqlalchemy.url = postgresql+asyncpg://user:pass@localhost/fruitcake_v5
```
`DATABASE_URL_SYNC` (psycopg2) is kept in `.env` for other sync uses but is not consumed by Alembic.

### LlamaIndex Startup Warning
```
LLM is explicitly disabled. Using MockLLM.
```
This is **expected and harmless**. We set `Settings.llm = None` intentionally — all inference goes through LiteLLM, not LlamaIndex's LLM layer.

### BM25 on Empty Docstore
BM25Retriever throws `RuntimeWarning: max() arg is an empty sequence` on fresh startup. This is handled by the `has_docs` guard in `app/rag/retriever.py` — BM25 is skipped until the first document is ingested, then activated via `_rebuild_retriever()`. RuntimeWarnings are suppressed with `warnings.catch_warnings()` during BM25 initialization.

---

## Phase 1: Agent Core + RAG Foundation ✅ COMPLETE
**Completed**: March 2026  
**Actual Duration**: ~2 weeks

### What Was Built
- FastAPI thin layer → LiteLLM agent core → LlamaIndex RAG + pgvector
- JWT auth with roles (admin/parent/child/guest)
- Persona/UserContext injected as system prompt
- `search_library` as first agent tool, wired to hybrid RAG
- REST chat API + WebSocket streaming chat
- Hybrid BM25 + vector retriever with RRF fusion

### Verified Endpoints
```
POST /auth/register  → 201 Created
POST /auth/login     → 200 { access_token, refresh_token }
POST /chat/sessions  → 201 { id, title, persona }
POST /chat/sessions/{id}/messages → LLM responds as family_assistant persona
  - With documents ingested: agent calls search_library, RAG retrieves chunks,
    LLM synthesizes answer with source attribution ✅
POST /library/ingest → 201 { id, filename, chunks, status: ready }
GET  /library/query  → semantic search results ✅
```

### Sprint 1.1 — Project Bootstrap ✅
### Sprint 1.2 — Auth System ✅
### Sprint 1.3 — LlamaIndex RAG Service ✅
### Sprint 1.4 — Agent Core ✅

---

## Phase 2: MCP Tools + Multi-User Polish ✅ COMPLETE
**Completed**: March 2026
**Actual Duration**: ~1 week
**Goal**: All v3 service capabilities restored as MCP tools. Multi-user context fully working.
**Success Metric**: Different family members get appropriately scoped responses; calendar/web/RSS tools work.

### What Was Built
- MCP client/registry infrastructure — auto-discovery from `config/mcp_config.yaml`; two transport types: `internal_python` (in-process Python modules) and `docker_stdio` (subprocess JSON-RPC)
- Three internal MCP servers: `calendar` (list/create/search events, Google + Apple CalDAV), `web_research` (DuckDuckGo HTML search, page fetch), `rss` (feed items, multi-feed keyword search)
- Two Docker MCP servers confirmed connected: `mcp/mcp-python-refactoring` (9 tools), `mcp/sequentialthinking` (1 tool)
- Persona system: config-driven via `config/personas.yaml`; `blocked_tools` applied at schema level before LLM sees tool list; `/persona <name>` mid-session switching persisted to DB
- User management API: `GET/POST /admin/users`, `PATCH /admin/users/{id}` with persona validation
- Audit logging: every agent tool call fire-and-forget logged to `audit_logs` table with user/session/tool/args/result
- Real health check: `GET /admin/health` checks PostgreSQL, Ollama/LLM, embedding model, and MCP registry
- `GET /chat/personas` endpoint for frontend persona switcher

### Verified Working
```
GET  /admin/health        → {status: ok, database: ok, llm: ok, embedding_model: ready, mcp: 12 tools}
GET  /admin/tools         → lists all enabled MCP tools with server/transport info
GET  /admin/users         → all users with roles and personas
POST /admin/users         → creates user, validates persona against personas.yaml
PATCH /admin/users/{id}   → updates role/persona/scopes, validates persona
GET  /admin/audit         → audit log with ?tool= and ?user_id= filters
GET  /chat/personas       → {family_assistant: {...}, kids_assistant: {...}, work_assistant: {...}}
POST /chat/sessions/{id}/messages with "/persona work_assistant"
  → switches session persona, persists to DB, returns confirmation ✅
kids_assistant context    → web_search/fetch_page/get_feed_items/search_feeds absent from tool schema ✅
web_search("Python FastAPI") → live DuckDuckGo results, titles + URLs + snippets ✅
Docker MCP servers        → python_refactoring (9 tools) + sequentialthinking (1 tool) ✅
```

### Sprint 2.1 — MCP Infrastructure ✅
### Sprint 2.2 — Calendar, Web Research, RSS Tools ✅
### Sprint 2.3 — Persona System ✅
### Sprint 2.4 — Multi-User Polish ✅

---

### Pre-Sprint: Tech Debt Cleanup
**Before starting Sprint 2.1, clear the Phase 1 tech debt. These are small fixes — budget half a day.**

- [x] **`send_message` missing `db.commit()`** — Added explicit `await db.commit()` after storing assistant reply in REST handler. WebSocket handler already had it. ✅

- [x] **`scope` Form field annotation** — Added `Form(...)` annotation and updated import in `POST /library/ingest`. Without it, `scope` always defaulted to `"personal"` regardless of client input. ✅

- [x] **Package conflict** — `llama-index-llms-openai` omitted entirely (we use `Settings.llm = None`). Comment added to `requirements.txt` explaining why. Pinning to `==0.4.1` would cause a hard conflict with `litellm>=1.82.0`. ✅

---

### Sprint 2.1 — MCP Infrastructure (Days 1-3) ✅

**Files built**:
- `app/mcp/client.py` — SSE + stdio transports, sequential request IDs, structlog, graceful disconnect
- `app/mcp/registry.py` — YAML-driven auto-discovery; `internal_python` (direct module import) and `docker_stdio` (subprocess JSON-RPC) support; MCP → LiteLLM schema conversion; singleton
- `config/mcp_config.yaml` — defines all 6 servers (3 internal, 3 docker)
- `app/agent/tools.py` — `get_tools_for_user()` merges built-in + MCP tools, filters `blocked_tools`
- `app/api/admin.py` — `GET /admin/tools` added (admin-only)
- `app/main.py` — MCP registry `startup()` / `shutdown()` wired into FastAPI lifespan

**Acceptance Criteria**: ✅ `GET /admin/tools` lists all enabled tools; config-only to add new server; Docker MCP servers launch on demand.

---

### Sprint 2.2 — Calendar, Web Research, RSS Tools (Days 4-8) ✅

**Files built**:
- `app/mcp/servers/calendar.py` — `list_events`, `create_event`, `search_events`; `_GoogleProvider` (google-api-python-client) + `_AppleProvider` (caldav/icalendar); lazy imports, graceful "not configured" fallback; settings wired into `app/config.py`
- `app/mcp/servers/web_research.py` — `web_search` (DuckDuckGo HTML scraping, no API key), `fetch_page` (httpx + BeautifulSoup, 8k char truncation); regex fallback if BS4 absent; non-HTTP schemes rejected
- `app/mcp/servers/rss.py` — `get_feed_items`, `search_feeds` (concurrent `asyncio.gather`); feedparser runs in executor (sync lib); BeautifulSoup summary stripping with regex fallback
- `requirements.txt` — added `beautifulsoup4>=4.12.0`, `feedparser>=6.0.0`; calendar optional deps noted

**Verified**: `web_search("Python FastAPI")` → live DuckDuckGo results ✅; all 3 modules import cleanly, tools listed correctly ✅

**Acceptance Criteria**: ✅ agent can call web/RSS tools; child persona tools blocked by schema (not just prompt)

---

### Sprint 2.3 — Persona System (Days 9-11) ✅

**Files built/updated**:
- `config/personas.yaml` — three personas: `family_assistant`, `kids_assistant` (content_filter: strict), `work_assistant`; each defines `blocked_tools` by exact function name, `calendar_access`, `library_scopes`, `tone`
- `config/users.yaml` — four seed users (admin, parent, kid, guest) with `calendar_access` fields
- `app/agent/persona_loader.py` — new; loads/caches personas.yaml; `get_persona()`, `list_personas()`, `persona_exists()`
- `app/agent/context.py` — `from_user()` now loads `blocked_tools`/`tone`/`description`/`content_filter` from persona yaml; `persona_name` override param for mid-session switches; richer `to_system_prompt()` with content filter block
- `app/api/chat.py` — `/persona <name>` command detection (REST + WebSocket); `session.persona` persisted to DB on switch; `UserContext` built from `session.persona` (not user default) on each message; `GET /chat/personas` endpoint

**Key design note**: `blocked_tools` are enforced at the LiteLLM schema level — the LLM never sees blocked tool definitions, not just a prompt instruction.

**Acceptance Criteria**: ✅ child user's tool schema has no web/RSS tools; `/persona work_assistant` persists to session; blocked tools absent from schema

---

### Sprint 2.4 — Multi-User Polish (Days 12-14) ✅

**Files built/updated**:
- `app/api/admin.py` — full replacement: `GET /admin/health` (real liveness checks), `GET /admin/users`, `POST /admin/users` (with persona validation), `PATCH /admin/users/{id}`, `GET /admin/audit` (`?tool=`, `?user_id=`, `?limit=` filters)
- `app/agent/context.py` — added `session_id: Optional[int]` field
- `app/agent/tools.py` — `dispatch_tool_calls()` fires `asyncio.create_task(_write_audit_log(...))` after each tool call; audit write never blocks the agent loop; uses its own short-lived `AsyncSessionLocal` session
- `app/api/chat.py` — sets `user_context.session_id = session_id` in REST and WebSocket handlers

**Document scoping** (was already in place from Phase 1):
- `personal` → filtered by `user_id == current_user_id` in RAG MetadataFilter
- `family` / `shared` → filtered by `scope` value — visible to all authenticated users
- RAG `accessible_scopes` already handles OR logic correctly

**`GET /admin/health` checks**:
- PostgreSQL: `SELECT 1`
- LLM/Ollama: HTTP GET to `{local_api_base}/api/tags` (5s timeout) — ⚠️ fixed in Sprint 3.7; was `/` which silently succeeds on macOS when Ollama is down
- Embedding model: `rag_service.health()` → status + retriever type
- MCP registry: tool count

**Acceptance Criteria**: ✅ admin sees all users and audit log; shared documents returned for all users; health endpoint reports real status

---

## Phase 3: Native Swift Client + Production Ready
**Duration**: 3 weeks
**Goal**: Native iOS/macOS Swift app consuming the v5 backend. On-device fallback via FoundationModels. System stable enough for daily family use.
**Success Metric**: Family members use the app daily from iPhone/Mac without needing the web interface.

**Xcode project**: `/Users/jwomble/Development/FruitcakeAi/FruitcakeAi/`
**Deployment targets**: iOS 26.2+, macOS 15.6+
**Current state**: Xcode template only — no application code written yet.

> **Why native Swift instead of React?**
> The native client spec (`FruitcakeAI_v5_Native_Client.md`) replaces the React frontend entirely. Reasons: native performance, Keychain JWT storage, EventKit calendar integration without OAuth, FoundationModels on-device fallback when backend is unreachable, and future Siri/Shortcuts/WidgetKit integration. The React frontend is dropped.

---

### Pre-Sprint: Backend API Gaps ✅ COMPLETE

All three gaps confirmed resolved before Sprint 3.1 began.

- [x] **`GET /library/documents`** — ✅ Already implemented in `app/api/library.py` (lines 129-163). Returns `[{id, filename, scope, created_at, processing_status}]` filtered by `current_user.id`.

- [x] **`DELETE /library/documents/{id}`** — ✅ Already implemented in `app/api/library.py` (lines 166-200). Calls `rag_service.delete_document()` then removes DB record.

- [x] **WebSocket auth via HTTP headers** — ✅ Implemented. `chat_websocket()` now checks `Authorization: Bearer <token>` HTTP upgrade header first (Auth path 1 — Swift `URLSessionWebSocketTask`), falls back to first-message-body token for backward compatibility with web clients (Auth path 2).

---

### Sprint 3.1 — Networking & Auth Foundation ✅ COMPLETE

Build the services layer first — everything else depends on it.

**Python backend location**: `/Users/jwomble/Development/fruitcake_v5/`
**Swift project location**: `/Users/jwomble/Development/FruitcakeAi/FruitcakeAi/`

**What Was Built**:
- [x] `Utilities/KeychainHelper.swift` — `save/read/delete(forKey:)` using `kSecClassGenericPassword`; service ID `com.fruitcakeai.app`; convenience `Keys` enum for `access_token`, `refresh_token`, `server_url`
- [x] `Services/AuthManager.swift` — `@Observable`; `login(username:password:serverURL:)` → POST /auth/login → Keychain + `GET /auth/me`; `token()` throws if no Keychain entry; `logout()` clears Keychain; `restoreSession()` called on launch
- [x] `Services/APIClient.swift` — `actor`; generic `request<T: Decodable>(_:method:body:)` with snake_case → camelCase decoding; `requestVoid` for DELETE; `upload` for multipart; typed `APIError` enum
- [x] `Services/ConnectivityMonitor.swift` — `@Observable`; polls `GET /admin/health` every 30s via `Task` loop; `checkNow()` for immediate re-check; `isBackendReachable: Bool`, `lastChecked: Date?`
- [x] `Models/ServerConfig.swift` — `@Model`; `serverURL: String`, `isDefault: Bool`, computed `url: URL?`
- [x] `Models/UserProfile.swift` — `Codable` struct; snake_case decoding; `isAdmin`/`isParent` computed helpers
- [x] `Item.swift` cleared to placeholder; `FruitcakeAiApp.swift` updated to `Schema([ServerConfig.self])`; `ContentView.swift` rewritten as auth router with working login form + connectivity status display

**Acceptance Criteria**: ✅ `AuthManager.login()` hits `POST /auth/login`, stores tokens in Keychain; `APIClient` sends authenticated requests; `ConnectivityMonitor` polls backend and publishes reachability.

---

### Sprint 3.2 — Chat UI ✅ COMPLETE

Core user experience. Must feel native and responsive.

**What Was Built**:
- [x] `Models/CachedMessage.swift` — SwiftData `@Model`; `id: UUID`, `serverMessageId: Int?`, `role`, `content`, `timestamp`, `toolCalls: [String]?`, `isLocal: Bool`; inverse relationship to `CachedConversation`
- [x] `Models/CachedConversation.swift` — SwiftData `@Model`; `serverSessionId: Int?`, `title`, `persona`, `lastActivity`, `isLocal`; cascade-delete messages; `sortedMessages` helper
- [x] `Services/WebSocketManager.swift` — `@Observable`; `URLSessionWebSocketTask` with `Authorization: Bearer` header; `AsyncStream<WSEvent>` (token/done/personaSwitched/error); `makeWSURL()` converts http→ws scheme; `receiveLoop()` async task; clean `disconnect()`
- [x] `Views/Chat/ChatView.swift` — `NavigationSplitView` sidebar (session list) + detail (message thread); `POST /chat/sessions` create; `GET /chat/sessions/{id}` history load; WebSocket streaming with token-by-token display; REST fallback when WebSocket unavailable; persona-switched event updates sidebar label; optimistic user message; SwiftData caching
- [x] `Views/Chat/MessageBubble.swift` — user/assistant bubbles; `AttributedString` Markdown rendering; `UnevenRoundedRectangle` tail corners; timestamp; local-mode iphone icon
- [x] `Views/Chat/ToolCallIndicator.swift` — animated `ProgressView` + label; shown from message send until first token chunk arrives
- [x] `Views/Components/ConnectionStatus.swift` — orange offline banner; `.transition(.move(edge: .top).combined(with: .opacity))`; renders nothing when connected
- [x] `ContentView.swift` — routes to `ChatView` (authenticated) or `LoginView` (unauthenticated); `LoginView` is a full polished login form with `symbolEffect` bounce
- [x] `FruitcakeAiApp.swift` schema updated: `[ServerConfig.self, CachedConversation.self, CachedMessage.self]`
- [x] Persona switching: `/persona <name>` message → `WSEvent.personaSwitched` → sidebar label + SwiftData updated

**Acceptance Criteria**: ✅ Chat sends messages and streams responses token-by-token; tool call indicator shown before first token; persona updated in session header; ConnectionStatus banner driven by ConnectivityMonitor.

---

### Sprint 3.3 — Library & Settings ✅ COMPLETE

**What Was Built**:
- [x] `Views/Library/LibraryView.swift` — document list (`GET /library/documents`); scope badge (personal/family color-coded); pull-to-refresh; swipe-to-delete → `DELETE /library/documents/{id}` with per-item error toast; `ContentUnavailableView` for empty/error states; upload sheet
- [x] `Views/Library/DocumentUpload.swift` — `.fileImporter` (iOS + macOS cross-platform); personal/family scope `Picker`; security-scoped resource access; `APIClient.upload()` multipart; progress indicator; `mimeType()` helper for pdf/txt/md/docx
- [x] `Views/Settings/SettingsView.swift` — server URL `TextField` → saved to Keychain + `ServerConfig` SwiftData; `LabeledContent` user info (username/email/role/persona); backend status row with relative timestamp + "Check" button; persona picker sheet; sign-out
- [x] `Views/Settings/PersonaPicker.swift` — `GET /chat/personas`; persona rows with description, tone badge, kids-safe badge, restricted-tools badge; selected persona saved to `UserDefaults preferred_persona`; "Done" dismiss button
- [x] `ContentView.swift` — `MainTabView` with `TabView` (Chat · Library · Settings tabs); `LoginView` extracted at top level; two `#Preview` macros (logged-out, main-tabs)

**Acceptance Criteria**: ✅ Documents list and delete; file upload with scope selector; server URL configurable without reinstall; persona picker populated from backend with descriptions and badges.

---

### Sprint 3.4 — On-Device Fallback ✅ COMPLETE

When the backend is unreachable, the app falls back to Apple's FoundationModels framework.

**What Was Built**:
- [x] `Services/OnDeviceAgent.swift` — `@Observable`; `LanguageModelSession(model: SystemLanguageModel.default, tools: [...])` initialized lazily; `checkAvailability()` maps all `UnavailableReason` cases to user-readable strings; `stream(_:)` returns `AsyncStream<String>` with token chunks — same interface as WebSocket tokens, so ChatView needs no special-casing; `resetSession()` for conversation changes
- [x] `Tools/CalendarTool.swift` — `Tool` protocol; `@Generable Arguments` with `daysAhead` + optional `keyword` filter; `requestFullAccessToEvents()`; sorted + filtered events; formats title/date/location/calendar
- [x] `Tools/ReminderTool.swift` — `Tool` protocol; `action: "list"|"create"`; `fetchReminders` via `withCheckedThrowingContinuation`; `createReminder` with `NSDataDetector` + common-phrase natural date parsing; `EKAlarm` for due-date reminders
- [x] `Tools/ContactsTool.swift` — `Tool` protocol; `CNContactStore.requestAccess`; `predicateForContacts(matchingName:)`; returns formatted name + phone + email block
- [x] `ChatView` wired: `@Environment(OnDeviceAgent.self)`; `sendMessage()` checks `connectivity.isBackendReachable` first — if false, calls `sendViaOnDevice()` which streams `onDeviceAgent.stream(text)` into the same `streamingContent` buffer, then stores `CachedMessage(isLocal: true)`
- [x] `FruitcakeAiApp.swift`: `@State private var onDeviceAgent = OnDeviceAgent()` injected into environment; `onDeviceAgent.checkAvailability()` called on launch
- [ ] **Remaining**: Add `NSCalendarsFullAccessUsageDescription`, `NSContactsUsageDescription`, `NSRemindersFullAccessUsageDescription` to `Info.plist` (Xcode → Target → Info tab)

**Fallback capabilities**: local calendar query, reminders read/create, contacts lookup — no RAG, no web search, no RSS
**Acceptance Criteria**: ✅ Backend offline → `sendViaOnDevice()` routes to FoundationModels; `CachedMessage.isLocal = true`; `ConnectionStatus` banner reflects mode accurately.

---

### Sprint 3.5 — Backend Stability & Production Scripts (Days 13-14) ✅ COMPLETE

**Tasks**:
- [x] `GET /admin/metrics` — `app/metrics.py` singleton; counters: total_requests, total_tool_calls, error_count, active_ws_sessions; wired into middleware + agent + WebSocket
- [x] `trace_id` middleware — UUID injected per request, bound to structlog contextvars, returned as `X-Trace-ID` response header and in all error JSON bodies
- [x] `scripts/start.sh` — now runs `python scripts/seed.py` after Alembic migrations
- [x] `scripts/reset.sh` — now runs `python scripts/seed.py` after reset migrations
- [x] User-friendly error responses — `app/main.py` exception handlers; 500s return `{"error": "...", "trace_id": "..."}`; no Python tracebacks exposed; WebSocket handler fixed too

**Acceptance Criteria**: ✅ `./scripts/start.sh` brings up full system from cold start; `GET /admin/metrics` returns counters; all 500 errors return clean JSON with trace ID.

---

### Sprint 3.6 — Testing & Documentation (Days 15-18) ✅ COMPLETE

**Python backend tests** (`/Users/jwomble/Development/fruitcake_v5/tests/`) — 48 tests, 0 failures:
- [x] `tests/test_agent.py` — tool schema format validation; blocked tools absent from kids_assistant schema; dispatch returns correct role messages; unknown tool handled gracefully
- [x] `tests/test_rag.py` — RAGService returns [] when not initialized; health() reports correct status; build_hybrid_retriever falls back to vector-only when BM25 unavailable; query() formats results correctly
- [x] `tests/test_auth.py` — login, token validation, role enforcement (admin endpoint rejects non-admin), session CRUD (create/list/delete), cross-user session isolation
- [x] `tests/test_mcp.py` — registry loads from config; tool schemas valid LiteLLM format; internal module dispatch; unknown tool returns error string; disabled servers skipped
- [x] `tests/conftest.py` — shared SQLite in-memory DB fixtures; no PostgreSQL required to run tests

**Swift client tests** — deferred to Phase 4 (XCTest targets require device/simulator; covered by manual testing in Phase 3):
- [ ] `AuthManagerTests` — login stores token in Keychain; expired token triggers refresh; logout clears Keychain
- [ ] `APIClientTests` — requests include Authorization header; 401 triggers re-auth flow; network errors surface as typed Swift errors
- [ ] `ConnectivityMonitorTests` — unreachable backend flips `isBackendReachable` to false

**Documentation** (`/Users/jwomble/Development/fruitcake_v5/`):
- [x] `README.md` — quick start: backend setup + Xcode build + first chat in under 30 minutes
- [x] `docs/ADDING_MCP_TOOLS.md` — config-only guide, no code changes needed
- [x] `docs/PERSONA_SYSTEM.md` — persona config, blocked tools, persona switching
- [x] `docs/LLM_BACKENDS.md` — switching between Ollama, Claude, OpenAI via `.env`

**Also completed during Sprint 3.6**:
- [x] Fixed `DELETE /chat/sessions/{id}` — `audit_logs_session_id_fkey` FK constraint changed from `NO ACTION` to `ON DELETE SET NULL`; deletes now return 204 instead of 500

**Acceptance Criteria**: ✅ `pytest tests/` passes (48/48); README covers end-to-end setup; docs cover all three configuration surfaces.

---

### Sprint 3.7 — Library Management GUI & Production Fixes ✅ COMPLETE

Post-Sprint-3.6 improvements driven by real daily use: richer library UX in the Swift client and three backend correctness fixes uncovered in production.

#### Backend

**`app/api/library.py` — `PATCH /library/documents/{id}`**
New endpoint for post-upload scope changes. Owner-only; scope validated against `_ALLOWED_SCOPES`. Returns `{"id": ..., "scope": ...}`.

```python
class UpdateDocumentRequest(BaseModel):
    scope: str

@router.patch("/documents/{doc_id}", status_code=200)
async def update_document(doc_id: int, body: UpdateDocumentRequest, ...)
```

**`app/agent/tools.py` — `summarize_document` hallucination fix**
When `summarize_document` couldn't match a filename, it returned a generic "check the filename" string. The LLM responded by fabricating a plausible-looking document list. Fix: query the DB for actual filenames and return them with an explicit retry instruction. The LLM now self-corrects on the next tool call.

```python
# When doc not found — return real library contents, not a vague error
if not doc:
    filenames = [r[0] for r in all_docs ...]
    return f"No document found matching '{doc_name}'. The documents actually in this user's library are:\n{doc_list}\nCall summarize_document again with the exact filename from this list."
```

**`app/api/admin.py` — `/admin/health` LLM false-positive fix**
`GET /admin/health` was hitting `{local_api_base}/` to check Ollama. On macOS, port 11434 accepts the TCP connection even when `ollama serve` is not running, so the check always returned `"llm: ok"`. Changed to `GET /api/tags` — an actual Ollama endpoint that requires a live server. This prevented silent failures where all chat requests were returning 500 while health showed green.

**`scripts/start.sh` — Ollama auto-start**
`start.sh` previously only warned if Ollama wasn't running. Now it starts Ollama in the background (`ollama serve &>/tmp/ollama.log &`) and polls for readiness for up to 30 seconds before proceeding to Alembic and uvicorn. Eliminates the most common cold-start failure.

---

#### Swift Client (`FruitcakeAi/Views/Library/`)

**`LibraryView.swift` — complete rewrite**

| Feature | Implementation |
|---------|----------------|
| Local filename filter | `.searchable(text: $searchText, prompt: "Filter documents")` + `filteredDocuments` computed property; `ForEach(filteredDocuments)` replaces `ForEach(documents)` |
| Semantic search | New `SemanticSearchSheet` private struct; toolbar `sparkle.magnifyingglass` button; hits `GET /library/query?q=...&top_k=10`; shows text chunks with filename + relevance score |
| Scope editing | `.contextMenu` on each document row → "Change Scope" submenu (Personal / Family / Shared); optimistic UI update with revert on PATCH failure |
| Status polling | `pollingTask: Task<Void, Never>?` checks every 5s for `processingStatus == "processing"` documents; auto-cancels when none remain; fetch runs directly (not via `loadDocuments()` to avoid recursion) |
| "Shared" teal badge | `scopeColor` switch adds `.teal` for shared scope; `DocumentSummary.scope` changed from `let` to `var` to allow in-place mutation |

Key detail: `updateScope()` mutates `documents[idx].scope` before the PATCH returns (optimistic), then reverts if the call throws. `deleteDocuments(at:)` maps `IndexSet` offsets to `filteredDocuments`, not `documents`, so swipe-to-delete is correct when a search filter is active.

**`DocumentUpload.swift` — Shared scope option**
Added `Label("Shared", systemImage: "globe").tag("shared")` to the scope `Picker`. Footer text updated to cover all three scopes. Backend already accepted "shared" — this was a UI-only gap.

---

**Acceptance Criteria**: ✅ Local filter and semantic search work independently; scope changes persist after reload; "Shared" available at upload time; status polling auto-refreshes without user action; `/admin/health` correctly detects Ollama down; `start.sh` cold-starts the full stack including Ollama without manual intervention.

---

## Future Phases

Good ideas that belong *after* daily use is proven. Add them in response to real friction, not speculation.

| Phase | Feature | Trigger to Start |
|-------|---------|-----------------|
| 4 | Redis caching (embeddings + sessions) | Noticeable latency in daily use |
| 4 | HNSW vector indexing | Library exceeds ~10k documents |
| 4 | Background ingestion queue | Large file uploads blocking chat |
| 4 | App Intents / Siri integration | "Hey Siri, ask Fruitcake..." requested by family |
| 4 | WidgetKit home screen widget | At-a-glance family info wanted on home screen |
| 5 | Background sync when back online | Offline conversations should sync to server |
| 5 | Push notifications for reminders | Reminders created via chat should surface as alerts |
| 5 | Multimodal (image/audio ingestion) | Specific use case identified |
| 6 | Email integration MCP | Actively requested |
| 7 | Enterprise fork | Home version proven, business interest confirmed |

---

## LLM Backend Configuration

Switch backends via `.env` — no code changes required.

```env
# ✅ DEFAULT — Local via Ollama (privacy-first, verified working on M1 Max 64GB)
LLM_MODEL=ollama_chat/qwen2.5:14b
LOCAL_API_BASE=http://localhost:11434/v1

# Middle ground — more capable, still fits in RAM
# LLM_MODEL=ollama_chat/qwen2.5:32b

# Cloud — best quality, requires API key
# LLM_MODEL=claude-sonnet-4-5
# ANTHROPIC_API_KEY=sk-ant-...

# OpenAI
# LLM_MODEL=gpt-4o
# OPENAI_API_KEY=sk-...

# Embeddings — shared across all LLM backends
EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
```

> ⚠️ **M1 Max 64GB note**: `llama3.3:70b` (~43GB) crashes Ollama at runtime due to memory pressure when running alongside the embedding model and macOS. `qwen2.5:14b` is the verified default. `qwen2.5:32b` is a reasonable step up if you close other applications first.

---

## Key Design Decisions

**Why `ollama_chat/` prefix?**  
The `ollama/` prefix routes to `/api/generate` (completion API) which does not support tool/function calling. The `ollama_chat/` prefix routes to `/api/chat` which does. Tool calling is central to the agent loop — using the wrong prefix means tools are silently ignored.

**Why LiteLLM instead of direct SDK calls?**  
Single interface for all LLM backends. Swap from local Qwen to Claude to GPT-4 via one env var. No code changes, no vendor lock-in. The `_litellm_kwargs()` helper handles backend-specific quirks (like the Ollama `api_base` requirement) in one place.

**Why MCP instead of the v4 service registry?**  
MCP is the emerging standard. New tools added via config, not code. Works with Cursor, Claude Desktop, and any MCP-compatible client — tooling investment compounds over time.

**Why is multi-user implemented as context injection?**  
Simpler to reason about, simpler to test, simpler to debug. You can read exactly what the LLM is being told. The v4 approach wove permissions through every layer, making it hard to trace why something was or wasn't accessible. Prompt-based scoping is also easy to audit — you can log the full system prompt per session if needed.

**Why no ServiceOrchestrator?**  
The LLM is the orchestrator. This is what GPT-4 function calling, Claude tool use, and every major agent framework has converged on. Hand-written routing rules are brittle and require constant maintenance as capabilities grow. The LLM routes to the right tool based on semantic understanding of the query.

---

## Migration Reference from v4

| v5 Component | Port From (v4) |
|-------------|----------------|
| `app/rag/retriever.py` | `app/services/library_manager/service.py` + `config/library_manager.yaml` |
| `app/mcp/client.py` | `app/services/mcp_client/python_refactoring_service.py` |
| `app/mcp/servers/calendar.py` | `app/services/calendar/service.py` + `providers.py` |
| `app/mcp/servers/web_research.py` | `app/services/web_research/service.py` |
| `app/mcp/servers/rss.py` | `app/services/rss/service.py` |
| `app/auth/` | `app/auth/` (mostly unchanged) |
| `app/db/models.py` | `app/db/models.py` (add `persona`, `scope` fields) |
| Swift client (Phase 3) | New — replaces React frontend; see `FruitcakeAI_v5_Native_Client.md` |

---

## Cursor Usage Notes

- **Start each sprint** by reading the sprint section and identifying files to create vs. port
- **Use `@codebase`** to reference v4 source files when porting service logic
- **Pre-sprint tech debt** (top of Phase 2) — do this first, it's small and clears the way
- **MCP client**: the Docker stdio transport in v4 is production-proven — port it directly
- **Agent loop**: `app/agent/core.py` is the most sensitive file. Any changes should preserve the `_normalize_tool_calls()` and `message.tool_calls` check patterns — these fix real Ollama bugs
- **One sprint at a time**: resist building Phase 3 features during Phase 2
- **Test with documents**: the RAG path only activates after ingesting at least one document; always have a test PDF ready during agent development

---

*FruitcakeAI v5 — Simpler. Smarter. Still private.* 🍰
*Phase 1 complete March 2026 · Phase 2 complete March 2026 · Phase 3 complete March 2026 · Sprint 3.7 complete March 2026*
