#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/SPPStudioDocs"
STATE_DIR="$ROOT_DIR/script/state"
TODAY="$(date +%Y-%m-%d)"

REST_DATA="$VAULT_DIR/.obsidian/plugins/obsidian-local-rest-api/data.json"
SESSION_INDEX="$STATE_DIR/current-session.md"
SESSION_JSON="$STATE_DIR/current-session.json"
STATE_ACTIVE_SUBSYSTEM="$STATE_DIR/active-subsystem.txt"
STATE_LAST_BUILD="$STATE_DIR/last-successful-build.md"
STATE_HIGH_REGRESSIONS="$STATE_DIR/high-severity-regressions.md"
STATE_CURRENT_FOCUS="$STATE_DIR/current-focus.md"
STATE_ARCH_WARNINGS="$STATE_DIR/architecture-warnings.md"
STATE_NEXT_ACTION="$STATE_DIR/recommended-next-action.txt"
STATE_LAST_VERIFICATION="$STATE_DIR/last-verification.md"
STATE_RUNTIME_NOTES="$STATE_DIR/runtime-instability.md"
RUNTIME_DUMP_FILE="$HOME/Library/Caches/SPPStudio/runtime-invariants/latest.txt"
STATE_RUNTIME_SNAPSHOTS="$STATE_DIR/runtime-snapshots"
STATE_RUNTIME_LATEST_SNAPSHOT="$STATE_RUNTIME_SNAPSHOTS/latest-snapshot.txt"
COMMAND_CENTER_DIR="$VAULT_DIR/00_CommandCenter"
AI_COORDINATION_DIR="$VAULT_DIR/30_AI_Coordination"
PROMPT_ENGINEERING_DIR="$VAULT_DIR/40_PromptEngineering"
RUNTIME_OPS_DIR="$VAULT_DIR/50_RuntimeOps"

mkdir -p "$STATE_DIR"

slugify() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/^$/session/'
}

api_key() {
  sed -n 's/.*"apiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REST_DATA" | head -n 1
}

git_status_line() {
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local changes
    changes="$(git -C "$ROOT_DIR" status --short | wc -l | tr -d ' ')"
    echo "git: worktree detected, $changes changed paths"
  else
    echo "git: no worktree detected at $ROOT_DIR"
  fi
}

rest_status() {
  local key
  key="$(api_key || true)"
  if [ -z "$key" ]; then
    echo "warn: API key not found in plugin data.json"
    return 1
  fi
  if curl -fsS -H "Authorization: Bearer $key" http://127.0.0.1:27123/ >/dev/null 2>&1; then
    echo "ok: Obsidian REST API reachable on http://127.0.0.1:27123/"
    return 0
  fi
  echo "warn: Obsidian REST API not reachable; open the vault in Obsidian, then rerun doctor"
  return 1
}

mcp_status() {
  local key response_file
  key="$(api_key || true)"
  response_file="$STATE_DIR/mcp-check.json"
  if [ -z "$key" ]; then
    echo "warn: MCP check skipped because API key was not found"
    return 1
  fi
  if curl -fsS \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"spp-workspace","version":"1.0.0"}}}' \
    http://127.0.0.1:27123/mcp >"$response_file" 2>/dev/null; then
    echo "ok: Obsidian MCP endpoint reachable on http://127.0.0.1:27123/mcp"
    return 0
  fi
  echo "warn: Obsidian MCP endpoint not reachable"
  return 1
}

require_vault() {
  if [ ! -d "$VAULT_DIR" ]; then
    echo "Vault not found: $VAULT_DIR" >&2
    exit 1
  fi
}

append_line() {
  local file="$1"
  local line="$2"
  printf "%s\n" "$line" >>"$file"
}

unresolved_regressions() {
  require_vault
  awk -F '|' '
    NR > 2 && $0 ~ /^\| REG-/ {
      status=$5
      gsub(/^ +| +$/, "", status)
      if (status != "Fixed") print $0
    }
  ' "$VAULT_DIR/50_RuntimeOps/Regressions/regression-tracker.md" || true
}

unresolved_regression_summary() {
  local rows
  rows="$(unresolved_regressions)"
  if [ -n "$rows" ]; then
    printf "%s\n" "$rows"
  else
    echo "none"
  fi
}

latest_build() {
  require_vault
  grep "^| 20" "$VAULT_DIR/60_DeliveryValidation/BuildNotes/build-validation-log.md" | tail -1 || echo "No build validation rows found."
}

current_milestone() {
  require_vault
  grep -m 1 "^## Current:" "$VAULT_DIR/70_SessionContinuity/Milestones/active-milestone-dashboard.md" | sed 's/^## Current: //' || echo "Unknown milestone"
}

active_subsystem() {
  require_vault
  grep -m 1 "^- Active engineering target:" "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md" | sed 's/^- Active engineering target: //' || echo "Unknown subsystem"
}

high_severity_regressions() {
  require_vault
  awk -F '|' '
    NR > 2 && $0 ~ /^\| REG-/ {
      severity=$4
      status=$5
      gsub(/^ +| +$/, "", severity)
      gsub(/^ +| +$/, "", status)
      if (status != "Fixed" && (severity == "High" || severity == "Critical")) print $0
    }
  ' "$VAULT_DIR/50_RuntimeOps/Regressions/regression-tracker.md" || true
}

high_severity_regression_summary() {
  local rows
  rows="$(high_severity_regressions)"
  if [ -n "$rows" ]; then
    printf "%s\n" "$rows"
  else
    echo "none"
  fi
}

active_runtime_issue_rows() {
  require_vault
  grep "^- 20[0-9][0-9]-" "$VAULT_DIR/50_RuntimeOps/RuntimeIssues/editor-runtime-issues.md" | tail -8 || true
}

active_runtime_issues() {
  local rows
  rows="$(active_runtime_issue_rows)"
  if [ -n "$rows" ]; then
    printf "%s\n" "$rows"
  else
    echo "none recorded"
  fi
}

current_focus() {
  require_vault
  grep -m 1 "^## Sprint Goal" -A1 "$VAULT_DIR/70_SessionContinuity/Sprints/current-sprint.md" | tail -1
}

editor_invariant_risks() {
  require_vault
  cat <<'RISKS'
- Critical: pooled NSTextView lifecycle must not be recreated for refresh.
- Critical: diagnostics must be file/document state, not editor-instance state.
- Critical: diagnostics must use temporary layout attributes, not permanent text mutation.
- High: SwiftUI overlays must not render editor gutters, squiggles, or completion.
- High: BuildService emits events; it is not the canonical diagnostics store.
RISKS
}

architecture_warnings() {
  require_vault
  echo "Architecture warnings"
  echo "- Review [[Known Bad Patterns]] before editor/runtime changes."
  echo "- Check [[Known Failure Modes]] when debugging symptoms."
  echo "- Run ./script/review-last-change.sh before Codex review."
  echo "- Severity lens: Critical for NSTextView lifecycle, diagnostics ownership, and NSTextStorage ownership."
  echo ""
  echo "Editor invariant risk section"
  editor_invariant_risks
}

unsafe_to_continue() {
  local high runtime
  high="$(high_severity_regressions)"
  runtime="$(active_runtime_issue_rows)"
  if [ -n "$high" ] || [ -n "$runtime" ]; then
    echo "UNSAFE TO CONTINUE WITHOUT TRIAGE"
    [ -n "$high" ] && printf "%s\n" "$high"
    [ -n "$runtime" ] && printf "%s\n" "$runtime"
  else
    echo "safe to continue: no high-severity regressions or active runtime instability recorded"
  fi
}

recommended_next_action() {
  local file="$VAULT_DIR/00_CommandCenter/recommended-next-action.md" action
  if [ -f "$file" ]; then
    action="$(awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*>/ { next }
      { print; exit }
    ' "$file" 2>/dev/null || true)"
    if [ -n "$action" ]; then
      printf "%s\n" "$action"
      return 0
    fi
  fi
  echo "Inline diagnostics foundation: BuildService parsed events -> FileDiagnosticsStore -> editor consumers."
}

