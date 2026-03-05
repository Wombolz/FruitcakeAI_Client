# 🍰 FruitcakeAI v5 — Phase 4 Implementation Plan
## Scheduled Tasks + Push Notifications

**Version**: 1.0
**Status**: Planned — ready to implement
**Builds on**: Phases 1–3 + Sprint 3.7 (all complete)
**Last Updated**: March 2026

---

## Why This Is Simpler Than Roadmap_3 Described

Before writing a line of code, OpenClaw's cron implementation was studied directly (`src/cron/`).

**What OpenClaw actually does:**

There is no `build_heartbeat_context()` aggregator. Their scheduled jobs work like this:
1. Store a natural-language `instruction` + a schedule expression in the DB
2. At run time, create an **isolated agent session** (no chat history)
3. Inject the instruction + current timestamp as the prompt
4. Run the LLM with its normal tool set — the agent gathers context via tool calls
5. Capture the output text
6. Push it if non-empty and delivery is configured

**The LLM is the judgment router.** There is no `JudgmentRouter`, no `ContextSanitizer`, no pre-built context aggregation. Since FruitcakeAI already runs Ollama locally, every task is air-gapped by default. No per-signal routing config is needed — the only thing that leaves the machine is the push notification text (the agent's output).

The `JudgmentRouter` and `ContextSanitizer` from Roadmap_3 are deferred indefinitely. They solve a problem that doesn't exist until cloud LLM routing is actually opted into.

---

## Architecture

```
APScheduler (in-process, persists to PostgreSQL)
    │
    ▼  every minute: check for due tasks
TaskRunner
    ├── mark task "running"
    ├── create isolated DB session (type="task", hidden from chat UI)
    ├── build UserContext from task.user
    ├── compose prompt:
    │     "[Task: {title}]
    │      {instruction}
    │
    │      Current time: {ISO timestamp}"
    ├── run_agent(session, user_context, mode="task", max_turns=16)
    │       └── LLM calls existing MCP tools naturally
    │           (list_events, search_library, web_search, etc.)
    ├── capture last assistant message as result
    ├── if irreversible tool called and requires_approval=True → pause, push approval request
    └── if deliver=True and result non-empty → APNs push to user's devices
```

---

## Sprint 4.1 — Task Infrastructure (Days 1–4)

### New DB models (`app/db/models.py`)

```python
class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str]
    instruction: Mapped[str]           # natural language prompt for the agent
    task_type: Mapped[str]             # "one_shot" | "recurring"
    status: Mapped[str] = mapped_column(default="pending")
                                       # pending | running | completed | failed
                                       # cancelled | waiting_approval
    schedule: Mapped[str | None]       # cron expr OR "every:30m" OR ISO timestamp
    deliver: Mapped[bool] = mapped_column(default=True)
    requires_approval: Mapped[bool] = mapped_column(default=False)
    result: Mapped[str | None]         # last output text
    error: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_run_at: Mapped[datetime | None]
    next_run_at: Mapped[datetime | None]

class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    token: Mapped[str] = mapped_column(unique=True)
    environment: Mapped[str] = mapped_column(default="sandbox")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
```

Add `is_task_session: Mapped[bool] = mapped_column(default=False)` to `ChatSession`.

### Task API (`app/api/tasks.py`)

```
POST   /tasks              create task; compute next_run_at from schedule
GET    /tasks              list user's tasks, most recent first
GET    /tasks/{id}         detail + last result text
PATCH  /tasks/{id}         update fields OR approve/reject
DELETE /tasks/{id}         cancel (status → cancelled)
POST   /tasks/{id}/run     manual trigger for dev/testing
```

PATCH approval: `{"approved": true}` resumes a `waiting_approval` task (re-runs with
`pre_approved=True`); `{"approved": false}` cancels it.

### Device API (`app/api/devices.py`)

```
POST   /devices/register   upsert DeviceToken for current_user
DELETE /devices/{token}    remove token (called on logout)
```

### Alembic migration

New tables: `tasks`, `device_tokens`.
New column: `chat_sessions.is_task_session BOOLEAN DEFAULT false`.

### Schedule parsing helper

```python
def compute_next_run_at(schedule: str, last_run_at: datetime | None = None) -> datetime:
    """
    Parses three schedule formats:
    - "every:30m" / "every:1h" / "every:6h" / "every:12h" / "every:1d"
    - Standard 5-field cron expression ("0 8 * * 1-5")
    - ISO 8601 timestamp for one-shot tasks
    """
```

---

## Sprint 4.2 — Task Runner + Scheduler (Days 5–9)

### `app/autonomy/runner.py`

```python
APPROVAL_REQUIRED_TOOLS = {
    "create_calendar_event",
    "send_email",    # Phase 5
}

class TaskRunner:
    def __init__(self, push: APNsPusher):
        self.push = push

    async def execute(self, task_id: int, pre_approved: bool = False) -> None:
        async with AsyncSessionLocal() as db:
            task = await db.get(Task, task_id)
            if not task or task.status not in ("pending", "waiting_approval"):
                return

            # Mark running
            task.status = "running"
            task.last_run_at = datetime.utcnow()
            await db.commit()

        try:
            result_text = await self._run_isolated_agent(task, pre_approved)
            await self._finalize(task, status="completed", result=result_text)

            if task.deliver and result_text.strip():
                await self.push.send(
                    user_id=task.user_id,
                    title=task.title,
                    body=result_text[:200],
                    data={"task_id": task.id},
                )
        except ApprovalRequired as e:
            await self._finalize(task, status="waiting_approval", error=str(e))
            await self.push.send(
                user_id=task.user_id,
                title=f"Approval needed: {task.title}",
                body=f"Task wants to {e.tool_name}. Approve in Inbox.",
                data={"task_id": task.id, "requires_approval": True},
            )
        except Exception as e:
            await self._finalize(task, status="failed", error=str(e))

    async def _run_isolated_agent(self, task: Task, pre_approved: bool) -> str:
        from app.api.chat import create_session_internal
        from app.agent.core import run_agent
        from app.agent.context import UserContext
        from app.db.models import User

        async with AsyncSessionLocal() as db:
            user = await db.get(User, task.user_id)
            session = await create_session_internal(
                db, user_id=task.user_id,
                title=f"[Task] {task.title}",
                is_task_session=True,
            )
            user_ctx = UserContext.from_user(user)
            user_ctx.session_id = session.id

        now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
        prompt = f"[Task: {task.title}]\n{task.instruction}\n\nCurrent time: {now}"

        # Inject pre_approved into context so tool dispatch knows
        user_ctx._task_pre_approved = pre_approved
        user_ctx._task_requires_approval = task.requires_approval
        user_ctx._approval_required_tools = APPROVAL_REQUIRED_TOOLS

        response = await run_agent(
            session_id=session.id,
            user_message=prompt,
            user_context=user_ctx,
            mode="task",
        )
        return response.get("content", "")
```

### `app/agent/core.py` — mode-aware turn limits

Minimal surgical change:

```python
TURN_LIMITS = {
    "chat":  8,
    "task": 16,
}

async def run_agent(session_id, user_message, user_context, mode: str = "chat"):
    max_turns = TURN_LIMITS.get(mode, 8)
    ...
```

No other changes — all existing behavior preserved.

### `app/autonomy/scheduler.py`

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore

_scheduler: AsyncIOScheduler | None = None

async def start_scheduler(runner: TaskRunner) -> None:
    global _scheduler
    _scheduler = AsyncIOScheduler(
        jobstores={"default": SQLAlchemyJobStore(url=settings.database_url_sync)}
    )
    _scheduler.add_job(
        lambda: asyncio.create_task(_tick(runner)),
        trigger="interval", minutes=1, id="task_dispatcher",
    )
    _scheduler.start()
    log.info("Task scheduler started")

async def _tick(runner: TaskRunner) -> None:
    """Find all due tasks and fire them concurrently."""
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Task).where(
                Task.status == "pending",
                Task.next_run_at <= datetime.utcnow(),
            )
        )
        due = result.scalars().all()

    for task in due:
        asyncio.create_task(runner.execute(task.id))

