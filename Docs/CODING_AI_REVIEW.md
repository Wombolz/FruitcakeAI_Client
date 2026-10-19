# Independent AI Review Client (R2)

Native branch: `codex/coding-review-client`. Pair with the backend R0/R1 branches
and migration `059_coding_reviews`. The client alone does not enable reviews.

## Rollout

1. Build this native branch, not the previous coding V1/main client.
2. Confirm the configured server is the intended backend checkout with migration
   059. Normal backend startup applies migrations but does not enable reviewers.
3. When ready to test, deliberately set `CODING_REVIEW_ENABLED=true` in the backend
   environment and restart it. Leave existing read-approval policy in force.
   This enables retained captures as well; no second capture flag is required.
4. Refresh Code. Missing/false `ai_reviews` capability keeps Review unavailable.
5. Use a disposable authorized managed checkout for the first real-model review.
   Source-only sessions cannot start reviews. Existing profile/tool permissions
   still apply; no credentials, networking, commands or edit rights are added.

## User Flow

- **Changes** opens live Git inspection without an AI call, as before.
- **Review** reopens the selected saved review, or the latest saved review when
  there is no selection, without another model call. If no review exists, it
  opens setup. The adjacent menu exposes **New Review** and **Review History**
  directly. Opening history does not fetch new-review options or require an
  editable checkout. Choose scope, eligible paths, an independent reviewer
  profile and supported effort in New Review, then explicitly Start Review.
- Closing the inspector or leaving Code does not delete a review. Return to the
  same coding conversation and click Review, or choose an older result through
  Review History. Conversation switches remember the selected review ID and
  Files/Findings tab in memory, while reloading authorized findings/approvals
  from the backend. After an app restart, history still recovers saved results;
  in-memory selection bookmarks are not a new persistence store and are cleared
  when review access is revoked or the capability is disabled.
- Start captures current bytes and reserves the checkout. Busy work is rejected,
  not queued or stopped. An uncertain response keeps the exact request ID and
  offers Retry Same Review Request, rather than issuing another operation.
- The shared right inspector shows Files / Findings for the selected review.
  Status, partial/limited/stale/expired qualifications, model/reasoning provenance
  and measured coverage remain separate. No findings reported is not a clean-code
  certificate; a review does not execute tests.
- Captured-read approvals have explicit Allow Read / Deny actions and no human
  wait timeout. Stop Review addresses only that reviewer, never the builder.
- Show Reviewed Diff uses the capture endpoint and existing top drawer/pop-out.
  Capture/base/HEAD identity, finding side/lines and qualifiers accompany the
  retained diff. Anchors are highlighted when present in displayed hunks. An
  anchor outside the hunks/split limit is disclosed; no live file is substituted.
- Dismiss With Reason / Reopen changes only the historical finding's disposition.
  Actor/time/reason are shown. New reviews do not inherit dismissals automatically.
- Draft Correction rechecks review ownership, then appends a bounded, editable
  historical finding reference/evidence to the existing builder draft. It never
  sends, edits files, resolves a finding or overwrites a draft that is too large.

Review events have an independent durable cursor with replay deduplication,
identity/schema checks, bounded retries and explicit refresh on disconnect.
Switching destination or disconnecting an observer does not stop backend work.
Session switches discard stale asynchronous responses. Builder model settings,
transcript rendering, sidebar/titlebar layout and resize ownership are unchanged.

## Verification And Remaining Acceptance

### October 19 Shared Explorer (Phase 3)

Code now has an **Explorer** folder button beside Changes. It requires a ready
managed checkout and resolves a backend-owned root ID, never a native Mac read
fallback. Expand folders lazily; click a file to open a persistent/pinned read-only
tab. Review/capture tabs remain independent and comparisons stay above the chat.
Source text has line numbers, selection, Copy, local Find, observed time and
changed-version disclosure. No HTML/Markdown execution or model access is added.

Chat's folder button opens the same Explorer host with **No Attached Directory**
until an explicit Chat root-grant contract exists. A project or artifact reference
is not a directory grant. The common provider/viewer boundary is ready for a real
Chat provider; there is no second Code-only tree implementation.

Directory pages are capped at 100 eligible entries, a 4,096-name direct scan and
32 path components. Text is complete UTF-8 up to 256 KiB/12,000 lines; binary,
oversized, missing, changed, ignored and denied content is explicitly unavailable,
not replaced with a prefix. Shared capture-sensitive-path and Git-ignore policy
exclude dot/config/credential/generated paths and links. Current content is not
historical review evidence. In-memory view/folder state is retained, but directory
reactivation reloads first pages and rechecks expanded folders still available in
those pages; additional pages may need to be loaded again.

Native app/test build and **123 tests (134 parameterized cases)** passed, excluding
the same known unrelated MCP fixture. Coverage includes generic and actual coding
provider boundaries, distinct roots, lazy pages, revocation, delayed responses,
Chat unavailability and changed versions. Synthetic 300/600pt tree/source renders
were inspected; signed-in scrolling, Find/Copy, keyboard focus and complete window
geometry remain operator acceptance checks. No working-app restart or model call
was performed. Existing titlebar/sidebar/resize ownership was not changed.

Restart the backend on `codex/coding-review-runtime` and rebuild native
`codex/coding-review-client`; no migration or `.env` change is needed for Explorer.
Backend contract and verification details are in the sibling backend repository's
`Docs/coding_explorer.md`. HTML/browser testing and preview servers remain separate
future work. Changes remain uncommitted on the existing review branches.

### October 19 Shared Inspector Tabs (Phase 2)

