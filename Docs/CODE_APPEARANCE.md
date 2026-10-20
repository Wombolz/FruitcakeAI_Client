# Code Appearance And Syntax Highlighting

Prepared for native v0.2.5 after implementation October 19, 2026 on
`codex/code-appearance-client`, based on native v0.2.4. Operator feedback accepted
the appearance direction; detailed manual acceptance remains listed below.

## Build The Correct Checkout

This feature lives in the isolated worktree, not the operator's existing native
checkout. Open/build:

`/Users/jwomble/Development/FruitcakeAi/.worktrees/code-appearance-client/FruitcakeAi.xcodeproj`

The existing Xcode checkout at `FruitcakeAi/FruitcakeAi` was not switched, and the
working application/server was not restarted. The ignored local Xcode config was
copied into the worktree for the authorized CLI checks; it is not versioned.
Code appearance itself is native-only. The paired My Workspace feature requires
backend v0.7.44; neither feature adds a migration or required environment setting.

## User Flow

Settings > Appearance > Code offers Fruitcake, Paper and High Contrast with live
Swift/Python previews. These are bundled original palettes, not downloaded themes.
The local `appearance.code.theme.v1` preference stores only the preset identifier.
Unknown identifiers safely fall back to Fruitcake; no code content is persisted
with the preference.

The selection applies to:
- Explorer's read-only source text, selection and line-number gutter;
- shared Chat/Code fenced blocks and structured Chat code cards;
- split/unified diff content in the top drawer and detached diff windows.

Navigation, sidebar, titlebar, message timestamps/cards, approvals and application
status colors stay in the existing app theme. Code theme changes do not replace
tabs, change file bytes or confer new access. AppKit source updates change text
attributes only, retaining the text view/storage, selection, scroll and native
Find configuration. Native Find match indicators retain their system treatment;
the internal search color is reserved for future custom code-search UI.

Diff rows retain addition/removal fills and +/- signals. Syntax colors that would
lose 4.5:1 contrast against a changed-row fill fall back to its diff foreground.
Finding markers remain separate, with a darker amber for Paper to maintain
contrast. Existing diff limitations and historical-capture provenance still apply.

## Tokenizer Decision And Boundaries

A small deterministic local lexical scanner is the initial implementation. It
works directly with UTF-16 offsets shared by AppKit and attributed text; it does
not install a JavaScript engine, web view, grammar bundle or package dependency.
Shared token roles isolate presentation from a future richer tokenizer or theme
import adapter. Files are identified by explicit language hints/extensions, never
by executing or inspecting project configuration.

Supported: Swift, Python, JavaScript, TypeScript, JSON and shell. Full documents
support quoted/multiline strings and comments, Swift nested block comments, numeric
literals, keyword lists, JSON properties and simple type/function-name heuristics.
This is not semantic analysis, a language server or a complete grammar: embedded
interpolation, JavaScript regex literals, JSX/TSX and some language-specific raw
literal forms are not specially parsed. Diff hunks use line-local lexical state,
not invented missing context; historical diffs never fetch live source for colors.

Unknown languages are literal plain text. HTML is never rendered or executed.
Highlighting is bounded to 256 KiB UTF-8, 12,000 LF-delimited lines and 50,000 tokens.
Exceeding any bound disables token coloring for the entire supplied text; it does
not truncate that text. Explorer's existing provider access/complete-read bounds
are unchanged. Source copy and diff copy use the original strings, not rendered
attributes. No model call, network request or filesystem grant is added.

## Verification

The authorized macOS build passed. Final native unit run: **135 tests, 161 cases
passed**, with only the known unrelated
`decodesMCPAppToolResponseResourceURI()` missing-state fixture explicitly excluded.
The unfiltered suite is not claimed green; iOS was not built in this pass.

Coverage includes language selection and plain fallback, Unicode/CRLF preservation,
multiline strings/nested comments, literal/JSON roles, numeric boundaries, bounded
fallback, all-palette text/diff/finding contrast, native attribute-only changes and
a live isolated-preference switch retaining the actual source-view/storage identity,
selection and scroll position. Existing transcript follow/resize, provider
revocation and late-response regressions also passed.

Synthetic code renders at 320/680pt and actual Appearance/split/unified diff renders
were inspected. They are test fixtures, not screenshots of the signed-in working
app. Logs, result summaries and temporary derived data use
`/private/tmp/fruitcake-code-appearance-*`. Existing asset-size, Codable isolation
and AppIntents metadata warnings remain outside this slice.

Manual acceptance: switch presets while a file, selected text, Find, a scrolled
transcript and a detached diff are open; verify retained reading position and
unchanged app chrome. Check the same Python/Swift source in each viewer. Theme
import/export remains a separately scoped follow-on, as do browser testing,
arbitrary Chat directory grants, GitHub delivery and orchestration.
