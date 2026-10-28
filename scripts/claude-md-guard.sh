#!/usr/bin/env bash
# Guards the agent constitution (root CLAUDE.md).
#   nested: fail if any CLAUDE.md other than the root one is tracked or staged.
#   warn:   print a warning when a commit changes the root CLAUDE.md (never fails).
set -u

mode="${1:-}"

case "$mode" in
  nested)
    nested=$(git ls-files -- '*CLAUDE.md' | grep -iE '(^|/)CLAUDE\.md$' | grep -vx 'CLAUDE.md' || true)
    if [ -n "$nested" ]; then
      echo "Only the root CLAUDE.md is allowed. Remove:"
      echo "$nested"
      echo "Put the content in docs/ and reference it from the root CLAUDE.md."
      exit 1
    fi
    ;;
  warn)
    if git diff --cached --name-only | grep -qx 'CLAUDE.md'; then
      echo "WARNING: this commit changes CLAUDE.md, the protected agent constitution."
      echo "Make sure a human asked for this change; it needs CODEOWNERS review."
    fi
    ;;
  *)
    echo "usage: $0 nested|warn" >&2
    exit 2
    ;;
esac
exit 0
