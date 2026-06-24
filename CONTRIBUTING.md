# Contributing to council-review

Thanks for considering a contribution! This skill lives or dies by two things: the
**quality of each reviewer's voice** and the **trustworthiness of its findings**. Most
contributions touch one of those, so this guide is built around them.

---

## Ways to contribute

- **Bug reports** — a script that fails on your platform, a fallback that doesn't trigger, a review that hallucinated something. Open an issue with the command you ran and the output.
- **More language/tool support** — a new test runner, package manager, or audit tool in the scripts.
- **Persona tuning** — sharper voice, better example lines, clearer cross-referencing cues.
- **Docs** — clearer install steps, more usage examples, fixes to this guide.

For anything larger than a small fix, open an issue first so we can agree on the approach before you write code.

---

## Project structure

```
council-review/
├── SKILL.md                   # the brain — phases, output format, grounding rules
├── references/
│   ├── reviewer-personas.md   # voice & style guide for each reviewer
│   └── severity-guide.md      # Critical / High / Medium / Low framework
├── scripts/                   # what closes the loops Claude can't close alone
│   ├── gather_context.sh      # collects PR / issue / path / codebase context
│   ├── scan_secrets.sh        # secrets: gitleaks → trufflehog → grep fallback
│   ├── check_deps.sh          # dependency CVEs — the single source of truth
│   ├── run_tests.sh           # auto-detects & runs the test suite
│   ├── save_review.sh         # persists a review to .council-reviews/
│   └── post_to_github.sh      # posts the verdict to a PR
└── tests/
    └── run.sh                 # integration tests for the helper scripts
```

Start with `SKILL.md` to understand the flow, then `CLAUDE.md` for the design constraints.

---

## The two rules that matter most

**1. Never fail silently.** Every script must print something useful even when a tool is
missing. No `gitleaks`? Run the grep fallback and *say so*. No test runner? Print
`STATUS: NOT_RUN` with a reason. A silent exit is a bug.

**2. Grounding is non-negotiable.** The review must never invent facts. This is enforced by
the scripts' status lines and by `SKILL.md`'s "Grounding Rules" section:

- CVEs come only from `check_deps.sh` — never from the model's memory.
- `file:line` references come only from `gather_context.sh` output.
- Secrets come from `scan_secrets.sh`; flag the lower confidence of the grep fallback.
- Never imply a step ran that didn't (`STATUS: NOT_RUN` → "tests not executed").

If your change could let the council state something it can't back up, it needs to be
reworked.

---

## Script conventions

All scripts target **bash 3.2+** (macOS's default) and must stay portable:

- Shebang `#!/usr/bin/env bash` — not `#!/bin/bash`.
- No bashisms that break on 3.2 (no associative arrays / `local -n` / `${var^^}`; use `tr` etc.).
- **Output for Claude, not humans.** Structured, section-delimited text with clear headers
  like `=== SECRETS SCAN ===` and explicit status lines (`SCANNER:`, `STATUS:`, `COUNT:`).
- **Be fast** — `gather_context.sh` and `scan_secrets.sh` run before the council thinks.
- Detect tools with `command -v`, degrade gracefully, and mark new scripts executable
  (`chmod +x`).

### Testing a script change

The repo ships an integration suite that builds throwaway fixtures and asserts each
script's output contract (the `=== SECTION ===` headers and status lines the council
relies on). Run it first — it needs only bash, no test framework:

```bash
bash tests/run.sh       # all scripts; add -v to dump output on failure
```

It must end with `FAILED: 0`. The suite deliberately exercises the **fallback** paths
(grep secret scan, `NOT_AUDITED` deps) since those are what a fresh install hits. If you
add a script or a new branch, add an assertion in `tests/run.sh` for both sides of it.

For a quick manual spot-check while iterating:

```bash
# Syntax check everything
for f in scripts/*.sh; do bash -n "$f" && echo "OK: $f"; done

# Run one script against a fixture (both the tool-present and tool-missing paths)
mkdir /tmp/fix && cd /tmp/fix && git init -q
printf 'const k="AKIAIOSFODNN7EXAMPLE"\n' > app.js
bash ~/.claude/skills/council-review/scripts/scan_secrets.sh
```

Please verify **both** branches of any fallback you touch: the path where the tool exists
and the path where it doesn't.

---

## Adding or tuning a reviewer persona

A reviewer is defined in three places — keep them consistent:

1. **`SKILL.md`** — the short mandate in "The Council Members", the output block in Phase 2,
   and the voice note in Phase 3.
2. **`references/reviewer-personas.md`** — the deep voice guide: mental model, tone, what they
   do *not* say, a checklist, example lines, and when to cross-reference.
3. **`references/severity-guide.md`** — only if the reviewer assigns severities.

The test for a good persona: **cover the name and a reader should still know who's speaking.**
Voices must not blur together. Give concrete example lines with real values — never generic
advice like "add more tests".

---

## Commit & PR guidelines

- Keep commits focused; write a clear message explaining the *why*.
- In the PR description, note **how you tested** — especially which fallback branches you exercised.
- One logical change per PR where possible.
- By contributing, you agree your work is licensed under the project's [MIT License](LICENSE).

---

## Versioning & releases

The skill follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).
Because a skill has no API, the "contract" is its **invocation interface** and its
**review output structure** (the per-reviewer sections plus the "Council Verdict"):

- **MAJOR** — breaks that contract: removing or renaming a council member, changing
  the `/council-review` argument syntax, restructuring the output format that users or
  automation rely on, or renaming a script a persona depends on.
- **MINOR** — backward-compatible additions: a new reviewer, a new invocation pattern,
  a new script, or a grounding rule that only *adds* checks.
- **PATCH** — fixes and tuning with no contract change: script bug fixes, persona voice
  tuning, fallback-path fixes, documentation.

The version of record is the `version:` field in **`SKILL.md`** frontmatter. The git tag
(`vX.Y.Z`), the GitHub Release, and the `.skill` artifact name all mirror it.

We stay in `0.x` until the skill has been validated against real external repos (Node and
Python) with `gitleaks` and `shellcheck` installed — i.e. once the primary tool paths,
not just the fallbacks, are proven. `1.0.0` is cut at that point.

**Release ritual:** bump `version:` in `SKILL.md` → commit as `chore(release): vX.Y.Z` →
`git tag vX.Y.Z` → rebuild the `.skill` archive with Python's `zipfile` (never
PowerShell `Compress-Archive`, which writes backslash paths that break on macOS/Linux) →
publish a GitHub Release from the tag.

---

## Code of conduct

Be respectful and constructive. We're building a tool that gives feedback for a living —
practice what it preaches. Assume good intent, critique the code and not the person, and
keep discussions focused on making the council sharper.
