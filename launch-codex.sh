#!/bin/bash
# Launch Codex review context for SPPStudio with the Obsidian vault linked.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_NOTE="$REPO_DIR/SPPStudioDocs/AgentLinks/Codex Review.md"

cd "$REPO_DIR"

open "obsidian://open?path=$CODEX_NOTE" 2>/dev/null || true

echo "=== SPPStudio - Codex Review Session ==="
echo "Obsidian vault: SPPStudioDocs/"
echo "Start note: SPPStudioDocs/AgentLinks/Codex Review.md"
echo "Sprint: SPPStudioDocs/Sprints/current-sprint.md"
echo "Regressions: SPPStudioDocs/Regressions/regression-tracker.md"
echo "Review prompt: SPPStudioDocs/ClaudePrompts/codex-review-prompt.md"
echo "Anti-loop rules: SPPStudioDocs/AntiLoopPrompts/anti-loop-rules.md"
echo ""
echo "Paste the Codex review prompt before submitting a diff."
echo ""
"$REPO_DIR/script/spp-workspace.sh" status
echo ""

if command -v code &>/dev/null; then
    code "SPPStudioDocs/ClaudePrompts/codex-review-prompt.md"
else
    cat "SPPStudioDocs/ClaudePrompts/codex-review-prompt.md"
fi
