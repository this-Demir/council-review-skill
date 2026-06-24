#!/usr/bin/env bash
#
# gather_context.sh — Phase 1 context gatherer for the council-review skill.
#
# Collects everything the AI council needs before it starts reviewing, and prints
# it as structured, section-delimited text for Claude to read (not for humans).
#
# Usage:
#   gather_context.sh --pr <number>      Review a GitHub pull request
#   gather_context.sh --issue <number>   Review work done for an issue (branch vs base)
#   gather_context.sh --path <path>      Review a specific file or directory
#   gather_context.sh                    Full-codebase survey mode
#
# Degrades gracefully: works without `gh` (git-only), and without git (filesystem-only).
# Targets bash 3.2+ (macOS default). No bashisms beyond 3.2.

set -u

# ----------------------------------------------------------------------------- helpers
have() { command -v "$1" >/dev/null 2>&1; }

section() { printf '\n=== %s ===\n' "$1"; }

# Print up to N lines of a command's output, noting if truncated.
print_capped() {
  cap="$1"; shift
  out="$("$@" 2>/dev/null)"
  if [ -z "$out" ]; then
    echo "(none)"
    return
  fi
  total="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  printf '%s\n' "$out" | head -n "$cap"
  if [ "$total" -gt "$cap" ]; then
    echo "... (${total} lines total, showing first ${cap})"
  fi
}

in_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Resolve the base branch to diff against: prefer main, then master, then any.
base_branch() {
  for b in main master; do
    if git show-ref --verify --quiet "refs/heads/$b"; then echo "$b"; return; fi
  done
  # fall back to the upstream's default if known
  git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'
}

# ----------------------------------------------------------------------------- args
MODE="codebase"
PR=""; ISSUE=""; TARGET_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)    MODE="pr";    PR="${2:-}";          shift 2 || shift ;;
    --issue) MODE="issue"; ISSUE="${2:-}";       shift 2 || shift ;;
    --path)  MODE="path";  TARGET_PATH="${2:-}"; shift 2 || shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "WARNING: ignoring unknown argument: $1" >&2; shift ;;
  esac
done

GH_OK="no"; have gh && gh auth status >/dev/null 2>&1 && GH_OK="yes"
GIT_OK="no"; in_git_repo && GIT_OK="yes"

# ----------------------------------------------------------------------------- env header
section "CONTEXT MODE"
echo "MODE: $MODE"
echo "GIT_AVAILABLE: $GIT_OK"
echo "GH_AVAILABLE: $GH_OK"
[ "$MODE" = "pr" ]    && echo "PR: ${PR:-<missing>}"
[ "$MODE" = "issue" ] && echo "ISSUE: ${ISSUE:-<missing>}"
[ "$MODE" = "path" ]  && echo "PATH: ${TARGET_PATH:-<missing>}"

# ----------------------------------------------------------------------------- project / stack
section "PROJECT STACK"
detected="no"
detect() { # file  label
  if [ -f "$1" ]; then echo "DETECTED: $2 ($1)"; detected="yes"; fi
}
detect package.json     "Node.js / JavaScript / TypeScript"
detect requirements.txt "Python (pip)"
detect pyproject.toml   "Python (pyproject)"
detect Pipfile          "Python (pipenv)"
detect go.mod           "Go"
detect Cargo.toml       "Rust"
detect Gemfile          "Ruby"
detect pom.xml          "Java (Maven)"
detect build.gradle     "Java/Kotlin (Gradle)"
detect build.gradle.kts "Kotlin (Gradle)"
detect composer.json    "PHP (Composer)"
detect Dockerfile       "Docker"
[ "$detected" = "no" ] && echo "DETECTED: unknown — could not identify language/framework from manifest files"

if [ -f package.json ]; then
  echo "--- package.json scripts ---"
  if have jq; then
    jq -r '.scripts // {} | to_entries[] | "  \(.key): \(.value)"' package.json 2>/dev/null || echo "(unparseable)"
  else
    grep -A 30 '"scripts"' package.json 2>/dev/null | head -n 20
  fi
fi

# ----------------------------------------------------------------------------- git state (always when available)
if [ "$GIT_OK" = "yes" ]; then
  section "GIT STATE"
  echo "BRANCH: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "BASE_BRANCH: $(base_branch)"
  echo "LAST_COMMIT: $(git log -1 --pretty='%h %s' 2>/dev/null)"
  echo "--- uncommitted changes (git status --short) ---"
  print_capped 40 git status --short
