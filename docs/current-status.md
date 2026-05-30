# Current Status

Last updated: May 2026. This file is updated at the end of each milestone.

---

## Overall

SPPStudio is in active development. The core IDE shell is functional and buildable. Editor intelligence (M6) is the current work. Device connectivity (M8) is the next major capability gap.

This is not production software. It is an early preview being developed in the open.

---

## Subsystem status

| Subsystem | Status | Notes |
|---|---|---|
| App shell (3-pane layout) | **Working** | NavigationSplitView, sidebar, editor, inspector, console |
| NSTextView pool | **Working** | Per-tab undo, caret, scroll preserved across tab switches |
| Syntax highlighting | **Working** | Swift, ObjC, Logos (.xm/.x), Makefile, plist |
| File navigator | **Working** | Tree, inline rename, context menu, collapse persistence |
| Tab system | **Working** | Multi-file, keyboard shortcuts, dirty state |
| Build integration | **Working** | `make package FINALPACKAGE=1` with streaming output |
| Theos scaffolding | **Working** | New project creates Makefile, control, plist |
| Build console | **Working** | ANSI stripping, auto-scroll, error/warning colors |
| Inline diagnostics | **In progress** | FileDiagnosticsStore design; rendering not complete |
| Code completion | **In progress** | Foundation work in M6; not visible yet |
| Gutter markers | **In progress** | M6 work; not visible yet |
| Find & Replace | **Planned (M7)** | Keyboard shortcut wired but panel not built |
| sppctl build integration | **Planned (M7)** | Direct `sppctl` invocation from toolbar |
| Device connectivity | **Planned (M8)** | SPPDeviceKit models exist; no UI or connection logic |
| Simulator | **Planned (M8)** | SPPSimulatorHost process exists; not wired |
| Source indexing | **Planned (M9)** | SPPSourceIndexKit stub; not integrated |
| Export pipeline | **Planned (M10)** | SPPExportKit stub; not integrated |
| Hook injection UI | **Planned (M10)** | SPPHookKit parser/graph work; no UI |
| Runtime log capture | **Planned (M11)** | SPPRuntimeKit models; no UI |
| Instrumentation | **Planned (M11)** | SPPInstrumentationBridge stub; requires device |
| UI Builder | **Icebox** | SPPUIBuilderKit stub; not scheduled |
| Live reload | **Icebox** | SPPIPCModels designed; not implemented |

---

## Active sprint: M6 — Editor intelligence

The current work is establishing the diagnostics and completion foundations without violating the NSTextView pool architecture.

Exit criteria (from `SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md`):
- Diagnostics ownership follows `BuildService` → events → `FileDiagnosticsStore` → editor consumers
- Editor rendering uses temporary diagnostic visuals, not permanent `NSTextStorage` mutation
- Completion and diagnostics preserve per-tab undo, caret, selection, and scroll state
- Build passes after each major subsystem change

---

## Known gaps and rough edges

- **No automated tests.** UI testing the pooled NSTextView architecture is non-trivial; the focus has been on getting the editor stable before writing tests against it.
- **Inspector is a stub.** The right panel exists but has no content. It is reserved for symbol info and diagnostics detail.
- **SimulatorService is a stub.** The sidebar simulator panel UI exists but the service has no real connection logic.
- **Find & Replace** is keyboard-shortcut wired but opens nothing yet.
- **No persistent app state.** The last-opened project is not remembered across launches.
- **Performance at scale.** Syntax highlighting is full-text on every keystroke; for large files this will be slow. Incremental/range-based highlighting is a future improvement.

---

## Build health

The main app builds cleanly with:

```bash
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

If you see a Swift version mismatch error (`module compiled with Swift X cannot be imported by Swift Y`), clean the build artifacts first:

```bash
rm -rf Apps/SwiftPlaygroundPlusPlusStudio/.build
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```