next_task() {
  require_vault
  echo "Recommended next task"
  echo "- $(recommended_next_action)"
  echo ""
  echo "Suggested Claude prompt"
  echo "- SPPStudioDocs/AgentPrompts/continue-current-sprint.md"
  echo ""
  echo "Architecture reminders"
  echo "- Read SPPStudioDocs/Architecture Contracts.md"
  echo "- Read SPPStudioDocs/Editor Invariants.md"
  echo "- Check SPPStudioDocs/Known Bad Patterns.md"
  echo ""
  echo "Unresolved regression warnings"
  unresolved_regression_summary
  echo ""
  echo "High severity regression warnings"
  high_severity_regression_summary
  echo ""
  echo "Runtime instability section"
  active_runtime_issues
  echo ""
  architecture_warnings
  echo ""
  echo "Required verification"
  echo "- swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio"
  echo "- ./script/review-last-change.sh before Codex review"
  echo "- Log build result with ./script/spp-workspace.sh build-log PASS|FAIL \"notes\""
  echo ""
  echo "Regression risk reminders"
  echo "- Check Known Failure Modes before broad rereads."
  echo "- If unsafe-to-continue is not safe, triage before implementation."
}

review_context() {
  require_vault
  echo "Codex Review Context"
  echo ""
  echo "Current focus"
  current_focus
  echo ""
  echo "Current milestone"
  current_milestone
  echo ""
  echo "Unsafe to continue"
  unsafe_to_continue
  echo ""
  echo "High severity regressions"
  high_severity_regression_summary
  echo ""
  echo "Runtime instability"
  active_runtime_issues
  echo ""
  echo "Architecture warnings"
  architecture_warnings
  echo ""
  echo "Known failure mode entrypoint"
  echo "- SPPStudioDocs/Known Failure Modes.md"
  echo ""
  echo "Review helper"
  echo "- ./script/review-last-change.sh"
}

verification_header() {
  local title="$1"
  echo "$title"
  echo ""
  echo "Flow reference: SPPStudioDocs/VerificationFlows/README.md"
  echo "Contracts: SPPStudioDocs/Editor Invariants.md, SPPStudioDocs/Architecture Contracts.md"
  echo "Failure modes: SPPStudioDocs/Known Failure Modes.md"
  echo ""
}

verify_editor_routing() {
  verification_header "Verify Editor Routing"
  cat <<'EOF'
Expected invariant:
- Active tab, active file identity, first responder, and command routing all point at the same editor.

Likely failure modes:
- Find/replace targets inactive editor.
- Runtime jump opens stale file.
- Completion suggestions use previous document context.

Steps:
1. Open two source files.
2. Place caret and selection in file A.
3. Switch to file B and place a different caret/selection.
4. Invoke find, undo/redo, and completion.
5. Confirm commands affect file B only.

Related:
- REG-2026-05-19-001
- Known Failure Modes: stale pooled NSTextView state, find/replace targeting inactive editor.
EOF
}

verify_pooled_editors() {
  verification_header "Verify Pooled Editors"
  cat <<'EOF'
Expected invariant:
- Switching tabs hides/reveals persistent NSTextViews; it does not recreate them.

Likely failure modes:
- Caret, scroll, undo, or selection resets after tab switch.
- Blank editor with visible line numbers.
- `.id(` or forced view recreation appears in editor code.

Steps:
1. Open file A, scroll to middle, make an edit, place caret.
2. Open file B, scroll elsewhere, make a different edit.
3. Switch A -> B -> A several times.
4. Undo in A, then B; confirm undo stacks are isolated.
5. Confirm scroll/caret persist per file.

Related:
- Editor Invariants: pooled NSTextView lifecycle.
- Known Bad Patterns: `.id(tabID)` editor recreation.
EOF
}

verify_find_routing() {
  verification_header "Verify Find/Replace Routing"
  cat <<'EOF'
Expected invariant:
- NSTextFinder/responder chain targets the active pooled editor only.

Likely failure modes:
- Find panel searches inactive tab.
- Replace mutates a hidden file.
- First responder remains stale after tab switch.

Steps:
1. Open two files with distinct repeated terms.
2. Activate file A and invoke find.
3. Switch to file B and invoke find again.
4. Replace one match in B.
5. Confirm file A is untouched and file B receives the edit.

Related:
- Known Failure Modes: find/replace targeting inactive editor.
- Editor Invariants: responder chain.
EOF
}

verify_diagnostics_lifecycle() {
  verification_header "Verify Diagnostics Lifecycle"
  cat <<'EOF'
Expected invariant:
- Diagnostics are owned by FileDiagnosticsStore by file/document identity and rendered with temporary attributes.

Likely failure modes:
- Diagnostics bleed across tabs/files.
- Permanent attributed-string mutation conflicts with syntax highlighting.
- BuildService becomes long-term diagnostics storage.

Steps:
1. Introduce a diagnostic in file A only.
2. Build and confirm diagnostic appears for file A.
3. Switch to file B and confirm no stale diagnostic appears.
4. Fix file A and rebuild.
5. Confirm diagnostic clears and temporary visuals disappear.

Related:
- Architecture Contracts: diagnostics ownership.
- Known Failure Modes: diagnostics bleeding, attributed-string ownership conflicts.
EOF
}

verify_runtime_linking() {
  verification_header "Verify Runtime/Editor Linking"
  cat <<'EOF'
Expected invariant:
- Runtime/build events route to editor targets through file/document identity, not cached NSTextView references.

Likely failure modes:
- Runtime event opens wrong file.
- Crash/log jump targets stale active editor.
- Runtime service starts owning editor state.

Steps:
1. Produce or select a runtime/build event that references a file or source location.
2. Switch active tabs before invoking jump.
3. Trigger jump-to-file.
4. Confirm correct file opens and caret/selection targets expected location.
5. Confirm previous active editor state is preserved.

Related:
- ArchitectureSnapshots/M6: runtime/editor interaction boundaries.
- Known Failure Modes: runtime/editor desync.
EOF
}

verify_completion_lifecycle() {
  verification_header "Verify Completion Lifecycle"
  cat <<'EOF'
Expected invariant:
- Completion context follows active document identity and cursor/selection range.

Likely failure modes:
- Stale completion state after tab switch.
- Completion cache becomes editor-owned truth.
- Project-wide index assumptions arrive before document-local behavior is stable.

Steps:
1. Open two files with different local symbols.
2. Trigger completion in file A.
3. Switch to file B and trigger completion at a different cursor context.
4. Confirm suggestions reflect file B only.
5. Switch back to A and confirm A context is restored.

Related:
- Editor Invariants: completion lifecycle.
- Known Failure Modes: stale completion state after tab switch.
EOF
}

verify_temp_attributes() {
  verification_header "Verify Temporary Attribute Cleanup"
  cat <<'EOF'
Expected invariant:
- Diagnostic visuals are temporary layout decoration and clear when diagnostics change.

Likely failure modes:
- Squiggles/colors remain after fix.
- Syntax highlighting and diagnostics overwrite each other.
- Permanent attributed-string mutation is used for diagnostics.

Steps:
1. Introduce a diagnostic with a visible marker.
2. Confirm marker appears.
3. Fix the diagnostic and rebuild.
4. Confirm marker clears without altering syntax highlighting.
5. Switch tabs and confirm no stale marker reappears.

Related:
- Editor Invariants: rendering.
- Known Failure Modes: attributed-string ownership conflicts.
EOF
}

inspection_header() {
  local title="$1"
  echo "$title"
  echo ""
  echo "Live dump: $RUNTIME_DUMP_FILE"
  echo "Trigger in app: Debug > Dump Runtime Invariants (⌃⌥⌘I)"
  echo "Contracts: SPPStudioDocs/Editor Invariants.md, SPPStudioDocs/Architecture Contracts.md"
  echo "Failure modes: SPPStudioDocs/Known Failure Modes.md"
  echo ""
}

print_runtime_dump_or_guidance() {
  if [ -f "$RUNTIME_DUMP_FILE" ]; then
    sed -n '1,220p' "$RUNTIME_DUMP_FILE"
  else
    echo "No runtime invariant dump found yet."
    echo "Open the app, focus the editor state under investigation, then run Debug > Dump Runtime Invariants."
  fi
}

runtime_snapshot_guidance() {
  echo "No runtime health snapshot source found."
  echo "Open the app, focus the runtime/editor state under investigation, then run Debug > Dump Runtime Invariants."
  echo "After the dump exists, run ./script/spp-workspace.sh snapshot-runtime-health \"label\"."
}

