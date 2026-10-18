# Coding Workspace

## V1 Sprint Closeout

The first coding sprint is complete through the operator-accepted chat scrolling
and prompt-style polish. It delivers the trusted-local inspect/edit/approve/test/
review/commit/source-apply loop; it is not an IDE or a general network-enabled
agent. Pair this native change with `Wombolz/FruitcakeAI` and migrations 052-057.
The backend's `Docs/coding_v1_closeout.md` records rollout and security boundaries.

Latest checks: 68 focused Swift tests, including an actual hidden-window scroll
view's growth/resize/reading-position/resume behavior, and a successful macOS
app/test-bundle build. The shared nullable-approval model also builds for iOS
Simulator. The backend's isolated coding suite passes 304 tests with installed
Pi 1.3.0 and Docker fixtures; no real model or live database is used by those tests.

Hands-on acceptance includes the AV Inventory and RoomCheck exercises, model
switching/review, source delivery, and final scrolling behavior. Independent
fresh-context review, model-specific reasoning controls, and GitHub publishing/
pull requests are separate follow-ups. Do not extend these branches for them.

## Transcript Scrolling And Prompt Styling

Coding chat follows the latest content while the reader is at the bottom. Streamed
messages, new approval cards, diff drawer open/close/resize, and viewport changes
keep that position. Scrolling up suspends following; **Jump to Latest** or manually
returning to the bottom resumes it. A newly submitted run follows the latest
content; prepending older history does not count as a new run. Conversation
selection resets to the latest content. Scroll corrections are non-animated and
driven by content/viewport size changes, not by their own offset notifications.

User prompts are right-aligned and use the main chat's compact teal bubble tokens.
Agent text and operation/approval cards stay left-aligned, retaining their existing
maximum reading width. Shared navigation and drawer sizing are unchanged.

## Approval Waits

Upgrade the backend through migration **057_coding_approval_wait** and rebuild
the native client together. New approval cards say **Waiting for you. No approval
timeout.** Waiting does not consume the run's execution budget. Command execution
and Stop still have deadlines; permission and file checks still run on approval.
Backend restart interrupts the run and cancels pending requests, not automatic
approval or resume. Finite legacy approval deadlines remain supported.

## Workspace Lifecycle Completion

Confirmed local commits and source applies show a dismissible **Last Git action**
banner with the resulting commit hash. Apply feedback names the destination branch
and source folder and explains that the conversation stays in its isolated checkout.
Feedback is per conversation, survives refresh and selection changes while this
workspace store is alive, and is not restored after an app restart. Generating a
review alone never shows success, nor does a failed or uncertain confirmation.

Upgrade the backend through migration **056_coding_workspace_lifecycle** and rebuild
this client. New Coding Session now offers **Working copy: Continue ...** for an
existing ready checkout of the selected repository. This keeps files and starts a
fresh conversation with edits/commands off. One run at a time may use a checkout.

Right-click a conversation to Archive or Delete; Show Archived supports Restore.
Delete hides/tombstones the conversation while retaining backend audit history
and checkout files, not secure erasure. Close all attached conversations before
clean-only checkout removal. The ellipsis menu offers Switch Model while idle;
switching resets edit/command opt-ins. Prior runs show their own model identity.

**Create Commit** and operator-only **Apply Commits to Source** use a resizable top
review panel, with an optional resizable diff pop-out. Generate a fresh preview,
inspect the selected-file or source diff, then explicitly confirm. Changed reviews
are rejected. No operation is retried automatically on a lost response. Apply is
local fast-forward-only and requires a clean original folder including ignored
files; no automatic stash, overwrite, merge, or push is offered. Uncommitted work
remains in the managed checkout. Failures after Git mutation block execution for
operator inspection rather than silently falling back to the source.

See backend `Docs/coding_workspace_lifecycle.md` for limits, API details, retention
semantics, and the live acceptance checklist. Existing titlebar/column geometry is
unchanged. Independent reviewer and reasoning controls remain the next slice.

The first Mac coding surface is implemented on `codex/coding-runtime-client`.
It uses the backend coding API from `codex/coding-runtime-phase-0` and remains
separate from ordinary chat and tasks. Existing pending chat-sidebar edits are
preserved; this slice does not edit ChatView.swift.

## Repository Setup

**Create Repository** uses the standard macOS name/location dialog, followed by
**Create & Authorize**. The backend creates only a new folder, initializes local
Git on `main`, and makes an empty initial commit. It refuses existing folders and
does not configure a remote or publish anything. **Authorize Repository** uses
the standard folder chooser and validates the exact Git root and initial commit
before granting read access. Neither flow requires typing a path. Cancelling the
chooser does not authorize or initialize anything.

