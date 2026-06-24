#!/usr/bin/env bash
#
# run.sh — integration tests for the council-review skill's helper scripts.
#
# These scripts are the only executable surface of the skill, and they encode the
# review-integrity rules (no fabricated secrets, honest test STATUS, never fail
# silently). This harness builds throwaway fixtures and asserts each script's
# output contract — especially the graceful-degradation / fallback paths.
#
# No external test framework (bats) is required; pure bash 3.2+.
#
# Usage:
#   tests/run.sh            run everything
#   tests/run.sh -v         verbose (print captured output on failure)
#
# Exit code: 0 if all tests pass, 1 otherwise.

set -u

VERBOSE="no"
[ "${1:-}" = "-v" ] && VERBOSE="yes"

# ----------------------------------------------------------------------------- locations
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
SCRIPTS="$SKILL_ROOT/scripts"

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/council-tests.$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Keep git quiet and hermetic regardless of the user's global config.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
GIT="git -c user.email=test@example.com -c user.name=test -c init.defaultBranch=main -c commit.gpgsign=false"

# ----------------------------------------------------------------------------- harness
PASS=0; FAIL=0
CURRENT=""        # name of the test being run
LAST_OUT=""       # captured output of the most recent run_script

note() { printf '   %s\n' "$1"; }

start() { CURRENT="$1"; printf '• %s\n' "$1"; }

# Run a script, capturing combined stdout+stderr into LAST_OUT and its exit code.
LAST_CODE=0
run_script() {
  LAST_OUT="$("$@" 2>&1)"
  LAST_CODE=$?
}

fail() {
  FAIL=$((FAIL + 1))
  printf '   FAIL: %s\n' "$1"
  if [ "$VERBOSE" = "yes" ]; then
    printf '   ----- captured output -----\n%s\n   ---------------------------\n' "$LAST_OUT"
  fi
}
ok() { PASS=$((PASS + 1)); printf '   ok: %s\n' "$1"; }

assert_contains() { # needle  message
  case "$LAST_OUT" in
    *"$1"*) ok "$2" ;;
    *)      fail "$2 (expected to contain: $1)" ;;
  esac
}
assert_not_contains() { # needle  message
  case "$LAST_OUT" in
    *"$1"*) fail "$2 (did NOT expect: $1)" ;;
    *)      ok "$2" ;;
  esac
}
assert_code() { # expected  message
  if [ "$LAST_CODE" -eq "$1" ]; then ok "$2"; else fail "$2 (exit $LAST_CODE, expected $1)"; fi
}
assert_file() { # path  message
  if [ -f "$1" ]; then ok "$2"; else fail "$2 (missing file: $1)"; fi
}

