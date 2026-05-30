# OpenJarvis CLI

`jarvis` is the manual-first orchestration CLI for SPPStudio.

It does not execute shell commands or run unattended automation. It creates tasks, retrieves Obsidian context, assembles worker packets, and records explicit state transitions.

## Quick Start

Install the daily wrapper:

```bash
cd ~/Developer/SPPStudio
./install-jarvis.sh
```

After that, `jarvis` works from any directory in your shell.

First launch starts the interactive manual-first shell:

```bash
jarvis
```

You should see the startup dashboard, then a persistent prompt:

```text
OpenJarvis manual-first mode enabled
No autonomous execution. No background workers. No hidden execution.

Database: connected
Vault: resolved
Open tasks: 1
Latest task: 8F287405 ready

Type 'help' for commands.
jarvis>
```

Quit safely with `q`, `quit`, or `exit`.

One-shot commands still work:

```bash
jarvis status
jarvis packet 1234abcd --role codex --copy
```

## Recommended Daily Flow

```text
jarvis
jarvis> go review current retrieval scoring for codex
[jarvis] task ready
  task: 1234abcd
  worker: codex
  scope: coordination
  context: 3 hits
  packet copied to clipboard
```

Paste the copied packet into Codex or Claude manually. OpenJarvis does not auto-send it.

```text
jarvis> close --note "done"
[jarvis] task
  id: 1234abcd
  status: archived
  worker: codex
jarvis> h
jarvis> q
```

## Interactive Workflow

Full control variant:

```text
jarvis> new "Review the runtime ops notes" --context SPPStudio --worker codex --memory runtime
jarvis> list
jarvis> next
jarvis> show 1234abcd
jarvis> retrieve 1234abcd --scope runtime --limit 5
jarvis> packet 1234abcd --role codex --copy
jarvis> done 1234abcd --note "validated"
jarvis> writeback 1234abcd --note "memory updated"
jarvis> history 1234abcd
jarvis> open 1234abcd
jarvis> q
```

After creating or selecting a task, the REPL remembers it as the current task.

Interactive aliases:

```text
ls -> list
s  -> status
n  -> next
r  -> retrieve current/latest task
p  -> packet current/latest task
c  -> close current/latest task
d  -> done
h  -> history
rb -> writeback
w  -> writeback current/latest task
q  -> exit
```

## Natural Language Mode

The REPL understands plain English. Typing 3+ words that aren't a known command shows an interpreted suggestion — it does **not** create a task automatically:

```text
jarvis> review current OpenJarvis UX and prepare a packet for codex
[jarvis] interpreted request
  Create task: Review current OpenJarvis UX and prepare a packet for codex
  Suggested worker: codex
  Suggested scope: coordination
  Run: go review current OpenJarvis UX and prepare a packet for codex
  Or:  new "Review current OpenJarvis UX and prepare a packet for codex" --worker codex --memory coordination
```

To create the task and copy the packet in one step, use `go`:

```text
jarvis> go review current OpenJarvis UX and prepare a packet for codex
[jarvis] task ready
  task: 1234abcd
  worker: codex
  scope: coordination
  context: 3 hits
  packet copied to clipboard
```

To create the task without immediately copying, use `ask`:

```text
jarvis> ask review current OpenJarvis UX and prepare a packet for codex
[jarvis] task ready
  task: 1234abcd
  worker: codex
  scope: coordination
  context: 3 hits
  suggested: p --copy
```

Worker inference:
- input mentions **codex** → `--worker codex`
- input mentions **claude** → `--worker claude`
- otherwise → `--worker codex` (default)

Scope inference:
- architecture / topology / design → `architecture`
- runtime / bug / regression / error → `runtime`
- prompt / agent / coordination / codex / claude / jarvis → `coordination`
- validation / test / build / proof → `validation`
- session / handoff / recovery → `continuity`
- (no match) → `coordination`

Short junk input stays concise:

```text
jarvis> asdf
Unknown command: asdf. Try: help
```

## Paste Protection

Pasting a multi-line prompt block into the REPL produces one message, not a stream of errors:

```text
jarvis> # My notes
That looks like pasted notes or a prompt. Use ask ... to turn it into a Jarvis task, or help for commands.
```

Detected paste patterns: markdown headings (`#`), bullets (`-`, `*`, `+`), numbered lists (`1.`), horizontal rules (`---`), and label lines (`Goal:`, `Required behavior:`). Blank lines are silently ignored. The paste message fires once per paste block and resets when you type a real command.

## Safety Boundaries

Jarvis is strictly manual-first. It does **not**:
- auto-send prompts to Claude or Codex
- execute shell commands or spawn workers autonomously
- run background loops or daemons
- modify the runtime or editor configuration
- advance task state without an explicit command

The `go` command creates a task, generates the packet, and copies it to the clipboard. You paste it into your worker manually, then run `close` when done. OpenJarvis never sends anything automatically.

The shell keeps in-session command history, and on macOS interactive terminals the arrow keys use the system line editor. The shell is persistent, but still manual-first. It does not run agents, send prompts, execute workers, or start background processes.

Create a task:

```bash
jarvis new "Review the runtime ops notes" \
  --context SPPStudio \
  --allowed-file SPPStudioDocs/50_RuntimeOps/ \
  --worker codex \
  --memory runtime
```

Show a task by full ID or unique prefix:

```bash
jarvis task show 1234abcd
```

List tasks:

```bash
jarvis list
jarvis next
```

Retrieve context:

```bash
jarvis retrieve --query "architecture memory" --scope architecture
jarvis retrieve --task 1234abcd --scope runtime --limit 5
```

Generate a worker packet:

```bash
jarvis packet 1234abcd --role codex --scope runtime --limit 5
jarvis packet 1234abcd --role codex --copy
```

Mark completion and writeback:

```bash
jarvis done 1234abcd --note "done"
jarvis writeback 1234abcd --note "memory updated"
jarvis history 1234abcd
```

The longer SwiftPM form still works from this package:

```bash
swift run jarvis status
swift run jarvis task create "Review the runtime ops notes"
swift run jarvis task complete 1234abcd --note "done"
swift run jarvis task history 1234abcd
```

Task lifecycle:

```text
go <request>  →  paste packet into worker  →  close --note "done"  →  h
```

Or with full control:

```text
new -> packet -> manual worker run -> done -> writeback -> history
```

## Safer Testing

Use `--database /tmp/openjarvis.sqlite` on any subcommand to keep smoke tests isolated from your default OpenJarvis database.
Place it after the subcommand, for example: `jarvis task create --database /tmp/openjarvis.sqlite ...`.

Daily aliases:

```bash
jarvis go "request"      # create task + packet + copy to clipboard
jarvis new "task"        # alias for task create (explicit flags)
jarvis list              # alias for task list
jarvis next              # read-only latest open task and suggested command
jarvis close TASK        # complete + writeback in one step (default note: closed)
jarvis done TASK         # alias for task complete
jarvis history TASK      # alias for task history
jarvis writeback TASK    # alias for task writeback
jarvis open TASK         # opens first related retrieved note or allowed file
```

## Verification Routing

Swift checks run from the Swift CLI package:

```bash
cd ~/Developer/SPPStudio/Tools/sppctl
swift build
swift run openjarvis-checks
swift run jarvis status
```

Python checks run from the Python OpenJarvis checkout:

```bash
cd ~/Developer/openjarvis
source .venv/bin/activate
python -m compileall jarvis tests
python -m pytest
python -m jarvis.main status
```
