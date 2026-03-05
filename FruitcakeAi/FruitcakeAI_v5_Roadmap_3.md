# 🍰 FruitcakeAI v5 — Rebuild Roadmap

**Version**: 5.4  
**Status**: Phase 1 ✅ · Phase 2 ✅ · Phase 3 ✅ · Sprint 3.7 ✅ · **Phase 4 Next**  
**Philosophy**: Agent-first. Air-gapped by default. Autonomous by design.  
**Build Location**: `/Users/jwomble/Development/fruitcake_v5/`  
**Last Updated**: March 2026

---

## Executive Summary

FruitcakeAI v5 is a clean rebuild that preserves the best ideas from v3/v4 — hybrid RAG retrieval, multi-user/persona support, MCP tool integration — while discarding the complexity that made v3/v4 cumbersome: the ServiceOrchestrator, PolicyRouter, intent detection keyword system, and enterprise-scale infrastructure aspirations.

The core mental model evolution:

> **v3/v4**: A platform that contains an AI  
> **v5**: An AI agent that has tools  
> **v5 Phase 4+**: An AI agent that acts without being prompted

**Where we stand vs. OpenClaw:**

| Capability | OpenClaw | FruitcakeAI | Status |
|-----------|----------|-------------|--------|
| Hybrid RAG (BM25+vector+RRF) | ❌ SQLite-vec only | ✅ pgvector+RRF | Done |
| Document library + scoping | ❌ Flat Markdown | ✅ Full ingest pipeline | Done |
| Multi-user safety + roles | ❌ Single-user | ✅ Role-based, persona-scoped | Done |
| Kids content safety | ❌ | ✅ Schema-enforced blocked tools | Done |
| Native mobile client | ❌ Telegram dependency | ✅ Swift/APNs | Done |
| Library management GUI | ❌ | ✅ Sprint 3.7 | Done |
| **Heartbeat / proactive wakeup** | ✅ | ❌ | **Phase 4** |
| **Cron scheduled tasks** | ✅ | ❌ | **Phase 4** |
| **Push notifications** | ✅ Telegram | ❌ | **Phase 4** |
| **Approval workflow** | ⚠️ Advisory only | ❌ | **Phase 4** |
| **Configurable judgment routing** | ❌ | ❌ | **Phase 4** |
| Inbound webhooks | ✅ | ❌ | Phase 5 |
| Gmail Pub/Sub | ✅ | ❌ | Phase 5 |
| Sandboxed filesystem MCP | ✅ (host shell, risky) | ⚠️ disabled | Phase 6 |
| Sub-agent spawning | ✅ | ❌ | Phase 6 |
| Enterprise fork | ❌ | ❌ | Phase 7 |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              Swift Client                   │
│   Chat · Library · Inbox (Phase 4) · Settings│
└─────────────────────┬───────────────────────┘
                      │ WebSocket / REST / APNs
┌─────────────────────▼───────────────────────┐
│           FastAPI — Thin Layer              │
│   Auth (JWT) · File Upload · Chat API       │
│   User/Session · Task API (Phase 4)         │
│   Webhook API (Phase 5)                     │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│              Agent Core                     │
│   LiteLLM (model-agnostic)                  │
│   System prompt = user context + persona    │
│   Tool-calling drives all orchestration     │
│   Mode-aware turn limits: chat=8 hb=4 task=32│
└──────┬───────────┬───────────┬──────────────┘
       │           │           │
┌──────▼───┐ ┌─────▼────┐ ┌───▼─────────────┐
│   RAG    │ │Calendar  │ │  Web / RSS / etc │
│LlamaIndex│ │  MCP     │ │   MCP Servers    │
│pgvector  │ │          │ │ (Docker, stdio)  │
└──────┬───┘ └──────────┘ └─────────────────┘
       │
