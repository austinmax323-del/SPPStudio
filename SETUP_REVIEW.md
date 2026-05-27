# SPPStudio — AI Setup Review

A review of the AI-assisted engineering setup (not the Swift app): AGENTS.md,
PROJECT_CONTEXT.md, WORKFLOW.md, the Obsidian vault + MCP, `spp-workspace.sh`,
`prompt-bridge.sh`, `review-last-change.sh`, the Claude Code config, and the
launch orchestration.

Short version: this is a genuinely strong, unusually disciplined setup. The
weaknesses aren't "you forgot to do X" — they're a few load-bearing gaps that
quietly cap how much the rest of the machinery can actually protect you.

---

## What's already strong (keep doing this)

- **Externalized memory.** The vault is the right pattern for multi-session,
  multi-agent work. Regression tracker, ADRs, failure modes, invariants — all
  outside the model context, all reloadable. Most people never build this.
- **Anti-loop rules.** The 5-file read budget, "no understand-the-codebase-first
  blocks," "the diff is the summary" — these target the *actual* failure mode of
  agentic coding (analysis paralysis + context churn), not a theoretical one.
- **Invariants as machine-checkable scan terms.** `review-last-change.sh` turning
  "don't recreate the NSTextView" into a grep lead is the single most clever
  piece here. It converts architectural intent into something an agent can't
  silently violate.
- **Real safety gates in the prompt bridge.** Unsafe-to-continue gate, repeated-
  failure circuit breaker, scope-expansion approval marker, forbidden-file scan,
  terminal-focus check before pasting. This is the difference between an
  "autonomous loop" and a controllable one.
- **Role separation** (Claude implements, Codex reviews) with a one-task /
  build-after-every-change discipline.

---

## Findings, ranked by leverage

### 1. No version control. (Highest leverage by far.)
There is no `.git` in the repo. Every script degrades around this — `review-
last-change.sh` falls back from `git diff` to `find -mtime -2`, and several docs
say "when git is set up."

Why it matters: your *entire* elaborate apparatus exists to avoid breaking
working code — pooled-editor invariants, regression tracker, runtime drift
snapshots, unsafe-to-continue gates. But with no git there is **no undo**. An
agent can violate an invariant, the build can still pass, and you have no clean
way to revert or bisect. The review tooling is running at maybe 40% of its
designed capability because it has no diff to read. Adding git doesn't just add a
feature — it switches your whole "don't break things" system from *advisory* to
*recoverable*.

