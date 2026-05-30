#!/usr/bin/env bash
# Open Terminal and run the read-only OpenJarvis Swift status command.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPPCTL_DIR="$REPO_DIR/Tools/sppctl"

if [ ! -d "$SPPCTL_DIR" ]; then
  echo "sppctl package not found: $SPPCTL_DIR" >&2
  exit 1
fi

terminal_command=$(printf 'cd %q && printf "OpenJarvis Status Launcher\\n" && swift run jarvis status; printf "\\nOpenJarvis status finished. Press Return to finish."; read _' "$SPPCTL_DIR")

osascript - "$terminal_command" >/dev/null <<'APPLESCRIPT'
on run argv
set terminalCommand to item 1 of argv
tell application "Terminal"
  activate
  do script terminalCommand
end tell
end run
APPLESCRIPT
