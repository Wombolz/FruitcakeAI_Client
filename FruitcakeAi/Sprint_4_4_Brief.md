# Sprint 4.4 — Inbox Tab + Memories UI
## Implementation Brief for Cursor

---

## What This Sprint Builds

Three things:
1. **Inbox tab** — task results, pending approvals with Approve/Reject, create new tasks
2. **Memories section** in Settings — shows what the assistant knows about each user
3. **Tab bar update** — add Inbox with pending approval badge count

No APNs dependency. Entirely frontend Swift work. Fully testable on a tethered device.

---

## Backend Endpoints This Sprint Consumes

All of these should already exist from Sprint 4.1. Verify they're working before starting UI work.

```
# Tasks
GET    /tasks                    list current user's tasks
POST   /tasks                    create task
PATCH  /tasks/{id}               update / approve / reject
DELETE /tasks/{id}               cancel/delete
POST   /tasks/{id}/run           manual trigger (dev/testing)

# Memories
GET    /memories                 list active memories (supports ?type= filter)
DELETE /memories/{id}            soft delete
PATCH  /memories/{id}            update importance / tags
```

---

## New Files to Create

```
Models/
├── Task.swift
└── Memory.swift

Views/Inbox/
├── InboxView.swift
├── TaskRow.swift
└── TaskCreateSheet.swift

Views/Settings/
└── MemoriesView.swift          (also contains MemoryRow)
```

---

## Data Models

### Task.swift

```swift
import SwiftUI

struct TaskSummary: Identifiable, Codable {
    let id: Int
    let title: String
    let instruction: String
    let status: String
    let taskType: String
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let result: String?
    let error: String?
    let lastRunAt: Date?
    let nextRunAt: Date?

    var statusColor: Color {
        switch status {
        case "completed":        return .green
        case "running":          return .blue
        case "failed":           return .red
        case "waiting_approval": return .orange
        case "cancelled":        return .gray
        default:                 return .gray
        }
    }

    var isPendingApproval: Bool { status == "waiting_approval" }
    var isRunning: Bool { status == "running" }
}

struct CreateTaskRequest: Codable {
    let title: String
    let instruction: String
    let taskType: String            // "one_shot" | "recurring"
    let schedule: String?           // "every:30m" | "every:1h" | "every:6h" |
                                    // "every:12h" | "every:1d" | cron expr | nil
    let deliver: Bool
    let requiresApproval: Bool
    let activeHoursStart: String?   // "07:00"
    let activeHoursEnd: String?     // "22:00"
    let activeHoursTz: String?      // e.g. "America/New_York"
}
```

### Memory.swift

```swift
import SwiftUI

struct MemorySummary: Identifiable, Codable {
    let id: Int
    let content: String
    let memoryType: String      // "episodic" | "semantic" | "procedural"
    let source: String          // "agent" | "task" | "explicit" | "extracted"
    let importance: Double      // 0.0–1.0
    let accessCount: Int
    let createdAt: Date
    let expiresAt: Date?
    let tags: [String]

    var typeColor: Color {
        switch memoryType {
        case "procedural": return .purple
        case "semantic":   return .blue
        case "episodic":   return .teal
        default:           return .gray
        }
    }

    // Visual importance indicator e.g. "●●●○○"
    var importanceDots: String {
        let filled = Int((importance * 5).rounded())
        return String(repeating: "●", count: filled) +
               String(repeating: "○", count: max(0, 5 - filled))
    }
}
```

---

## API Client Extensions

Add these methods to the existing `APIClient`. Follow the exact same patterns already used in the codebase for auth headers, base URL, and error handling.

```swift
// Tasks
func fetchTasks() async throws -> [TaskSummary]
func createTask(_ request: CreateTaskRequest) async throws -> TaskSummary
func approveTask(_ id: Int, approved: Bool) async throws
    // PATCH /tasks/{id} body: {"approved": true/false}
func deleteTask(_ id: Int) async throws
func runTask(_ id: Int) async throws   // POST /tasks/{id}/run

// Memories
func fetchMemories(type: String? = nil) async throws -> [MemorySummary]
    // GET /memories or GET /memories?type=episodic
func deleteMemory(_ id: Int) async throws
func updateMemoryImportance(_ id: Int, importance: Double) async throws
    // PATCH /memories/{id} body: {"importance": 0.8}
```

---

## Views

### InboxView.swift

Main list view. Two sections:
- **Needs Approval** — tasks with `status == "waiting_approval"`, shown first with orange header
- **Recent** — all other tasks, sorted by `lastRunAt` descending

Behaviors:
- Pull-to-refresh reloads task list
- `.task` modifier loads on appear
- Empty state with illustration and "Create Task" button when list is empty
- Toolbar `+` button opens `TaskCreateSheet`
- `onCreated` callback from sheet reloads the list

```swift
struct InboxView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var tasks: [TaskSummary] = []
    @State private var showCreate = false
    @State private var isLoading = false

    private var pendingApprovals: [TaskSummary] {
        tasks.filter { $0.isPendingApproval }
    }

    private var recentTasks: [TaskSummary] {
        tasks.filter { !$0.isPendingApproval }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tasks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                TaskCreateSheet(onCreated: {
                    Task { await loadTasks() }
                })
                .environment(authManager)
            }
            .refreshable { await loadTasks() }
            .task { await loadTasks() }
        }
    }

    // implement taskList, emptyState, loadTasks, approve, delete
    // following existing patterns in the codebase
}
```

