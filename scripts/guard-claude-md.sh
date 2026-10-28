#!/usr/bin/env bash
# PreToolUse hook: ask the human to confirm before an agent edits the root
# CLAUDE.md (or AGENTS.md, which is a symlink to it).
set -u

input=$(cat)
file=$(printf '%s' "$input" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
[ -z "$file" ] && exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$file" in
  /*) ;;
  *) file="$root/$file" ;;
esac

case "$file" in
  "$root/CLAUDE.md" | "$root/AGENTS.md")
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"CLAUDE.md is the protected agent constitution. Approve only if you explicitly asked for this change."}}'
    ;;
esac
exit 0
