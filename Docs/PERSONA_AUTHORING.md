# Persona Authoring

Status: bounded implementation complete on `codex/persona-authoring-client`, based
on v0.2.5; prepared for review, not merged/released. Requires the paired persona
backend and migrations 060/061. Backend `Docs/persona_authoring_closeout.md`
records remaining acceptance checks and separate follow-ups.

## Settings > Personas

- Create from Neutral or duplicate a bundled preset. Built-ins remain read-only.
- Edit display name, description, identity, tone and up to 24 instructions.
  Inherit-on-save and explicitly empty fields are distinct.
- Save immutable revisions with expected-version conflict checks. A stale save
  retains the draft. Changing Settings sections retains editor state; changing
  personas/reloading asks before discarding edits.
- Changing the signed-in server/account recreates Settings state instead of
  carrying old drafts, images, history or previews across identities. A stale
  test-chat callback cannot navigate under the new account.
- Choose the default for new chats separately from the administrator-managed
  account access baseline. Saved edits do not rewrite existing chats or defaults.
- Preview source-labelled static prompt and current tool availability, without
  history, recalled memories, dynamic skills or inline image payloads.
- Open a fresh test chat on an explicit model and saved revision. Automatic memory
  recall defaults off. This does not disable memory-writing/search tools or normal
  approval/access checks. Chat labels the test, revision and recall setting.
- Chat Profile explicitly selects custom revisions. Newer heads are not silently
  applied when other profile settings are saved.
- Archive retains existing selections/history. Delete permanently removes an
  owned custom persona (including archived ones) after showing the affected chat
  count and any default reset. Those chats use Personal Assistant going forward;
  existing messages remain. The backend clears saved persona instructions and
  unshared reference images, but does not erase messages, metadata or backups.
  Active chats/approvals block deletion; stale usage requires reconfirmation.
  Unsaved drafts must be saved/discarded before requesting deletion. Bundled
  presets cannot be deleted. Account/tool permissions remain unchanged.

## Visual Identity

Optional portrait and/or visual character sheet/turnaround image. No character.md
or text biography is required. Images are private immutable backend assets, with
IDs/hashes retained by persona revisions. The authenticated preview never uses
public asset URLs or accepts arbitrary filesystem paths.

PNG/JPEG/still WebP only, at most 8 MiB and 4 megapixels. The backend validates
pixels, strips metadata and normalizes PNG. Per-account quota: 128 images/128 MiB.
Removing/replacing changes the draft; saved history retains old references. Even
uploaded-but-unsaved references count toward quota; cleanup is a follow-up.

Image-generation MCP handoff/test portraits are **not enabled** in this slice.
The editor says so explicitly. A reference-input-capable adapter and disclosure
flow must be verified before images leave the backend for generation. Ordinary
chat does not receive the image bytes or a character-sheet document.

## Verification

Approved isolated macOS build succeeded. Focused native run: **37 tests across
4 suites passed**, with parameterized compact/wide rendering and lexer cases.
Covers DTO contracts, versioned saves, conflict-retained drafts, post-save refresh
recovery, deletion confirmation/conflicts/post-delete refresh failure, image draft
state, model/recall requests and existing inspector/appearance
regressions. No working-app launch/restart was performed; native tests use an
isolated test host. Operator visual acceptance and iOS device testing remain.

Latest log: `/private/tmp/fruitcake-persona-closeout-native.log`.
The operator's Xcode signing-team settings were preserved.

## Correct Test Checkouts

Open this project in Xcode:

`/Users/jwomble/Development/FruitcakeAi/.worktrees/persona-authoring-client/FruitcakeAi.xcodeproj`

Backend code:

`/Users/jwomble/.codex/worktrees/persona-authoring/fruitcake_v5`

Backend `Docs/persona_authoring.md` includes exact migration and branch-specific
launch instructions that retain the operator's existing configuration/data.
Migrations 060/061 were applied to the operator's live database on 2026-10-20 after
a private backup; the backend document records verification. Deletion needs no
further migration. No live personas were deleted during development. The old
primary backend's minimal Neutral preview does not expose authoring APIs. No
human-owned checkout was switched; no .env, credentials or user data were copied.
