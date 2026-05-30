#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/SPPStudioDocs/40_PromptEngineering/PromptBridge"
OUTBOX_DIR="$BRIDGE_DIR/Outbox"
QUEUE_DIR="$BRIDGE_DIR/Queue"
WATCHDOG_DIR="$BRIDGE_DIR/Watchdog"
SESSION_NOTES="$BRIDGE_DIR/SessionNotes/codex-output.md"
APPROVED_PROMPT="$OUTBOX_DIR/approved.md"

QUEUE_QUEUED="$QUEUE_DIR/queued"
QUEUE_APPROVED="$QUEUE_DIR/approved"
QUEUE_COMPLETED="$QUEUE_DIR/completed"
QUEUE_FAILED="$QUEUE_DIR/failed"
QUEUE_BLOCKED="$QUEUE_DIR/blocked"
QUEUE_STATE="$QUEUE_DIR/state"
ACTIVE_PROMPT_PATH="$QUEUE_STATE/active-prompt.path"
FAILURE_COUNT_PATH="$QUEUE_STATE/failure-count"

usage() {
  cat <<'EOF'
SPPStudio prompt bridge

Usage:
  ./script/prompt-bridge.sh status
  ./script/prompt-bridge.sh preview
  ./script/prompt-bridge.sh send-approved
  ./script/prompt-bridge.sh capture-output

  ./script/prompt-bridge.sh queue-status
  ./script/prompt-bridge.sh queue-next
  ./script/prompt-bridge.sh approve-next
  ./script/prompt-bridge.sh send-next
  ./script/prompt-bridge.sh run-once
  ./script/prompt-bridge.sh capture-and-archive [completed|failed|blocked]
  ./script/prompt-bridge.sh blocked "reason"

Controlled loop:
  queued -> approved -> run-once -> capture-and-archive -> watchdog summary

Safety:
  - run-once sends exactly one approved queued prompt.
  - No background loop exists.
  - Unapproved prompts are never sent.
  - Unsafe-to-continue stops sending.
  - Runtime/editor file modification attempts are blocked.
  - Scope expansion requires an explicit approval marker.
EOF
}

ensure_dirs() {
  mkdir -p "$OUTBOX_DIR" "$QUEUE_QUEUED" "$QUEUE_APPROVED" "$QUEUE_COMPLETED" \
    "$QUEUE_FAILED" "$QUEUE_BLOCKED" "$QUEUE_STATE" "$WATCHDOG_DIR" \
    "$(dirname "$SESSION_NOTES")"
}

require_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "Missing or empty: $file" >&2
    exit 1
  fi
}

first_markdown_file() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort | head -n 1
}

prompt_body_from_file() {
  local file="$1"
  require_file "$file"
  awk '
    /^```prompt$/ { in_prompt=1; next }
    /^```$/ && in_prompt { in_prompt=0; next }
    in_prompt { print }
  ' "$file"
}

prompt_body() {
  prompt_body_from_file "$APPROVED_PROMPT"
}

preview_file() {
  local file="$1"
  local body
  body="$(prompt_body_from_file "$file")"
  if [[ -z "$body" ]]; then
    echo "No prompt block found in $file" >&2
    echo "Expected a fenced block that starts with: \`\`\`prompt" >&2
    exit 1
  fi

  echo "Prompt source:"
  echo "$file"
  echo
  echo "Prompt preview:"
  echo "----------------"
  printf '%s\n' "$body"
  echo "----------------"
}

preview_prompt() {
  preview_file "$APPROVED_PROMPT"
}

front_app_name() {
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true
}

ensure_focused_terminal() {
  local app
  app="$(front_app_name)"
  case "$app" in
    Terminal|iTerm|iTerm2|Warp|WezTerm|Alacritty|Ghostty)
      return 0
      ;;
    *)
      echo "Hard stop: focused app is '$app', not a known terminal." >&2
      echo "Focus the active Codex terminal and rerun." >&2
      exit 1
      ;;
  esac
}

