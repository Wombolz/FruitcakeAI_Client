# Preferred Commit And Merge Process

This note captures the preferred branch wrap-up and release process for the
**client** repo so another AI agent can follow it consistently. It mirrors
the backend's `Docs/_internal/CLAUDE_COMMIT_MERGE_PROCESS.md` in
`fruitcake_v5`, adapted to this repo's Xcode/Swift conventions.

## Core Principles

- Keep the branch focused. Do not merge unrelated spillover work just because it happened on the same branch.
- If unrelated fixes were made while debugging, split or stash them onto a follow-up branch before preparing the merge.
- Prefer small, reviewable commits over one mixed "everything changed" commit when the work naturally separates (e.g. a Chat-specific fix landing on a Tasks branch should be called out, and split off if the user wants).
- Do not invent a new release process. Follow the existing version/changelog/tag pattern already present in this repo.

## Building And Running — Hands Off By Default

Unlike a typical repo, **do not run `xcodebuild`, and do not try to launch,
kill, or relaunch the app yourself** (`open`, `pkill`, etc.) unless the user
explicitly asks. The user keeps an active Xcode debug session running and
drives builds/relaunches/screenshots themselves — repeated agent-initiated
build/kill/relaunch attempts just produce permission prompts and friction.

- Make the code edit, state what changed and why, and hand off: "Build and
  relaunch whenever you're ready."
- The user supplies screenshots for visual verification rather than the
  agent taking them.
- Only build via CLI if the user explicitly asks for a CLI build/test run.

## Before Commit

1. Confirm the branch is clean in scope.
   - Check `git status --short`
   - Check `git diff --stat`
   - Separate unrelated files before staging
2. Verification, in order of preference:
   - The user's own manual build + UI smoke test (the primary signal for this client — there is no meaningful automated coverage yet; `FruitcakeAiTests`/`FruitcakeAiUITests` are boilerplate stubs).
   - If the user explicitly asks for a CLI check, `xcodebuild -scheme FruitcakeAi -destination 'platform=macOS' build` (Debug) is the same build CI runs.
   - `git diff --check` for whitespace/conflict-marker issues.
3. Treat user-reported visual bugs (screenshot + description) as the primary release signal for UI work — there's no snapshot/UI test suite to lean on instead.

## Release Hygiene Pattern

When wrapping a branch that is intended to merge:

1. Bump the version in `FruitcakeAi.xcodeproj/project.pbxproj`:
   - `MARKETING_VERSION` (every build configuration block — there are several, update all matching occurrences)
   - `CURRENT_PROJECT_VERSION` where it tracks the same release (some configs use a separate build-number counter — check before assuming it moves in lockstep)
2. Add a new top entry to `CHANGELOG.md`.

There is no separate `release_notes_vX.Y.Z.md` file convention in this repo (unlike the backend) — `CHANGELOG.md` is the single source. Don't add one unless the user asks for it.

Use the next patch version unless the user explicitly asks for a different versioning decision.

### Changelog Style

- Add a new `## vX.Y.Z` section at the top.
- Use short, lowercase bullets describing shipped behavior, not internal struggle (see existing `v0.2.0`/`v0.2.1` entries for tone).
- Keep it user/release oriented.

## Commit Process

1. Stage only the files that belong to the slice.
2. Create a clear commit message describing the shipped capability, in the style already used on this repo's history, e.g.:
   - `fix(chat): correct task-draft accept route, add deny flow, link existing tasks`
   - `feat(tasks): console-card redesign with collapse, accent, inline editors`
   - `chore(release): bump version to 0.2.1`
3. After committing, verify `git status --short` is clean or clearly explain any intended leftovers.

Preferred commit characteristics:

- specific, not vague
- capability-oriented, `type(scope): summary` prefix matching existing history
- no "misc fixes"

## Push Process

1. Push the working branch first: `git push -u origin <branch>`.
2. Do not merge immediately if:
   - manual testing is still ongoing
   - unrelated spillover is still on the branch
   - a paired backend change hasn't landed yet (check `fruitcake_v5`'s coordination notes under `Docs/_internal/` if the work was coordinated)

## Preferred Merge Process

Once the branch is ready:

1. Make sure the intended work is committed and pushed.
2. Switch to `main`.
3. Pull/update `main`.
4. Merge the feature branch into `main`.
5. Push `main`.
6. Create the release tag for the new version.
7. Push the tag.

If the work was paired with a backend branch:

- finish and validate both sides first
- merge in a deliberate order
- keep the client's version bump/changelog aligned with what the merged result actually does (e.g. don't claim a backend capability the client doesn't render yet)

## Tagging Pattern

After merging to `main`, create and push the matching release tag:

- tag format: `vX.Y.Z` (matches `v0.2.0`, `v0.2.1` — ignore the one-off `pre-realign-client-v0.2` tag, it predates this convention)

```bash
git tag v0.2.2
git push origin v0.2.2
```

Only tag after:

- the merge to `main` is complete
- the version bump and changelog entry are already committed on `main`

## Branch Hygiene

If the branch contains useful but out-of-scope work:

1. Stash or move that work to a new branch.
2. Finish the intended branch cleanly.
3. Resume the spillover on the new branch.

This is preferred over letting a branch gradually absorb unrelated chat/tasks/UI changes — flag it to the user explicitly when it happens rather than merging silently.

## What To Tell The User

When wrapping a branch, report:

- what was committed
- whether the user's own build/manual testing already confirmed it, or it's still pending
- whether the branch was pushed
- whether unrelated work was split off
- what remains before merge, if anything

Keep the summary concise and concrete.

## Repo-Specific Notes

- Version lives in `FruitcakeAi.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), not a source file like the backend's `app/config.py`.
- `CHANGELOG.md` is the only release-summary artifact; there's no `Docs/release_notes_*` equivalent yet.
- CI (`.github/workflows/xcode-build.yml`) only builds the macOS target with signing disabled, on push to `main` and on PRs — it does not run tests.
- `FruitcakeAiTests`/`FruitcakeAiUITests` are boilerplate stubs with no real coverage; don't treat their presence as verification.
- The user actively drives Xcode (build, run, relaunch, screenshots) during a session — see "Building And Running" above.
- If a feature spans both repos, check `fruitcake_v5/Docs/_internal/` for the matching coordination note before assuming what's already shipped on the backend.