snapshot_runtime_health() {
  local label="${1:-manual}"
  local slug timestamp file
  slug="$(slugify "$label")"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  file="$STATE_RUNTIME_SNAPSHOTS/$timestamp-$slug.txt"

  if [ ! -f "$RUNTIME_DUMP_FILE" ]; then
    runtime_snapshot_guidance
    return 1
  fi

  mkdir -p "$STATE_RUNTIME_SNAPSHOTS"
  {
    echo "SPPStudio Runtime Health Artifact"
    echo "captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "label: $label"
    echo "source: $RUNTIME_DUMP_FILE"
    echo "$(git_status_line)"
    echo ""
    sed -n '1,220p' "$RUNTIME_DUMP_FILE"
  } >"$file"
  cp "$file" "$STATE_RUNTIME_LATEST_SNAPSHOT"

  echo "Created runtime health snapshot: $file"
  echo "Latest snapshot: $STATE_RUNTIME_LATEST_SNAPSHOT"
}

latest_runtime_snapshot_file() {
  find "$STATE_RUNTIME_SNAPSHOTS" -type f -name '*.txt' ! -name 'latest-snapshot.txt' 2>/dev/null | sort | tail -1 || true
}

latest_runtime_snapshot_summary() {
  local latest
  latest="$(latest_runtime_snapshot_file)"
  if [ -n "$latest" ] && [ -f "$latest" ]; then
    echo "$latest"
    snapshot_section_warnings "$latest" | sed 's/^/  /'
  else
    echo "none captured"
  fi
}

previous_runtime_snapshot_file() {
  find "$STATE_RUNTIME_SNAPSHOTS" -type f -name '*.txt' ! -name 'latest-snapshot.txt' 2>/dev/null | sort | tail -2 | head -1 || true
}

print_latest_runtime_snapshot() {
  local latest
  latest="$(latest_runtime_snapshot_file)"
  if [ -n "$latest" ] && [ -f "$latest" ]; then
    sed -n '1,220p' "$latest"
  else
    runtime_snapshot_guidance
    return 1
  fi
}

snapshot_field() {
  local file="$1"
  local key="$2"
  grep -m 1 -- "- $key:" "$file" 2>/dev/null | sed "s/^.*- $key:[[:space:]]*//" || true
}

snapshot_section_warnings() {
  local file="$1"
  awk '
    /^drift-warnings$/ { in_section=1; next }
    in_section && /^$/ { in_section=0 }
    in_section && /^- / { print }
  ' "$file" 2>/dev/null || true
}

snapshot_section() {
  local file="$1"
  local section="$2"
  awk -v target="$section" '
    $0 == target { in_section=1; next }
    in_section && /^$/ { in_section=0 }
    in_section { print }
  ' "$file" 2>/dev/null || true
}

compare_snapshot_field() {
  local baseline="$1"
  local candidate="$2"
  local key="$3"
  local label="$4"
  local before after
  before="$(snapshot_field "$baseline" "$key")"
  after="$(snapshot_field "$candidate" "$key")"
  if [ "$before" = "$after" ]; then
    echo "- ok: $label unchanged ($after)"
  else
    echo "- drift: $label changed from ${before:-missing} to ${after:-missing}"
  fi
}

compare_runtime_snapshots() {
  local baseline="${1:-}"
  local candidate="${2:-}"

  mkdir -p "$STATE_RUNTIME_SNAPSHOTS"
  if [ -z "$baseline" ]; then
    baseline="$(previous_runtime_snapshot_file)"
  fi
  if [ -z "$candidate" ]; then
    candidate="$(latest_runtime_snapshot_file)"
  fi

  if [ -z "$baseline" ] || [ -z "$candidate" ] || [ "$baseline" = "$candidate" ]; then
    echo "Need two runtime health snapshots to compare."
    echo "Run Debug > Dump Runtime Invariants in two states, then run:"
    echo "./script/spp-workspace.sh snapshot-runtime-health \"before\""
    echo "./script/spp-workspace.sh snapshot-runtime-health \"after\""
    return 1
  fi
  if [ ! -f "$baseline" ] || [ ! -f "$candidate" ]; then
    echo "Snapshot file missing."
    echo "- baseline: $baseline"
    echo "- candidate: $candidate"
    return 1
  fi

  echo "Runtime Drift Comparison"
  echo "- baseline: $baseline"
  echo "- candidate: $candidate"
  echo ""
  echo "Lifecycle fields"
  compare_snapshot_field "$baseline" "$candidate" "pooled-editor-count" "pooled editor count"
  compare_snapshot_field "$baseline" "$candidate" "visible-editor-count" "visible editor count"
  compare_snapshot_field "$baseline" "$candidate" "active-claim-count" "active ownership claim count"
  compare_snapshot_field "$baseline" "$candidate" "active-file-id" "active file identity"
  compare_snapshot_field "$baseline" "$candidate" "active-context-file-id" "completion context file identity"
  compare_snapshot_field "$baseline" "$candidate" "current-target-file-id" "runtime route target identity"
  compare_snapshot_field "$baseline" "$candidate" "responder-matches-active-editor" "responder match"
  compare_snapshot_field "$baseline" "$candidate" "identity" "active NSTextView identity"
  compare_snapshot_field "$baseline" "$candidate" "layout-manager" "active layout manager identity"
  compare_snapshot_field "$baseline" "$candidate" "text-storage" "active text storage identity"
  compare_snapshot_field "$baseline" "$candidate" "undo-manager" "active undo manager identity"
  compare_snapshot_field "$baseline" "$candidate" "layout-manager-text-storage-matches" "layout/text-storage relationship"
  compare_snapshot_field "$baseline" "$candidate" "text-storage-layout-manager-count" "text storage layout manager count"
  compare_snapshot_field "$baseline" "$candidate" "continuity-warning-count" "continuity warning count"
  echo ""
  echo "Candidate active drift indicators"
  snapshot_section "$candidate" "active-drift-indicators"
  echo ""
  echo "Baseline warnings"
  snapshot_section_warnings "$baseline"
  echo ""
  echo "Candidate warnings"
  snapshot_section_warnings "$candidate"
  echo ""
  echo "Review lens"
  echo "- Treat unexpected identity/count/responder changes as lifecycle drift, not proof of a bug by itself."
  echo "- Confirm drift with inspect-* and verify-* commands before changing ownership boundaries."
}

runtime_snapshot_workflow() {
  cat <<'EOF'
Runtime Snapshot Workflow

Purpose:
- Preserve a compact, deterministic runtime health artifact during editor/runtime investigations.
- Compare manually triggered states without background monitoring or telemetry storage.

Capture:
1. Open SPPStudio and focus the editor/runtime state under investigation.
2. Run Debug > Dump Runtime Invariants.
3. Run ./script/spp-workspace.sh snapshot-runtime-health "label"

Compare:
1. Capture a baseline snapshot.
2. Change only the state being investigated, such as tab switch or command route.
3. Capture a candidate snapshot.
4. Run ./script/spp-workspace.sh snapshot-runtime-drift

Scope:
- pooled editor graph
- responder ownership
- tab/file routing
- diagnostics/completion ownership summaries
- layout manager and text storage relationships
- identity continuity breadcrumbs
- compact drift warning summary
EOF
}

print_runtime_sections() {
  local title="$1"
  shift
  inspection_header "$title"
  if [ ! -f "$RUNTIME_DUMP_FILE" ]; then
    print_runtime_dump_or_guidance
    return 1
  fi
  awk -v sections="$*" '
    BEGIN {
      split(sections, wanted, " ")
      for (i in wanted) include[wanted[i]]=1
    }
    /^[[:alnum:]-]+$/ {
      current=$0
      printing=(current in include)
      if (printing) {
        if (seen++) print ""
        print current
      }
      next
    }
    printing { print }
  ' "$RUNTIME_DUMP_FILE"
}

