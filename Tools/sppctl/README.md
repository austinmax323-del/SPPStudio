# OpenJarvis CLI

`jarvis` is the manual-first orchestration CLI for SPPStudio.

It does not execute shell commands or run unattended automation. It creates tasks, retrieves Obsidian context, assembles worker packets, and records explicit state transitions.

## Quick Start

Create a task:

```bash
swift run jarvis task create "Review the runtime ops notes" \
  --context SPPStudio \
  --allowed-file SPPStudioDocs/50_RuntimeOps/ \
  --memory runtime
```

Show a task by full ID or unique prefix:

```bash
swift run jarvis task show 1234abcd
```

List tasks:

```bash
swift run jarvis task list
```

Retrieve context:

```bash
swift run jarvis retrieve --query "architecture memory" --scope architecture
```

Generate a worker packet:

```bash
swift run jarvis packet 1234abcd --role codex
```

Mark completion and writeback:

```bash
swift run jarvis task complete 1234abcd --note "done"
swift run jarvis task writeback 1234abcd --note "memory updated"
```

## Safer Testing

Use `--database /tmp/openjarvis.sqlite` on any subcommand to keep smoke tests isolated from your default OpenJarvis database.
Place it after the subcommand, for example: `jarvis task create --database /tmp/openjarvis.sqlite ...`.

## Verification Routing

Swift checks run from the Swift CLI package:

```bash
cd /path/to/SPPStudio/Tools/sppctl
swift build
swift run openjarvis-checks
swift run jarvis status
```

Python checks run from the Python OpenJarvis checkout:

```bash
cd /path/to/user/Developer/openjarvis
source .venv/bin/activate
python -m compileall jarvis tests
python -m pytest
python -m jarvis.main status
```
