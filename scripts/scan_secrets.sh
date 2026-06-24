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

# Running total of candidate lines. A function (not a |-delimited string) is used
# deliberately: several patterns contain `|` alternation, which would be mangled by
# any pipe-delimited parsing.
HITS=0
scan() { # severity  label  regex...
  sev="$1"; label="$2"; pat="$3"
  # -I skip binary, -E extended regex, -n line numbers, -r recursive
  matches="$(grep -rIEn $EXCLUDES -e "$pat" "$TARGET" 2>/dev/null | head -n 25)"
  [ -z "$matches" ] && return
  while IFS= read -r line; do
    file="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"
    echo "FINDING [$sev] $file:$lineno — possible $label"
    HITS=$((HITS + 1))
  done <<EOF
$matches
EOF
}

scan HIGH   "AWS access key id"          'AKIA[0-9A-Z]{16}'
scan HIGH   "Private key (PEM)"          '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----'
scan HIGH   "Slack token"               'xox[baprs]-[0-9A-Za-z-]{10,}'
scan HIGH   "GitHub token"              'gh[pousr]_[0-9A-Za-z]{36,}'
scan HIGH   "Google API key"           'AIza[0-9A-Za-z_-]{35}'
scan MEDIUM "JWT"                       'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
scan MEDIUM "Generic secret assignment" '(secret|password|passwd|api[_-]?key|token|access[_-]?key)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/+_=-]{12,}'

if [ "$HITS" -eq 0 ]; then
  echo "RESULT: no secrets matched by basic grep (low confidence — patterns are limited)"
else
  echo "COUNT: $HITS candidate line(s) — review each; grep fallback has false positives"
fi

echo "=== SECRETS SCAN COMPLETE ==="
