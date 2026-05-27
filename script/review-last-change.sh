#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/SPPStudioDocs"
SWIFT_SOURCE_DIR="Apps/SwiftPlaygroundPlusPlusStudio/Sources"
GIANT_FILE_LINES="${GIANT_FILE_LINES:-900}"
ASYNC_WARN_COUNT="${ASYNC_WARN_COUNT:-3}"

cd "$ROOT_DIR"

echo "SPPStudio review context"
echo "repo: $ROOT_DIR"
echo ""

changed_swift_files=()

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Changed files"
  git -C "$ROOT_DIR" status --short
  echo ""
  echo "Diff stats"
  git -C "$ROOT_DIR" diff --stat
  echo ""
  echo "Editor/runtime files first"
  git -C "$ROOT_DIR" status --short | awk '
    /Editor|Console|Runtime|Simulator|BuildService|ProjectService|AppEnvironment|IDEWindowView|Diagnostics|Completion/ { print }
  '

  while IFS= read -r changed_file; do
    [ -n "$changed_file" ] && changed_swift_files+=("$changed_file")
  done < <({
    git -C "$ROOT_DIR" diff --name-only -- '*.swift'
    git -C "$ROOT_DIR" diff --cached --name-only -- '*.swift'
    git -C "$ROOT_DIR" status --short -- '*.swift' | sed 's/^...//'
  } | sort -u)
else
  echo "Changed files"
  echo "git unavailable: no worktree detected; showing recent workspace files instead"
  find SPPStudioDocs script -type f -mtime -2 \
    ! -path 'SPPStudioDocs/.obsidian/*' \
    ! -path 'script/state/*' | sort

  while IFS= read -r changed_file; do
    [ -n "$changed_file" ] && changed_swift_files+=("$changed_file")
  done < <(find "$SWIFT_SOURCE_DIR" -name '*.swift' -mtime -2 | sort)
fi

echo ""
echo "Latest changed Swift files"
if [ "${#changed_swift_files[@]}" -eq 0 ]; then
  echo "none detected"
else
  printf "%s\n" "${changed_swift_files[@]}"
fi

echo ""
echo "Editor/runtime-related Swift files"
if [ "${#changed_swift_files[@]}" -eq 0 ]; then
  echo "none detected"
else
  printf "%s\n" "${changed_swift_files[@]}" | awk '
    /Editor|Console|Runtime|Simulator|BuildService|ProjectService|AppEnvironment|IDEWindowView|Diagnostics|Completion/ { print }
  '
fi

echo ""
echo "Focused architecture warning scan"
echo "Treat these as review leads, not automatic failures."

warn_if_found() {
  local title="$1"
  local pattern="$2"
  shift 2
  if rg -n "$pattern" "$@" >/tmp/spp-review-focused.out 2>/dev/null; then
    echo ""
    echo "warning: $title"
    sed -n '1,10p' /tmp/spp-review-focused.out
  fi
}

warn_if_found ".id( on editor/container views" "\\.id\\(" "$SWIFT_SOURCE_DIR/IDE"
warn_if_found "SwiftUI TextEditor usage" "TextEditor\\(" "$SWIFT_SOURCE_DIR"
warn_if_found "possible editor-owned diagnostics state" "diagnostic|Diagnostic|diagnostics|Diagnostics" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "permanent attributed string mutation near editor/diagnostic surfaces" "setAttributedString|addAttribute|removeAttribute" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/IDE/Console"
warn_if_found "direct SwiftUI overlay rendering in editor surfaces" "\\.overlay\\(" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "suspicious editor recreation patterns" "NSTextView\\(|NSScrollView\\(|makeNSView|dismantleNSView" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "broad/global singleton abuse" "static let shared|static var shared|shared =" "$SWIFT_SOURCE_DIR"
warn_if_found "fake abstraction growth candidates" "(Engine|Factory|Coordinator|Manager)" "$SWIFT_SOURCE_DIR"
warn_if_found "TODO/FIXME accumulation" "TODO|FIXME" "$SWIFT_SOURCE_DIR"

