# PROJECT_CONTEXT.md — SPPStudio / OpenJarvis Reference

> Read this file first. Do not read the entire codebase before asking questions.

## What This Is
Swift Playground++ Studio (SPPStudio) — a macOS 14+ IDE built in SwiftUI + AppKit for building, running, and deploying Swift/Theos projects to jailbroken devices and simulators.

OpenJarvis is the manual-first operating layer around SPPStudio work. The Swift
`jarvis` CLI is the current operator surface. Python OpenJarvis supports runtime,
tooling, and memory behavior. Obsidian is the memory/cockpit layer.

There is no autonomous execution in the current MVP.

## Architecture in One Paragraph
Multi-package Swift workspace. The main app (`Apps/SwiftPlaygroundPlusPlusStudio`) is a SwiftUI app with AppKit wrappers for the code editor (`NSTextView`). State lives in `AppEnvironment` (ObservableObject). File mutations go through `ProjectService`. Reusable domain logic is split into 11 packages under `Packages/`. A CLI tool `sppctl` lives in `Tools/`.

## Source Layout
```
Apps/SwiftPlaygroundPlusPlusStudio/Sources/
  App/            SPPApp.swift, AppEnvironment.swift
  DesignSystem/   IDETheme.swift (all colors/fonts/spacing)
  Services/       ProjectService.swift (all file I/O)
  IDE/
    IDEWindowView.swift          3-pane layout root
    Editor/    EditorAreaView, LineNumberRulerView, SyntaxHighlighter
    Navigator/ ProjectFileNavigatorView, SidebarView
    Console/   BuildConsoleView, BuildLogTextView, ConsoleTabView
    Inspector/ InspectorView
    Welcome/   WelcomeView, NewProjectView
```

## Packages (what each one does)
| Package | Purpose |
|---|---|
| SPPCore | Shared models, utilities |
| SPPIPCModels | IPC message types for live reload |
| SPPSymbolKit | Symbol model (function, type, etc.) |
| SPPRuntimeKit | Runtime log capture |
| SPPHookKit | Runtime hook injection |
| SPPTheosKit | Theos tweak project scaffolding |
| SPPExportKit | IPA / deb export |
| SPPUIBuilderKit | Visual UI canvas (not started) |
| SPPInstrumentationBridge | Profiling bridge |
| SPPDeviceKit | Connected device management |
| SPPSourceIndexKit | Background source code indexing |

## Coding Standards
- SwiftUI views: no logic, thin wrappers only — logic belongs in services or view models
- All colors/fonts from `IDETheme` — no hardcoded values in views
- All file system mutations via `ProjectService` — never call `FileManager` directly from a view
- `NSViewRepresentable` pattern for all AppKit bridging
- No force unwraps except where the invariant is guaranteed and obvious
- No `print()` statements in committed code
- macOS 14+ APIs permitted; no backwards compatibility shims

## Implementation Priorities (May 2026)
1. Wire build button → `sppctl build` subprocess
2. Code completion (basic keyword/symbol list)
3. Inline error/warning annotations from build output
4. Find & Replace panel

## What's Working
- Full 3-pane IDE layout
- Code editor: syntax highlight, bracket match, line numbers, current-line highlight
- File navigator: tree, inline rename, context menu, file icons, collapse persistence
- Tab system: open files, close, active state
- Build console: ANSI stripping, auto-scroll toggle, warning/error line colors

## What's NOT Working Yet
- Build button (placeholder, not wired)
- Code completion
- Error annotations in editor
- Device/simulator integration
- Any SPP package UI integration (all packages exist but none surfaced in UI)

## Forbidden Behaviors (for AI agents)
- Do not refactor files outside the scope of the current task
- Do not redesign the state management pattern without explicit discussion
- Do not add third-party dependencies without asking
- Do not read all files before starting — use this doc + system-map.md
- Do not write "let me understand the codebase first" analysis blocks
- Do not add TODO comments to code
- Do not create new source files when editing existing ones would do
- Do not add autonomous planners, daemons, hidden loops, or executor expansion
- Do not change runtime/editor architecture during OpenJarvis hygiene work

## Build Command
```bash
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

## Docs Vault
Full project docs in `SPPStudioDocs/` — structured for Obsidian.
Key files:
- `00_CommandCenter/Current Operating State.md` — current cockpit state
- `70_SessionContinuity/Sprints/current-sprint.md` — active sprint goal and exit criteria
- `70_SessionContinuity/ImplementationLog/active-implementation.md` — live implementation notes
- `50_RuntimeOps/Regressions/regression-tracker.md` — regression tracking
- `50_RuntimeOps/Issues/unresolved-bugs.md` — unresolved issue tracking
- `50_RuntimeOps/RuntimeIssues/editor-runtime-issues.md` — editor/runtime stability issues
- `Automation/automation-rules.md` — workspace automation notes
- `MCP/obsidian-local-rest-api.md` — Obsidian REST API and MCP integration
- `20_ArchitectureMemory/Architecture/system-map.md` — full file tree + data flow
- `20_ArchitectureMemory/Architecture/architecture-decisions.md` — ADRs
- `50_RuntimeOps/Bugs/known-regressions.md` — open bugs
- `70_SessionContinuity/Milestones/roadmap.md` — upcoming work
- `40_PromptEngineering/AntiLoopPrompts/anti-loop-rules.md` — session discipline rules

## Manual OpenJarvis Surfaces

Swift side:
```bash
cd Tools/sppctl
swift run jarvis status
swift run jarvis task history <task-id>
```

Python side:
```bash
cd ~/Developer/openjarvis
source .venv/bin/activate
python -m jarvis.main status
```

Obsidian:
- Use `SPPStudioDocs/00_CommandCenter/Current Operating State.md` as the cockpit anchor.
- Update continuity and memory notes manually after each significant use.
