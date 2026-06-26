---
name: md-fix
description: "Remediate non-compliant Markdown — fix the markdownlint classes that `markdownlint-cli2 --fix` cannot auto-resolve (MD025 frontmatter-title, MD060 tables, MD033 placeholders, MD036 bold-as-heading, MD029 list-embedded blocks), repair broken intra-repo links, and triage cSpell/typos, escalating only genuine judgment calls. Use this skill when the user wants to fix Markdown lint errors, clean up markdown, make a doc compliant, fix broken doc links, resolve markdownlint/cSpell/typos diagnostics, or remediate documentation without suppressing warnings. Triggers on 'fix markdown', 'fix lint', 'markdownlint errors', 'fix the docs', 'clean up this markdown', 'fix broken links', 'md-fix', 'remediate markdown'. Never suppresses a diagnostic."
version: 0.3.0
argument-hint: "<path-or-glob> ... [--check] [--dry-run] [--apply-allowlist] [--no-spell]"
allowed-tools: Read, Bash, Edit, Glob, Grep, Agent
---

# md-fix — Markdown remediation

Repairs non-compliant Markdown **without suppressing diagnostics**. It pairs with
the project's `md_guard` hook (`.claude/hooks/markdown/`): the hook *guards*
(denies suppression, auto-runs `markdownlint-cli2 --fix` on edits); this skill
*remediates* — it fixes the residual classes `--fix` cannot, plus links and
spell/typo false positives, and escalates only what genuinely needs judgment.

The deterministic engine is `.claude/hooks/markdown/md_remediate.py` (shares
`md_lint_core.py` with the hook). This skill drives it, then resolves escalations.

## Non-negotiable invariants

- **Never suppress.** Do not add `markdownlint-disable` / `prettier-ignore`
  comments or `.md` entries to `.markdownlintignore` / `.prettierignore`. The
  `md_guard` PreToolUse hook denies these anyway.
- **Never disable a rule to silence a fixable issue.** A markdownlint config
  rule-off is acceptable only as deliberate, justified project policy (the hook
  warns on it). Fix the Markdown instead.
- **Never blind-edit prose for spelling.** Proper-noun/identifier false positives
  go to the allowlist (`cspell.json` / `_typos.toml`); genuine typos are reworded
  *in context* by a human or the escalation agent, never auto-replaced.

## Arguments

Parse `$ARGUMENTS`.

| Arg | Meaning |
| --- | --- |
| `<path-or-glob> ...` | Files/globs to remediate. Default: Markdown changed this session (`git status --porcelain`, `.md`/`.markdown` only). If none, ask for a path. |
| `--check` | Report only; write nothing. Exit 1 if anything would change or escalates. |
| `--dry-run` | Print unified diffs; write nothing. |
| `--apply-allowlist` | Add proper-noun spell hits to `_typos.toml` (write mode only). |
| `--no-spell` | Skip the cSpell/typos pass. |

## Execution flow

### 1. Resolve targets

If explicit paths/globs were given, use them. Otherwise:

```bash
git -C "$CLAUDE_PROJECT_DIR" status --porcelain | awk '{print $2}' | grep -E '\.(md|markdown)$' || true
```

If the result is empty and no path was supplied, ask the user which path/tree to remediate.

### 2. Run the remediation engine

```bash
python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/markdown/md_remediate.py" [FLAGS] <targets...>
```

Pass `--check` or `--dry-run` through when supplied. The tool prints a JSON report:

```json
{ "mode": "...", "results": [
  { "file": "...", "changed": true, "fixed": ["MD025","MD060"],
    "links_repaired": ["old -> new"], "allowlist_candidates": ["..."],
    "escalate": [ { "class": "typo|link|spell", "detail": "..." } ],
    "residual": "<markdownlint lines that survived>" } ] }
```

In write mode the deterministic fixes are already applied on disk (the engine also
runs `markdownlint-cli2 --fix` internally for the auto-fixable classes).

### 3. Escalate judgment cases

Collect every `escalate[]` item across files. If non-empty, spawn ONE agent to
resolve them from context (do not resolve them by guessing yourself):

```text
Agent(subagent_type="general-purpose"): "Resolve these Markdown remediation
escalations WITHOUT suppressing anything. For each:
 - class 'typo': read the file at the cited location, decide if it is a real
   misspelling; if so correct it in context, if it is a proper noun add it to
   <repo>/_typos.toml [default.extend-words] and <repo>/cspell.json words.
 - class 'link': find the intended target file in the repo and fix the relative
   link; if no target exists, report it (do not invent one).
 - residual markdownlint lines: fix the underlying Markdown; never add a disable
   directive or ignore-file entry.
After fixing, re-run `python3 .claude/hooks/markdown/md_remediate.py --check <files>`
and confirm zero changes and zero escalations. Return what you changed."
```

### 4. Verify clean

Re-run in check mode and confirm nothing remains:

```bash
python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/markdown/md_remediate.py" --check <targets...>
```

Exit 0 with empty `escalate[]` and `changed:false` everywhere = compliant. Also
confirm the linter directly on a representative file:

```bash
npx --yes markdownlint-cli2 <targets...>   # only MD013 (line-length, intentionally off) may remain
```

### 5. Report

Summarize per file: classes fixed, links repaired, allowlist additions, and any
escalations and how they were resolved. State plainly if anything could not be
fixed and why — never report "clean" while residual lint or unresolved
escalations remain.

## Notes

- Idempotent: re-running on a compliant file makes no changes.
- `MD013` (line-length) is intentionally off in the project ruleset
  (`.claude/hooks/markdown/default.markdownlint.jsonc`) — long tables, commands,
  and URLs cannot wrap; it is not treated as debt.
- Tests: `bash .claude/hooks/markdown/test_md_remediate.sh` (engine) and
  `bash .claude/hooks/markdown/test_md_guard.sh` (hook).