verify_identity_continuity() {
  verification_header "Verify Identity Continuity"
  cat <<'EOF'
Expected invariant:
- Pooled editor identities remain stable across hide/reveal tab transitions.
- NSTextView, NSLayoutManager, NSTextStorage, and UndoManager identities do not reset during non-destructive updates.
- First responder follows the active pooled editor after tab switches.

Likely failure modes:
- NSTextView replacement hides lifecycle bugs.
- Layout/text-storage ownership changes break syntax, diagnostics, or selection.
- Undo history resets after tab switch.
- Responder chain points at the previous editor.

Steps:
1. Open two editable source files.
2. Focus file A and run Debug > Dump Runtime Invariants.
3. Run ./script/spp-workspace.sh snapshot-runtime-health "identity-a".
4. Switch to file B, then back to file A, and dump again.
5. Run ./script/spp-workspace.sh snapshot-runtime-health "identity-a-return".
6. Run ./script/spp-workspace.sh snapshot-runtime-drift.
7. Confirm identity-continuity is stable for file A unless the tab was closed or the project changed.

Related:
- Editor Invariants: identity continuity.
- Known Failure Modes: stale pooled NSTextView state, find/replace targeting inactive editor.
- REG-2026-05-19-001, REG-2026-05-19-002.
EOF
}

inspect_editor_identities() {
  print_runtime_sections "Inspect Editor Identities" editor-pool lifecycle-transition active-text-view identity-continuity continuity-summary active-drift-indicators drift-warnings
  cat <<'EOF'

Expected:
- textView identity is stable for an existing tab across hide/reveal cycles.
- tab/file identity remains paired unless the tab is intentionally closed or project state resets.

Likely violations:
- unexpected NSTextView replacement.
- tab/file identity continuity drift.
- multiple live editors for one logical tab.
EOF
}

inspect_layout_manager_chain() {
  print_runtime_sections "Inspect Layout Manager Chain" active-text-view layout-relationships identity-continuity drift-warnings
  cat <<'EOF'

Expected:
- layoutManager identity remains stable during tab switches and non-destructive editor updates.
- layoutManager.textStorage matches the active text storage.

Likely violations:
- layoutManager replacement suspicion.
- layout/text-storage relationship drift.
- more than one layout manager attached to one editor text storage.
EOF
}

inspect_text_storage_chain() {
  print_runtime_sections "Inspect Text Storage Chain" active-text-view layout-relationships identity-continuity diagnostics drift-warnings
  cat <<'EOF'

Expected:
- textStorage identity remains stable for a pooled editor while the tab is alive.
- diagnostics rendering stays temporary and does not take text storage ownership.

Likely violations:
- textStorage replacement suspicion.
- permanent diagnostic attributes competing with syntax highlighting.
- diagnostics stored on editor instances.
EOF
}

inspect_undo_manager_chain() {
  print_runtime_sections "Inspect Undo Manager Chain" active-text-view identity-continuity drift-warnings
  cat <<'EOF'

Expected:
- undoManager identity remains stable for a pooled editor while its tab is alive.
- undo/redo history is isolated per tab and survives tab switching.

Likely violations:
- UndoManager identity reset suspicion.
- tab switch recreated the editor.
- undo targets the wrong responder.
EOF
}

inspect_editor_state() {
  inspection_header "Inspect Editor State"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- active-tab-id and active-file-id are present when an editor tab is active.
- active-text-view identity exists for exactly one active visible editor.

Likely violations:
- active tab has no visible NSTextView claim.
- active tab/file identity mismatch.
- multiple active editor ownership claims.
EOF
}

inspect_responder_chain() {
  inspection_header "Inspect Responder Chain"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- first-responder is an NSTextView when editor commands should target the editor.
- responder-matches-active-editor is true after tab switches.

Likely violations:
- stale first responder after tab switch.
- find/replace, undo, redo, or completion targets an inactive editor.
EOF
}

inspect_diagnostics() {
  inspection_header "Inspect Diagnostics Ownership"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- diagnostics snapshot-owner remains FileDiagnosticsStore.
- editor-owned-diagnostics-state remains absent.
- rendering-owner stays NSLayoutManager temporary attributes/layout drawing.

Likely violations:
- diagnostics stored on CodeEditorView, Coordinator, NSTextView, or tab state.
- permanent attributed-string mutation used for diagnostic visuals.
EOF
}

inspect_runtime_routing() {
  inspection_header "Inspect Runtime Routing"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- runtime route target is file/document identity.
- current-target-file-id agrees with the active file when a runtime jump is invoked.

Likely violations:
- runtime service caches NSTextView references.
- jump-to-file targets the previous active editor.
EOF
}

inspect_completion_context() {
  inspection_header "Inspect Completion Context"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- completion context owner is active document identity plus selection range.
- active-context-file-id changes on tab switch.

Likely violations:
- stale completion suggestions after tab switch.
- completion cache becomes editor-owned truth.
EOF
}

inspect_editor_pool() {
  inspection_header "Inspect Editor Pool"
  print_runtime_dump_or_guidance
  cat <<'EOF'

Expected:
- pooled-editor-count equals the number of open editor tabs.
- visible-editor-count is 1 when an editor tab is active.
- visible view hierarchy lists only the active editor.

Likely violations:
- pooled editors recreated during tab switches.
- multiple visible editors.
- released editor state remains registered.
EOF
}