┌──────▼────────────────────────────────────┐
│   PostgreSQL + pgvector                   │
│   APScheduler (in-process, Phase 4)       │
└───────────────────────────────────────────┘
```

---

## ⚠️ Ground Truth: Verified Working Configuration

### Hardware
- **Machine**: M1 Max, 64GB RAM (macOS)
- **Verified LLM**: `qwen2.5:14b` via Ollama ✅
- **`llama3.3:70b`** (~43GB): crashes Ollama — memory pressure with embedding model + macOS overhead
- **`qwen2.5:32b`** (~20GB): viable step-up if other apps closed first

### LiteLLM / Ollama Critical Patterns

**Use `ollama_chat/` prefix, not `ollama/`**
```env
LLM_MODEL=ollama_chat/qwen2.5:14b   # ✅ /api/chat — tool calling works
# LLM_MODEL=ollama/qwen2.5:14b     # ❌ /api/generate — tool calls silently broken
```

**Always pass `api_base` explicitly**
```python
def _litellm_kwargs(self) -> dict:
    base = settings.local_api_base.rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3]
    return {"api_base": base, "model": settings.llm_model}
```

**Check `message.tool_calls`, not `finish_reason`**
```python
while message.tool_calls:   # ✅ correct — Ollama returns stop even with tool calls
    ...
```

**`_normalize_tool_calls()` is required** — Ollama returns inconsistent tool call formats across model versions. Always normalize before dispatch.

---

## Project Structure

```
fruitcake_v5/
├── app/
│   ├── main.py
│   ├── config.py
│   ├── auth/
│   ├── agent/
│   │   ├── core.py                  # Agent loop — mode-aware turn limits
│   │   ├── context.py
│   │   ├── tools.py
│   │   └── prompts.py
│   ├── autonomy/                    # Phase 4 — new top-level module
│   │   ├── heartbeat.py             # Heartbeat runner
│   │   ├── scheduler.py             # APScheduler (in-process, persists to PG)
│   │   ├── push.py                  # APNs delivery via httpx HTTP/2
│   │   ├── judgment.py              # Routes local vs cloud per autonomy.yaml
│   │   └── sanitizer.py             # Context abstraction before any cloud send
│   ├── rag/
│   ├── mcp/
│   ├── api/
│   │   ├── chat.py
│   │   ├── library.py
│   │   ├── tasks.py                 # Phase 4 — task CRUD + approval workflow
│   │   ├── devices.py               # Phase 4 — APNs token registration
│   │   ├── webhooks.py              # Phase 5
│   │   └── admin.py
│   └── db/
│       ├── models.py                # + Task, DeviceToken (Ph4), WebhookConfig (Ph5)
│       ├── session.py
│       └── migrations/
├── config/
│   ├── mcp_config.yaml
│   ├── personas.yaml
│   ├── users.yaml
│   ├── heartbeat.yaml               # Phase 4 — checklist items
│   └── autonomy.yaml                # Phase 4 — judgment routing config
├── tests/
├── scripts/
│   ├── start.sh                     # One-command startup (Ollama auto-start)
│   └── reset.sh
├── docker-compose.yml
├── .env / .env.example
└── README.md
```

---

## Completed Work

### Phase 1 ✅ — Agent Core + RAG Foundation
Agent loop, LiteLLM integration, pgvector RAG, hybrid BM25+vector+RRF retrieval, basic auth, PostgreSQL, document ingestion pipeline.

### Phase 2 ✅ — MCP Tools + Multi-User Polish
Calendar MCP, web research MCP, RSS MCP, persona system, library scoping (personal/family/shared), multi-user API, pre-sprint tech debt resolved including `library_scopes` safety fix.

### Phase 3 ✅ — Frontend + Production Stability
Swift client (chat, library, settings), WebSocket dual-auth, FoundationModels on-device fallback, health check fix (`/api/tags` not `/`), one-command startup with Ollama auto-start.

### Sprint 3.7 ✅ — Library Management GUI
Local filename filter, semantic search sheet, scope editing via context menu, status polling, shared scope support, `summarize_document` hallucination fix, `PATCH /library/documents/{id}`, `DELETE /chat/sessions/{id}` FK constraint fix.

---

## Phase 4 — Heartbeat + Autonomous Tasks (~3 weeks)

**Goal**: FruitcakeAI acts without being prompted. Closes the primary gap vs. OpenClaw.

The qualitative shift: from "capable chatbot that waits" to "present assistant that comes to you."

### The Air-Gap Architecture Decision

FruitcakeAI's security model is **air-gapped by default**. All heartbeat judgment, task execution, and autonomous decisions run on-device with a local model. No external API calls in production unless explicitly opted into.

The challenge: 14B local models produce noisier judgment than frontier models — more false positives, less nuanced triage. False positives erode user trust faster than any other failure mode in a background system.

**The solution**: configurable per-signal-type judgment routing. Users choose what leaves the machine based on their own privacy intuitions — not a blanket all-or-nothing choice.

```yaml
# config/autonomy.yaml

