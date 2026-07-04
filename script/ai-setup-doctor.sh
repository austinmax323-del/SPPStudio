#!/bin/bash
# ai-setup-doctor.sh — read-only health check for the local AI stack.
# Manual-first: run it yourself, nothing runs in the background.
# Prints NO secrets. Exit codes: 0 = green, 1 = warnings, 2 = critical.
set -u

REPO="$HOME/Developer/SPPStudio"
VAULT="$HOME/Developer/Obsidian"
G=0; Y=0; R=0
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; G=$((G+1)); }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$1"; Y=$((Y+1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; R=$((R+1)); }
hdr()  { printf "\n\033[1m── %s ─────────────────────────────────\033[0m\n" "$1"; }
days_old() { local m; m=$(stat -f %m "$1" 2>/dev/null) || { echo "-1"; return; }; echo $(( ( $(date +%s) - m ) / 86400 )); }

echo "AI SETUP DOCTOR · $(date '+%Y-%m-%d %H:%M %Z')"

hdr "Tooling"
for c in claude codex gemini ollama gh; do
  if command -v "$c" >/dev/null 2>&1; then
    v=$("$c" --version 2>&1 | head -1 | cut -c1-44)
    ok "$c · $v"
  else
    warn "$c not installed / not on PATH"
  fi
done

hdr "Auth"
if gh auth status >/dev/null 2>&1; then ok "GitHub CLI authenticated (keyring)"; else bad "GitHub CLI unauthenticated — run: gh auth login"; fi
if [ -e "$HOME/.claude-mem/oauth-stale.marker" ]; then
  bad "claude-mem OAuth STALE since $(stat -f %Sm -t '%Y-%m-%d %H:%M' "$HOME/.claude-mem/oauth-stale.marker") — re-login Claude Desktop, then delete the marker"
else
  ok "no stale OAuth marker (claude-mem)"
fi

if [ -n "" ]; then
  warn "launchd ANTHROPIC_API_KEY is set — shadows Claude Code OAuth for GUI-launched runs; clear with: launchctl unsetenv ANTHROPIC_API_KEY"
else
  ok "no stray launchd ANTHROPIC_API_KEY"
fi

hdr "Local services"
TMPJ="$(mktemp)"
if curl -s --max-time 2 http://localhost:11434/api/tags >"$TMPJ" 2>/dev/null; then
  n=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1])).get('models',[])))" "$TMPJ" 2>/dev/null || echo "?")
  ok "Ollama up on 11434 · $n model(s)"
else
  warn "Ollama not responding on 11434 (fine if intentionally stopped)"
fi
rm -f "$TMPJ"
rest=0
curl -s -o /dev/null --max-time 2 http://127.0.0.1:27123/ 2>/dev/null && { ok "Obsidian REST http :27123"; rest=1; }
curl -sk -o /dev/null --max-time 2 https://127.0.0.1:27124/ 2>/dev/null && { ok "Obsidian REST https :27124"; rest=1; }
[ "$rest" -eq 0 ] && warn "Obsidian REST not responding — is Obsidian running?"

hdr "Listening ports (AI-related)"
PORTS=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '/11434|27123|27124|1234|3000|5173|8000|8080/ {print "  " $1 " " $9}' | sort -u)
if [ -n "$PORTS" ]; then echo "$PORTS"; else echo "  (none)"; fi
NONLOOP=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '/11434|27123|27124/ && $9 !~ /127\.0\.0\.1|\[::1\]/' | head -3)
if [ -n "$NONLOOP" ]; then bad "AI service bound to non-loopback interface — review:"; echo "$NONLOOP" | sed 's/^/    /'; else ok "AI services loopback-only"; fi

hdr "SPPStudio git"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last=$(git -C "$REPO" log -1 --format='%ad' --date=short 2>/dev/null)
  age=$(( ( $(date +%s) - $(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo 0) ) / 86400 ))
  if [ "$dirty" -eq 0 ]; then ok "clean worktree on $branch"; else warn "$dirty uncommitted path(s) on $branch — review, then commit or stash"; fi
  if [ "$age" -gt 21 ]; then warn "last commit $last (${age}d ago) — consider a checkpoint commit"; else ok "last commit $last (${age}d ago)"; fi
else
  bad "$REPO is not a git repository"
fi
if [ -d "$HOME/Developer/openjarvis" ]; then
  if [ -d "$HOME/Developer/openjarvis/.git" ]; then ok "openjarvis is git-backed"; else warn "openjarvis NOT git-backed — run: git -C ~/Developer/openjarvis init (then commit manually)"; fi
fi

hdr "Memory / continuity freshness"
fresh() { # path label warn_days bad_days
  local d; d=$(days_old "$1")
  if [ "$d" -lt 0 ]; then warn "$2 missing ($1)"
  elif [ "$d" -ge "$4" ]; then bad "$2 stale — ${d}d old"
  elif [ "$d" -ge "$3" ]; then warn "$2 aging — ${d}d old"
  else ok "$2 fresh — ${d}d old"; fi
}
fresh "$HOME/.claude-mem/claude-mem.db" "claude-mem DB" 7 30
fresh "$HOME/.jarvis/jarvis.db"         "Jarvis DB"     21 60
NEWEST_STATE=$(ls -t "$REPO/script/state/" 2>/dev/null | head -1)
if [ -n "$NEWEST_STATE" ]; then fresh "$REPO/script/state/$NEWEST_STATE" "script/state (newest: $NEWEST_STATE)" 14 30; else warn "no script/state directory"; fi

hdr "Vault"
NOTES=$(find "$VAULT" -name '*.md' -not -path '*/.obsidian/*' 2>/dev/null | wc -l | tr -d ' ')
ok "$NOTES markdown notes"
NEWEST_OP=$(find "$VAULT/00_CommandCenter" "$VAULT/70_SessionContinuity" -name '*.md' 2>/dev/null -exec stat -f '%m %N' {} \; | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$NEWEST_OP" ]; then
  d=$(days_old "$NEWEST_OP")
  if [ "$d" -gt 14 ]; then warn "newest operational note is ${d}d old: ${NEWEST_OP#$VAULT/}"; else ok "operational notes current (${d}d): ${NEWEST_OP#$VAULT/}"; fi
fi

hdr "Sensitive file permissions"
for f in "$REPO/.mcp.json" "$HOME/.codex/auth.json" "$HOME/.claude.json" "$HOME/.gemini/oauth_creds.json" "$HOME/.ollama/id_ed25519" "$HOME/.jarvis/jarvis.db" "$HOME/.claude-mem/claude-mem.db"; do
  if [ -e "$f" ]; then
    mode=$(stat -f %Lp "$f")
    if [ "$mode" = "600" ] || [ "$mode" = "400" ]; then ok "$mode ${f/#$HOME/~}"; else bad "$mode ${f/#$HOME/~} — fix: chmod 600 '$f'"; fi
  else
    warn "missing: ${f/#$HOME/~}"
  fi
done

hdr "Summary"
printf "  %d green · %d yellow · %d red\n" "$G" "$Y" "$R"
if [ "$R" -gt 0 ]; then echo "  STATUS: RED — fix ✗ items first"; exit 2
elif [ "$Y" -gt 0 ]; then echo "  STATUS: YELLOW — review ⚠ items"; exit 1
else echo "  STATUS: GREEN"; exit 0; fi
