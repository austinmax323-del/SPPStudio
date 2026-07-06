#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_DIR="$ROOT_DIR/SPPStudioDocs"
OPEN_OBSIDIAN=1
SMOKE_BUILD=0
DRY_RUN=0
RESTORE_ONLY=0
REST_DATA="$VAULT_DIR/.obsidian/plugins/obsidian-local-rest-api/data.json"

usage() {
  echo "usage: ./launch-workspace.sh [--dry-run] [--no-open] [--smoke-build] [--restore-only]"
}

api_key() {
  sed -n 's/.*"apiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REST_DATA" | head -n 1
}

wait_for_rest() {
  local key
  key="$(api_key || true)"
  if [ -z "$key" ]; then
    echo "REST wait skipped: API key not found"
    return 1
  fi

  local attempt
  for attempt in {1..12}; do
    if curl -fsS -H "Authorization: Bearer $key" http://127.0.0.1:27123/ >/dev/null 2>&1; then
      echo "REST ready after ${attempt}s"
      return 0
    fi
    sleep 1
  done

  echo "REST not ready after 12s; doctor will report details"
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; OPEN_OBSIDIAN=0 ;;
    --no-open) OPEN_OBSIDIAN=0 ;;
    --smoke-build) SMOKE_BUILD=1 ;;
    --restore-only) RESTORE_ONLY=1; OPEN_OBSIDIAN=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT_DIR"

echo "=== SPPStudio AI Engineering Cockpit ==="
echo "repo: $ROOT_DIR"
echo "vault: $VAULT_DIR"
echo ""

if [ ! -d "$VAULT_DIR" ]; then
  echo "missing vault: $VAULT_DIR" >&2
  exit 1
fi

echo "1. Restoring session context"
"$ROOT_DIR/script/spp-workspace.sh" restore
echo ""

if [ "$OPEN_OBSIDIAN" -eq 1 ]; then
  echo "2. Opening Obsidian command center"
  open "obsidian://open?path=$VAULT_DIR/00_CommandCenter/Engineering Dashboard.md" 2>/dev/null || open "$VAULT_DIR"
  wait_for_rest || true
else
  echo "2. Obsidian open skipped"
fi
echo ""

echo "3. Verifying workspace services"
"$ROOT_DIR/script/spp-workspace.sh" doctor
echo ""

if [ "$RESTORE_ONLY" -eq 1 ]; then
  echo "restore-only complete"
  exit 0
fi

echo "4. Current milestone"
"$ROOT_DIR/script/spp-workspace.sh" milestone-current || true
echo ""

echo "5. Recommended next prompt"
echo "prompt: SPPStudioDocs/40_PromptEngineering/AgentPrompts/continue-current-sprint.md"
echo "dashboard: SPPStudioDocs/00_CommandCenter/Engineering Dashboard.md"
echo "review context: ./script/spp-workspace.sh review-context"
echo ""

echo "6. Unresolved regression summary"
"$ROOT_DIR/script/spp-workspace.sh" regressions || true
echo ""

echo "7. High severity regression warning section"
"$ROOT_DIR/script/spp-workspace.sh" high-regressions || true
echo ""

echo "8. Unsafe to continue indicator"
"$ROOT_DIR/script/spp-workspace.sh" unsafe-to-continue || true
echo ""

echo "9. Active runtime issues"
"$ROOT_DIR/script/spp-workspace.sh" runtime-issues || true
echo ""

echo "10. Latest build validation"
"$ROOT_DIR/script/spp-workspace.sh" latest-build || true
echo ""

echo "11. Architecture warning section"
"$ROOT_DIR/script/spp-workspace.sh" architecture-warnings || true
echo ""

if [ "$SMOKE_BUILD" -eq 1 ]; then
  echo "12. Running optional smoke build"
  if swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio; then
    "$ROOT_DIR/script/spp-workspace.sh" build-log PASS "launch-workspace smoke build"
  else
    "$ROOT_DIR/script/spp-workspace.sh" build-log FAIL "launch-workspace smoke build"
    exit 1
  fi
  echo ""
else
  echo "12. Smoke build skipped; pass --smoke-build to run it"
  echo ""
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "dry run complete"
else
  echo ""
  echo "workspace ready"
fi
