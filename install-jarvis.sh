#!/usr/bin/env bash
# Install the repo-local Jarvis wrapper into a PATH directory.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$REPO_DIR/bin/jarvis"
INSTALL_DIR="${JARVIS_INSTALL_DIR:-/opt/homebrew/bin}"
TARGET="$INSTALL_DIR/jarvis"

if [ ! -x "$WRAPPER" ]; then
  echo "jarvis wrapper is missing or not executable: $WRAPPER" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
  echo "refusing to replace non-symlink: $TARGET" >&2
  exit 1
fi

ln -sfn "$WRAPPER" "$TARGET"
echo "installed jarvis -> $WRAPPER"
echo "try: jarvis status"