judgment:
  default: local                # air-gapped unless explicitly overridden

  routing:
    calendar_conflicts: local
    email_urgency: cloud        # user opts in — better triage, acceptable tradeoff
    task_prioritization: local
    financial_signals: local    # never
    document_content: local     # never
    health_data: local          # never

  cloud:
    provider: anthropic
    model: claude-haiku-4-5     # cheap, fast, sufficient for judgment calls
    max_context_tokens: 500     # hard cap — forces summarization, limits exposure
    audit_log: true             # all cloud calls logged: timestamp + signal type

  local:
    model: ollama_chat/qwen2.5:14b
    fallback_chain:
      - ollama_chat/qwen2.5:14b
      - claude-haiku-4-5        # if Ollama is down
      - claude-sonnet-4-6       # last resort
```

**Why `max_context_tokens: 500` is structural sanitization**: if the local sanitizer cannot compress the signal below 500 tokens, the call stays local. Obfuscation is enforced by the constraint — not a separate policy step that can be missed or forgotten.

**Enterprise fork implication**: lock the entire `routing` block to `local`. One config property = fully air-gapped deployment with a compliance guarantee.

### The Fine-Tune Path (Post-Phase 4, Long-Term)

The cleanest permanent solution:

1. During development, use Claude/GPT-4 to generate thousands of synthetic abstract judgment scenarios + correct responses — "given this signal pattern, should the assistant notify the user?"
2. Fine-tune `qwen2.5:14b` on that dataset
3. Ship `heartbeat_judge.gguf` — permanently air-gapped, near-frontier judgment for the specific task of "should I wake the user about this?"

Cloud trains the local model once. After that, production has no external dependency. Revisit after Phase 4 produces real-world data on exactly where local judgment fails.

---

### Sprint 4.1 — Task Infrastructure (Days 1–4)

**New DB models** (`app/db/models.py`):

```python
class Task(Base):
    __tablename__ = "tasks"
    id: int
    user_id: int
    title: str
    instruction: str
    task_type: str            # "one_shot" | "recurring" | "heartbeat_item"
    status: str               # "pending" | "running" | "completed" |
                              # "failed" | "cancelled" | "waiting_approval"
    cron_expression: str | None
    result: str | None
    requires_approval: bool
    created_at: datetime
    last_run_at: datetime | None
    next_run_at: datetime | None

class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id: int
    user_id: int
    token: str
    environment: str          # "sandbox" | "production"
    created_at: datetime
```

**New API** (`app/api/tasks.py`, `app/api/devices.py`):

```
POST   /tasks                  create task
GET    /tasks                  list user's tasks
GET    /tasks/{id}             task detail + last result
PATCH  /tasks/{id}             update / approve / reject
DELETE /tasks/{id}             cancel
POST   /tasks/{id}/run         manual trigger (dev/testing)

