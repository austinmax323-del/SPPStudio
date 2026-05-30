# Notes for Anthropic Claude for Open Source Application

This document explains why SPPStudio is a good fit for Anthropic's Claude for Open Source program. It is honest about current limitations and does not overstate what exists.

---

## What the project is

SPPStudio is a native macOS IDE for iOS and macOS jailbreak tweak development. It targets the [Theos](https://theos.dev) toolchain and [Logos](https://github.com/theos/logos) preprocessor — the dominant build system and macro preprocessor in the jailbreak ecosystem.

This is open-source infrastructure for a real developer ecosystem that has been underserved by tooling for a decade. The project is in active development, not finished.

---

## Why the jailbreak ecosystem needs this

Jailbreak tweak development has virtually no dedicated IDE support:

- General-purpose editors (VS Code, Zed, Sublime) have no awareness of Logos syntax, Theos project structure, rootless/rootful packaging schemes, or substrate hook patterns
- The standard workflow is: text editor + terminal running `make` + manual SSH deployment — unchanged for many years
- There is no integrated build→diagnose→deploy loop for tweak developers

Thousands of developers maintain active tweaks across multiple jailbreak ecosystems (Cydia, Sileo, Zebra, TrollStore). The tooling they use today is the same tooling they used in 2014.

SPPStudio is being built to change that: a native IDE that understands Theos, Logos, hook structures, rootless/rootful packaging, and eventually on-device deployment.

---

## How Claude Code is integrated into this project

Claude Code (via Anthropic's Claude API) is deeply integrated into the development workflow for SPPStudio itself:

- **Claude Code** is the primary implementation surface — it writes Swift code, runs builds, fixes errors, and navigates the codebase
- **Codex** (OpenAI) is used for architecture review and second-opinion passes before committing
- **Jarvis** — a custom Swift CLI tool in `Tools/sppctl/` — manages task context, assembles packets for AI workers, and captures WorkerRun artifacts as diff-centric review outputs
- **Obsidian** (`SPPStudioDocs/`) is the shared durable memory layer — architecture decisions, sprint state, regression tracking, and session handoff notes are stored there and are version-controlled

This is not a wrapper around Claude or a demo of the API. It is a real engineering project using Claude Code as a development tool. The workflow documentation in `AGENTS.md`, `PROJECT_CONTEXT.md`, and `SPPStudioDocs/30_AI_Coordination/` is the actual coordination layer used in daily development.

### Specific ways Claude Code accelerates this project

- **Complex AppKit code:** the `NSTextView` pool architecture and the `NSLayoutManager` temporary attributes for diagnostics are exactly the kind of subtle AppKit behavior where Claude Code's knowledge of underdocumented framework behavior is high-value
- **Multi-package refactoring:** with 11 packages and a strictly typed event bus, changes that span package boundaries benefit from an assistant that can hold the full dependency graph in context
- **Architecture review:** every significant change goes through a Codex diff review before commit — the `AGENTS.md` file documents the exact prompts and scope rules
- **Reducing research overhead:** Logos and Theos are niche enough that documentation is sparse and scattered; Claude Code's breadth covers the gaps that standard language tooling doesn't

### What this project would do with increased API access

The current workflow is constrained by token budget:

- **Deeper cross-file analysis** — the 11-package architecture creates many cross-package invariants; a larger context window allows reviewing all dependency relationships simultaneously
- **Automated architecture review** — currently Codex reviews happen manually per sprint; expanded access would allow every PR-ready diff to get a full architecture review pass
- **Documentation generation** — the `SPPStudioDocs/` vault is maintained manually; an AI pass over each milestone would generate accurate, up-to-date architecture snapshots automatically
- **Completing M6 faster** — the current diagnostics and completion work is the highest-leverage in-progress feature; having fewer token constraints would accelerate the implementation sprints directly

---

## Current state (honest)

The core IDE shell is functional and builds cleanly. What works: 3-pane layout, code editor with per-tab state, syntax highlighting for Swift/ObjC/Logos, file navigator, build integration, Theos project scaffolding.

What does not work yet: inline diagnostics, code completion, device deployment, source indexing, export pipeline.

The project is early but the architecture is solid and the development pace is consistent. It is not a prototype that was spun up for this application — it has been in active development since early 2026 with a tracked milestone history.

---

## Open source rationale

SPPStudio is open-source because:

1. The jailbreak ecosystem has always been open infrastructure — Theos, Substrate, libhooker, Orion are all open. A closed IDE would be out of step with this.
2. The tooling gap is too large for one person to close alone. The goal is for the ecosystem to build on SPPStudio — custom package types, Logos extensions, deployment integrations.
3. The AI-assisted development workflow documented in this repo is itself potentially useful to other developers building native macOS tooling.

---

## Links

- Repository: (this repo)
- Theos: https://theos.dev
- Logos: https://github.com/theos/logos
- Orion: https://orion.theos.dev
