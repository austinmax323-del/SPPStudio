#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/SPPStudioDocs"
VAULT_SCAN_DIR="$(cd "$VAULT_DIR" 2>/dev/null && pwd -P || printf '%s\n' "$VAULT_DIR")"
STATE_DIR="$ROOT_DIR/script/state"

usage() {
  cat <<'EOF'
Agent Infrastructure Doctor

Read-only audit commands:
  scan         summarize repo/vault/script/plugin/OpenJarvis consumers
  paths        inventory vault path references and classify them
  writes       detect possible vault-touching write/move/overwrite operations
  stale-paths  report pre-reorganization path references
  contracts    validate machine-readable note contracts
  report       combined markdown report

This tool does not run restore, PromptBridge send/capture/archive, worker sends,
or any vault-mutating project command.
EOF
}

consumer_files() {
  find "$ROOT_DIR" \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.build" -o -path "$ROOT_DIR/Tools/sppctl/.build" -o -path "$ROOT_DIR/Tools/TextViewRepro/.build" \) -prune -o \
    -type f \( \
      -path "$ROOT_DIR/script/*.sh" -o \
      -path "$ROOT_DIR/launch-*.sh" -o \
      -path "$ROOT_DIR/.mcp.json" -o \
      -path "$ROOT_DIR/.mcp.json.example" -o \
      -path "$ROOT_DIR/Tools/sppctl/Sources/*.swift" -o \
      -path "$ROOT_DIR/Tools/sppctl/Sources/*/*.swift" -o \
      -path "$ROOT_DIR/Tools/spp-obsidian-plugin/src/*.ts" -o \
      -path "$ROOT_DIR/Tools/spp-obsidian-plugin/src/*/*.ts" \
    \) -print | grep -v '/script/agent-infra-doctor\.sh$' | sort
}

rel() {
  local path="$1"
  printf '%s\n' "${path#$ROOT_DIR/}"
}

vault_rel_exists() {
  local path="$1"
  [ -e "$VAULT_DIR/$path" ]
}

print_header() {
  printf '\n## %s\n\n' "$1"
}

classify_line() {
  local file="$1"
  local line="$2"
  local class="dynamic"
  local note=""

  case "$line" in
    *'script/state'*|*'STATE_DIR'*|*'SESSION_JSON'*|*'SESSION_INDEX'*)
      class="generated-state"
      ;;
    *'$HOME/Library/Caches'*|*'127.0.0.1:27123'*|*'.mcp.json'*|*'sqlite'*|*'SQLite'*)
      class="external-state"
      ;;
    *'Sprints/current-sprint.md'*|*'ImplementationLog/active-implementation.md'*|*'Regressions/regression-tracker.md'*|*'Issues/unresolved-bugs.md'*|*'Bugs/known-regressions.md'*|*'VerificationFlows/README.md'*|*'VerificationArtifacts'*|*'Architecture Contracts.md'*|*'Editor Invariants.md'*|*'Known Bad Patterns.md'*|*'Known Failure Modes.md'*|*'AgentPrompts/'*|*'ClaudePrompts/'*|*'AntiLoopPrompts/'*|*'SessionSummaries/'*)
      if printf '%s\n' "$line" | grep -Eq '70_SessionContinuity|50_RuntimeOps|60_DeliveryValidation|20_ArchitectureMemory|40_PromptEngineering'; then
        class="valid-current"
      else
        class="stale-pre-reorg"
      fi
      ;;
    *'SPPStudioDocs/00_'*|*'SPPStudioDocs/20_'*|*'SPPStudioDocs/30_'*|*'SPPStudioDocs/40_'*|*'SPPStudioDocs/50_'*|*'SPPStudioDocs/60_'*|*'SPPStudioDocs/70_'*|*'SPPStudioDocs/80_'*|*'SPPStudioDocs/90_'*)
      class="valid-current"
      ;;
    *'SPPStudioDocs/'*)
      class="valid-legacy-symlink"
      ;;
  esac

  if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*(echo|#)|createSpan|text:'; then
    note=" documentation-only"
  fi

  printf '%s:%s | %s%s | %s\n' "$(rel "$file")" "${line%%:*}" "$class" "$note" "${line#*:}"
}