write_command_center() {
  require_vault
  mkdir -p "$COMMAND_CENTER_DIR" "$AI_COORDINATION_DIR" "$PROMPT_ENGINEERING_DIR" "$RUNTIME_OPS_DIR"

  cat >"$COMMAND_CENTER_DIR/Engineering Dashboard.md" <<'EOF'
# SPPStudio Engineering Cockpit

Purpose: restore operational context fast enough to keep editor/runtime invariants intact.

## Live State
![[Current Operating State]]

## Command Surfaces
- [[Subsystem Pressure]]
- [[Unsafe Mutation Zones]]
- [[Current Runtime Shape]]
- [[AI Workflow Control]]
- [[../50_RuntimeOps/Runtime Awareness]]
- [[../50_RuntimeOps/Runtime Relationship Graph]]
- [[../50_RuntimeOps/Architecture Pressure Memory]]
- [[../50_RuntimeOps/Failure Prediction Heuristics]]
- [[../50_RuntimeOps/Engineering Cognition Loop]]
- [[../50_RuntimeOps/Externalized Observability Doctrine]]
- [[../40_PromptEngineering/Prompt Cockpit]]

## Canonical Truth
- [[../Sprints/current-sprint|Current Sprint]]
- [[../ImplementationLog/active-implementation|Active Implementation]]
- [[../Regressions/regression-tracker|Regression Tracker]]
- [[../Architecture Contracts]]
- [[../Editor Invariants]]
- [[../Known Failure Modes]]
- [[../VerificationFlows/README|Verification Flows]]

## Required Recovery Commands
```bash
./script/spp-workspace.sh command-center
./script/spp-workspace.sh restore
./script/spp-workspace.sh unsafe-to-continue
./script/spp-workspace.sh review-context
./script/spp-workspace.sh snapshot-runtime-latest
```
EOF

  {
    echo "# Current Operating State"
    echo ""
    echo "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Repo: $ROOT_DIR"
    echo "- $(git_status_line)"
    echo "- Current subsystem: $(active_subsystem)"
    echo "- Current sprint: $(current_focus)"
    echo "- Current milestone: $(current_milestone)"
    echo "- Latest build: $(latest_build)"
    echo ""
    echo "## Unsafe To Continue"
    unsafe_to_continue
    echo ""
    echo "## Active Regressions"
    unresolved_regression_summary
    echo ""
    echo "## Runtime Instability"
    active_runtime_issues
    echo ""
    echo "## Latest Runtime Snapshot"
    latest_runtime_snapshot_summary
    echo ""
    echo "## Latest Continuity Drift Indicators"
    latest="$(latest_runtime_snapshot_file)"
    if [ -n "$latest" ] && [ -f "$latest" ]; then
      snapshot_section "$latest" "active-drift-indicators"
    else
      echo "- none captured"
    fi
    echo ""
    echo "## Invariants Under Pressure"
    echo "- Pooled NSTextView lifecycle"
    echo "- Identity continuity: NSTextView, NSLayoutManager, NSTextStorage, UndoManager"
    echo "- Responder-chain correctness"
    echo "- Diagnostics ownership by file/document identity"
    echo "- Runtime/editor routing by file/document identity"
    echo "- Temporary attributes only for diagnostic rendering"
    echo "- Externalized observability: dumps, snapshots, dashboards, command reports"
    echo ""
    echo "## Next AI Actions"
    echo "- Claude: implement the next narrow editor/runtime task, then build and verify."
    echo "- Codex: review for lifecycle, ownership, routing, and noise inflation regressions."
    echo "- ChatGPT: refine prompts and operational workflows when context starts to blur."
    echo ""
    echo "## Verification Requirements"
    echo "- swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio"
    echo "- ./script/spp-workspace.sh doctor"
    echo "- ./script/spp-workspace.sh restore"
    echo "- ./script/review-last-change.sh"
    echo "- relevant inspect-* and verify-* command set"
  } >"$COMMAND_CENTER_DIR/Current Operating State.md"

  cat >"$COMMAND_CENTER_DIR/Subsystem Pressure.md" <<'EOF'
# Subsystem Pressure

Use this page as an operational pressure map, not a project-management board.

| Pressure Surface | Current Risk | Primary Inspection |
|---|---|---|
| Editor pooling | Critical if identities reset or multiple editors become visible | `inspect-editor-identities`, `inspect-editor-pool` |
| Runtime routing | High if runtime jumps use stale active file/editor state | `inspect-runtime-routing`, `verify-runtime-linking` |
| Diagnostics lifecycle | Critical if diagnostics attach to editors or permanent attributes | `inspect-diagnostics`, `verify-diagnostics-lifecycle` |
| Completion ownership | High if suggestions follow stale document identity | `inspect-completion-context`, `verify-completion-lifecycle` |
| Responder chain | Critical for find/undo/completion routing | `inspect-responder-chain`, `verify-editor-routing` |
| Layout/text storage | Critical if relationships drift during tab switches | `inspect-layout-manager-chain`, `inspect-text-storage-chain` |

Pressure rules:
- Investigate pressure with snapshots before changing ownership boundaries.
- Treat warnings as leads, not enforcement.
- Prefer one narrow owner fix over new coordination layers.
EOF

  cat >"$COMMAND_CENTER_DIR/Unsafe Mutation Zones.md" <<'EOF'
# Unsafe Mutation Zones

These files and systems are safe to edit only with a clear invariant target and immediate verification.

## Critical Files
- `Apps/SwiftPlaygroundPlusPlusStudio/Sources/IDE/Editor/EditorAreaView.swift`
- `Apps/SwiftPlaygroundPlusPlusStudio/Sources/IDE/Editor/RuntimeInvariantInspector.swift`
- `Apps/SwiftPlaygroundPlusPlusStudio/Sources/Services/BuildService.swift`
- `Apps/SwiftPlaygroundPlusPlusStudio/Sources/Services/ProjectService.swift`
- `script/spp-workspace.sh`
- `script/review-last-change.sh`

## Dangerous Mutations
- Recreating `NSTextView`, `NSScrollView`, `NSLayoutManager`, `NSTextStorage`, or `UndoManager` for refresh.
- Moving diagnostics into editor instances.
- Making runtime/build services cache editor views.
- Turning inspector output into routing or ownership truth.
- Adding SwiftUI overlays for editor annotations.
- Adding background monitoring or telemetry for lifecycle state.
- Reassigning layout managers or text storage outside explicit tab teardown/reload.
- Retaining editor views strongly from services, snapshots, or dashboards.
- Moving observability into the editor render path.

## Required Lens
- Does this preserve pooled editor identity?
- Does this keep ownership in the canonical subsystem?
- Does this remain manually triggered and observational?
- Does this keep recovery deterministic?
EOF

  cat >"$COMMAND_CENTER_DIR/Current Runtime Shape.md" <<'EOF'
# Current Runtime Shape

## Ownership Map
- `BuildService` emits structured build/runtime events only.
- `FileDiagnosticsStore` owns diagnostics by file/document identity.
- `EditorCoordinator` routes active editor/file context.
- Pooled `NSTextView` instances render and interact only.
- `NSLayoutManager` / `NSTextStorage` provide temporary decoration and text layout relationships.
- SwiftUI owns shell/container composition only.
- `RuntimeInvariantInspector` observes identities and emits advisory warnings only.

## Routing Shape
Runtime/build event -> file/document identity -> editor routing -> active pooled editor.

The reverse path is forbidden: runtime services must not cache editor views as truth.

## Verification Topology
- Identity continuity: `inspect-editor-identities`, `verify-identity-continuity`
- Layout/text chain: `inspect-layout-manager-chain`, `inspect-text-storage-chain`
- Responder chain: `inspect-responder-chain`, `verify-editor-routing`
- Diagnostics lifecycle: `inspect-diagnostics`, `verify-diagnostics-lifecycle`
- Runtime routing: `inspect-runtime-routing`, `verify-runtime-linking`
- Externalized observability: `snapshot-runtime-health`, `snapshot-runtime-drift`, `review-last-change.sh`

## Continuity-Sensitive Systems
- `EditorAreaView` pooled AppKit bridge.
- `RuntimeInvariantInspector` weak identity observation.
- `BuildService` event emission and routing boundaries.
- Diagnostics ownership and temporary rendering pipeline.
- Responder chain and find/undo/completion command routing.

## Compact Runtime Evidence
- Live dump: `~/Library/Caches/SPPStudio/runtime-invariants/latest.txt`
- Snapshot artifacts: `script/state/runtime-snapshots/`
- Comparison: `./script/spp-workspace.sh snapshot-runtime-drift`
EOF

  cat >"$COMMAND_CENTER_DIR/AI Workflow Control.md" <<'EOF'
# AI Workflow Control

## Role Boundaries
- Codex: architecture supervisor, reviewer, invariant protection, regression detection.
- Claude: implementation, build execution, verification, tracker updates.
- ChatGPT: prompt engineering, systems reasoning, workflow refinement.

## Handoff Rule
Every handoff must answer:
- What subsystem is active?
- What invariant is under pressure?
- What changed last?
- What verification passed?
- What is unsafe to touch casually?
- What is the next narrow action?

## Prompt Flow
- Claude prompt: [[../AgentPrompts/implement-next-feature]]
- Codex prompt: [[../AgentPrompts/review-latest-diff]]
- ChatGPT prompt workbench: [[../40_PromptEngineering/Prompt Cockpit]]
EOF

  cat >"$PROMPT_ENGINEERING_DIR/Prompt Cockpit.md" <<'EOF'
# Prompt Cockpit

Goal: keep AI prompts operational, role-specific, and grounded in canonical context.

## Active Prompt Queue
- Claude implementation: preserve pooled editor identity, implement one narrow subsystem, build immediately.
- Codex review: inspect lifecycle, ownership, routing, identity continuity, and review-helper noise.
- ChatGPT prompt architect: refine prompts when session continuity or AI role boundaries start to blur.

## Prompt Families
- [[../AgentPrompts/continue-current-sprint]]
- [[../AgentPrompts/implement-next-feature]]
- [[../AgentPrompts/review-latest-diff]]
- [[../AgentPrompts/diagnose-runtime-regression]]
- [[../AgentPrompts/verify-editor-invariants]]
- [[../AgentPrompts/write-session-handoff]]

## Prompt Rules
- Link canonical docs instead of pasting the vault.
- Name the invariant under pressure.
- Include exact verification commands.
- Keep role boundaries explicit.
EOF

  cat >"$RUNTIME_OPS_DIR/Runtime Awareness.md" <<'EOF'
# Runtime Awareness

Purpose: compact operational visibility into editor/runtime health without telemetry or background monitoring.

## Manual Evidence Loop
1. Focus the app state under investigation.
2. Run `Debug > Dump Runtime Invariants`.
3. Capture with `./script/spp-workspace.sh snapshot-runtime-health "label"`.
4. Compare with `./script/spp-workspace.sh snapshot-runtime-drift`.
5. Use focused `inspect-*` commands before changing code.

## Runtime Surfaces
- Pooled editor graph.
- Active responder ownership.
- Tab/file routing.
- Diagnostics ownership summary.
- Completion context summary.
- Layout manager and text storage relationships.
- Identity continuity breadcrumbs.

## Non-Goals
- No telemetry.
- No background monitoring.
- No automatic healing.
- No inspector-as-owner behavior.
EOF

  cat >"$RUNTIME_OPS_DIR/Externalized Observability Doctrine.md" <<'EOF'
# Externalized Observability Doctrine

Purpose: keep runtime/editor observability useful without entering the editor render path.

## Allowed Observability
- Manual runtime dumps.
- Runtime health snapshots.
- Topology snapshots.
- Obsidian dashboards generated from command output.
- Review-helper reports.
- Focused `inspect-*` and `verify-*` commands.

## Forbidden Observability
- SwiftUI overlays over `NSTextView`.
- Always-on visual instrumentation.
- Background monitoring loops.
- Telemetry collection.
- Render-path probes.
- Inspector-driven routing or repair.
- Strong editor retention from observers.

## Boundary Rule
Observability may explain lifecycle state. It may not participate in lifecycle timing, command routing, editor ownership, or rendering.
EOF

  cat >"$RUNTIME_OPS_DIR/Runtime Relationship Graph.md" <<'EOF'
# Runtime Relationship Graph

Purpose: preserve a compact conceptual model of how editor/runtime subsystems influence each other.

This is not a graph database, telemetry model, or ownership source. It is an operational reasoning map.

## Core Relationships

```text
BuildService
  -> structured build/runtime events
  -> FileDiagnosticsStore
  -> editor consumers by file/document identity

Runtime events
  -> file/document identity
  -> EditorCoordinator route
  -> active pooled NSTextView

EditorCoordinator
  -> active tab/file identity
  -> responder expectations
  -> completion context

Pooled NSTextView
  -> interaction/rendering only
  -> NSTextStorage
  -> NSLayoutManager
  -> UndoManager

RuntimeInvariantInspector
  -> observes identities
  -> emits advisory warnings
  -> never routes, heals, or owns truth
```

## Dangerous Couplings
- Runtime service caching `NSTextView`.
- Diagnostics attached to editor instances.
- Completion context stored as global active editor state.
- SwiftUI refresh replacing AppKit editor identity.
- Inspector output used as operational truth.

## Reasoning Rule
When a change touches one node, inspect the downstream relationship before editing adjacent owners.
EOF

  cat >"$RUNTIME_OPS_DIR/Architecture Pressure Memory.md" <<'EOF'
# Architecture Pressure Memory

Purpose: accumulate architectural intuition about which subsystems repeatedly carry risk.

This page should stay concise. Add pressure observations only when a build, review, runtime dump, or regression gives evidence.

## Current Pressure Surfaces

| Surface | Pressure Signal | Evidence Source | Current Posture |
|---|---|---|---|
| Editor pooling | Identity reset would collapse undo/caret/scroll isolation | REG-2026-05-19-001, runtime snapshots | Critical guardrail |
| Project state reset | Orphaned tabs can survive project transitions | REG-2026-05-19-002 | Fixed, watch project switches |
| Build console rendering | Trimmed logs can look current while stale | REG-2026-05-19-003 | Fixed, watch render gating |
| Diagnostics lifecycle | Upcoming work will stress file/document ownership | Current sprint | High attention |
| Runtime routing | Simulator/runtime events can drift from active file identity | M6 direction | High attention |
| Identity continuity | Silent AppKit replacement can hide regressions | Runtime invariant work | Critical guardrail |

## Pressure Update Rule
- Record the subsystem.
- Name the invariant under pressure.
- Link evidence, not vibes.
- Prefer one sentence over a long report.
EOF

  cat >"$RUNTIME_OPS_DIR/Failure Prediction Heuristics.md" <<'EOF'
# Failure Prediction Heuristics

Purpose: surface likely regression zones before they become catastrophic editor/runtime bugs.

These are review heuristics, not automated enforcement.

## Heuristics

| Signal | Likely Failure | First Check |
|---|---|---|
| `NSTextView` or `NSScrollView` lifecycle code changed | editor recreation, undo/caret loss | `verify-pooled-editors` |
| `NSLayoutManager` or `NSTextStorage` relationship changed | syntax/diagnostics/render drift | `inspect-layout-manager-chain` |
| `UndoManager` behavior changed | undo reset or cross-tab undo | `inspect-undo-manager-chain` |
| responder-chain code changed | find/replace/undo targets inactive editor | `inspect-responder-chain` |
| diagnostics fields added near editor state | diagnostics bleed across tabs | `inspect-diagnostics` |
| runtime code references active editor/view | runtime/editor ownership inversion | `inspect-runtime-routing` |
| inspector gains mutation/routing behavior | inspector ownership creep | review `RuntimeInvariantInspector` |
| review helper output expands sharply | signal loss and process noise | trim scan terms |

## Prediction Rule
Flag architectural risk when two or more signals touch the same ownership boundary in one change.
EOF

  cat >"$RUNTIME_OPS_DIR/Engineering Cognition Loop.md" <<'EOF'
# Engineering Cognition Loop

Purpose: turn repeated verification, regressions, and runtime snapshots into durable architectural understanding.

## Loop
1. Observe: run focused `inspect-*`, `verify-*`, build, doctor, and review commands.
2. Relate: identify which subsystem relationship is under pressure.
3. Explain: name the ownership or lifecycle invariant involved.
4. Record: update pressure memory or known failure modes only when evidence exists.
5. Act: make the smallest owner-correct change.
6. Verify: capture before/after evidence when lifecycle continuity is involved.

## Inputs
- Runtime snapshots.
- Regression tracker.
- Known failure modes.
- Review helper warnings.
- Verification artifacts.
- Session handoffs.

## Outputs
- Better prompts.
- Sharper review lenses.
- More accurate unsafe mutation zones.
- Faster recovery.
- Fewer ownership-boundary regressions.

## Guardrail
The cockpit may improve reasoning quality over time. It must not become autonomous execution, telemetry, or hidden policy enforcement.
EOF

  echo "Wrote command center: $COMMAND_CENTER_DIR"
}

