# Architecture

SPPStudio is a multi-package Swift workspace. The main application target is `SwiftPlaygroundPlusPlusStudio` (`Apps/SwiftPlaygroundPlusPlusStudio`). Domain logic is split into 11 packages under `Packages/`. A CLI tool lives in `Tools/sppctl/`.

---

## Package graph

```
Apps/SwiftPlaygroundPlusPlusStudio   ← main app target
  depends on:
    SPPCore              ← shared models, event bus, logging, error types
    SPPHookKit           ← hook parser, graph, and layout engine
    SPPTheosKit          ← Theos/NIC project scaffolding and SDK discovery
    SPPRuntimeKit        ← runtime log capture models
    SPPSymbolKit         ← symbol model (function, type, property, etc.)
    SPPIPCModels         ← IPC message types for live reload
    SPPExportKit         ← IPA/deb export pipeline (planned)
    SPPDeviceKit         ← connected device management (planned)
    SPPSourceIndexKit    ← background source indexing (planned)
    SPPInstrumentationBridge ← profiling bridge (planned)
    SPPUIBuilderKit      ← visual UI canvas (icebox)

Apps/SPPSimulatorHost               ← companion simulator process (planned)
  depends on: SPPCore, SPPIPCModels

Tools/sppctl/                       ← CLI tool
  Sources/jarvis/                   ← OpenJarvis orchestration CLI
  Sources/OpenJarvisCore/           ← retrieval, packet, SQLite store
  Sources/sppctl/                   ← build, export, validate commands
```

All package references are local (`path:` relative). No external version-pinned dependencies except `swift-argument-parser` in the CLI tool.

---

## Application architecture

### State management

All observable state lives in `AppEnvironment` (`Sources/App/AppEnvironment.swift`), which is a `@MainActor ObservableObject` injected as an `@EnvironmentObject` at the root. There is one instance for the lifetime of the app.

```
SPPApp
  └── IDEWindowView (.environmentObject(AppEnvironment))
        ├── SidebarView
        ├── EditorAreaView
        ├── InspectorView
        └── ConsoleTabView
```

`AppEnvironment` owns:
- `ProjectService` — all file system I/O
- `SimulatorService` — simulator connection (stub)
- `EventBus` — typed pub/sub for decoupled communication
- Build state: `buildLog`, `isBuilding`, `lastBuiltPackageURL`

### Event bus

`EventBus` is a typed publish/subscribe bus (`Sources/SPPCore/EventBus/EventBus.swift`). Views and services communicate via events rather than direct references where the dependency would create unwanted coupling.

Key event types:
- `FileSelectedEvent` — user tapped a file in the navigator; editor opens or focuses it
- `BuildOutputLineEvent` — one line from the build subprocess; consumed by `BuildConsoleView`

### File I/O routing

All file system mutations go through `ProjectService`. Views never call `FileManager` directly. The routing is strictly one-way:

```
User action → View → ProjectService → file system
```

On read, `ProjectService` publishes a `@Published var currentProject: SPPProject?` that the editor and navigator observe.

---

## Editor architecture — critical invariants

The editor uses `NSTextView` via `NSViewRepresentable`. This is intentional: SwiftUI's `TextEditor` cannot support the features required (line numbers, syntax highlighting, diagnostics, bracket matching, caret-position preservation).

### NSTextView pool

`EditorAreaView` maintains one `NSScrollView`/`NSTextView` pair per open tab, all alive simultaneously in a `ZStack+ForEach`. The active tab is visible; all others are hidden via `isHidden`.

**Why this matters:** each `NSTextView` has its own `NSUndoManager`, selection state, and scroll position. If you recreate the view (e.g. with `.id(tabID)` or by removing it from the hierarchy), you lose all of that. The pool keeps views alive so state is preserved across tab switches.

**Rules:**
- Never use `.id(tabID)` on the editor view — this forces recreation
- Never remove an editor from the `ZStack` while its tab is still open; use `isHidden`
- Never create a new `NSTextView` per tab switch

### Diagnostics ownership

Diagnostics (errors, warnings) are owned by `FileDiagnosticsStore`, keyed by file identity (`UUID`), not by editor instance. The store is the source of truth. Editors consume from it.

Rendering uses `NSLayoutManager` temporary attributes (`addTemporaryAttribute(_:value:forCharacterRange:)`). Temporary attributes do not mutate the underlying `NSTextStorage`, which means:
- Undo history is not polluted by diagnostic rendering
- Diagnostics disappear cleanly when cleared
- Multiple editors on the same document (future feature) can each maintain their own visual state

Never write diagnostic state into `NSTextStorage` permanently.

### One-way routing

Build and runtime services route to editors via file/document identity events through the event bus. The reverse — an editor holding a direct reference to a build service, or a build service holding a reference to an editor — is forbidden. This prevents retain cycles and ensures the editor layer remains unaware of what generates diagnostics.

---

## Design system

`IDETheme` (`Sources/DesignSystem/IDETheme.swift`) is the single source of all colors, fonts, spacing constants, and animation presets. No hardcoded values belong in view files.

---

## Syntax highlighting

`SyntaxHighlighter` (`Sources/IDE/Editor/SyntaxHighlighter.swift`) applies token-based coloring to `NSTextStorage`. It handles:
- Swift
- Objective-C and Objective-C headers
- Logos (`.xm`/`.x`) with Logos-specific keyword detection
- Makefile
- plist (XML tag style)

Highlighting is applied synchronously during `NSTextStorageDelegate` callbacks. It operates on the full text; range-based incremental highlighting is a future improvement.

---

## Build system integration

`AppEnvironment.buildCurrentProject()` launches `/usr/bin/make package FINALPACKAGE=1` as a subprocess in the project directory. It:
- Injects the Theos environment (discovers Theos at `~/theos`, `/opt/theos`, or via the `THEOS` env var)
- Streams stdout/stderr via `Pipe.fileHandleForReading.readabilityHandler`
- Publishes each line as a `BuildOutputLineEvent`
- Detects the output `.deb` in the project's `packages/` directory

The build runs on a background `Task`, but all state mutations happen on `@MainActor`.

---

## CLI tools

### sppctl

`Tools/sppctl/` is a Swift Package with three products:
- `jarvis` — the OpenJarvis manual-first orchestration CLI (task management, context retrieval, worker packet assembly for AI sessions)
- `sppctl` — build, export, validate subcommands for direct project operations
- `OpenJarvisCore` — shared SQLite-backed store, packet generation, vault indexing

### bin/jarvis wrapper

`bin/jarvis` is a shell script wrapper that auto-builds the `jarvis` Swift binary if source changes are newer than the compiled output, then `exec`s it. Install it to a PATH directory with `./install-jarvis.sh`.

---

## Obsidian vault

`SPPStudioDocs/` is an [Obsidian](https://obsidian.md) vault used as shared durable memory for the development workflow. It contains architecture decisions, sprint state, regression tracking, and session handoff notes. It is part of the repo because the documentation is intentional and version-controlled alongside the code.

The vault is not required to build or use SPPStudio. It is a development tool, not product documentation.

MCP integration (for AI sessions connecting to the vault via Obsidian's local REST API) is configured in `.mcp.json`, which is gitignored. See `.mcp.json.example` for the template.
