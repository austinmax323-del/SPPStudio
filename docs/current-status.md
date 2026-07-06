# Current Status

Last updated: July 2026. This file is updated when tested app state changes.

---

## Overall

SPPStudio is in active development. The core IDE shell is functional and buildable. Editor intelligence (M6) has landed: diagnostics, gutter markers, the Problems panel, hover diagnostics, and native NSTextView completion are implemented enough to use and test. Simulator/runtime attachment is now partially implemented and actively being hardened; device connectivity remains a major capability gap.

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
| Inline diagnostics | **Working / early** | Build output is parsed into `FileDiagnosticsStore` and rendered with temporary editor attributes |
| Code completion | **Working / early** | NSTextView-native keyword, type, and document-symbol suggestions |
| Gutter markers | **Working / early** | Error/warning indicators render in the line-number ruler |
| Problems panel | **Working / early** | Console tab lists build diagnostics and routes rows back to source locations |
| Hover diagnostics | **Working / early** | Native AppKit tracking surfaces diagnostic messages on hover |
| Find & Replace | **Planned (M7)** | Keyboard shortcut wired but panel not built |
| sppctl build integration | **Planned (M7)** | Direct `sppctl` invocation from toolbar |
| Device connectivity | **Planned (M8)** | SPPDeviceKit models exist; on-hardware deployment is not implemented |
| Simulator discovery | **Partially implemented** | Simulator list, boot state, syslog controls, and preflight UI exist |
| Simulator dylib build | **Partially implemented** | Manual simulator dylib build works; app pipeline is being hardened |
| Runtime injection | **Partial / hardening** | Launch path now uses `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES`; end-to-end hook behavior still needs broader validation |
| Runtime invariant dump | **Working / manual** | Debug menu writes a runtime health snapshot for editor/routing diagnostics |
| Source indexing | **Planned (M9)** | SPPSourceIndexKit stub; not integrated |
| Export pipeline | **Planned (M10)** | SPPExportKit stub; not integrated |
| Hook injection UI | **Partial / internal** | Preflight/injection services exist, but the end-to-end UI is not reliable yet |
| Runtime log capture | **Partial / early** | Simulator syslog surface exists; runtime workflow is still hardening |
| Instrumentation | **Planned (M11)** | SPPInstrumentationBridge stub; requires device |
| UI Builder | **Icebox** | SPPUIBuilderKit stub; not scheduled |
| Live reload | **Icebox** | SPPIPCModels designed; not implemented |

---

## Recently landed: M6 — Editor intelligence

M6 established diagnostics and completion foundations without violating the NSTextView pool architecture. The current editor-intelligence implementation is usable but still early: it should be treated as landed functionality with rough edges, not as a polished production IDE experience.

Exit criteria (from `SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md`):
- Diagnostics ownership follows `BuildService` → events → `FileDiagnosticsStore` → editor consumers
- Editor rendering uses temporary diagnostic visuals, not permanent `NSTextStorage` mutation
- Completion and diagnostics preserve per-tab undo, caret, selection, and scroll state
- Build passes after each major subsystem change

Current tested verification:
- App builds and launches from the repo.
- SPPCore diagnostics/parser/path-resolver tests pass when run with full Xcode selected through `DEVELOPER_DIR`.
- Runtime invariant dump reports the expected diagnostics ownership and no active editor drift in the tested session.

---

## Known gaps and rough edges

- **Limited automated tests.** SPPCore has focused tests for diagnostics/parser/path resolution, but the UI/editor/simulator layers are still mostly verified by manual smoke testing.
- **Inspector is basic.** The right panel shows project/build metadata, but richer symbol and diagnostic detail are still future work.
- **Simulator/runtime attachment is not complete.** Discovery and preflight exist, and simulator dylib builds have been verified manually, but end-to-end injection still needs a booted simulator target and a valid simulator dylib to be confirmed working.
- **Simulator injection uses SIMCTL_CHILD_ prefix.** The injection command passes `DYLD_INSERT_LIBRARIES` via `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` in the parent process environment — the `simctl launch --env` form is not supported by current simctl versions. This is now the implemented approach.
- **Build-from-Simulator-tab UX is weak.** A build can succeed while the console remains on the Simulator tab, hiding the build log from the user.
- **Preflight failure visibility is weak.** The panel can summarize a failed check while the failing row is below the visible area.
- **Find & Replace** is keyboard-shortcut wired but opens nothing yet.
- **No persistent app state.** The last-opened project is not remembered across launches.
- **Performance at scale.** Syntax highlighting is full-text on every keystroke; for large files this will be slow. Incremental/range-based highlighting is a future improvement.

---

## Build health

The main app builds cleanly with:

```bash
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

Focused SPPCore tests pass when XCTest is available from full Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SPPCore
```

If you see a Swift version mismatch error (`module compiled with Swift X cannot be imported by Swift Y`), clean the build artifacts first:

```bash
rm -rf Apps/SwiftPlaygroundPlusPlusStudio/.build
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```