path_hits() {
  consumer_files | while IFS= read -r file; do
    rg --with-filename -n 'SPPStudioDocs|VAULT_DIR|BRIDGE_DIR|QUEUE_DIR|WATCHDOG_DIR|SESSION_NOTES|REST_DATA|PromptBridge|VerificationArtifacts|VerificationFlows|SessionSummaries|Sprints/current-sprint|ImplementationLog/active-implementation|Regressions/regression-tracker|Issues/unresolved-bugs|Bugs/known-regressions|Architecture Contracts|Editor Invariants|Known Bad Patterns|Known Failure Modes|AgentPrompts|ClaudePrompts|AntiLoopPrompts|OpenJarvis Active Task|OpenJarvis Session Handoff|WorkerRuns|127\.0\.0\.1:27123|\.mcp\.json|script/state|[0-9][0-9]_[A-Za-z]+[A-Za-z0-9_/ .-]*\.md' "$file" 2>/dev/null || true
  done
}

suggest_canonical() {
  local text="$1"
  case "$text" in
    *'Sprints/current-sprint.md'*) echo '70_SessionContinuity/Sprints/current-sprint.md' ;;
    *'ImplementationLog/active-implementation.md'*) echo '70_SessionContinuity/ImplementationLog/active-implementation.md' ;;
    *'Regressions/regression-tracker.md'*) echo '50_RuntimeOps/Regressions/regression-tracker.md' ;;
    *'Issues/unresolved-bugs.md'*) echo '50_RuntimeOps/Issues/unresolved-bugs.md' ;;
    *'Bugs/known-regressions.md'*) echo '50_RuntimeOps/Bugs/known-regressions.md' ;;
    *'VerificationFlows/README.md'*) echo '60_DeliveryValidation/VerificationFlows/README.md' ;;
    *'VerificationArtifacts'*) echo '60_DeliveryValidation/VerificationArtifacts' ;;
    *'Architecture Contracts.md'*) echo '20_ArchitectureMemory/Architecture Contracts.md' ;;
    *'Editor Invariants.md'*) echo '20_ArchitectureMemory/Editor Invariants.md' ;;
    *'Known Bad Patterns.md'*) echo '20_ArchitectureMemory/Known Bad Patterns.md' ;;
    *'Known Failure Modes.md'*) echo '20_ArchitectureMemory/Known Failure Modes.md' ;;
    *'AgentPrompts/'*) echo '40_PromptEngineering/AgentPrompts/' ;;
    *'ClaudePrompts/'*) echo '40_PromptEngineering/ClaudePrompts/' ;;
    *'AntiLoopPrompts/'*) echo '40_PromptEngineering/AntiLoopPrompts/' ;;
    *'SessionSummaries/'*) echo '70_SessionContinuity/SessionSummaries/' ;;
    *) echo '(no mapping)' ;;
  esac
}

scan() {
  print_header "Scan"
  printf -- '- repo: %s\n' "$ROOT_DIR"
  printf -- '- vault symlink path: %s\n' "$VAULT_DIR"
  if [ -L "$VAULT_DIR" ]; then
    printf -- '- vault symlink target: %s\n' "$(readlink "$VAULT_DIR")"
  fi
  printf -- '- consumer files: %s\n' "$(consumer_files | wc -l | tr -d ' ')"
  printf -- '- shell consumers: %s\n' "$(consumer_files | grep -E '/(script|launch).*\.sh$' | wc -l | tr -d ' ')"
  printf -- '- OpenJarvis Swift consumers: %s\n' "$(consumer_files | grep '/Tools/sppctl/Sources/' | wc -l | tr -d ' ')"
  printf -- '- Obsidian plugin consumers: %s\n' "$(consumer_files | grep '/Tools/spp-obsidian-plugin/src/' | wc -l | tr -d ' ')"
  printf -- '- MCP configs: %s\n' "$(consumer_files | grep -E '/\.mcp\.json(\.example)?$' | wc -l | tr -d ' ')"
  printf -- '- vault real path: %s\n' "$VAULT_SCAN_DIR"
  printf -- '- vault markdown files: %s\n' "$(find "$VAULT_SCAN_DIR" -path "$VAULT_SCAN_DIR/.obsidian" -prune -o -type f -name '*.md' -print | wc -l | tr -d ' ')"
  printf -- '- PromptBridge live queued prompts: %s\n' "$(find "$VAULT_DIR/40_PromptEngineering/PromptBridge/Queue/queued" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
  printf -- '- PromptBridge approved prompts: %s\n' "$(find "$VAULT_DIR/40_PromptEngineering/PromptBridge/Queue/approved" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
}

