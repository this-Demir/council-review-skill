#!/usr/bin/env bash
#
# scan_secrets.sh — secret scanner for the council-review skill.
#
# Tries gitleaks, then trufflehog, then falls back to a built-in grep for common
# secret patterns. ALWAYS prints which scanner ran (SCANNER: line) so the Security
# Sentinel can distinguish a deep scan from the grep fallback and never overstate.
#
# Usage:
#   scan_secrets.sh [path]    (defaults to current directory)
#
# Never fails silently: prints findings, or a clear "no secrets detected" / fallback note.
# Targets bash 3.2+.

set -u

TARGET="${1:-.}"

have() { command -v "$1" >/dev/null 2>&1; }

echo "=== SECRETS SCAN ==="
echo "TARGET: $TARGET"

# ----------------------------------------------------------------------------- gitleaks
if have gitleaks; then
  echo "SCANNER: gitleaks"
  tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/gitleaks.$$.json")"
  # `detect` needs a git repo; `dir` scans the filesystem. Pick based on repo state.
  if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gitleaks detect --source "$TARGET" --no-banner --redact \
      --report-format json --report-path "$tmp" >/dev/null 2>&1
  else
    gitleaks dir "$TARGET" --no-banner --redact \
      --report-format json --report-path "$tmp" >/dev/null 2>&1
  fi
  if [ -s "$tmp" ] && [ "$(tr -d '[:space:]' < "$tmp")" != "[]" ]; then
    if have jq; then
      jq -r '.[] | "FINDING [HIGH] \(.File):\(.StartLine) — rule=\(.RuleID) match=\(.Match)"' "$tmp" 2>/dev/null
      echo "COUNT: $(jq 'length' "$tmp" 2>/dev/null)"
    else
      echo "(findings present; install jq for parsed output)"
      grep -E '"File"|"StartLine"|"RuleID"' "$tmp" | head -n 60
    fi
  else
    echo "RESULT: no secrets detected by gitleaks"
  fi
  rm -f "$tmp" 2>/dev/null
  echo "=== SECRETS SCAN COMPLETE ==="
  exit 0
fi

# ----------------------------------------------------------------------------- trufflehog
if have trufflehog; then
  echo "SCANNER: trufflehog"
  out="$(trufflehog filesystem "$TARGET" --no-update --json 2>/dev/null)"
  if [ -n "$out" ]; then
    if have jq; then
      printf '%s\n' "$out" | jq -r 'select(.SourceMetadata!=null) | "FINDING [HIGH] \(.SourceMetadata.Data.Filesystem.file // "?") — detector=\(.DetectorName // "?")"' 2>/dev/null
    else
      printf '%s\n' "$out" | head -n 60
    fi
  else
    echo "RESULT: no secrets detected by trufflehog"
  fi
  echo "=== SECRETS SCAN COMPLETE ==="
  exit 0
fi

# ----------------------------------------------------------------------------- grep fallback
echo "SCANNER: grep-fallback"
echo "NOTE: neither gitleaks nor trufflehog is installed — ran a basic pattern grep."
echo "      Install gitleaks for deeper, lower-false-positive scanning."

EXCLUDES="--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build --exclude-dir=.venv --exclude-dir=venv"

# Patterns are kept as parallel arrays (not a |-delimited string) deliberately:
# several regexes contain `|` alternation, which any pipe-delimited parsing would
# mangle. Order matters — classification takes the FIRST matching pattern, so the
# higher-severity HIGH patterns precede the MEDIUM ones.
SEVS=(HIGH HIGH HIGH HIGH HIGH MEDIUM MEDIUM)
LABELS=(
  "AWS access key id"
  "Private key (PEM)"
  "Slack token"
  "GitHub token"
  "Google API key"
  "JWT"
  "Generic secret assignment"
)
PATS=(
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----'
  'xox[baprs]-[0-9A-Za-z-]{10,}'
  'gh[pousr]_[0-9A-Za-z]{36,}'
  'AIza[0-9A-Za-z_-]{35}'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  '(secret|password|passwd|api[_-]?key|token|access[_-]?key)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/+_=-]{12,}'
)

# Walk the tree ONCE with every pattern as a separate -e, instead of one full
# recursive grep per pattern. The expensive part is the filesystem traversal;
# classifying which pattern each hit matched is cheap and happens in-memory below.
# -I skip binary, -E extended regex, -n line numbers, -r recursive.
GREP_ARGS=()
for p in "${PATS[@]}"; do GREP_ARGS+=(-e "$p"); done
matches="$(grep -rIEn $EXCLUDES "${GREP_ARGS[@]}" "$TARGET" 2>/dev/null | head -n 50)"

HITS=0
if [ -n "$matches" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Attribute the line to the first (highest-severity) pattern it matches.
    i=0; n=${#PATS[@]}
    while [ "$i" -lt "$n" ]; do
      if printf '%s' "$content" | grep -Eq -e "${PATS[$i]}"; then
        echo "FINDING [${SEVS[$i]}] $file:$lineno — possible ${LABELS[$i]}"
        HITS=$((HITS + 1))
        break
      fi
      i=$((i + 1))
    done
  done <<EOF
$matches
EOF
fi

if [ "$HITS" -eq 0 ]; then
  echo "RESULT: no secrets matched by basic grep (low confidence — patterns are limited)"
else
  echo "COUNT: $HITS candidate line(s) — review each; grep fallback has false positives"
fi

echo "=== SECRETS SCAN COMPLETE ==="
