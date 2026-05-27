# AGENTS.md — SPPStudio / OpenJarvis Context

Swift Playground++ Studio: a macOS 14+ jailbreak tweak IDE (SwiftUI + AppKit).
OpenJarvis: a manual-first operational layer for task intake, retrieval,
packet generation, and audit history.

This file is **durable context only** — build, layout, architecture rules,
roles, and safety boundaries. It deliberately does **not** track current
milestone, sprint, or regression state (that drifts). For OpenJarvis live task
state, use the Swift `jarvis` CLI from `Tools/sppctl`.

```bash
cd Tools/sppctl
swift run jarvis status
```

Canonical live sources:
- Swift `jarvis` CLI — current operator-facing OpenJarvis control surface
- Python OpenJarvis — supporting runtime/tooling/memory layer
- `SPPStudioDocs/00_CommandCenter/Current Operating State.md` — current cockpit snapshot
- `SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md` — active sprint goal + exit criteria
- `SPPStudioDocs/50_RuntimeOps/Regressions/regression-tracker.md` — open regressions
- `SPPStudioDocs/70_SessionContinuity/Milestones/active-milestone-dashboard.md` — current milestone
- `SPPStudioDocs/20_ArchitectureMemory/ArchitectureSnapshots/` — per-milestone implementation snapshots

---

## OpenJarvis MVP Boundaries

Current MVP posture:
- Manual-first and non-autonomous.
- Single active Codex implementation lane unless explicitly changed by the user.
- Swift `jarvis` CLI is the operator-facing control surface.
- Python OpenJarvis supports runtime/tooling/memory operations.
- Obsidian is operational memory and the continuity cockpit.

Forbidden without explicit user approval:
- autonomous planners, agents, daemons, or background loops
- executor expansion or uncontrolled shell execution
- embeddings/vector database work
- prompt bridge rewrites or auto-send behavior
- runtime/editor architecture rewrites

---

## Build & Run

```bash
# Primary build (use this)
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio

# Full workspace
xcodebuild -workspace SPPStudio.xcworkspace -scheme SwiftPlaygroundPlusPlusStudio build

# Launch app binary directly
Apps/SwiftPlaygroundPlusPlusStudio/.build/arm64-apple-macosx/debug/SwiftPlaygroundPlusPlusStudio
```

Build must pass after every change. No exceptions.

---

## Repo Layout

```
Apps/SwiftPlaygroundPlusPlusStudio/   ← main IDE app (build target)
  Sources/IDE/
    Editor/EditorAreaView.swift       ← tab management, NSTextView pool, syntax highlighting
    Editor/LineNumberRulerView.swift  ← gutter ruler
    Console/BuildConsoleView.swift    ← build output, ANSI, streaming
    IDEWindowView.swift               ← NavigationSplitView root
    Sidebar/SidebarView.swift         ← file navigator, rename, collapse
  Sources/Services/
    AppEnvironment.swift              ← @EnvironmentObject singleton
    ProjectService.swift              ← ALL file system mutations go here
    BuildService.swift                ← build pipeline, readabilityHandler streaming
  Sources/DesignSystem/IDETheme.swift ← all colors, fonts, spacing constants
Packages/
  SPPCore/                            ← project model (SPPProject, SPPFile)
  SPPSymbolKit/, SPPRuntimeKit/, ...  ← 9 other domain packages (not yet wired)
Tools/sppctl/                         ← CLI tool
SPPStudioDocs/                        ← Obsidian vault (DO NOT put code here)
```

---

## Architecture Rules

