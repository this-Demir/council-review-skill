<div align="center">

<h1>council-review</h1>

<b>Five senior reviewers analyze your code at once — and talk to each other about it.</b>

<img src="assets/council.svg" width="148" height="148" alt="Council of five" />

[![License: MIT](https://img.shields.io/badge/License-MIT-58a6ff.svg?style=flat-square)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-d97757.svg?style=flat-square)](https://docs.claude.com/en/docs/claude-code)
[![Shell: bash](https://img.shields.io/badge/Shell-bash%203.2%2B-89e051.svg?style=flat-square)](#dependencies)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-3fb950.svg?style=flat-square)](CONTRIBUTING.md)


<br/>

**[Quickstart](#quickstart) · [Usage](#usage) · [The Council](#the-council) · [How it works](#how-it-works) · [Dependencies](#dependencies) · [Contributing](CONTRIBUTING.md)**

</div>

---

## What is this?

Most AI code review gives you one voice doing a checklist pass, or a wall of linter-style bullets. **`council-review` is different.** It convenes **five specialists with distinct mandates** — Security, Readability, QA, Performance, Architecture — who review *simultaneously* and then **cross-reference each other's findings**. The output reads like four senior colleagues had a real conversation in your PR thread, not five parallel reports.

And the security claims are **grounded in real tools** — `gitleaks`, `npm audit`, `pip-audit`, your actual test suite — not the model's memory. So you don't get confidently-wrong CVE numbers or invented line references.

> **The bar:** someone finds this repo, reads this far, installs it in five minutes, types `/council-review PR #95`, and gets a review that feels like four senior devs actually looked at their code.

---

## Quickstart

```bash
# 1. Install into your Claude Code skills directory
git clone https://github.com/this-Demir/council-review-skill.git ~/.claude/skills/council-review

# 2. Make the helper scripts executable
chmod +x ~/.claude/skills/council-review/scripts/*.sh

# 3. Start a new Claude Code session and summon the council
/council-review PR #95
```

That's it. Everything beyond bash and git is optional — the skill gets sharper as you add tools, and degrades with a clear note when one is missing (never a silent failure). See [Dependencies](#dependencies).

---

## The Council

<table>
<tr>
<td width="33%" valign="top">

### Security Sentinel
Injection, secrets, auth bypass, dependency CVEs, OWASP Top 10. Cites secrets and CVEs **only** from real scans — never from memory.

</td>
<td width="33%" valign="top">

### Readability Advocate
Naming, function size, dead code, magic numbers, cognitive load. Writes for the next dev reading this at 2am.

</td>
<td width="33%" valign="top">

### QA Engineer
Boundary values, edge cases, coverage gaps. Runs your test suite and reasons about what's missing — with concrete inputs.

</td>
</tr>
<tr>
<td width="33%" valign="top">

### Performance Analyst
N+1 queries, O(n squared), memory leaks, missing indexes — every finding with a scale-based impact estimate.

</td>
<td width="33%" valign="top">

### Architect
Coupling, wrong abstractions, separation of concerns, premature vs. missing abstraction. Zooms out.

</td>
<td width="33%" valign="top">

### The Verdict
A single reconciled summary: blockers, should-fix, nice-to-have, and **the one thing** that matters most.

</td>
</tr>
</table>

---

## Example output

> `/council-review PR #142` — a PR adding a user-search endpoint to a Node/Express API.

```markdown
## Security Sentinel

**[CRITICAL]** src/users/search.js:34 — `searchUsers` builds the query by string
interpolation: `SELECT * FROM users WHERE name LIKE '%${q}%'`. `q` comes straight from
`req.query` with no escaping. `?q=%' OR '1'='1` dumps every user; `'; DROP TABLE…` is
on the table too.
> Use a parameterized query: db.query('… WHERE name LIKE ?', ['%'+q+'%']).

**[HIGH]** dependency `lodash@4.17.19` — CVE-2021-23337 (High), command injection via
`_.template`. Fixed in 4.17.21. (from `npm audit`)
> npm install lodash@^4.17.21

## Readability Advocate

**Finding** src/users/search.js:34 — `searchUsers` does three things: parse the request,
build SQL, and format the response. The name promises one.
> The Security Sentinel's injection finding hides exactly here — when one function owns
> the whole pipeline, the missing escaping has nowhere obvious to live.

## QA Engineer

run_tests.sh -> STATUS: PASSED (jest, 28 passed). But coverage has a hole:

**Missing coverage** No test passes a `q` containing `%`, `'`, or an empty string.
> expect(await searchUsers("")).toEqual([]) — and a test asserting `'` is escaped. The
> exact input the Security Sentinel flagged as injectable has no test at all.

## Performance Analyst

**Finding** src/users/search.js:34 — `LIKE '%…%'` with a leading wildcard can't use an
index on `users.name`: full table scan on every search. Fine at 1k users, a problem at 1M.
> Consider a trigram index (pg_trgm) if the table grows.

## Architect

**Finding** Raw SQL lives in the route handler. Every reviewer above pointed at the same
line for a different reason — that's the tell. The route knows HTTP *and* the schema.
> Move persistence behind a UserRepository: it gives the escaping (Security), the single
> responsibility (Readability), and the index decision (Performance) one home.

## Council Verdict

**Blocker before PR:** SQL injection on line 34. Bump `lodash` to 4.17.21.
**Should fix soon:** Tests for the injection inputs; extract a repository layer.
**Nice to have:** Trigram index when the users table grows.
**The one thing:** Line 34 is one bug wearing five hats — fix the raw-SQL-in-the-handler
and four of these findings disappear at once.
```

Notice what a linter can't do: every reviewer converges on line 34 *from a different angle*, the CVE is **real** (pulled from `npm audit`, not invented), and the verdict names the single root cause.

---

## Usage

Three invocation patterns cover almost everything:

```bash
/council-review PR #142              # a pull request — reads the description for intent
/council-review I finished issue #22 # an issue — diffs your branch against its base
/council-review src/auth/            # a path, a file, or "review my codebase"
```

**Narrow the council** when you only want certain lenses:

```bash
/council-review PR #142 — just the security reviewer
/council-review src/ — only QA and readability
```

Or **paste a function** straight into the chat with `/council-review` for a focused deep-dive.

---

## Installation

`council-review` is a Claude Code skill — a folder Claude reads when you invoke it.

| Method | Command |
|---|---|
| **Global** (all your projects) | `git clone … ~/.claude/skills/council-review` |
| **Project-local** (commit with your repo) | `git clone … .claude/skills/council-review` |
| **From a release** | download the `.skill` file from Releases and install it (a `.skill` is just a zip of this folder) |

After any method, make the scripts executable and start a new session:

```bash
chmod +x <skill-dir>/scripts/*.sh
```

---

## Dependencies

Works with **nothing but bash and git** — and gets sharper as you add tools. Everything below except bash is optional; a missing tool triggers a clearly-labeled fallback, never a silent failure.

| Tool | Powers | Without it |
|---|---|---|
| **bash 3.2+, git** | everything | required (Windows: Git Bash or WSL) |
| [`gh`](https://cli.github.com) | PR/issue context, posting the verdict | git-only mode |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | Security Sentinel — secret scan | basic grep scan (flagged low-confidence) |
| `jq` | clean parsing of `npm audit` / scanner JSON | raw tool output |
| `npm` · `pip-audit` · `cargo-audit` · `bundler-audit` · `govulncheck` · `composer` | Security Sentinel — dependency CVEs | reports "dependencies not audited" instead of guessing |
| jest · vitest · pytest · `go test` · cargo · rspec · phpunit | QA Engineer | reviews tests statically, says they weren't run |

<details>
<summary><b>Recommended one-line installs</b></summary>

```bash
# macOS (Homebrew)
brew install gh gitleaks jq

# Debian / Ubuntu
sudo apt install gh jq        # gitleaks: see its install page

# Python projects
pip install pip-audit
```
</details>

---

## How it works

```
  +- gather_context.sh --+   PR diff / issue+branch / path / codebase + stack detection
  |  scan_secrets.sh     |   secrets   (gitleaks -> trufflehog -> grep fallback)
  |  check_deps.sh       |   CVEs      (npm/pip/cargo/... audit — the only CVE source)
  +- run_tests.sh -------+   tests     (auto-detected runner, PASSED/FAILED/NOT_RUN)
            |
            v
   Security · Readability · QA · Performance · Architect
                  five lenses, one pass, aware of each other
            |
            v
   Council Verdict   blockers · should-fix · nice-to-have · the one thing
            |
            v
   save_review.sh · post_to_github.sh   (optional: persist / post to the PR)
```

1. **Context** — the right material is gathered for your invocation, and the language/framework is auto-detected.
2. **Grounding** — scanners and the test suite run *before* the council thinks. Each script prints a status line so Claude can tell a grounded finding from a gap. The skill is **forbidden** from inventing CVEs, line numbers, or test results it doesn't have.
3. **Deliberation** — the five reviewers each pass over the code in their own voice, cross-referencing where it genuinely adds an angle.
4. **Verdict** — one reconciled summary.
5. **Save & share** *(optional)* — reviews are written to `.council-reviews/` (git-ignored, since they can contain sensitive code); the verdict can be posted to the PR.

The reviewers run as personas in a **single pass** — cheap, fast, and portable — which is exactly what lets later reviewers see earlier ones and cross-reference. It's one model's analysis through five disciplined lenses, grounded in real tools where it counts.

---

## Contributing

Issues and PRs are welcome — new reviewer angles, better fallbacks, more language support. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the dev setup, the script conventions, and how to add or tune a reviewer persona.

## License

[MIT](LICENSE) © this-Demir