# Make a fresh fixture dir and echo its path.
fixture() { d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d"; echo "$d"; }

# =============================================================================
# scan_secrets.sh
# =============================================================================
start "scan_secrets: detects a planted AWS key (grep fallback)"
d="$(fixture secrets_hit)"
printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$d/config.js"
run_script bash "$SCRIPTS/scan_secrets.sh" "$d"
assert_contains "=== SECRETS SCAN ==="          "prints scan header"
assert_contains "SCANNER:"                       "declares which scanner ran"
assert_contains "FINDING [HIGH]"                 "flags the key as HIGH"
assert_contains "AWS access key id"              "names the secret type"
assert_contains "=== SECRETS SCAN COMPLETE ==="  "prints completion marker"

start "scan_secrets: clean dir reports no secrets"
d="$(fixture secrets_clean)"
printf 'export const greeting = "hello world";\n' > "$d/app.js"
run_script bash "$SCRIPTS/scan_secrets.sh" "$d"
assert_contains "no secrets"                     "reports nothing found"
assert_not_contains "FINDING [HIGH]"             "no false-positive HIGH finding"

start "scan_secrets: empty / too-short values do not trip the generic pattern"
# The generic-secret regex requires a value of 12+ chars after the = / : . An empty
# string or a 1-char value must NOT match — this pins the {12,} boundary.
d="$(fixture secrets_boundary)"
printf 'password = ""\napi_key: x\nconst note = "ok";\n' > "$d/conf.txt"
run_script bash "$SCRIPTS/scan_secrets.sh" "$d"
assert_contains "no secrets"                     "empty and <12-char values yield no finding"
assert_not_contains "FINDING"                    "no generic-secret false positive on short values"

# =============================================================================
# check_deps.sh
# =============================================================================
start "check_deps: no manifest => NOT_AUDITED / unknown ecosystem"
d="$(fixture deps_none)"
printf 'just some text\n' > "$d/readme.txt"
run_script bash "$SCRIPTS/check_deps.sh" "$d"
assert_contains "=== DEPENDENCY AUDIT ==="       "prints audit header"
assert_contains "ECOSYSTEM: unknown"             "identifies unknown ecosystem"
assert_contains "NOT_AUDITED"                    "honestly says it did not audit"

start "check_deps: package.json => detects Node ecosystem"
d="$(fixture deps_node)"
printf '{"name":"x","version":"1.0.0","dependencies":{}}\n' > "$d/package.json"
run_script bash "$SCRIPTS/check_deps.sh" "$d"
assert_contains "ECOSYSTEM: Node.js"             "detects Node.js"
assert_contains "=== DEPENDENCY AUDIT COMPLETE ===" "prints completion marker"

# =============================================================================
# run_tests.sh  (STATUS line is contractual)
# =============================================================================
start "run_tests: no runner => STATUS NOT_RUN"
d="$(fixture tests_none)"
printf 'plain file\n' > "$d/notes.txt"
run_script bash "$SCRIPTS/run_tests.sh" "$d"
assert_contains "=== TEST RESULTS ==="           "prints results header"
assert_contains "STATUS: NOT_RUN"                "honest NOT_RUN when no runner"

start "run_tests: passing npm test => STATUS PASSED"
d="$(fixture tests_pass)"
printf '{"name":"x","version":"1.0.0","scripts":{"test":"node -e \\"process.exit(0)\\""}}\n' > "$d/package.json"
run_script bash "$SCRIPTS/run_tests.sh" "$d"
assert_contains "STATUS: PASSED"                 "reports PASSED on green suite"

start "run_tests: failing npm test => STATUS FAILED"
d="$(fixture tests_fail)"
printf '{"name":"x","version":"1.0.0","scripts":{"test":"node -e \\"process.exit(1)\\""}}\n' > "$d/package.json"
run_script bash "$SCRIPTS/run_tests.sh" "$d"
assert_contains "STATUS: FAILED"                 "reports FAILED on red suite"
assert_not_contains "STATUS: PASSED"             "does not also claim PASSED"

start "run_tests: pytest that collects nothing => STATUS NOT_RUN (not FAILED)"
# pytest exits 5 on "no tests collected". Shim a fake pytest on PATH so this is
# hermetic and does not depend on pytest actually being installed.
d="$(fixture tests_pytest_empty)"
printf '[project]\nname = "x"\n' > "$d/pyproject.toml"
bin="$d/bin"; mkdir -p "$bin"
printf '#!/usr/bin/env bash\necho "no tests ran"\nexit 5\n' > "$bin/pytest"
chmod +x "$bin/pytest"
run_script bash -c "PATH=\"$bin:\$PATH\" bash '$SCRIPTS/run_tests.sh' '$d'"
assert_contains "RUNNER: pytest"      "selects pytest runner"
assert_contains "STATUS: NOT_RUN"     "no-tests-collected is NOT_RUN, not FAILED"
assert_not_contains "STATUS: FAILED"  "does not misreport empty collection as failure"

start "run_tests: bare tests/run.sh harness is detected and run"
d="$(fixture tests_shell)"
mkdir -p "$d/tests"
printf '#!/usr/bin/env bash\necho "all good"\nexit 0\n' > "$d/tests/run.sh"
chmod +x "$d/tests/run.sh"
run_script bash "$SCRIPTS/run_tests.sh" "$d"
assert_contains "RUNNER: shell"   "detects the project-local bash harness"
assert_contains "STATUS: PASSED"  "runs it and reports PASSED"

start "run_tests: failing tests/run.sh harness => STATUS FAILED"
d="$(fixture tests_shell_fail)"
mkdir -p "$d/tests"
printf '#!/usr/bin/env bash\necho "nope"\nexit 1\n' > "$d/tests/run.sh"
chmod +x "$d/tests/run.sh"
run_script bash "$SCRIPTS/run_tests.sh" "$d"
assert_contains "RUNNER: shell"   "detects the harness"
assert_contains "STATUS: FAILED"  "shell runner is not hardcoded to PASSED"

# =============================================================================
# gather_context.sh
# =============================================================================
start "gather_context: --path on a file dumps its contents"
d="$(fixture ctx_path)"
printf 'function add(a,b){return a+b}\n' > "$d/lib.js"
run_script bash "$SCRIPTS/gather_context.sh" --path "$d/lib.js"
assert_contains "=== CONTEXT MODE ==="           "prints context-mode header"
assert_contains "MODE: path"                     "records path mode"
assert_contains "=== PATH CONTENTS ==="          "prints the path section"
assert_contains "function add"                   "includes the file body"

start "gather_context: --path on a directory lists AND dumps shell files (regression)"
# Regression for the .sh-blindness bug: directory mode used to filter out shell
# scripts (and emit names only), so reviewing a shell dir returned "(none)" with no
# citable lines. It must now both list the files and dump their contents.
d="$(fixture ctx_shdir)"
printf '#!/usr/bin/env bash\necho COUNCIL_MARKER_SH\n' > "$d/tool.sh"
printf 'def f():\n    return "COUNCIL_MARKER_PY"\n' > "$d/helper.py"
run_script bash "$SCRIPTS/gather_context.sh" --path "$d"
assert_not_contains "(none)"                     "directory mode is no longer blind to shell files"
assert_contains "tool.sh"                        "lists the .sh file"
assert_contains "COUNCIL_MARKER_SH"              "dumps .sh contents (so file:line is citable)"
assert_contains "COUNCIL_MARKER_PY"              "dumps other-language contents too"

start "gather_context: codebase mode in a git repo reports git state"
d="$(fixture ctx_repo)"
( cd "$d" && $GIT init -q && printf 'hi\n' > a.txt && $GIT add a.txt && $GIT commit -qm "init" )
run_script bash -c "cd '$d' && bash '$SCRIPTS/gather_context.sh'"
assert_contains "GIT_AVAILABLE: yes"             "detects it is in a git repo"
assert_contains "=== CODEBASE SURVEY ==="        "runs codebase survey mode"
assert_contains "=== CONTEXT GATHERING COMPLETE ===" "prints completion marker"

# =============================================================================
# save_review.sh
# =============================================================================
start "save_review: writes from stdin and prints SAVED path"
d="$(fixture save_ok)"
run_script bash -c "cd '$d' && printf '## Council Verdict\nLooks good.\n' | bash '$SCRIPTS/save_review.sh'"
assert_contains "SAVED:"                          "prints the saved path"
assert_code 0                                     "exits 0 on success"
# the file should actually exist under .council-reviews/
if ls "$d/.council-reviews/"*.md >/dev/null 2>&1; then ok "review file created on disk"; else fail "review file created on disk"; fi

start "save_review: empty input is rejected"
d="$(fixture save_empty)"
run_script bash -c "cd '$d' && printf '' | bash '$SCRIPTS/save_review.sh'"
assert_contains "ERROR"                           "errors on empty content"
assert_code 1                                     "exits non-zero on empty content"

start "save_review: a second save the same day/branch does not clobber the first"
d="$(fixture save_collide)"
( cd "$d" && $GIT init -q && printf 'x\n' > a.txt && $GIT add a.txt && $GIT commit -qm init )
run_script bash -c "cd '$d' && printf 'first review\n'  | bash '$SCRIPTS/save_review.sh'"
run_script bash -c "cd '$d' && printf 'second review\n' | bash '$SCRIPTS/save_review.sh'"
count="$(ls "$d/.council-reviews/"*.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "$count" -ge 2 ]; then ok "two distinct review files exist (no clobber)"; else fail "two distinct review files exist (got $count)"; fi

# =============================================================================
# post_to_github.sh  (no network: temp repo has no remote, so gh comment fails -> fallback)
# =============================================================================
start "post_to_github: missing args => usage error, exit 1"
run_script bash "$SCRIPTS/post_to_github.sh"
assert_contains "ERROR"                           "complains about usage"
assert_code 1                                     "exits 1 on bad usage"

start "post_to_github: cannot post => writes fallback file, never silent"
d="$(fixture post_fallback)"
( cd "$d" && $GIT init -q )
printf '## Council Verdict\nShip it.\n' > "$d/review.md"
run_script bash -c "cd '$d' && bash '$SCRIPTS/post_to_github.sh' 999999 review.md"
assert_contains "SAVED_FALLBACK:"                 "saves a fallback comment file"

start "post_to_github: non-numeric PR is rejected"
d="$(fixture post_badpr)"
printf '## Council Verdict\nShip it.\n' > "$d/review.md"
run_script bash -c "cd '$d' && bash '$SCRIPTS/post_to_github.sh' not-a-number review.md"
assert_contains "PR must be a number"             "rejects a non-numeric PR id"
assert_code 1                                     "exits 1 on bad PR id"

start "post_to_github: review without a Council Verdict => warns and posts full review"
d="$(fixture post_noverdict)"
( cd "$d" && $GIT init -q )
printf '## Security Sentinel\nLooks fine.\nUNIQUE_BODY_MARKER\n' > "$d/review.md"
run_script bash -c "cd '$d' && bash '$SCRIPTS/post_to_github.sh' 999999 review.md"
assert_contains "no '## Council Verdict'"         "warns when the verdict section is missing"
assert_contains "SAVED_FALLBACK:"                 "still produces a fallback, never silent"
if [ -f "$d/.council-reviews/verdict-pr999999.md" ] && grep -q "UNIQUE_BODY_MARKER" "$d/.council-reviews/verdict-pr999999.md"; then
  ok "fallback carries the full review body (no verdict to slice)"
else
  fail "fallback carries the full review body"
fi

# =============================================================================
# summary
# =============================================================================
echo
echo "==================================="
printf 'PASSED: %d   FAILED: %d\n' "$PASS" "$FAIL"
echo "==================================="
[ "$FAIL" -eq 0 ]