async def stop_scheduler() -> None:
    if _scheduler:
        _scheduler.shutdown(wait=False)
```

Wire into `app/main.py` lifespan:
```python
@asynccontextmanager
async def lifespan(app):
    await rag_service.startup()
    await mcp_registry.startup()
    await start_scheduler(runner=TaskRunner(push=APNsPusher()))   # ← add
    yield
    await stop_scheduler()                                          # ← add
    await mcp_registry.shutdown()
```

---

## Sprint 4.3 — APNs Push Notifications (Days 10–13)

### `app/autonomy/push.py`

```python
import httpx, jwt, time
from pathlib import Path

class APNsPusher:
    """httpx HTTP/2 client to Apple Push Notification service."""

    def __init__(self):
        self._base_url = (
            "https://api.sandbox.push.apple.com"
            if settings.apns_environment == "sandbox"
            else "https://api.push.apple.com"
        )

    def _make_jwt(self) -> str:
        key = Path(settings.apns_auth_key_path).read_text()
        return jwt.encode(
            {"iss": settings.apns_team_id, "iat": int(time.time())},
            key, algorithm="ES256",
            headers={"kid": settings.apns_key_id},
        )

    async def send(self, user_id: int, title: str, body: str, data: dict = {}) -> None:
        tokens = await self._get_tokens(user_id)
        for token in tokens:
            await self._deliver(token, title, body, data)

    async def _deliver(self, token: str, title: str, body: str, data: dict) -> None:
        payload = {
            "aps": {
                "alert": {"title": title, "body": body[:200]},
                "sound": "default",
                "badge": 1,
            },
            **data,
        }
        async with httpx.AsyncClient(http2=True) as client:
            resp = await client.post(
                f"{self._base_url}/3/device/{token}",
                json=payload,
                headers={
                    "authorization": f"bearer {self._make_jwt()}",
                    "apns-topic": settings.apns_bundle_id,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
                timeout=10,
            )
            if resp.status_code != 200:
                log.warning("APNs delivery failed", token=token[:8], status=resp.status_code,
                            body=resp.text)
```

### Required `.env` additions

```env
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
APNS_AUTH_KEY_PATH=./certs/AuthKey_XXXXXXXXXX.p8
APNS_BUNDLE_ID=none.FruitcakeAi
APNS_ENVIRONMENT=sandbox          # sandbox | production
```

### Swift — APNs registration (`FruitcakeAiApp.swift`)

```swift
// On launch, request permission and register
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
UIApplication.shared.registerForRemoteNotifications()

// In notification delegate / scene delegate:
func application(_ app: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    Task {
        let api = APIClient(authManager: authManager)
        try? await api.requestVoid("/devices/register", method: "POST",
                                    body: ["token": hex, "environment": "sandbox"])
    }
}
```

Add `NSUserNotificationUsageDescription` key to `Info.plist`.

---

## Sprint 4.4 — Inbox Tab (Swift) (Days 14–18)

### File layout

```
Views/
└── Inbox/
    ├── InboxView.swift          # Main list view
    ├── TaskRow.swift            # Single task row with status badge
    └── TaskCreateSheet.swift    # Create/edit task form
```

### `InboxView.swift`

```swift
struct InboxView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var tasks: [TaskSummary] = []
    @State private var showCreate = false
    @State private var loadError: String?

    var pendingApprovals: [TaskSummary] { tasks.filter { $0.status == "waiting_approval" } }
    var recentTasks: [TaskSummary] { tasks.filter { $0.status != "waiting_approval" } }

    var body: some View {
        NavigationStack {
            List {
                if !pendingApprovals.isEmpty {
                    Section("Needs Approval") {
                        ForEach(pendingApprovals) { task in
                            TaskRow(task: task, onApprove: { Task { await approve(task, approved: true) } },
                                                onReject:  { Task { await approve(task, approved: false) } })
                        }
                    }
                }
                Section("Recent") {
                    ForEach(recentTasks) { task in TaskRow(task: task) }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showCreate) {
                TaskCreateSheet { Task { await loadTasks() } }
                    .environment(authManager)
            }
            .refreshable { await loadTasks() }
            .task { await loadTasks() }
        }
    }

    private func loadTasks() async { ... }
    private func approve(_ task: TaskSummary, approved: Bool) async { ... }
}
```

### `TaskRow.swift`

Status badge colors:
- `completed` → green
- `running` → blue (with `ProgressView`)
- `failed` → red
- `waiting_approval` → orange (with Approve / Reject buttons)
- `cancelled` → gray

### `TaskCreateSheet.swift`

Fields:
- **Title** — short label
- **Instruction** — multiline `TextEditor` (the natural language prompt)
- **Schedule** — `Picker` with options:
  - One-time (shows `DatePicker`)
  - Every 30 min / 1h / 6h / 12h / Daily
  - Custom cron (shows `TextField` with hint "0 8 * * 1-5")
- **Push when done** — `Toggle` (maps to `deliver`)
- **Require approval for actions** — `Toggle` (maps to `requires_approval`)

### `ContentView.swift` — add Inbox tab

```swift
TabView {
    Tab("Chat",     systemImage: "bubble.left.and.bubble.right") { ChatView() }
    Tab("Inbox",    systemImage: "envelope.badge") { InboxView() }
        .badge(pendingApprovalCount)
    Tab("Library",  systemImage: "books.vertical") { LibraryView() }
    Tab("Settings", systemImage: "gear") { SettingsView() }
}
```

---

## Key Design Notes

**1. No heartbeat context builder.**
The agent gathers context via tool calling. The instruction is the context directive.
Example: `"Check my calendar for today and summarize anything urgent"` → agent calls `list_events`.

**2. Isolated sessions.**
Task sessions are real `ChatSession` rows with `is_task_session=True`, excluded from
`GET /chat/sessions`. Tool call audit logs fire normally. SwiftData is never updated for task sessions.

**3. Air-gap is automatic.**
Ollama runs locally. Task agent uses local model + local MCP tools. The only thing that leaves
the machine is the push notification body (agent output text, ≤200 chars). No routing config needed.

**4. APScheduler over Celery.**
In-process scheduler, persists job store to existing PostgreSQL via `SQLAlchemyJobStore`.
No Redis, no separate worker process. Interface-compatible with Celery if usage outgrows it.

**5. Concurrency.**
Multiple due tasks fire via `asyncio.create_task()` in the same tick. Tasks mark themselves
`running` under their own DB session — no scheduler-level locking needed for the common case.

**6. Approval flow.**
`APPROVAL_REQUIRED_TOOLS` starts with `create_calendar_event`. The interceptor sits in
`app/autonomy/runner.py`, not in `tools.py`, to keep the approval concept isolated from the
normal chat tool dispatch path.

---

## Requirements additions (`requirements.txt`)

```
apscheduler>=3.10.0          # in-process scheduler
apscheduler[sqlalchemy]      # SQLAlchemyJobStore
PyJWT>=2.8.0                 # APNs JWT signing
httpx[http2]>=0.27.0         # http2=True for APNs (already in deps — verify flag)
croniter>=2.0.0              # cron expression parsing for next_run_at
```

---

## Verification Checklist

1. `POST /tasks` with `schedule: "every:1m"` + `deliver: false`
   → `next_run_at` computed and stored ✓

2. Wait 1 minute → `GET /tasks/{id}`
   → `status: "completed"`, `result` populated, `last_run_at` updated ✓
   → Task is hidden from `GET /chat/sessions` ✓

3. `POST /devices/register` from Swift
   → token stored in `device_tokens` table ✓

4. Create task with `deliver: true` + instruction that produces output
   → APNs push arrives on sandbox device ✓

5. Create task with `requires_approval: true` + instruction containing `create_calendar_event`
   → `status: "waiting_approval"` after run ✓
   → Approval push notification received ✓
   → Task appears in Inbox "Needs Approval" section ✓

6. `PATCH /tasks/{id}` `{"approved": true}`
   → Task re-runs with `pre_approved=True`, completes, status → "completed" ✓

7. `pytest tests/ -q` — existing 48 tests still pass ✓
   New tests: task CRUD, schedule parser, runner isolation, approval intercept

---

*Phase 4 ready to implement. Start with Sprint 4.1 (DB models + migrations + task API).*