Action (run these yourself — I can't exec on your machine):
```bash
cd ~/Developer/SPPStudio
git init
# .gitignore is already in place (added in this pass)
git add -A
git commit -m "Baseline: M6 simulator/runtime foundation + AI workspace"
```
After this, `review-last-change.sh` uses real diffs, and a bad agent run is one
`git restore` away instead of a manual cleanup.

### 2. A live secret is committed in the repo. (DONE — partially.)
`.mcp.json` contains the Obsidian REST API bearer token in plaintext, and the
same key sits in `SPPStudioDocs/.obsidian/plugins/obsidian-local-rest-api/
data.json` — both inside the repo tree. Today the blast radius is small (the API
is localhost-only and there's no git yet), but the moment you `git init && git
add .` it becomes a committed secret, and it's the kind that leaks via a pushed
branch or a shared zip.

Done in this pass:
- Added `.gitignore` excluding `.mcp.json`, the plugin `data.json`, and Obsidian
  workspace state — so `git init` won't capture the token.
- Added `.mcp.json.example` using `${OBSIDIAN_REST_API_TOKEN}` as a committed
  template.

Still on you: confirm your MCP client can read the token from env (or just keep
the real `.mcp.json` local and gitignored, which the .gitignore now handles). If
this token was ever in a synced/shared location, rotate it in the Obsidian plugin
settings.

### 3. "Recommended next action" was a hardcoded lie. (DONE.)
The next-action string ("Inline diagnostics foundation…") was baked as a literal
into three functions in `spp-workspace.sh` (`next_task`, `write_session_state`,
`restore`). It never changed as work progressed — so the moment that task is
done, every session start, restore, and state dump confidently points the agent
at stale work.

Done in this pass: added a `recommended_next_action()` helper that reads the
first non-heading line of `SPPStudioDocs/00_CommandCenter/recommended-next-
action.md`, with the old string preserved as a fallback so nothing breaks if the
file is missing. Edit that one file when the active task changes; the cockpit now
follows it everywhere.

### 4. Three documents disagree about the truth.
- **Agent roster drifts:** AGENTS.md says two agents (Claude + Codex). WORKFLOW.md
  and the generated command-center notes describe three (Claude + Codex +
  ChatGPT). An agent reading AGENTS.md and an agent reading the cockpit get
  different org charts.
- **Volatile state is duplicated:** AGENTS.md hand-maintains the current
  milestone, "M6 completed/remaining," and an open-regressions table — all of
  which also live in the vault (`regression-tracker.md`, milestone dashboard).
  Two copies of mutable state guarantee drift; the agent can't tell which is
  current.
- **Two filing schemes coexist:** numbered folders (`00_CommandCenter`,
  `30_AI_Coordination`, `40_PromptEngineering`, `50_RuntimeOps`) sit alongside
  flat top-level notes (`Architecture Contracts.md`, `Known Failure Modes.md`,
  `Agent Prompts.md`) plus near-duplicate names (`Regressions/regression-
  tracker.md` vs a top-level `Regression Tracker.md`). Cross-links point both
  ways.

Recommendation: make AGENTS.md own *only* the stable stuff (build commands, repo
layout, architecture rules, anti-loop rules, where to look) and **delete the
volatile sections**, replacing them with one line: "Current state: run
`./script/spp-workspace.sh status`." Let the script + vault be the single live
source. Then pick one filing scheme and make the other a stub that links to it.

### 5. "Build must pass" is a norm, not a gate.
AGENTS.md says "Build must pass after every change. No exceptions." but nothing
enforces it. The only Stop hook checks for a session-summary file, not a build.
The cheapest real enforcement is a Claude Code hook that runs the build and
blocks the stop on failure. Sketch:
```jsonc
// in .claude/settings.local.json "hooks"
"PostToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [{ "type": "command",
    "command": "cd /path/to/SPPStudio && swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio >/tmp/spp-build.log 2>&1 || echo 'BUILD FAILED — see /tmp/spp-build.log'" }]
}]
```
(Tune the matcher/cost to taste — a full build on every edit may be too heavy; a
build on Stop is a reasonable middle ground.)

### 6. The Claude permission allowlist has accumulated one-off cruft.
`.claude/settings.local.json` contains session-specific entries that no longer
belong in a standing allowlist: a hardcoded `curl` of a specific
`iPhoneOS16.5.sdk.tar.xz`, a specific `ln -sf … iPhoneOS26.5.sdk`, and a
malformed-looking `Bash(python3 -c ' *)` and `Bash(echo "nic.pl found at $\(…)`
entry. These widen the surface and add noise. Prune to durable patterns (build,
test, workspace script, launch scripts) and re-grant one-offs as needed.

---

## What I changed in this pass (files added/edited)
- `+ .gitignore` — keeps the token, build output, and regenerated state out of
  git once you init it.
- `+ .mcp.json.example` — committed, sanitized MCP template.
- `+ SPPStudioDocs/00_CommandCenter/recommended-next-action.md` — the new single
  source for "what's next."
- `~ script/spp-workspace.sh` — replaced 3 hardcoded next-action strings with a
  helper that reads the file above (fallback-safe).
- `+ SETUP_REVIEW.md` — this file.

Nothing destructive was done. No working script behavior changed except the
next-action now being editable instead of frozen.

## Highest-leverage next steps, in order
1. `git init` + commit a baseline (unlocks everything else).
2. Collapse duplicated volatile state out of AGENTS.md into the script/vault.
3. Add the build-on-Stop hook so "build must pass" is enforced, not hoped.
4. Prune the permission allowlist.
5. Reconcile the two-vs-three agent roster and the dual filing scheme.