These dialogs browse this Mac; the backend must run on this Mac too. Repository
setup remains admin-only. Next choose **New Coding Session**, then explicitly
create an isolated checkout and enable approved edits/commands as needed. No
execution permission is enabled by repository setup. Restart the updated backend
and rebuild this client; no additional database migration is required. A partial
Git setup failure retains the new folder for inspection rather than deleting it.

## Offline Container Command Follow-On

Migration 055 and the matching backend/client add an explicit **Enable Container
Commands** control for idle sessions with a ready checkout. Every invocation
requires **Approve Command**, showing the full command, container directory,
timeout, pinned image, offline policy, and writable-checkout warning. Commands can
change/delete checkout files without separate file-edit approvals. Host Bash,
Mac localhost, internet/LAN access, and personal directories remain unavailable.
This does not change the existing shell MCP container or its network policy.

Keep Docker running, restart with the normal backend start command to migrate
through 055, and rebuild this branch. The default operator-installed image is
`fruitcake/mcp-shell` (`CODING_COMMAND_IMAGE`); nothing is automatically pulled.
Try: `Use fruitcake_run to propose python --version in the checkout root. Wait
for my approval. Do not use host Bash.` The image must contain its own dependencies,
`/bin/sh`, and GNU `/usr/bin/timeout`; macOS-native builds are not supported there.

Output streams into the existing ordered transcript and bounded results remain
in approval history, reloadable with **Load Operation History**. Stop cleans up
the command container; a container-side watchdog enforces the deadline even if
the backend exits. Offline commands have separate per-session opt-in from edits.
See the backend's `Docs/coding_container_commands.md` for the full boundary and
operator checklist. Existing titlebar, inspector, diff resizing, and Chat styling
are unchanged.

## Original Setup

Approved edits now support complete UTF-8 files up to 256 KiB before and after,
with separate 4 MiB complete proposal/approval budgets. Rebuild this client and
restart the backend together for that change; no new migration is required.
Approval SSE frames allow 4 MiB plus framing headroom, while ordinary frames
retain the 128 KiB limit. No diff or file is silently shortened to fit.
Prefer exact edits for existing files; never write a truncated read preview.

- Build this native branch in the existing Xcode project, then select **Code**.
- This backend revision must have migrations through 054 applied, Pi 1.3.0 deliberately installed,
  `CODING_RUNTIME_ENABLED=true`, and an absolute `CODING_RUNTIME_EXECUTABLE`.
  The backend remains disabled by default; the client does not migrate it or
  install a runtime automatically.
- As an operator, authorize a specific repository path on the backend machine.
  Select that grant and an authorized local tool-capable model when creating a
  session. Optional project association grants no filesystem access.
- Try: `Read README.md and explain the application entry points. Do not modify
  files or execute commands.`
- Enable `CODING_REQUIRE_READ_APPROVAL=true` on the backend to test Allow/Deny
  read confirmations. Server-side expiry remains authoritative.

The backend's `Docs/coding_client.md`, `Docs/coding_api.md`, and
`Docs/coding_backend_foundation.md` contain the complete contract and setup.
A personal launcher must start that backend checkout, not an older branch.

## Behavior

Submissions have client-generated idempotency keys. Ambiguous retries preserve
both the key and original message. Guidance and approval decisions are never
retried automatically. Leaving Code cancels only its event observer, not work
on the server; Stop targets a specific run. Reopening reconstructs the display
from durable history and a fresh replay, not a partially persisted cursor.

The shared titlebar host retains its fixed control anchors and moving divider
calculation, now accepting Chat or Code as its title. Coding has separate
sidebar width state, uses global drag coordinates, and respects the existing
document-inspector reservation. Chat styling is not replaced.

Editor handoff opens a matching path on this Mac explicitly through Finder,
VS Code, or Xcode. It never invokes a shell or assumes backend and client
filesystems are identical. Write tools and shell execution are not enabled.

## Verification

macOS application/test bundles compile with signing disabled. Forty-one focused
coding checks pass in an isolated Swift harness, including actual Foundation
chunked SSE delivery, repository-review race guards, split-diff parsing/bounds,
drawer sizing, shared-inspector lifecycle, checkout polling/reconciliation, and offscreen renders of
the real coding pane, file inspector, and diff drawer with mocked auth/network. Full
app-hosted Xcode tests compiled but stalled during
host execution; they are not claimed as passing.

The checked-in tests are `FruitcakeAiTests/CodingWorkspaceTests.swift`. Run the
normal signed host configuration with:

```bash
xcodebuild -project FruitcakeAi.xcodeproj -scheme FruitcakeAi \
  -destination 'platform=macOS' -only-testing:FruitcakeAiTests test
```

Live signed-in local-model testing and full-window sidebar/titlebar/inspector
geometry were reported working by the operator on October 16, 2026. That is
manual acceptance, not automated end-to-end certification.

## Repository Changes

