#!/usr/bin/env bash
#
# check_deps.sh — dependency vulnerability audit for the council-review skill.
#
# This is the SINGLE SOURCE OF TRUTH for CVEs. The Security Sentinel must cite
# vulnerabilities only from this output — never from memory. Detects the package
# manager, runs the matching audit tool, and prints CVE id / severity / affected /
# fixed version where the tool provides it.
#
# Usage:
#   check_deps.sh [path]    (defaults to current directory)
#
# Degrades gracefully: if the audit tool is missing, says so clearly and does not
# pretend to have audited.
# Targets bash 3.2+.

set -u

cd "${1:-.}" 2>/dev/null || { echo "ERROR: cannot cd to ${1:-.}"; exit 0; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "=== DEPENDENCY AUDIT ==="

ran="no"

# ----------------------------------------------------------------------------- Node
if [ -f package.json ]; then
  ran="yes"
  echo "ECOSYSTEM: Node.js"
  if have npm; then
    echo "TOOL: npm audit"
    if have jq; then
      audit="$(npm audit --json 2>/dev/null)"
      if [ -n "$audit" ]; then
        printf '%s\n' "$audit" | jq -r '
          (.vulnerabilities // {}) | to_entries[] |
          "VULN [\(.value.severity|ascii_upcase)] \(.key) — range=\(.value.range)" +
          (if (.value.via|type)=="array" then
             ([.value.via[] | select(type=="object") | "\n  via \(.title // .name) cve=\((.cve//[])|join(","))  url=\(.url // "")"] | join(""))
           else "" end)' 2>/dev/null
        printf '%s\n' "$audit" | jq -r '
          .metadata.vulnerabilities // {} |
          "SUMMARY: critical=\(.critical // 0) high=\(.high // 0) moderate=\(.moderate // 0) low=\(.low // 0)"' 2>/dev/null
      else
        echo "RESULT: npm audit produced no output (no lockfile? run 'npm install' first)"
      fi
    else
      echo "(jq not installed — raw npm audit follows)"
      npm audit 2>/dev/null | head -n 60 || echo "RESULT: npm audit failed"
    fi
  else
    echo "STATUS: NOT_AUDITED — npm not installed. Install Node.js/npm to audit."
  fi
fi

# ----------------------------------------------------------------------------- Python
if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f Pipfile ]; then
  ran="yes"
  echo "ECOSYSTEM: Python"
  if have pip-audit; then
    echo "TOOL: pip-audit"
    if [ -f requirements.txt ]; then
      pip-audit -r requirements.txt 2>/dev/null | head -n 80 || echo "RESULT: pip-audit failed"
    else
      pip-audit 2>/dev/null | head -n 80 || echo "RESULT: pip-audit failed"
    fi
  else
    echo "STATUS: NOT_AUDITED — pip-audit not installed. Install with: pip install pip-audit"
  fi
fi

# ----------------------------------------------------------------------------- Go
if [ -f go.mod ]; then
  ran="yes"
  echo "ECOSYSTEM: Go"
  if have govulncheck; then
    echo "TOOL: govulncheck"
    govulncheck ./... 2>/dev/null | head -n 80 || echo "RESULT: govulncheck failed"
  else
    echo "STATUS: NOT_AUDITED — govulncheck not installed."
    echo "Install with: go install golang.org/x/vuln/cmd/govulncheck@latest"
  fi
fi

# ----------------------------------------------------------------------------- Rust
if [ -f Cargo.toml ]; then
  ran="yes"
  echo "ECOSYSTEM: Rust"
  if have cargo-audit || cargo audit --version >/dev/null 2>&1; then
    echo "TOOL: cargo audit"
    cargo audit 2>/dev/null | head -n 80 || echo "RESULT: cargo audit failed"
  else
    echo "STATUS: NOT_AUDITED — cargo-audit not installed. Install with: cargo install cargo-audit"
  fi
fi

# ----------------------------------------------------------------------------- Ruby
if [ -f Gemfile ]; then
  ran="yes"
  echo "ECOSYSTEM: Ruby"
  if have bundle-audit || have bundler-audit; then
    echo "TOOL: bundler-audit"
    bundle-audit check --update 2>/dev/null | head -n 80 || bundler-audit check 2>/dev/null | head -n 80 || echo "RESULT: bundler-audit failed"
  else
    echo "STATUS: NOT_AUDITED — bundler-audit not installed. Install with: gem install bundler-audit"
  fi
fi

# ----------------------------------------------------------------------------- PHP
if [ -f composer.json ]; then
  ran="yes"
  echo "ECOSYSTEM: PHP"
  if have composer; then
    echo "TOOL: composer audit"
    composer audit 2>/dev/null | head -n 80 || echo "RESULT: composer audit failed"
  else
    echo "STATUS: NOT_AUDITED — composer not installed."
  fi
fi

if [ "$ran" = "no" ]; then
  echo "ECOSYSTEM: unknown"
  echo "STATUS: NOT_AUDITED — no recognized dependency manifest found."
fi

echo "=== DEPENDENCY AUDIT COMPLETE ==="
