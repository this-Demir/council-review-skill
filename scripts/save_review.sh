#!/usr/bin/env bash
#
# save_review.sh — persist a council review to disk.
#
# Reads the review from a file argument or from stdin, writes it to
# .council-reviews/{YYYY-MM-DD}-{branch}.md with a git-context header, and prints
# the saved path so Claude can confirm to the user.
#
# Usage:
#   save_review.sh <review-file>     Save from a file
#   some_cmd | save_review.sh        Save from stdin
#
# Targets bash 3.2+.

set -u

OUTDIR=".council-reviews"

# ----------------------------------------------------------------------------- read content
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  if [ ! -f "$1" ]; then
    echo "ERROR: review file not found: $1" >&2
    exit 1
  fi
  CONTENT="$(cat "$1")"
else
  CONTENT="$(cat)"   # stdin
fi

if [ -z "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ]; then
  echo "ERROR: no review content provided (empty file/stdin)" >&2
  exit 1
fi

# ----------------------------------------------------------------------------- git context
BRANCH="nogit"; COMMIT="n/a"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  COMMIT="$(git log -1 --pretty='%h %s' 2>/dev/null || echo unknown)"
fi

# Sanitize branch for use in a filename (slashes, spaces -> dashes).
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-')"
[ -z "$SAFE_BRANCH" ] && SAFE_BRANCH="review"

DATE="$(date +%Y-%m-%d)"
STAMP="$(date '+%Y-%m-%d %H:%M:%S %z')"

mkdir -p "$OUTDIR" 2>/dev/null || { echo "ERROR: cannot create $OUTDIR" >&2; exit 1; }

OUTFILE="$OUTDIR/${DATE}-${SAFE_BRANCH}.md"

# If a review for this date+branch already exists, suffix with time to avoid clobbering.
if [ -e "$OUTFILE" ]; then
  OUTFILE="$OUTDIR/${DATE}-${SAFE_BRANCH}-$(date +%H%M%S).md"
fi

# ----------------------------------------------------------------------------- write
{
  echo "<!-- council-review -->"
  echo "**Reviewed:** $STAMP  "
  echo "**Branch:** \`$BRANCH\`  "
  echo "**Commit:** $COMMIT"
  echo
  echo "---"
  echo
  printf '%s\n' "$CONTENT"
} > "$OUTFILE"

echo "SAVED: $OUTFILE"