### TaskRow.swift

Each row shows:
- Status badge (colored capsule with dot or spinner for "running")
- Title (headline)
- Instruction preview (2 lines, secondary color)
- Result text — expandable/collapsible on tap, truncated to 80 chars when collapsed
- Error text in red if present
- Approve / Reject buttons if `isPendingApproval`
- Swipe-to-delete

Status badge colors: `completed` → green · `running` → blue + ProgressView spinner · `failed` → red · `waiting_approval` → orange · `cancelled` → gray

```swift
struct TaskRow: View {
    let task: TaskSummary
    var onApprove: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // header: statusBadge + title + nextRunAt
            // instruction preview
            // expandable result
            // error if present
            // approve/reject buttons if isPendingApproval
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) { /* delete */ }
    }
}
```

### TaskCreateSheet.swift

Form with these fields:

| Field | Control | Notes |
|-------|---------|-------|
| Title | TextField | Required |
| Instruction | TextEditor min 80pt | Placeholder text "What should FruitcakeAI do?" Required |
| Frequency | Picker | Options below |
| Custom cron | TextField (monospaced) | Only shown when "Custom cron..." selected |
| Push when done | Toggle | Bound to `deliver` |
| Require approval | Toggle | Bound to `requiresApproval` |
| Active hours | Toggle + two TextFields | Start/end in "HH:mm" format |

Schedule picker options:
```
("one_shot",  "One time")
("every:30m", "Every 30 min")
("every:1h",  "Every hour")
("every:6h",  "Every 6 hours")
("every:12h", "Every 12 hours")
("every:1d",  "Daily")
("custom",    "Custom cron...")
```

Schedule logic when submitting:
- `one_shot` → `taskType: "one_shot"`, `schedule: nil`
- `every:*` → `taskType: "recurring"`, `schedule: "every:Xh"` etc.
- `custom` → `taskType: "recurring"`, `schedule: customSchedule`

Active hours: if toggle on, pass `activeHoursStart`, `activeHoursEnd`, `activeHoursTz: TimeZone.current.identifier`. If off, pass nil for all three.

Toolbar: Cancel (dismisses) + Create (disabled until title and instruction non-empty, shows error inline if API call fails).

### MemoriesView.swift + MemoryRow

**MemoriesView** — navigation destination from Settings. Contains:

- `.searchable` modifier for filtering by content
- Horizontal filter chip row: All · Procedural · Semantic · Episodic
- List grouped by type in that order, skipping empty groups
- Pull-to-refresh
- Empty state message if no memories yet

Filter chips: tapping sets `filterType`. Selected chip uses `.accentColor` background with white text. Unselected uses `Color.secondary.opacity(0.15)`.

**MemoryRow** — each memory shows:
- Content text (full, not truncated)
- Type badge (3-letter abbreviation: PRO / SEM / EPI) in type color
- Importance dots (`●●●○○`) + relative age ("3 days ago")
- Expiry if set ("· expires in 2 days") in tertiary color
- Tags as small capsules if present
- Swipe-to-delete

---

## ContentView.swift Changes

Add Inbox as the second tab (between Chat and Library):

```swift
TabView {
    Tab("Chat",    systemImage: "bubble.left.and.bubble.right") { ChatView() }
    Tab("Inbox",   systemImage: "envelope.badge") { InboxView() }
        .badge(pendingApprovalCount)
    Tab("Library", systemImage: "books.vertical") { LibraryView() }
    Tab("Settings",systemImage: "gear") { SettingsView() }
}
```

`pendingApprovalCount` should be an `@State` integer that refreshes whenever `InboxView` loads. Pass it as a binding or use a shared observable — follow whatever state management pattern is already established in `ContentView`.

---

## SettingsView.swift Changes

Add a Memories row to the existing Settings list:

```swift
Section("Assistant") {
    NavigationLink("Memories") {
        MemoriesView()
            .environment(authManager)
    }
}
```

Place this section near the top of Settings, above account/admin sections.

---

## Build Order

Build in this sequence — each step is independently testable:

1. `Models/Task.swift` + `Models/Memory.swift`
2. API client extensions (test with `/docs` before building UI)
3. `TaskRow.swift` (no network dependency, use preview data)
4. `InboxView.swift`
5. `TaskCreateSheet.swift`
6. `MemoriesView.swift` + `MemoryRow`
7. `ContentView.swift` tab bar update
8. `SettingsView.swift` Memories link

---

## Notes for Cursor

- Follow all existing patterns in the codebase for API calls, auth headers, environment injection, and error handling. Do not introduce new patterns.
- Use `@Environment(AuthManager.self)` consistently — this is already established in the project.
- All async operations use `Task { await ... }` from button callbacks and `.task` / `.refreshable` modifiers.
- No hardcoded colors — use semantic colors (`Color.red`, `.green`, `.orange` etc.) so they adapt to light/dark mode.
- `MemoriesView` is a navigation destination, not a sheet — it pushes onto the Settings `NavigationStack`.
- `TaskCreateSheet` is a sheet — it presents modally from the Inbox toolbar button.
- The `.badge()` modifier on the Inbox tab only shows when `pendingApprovalCount > 0`.
- Do not add any APNs code in this sprint — push notification registration is handled separately.