paths() {
  print_header "Path Inventory"
  path_hits | while IFS= read -r hit; do
    local file="${hit%%:*}"
    local rest="${hit#*:}"
    classify_line "$file" "$rest"
  done
}

writes() {
  print_header "Possible Vault Writes Or Moves"
  consumer_files | while IFS= read -r file; do
    rg -n '>>|>[[:space:]]*"?\$|>[[:space:]]*"?\$[A-Z_]+|cat >|mv |rm -f|mkdir -p|sed -i|write\(to:|createDirectory|appendingPathComponent\("70_SessionContinuity/WorkerRuns"|pbcopy|osascript' "$file" 2>/dev/null || true
  done | while IFS= read -r hit; do
    case "$hit" in
      *VAULT*|*BRIDGE*|*QUEUE*|*WATCHDOG*|*SESSION_NOTES*|*SPPStudioDocs*|*WorkerRuns*|*PromptBridge*|*pbcopy*|*osascript*|*write\(to:*|*createDirectory*)
        printf '%s\n' "$hit"
        ;;
    esac
  done
}

stale_paths() {
  print_header "Stale Pre-Reorganization References"
  path_hits | while IFS= read -r hit; do
    local file="${hit%%:*}"
    local rest="${hit#*:}"
    local classified
    classified="$(classify_line "$file" "$rest")"
    case "$classified" in
      *'| stale-pre-reorg'*)
        printf '%s\n' "$classified"
        printf '  suggested: %s\n' "$(suggest_canonical "$rest")"
        ;;
    esac
  done
}

contract_ok() {
  printf 'OK   %s\n' "$1"
}

contract_warn() {
  printf 'WARN %s\n' "$1"
}

require_note() {
  local path="$1"
  if vault_rel_exists "$path"; then
    contract_ok "$path exists"
    return 0
  fi
  contract_warn "$path missing"
  return 1
}

validate_recommended_next_action() {
  local path="00_CommandCenter/recommended-next-action.md"
  require_note "$path" || return 0
  local action
  action="$(awk '/^[[:space:]]*$/ { next } /^[[:space:]]*#/ { next } /^[[:space:]]*>/ { next } { print; exit }' "$VAULT_DIR/$path")"
  if [ -n "$action" ]; then
    contract_ok "$path actionable line: $action"
  else
    contract_warn "$path has no actionable non-heading line"
  fi
}

validate_regressions() {
  local path="50_RuntimeOps/Regressions/regression-tracker.md"
  require_note "$path" || return 0
  local rows high
  rows="$(grep -c '^| REG-' "$VAULT_DIR/$path" || true)"
  high="$(awk -F '|' 'NR > 2 && $0 ~ /^\| REG-/ { severity=$4; status=$5; gsub(/^ +| +$/, "", severity); gsub(/^ +| +$/, "", status); if (status != "Fixed" && (severity == "High" || severity == "Critical")) print }' "$VAULT_DIR/$path" | wc -l | tr -d ' ')"
  [ "$rows" -gt 0 ] && contract_ok "$path has $rows regression rows" || contract_warn "$path has no REG rows"
  [ "$high" -eq 0 ] && contract_ok "$path has no open High/Critical rows" || contract_warn "$path has $high open High/Critical rows"
}

validate_runtime_issues() {
  local path="50_RuntimeOps/RuntimeIssues/editor-runtime-issues.md"
  require_note "$path" || return 0
  local rows
  rows="$(grep -c '^- 20[0-9][0-9]-' "$VAULT_DIR/$path" || true)"
  [ "$rows" -gt 0 ] && contract_ok "$path has $rows dated runtime issue rows" || contract_warn "$path has no dated runtime issue rows"
}