POST   /devices/register       register APNs device token
DELETE /devices/{token}        deregister on logout
```

---

### Sprint 4.2 — Heartbeat System (Days 5–9)

**`app/autonomy/heartbeat.py`**

```python
class HeartbeatRunner:
    async def run(self, user: User) -> HeartbeatResult:
        checklist = load_heartbeat_config()
        context = await build_heartbeat_context(user)   # calendar, tasks, email subjects only
        
        decision = await self.judgment.evaluate(context, checklist)
        
        if decision.result == "HEARTBEAT_OK":
            logger.debug(f"Heartbeat OK for {user.id} — silent")
            return HeartbeatResult(notified=False)
        
        if decision.result.startswith("URGENT:"):
            await self.push.send(user, decision.message, urgency="high")
            return HeartbeatResult(notified=True)
        
        if decision.result.startswith("NEEDS_APPROVAL:"):
            task = await create_approval_task(user, decision)
            await self.push.send(user, f"Needs approval: {decision.summary}")
            return HeartbeatResult(notified=True, approval_task_id=task.id)
```

**`config/heartbeat.yaml`**

```yaml
checklist:
  - id: calendar_conflicts
    description: "Check for scheduling conflicts in the next 24 hours"
    routing: calendar_conflicts
    notify_if: "conflict with less than 2 hours notice"

  - id: pending_approvals
    description: "Check for tasks waiting user approval"
    routing: task_prioritization
    notify_if: "any waiting_approval task older than 1 hour"

  - id: overdue_tasks
    description: "Check for overdue recurring tasks"
    routing: task_prioritization
    notify_if: "recurring task missed its window by 30+ minutes"
```

**`app/autonomy/judgment.py`** — routes per `autonomy.yaml`:

```python
class JudgmentRouter:
    async def evaluate(self, context: HeartbeatContext, signal_type: str) -> Decision:
        routing = self.config.routing.get(signal_type, self.config.default)
        
        if routing == "local":
            return await self._evaluate_local(context)
        
        # Cloud path — sanitize first, enforce hard token cap
        sanitized = self.sanitizer.abstract(context)
        if sanitized.token_count > self.config.cloud.max_context_tokens:
            logger.warning(f"Context too large ({sanitized.token_count} tokens) — falling back to local")
            return await self._evaluate_local(context)
        
        return await self._evaluate_cloud(sanitized)
```

**`app/autonomy/sanitizer.py`** — PII never leaves the machine:

```python
class ContextSanitizer:
    def abstract(self, context: HeartbeatContext) -> AbstractSignal:
        return AbstractSignal(
            signal_type=context.type,
            sender_class=classify_sender(context),       # class, not identity
            subject_signals=extract_signals(context),    # ["deadline", "action_required"]
            urgency_score=score_urgency(context),        # 0.0–1.0
            time_to_deadline=self._bucket_deadline(context),  # range, not exact
            user_load=count_pending_items(context),      # count, not content
            time_context=classify_time(),                # "weekday_afternoon"
        )
    
    def _bucket_deadline(self, context) -> str:
        # Ranges only — never send exact values
        hours = calculate_hours_to_deadline(context)
        if hours < 4:  return "under_4_hours"
        if hours < 24: return "same_day"
        if hours < 72: return "this_week"
        return "later"
```

**`app/autonomy/scheduler.py`** — APScheduler wired into FastAPI lifespan:

```python
scheduler = AsyncIOScheduler(
    jobstores={"default": SQLAlchemyJobStore(url=DATABASE_URL)}
)

async def start_scheduler():
    scheduler.add_job(run_all_heartbeats, "interval", minutes=30, id="heartbeat")
    scheduler.add_job(run_cron_dispatcher, "interval", minutes=1, id="cron_dispatcher")
    scheduler.start()
```

---

### Sprint 4.3 — APNs Push Notifications (Days 10–13)

**`app/autonomy/push.py`** — httpx HTTP/2 to `api.push.apple.com`:

```python
class APNsPusher:
    async def send(self, user: User, message: str, urgency: str = "normal"):
        tokens = await get_device_tokens(user.id)
        for token in tokens:
            await self._deliver(token, message, urgency)