ensure_unsafe_gate_clear() {
  local output
  output="$("$ROOT_DIR/script/spp-workspace.sh" unsafe-to-continue 2>/dev/null || true)"
  if ! printf '%s\n' "$output" | grep -qi '^safe to continue:'; then
    echo "Hard stop: unsafe-to-continue gate is not clear." >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

has_scope_expansion_approval() {
  local file="$1"
  grep -Eiq '^(Scope expansion approved|Extra approval|Runtime/editor approval):[[:space:]]*(yes|true|approved)$' "$file"
}

ensure_no_repeated_failure() {
  local count
  count="0"
  if [[ -f "$FAILURE_COUNT_PATH" ]]; then
    count="$(tr -cd '0-9' <"$FAILURE_COUNT_PATH")"
    count="${count:-0}"
  fi
  if (( count >= 2 )); then
    echo "Hard stop: repeated failure count is $count." >&2
    echo "Review $QUEUE_FAILED and $WATCHDOG_DIR before sending another prompt." >&2
    exit 1
  fi
}

ensure_no_critical_watchdog() {
  if find "$WATCHDOG_DIR" -maxdepth 1 -type f -name '*.md' -print0 \
    | xargs -0 grep -Eil '^Severity:[[:space:]]*Critical' >/dev/null 2>&1; then
    echo "Hard stop: watchdog critical warning is present." >&2
    echo "Resolve or archive the critical warning before continuing." >&2
    exit 1
  fi
}

scope_check_file() {
  local file="$1"
  local body
  body="$(prompt_body_from_file "$file")"
  if [[ -z "$body" ]]; then
    echo "Hard stop: empty approved prompt." >&2
    exit 1
  fi

  if printf '%s\n' "$body" | grep -Eiq 'EditorAreaView\.swift|RuntimeInvariantInspector|BuildService|Diagnostics|Completion|pooled NSTextView|NSTextView lifecycle|runtime/editor routing|Apps/SwiftPlaygroundPlusPlusStudio/Sources/IDE/Editor|Apps/SwiftPlaygroundPlusPlusStudio/Sources/Services|RuntimeInvariant|SimulatorService'; then
    echo "Hard stop: prompt appears to target forbidden runtime/editor code." >&2
    echo "Move it to blocked or request explicit unlock from the user in a new instruction." >&2
    exit 1
  fi

  if printf '%s\n' "$body" | grep -Eiq 'Apps/SwiftPlaygroundPlusPlusStudio|Packages/|Tools/|ProjectService|script/|launch-.*\.sh|background|daemon|watcher|telemetry|monitoring|always-on|autonomous loop|infinite loop'; then
    if ! has_scope_expansion_approval "$file"; then
      echo "Hard stop: prompt requests a scope expansion that requires explicit approval." >&2
      echo "Add 'Scope expansion approved: yes' to the queue file only after user approval." >&2
      exit 1
    fi
  fi
}

preflight_file() {
  local file="$1"
  ensure_unsafe_gate_clear
  ensure_no_repeated_failure
  ensure_no_critical_watchdog
  scope_check_file "$file"
}

send_file() {
  local file="$1"
  local body confirmation
  body="$(prompt_body_from_file "$file")"
  if [[ -z "$body" ]]; then
    echo "Hard stop: empty approved prompt." >&2
    exit 1
  fi

  preflight_file "$file"
  preview_file "$file"
  echo
  echo "Focus the active Codex terminal before continuing."
  read -r -p "Type SEND to paste this prompt into the focused Codex terminal: " confirmation
  if [[ "$confirmation" != "SEND" ]]; then
    echo "Cancelled."
    exit 0
  fi

  ensure_focused_terminal
  printf '%s' "$body" | pbcopy
  osascript <<'APPLESCRIPT'
tell application "System Events"
  keystroke "v" using command down
  key code 36
end tell
APPLESCRIPT
  printf '%s\n' "$file" >"$ACTIVE_PROMPT_PATH"
  echo "Sent one approved prompt to the focused terminal."
}

send_approved() {
  send_file "$APPROVED_PROMPT"
}

queue_status() {
  ensure_dirs
  echo "Prompt queue:"
  printf -- "- queued:    %s\n" "$(find "$QUEUE_QUEUED" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  printf -- "- approved:  %s\n" "$(find "$QUEUE_APPROVED" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  printf -- "- completed: %s\n" "$(find "$QUEUE_COMPLETED" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  printf -- "- failed:    %s\n" "$(find "$QUEUE_FAILED" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  printf -- "- blocked:   %s\n" "$(find "$QUEUE_BLOCKED" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  if [[ -f "$ACTIVE_PROMPT_PATH" ]]; then
    printf -- "- active:    %s\n" "$(cat "$ACTIVE_PROMPT_PATH")"
  fi
}

queue_next() {
  ensure_dirs
  local next
  next="$(first_markdown_file "$QUEUE_QUEUED")"
  if [[ -z "$next" ]]; then
    echo "No queued prompts."
    return 0
  fi
  preview_file "$next"
}

approve_next() {
  ensure_dirs
  local next dest base
  next="$(first_markdown_file "$QUEUE_QUEUED")"
  if [[ -z "$next" ]]; then
    echo "No queued prompts to approve."
    return 0
  fi
  preview_file "$next"
  echo
  read -r -p "Type APPROVE to move this prompt into the approved queue: " confirmation
  if [[ "$confirmation" != "APPROVE" ]]; then
    echo "Cancelled."
    exit 0
  fi
  base="$(basename "$next")"
  dest="$QUEUE_APPROVED/$base"
  mv "$next" "$dest"
  echo "Approved:"
  echo "$dest"
}

send_next() {
  ensure_dirs
  local next
  next="$(first_markdown_file "$QUEUE_APPROVED")"
  if [[ -z "$next" ]]; then
    echo "No approved prompts to send."
    return 0
  fi
  send_file "$next"
}

run_once() {
  send_next
}

write_watchdog_summary() {
  local archive_status="$1"
  local prompt_file="$2"
  local output_file="$3"
  local ts out watchdog severity
  ts="$(date '+%Y-%m-%d-%H%M%S')"
  watchdog="$WATCHDOG_DIR/$ts-watchdog-summary.md"
  severity="Info"
  out="$(pbpaste || true)"

  if printf '%s\n' "$out" | grep -Eiq 'RuntimeInvariantInspector|EditorAreaView\.swift|BuildService|NSTextView|telemetry|background|daemon|always-on|infinite loop'; then
    severity="Warning"
  fi
  if [[ "$archive_status" == "failed" || "$archive_status" == "blocked" ]]; then
    severity="Warning"
  fi

  {
    echo "# Watchdog Summary - $ts"
    echo
    echo "Severity: $severity"
    echo "Archive status: $archive_status"
    echo "Prompt: $prompt_file"
    echo "Output: $output_file"
    echo
    echo "## Human Summary"
    echo "- Codex output was captured from the clipboard."
    echo "- Review the output for scope drift before queueing the next prompt."
    echo
    echo "## Drift Checks"
    if [[ "$severity" == "Warning" ]]; then
      echo "- Warning: output or archive status mentions a sensitive area or failed/blocked run."
    else
      echo "- No obvious bridge-level scope drift markers were found."
    fi
    echo "- This watchdog note is passive and does not execute anything."
    echo
    echo "## Output Preview"
    echo '```'
    printf '%s\n' "$out" | sed -n '1,80p'
    echo '```'
  } >"$watchdog"

  echo "Watchdog summary:"
  echo "$watchdog"
}

capture_output() {
  ensure_dirs
  {
    echo
    echo "## Codex Output Capture - $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    pbpaste
    echo
  } >>"$SESSION_NOTES"
  echo "Captured clipboard into:"
  echo "$SESSION_NOTES"
}

capture_and_archive() {
  ensure_dirs
  local status="${1:-completed}"
  local active dest base ts output_file count
  case "$status" in
    completed|failed|blocked) ;;
    *)
      echo "Archive status must be completed, failed, or blocked." >&2
      exit 1
      ;;
  esac

  capture_output
  active=""
  if [[ -f "$ACTIVE_PROMPT_PATH" ]]; then
    active="$(cat "$ACTIVE_PROMPT_PATH")"
  fi
  if [[ -z "$active" || ! -f "$active" ]]; then
    echo "No active approved prompt to archive."
    write_watchdog_summary "$status" "(none)" "$SESSION_NOTES"
    exit 0
  fi

  ts="$(date '+%Y-%m-%d-%H%M%S')"
  base="$(basename "$active")"
  case "$status" in
    completed) dest="$QUEUE_COMPLETED/$ts-$base" ;;
    failed) dest="$QUEUE_FAILED/$ts-$base" ;;
    blocked) dest="$QUEUE_BLOCKED/$ts-$base" ;;
  esac
  mv "$active" "$dest"
  rm -f "$ACTIVE_PROMPT_PATH"

  if [[ "$status" == "completed" ]]; then
    printf '0\n' >"$FAILURE_COUNT_PATH"
  else
    count="0"
    if [[ -f "$FAILURE_COUNT_PATH" ]]; then
      count="$(tr -cd '0-9' <"$FAILURE_COUNT_PATH")"
      count="${count:-0}"
    fi
    printf '%s\n' "$((count + 1))" >"$FAILURE_COUNT_PATH"
  fi

  output_file="$SESSION_NOTES"
  echo "Archived prompt:"
  echo "$dest"
  write_watchdog_summary "$status" "$dest" "$output_file"
}

