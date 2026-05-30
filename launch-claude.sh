#!/bin/bash
# Launch Claude Code in the SPPStudio repo with the Obsidian vault context.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_NOTE="$REPO_DIR/SPPStudioDocs/AgentLinks/Claude Code.md"

cd "$REPO_DIR"

open "obsidian://open?path=$CLAUDE_NOTE" 2>/dev/null || true

echo "=== SPPStudio - Claude Code Session ==="
echo "Project context: PROJECT_CONTEXT.md"
echo "Obsidian vault: SPPStudioDocs/"
echo "Start note: SPPStudioDocs/AgentLinks/Claude Code.md"
echo "Sprint: SPPStudioDocs/Sprints/current-sprint.md"
echo "Active implementation: SPPStudioDocs/ImplementationLog/active-implementation.md"
echo "MCP vault server: sppstudio-obsidian-vault (Obsidian must be open)"
echo "Prompt: SPPStudioDocs/ClaudePrompts/session-start-prompt.md"
echo "Anti-loop rules: SPPStudioDocs/AntiLoopPrompts/anti-loop-rules.md"
echo ""
"$REPO_DIR/script/spp-workspace.sh" status
echo ""
claude