else
  section "GIT STATE"
  echo "(not a git repository — git-based context unavailable)"
fi

# ----------------------------------------------------------------------------- env surface
section "ENV SURFACE"
found_env="no"
for f in .env.example .env.sample .env.template; do
  if [ -f "$f" ]; then
    echo "--- $f (keys only) ---"
    # show variable names only, never values
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$f" 2>/dev/null | sed 's/=.*$/=<redacted>/' | head -n 40
    found_env="yes"
  fi
done
[ "$found_env" = "no" ] && echo "(no .env.example / .env.sample found)"

# ----------------------------------------------------------------------------- mode-specific
case "$MODE" in
  pr)
    section "PULL REQUEST"
    if [ -z "$PR" ]; then
      echo "ERROR: --pr requires a number"
    elif [ "$GH_OK" = "yes" ]; then
      echo "--- metadata ---"
      gh pr view "$PR" --json number,title,body,baseRefName,headRefName,author,files \
        --template '{{.title}} (#{{.number}}) by {{.author.login}}
base: {{.baseRefName}} <- head: {{.headRefName}}

{{.body}}

files changed:
{{range .files}}  {{.path}} (+{{.additions}}/-{{.deletions}})
{{end}}' 2>/dev/null || echo "(gh pr view failed — PR may not exist or no access)"
      section "DIFF"
      print_capped 800 gh pr diff "$PR"
    else
      echo "gh CLI not available/authenticated — cannot fetch PR #$PR."
      echo "FALLBACK: install and run 'gh auth login', or re-run in --issue/--path mode."
      if [ "$GIT_OK" = "yes" ]; then
        echo "--- best-effort: diff of current branch vs base ---"
        bb="$(base_branch)"
        [ -n "$bb" ] && print_capped 800 git diff "$bb"...HEAD
      fi
    fi
    ;;

  issue)
    section "ISSUE"
    if [ "$GH_OK" = "yes" ] && [ -n "$ISSUE" ]; then
      gh issue view "$ISSUE" --json number,title,body,state \
        --template '{{.title}} (#{{.number}}) [{{.state}}]

{{.body}}' 2>/dev/null || echo "(gh issue view failed)"
    else
      echo "(issue text unavailable — gh missing/unauth or no issue number)"
    fi
    if [ "$GIT_OK" = "yes" ]; then
      bb="$(base_branch)"
      section "COMMITS ON THIS BRANCH"
      if [ -n "$bb" ]; then print_capped 50 git log "$bb"..HEAD --oneline; else echo "(no base branch found)"; fi
      section "DIFF (branch vs base)"
      if [ -n "$bb" ]; then print_capped 800 git diff "$bb"...HEAD; else echo "(no base branch to diff against)"; fi
    fi
    ;;

  path)
    section "PATH CONTENTS"
    if [ -z "$TARGET_PATH" ]; then
      echo "ERROR: --path requires a path"
    elif [ -d "$TARGET_PATH" ]; then
      echo "--- files under $TARGET_PATH ---"
      print_capped 60 find "$TARGET_PATH" -type f \
        \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
           -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.rb' \
           -o -name '*.java' -o -name '*.php' -o -name '*.c' -o -name '*.cpp' \)
    elif [ -f "$TARGET_PATH" ]; then
      echo "--- $TARGET_PATH ---"
      print_capped 600 cat "$TARGET_PATH"
    else
      echo "ERROR: path not found: $TARGET_PATH"
    fi
    ;;

  codebase)
    section "CODEBASE SURVEY"
    echo "--- top-level layout ---"
    print_capped 40 ls -1A
    if [ "$GIT_OK" = "yes" ]; then
      echo "--- recent activity (last 20 commits) ---"
      print_capped 20 git log --oneline -20
      echo "--- recent change (last 5 commits, diffstat) ---"
      print_capped 60 git diff --stat HEAD~5..HEAD
    fi
    echo "--- rough test footprint ---"
    tc="$(find . -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.go' -o -name 'test_*.py' \) \
          -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    echo "TEST_FILES_FOUND: $tc"
    ;;
esac

section "CONTEXT GATHERING COMPLETE"