validate_build_log() {
  local path="60_DeliveryValidation/BuildNotes/build-validation-log.md"
  require_note "$path" || return 0
  local rows latest
  rows="$(grep -c '^| 20' "$VAULT_DIR/$path" || true)"
  latest="$(grep '^| 20' "$VAULT_DIR/$path" | tail -1 || true)"
  [ "$rows" -gt 0 ] && contract_ok "$path has $rows build rows" || contract_warn "$path has no dated build rows"
  [ -n "$latest" ] && contract_ok "$path latest row: $latest"
}

validate_sprint() {
  local path="70_SessionContinuity/Sprints/current-sprint.md"
  require_note "$path" || return 0
  local goal
  goal="$(grep -m 1 '^## Sprint Goal' -A1 "$VAULT_DIR/$path" | tail -1 || true)"
  [ -n "$goal" ] && [ "$goal" != "## Sprint Goal" ] && contract_ok "$path sprint goal: $goal" || contract_warn "$path missing parseable sprint goal"
}

validate_active_implementation() {
  local path="70_SessionContinuity/ImplementationLog/active-implementation.md"
  require_note "$path" || return 0
  local target
  target="$(grep -m 1 '^- Active engineering target:' "$VAULT_DIR/$path" | sed 's/^- Active engineering target: //' || true)"
  [ -n "$target" ] && contract_ok "$path active target: $target" || contract_warn "$path missing active target line"
}

validate_milestone() {
  local path="70_SessionContinuity/Milestones/active-milestone-dashboard.md"
  require_note "$path" || return 0
  local milestone
  milestone="$(grep -m 1 '^## Current:' "$VAULT_DIR/$path" | sed 's/^## Current: //' || true)"
  [ -n "$milestone" ] && contract_ok "$path current milestone: $milestone" || contract_warn "$path missing current milestone line"
}

validate_promptbridge() {
  local root="40_PromptEngineering/PromptBridge/Queue"
  require_note "40_PromptEngineering/PromptBridge/Bridge Status.md" || true
  for lane in queued approved completed failed blocked; do
    local dir="$VAULT_DIR/$root/$lane"
    if [ -d "$dir" ]; then
      contract_ok "$root/$lane exists ($(find "$dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ') markdown prompts)"
    else
      contract_warn "$root/$lane missing"
    fi
  done
  find "$VAULT_DIR/$root/queued" "$VAULT_DIR/$root/approved" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | sort | while IFS= read -r prompt; do
    if awk '/^```prompt$/ { found=1 } END { exit found ? 0 : 1 }' "$prompt"; then
      contract_ok "${prompt#$VAULT_DIR/} has prompt fence"
    else
      contract_warn "${prompt#$VAULT_DIR/} missing exact prompt fence"
    fi
  done
  local active="$VAULT_DIR/$root/state/active-prompt.path"
  if [ -f "$active" ]; then
    local target
    target="$(cat "$active")"
    [ -f "$target" ] && contract_ok "$root/state/active-prompt.path points to existing prompt" || contract_warn "$root/state/active-prompt.path points to missing prompt: $target"
  else
    contract_ok "$root/state/active-prompt.path absent"
  fi
  local failures="$VAULT_DIR/$root/state/failure-count"
  if [ -f "$failures" ]; then
    grep -Eq '^[0-9]+$' "$failures" && contract_ok "$root/state/failure-count is numeric" || contract_warn "$root/state/failure-count is not numeric"
  else
    contract_ok "$root/state/failure-count absent"
  fi
}

contracts() {
  print_header "Machine-Readable Note Contracts"
  validate_recommended_next_action
  validate_regressions
  validate_runtime_issues
  validate_build_log
  validate_sprint
  validate_active_implementation
  validate_milestone
  validate_promptbridge
}

report() {
  printf '# Agent Infrastructure Doctor Report\n'
  scan
  paths
  writes
  stale_paths
  contracts
}

case "${1:-report}" in
  scan) scan ;;
  paths) paths ;;
  writes) writes ;;
  stale-paths) stale_paths ;;
  contracts) contracts ;;
  report) report ;;
  -h|--help|help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
