# Roadmap

This file tracks the feature milestones for SPPStudio. Status is honest: completed means it works, in progress means active development, planned means it is scoped but not started, and icebox means deferred indefinitely.

---

## Completed

### M0 — Project bootstrap
- Multi-package Swift workspace (`SPPStudio.xcworkspace`)
- Main app target: `SwiftPlaygroundPlusPlusStudio` (macOS 14+)
- Package graph established: SPPCore, SPPIPCModels, SPPSymbolKit, SPPRuntimeKit, SPPHookKit, SPPTheosKit, SPPExportKit, SPPUIBuilderKit, SPPInstrumentationBridge, SPPDeviceKit, SPPSourceIndexKit
- Companion targets: `SPPSimulatorHost`, `sppctl`

### M1 — IDE shell
- `IDEWindowView` — three-pane `NavigationSplitView` (sidebar, editor, inspector)
- `SidebarView` + `ProjectFileNavigatorView` — file tree with icons
- `EditorAreaView` — editor host with per-tab state (undo, caret, scroll)
- `BuildConsoleView` + `ConsoleTabView` — build output panel
- `InspectorView` — right panel stub
- `WelcomeView` + `NewProjectView` — project creation flow

### M2 — Editor core
- `SyntaxHighlighter` — keyword, string, comment, number token coloring for Swift, ObjC, Logos, Makefile, plist
- `LineNumberRulerView` — gutter with accent bar
- Current-line highlight
- Bracket matching (`() [] {}`)
- Centralized `tabWidth` config

### M3 — File navigator
- Nested folder creation via `ProjectService`
- Inline rename (click-to-edit, Enter/Escape to commit/cancel)
- Sidebar collapse-state persistence
- File-type icons (`.swift`, `.json`, `.md`, plain file)
- Context menu: New File, New Folder, Rename, Delete
- Visual selection state

### M4 — Build console polish
- ANSI escape code stripping
- Auto-scroll toggle
- Warning/error line color distinction
- Streaming real-time output from `make` subprocess

### M5 — Tab system
- `TabButtonView` with hover, close, and active states
- Keyboard shortcuts: ⌘S (save), ⌘W (close), ⌘[ / ⌘] (navigate)
- Per-tab dirty state indicator

### M5A — Build integration
- `AppEnvironment.buildCurrentProject()` wired to `make package FINALPACKAGE=1`
- Theos environment injection (THEOS, THEOS_MAKE_PATH, PATH)
- Build start/stop/progress in toolbar
- `.deb` output detection and Finder reveal

### M6 — Editor intelligence
Established editor intelligence foundations without breaking the pooled `NSTextView` architecture.

- [x] `FileDiagnosticsStore` — diagnostics owned by file identity, not editor instances (one-way routing, per-file publisher)
- [x] Build output → diagnostics: `DiagnosticsParser` + `BuildDiagnosticsCollector` parse clang/swiftc output during both build paths and populate the store atomically
- [x] Diagnostics rendered via `NSLayoutManager` temporary attributes only (underline; no permanent `NSTextStorage` mutation)
- [x] Gutter markers for errors/warnings in `LineNumberRulerView` (no SwiftUI overlays)
- [x] Hover tooltips (native `NSTrackingArea`) and click-to-jump from a Problems panel (`NavigateToLineEvent`)
- [x] Code completion foundation: `NSTextView`-native completion (⌥⎋ / F5), language vocabulary + document identifiers
- [x] Problems console tab + toolbar error/warning badge
- [x] SPPCore unit tests for the diagnostic model, parser, and path resolver

---

## Planned

### M7 — Build pipeline integration
- Wire `sppctl build` CLI into the toolbar build action
- Build configuration picker (Debug / Release)
- ~~Error/warning parsing from build output into `FileDiagnosticsStore`~~ — done in M6
- Find & Replace panel — basic Find/Replace already available via `NSTextFinder` (⌘F / ⌘⌥F); a dedicated inline panel is still open

### M8 — Device and simulator
- `SPPDeviceKit` — connected device list in the sidebar
- `SPPSimulatorHost` — launch/attach simulator, run on simulator
- Deploy `.deb` to connected device
- Run on device action

### M9 — Symbol and source index
- `SPPSourceIndexKit` — background source indexing (file-watching, incremental)
- Symbol outline in inspector panel
- Jump-to-symbol palette (⌘⇧O)

### M10 — Export and deploy
- `SPPExportKit` — IPA and deb package export pipeline
- `SPPTheosKit` full NIC template wiring in the new project flow
- `SPPHookKit` — hook injection workflow surfaced in UI

### M11 — Runtime and instrumentation
- `SPPRuntimeKit` — runtime log capture with a dedicated console tab
- `SPPInstrumentationBridge` — profiling hooks (requires device connection)
- Runtime log search and filtering

---

## Icebox

Items that are architecturally designed but not scheduled.

- `SPPUIBuilderKit` — visual UI canvas for interface layout
- `SPPIPCModels` — IPC-based live reload (requires `SPPSimulatorHost`)
- Plugin/extension API
- Multi-workspace support

---

## What this roadmap is not

This roadmap is not a commitment or a ship date. It reflects the current engineering direction. Priorities shift based on what is most useful to developers who are actively writing tweaks. If you have a specific workflow need that is not addressed here, open an issue.