The right inspector is now one shared tab host for Chat/Task artifacts and Code.
Live Changes, each saved review/capture, and changed-file details have independent
identities. Opening another item no longer replaces an existing review. Review
Files/Findings state stays with that tab; comparisons remain in the top drawer or
resizable pop-out, not in a new column.

Use the tab's x to close it, the tab context menu for Close Other Tabs, or the
ellipsis menu to select overflow tabs/reopen closed tabs. Hide Inspector preserves
all open tabs. If the last tab was closed, Show Inspector reopens the most recently
closed tab. Closing inspection never stops the reviewer or builder. Switching
conversations/destinations restores the appropriate tab set; account/server
changes and logout clear both open and closed references.

Tab content stays in memory only (12 tabs per context, 32 globally). Reopening or
activating content rechecks authenticated provider access. Each review tab uses
its exact saved review ID and capture rather than following the workspace's most
recent selection. Inactive tab observers are suspended and delayed requests cannot
publish after suspension. Closed tabs release their view state; reopening starts a
fresh authorized viewer. The existing artifact size check is an inline preview
limit after download, not a transport quota.

The approved native build and 113 unit tests (123 parameterized cases) passed,
excluding the same pre-existing MCP fixture documented below. Synthetic 300/560pt
tab chrome was inspected. Signed-in tab round trips, keyboard/focus, retained
scroll and full-window geometry still need operator acceptance. No working-app
restart or model inference was performed.

Only a native rebuild is needed for this phase. No new backend API, migration,
`.env` setting or permission was introduced. Changed-file tabs show current
observations through the existing diff API, not arbitrary source-file access.
Explorer/unchanged-file browsing is Phase 3. HTML/browser testing is still later
work with its own origin, network and preview-server lifecycle controls.

### October 19 Visual Alignment Pass

Code now shares Chat's timestamp format/metadata and inline Markdown rendering,
with fenced code blocks, clearer status/approval cards, compact run details and
expandable finding disposition history. Visible completed runs reload their saved
timeline. The backend adds optional persisted `occurred_at` to coding SSE without
a migration; update both sides for historical per-message timestamps. Legacy
events without timing remain unknown, never assigned reload/run-start times.

Split and unified comparisons use brighter diff-specific red/green text and row
fills; finding outlines retain those colors. Full returned diff copying remains
available. Header/capability details adapt to space without changing application
titlebar/sidebar geometry or resize ownership. This Phase 1 pass did not add tabs;
Phase 2 is recorded above. Explorer remains unimplemented.

The approved CLI macOS build and native unit pass succeeded: 102 tests (111
parameterized cases), with only the previously documented unrelated MCP fixture
below excluded. Backend API/service checks: 50 passed. Synthetic narrow/normal/
wide message fixtures, approval rendering and split/unified diff fixtures were
inspected; this is not signed-in full-window visual acceptance. The operator's
working app was not restarted. Rebuild/relaunch the native client when ready;
the backend must load the additive timestamp change, with no new environment
setting or migration. Changes remain uncommitted on the current review branches.

October 19, 2026: macOS app/test build succeeded. Final native unit run passed
86 tests (92 parameterized cases) with zero failures after explicitly excluding
one unrelated pre-existing MCP fixture failure. That test,
`FruitcakeAiTests/decodesMCPAppToolResponseResourceURI`, supplies no `state` even
though the existing response decoder requires it; both that fixture and decoder
contract remain unchanged by R2. The initial full run recorded that failure;
the unfiltered unit target is not claimed green.

Existing AppIcon sizing, Swift 6 actor-isolation warnings in CachedMessage, and
no-AppIntents metadata warnings remain outside this slice. Test products were
built under `/private/tmp/fruitcake-r2-build`; no working app relaunch or backend
feature enablement was performed.

`FruitcakeAiTests/CodingReviewTests.swift` adds decoding, capability fallback,
selection-race, idempotency, captured-diff identity, Stop, approval, disposition,
correction-draft and cursor fixtures, plus a retained-diff view fixture.
`CodingWorkspaceTests.swift` adds actual inspector renders at 300/440-point
widths across completed, waiting, interrupted/expired and failed states, and
builder/draft safety checks. These are not evidence of real-model behavior or
full-window acceptance.

Before closing R2, exercise the paired signed-in build at minimum, normal and wide
logical window dimensions. Check both sidebar states, inspector/drawer/pop-out
combinations, mid-transcript reading position, bottom following, keyboard/focus
return and composer usability. Findings arriving must not move focus or scroll
the conversation. No sidebar/titlebar redesign is authorized by this slice.

Record empty, limited, blocked/busy, unsupported effort, stale, stopped,
interrupted and expired-content states, not just a successful review. Confirm
reviewer reasoning readback is labelled runtime evidence and provider effort is
unconfirmed. Do not count a code-only fixture as this live acceptance matrix.

No worker orchestration, automatic fixes, GitHub publishing or builder reasoning
controls are part of R2. Rollback disables reviewer admission on the backend and
retains evidence; do not downgrade populated review tables or delete captures.

## Release Checkpoint And Next Slice

Native v0.2.4 pairs with backend v0.7.43 and migration 059 for reviews.
The operator accepted the review/polish/Explorer appearance; full signed-in
interaction checks and the documented unrelated MCP fixture exclusion remain
qualifications, not claims of complete acceptance.

Code Appearance And Syntax Highlighting is the next approved branch, not part of
this release. Follow the sibling backend's `Docs/code_appearance_plan.md`: shared
code palettes/local highlighting and bundled presets first, data-only theme
import/export later. Preserve app chrome, strong diff contrast, tab identity,
selection and scroll state. Browser testing and GitHub delivery remain separate.
