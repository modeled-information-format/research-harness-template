---
name: github-issues
description: "Convert a research topic's surviving findings into actionable GitHub issues — atomize each finding's implications into sprint-sized, well-structured issues with acceptance criteria and evidence-justified priority. Grounded in the SOURCES (the findings corpus and their primary-source citations) — NEVER a rendered report. Optional channel; depends on the `gh` CLI. Use when the user says 'create issues from the research', 'turn findings into issues', or 'file action items'."
version: 0.1.1
argument-hint: "<findings-dir> [--repo owner/repo] [--labels a,b] [--dry-run]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# GitHub Issues Channel — source-grounded

**Non-negotiable: this deliverable is produced from the SOURCES alone.** Input is the
topic's surviving findings corpus (`reports/<topic>/findings/*.json`) and the primary
materials its citations point to — **never a rendered report** (a deliverable built
from a report is a copy-of-a-copy). Each issue traces to a finding and the primary
source(s) it rests on; it must read as standalone work, with no internal references
in the body. This is a generic, domain-neutral findings→issues adapter.

This is an **optional** channel. It depends on the external `gh` CLI being installed and authenticated. If `gh` is unavailable, degrade gracefully (see below).

## Dependency Check (run first)

```bash
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed — this channel is unavailable. Issues will be written locally; install gh and run 'gh auth login' to file them."; }
gh auth status >/dev/null 2>&1 || echo "gh not authenticated — running in local-write mode."
```

If `gh` is missing or unauthenticated, set local-write mode: write the issue set to `<findings-dir>/../issues.json` instead of filing, and tell the user how to file later. Never error out.

## Phase 0: Load the sources

1. Resolve `<findings-dir>`. Load **every surviving finding** (verdict ≠ `falsified`):

   ```bash
   jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
   ```

   Each finding carries `title` (the verified claim), `content`, `citations[]` (its primary sources), and `extensions.harness.verification.verdict`. Read no rendered report.
2. Resolve `--repo`: the flag, else `gh repo view --json nameWithOwner -q .nameWithOwner`. Validate it matches `[\w.-]+/[\w.-]+`; reject shell metacharacters and path traversal.
3. `--labels` is an optional comma-separated list applied to every issue. `--dry-run` previews without filing.

## Phase 1: Extract Actionable Items FROM the findings

For each finding, identify the discrete action(s) its claim implies. Classify each:

| Category | Label | What it is |
| --- | --- | --- |
| Feature | `feature` | A new capability a finding recommends building |
| Enhancement | `enhancement` | An improvement to something that exists |
| Follow-up | `follow-up` | Further investigation a `weakened`/`inconclusive` finding flags as open |
| Action item | `action-item` | A concrete process, config, or documentation change |

A finding that establishes a fact but implies no action yields no issue — do not manufacture work. A `weakened`/`inconclusive` finding yields a `follow-up`, not an asserted action.

## Phase 2: Atomize

Break any item larger than sprint-size (completable by one person in 1–2 weeks, independently demoable) into atomic issues. Make dependencies explicit (blocks / blocked-by) and note a suggested implementation order.

## Phase 3: Structure Each Issue

```markdown
## Summary
{1-2 sentences: what to do}

## Context
{The finding's claim that drives this work, paraphrased so the issue stands alone,
 with its primary source(s) cited as links.}

## Acceptance Criteria
- [ ] {specific, measurable criterion}
- [ ] {specific, measurable criterion}

## Dependencies
- Blocks: #{n} (if any)
- Blocked by: #{n} (if any)

## Priority Rationale
{Why this priority, justified by the finding's verification verdict + evidence
 strength and the impact of the item — in domain-neutral terms.}
```

The Context cites the finding's **primary sources** (the citation URLs); it never carries internal-research identity (no finding/concept `@id`s, `urn:mif:`, corpus paths, or `f_<dim>_<n>` handles).

**Priority** is justified by evidence strength plus impact, not by any domain assumption:

- **P0** — strong evidence (`survived`), high impact, blocks other work.
- **P1** — strong evidence or high impact; clear value.
- **P2** — moderate evidence/impact; incremental.
- **P3** — speculative or `weakened`/`inconclusive`; revisit later.

## Phase 4: Preview or File

- `--dry-run` or local-write mode: write the issue set to `<findings-dir>/../issues.json` (`{title, body, labels, priority, category}` per item) and report the path.
- Otherwise file each:

```bash
gh issue create --repo <owner/repo> --title "<title>" --body "<body>" --label "<category-label>" [--label "<extra>"]
```

Apply `--labels` to every issue. Link related issues with `blocks`/`blocked by` references after creation.

## Phase 5: Quality Gate (before filing)

For each planned issue, verify: it has ≥2 measurable acceptance criteria; its priority is justified by the finding's verdict + cited evidence strength rather than inflated; its context stands alone, cites the primary source, and carries no internal identity. Revise once if any fail; if still flagged, add a `review-warning` label.

## Phase 6: Report

Write a manifest to `<findings-dir>/../<date>-issues.json` (one entry per issue with number/url when filed) and summarize by category:

```text
Issues {filed | previewed}: {total}
  Features: {n}  Enhancements: {n}  Follow-ups: {n}  Action items: {n}
{priority} #{num} — {title}
...
```

## Error Handling

- Auth failure: "Verify GitHub auth with `gh auth status`" — fall back to local-write.
- Repo not found / no write access: report and fall back to local-write.
- Rate limited: suggest `--dry-run` to preview without API calls.