```

**Required `.env` additions**:

```env
APNS_KEY_ID=...
APNS_TEAM_ID=...
APNS_AUTH_KEY_PATH=./certs/AuthKey_XXXXXX.p8
APNS_BUNDLE_ID=com.yourname.fruitcakeai
APNS_ENVIRONMENT=sandbox     # sandbox | production
```

**Swift client — new Inbox tab**:

- Heartbeat results with timestamp + action taken
- Completed task summaries
- `waiting_approval` tasks with Approve / Reject buttons
- `PATCH /tasks/{id}` with `{"approved": true}` resumes paused task
- Separate from Chat tab — autonomous activity lands here, not in conversation history

---

### Sprint 4.4 — Cron Tasks + Approval Workflow (Days 14–21)

**Mode-aware turn limits** (surgical change to `app/agent/core.py`):

```python
TURN_LIMITS = {
    "chat":       8,    # interactive — user present, can course-correct
    "heartbeat":  4,    # quick check — fail fast, don't overthink
    "task":      32,    # autonomous — needs room for multi-step work
}

async def run_agent(session, mode: str = "chat"):
    max_turns = TURN_LIMITS[mode]
    ...
```

**Cron task example**:

```json
POST /tasks
{
  "title": "Morning briefing",
  "instruction": "Check my calendar for today, review any overnight messages, send me a push summary",
  "task_type": "recurring",
  "cron_expression": "0 8 * * 1-5"
}
```

**Irreversible action approval**:

```python
IRREVERSIBLE_TOOLS = {
    "send_email", "create_calendar_event",
    "delete_file", "modify_file"
}

async def dispatch_tool(tool_name: str, args: dict, task: Task):
    if tool_name in IRREVERSIBLE_TOOLS and not task.pre_approved:
        await pause_for_approval(task, tool_name, args)
        raise ApprovalRequired(f"'{tool_name}' requires user approval")
```

Task → `waiting_approval`. Push sent. User approves from Inbox. `PATCH /tasks/{id}` with `approved: true` resumes from paused point.

---

## Phase 5 — Webhooks + External Triggers (1 week)

**Sprint 5.1** — Inbound webhook surface:

```python
class WebhookConfig(Base):
    __tablename__ = "webhook_configs"
    id: int
    user_id: int
    name: str
    webhook_key: str        # random secret — appears in URL
    instruction: str        # what agent does when triggered
    active: bool
```

```
POST   /webhooks/{key}   inbound trigger (GitHub, Zapier, IFTTT, etc.)
GET    /webhooks         list
POST   /webhooks         create
DELETE /webhooks/{id}    remove
```

**Sprint 5.2** — Gmail Pub/Sub (`app/mcp/servers/gmail.py`):

Tools: `read_email`, `send_email`, `search_emails`, `label_email`. Gmail push → Pub/Sub → `/webhooks/{key}` → agent wakes. Email judgment defaults `local` unless user sets `email_urgency: cloud` in `autonomy.yaml`.

---

## Phase 6 — Filesystem + Sub-Agent Spawning (2 weeks)

**Sprint 6.1** — Sandboxed filesystem MCP:

Enable with `--allowed-paths /workspace`. Each user gets isolated `workspace/{user_id}/`. No traversal above that path.

**Sprint 6.2** — Shell MCP (non-negotiable constraints):
- `docker run --network none` — no network access from shell
- 30s timeout
- 8k output cap
- Explicit blocked commands list

**Sprint 6.3** — Sub-agent spawning:

```python
async def spawn_agent(instruction: str, persona: str, timeout_seconds: int = 120):
    """Delegate to a specialist sub-agent. Child cannot escalate parent scopes."""
    child_session = create_child_session(parent=current_session, persona=persona)
    result = await run_agent(child_session, mode="task", max_turns=32)
    audit_log_child(parent=current_session, child=child_session)
    return result
