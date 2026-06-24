#!/usr/bin/env bash
#
# run_tests.sh — test-suite runner for the council-review skill (QA Engineer).
#
# Auto-detects the test runner, runs it with a timeout, and prints a STRUCTURED
# summary — not raw test output. The STATUS line is contractual: the QA Engineer
# must never imply a suite ran unless STATUS is PASSED or FAILED.
#
#   STATUS: PASSED   — runner ran, all tests passed
#   STATUS: FAILED   — runner ran, some tests failed
#   STATUS: NOT_RUN  — no runner found, tool missing, or timed out (reviewer must
#                      say "tests not executed" and review tests statically)
#
# Usage:
#   run_tests.sh [path] [--timeout <seconds>]   (path defaults to ".", timeout 120)
#
# Targets bash 3.2+.

set -u

DIR="."
TIMEOUT="${COUNCIL_TEST_TIMEOUT:-120}"

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-120}"; shift 2 || shift ;;
    *) DIR="$1"; shift ;;
  esac
done

cd "$DIR" 2>/dev/null || { echo "=== TEST RESULTS ==="; echo "STATUS: NOT_RUN"; echo "REASON: cannot cd to $DIR"; echo "=== TEST RESULTS COMPLETE ==="; exit 0; }

have() { command -v "$1" >/dev/null 2>&1; }

# Pick a timeout wrapper if one exists; otherwise run without (and note it).
TIMEOUT_BIN=""
if have timeout; then TIMEOUT_BIN="timeout"; elif have gtimeout; then TIMEOUT_BIN="gtimeout"; fi
run_with_timeout() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$TIMEOUT" "$@"
  else
    "$@"
  fi
}

echo "=== TEST RESULTS ==="

# ----------------------------------------------------------------------------- detect runner
RUNNER=""; CMD=""
if [ -f package.json ]; then
  if grep -q '"test"' package.json 2>/dev/null && ! grep -q 'no test specified' package.json 2>/dev/null; then
    RUNNER="npm"; CMD="npm test --silent"
  elif have npx && grep -q 'vitest' package.json 2>/dev/null; then
    RUNNER="vitest"; CMD="npx vitest run"
  elif have npx && grep -q 'jest' package.json 2>/dev/null; then
    RUNNER="jest"; CMD="npx jest"
  fi
elif [ -f go.mod ]; then
  RUNNER="go"; CMD="go test ./..."
elif [ -f Cargo.toml ]; then
  RUNNER="cargo"; CMD="cargo test"
elif have pytest && { [ -d tests ] || ls -1 test_*.py *_test.py >/dev/null 2>&1 || [ -f pyproject.toml ] || [ -f setup.py ]; }; then
  RUNNER="pytest"; CMD="pytest -q"
elif [ -f Gemfile ] && have bundle && [ -d spec ]; then
  RUNNER="rspec"; CMD="bundle exec rspec"
elif [ -f phpunit.xml ] || [ -f phpunit.xml.dist ]; then
  RUNNER="phpunit"; CMD="./vendor/bin/phpunit"
fi

if [ -z "$RUNNER" ]; then
  echo "STATUS: NOT_RUN"
  echo "REASON: no recognized test runner / test files detected"
  echo "=== TEST RESULTS COMPLETE ==="
  exit 0
fi

# Verify the runner's binary is actually callable.
first_word="${CMD%% *}"
if ! have "$first_word"; then
  echo "STATUS: NOT_RUN"
  echo "RUNNER: $RUNNER"
  echo "REASON: '$first_word' not installed — cannot execute '$CMD'"
  echo "=== TEST RESULTS COMPLETE ==="
  exit 0
fi

echo "RUNNER: $RUNNER"
echo "COMMAND: $CMD"
[ -z "$TIMEOUT_BIN" ] && echo "NOTE: no 'timeout' binary available — ran without a time limit"
echo "TIMEOUT_SECONDS: $TIMEOUT"

# ----------------------------------------------------------------------------- run
OUT_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/council_tests.$$")"
# shellcheck disable=SC2086
run_with_timeout $CMD >"$OUT_FILE" 2>&1
EXIT=$?

echo "EXIT_CODE: $EXIT"
if [ "$EXIT" -eq 124 ] && [ -n "$TIMEOUT_BIN" ]; then
  echo "STATUS: NOT_RUN"
  echo "REASON: timed out after ${TIMEOUT}s (suite did not finish)"
elif [ "$EXIT" -eq 0 ]; then
  echo "STATUS: PASSED"
else
  echo "STATUS: FAILED"
fi

# ----------------------------------------------------------------------------- summary line (best effort)
summary="$(grep -iE 'tests?:|passing|failing|passed|failed|[0-9]+ (passed|failed|error)|ok |FAIL' "$OUT_FILE" 2>/dev/null | tail -n 5)"
if [ -n "$summary" ]; then
  echo "--- summary lines ---"
  printf '%s\n' "$summary"
fi

# ----------------------------------------------------------------------------- failure excerpt
if [ "$EXIT" -ne 0 ]; then
  echo "--- failure output (last 40 lines) ---"
  tail -n 40 "$OUT_FILE"
fi

rm -f "$OUT_FILE" 2>/dev/null
echo "=== TEST RESULTS COMPLETE ==="
