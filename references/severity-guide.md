# Severity Guide — Security Sentinel

Use these levels consistently. When in doubt, go one level higher — it's easier to
downgrade a finding than to explain why you called a data exposure "Low".

## Critical
Immediate exploitability. A competent attacker could exploit this today without
special access. The PR should not merge until this is fixed.

Examples:
- SQL injection with user-controlled input
- Hardcoded credentials or API keys in source
- Authentication bypass (can reach protected resource without valid token)
- Arbitrary code execution (eval of user input, deserialization of untrusted data)
- Broken access control (user A can read/write user B's data)

## High
Not immediately exploitable but creates serious risk under realistic conditions.
Should be fixed before the feature ships to production.

Examples:
- Missing input validation on a security boundary (even if not currently injectable)
- Outdated dependency with a known CVE (CVSS >= 7.0)
- Sensitive data logged (PII, tokens, passwords in log statements)
- CSRF on state-changing endpoints
- Insecure default configuration that will reach production

## Medium
Real security concern but requires unusual conditions or chained exploits.
Fix in the next sprint, not necessarily before this PR merges.

Examples:
- Missing rate limiting on sensitive endpoints
- Weak cryptography in non-critical path
- Overly permissive CORS
- Missing security headers
- Outdated dependency with CVE (CVSS 4.0–6.9)

## Low
Best practice gap that doesn't create immediate exploitability but erodes
security posture over time. Track it, fix it eventually.

Examples:
- Verbose error messages that expose stack traces
- Unnecessary permissions or scopes requested
- Missing audit logging on sensitive operations
- Cookie without Secure or HttpOnly flag in non-sensitive context

---

## How to write a finding

Bad: "This could have SQL injection issues."

Good:
**[CRITICAL]** `src/users/repository.py:47` — The `search_users` function builds
a raw SQL query using string interpolation: `f"WHERE name LIKE '%{query}%'"`. An
attacker passing `%'; DROP TABLE users; --` as the query parameter would execute
arbitrary SQL. The `query` param comes directly from the request body with no
sanitization.
> Use parameterized queries: `cursor.execute("WHERE name LIKE %s", (f"%{query}%",))`