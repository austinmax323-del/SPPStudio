#!/bin/bash
# Open the SPPStudio Obsidian vault at the engineering dashboard.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_NAME="SPPStudioDocs"
VAULT_DIR="$REPO_DIR/SPPStudioDocs"
DASHBOARD_NOTE="$VAULT_DIR/00_CommandCenter/Engineering Dashboard.md"

if [ ! -d "$VAULT_DIR" ]; then
    echo "Vault not found: $VAULT_DIR"
    exit 1
fi

open "obsidian://open?path=$DASHBOARD_NOTE" 2>/dev/null || open "$VAULT_DIR"
