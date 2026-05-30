# SPPStudio

A native macOS IDE for iOS and macOS jailbreak tweak development.

**Status: Early preview — active development. Not feature-complete. Expect rough edges.**

---

## What this is

SPPStudio (Swift Playground++ Studio) is a purpose-built native macOS IDE for writing, building, and deploying jailbreak tweaks. It targets the [Theos](https://theos.dev) build system and the [Logos](https://github.com/theos/logos) preprocessor.

The goal is to give tweak developers a proper native workspace instead of the current default: a text editor, a terminal running `make`, and manual deployment over SSH.

This is open-source infrastructure for the jailbreak development ecosystem. It is not finished. It is being built in the open.

---

## Who this is for

- iOS/macOS jailbreak developers writing Objective-C tweaks with Logos
- Swift tweak developers using [Orion](https://orion.theos.dev)
- Anyone working with the Theos toolchain who wants IDE-level tooling

This is not a general-purpose IDE. It is focused on the specific requirements of tweak development: Logos syntax, rootless/rootful packaging, `make`-based builds, and eventually on-device deployment.

---

## Why this exists

Jailbreak tweak development has been largely frozen in tooling terms for years. The standard workflow is:

1. Open source files in a general-purpose editor with no Theos awareness
2. Run `make package` in a separate terminal
3. Copy errors from terminal into editor manually
4. SCP/SSH the resulting `.deb` to a device to test

No IDE currently provides: Logos syntax highlighting, integrated Theos builds with inline diagnostics, device connection, or an understanding of the rootless/rootful packaging schemes.

SPPStudio is an attempt to build that tooling as open-source infrastructure that the whole ecosystem can build on.

---

## Current state

SPPStudio is in active development. The core IDE shell is functional. Editor intelligence and device integration are next.

### Working now

- **Native macOS IDE layout** — three-pane `NavigationSplitView` (file navigator, editor, inspector) with a resizable build console
- **Code editor** — `NSTextView`-backed with per-tab state preservation (undo history, caret position, scroll offset survive tab switching)
- **Syntax highlighting** — Swift, Objective-C, Logos (`.xm`/`.x`), Makefile, plist
- **File navigator** — tree view with inline rename, context menu (New File, New Folder, Rename, Delete), file type icons, collapse-state persistence
- **Tab system** — multi-file editing with keyboard shortcuts (⌘S save, ⌘W close, ⌘[ / ⌘] tab navigation)
- **Build system** — integrated `make package FINALPACKAGE=1` subprocess with real-time streaming output
- **Build console** — ANSI escape stripping, auto-scroll toggle, error/warning line color distinction
- **Theos project scaffolding** — `SPPTheosKit` generates Makefile, control, and plist for new tweaks; rootless, rootful, and rooted packaging schemes
- **Project model** — `SPPProject` with file tree, versioning, bundle ID, and Theos configuration

### In active development (M6 sprint)

- **Inline diagnostics** — `FileDiagnosticsStore` → editor consumers via `NSLayoutManager` temporary attributes (no permanent mutation of text storage)
- **Gutter markers** — error/warning indicators in the line number ruler
- **Code completion** — basic keyword and symbol suggestions, AppKit-native
- **Find & Replace panel**

### Planned (not started)

| Milestone | Feature |
|---|---|
| M7 | sppctl CLI build integration, build config picker |
| M8 | `SPPDeviceKit` — connected device list and deployment |
| M8 | `SPPSimulatorHost` — simulator attach and launch |
| M9 | `SPPSourceIndexKit` — background source indexing, jump-to-symbol |
| M10 | `SPPExportKit` — IPA/deb export pipeline |
| M11 | `SPPRuntimeKit` — runtime log capture, console tab |
| M11 | `SPPInstrumentationBridge` — profiling hooks |
| Icebox | `SPPUIBuilderKit` — visual UI canvas |
| Icebox | IPC-based live reload |

See [ROADMAP.md](ROADMAP.md) for the full milestone list.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (for Swift toolchain)
- [Theos](https://theos.dev/docs/installation) installed (required to build tweaks)

Optional for the `jarvis` CLI tool:
- Swift Package Manager (included with Xcode)

---

## Build and run

Clone the repo and build the main application:

```bash
git clone https://github.com/<your-org>/SPPStudio.git
cd SPPStudio
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

To stage a runnable `.app` bundle and launch it:

```bash
./script/build_and_run.sh
```

Or open the workspace in Xcode:

```bash
open SPPStudio.xcworkspace
```

Then build and run the `SwiftPlaygroundPlusPlusStudio` scheme.

The build takes roughly 45–60 seconds on first compile (11 packages + the app target). Incremental builds are fast.

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
  sppctl/                           ← CLI for build and AI workflow operations
  spp-obsidian-plugin/              ← custom Obsidian plugin for project state
SPPStudioDocs/                      ← project documentation vault (Obsidian)
script/                             ← build, run, and workspace automation scripts
```

---

## Screenshots

> Screenshots pending. The IDE is functional but UI polish is ongoing.

To build and run the current state yourself:

```bash
./script/build_and_run.sh
```

---

## AI-assisted development workflow

SPPStudio is developed using a local-first AI workflow: Claude Code for implementation, Codex for architecture review, and a custom CLI tool (`jarvis`) for task management and context assembly. The `SPPStudioDocs/` directory is an [Obsidian](https://obsidian.md) vault that serves as shared durable memory across sessions.

The `AGENTS.md` and `PROJECT_CONTEXT.md` files at the repo root are the canonical context files for AI sessions. `SPPStudioDocs/30_AI_Coordination/` contains the coordination protocols. This workflow is documented here because it is an intentional part of the project, not because it is required to use or contribute to SPPStudio.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

The short version: contributions are welcome, but the architecture has hard invariants (especially around the `NSTextView` pool) that must be preserved. Read `CONTRIBUTING.md` and `docs/architecture.md` before sending a PR.

---

## License

MIT. See [LICENSE](LICENSE).