write_session_state() {
  require_vault
  local focus subsystem build milestone next_action open_regressions high_regressions runtime_count
  focus="$(grep -m 1 "^## Sprint Goal" -A1 "$VAULT_DIR/70_SessionContinuity/Sprints/current-sprint.md" | tail -1)"
  subsystem="$(active_subsystem)"
  build="$(latest_build)"
  milestone="$(current_milestone)"
  next_action="$(recommended_next_action)"
  open_regressions="$(unresolved_regressions | wc -l | tr -d ' ')"
  high_regressions="$(high_severity_regressions | wc -l | tr -d ' ')"
  runtime_count="$(active_runtime_issue_rows | wc -l | tr -d ' ')"

  {
    echo "{"
    echo "  \"date\": \"$TODAY\","
    echo "  \"current_focus\": \"${focus//\"/\\\"}\","
    echo "  \"active_subsystem\": \"${subsystem//\"/\\\"}\","
    echo "  \"current_milestone\": \"${milestone//\"/\\\"}\","
    echo "  \"last_successful_build\": \"${build//\"/\\\"}\","
    echo "  \"open_regressions\": $open_regressions,"
    echo "  \"high_severity_regressions\": $high_regressions,"
    echo "  \"active_runtime_issue_count\": $runtime_count,"
    echo "  \"recommended_next_action\": \"${next_action//\"/\\\"}\","
    echo "  \"architecture_warnings\": ["
    echo "    \"Preserve pooled NSTextView lifecycle\","
    echo "    \"Diagnostics belong to FileDiagnosticsStore by file/document identity\","
    echo "    \"Use temporary layout attributes for diagnostics\","
    echo "    \"Avoid SwiftUI editor overlays and fake abstraction growth\""
    echo "  ]"
    echo "}"
  } >"$SESSION_JSON"

  printf "%s\n" "$subsystem" >"$STATE_ACTIVE_SUBSYSTEM"
  printf "%s\n" "$build" >"$STATE_LAST_BUILD"
  {
    echo "# High Severity Regressions"
    echo ""
    high_severity_regression_summary
  } >"$STATE_HIGH_REGRESSIONS"
  {
    echo "# Current Focus"
    echo ""
    echo "$focus"
    echo ""
    echo "- Milestone: $milestone"
    echo "- Active subsystem: $subsystem"
  } >"$STATE_CURRENT_FOCUS"
  {
    echo "# Architecture Warnings"
    echo ""
    architecture_warnings
  } >"$STATE_ARCH_WARNINGS"
  printf "%s\n" "$next_action" >"$STATE_NEXT_ACTION"
  {
    echo "# Last Verification"
    echo ""
    echo "- Latest build: $build"
    echo "- Doctor: run ./script/spp-workspace.sh doctor"
    echo "- Review helper: run ./script/review-last-change.sh"
  } >"$STATE_LAST_VERIFICATION"
  {
    echo "# Runtime Instability"
    echo ""
    active_runtime_issues
  } >"$STATE_RUNTIME_NOTES"
}