mark_blocked() {
  ensure_dirs
  local reason="${1:-Manual block}"
  local active next dest base ts
  ts="$(date '+%Y-%m-%d-%H%M%S')"
  active=""
  if [[ -f "$ACTIVE_PROMPT_PATH" ]]; then
    active="$(cat "$ACTIVE_PROMPT_PATH")"
  fi
  if [[ -n "$active" && -f "$active" ]]; then
    base="$(basename "$active")"
    dest="$QUEUE_BLOCKED/$ts-$base"
    {
      echo
      echo "## Blocked"
      echo "Reason: $reason"
    } >>"$active"
    mv "$active" "$dest"
    rm -f "$ACTIVE_PROMPT_PATH"
    echo "Blocked active prompt:"
    echo "$dest"
    write_watchdog_summary "blocked" "$dest" "$SESSION_NOTES"
    exit 0
  fi

  next="$(first_markdown_file "$QUEUE_APPROVED")"
  if [[ -z "$next" ]]; then
    echo "No active or approved prompt to block."
    return 0
  fi
  base="$(basename "$next")"
  dest="$QUEUE_BLOCKED/$ts-$base"
  {
    echo
    echo "## Blocked"
    echo "Reason: $reason"
  } >>"$next"
  mv "$next" "$dest"
  echo "Blocked next approved prompt:"
  echo "$dest"
  write_watchdog_summary "blocked" "$dest" "$SESSION_NOTES"
}

case "${1:-}" in
  status)
    ensure_dirs
    echo "Prompt bridge:"
    echo "- Pending:  $OUTBOX_DIR/pending.md"
    echo "- Approved: $APPROVED_PROMPT"
    echo "- Queue:    $QUEUE_DIR"
    echo "- Output:   $SESSION_NOTES"
    ;;
  preview)
    preview_prompt
    ;;
  send-approved)
    send_approved
    ;;
  capture-output)
    capture_output
    ;;
  queue-status)
    queue_status
    ;;
  queue-next)
    queue_next
    ;;
  approve-next)
    approve_next
    ;;
  send-next)
    send_next
    ;;
  run-once)
    run_once
    ;;
  capture-and-archive)
    capture_and_archive "${2:-completed}"
    ;;
  blocked)
    mark_blocked "${2:-Manual block}"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