echo ""
echo "Behavioral-risk touchpoints"
warn_if_found "editor lifecycle touchpoints" "makeNSView|updateNSView|dismantleNSView|NSTextView\\(|NSScrollView\\(" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "responder-chain changes" "firstResponder|becomeFirstResponder|resignFirstResponder|performFindPanelAction|NSTextFinder" "$SWIFT_SOURCE_DIR"
warn_if_found "text storage ownership changes" "textStorage|NSTextStorage|setAttributedString|addAttribute|removeAttribute" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/IDE/Console"
warn_if_found "layout-manager mutation changes" "layoutManager|temporaryAttribute|addTemporary|removeTemporary|invalidateDisplay" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "runtime/editor coupling changes" "activeFile|activeTab|openTab|selectedFile|bundleID|crash|runtime|Runtime|Simulator" "$SWIFT_SOURCE_DIR/IDE" "$SWIFT_SOURCE_DIR/Services"
warn_if_found "completion lifecycle changes" "completion|Completion|complete\\(|rangeForUserCompletion|completions" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/Services"

echo ""
echo "Runtime introspection risk scan"
warn_if_found "debug instrumentation growth" "RuntimeInvariantInspector|Dump Runtime Invariants|runtime invariant|inspection|inspect" "$SWIFT_SOURCE_DIR"
warn_if_found "always-on logging risks" "NSLog|Logger|os_log|print\\(" "$SWIFT_SOURCE_DIR"
warn_if_found "debug-only boundary violations" "#if DEBUG|DEBUG|isDebug|debugOnly" "$SWIFT_SOURCE_DIR"
warn_if_found "ownership inversion risks" "weak var textView|NSTextView.*Service|Service.*NSTextView|BuildService.*NSTextView|SimulatorService.*NSTextView" "$SWIFT_SOURCE_DIR"
warn_if_found "editor/runtime coupling drift" "RuntimeInvariantInspector|runtime.*editor|editor.*runtime|activeFileID|activeTabID" "$SWIFT_SOURCE_DIR/IDE" "$SWIFT_SOURCE_DIR/Services"

echo ""
echo "Identity-continuity risk scan"
warn_if_found "editor recreation or replacement risk" "NSTextView\\(|NSScrollView\\(|dismantleNSView|makeNSView|\\.id\\(" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "identity reset risk" "ObjectIdentifier|identity\\(|replacement|reset|continuity|activeTabID|activeFileID" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "textStorage ownership mutation" "textStorage\\s*=|NSTextStorage\\(|setAttributedString|addLayoutManager|removeLayoutManager" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/IDE/Console"
warn_if_found "layoutManager reassignment" "layoutManager\\s*=|NSLayoutManager\\(|addLayoutManager|removeLayoutManager" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/IDE/Console"
warn_if_found "UndoManager recreation" "UndoManager\\(|undoManager\\s*=|allowsUndo|removeAllActions" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/IDE/Console"
warn_if_found "responder-chain disruption" "firstResponder|makeFirstResponder|becomeFirstResponder|resignFirstResponder|sendAction" "$SWIFT_SOURCE_DIR/IDE" "$SWIFT_SOURCE_DIR/App"
warn_if_found "inspector canonical-owner creep" "RuntimeInvariantInspector.*route|RuntimeInvariantInspector.*set|RuntimeInvariantInspector.*mutat|snapshot-owner|canonical|owner" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/Services"