doctor() {
  require_vault
  echo "SPPStudio workspace doctor"
  echo "repo: $ROOT_DIR"
  echo "vault: $VAULT_DIR"
  echo ""

  local tools=(swift xcode-select rg curl claude npx)
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "ok: $tool"
    else
      echo "missing: $tool"
    fi
  done

  echo ""
  [ -f "$VAULT_DIR/.obsidian/plugins/obsidian-local-rest-api/manifest.json" ] && echo "ok: Obsidian Local REST API plugin installed" || echo "missing: Local REST API plugin"
  [ -f "$ROOT_DIR/.mcp.json" ] && echo "ok: project MCP config present" || echo "missing: .mcp.json"
  [ -f "$VAULT_DIR/70_SessionContinuity/Sprints/current-sprint.md" ] && echo "ok: current sprint note present" || echo "missing: current sprint note"
  [ -f "$VAULT_DIR/50_RuntimeOps/Regressions/regression-tracker.md" ] && echo "ok: regression tracker present" || echo "missing: regression tracker"
  [ -f "$VAULT_DIR/00_CommandCenter/Engineering Dashboard.md" ] && echo "ok: engineering dashboard present" || echo "missing: engineering dashboard"
  [ -f "$COMMAND_CENTER_DIR/Engineering Dashboard.md" ] && echo "ok: command center cockpit present" || echo "missing: command center cockpit"
  [ -f "$VAULT_DIR/20_ArchitectureMemory/Architecture Contracts.md" ] && echo "ok: architecture contracts present" || echo "missing: architecture contracts"

  echo ""
  rest_status || true
  mcp_status || true
  git_status_line
}

restore() {
  require_vault
  write_session_state
  {
    echo "# Current Session"
    echo ""
    echo "- Date: $TODAY"
    echo "- Repo: $ROOT_DIR"
    echo "- Vault: $VAULT_DIR"
    echo "- Sprint: SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md"
    echo "- Active implementation: SPPStudioDocs/ImplementationLog/active-implementation.md"
    echo "- Regressions: SPPStudioDocs/Regressions/regression-tracker.md"
    echo "- Unresolved bugs: SPPStudioDocs/Issues/unresolved-bugs.md"
    echo "- Dashboard: SPPStudioDocs/00_CommandCenter/Engineering Dashboard.md"
    echo "- State JSON: script/state/current-session.json"
    echo "- Current focus: script/state/current-focus.md"
    echo "- Active subsystem: script/state/active-subsystem.txt"
    echo "- Last build: script/state/last-successful-build.md"
    echo "- High regressions: script/state/high-severity-regressions.md"
    echo "- Runtime notes: script/state/runtime-instability.md"
    echo "- Current milestone: $(current_milestone)"
    echo "- Active subsystem: $(active_subsystem)"
    echo "- Last successful build: $(latest_build)"
    echo ""
    echo "## Startup Reading"
    echo "- PROJECT_CONTEXT.md"
    echo "- SPPStudioDocs/Home.md"
    echo "- SPPStudioDocs/00_CommandCenter/Engineering Dashboard.md"
    echo "- SPPStudioDocs/00_CommandCenter/Current Operating State.md"
    echo "- SPPStudioDocs/70_SessionContinuity/Sprints/current-sprint.md"
    echo "- SPPStudioDocs/Architecture Contracts.md"
    echo "- SPPStudioDocs/Editor Invariants.md"
    echo "- SPPStudioDocs/Known Failure Modes.md"
    echo ""
    echo "## Recommended Prompt"
    echo "- SPPStudioDocs/AgentPrompts/continue-current-sprint.md"
    echo ""
    echo "## Recommended Next Action"
    echo "- $(recommended_next_action)"
    echo ""
    echo "## High Severity Regression Warnings"
    high_severity_regression_summary
    echo ""
    echo "## Unsafe To Continue"
    unsafe_to_continue
    echo ""
    echo "## Runtime Instability"
    active_runtime_issues
    echo ""
    echo "## Architecture Warnings"
    architecture_warnings
  } >"$SESSION_INDEX"

  echo "Restored session context: $SESSION_INDEX"
  status
}

status() {
  require_vault
  echo "Workspace"
  git_status_line
  echo ""
  echo "Command center"
  if [ -f "$COMMAND_CENTER_DIR/Engineering Dashboard.md" ]; then
    sed -n '1,140p' "$COMMAND_CENTER_DIR/Engineering Dashboard.md"
  else
    sed -n '1,120p' "$VAULT_DIR/Engineering Dashboard.md"
  fi
  echo ""
  echo "Current sprint"
  sed -n '1,120p' "$VAULT_DIR/70_SessionContinuity/Sprints/current-sprint.md"
  echo ""
  echo "Current milestone"
  current_milestone
  echo ""
  echo "Current focus"
  current_focus
  echo ""
  echo "Unresolved regressions"
  unresolved_regression_summary
  echo ""
  echo "High severity regression warnings"
  high_severity_regression_summary
  echo ""
  echo "Unsafe to continue"
  unsafe_to_continue
  echo ""
  echo "Runtime instability section"
  active_runtime_issues
  echo ""
  echo "Latest build"
  latest_build
  echo ""
  next_task
  echo ""
  echo "Active implementation"
  sed -n '1,120p' "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md"
}

summary() {
  require_vault
  local topic="${1:-session}"
  local slug
  slug="$(slugify "$topic")"
  local file="$VAULT_DIR/SessionSummaries/$TODAY-$slug.md"

  {
    echo "# Session: $TODAY - $topic"
    echo ""
    echo "## Goal"
    echo "- $topic"
    echo ""
    echo "## Changed"
    echo "- "
    echo ""
    echo "## Verified"
    echo "- "
    echo ""
    echo "## Open Issues"
    echo "- See [[Issues/unresolved-bugs]] and [[Regressions/regression-tracker]]."
    echo ""
    echo "## Next Session"
    echo "- Continue from [[70_SessionContinuity/Sprints/current-sprint]]."
  } >"$file"

  append_line "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md" "- $TODAY: Created session summary [[SessionSummaries/$TODAY-$slug]]."
  echo "Created $file"
}

regression() {
  require_vault
  local area="${1:-Unknown}"
  local severity="${2:-Medium}"
  local symptom="${3:-No symptom provided}"
  local count id
  count="$(grep -c "^| REG-$TODAY" "$VAULT_DIR/50_RuntimeOps/Regressions/regression-tracker.md" || true)"
  id="REG-$TODAY-$(printf "%03d" "$((count + 1))")"
  append_line "$VAULT_DIR/50_RuntimeOps/Regressions/regression-tracker.md" "| $id | $area | $severity | Open | $TODAY | Unassigned | $symptom |"
  append_line "$VAULT_DIR/Bugs/known-regressions.md" "- [ ] $id: $symptom"
  echo "Logged $id"
}

issue() {
  require_vault
  local priority="${1:-Medium}"
  local symptom="${2:-No issue provided}"
  append_line "$VAULT_DIR/Issues/unresolved-bugs.md" "- [ ] $priority: $symptom"
  echo "Logged issue"
}

runtime() {
  require_vault
  local area="${1:-Runtime}"
  local severity="${2:-High}"
  local symptom="${3:-No runtime symptom provided}"
  append_line "$VAULT_DIR/50_RuntimeOps/RuntimeIssues/editor-runtime-issues.md" "- $TODAY [$severity] $area - $symptom"
  echo "Logged runtime issue"
}

