# Workflow Rules

## Current Operating Model

OpenJarvis/SPPStudio is manual-first and non-autonomous.

- Swift `jarvis` CLI: primary operator-facing control surface.
- Python OpenJarvis: supporting runtime, tooling, and memory layer.
- Obsidian: operational memory, cockpit, and continuity layer.
- Codex: the single active implementation lane unless the user explicitly changes routing.

Do not add agents, daemons, background loops, executor expansion, prompt auto-send,
or autonomous planning behavior.

## Manual Daily Workflow

1. Check status from the Swift CLI.
2. Create or select one task.
3. Retrieve deterministic context.
4. Generate a Claude/Codex packet only when a manual worker needs one.
5. Run any worker manually.
6. Complete or update the task manually.
7. Write back the decision, verification, and remaining risk.
8. Check task history.
9. Update the Obsidian cockpit, digest, or handoff note when the state changed.

## Verification

Swift side:

```bash
cd Tools/sppctl
swift build
swift run openjarvis-checks
```

Python side:

```bash
cd /path/to/user/Developer/openjarvis
source .venv/bin/activate
python -m compileall jarvis tests
python -m pytest
python -m jarvis.main status
```

SPPStudio app side, when runtime/editor code changes:

```bash
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio
```

## Documentation Updates

Use Obsidian as the durable memory layer.

| Event | Update |
|---|---|
| OpenJarvis task used | task history plus relevant memory digest |
| Context packet generated | session handoff or active task note |
| Verification run | delivery validation or operating state note |
| Risk found | runtime issue, regression, or handoff note |
| Workflow changed | root docs plus matching Obsidian cockpit note |

## Safety Rules

- No hidden automation.
- No prompt bridge semantic changes without explicit approval.
- No automatic prompt sending.
- No uncontrolled shell execution.
- No background monitoring.
- No runtime/editor architecture rewrite during OpenJarvis hygiene work.
- Keep commits narrow and grouped by behavior.

## Root Doc Rule

Root docs describe stable operating policy. Current state belongs in:

- `SPPStudioDocs/00_CommandCenter/Current Operating State.md`
- `SPPStudioDocs/70_SessionContinuity/OpenJarvis Active Task.md`
- `SPPStudioDocs/70_SessionContinuity/OpenJarvis Session Handoff.md`
- `SPPStudioDocs/80_SessionMemory/OpenJarvis Memory Digest.md`
