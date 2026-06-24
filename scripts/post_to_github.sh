#!/usr/bin/env bash
#
# post_to_github.sh — post the council VERDICT to a PR as a comment.
#
# Posts only the "Council Verdict" section (not the full review) via `gh pr comment`.
# If gh is missing or unauthenticated, writes the comment to a file and tells the
# user exactly how to post it manually. Never fails silently.
#
# Usage:
#   post_to_github.sh <pr-number> <review-file>
#
# Targets bash 3.2+.

set -u

PR="${1:-}"
FILE="${2:-}"

if [ -z "$PR" ] || [ -z "$FILE" ]; then
  echo "ERROR: usage: post_to_github.sh <pr-number> <review-file>" >&2
  exit 1
fi
case "$PR" in
  *[!0-9]*)
    echo "ERROR: PR must be a number (got: $PR)" >&2
    exit 1 ;;
esac
if [ ! -f "$FILE" ]; then
  echo "ERROR: review file not found: $FILE" >&2
  exit 1
fi

have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------------- extract verdict
# Pull from the "## Council Verdict" heading to the next top-level "## " or EOF.
VERDICT="$(awk '
  /^##[[:space:]]+Council Verdict/ {grab=1}
  grab && /^##[[:space:]]/ && !/Council Verdict/ {if (seen) exit}
  grab {print; seen=1}
' "$FILE")"

if [ -z "$(printf '%s' "$VERDICT" | tr -d '[:space:]')" ]; then
  echo "WARNING: no '## Council Verdict' section found — posting full review instead." >&2
  VERDICT="$(cat "$FILE")"
fi

COMMENT="$(printf '%s\n\n%s\n' "$VERDICT" "_Posted by the [council-review](https://github.com) skill._")"

# ----------------------------------------------------------------------------- post or fallback
if have gh && gh auth status >/dev/null 2>&1; then
  TMP="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/council_comment.$$.md")"
  printf '%s\n' "$COMMENT" > "$TMP"
  if gh pr comment "$PR" --body-file "$TMP" >/dev/null 2>&1; then
    echo "POSTED: verdict added as a comment to PR #$PR"
  else
    echo "ERROR: gh pr comment failed (wrong repo, no PR #$PR, or insufficient permissions)."
    FALLBACK=".council-reviews/verdict-pr${PR}.md"
    mkdir -p .council-reviews 2>/dev/null
    printf '%s\n' "$COMMENT" > "$FALLBACK"
    echo "SAVED_FALLBACK: $FALLBACK"
    echo "Post manually with: gh pr comment $PR --body-file $FALLBACK"
  fi
  rm -f "$TMP" 2>/dev/null
else
  echo "gh CLI not available or not authenticated — cannot post automatically."
  FALLBACK=".council-reviews/verdict-pr${PR}.md"
  mkdir -p .council-reviews 2>/dev/null
  printf '%s\n' "$COMMENT" > "$FALLBACK"
  echo "SAVED_FALLBACK: $FALLBACK"
  echo "To post: install gh (https://cli.github.com), run 'gh auth login', then:"
  echo "  gh pr comment $PR --body-file $FALLBACK"
fi