artifact() {
  require_vault
  local kind="${1:-build-results}"
  local topic="${2:-verification}"
  local notes="${3:-No notes provided}"
  local slug file dir
  slug="$(slugify "$topic")"
  dir="$VAULT_DIR/VerificationArtifacts/$kind"
  mkdir -p "$dir"
  file="$dir/$TODAY-$slug.md"
  {
    echo "# Verification Artifact: $TODAY - $topic"
    echo ""
    echo "- Kind: $kind"
    echo "- Notes: $notes"
    echo "- Latest build: $(latest_build)"
    echo ""
    echo "## Context"
    echo "- Dashboard: [[Engineering Dashboard]]"
    echo "- Architecture: [[Architecture Contracts]]"
    echo "- Invariants: [[Editor Invariants]]"
  } >"$file"
  echo "Created $file"
}

milestone() {
  require_vault
  local title="${1:-Untitled milestone}"
  append_line "$VAULT_DIR/70_SessionContinuity/Milestones/completed-milestones.md" "- $TODAY: $title"
  append_line "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md" "- $TODAY: Completed milestone: $title."
  echo "Logged milestone"
}

build_log() {
  require_vault
  local result="${1:-PASS}"
  local notes="${2:-no notes}"
  local target="${3:-SwiftPlaygroundPlusPlusStudio}"
  local log_file="$VAULT_DIR/60_DeliveryValidation/BuildNotes/build-validation-log.md"
  local entry="| $TODAY | $result | $target | $notes |"
  # Append after the last table row (line starting with "| 20")
  if grep -q "^| 20" "$log_file" 2>/dev/null; then
    local last_row
    last_row="$(grep -n "^| 20" "$log_file" | tail -1 | cut -d: -f1)"
    sed -i '' "${last_row}a\\
$entry" "$log_file"
  else
    append_line "$log_file" "$entry"
  fi
  echo "Logged build: $result — $notes"
}

handoff() {
  require_vault
  local next_task="${1:-Continue from current sprint}"
  local file="$VAULT_DIR/SessionSummaries/$TODAY-handoff.md"
  {
    echo "# Session Handoff: $TODAY"
    echo ""
    echo "## Restore"
    echo "- Dashboard: [[Engineering Dashboard]]"
    echo "- Sprint: [[Current Sprint]]"
    echo "- Regressions: [[Regression Tracker]]"
    echo "- Architecture: [[Architecture Contracts]]"
    echo ""
    echo "## Next Task"
    echo "- $next_task"
    echo ""
    echo "## Severity Lens"
    echo "- Critical: pooled NSTextView lifecycle, editor state bleed, diagnostics ownership, NSTextStorage ownership."
    echo "- High: build console rendering, runtime/editor routing, completion ownership."
    echo ""
    echo "## Prompt"
    echo "- [[AgentPrompts/continue-current-sprint]]"
    echo ""
    echo "## Warnings"
    unresolved_regressions
    echo ""
    echo "## Verification"
    latest_build
  } >"$file"
  append_line "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md" "- $TODAY: Wrote handoff [[SessionSummaries/$TODAY-handoff]]."
  echo "Created $file"
}

adr() {
  require_vault
  local title="${1:-Untitled decision}"
  local decision="${2:-Decision not specified}"
  local reason="${3:-Reason not specified}"
  local adr_file="$VAULT_DIR/Architecture/architecture-decisions.md"
  local count
  count="$(grep -c "^## AD-" "$adr_file" || true)"
  local id
  id="AD-$(printf "%03d" "$((count + 1))")"
  {
    echo ""
    echo "## $id: $title"
    echo "**Decision:** $decision"
    echo "**Reason:** $reason"
    echo "**Tradeoffs:** (fill in)"
  } >>"$adr_file"
  echo "Logged $id: $title"
}

sprint_close() {
  require_vault
  local summary_text="${1:-Sprint closed}"
  local history_file="$VAULT_DIR/70_SessionContinuity/Sprints/sprint-history.md"
  local sprint_file="$VAULT_DIR/70_SessionContinuity/Sprints/current-sprint.md"
  {
    echo ""
    echo "## Sprint closed: $TODAY"
    echo "**Summary:** $summary_text"
    echo ""
    echo "See [[SessionSummaries]] for session details."
    echo ""
    echo "---"
  } >>"$history_file"
  append_line "$VAULT_DIR/70_SessionContinuity/ImplementationLog/active-implementation.md" "- $TODAY: Sprint closed. $summary_text"
  echo "Sprint closed and logged to $history_file"
  echo "Update $sprint_file with the new sprint goal."
}

case "${1:-status}" in
  doctor) doctor ;;
  restore) restore ;;
  status) status ;;
  regressions) unresolved_regression_summary ;;
  high-regressions) high_severity_regression_summary ;;
  runtime-issues) active_runtime_issues ;;
  milestone-current) current_milestone ;;
  current-focus) current_focus ;;
  latest-build) latest_build ;;
  next-task) next_task ;;
  architecture-warnings) architecture_warnings ;;
  unsafe-to-continue) unsafe_to_continue ;;
  review-context) review_context ;;
  verify-editor-routing) verify_editor_routing ;;
  verify-pooled-editors) verify_pooled_editors ;;
  verify-find-routing) verify_find_routing ;;
  verify-diagnostics-lifecycle) verify_diagnostics_lifecycle ;;
  verify-runtime-linking) verify_runtime_linking ;;
  verify-completion-lifecycle) verify_completion_lifecycle ;;
  verify-temp-attributes) verify_temp_attributes ;;
  verify-identity-continuity) verify_identity_continuity ;;
  inspect-editor-state) inspect_editor_state ;;
  inspect-responder-chain) inspect_responder_chain ;;
  inspect-diagnostics) inspect_diagnostics ;;
  inspect-runtime-routing) inspect_runtime_routing ;;
  inspect-completion-context) inspect_completion_context ;;
  inspect-editor-pool) inspect_editor_pool ;;
  inspect-editor-identities) inspect_editor_identities ;;
  inspect-layout-manager-chain) inspect_layout_manager_chain ;;
  inspect-text-storage-chain) inspect_text_storage_chain ;;
  inspect-undo-manager-chain) inspect_undo_manager_chain ;;
  snapshot-runtime-health) shift; snapshot_runtime_health "${1:-manual}" ;;
  snapshot-runtime-latest) print_latest_runtime_snapshot ;;
  snapshot-runtime-drift) shift; compare_runtime_snapshots "${1:-}" "${2:-}" ;;
  snapshot-runtime-workflow) runtime_snapshot_workflow ;;
  command-center) write_command_center ;;
  state) write_session_state; cat "$SESSION_JSON" ;;
  summary) shift; summary "${1:-session}" ;;
  regression) shift; regression "${1:-Unknown}" "${2:-Medium}" "${3:-No symptom provided}" ;;
  issue) shift; issue "${1:-Medium}" "${2:-No issue provided}" ;;
  runtime) shift; runtime "${1:-Runtime}" "${2:-High}" "${3:-No runtime symptom provided}" ;;
  artifact) shift; artifact "${1:-build-results}" "${2:-verification}" "${3:-No notes provided}" ;;
  milestone) shift; milestone "${1:-Untitled milestone}" ;;
  build-log) shift; build_log "${1:-PASS}" "${2:-no notes}" "${3:-SwiftPlaygroundPlusPlusStudio}" ;;
  handoff) shift; handoff "${1:-Continue from current sprint}" ;;
  adr) shift; adr "${1:-Untitled}" "${2:-Decision}" "${3:-Reason}" ;;
  sprint-close) shift; sprint_close "${1:-Sprint closed}" ;;
  *)
    echo "usage: $0 {doctor|restore|status|regressions|high-regressions|runtime-issues|milestone-current|current-focus|latest-build|next-task|architecture-warnings|unsafe-to-continue|review-context|verify-editor-routing|verify-pooled-editors|verify-find-routing|verify-diagnostics-lifecycle|verify-runtime-linking|verify-completion-lifecycle|verify-temp-attributes|verify-identity-continuity|inspect-editor-state|inspect-responder-chain|inspect-diagnostics|inspect-runtime-routing|inspect-completion-context|inspect-editor-pool|inspect-editor-identities|inspect-layout-manager-chain|inspect-text-storage-chain|inspect-undo-manager-chain|snapshot-runtime-health|snapshot-runtime-latest|snapshot-runtime-drift|snapshot-runtime-workflow|command-center|state|summary|regression|issue|runtime|artifact|milestone|build-log|handoff|adr|sprint-close}" >&2
    exit 2
    ;;
esac
