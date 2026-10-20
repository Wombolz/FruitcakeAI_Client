# My Workspace In Chat

Chat's folder button now opens the authenticated user's Fruitcake workspace,
not a coding repository. This uses the existing Explorer, file tabs and themes.
Code's repository provider, grants, checkout/baseline and review rules are unchanged.

Files are read-only. Complete text has Find/Copy; supported PDFs/images can open
in the existing inert preview tabs. Download uses the native save dialog (20 MB
bound). Attach to Chat only stages a file reference in the current conversation's
draft, with no model call or automatic Send. References use an explicit
`workspace/<user>/<relative-path>` tool prefix, preserving real workspace/
subfolders without ambiguity. Workspace reference drafts remain
conversation-specific and clear on account/server change.
Legacy tools trim trailing whitespace, so those filenames remain browseable and
downloadable but Attach to Chat is disabled with an explanatory tooltip.

The account-bound provider rejects wrong owners, changed server/account identities,
root mismatches and a repository response basis. Inspection cache/lifecycle and
post-wait authorization checks remain in force. New workspace preview references
carry root/owner identity and use the bounded authenticated workspace-download
endpoint, not an arbitrary local path or an executable HTML/browser surface.

Release pairing: native v0.2.5 and backend v0.7.44. After merge, build the updated
normal native checkout and restart the matching backend through its usual start
command. No migration or new environment setting is needed.

For pre-merge development, build this worktree's `FruitcakeAi.xcodeproj`. Pair with backend
`codex/chat-workspace-runtime` in
`/Users/jwomble/.codex/worktrees/chat-workspace/fruitcake_v5`; its
`Docs/chat_workspace.md` documents API limits and the temporary launch command
that preserves the normal backend checkout's configuration and user data paths.
The old backend/start command has not been switched, so rebuilding the native
client alone is insufficient. No new migration or `.env` setting is required.

Final authorized macOS build/tests: **141 tests / 168 cases passed**, with the existing
unrelated missing-state MCP fixture excluded. Narrow/wide fake-provider workspace
and file-action renders were inspected. Signed-in save/preview/send behavior is
still operator acceptance, not established by synthetic fixtures. No working-app
restart or real model turn was performed. Workspace changes ship alongside code appearance; project changes are limited
to release version metadata.

The first closeout pass had a checkout-polling timeout; the complete final rerun
passed, including the attachment-path regression. Logs and the final summary are
under `/private/tmp/fruitcake-closeout-*`.