echo ""
echo "Externalized observability risk scan"
warn_if_found "overlay introduction risk" "\\.overlay\\(|ZStack|GeometryReader|Canvas\\(" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "render-path instrumentation risk" "drawGlyphs|drawBackground|layoutManager.*delegate|temporaryAttribute|invalidateDisplay|setNeedsDisplay" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "lifecycle participation risk" "RuntimeInvariantInspector\\.(register|unregister|updateActive|recordSelection|writeDump)|onAppear|onDisappear|task\\(" "$SWIFT_SOURCE_DIR/IDE/Editor" "$SWIFT_SOURCE_DIR/App"
warn_if_found "strong editor retention risk" "var textView: NSTextView|let textView: NSTextView|\\[NSTextView\\]|NSTextView\\]" "$SWIFT_SOURCE_DIR/IDE" "$SWIFT_SOURCE_DIR/Services"
warn_if_found "ownership duplication risk" "activeEditor|currentEditor|editorOwner|diagnosticsOwner|routingOwner|canonicalOwner" "$SWIFT_SOURCE_DIR"
warn_if_found "continuity instability risk" "ObjectIdentifier|prior.*identity|replacement suspicion|identity reset|continuity-warning" "$SWIFT_SOURCE_DIR/IDE/Editor"
warn_if_found "layoutManager replacement risk" "layoutManager\\s*=|NSLayoutManager\\(|addLayoutManager|removeLayoutManager" "$SWIFT_SOURCE_DIR"
warn_if_found "textStorage replacement risk" "textStorage\\s*=|NSTextStorage\\(|setAttributedString" "$SWIFT_SOURCE_DIR"

echo ""
echo "Giant Swift files over ${GIANT_FILE_LINES} lines"
if find "$SWIFT_SOURCE_DIR" -name '*.swift' -print0 | xargs -0 wc -l | awk -v threshold="$GIANT_FILE_LINES" '$1 > threshold && $2 != "total" { print }' | sed -n '1,20p'; then
  :
fi

echo ""
echo "DispatchQueue.main.async counts"
if find "$SWIFT_SOURCE_DIR" -name '*.swift' -print0 | while IFS= read -r -d '' swift_file; do
  count="$(rg -c "DispatchQueue\\.main\\.async" "$swift_file" 2>/dev/null || true)"
  if [ "${count:-0}" -ge "$ASYNC_WARN_COUNT" ]; then
    echo "$count $swift_file"
  fi
done | sed -n '1,20p'; then
  :
fi

echo ""
echo "Known bad pattern scan terms"
patterns=()
in_terms=0
while IFS= read -r line; do
  if [ "$line" = "## Review Scan Terms" ]; then
    in_terms=1
    continue
  fi
  if [ "$in_terms" -eq 1 ] && [ "$line" = '```text' ]; then
    continue
  fi
  if [ "$in_terms" -eq 1 ] && [ "$line" = '```' ]; then
    break
  fi
  if [ "$in_terms" -eq 1 ] && [ -n "$line" ]; then
    patterns+=("$line")
  fi
done < "$VAULT_DIR/Known Bad Patterns.md"

scan_paths=(
  "Apps/SwiftPlaygroundPlusPlusStudio/Sources"
)

for pattern in "${patterns[@]}"; do
  if rg -n --fixed-strings "$pattern" "${scan_paths[@]}" >/tmp/spp-review-pattern.out 2>/dev/null; then
    echo "pattern: $pattern"
    sed -n '1,8p' /tmp/spp-review-pattern.out
  fi
done

echo ""
echo "Architecture severity levels"
sed -n '/## Severity Levels/,+6p' "$VAULT_DIR/Architecture Contracts.md"

echo ""
echo "Editor invariants"
sed -n '1,120p' "$VAULT_DIR/Editor Invariants.md"

echo ""
echo "Unsafe-to-continue gate"
"$ROOT_DIR/script/spp-workspace.sh" unsafe-to-continue || true

echo ""
echo "Known failure modes"
sed -n '1,220p' "$VAULT_DIR/Known Failure Modes.md"

echo ""
echo "Verification flows"
sed -n '1,220p' "$VAULT_DIR/VerificationFlows/README.md"

echo ""
echo "Known bad patterns"
sed -n '1,220p' "$VAULT_DIR/Known Bad Patterns.md"

echo ""
echo "Suggested Codex review prompt"
echo "Use SPPStudioDocs/AgentPrompts/review-latest-diff.md."
echo "Prioritize Critical and High findings. Treat pattern hits as review leads, not automatic failures."
