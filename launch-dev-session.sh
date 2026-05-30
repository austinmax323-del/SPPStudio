#!/bin/bash
# One-command dev session launcher for SPPStudio.
# Opens: Xcode workspace, Obsidian vault, restored sprint context, Claude, and Codex.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$REPO_DIR/SPPStudio.xcworkspace"
VAULT="$REPO_DIR/SPPStudioDocs"

cd "$REPO_DIR"

echo "=== Launching SPPStudio Dev Session ==="

# 1. Restore AI-readable session context and verify cockpit health.
echo "-> Restoring sprint and implementation context..."
"$REPO_DIR/launch-workspace.sh" --no-open

# 2. Open Xcode workspace.
if [ -d "$WORKSPACE" ]; then
    echo "-> Opening Xcode workspace..."
    open "$WORKSPACE"
else
    echo "Workspace not found: $WORKSPACE"
fi

# 3. Open Obsidian vault to the active implementation note.
if [ -d "$VAULT" ]; then
    echo "-> Opening Obsidian vault..."
    open "obsidian://open?path=$VAULT/Engineering Dashboard.md" 2>/dev/null || open "$VAULT"
else
    echo "Vault not found: $VAULT"
fi

# 4. Open terminal tabs with implementation and review contexts.
echo "-> Launching Claude Code..."
osascript <<EOF
tell application "Terminal"
    activate
    tell application "System Events" to keystroke "t" using command down
    delay 0.5
    do script "cd \"$REPO_DIR\" && ./launch-claude.sh" in front window
    tell application "System Events" to keystroke "t" using command down
    delay 0.5
    do script "cd \"$REPO_DIR\" && ./launch-codex.sh" in front window
end tell
EOF

echo ""
echo "Session ready. Check:"
echo "  - script/state/current-session.md for restored startup context"
echo "  - SPPStudioDocs/Sprints/current-sprint.md for current focus"
echo "  - SPPStudioDocs/ImplementationLog/active-implementation.md for active notes"
echo "  - SPPStudioDocs/Regressions/regression-tracker.md for regressions"