1. **All file mutations go through `ProjectService`** — never touch `FileManager` directly in UI.
2. **All colors/fonts from `IDETheme`** — no hardcoded hex in views.
3. **NSTextView via `NSViewRepresentable`** — never use SwiftUI `TextEditor` for the code editor.
4. **Editor pool** — `EditorAreaView` keeps one `NSScrollView`/`NSTextView` per open tab alive in a `ZStack+ForEach`. Never use `.id(tabID)` to force recreation; use `isActive`/`isHidden` to switch visibility. This preserves undo history, caret, and scroll per tab.
5. **Package paths are relative** — all `Package.swift` use `path:` references, not version pins.
6. **macOS 14+ only** — use two-parameter `onChange(of:) { old, new in }` syntax.

---

## Known Build Quirks

- Unset `CLANG_MODULE_CACHE_PATH` before building if you see sandbox errors.
- Do not set `CLANG_MODULE_CACHE_PATH` in any build scripts.
- Open `SPPStudio.xcworkspace` (not individual `Package.swift`) for full scheme list.

---

## Working Roles

Canonical contracts live in the vault — do not restate or fork them here:
`SPPStudioDocs/30_AI_Coordination/Role Contracts.md`, `Agent State Board.md`,
`Mode Router.md`. Summary:

- **Codex** — current active implementation lane. Makes narrow code/doc changes,
  runs verification when requested, and keeps commits scoped.
- **Claude** — optional/manual worker surface only when the user explicitly routes
  work there. It is not autonomous and is not assumed to be active.
- **ChatGPT** — prompt architect / systems reasoner. Turns fuzzy goals into
  role-specific prompts and workflows. Does **not** execute code or own runtime state.
- **Watchdog** — passive. Summarizes output and flags drift. Never executes,
  sends, or mutates project code.

Use the smallest operating mode that safely completes the task (see `Mode Router.md`).

---

## Safety Boundaries — forbidden / unsafe to touch casually

Full map: `SPPStudioDocs/00_CommandCenter/Unsafe Mutation Zones.md`. Never do the
following without an explicit invariant target and immediate verification:

- Recreate `NSTextView` / `NSScrollView` / `NSLayoutManager` / `NSTextStorage` /
  `UndoManager` for refresh — this breaks pooled-editor identity, undo, caret, and scroll.
- Move diagnostics onto editor instances. Diagnostics are owned by
  `FileDiagnosticsStore` by file/document identity and rendered with **temporary**
  layout attributes only.
- Make runtime/build services cache editor views. Routing is one-way:
  event → file/document identity → editor. The reverse is forbidden.
- Add SwiftUI overlays, background monitoring, or telemetry to editor surfaces.
- Treat `RuntimeInvariantInspector` output as routing or ownership truth — it is
  advisory only.

Source/automation expansion and any runtime/editor change require **explicit user
approval**.

---

## Obsidian / MCP

The vault at `SPPStudioDocs/` is accessible via MCP while Obsidian is running:

```
MCP server: sppstudio-obsidian-vault
URL: http://127.0.0.1:27123/mcp
Config: .mcp.json (repo root) — local only, gitignored; never commit the token.
        Use .mcp.json.example as the shareable template.
```

Read `SPPStudioDocs/Home.md` for navigation. Write regressions/summaries via:

- OpenJarvis task history and audit commands in the Swift `jarvis` CLI.
- Manual Obsidian notes in the relevant continuity, runtime, or memory docs.
- Python OpenJarvis writeback only through explicit manual commands.

---

## Anti-Loop Rules

- Read budget: 5 files max before writing code. Scope down if you need more.
- No "let me understand the codebase first" blocks.
- No re-reading files already read this session.
- No summaries after finishing (the diff is the summary).
- No asking "should I proceed?" when given a clear task.
- Architecture analysis: 1 paragraph max per session.

Full rules: `SPPStudioDocs/40_PromptEngineering/AntiLoopPrompts/anti-loop-rules.md`

---

## Session Startup (3 files max)

1. `SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md` — what to work on
2. `SPPStudioDocs/50_RuntimeOps/Regressions/regression-tracker.md` — what not to break
3. `PROJECT_CONTEXT.md` — coding standards

Then build. Then implement.