Select **Changes** in the Code workspace header to open the shared, resizable
right-hand file inspector. Select a file for its status/details, then choose
**View Diff** for a height-resizable panel above the conversation. Its default
split view aligns before/after lines and preserves source line numbers; Unified
remains available. Staged, unstaged, and untracked additions are separate.
The diff panel's window icon opens a normal resizable window with a labelled
snapshot, not an automatically refreshing live view. Closing the file inspector
can leave the diff open; closing either surface never stops the agent run.
Refresh/session changes clear stale in-app diffs. Detached snapshots remain
until closed or the coding workspace is removed (including sign-out).

The top panel height uses a fixed drag-start height plus global translation,
not measured-height feedback. It preserves conversation space, with a compact
pop-out/close fallback for short windows. Split rendering is limited to 1,500
rows per comparison; the original bounded unified preview remains available.
Preview truncation and unsupported link/conflict/submodule content are explicit.
No prompt, model call, edit, staging, or commit is performed. The existing
titlebar layout and shared right-inspector resize geometry are retained.

This shows all current repository changes, including pre-existing user edits;
it is not a saved checkpoint or a claim that an agent run made those changes.
Refresh obtains new observations. Late responses after selection/dismissal are
ignored, and failed refreshes clear stale data. The updated backend is required;
no new migration or setting is needed. See its `Docs/coding_repository_review.md`.

## Isolated Read-Only Checkouts

On a new or existing source-only Code session, finish/Stop any active run, choose
**Create Isolated Checkout**, and confirm. Idle and interrupted sessions can
transition even after read-only conversation history. The old source runtime is
retired, the conversation is preserved, and the next run starts in the checkout
with reconstructed context. The action remains visible with a disabled-state
explanation when prerequisites are unmet. Enabling approved edits is a separate
step after the checkout is ready. No new migration is needed for this fix.

The backend creates a detached Git worktree at committed HEAD, not a named branch;
dirty, untracked, and ignored source files are not copied. The banner shows
creation/status/baseline, and the execution path changes to the managed checkout.
Prompt execution, Changes review, and local editor handoff all use that path.
An attached session never silently falls back to the source repository.

Creation/removal is background work. The client polls while visible; leaving
Code cancels only polling, not provisioning. Refresh reconciles lost responses
or backend restarts. A lost response blocks submission until reconciliation.
After closing the session, **Remove Clean Checkout** explicitly requests removal;
changed/untracked/ignored files cause retention, not forced deletion. Reopening
a removed session cannot run against the source. Create a new session instead.

Run the normal backend bootstrap to apply migration 053 before using this build.
There is no new setting or runtime package requirement. Old backends that omit
`managed_checkouts` retain the source-only read-only client path. See backend
`Docs/coding_checkouts.md` for storage/recovery/count limits and operator cleanup.

## Host-Approved Changes

Ready isolated checkouts now offer **Enable Approved Edits** while idle. This is
explicit per-session opt-in, never source-repository write access. Pi proposes
complete UTF-8 files up to 4 KiB through `fruitcake_edit`/`fruitcake_write`; the
Fruitcake host owns every write. Existing parent directories only; no deletion,
shell, installs, automatic commits/merge/publish, or bulk patches.

Each approval offers **Review Proposed Diff** in the existing top drawer/pop-out.
Approve enables after opening the complete preview and acknowledges its exact
hash. Legacy boolean-only approvals cannot apply file changes. The host rechecks
the target and authorization after approval; stale files are not overwritten.
**Load Saved Changes** reviews per-operation host evidence, including denied,
failed, and uncertain outcomes, distinct from live working-tree Changes.

Migration 054 is required. A lost mode response blocks submission until Refresh;
Stop cannot undo an already applied edit. Recovery labels in-flight writes
uncertain and never reapplies them automatically. This remains a trusted-local
alpha, not an OS sandbox. See backend `Docs/coding_approved_edits.md` for the
operator test and security limits. Commands and stronger isolation remain gates.

## Ordered Transcript And Approvals

Assistant messages, tool operations, steering, and approvals now share the same
persisted event-sequence timeline. Streamed deltas/final snapshots update their
own message block; later commentary no longer replaces a paragraph above every
action. Resolved approvals collapse in place and remain available as history.

Complete approval events render immediately, without a per-request HTTP fetch.
Reconnect/decision refreshes merge by durable ID, retaining newer requests and
resolved decisions. There is no three-request display cap. Backend operation
completion now settles only that operation's outstanding approval, preserving
parallel requests. The API supplies event-derived request order for REST/history.

Restart the updated backend and rebuild this native branch. No new migration is
needed. **Load Operation History** replays the same ordering for completed runs.
Forty-one focused checks include a seven-approval transcript render, pending
request retention, stale snapshots, and fragmented text. See backend
`Docs/coding_transcript.md` for the operator test and verification limits.
