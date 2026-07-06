# SPPStudio

**A native macOS IDE for Theos/Logos jailbreak tweak development.**

> **Status: early preview, active development.** The core IDE shell works — editor, file navigator, syntax highlighting, and integrated Theos builds. Editor intelligence (build diagnostics, gutter markers, a Problems panel, and NSTextView-native completion) has landed (M6). Device deployment is planned (M8). Not feature-complete; expect rough edges.

> **Screenshots:** not yet captured — see [Screenshots](#screenshots). To see the current build, clone the repo and run `./script/build_and_run.sh`.

---

## Overview

SPPStudio (Swift Playground++ Studio) is a native macOS application (SwiftUI + AppKit) for writing and building jailbreak tweaks, with on-device deployment on the roadmap. It targets the [Theos](https://theos.dev) build system and the [Logos](https://github.com/theos/logos) preprocessor.

Most tweak development today happens in general-purpose editors that have no awareness of Theos project structure or Logos syntax. The typical loop is:

1. Edit source in an editor with no Theos/Logos awareness
2. Run `make package` in a separate terminal
3. Read build errors in the terminal and map them back to source by hand
4. Copy the resulting `.deb` to a device over SSH to test

SPPStudio brings these steps into one native application: a Logos-aware editor, an integrated Theos build with streaming output, and early inline diagnostics. On-device deployment remains on the roadmap. It is open-source infrastructure for the jailbreak development ecosystem, built in the open.

---

## Who it's for

- iOS/macOS jailbreak developers writing Objective-C tweaks with Logos
- Swift tweak developers using [Orion](https://orion.theos.dev)
- Anyone working with the Theos toolchain who wants IDE-level tooling

This is not a general-purpose IDE. It is scoped to the specifics of tweak development: Logos syntax, rootless/rootful/rooted packaging, `make`-based builds, and eventually on-device deployment.

---

## Current state

### Working now

- **Native macOS IDE layout** — three-pane `NavigationSplitView` (file navigator, editor, inspector) with a resizable build console
- **Code editor** — `NSTextView`-backed, with per-tab state preservation (undo history, caret position, and scroll offset survive tab switching)
- **Syntax highlighting** — Swift, Objective-C, Logos (`.xm`/`.x`), Makefile, plist
- **File navigator** — tree view with inline rename, context menu (New File, New Folder, Rename, Delete), file-type icons, collapse-state persistence
- **Tab system** — multi-file editing with keyboard shortcuts (⌘S save, ⌘W close, ⌘[ / ⌘] navigation)
- **Integrated build** — runs `make package FINALPACKAGE=1` as a subprocess with real-time streaming output and `.deb` detection
- **Build console** — ANSI escape stripping, auto-scroll toggle, error/warning line color distinction
- **Theos project scaffolding** — `SPPTheosKit` generates Makefile, control, and plist for new tweaks across rootless, rootful, and rooted schemes
- **Project model** — `SPPProject` with file tree, versioning, bundle ID, and Theos configuration

### Editor intelligence — M6 (landed)

- **Build diagnostics** — `FileDiagnosticsStore` owns diagnostics by file identity; build output is parsed (`DiagnosticsParser`) and rendered in the editor via `NSLayoutManager` temporary attributes only (no permanent mutation of text storage)
- **Gutter markers** — error/warning indicators in the line-number ruler
- **Problems panel** — a console tab listing every diagnostic, click-to-jump to the source line, plus a toolbar error/warning badge
- **Hover tooltips** — diagnostic messages on hover via native AppKit tracking
- **Code completion** — `NSTextView`-native keyword, type, and document-symbol suggestions (⌥⎋ / F5)

### Planned and hardening

| Milestone | Feature |
|---|---|
| M7 | `sppctl` CLI build integration, build-config picker, Find & Replace panel |
| M8 | `SPPDeviceKit` — connected device list and deployment |
| M8 | Simulator/runtime attachment hardening — discovery and preflight exist; end-to-end injection is not yet reliable |
| M8 | `SPPSimulatorHost` — companion process work, if still needed by the final runtime architecture |
| M9 | `SPPSourceIndexKit` — background source indexing, jump-to-symbol |
| M10 | `SPPExportKit` — IPA/deb export pipeline |
| M11 | `SPPRuntimeKit` — runtime log capture, console tab |
| M11 | `SPPInstrumentationBridge` — profiling hooks |
| Icebox | `SPPUIBuilderKit` — visual UI canvas |
| Icebox | `SPPIPCModels` — IPC-based live reload |

See [ROADMAP.md](ROADMAP.md) for the full milestone list and [docs/current-status.md](docs/current-status.md) for per-subsystem status.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (for the Swift toolchain)
- [Theos](https://theos.dev/docs/installation) installed (required to build tweaks)

---

## Build and run

Clone and build the main application:

```bash
git clone https://github.com/austinmax323-del/SPPStudio.git
cd SPPStudio
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

Stage a runnable `.app` bundle and launch it:

```bash
./script/build_and_run.sh
```

Or open the workspace in Xcode and run the `SwiftPlaygroundPlusPlusStudio` scheme:

```bash
open SPPStudio.xcworkspace
```

First compile takes roughly 45–60 seconds (11 packages + the app target); incremental builds are fast. If you hit a Swift version mismatch (`module compiled with Swift X cannot be imported by Swift Y`), clear stale artifacts with `rm -rf Apps/SwiftPlaygroundPlusPlusStudio/.build` and rebuild.

### Manual smoke test

Automated tests cover the shared model layer (`swift test --package-path Packages/SPPCore` — diagnostic model, build-output parser, and path resolver; requires full Xcode for XCTest). The UI/editor layer is still verified by hand. After building, verify the core editor invariants by hand:

1. Launch the app (`./script/build_and_run.sh`).
2. Open or create a Theos project (File → New Project, or File → Open on an existing project directory).
3. Open two or more source files in tabs.
4. Type in one tab, switch to another, and switch back — undo history, caret position, and scroll offset should each be preserved per tab.
5. Trigger a build (⌘B) and confirm streaming output appears in the console.

These checks exercise the most fragile part of the codebase: the pooled `NSTextView` architecture. See [docs/architecture.md](docs/architecture.md) for why it matters.

---

## Repository structure

```
Apps/
  SwiftPlaygroundPlusPlusStudio/    ← main macOS IDE application
  SPPSimulatorHost/                 ← simulator companion process (planned)
Packages/
  SPPCore/                          ← shared models, event bus, logging
  SPPHookKit/                       ← hook graph, parser, layout engine
  SPPTheosKit/                      ← Theos/NIC project scaffolding
  SPPRuntimeKit/                    ← runtime log capture models
  SPPSymbolKit/                     ← symbol model (function, type, etc.)
  SPPIPCModels/                     ← IPC message types for live reload
  SPPExportKit/                     ← IPA/deb export (planned)
  SPPDeviceKit/                     ← connected device management (planned)
  SPPSourceIndexKit/                ← background source indexing (planned)
  SPPInstrumentationBridge/         ← profiling bridge (planned)
  SPPUIBuilderKit/                  ← visual UI canvas (icebox)
Tools/
  sppctl/                           ← CLI for build and project operations
  spp-obsidian-plugin/              ← custom Obsidian plugin for project state
SPPStudioDocs/                      ← project documentation vault (Obsidian)
script/                             ← build, run, and workspace automation scripts
docs/                               ← architecture, status, and contributor docs
```

See [docs/architecture.md](docs/architecture.md) for the package graph, data flow, and the editor invariants.

---

## Screenshots

_Not yet captured. Planned shots, in priority order:_

- [ ] Main three-pane window with a Logos tweak open (syntax highlighting visible)
- [ ] Build console streaming `make package` output
- [ ] New-project sheet showing Theos scheme selection
- [ ] File navigator with context menu

To produce the current build yourself: `./script/build_and_run.sh`.

---

## Contributing

Contributions are welcome. The architecture has hard invariants — especially around the pooled `NSTextView` editor — that must be preserved, so read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/architecture.md](docs/architecture.md) before opening a PR.

---

## Development workflow

SPPStudio is built with a local-first, AI-assisted workflow (Claude Code for implementation, Codex for review), coordinated through a small CLI in `Tools/sppctl/` and an [Obsidian](https://obsidian.md) vault under `SPPStudioDocs/` used as durable project memory. None of this is required to build, run, or contribute to SPPStudio — it is internal development tooling. See `AGENTS.md` and `PROJECT_CONTEXT.md` for details.

---

## License

MIT. See [LICENSE](LICENSE).