```

Child agents inherit parent scopes and cannot escalate them. All child tool calls appear in the audit log alongside parent calls.

---

## Phase 7 — Enterprise Fork

**Trigger**: Home version in stable daily use + confirmed business interest. Not speculative.

**Delta from home version**:
- SSO/LDAP/SAML auth
- Teams (10–500 users), project/department/client scopes
- ACL-based role matrix
- Compliance export + retention policies
- Docker Compose / K8s deployment manifests
- `autonomy.yaml` routing all `local` = air-gapped deployment guarantee
- HIPAA/SOC 2 path
- `audit_log: true` becomes mandatory

**Why v5 already supports this**: persona=role mapping, library scopes→workspaces, LiteLLM model swap via env var, `autonomy.yaml` all-local = one config change to fully air-gapped compliance-ready deployment.

---

## LLM Backend Configuration

```env
# Default — local, privacy-first, verified M1 Max 64GB
LLM_MODEL=ollama_chat/qwen2.5:14b
LOCAL_API_BASE=http://localhost:11434/v1

# Step up (close other apps first)
# LLM_MODEL=ollama_chat/qwen2.5:32b

# Cloud — best judgment quality, opt-in only
# LLM_MODEL=claude-sonnet-4-6
# ANTHROPIC_API_KEY=sk-ant-...

# OpenAI
# LLM_MODEL=gpt-4o
# OPENAI_API_KEY=sk-...

# Embeddings — shared across all LLM backends
EMBEDDING_MODEL=BAAI/bge-small-en-v1.5

# Phase 4 — optional cloud judgment routing
# ENABLE_CLOUD_JUDGMENT=false      # default: off
# ANTHROPIC_API_KEY=sk-ant-...     # required if any signal type routes to cloud
```

---

## Key Design Decisions

**Air-gap as default, cloud as explicit opt-in per signal type**  
The security model never breaks. Every signal type routes `local` by default. Cloud routing requires deliberate per-type configuration in `autonomy.yaml`. Enterprise fork = lock all to `local` = compliance guarantee in one config change.

**`max_context_tokens: 500` as structural sanitization**  
Forces context compression before any data leaves the machine. If compressed context still exceeds 500 tokens, falls back to local. Obfuscation is enforced by the constraint — no separate policy step that can be skipped.

**APScheduler over Celery**  
Celery requires Redis + separate workers — overkill for 4 users and 30-minute heartbeats. APScheduler runs in-process, persists to existing PostgreSQL. Interface-compatible with Celery if usage outgrows it.

**Approval workflow mandatory for irreversible actions**  
Any tool flagged as irreversible pauses the task and requires user confirmation from the Inbox tab. Primary documented failure mode in the OpenClaw community. Safe-by-default is non-negotiable for a system that acts while the user isn't watching.

**Heartbeat before webhooks and sub-agents**  
Heartbeat is the qualitative shift from "capable chatbot" to "present assistant." FruitcakeAI's retrieval, document handling, and multi-user safety are all ahead of OpenClaw. Without heartbeat, users initiate everything. With heartbeat, the system comes to them. Phases 5 and 6 build on this foundation.

**Fine-tune path post-Phase 4**  
After real-world data shows exactly where 14B local judgment fails, generate synthetic training data using frontier models during development. Fine-tune `qwen2.5:14b` → ship `heartbeat_judge.gguf`. Permanently air-gapped with near-frontier judgment quality for the specific heartbeat task.

**Self-modifying skills: Post-Phase 7**  
OpenClaw lets agents write their own tools — impressive for power users, security risk for a family system with children. MCP config-based tools are auditable and safe. Revisit after enterprise audit trail is proven.

---

## Cursor Usage Notes

- **`app/autonomy/`** is a new top-level module — create from scratch, don't port from anywhere
- **Agent core changes** (`core.py`) for mode-aware turn limits are surgical — preserve all existing `_normalize_tool_calls()` and `message.tool_calls` check patterns
- **APScheduler wires into FastAPI lifespan** — not a separate process, not Celery
- **Test heartbeat manually** via `POST /tasks/{id}/run` before enabling the scheduler
- **APNs requires valid certs** — use sandbox environment during all development
- **`autonomy.yaml` defaults all `local`** — the cloud path needs deliberate test coverage, it should never be the default code path

---

*FruitcakeAI v5 — Simpler. Smarter. Still private. Now proactive.* 🍰  
*Phases 1–3 + Sprint 3.7 complete March 2026 · Phase 4 next*
