---
name: github-issues
description: "Convert a synthesized deliverable into actionable GitHub issues — atomize its recommendations into sprint-sized, well-structured issues with acceptance criteria and evidence-justified priority. A channel adapter behind the findings→artifact contract: input is the report-synthesizer artifact, output is one issue per actionable item. Optional channel; depends on the `gh` CLI. Use when the user says 'create issues from the report', 'turn recommendations into issues', or 'file action items'."
version: 1.0.0
argument-hint: "<artifact-path> [--repo owner/repo] [--labels a,b] [--dry-run]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# GitHub Issues Channel Adapter

Convert a synthesized deliverable into actionable GitHub issues. Input is the
**rendered artifact** from `report-synthesizer` (a clean, already-cited
document), not the findings corpus. Each issue is composed from the artifact's
own recommendations and conclusions — it must read as standalone work, with no
internal references in the body. This is a generic, domain-neutral
findings→issues adapter; it carries no domain-specific framing.

This is an **optional** channel. It depends on the external `gh` CLI being installed and authenticated. If `gh` is unavailable, degrade gracefully (see below).

## Dependency Check (run first)

```bash
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed — this channel is unavailable. Issues will be written locally; install gh and run 'gh auth login' to file them."; }
gh auth status >/dev/null 2>&1 || echo "gh not authenticated — running in local-write mode."
```

If `gh` is missing or unauthenticated, set local-write mode: write the issue set to `<artifact-dir>/issues.json` instead of filing, and tell the user how to file later. Never error out.

## Phase 0: Resolve Inputs

1. Resolve `<artifact-path>` to the synthesized deliverable. If omitted, glob the topic's output directory and ask which to use if more than one is found. Read no corpus files — the artifact is the sole source.
2. Resolve `--repo`: the flag, else `gh repo view --json nameWithOwner -q .nameWithOwner`. Validate it matches `[\w.-]+/[\w.-]+`; reject shell metacharacters and path traversal.
3. `--labels` is an optional comma-separated list applied to every issue. `--dry-run` previews without filing.

## Phase 1: Extract Actionable Items

From the artifact's recommendations, conclusions, and open questions, identify each discrete actionable item. Classify each:

| Category | Label | What it is |
| --- | --- | --- |
| Feature | `feature` | A new capability the artifact recommends building |
| Enhancement | `enhancement` | An improvement to something that exists |
| Follow-up | `follow-up` | Further investigation or validation the artifact flags as open |
| Action item | `action-item` | A concrete process, config, or documentation change |

## Phase 2: Atomize

Break any item larger than sprint-size (completable by one person in 1–2 weeks, independently demoable) into atomic issues. Make dependencies explicit (blocks / blocked-by) and note a suggested implementation order.

## Phase 3: Structure Each Issue

```markdown
## Summary
{1-2 sentences: what to do}

## Context
{The recommendation or conclusion from the artifact that drives this work,
 paraphrased so the issue stands alone.}

## Acceptance Criteria
- [ ] {specific, measurable criterion}
- [ ] {specific, measurable criterion}

## Dependencies
- Blocks: #{n} (if any)
- Blocked by: #{n} (if any)

## Priority Rationale
{Why this priority, justified by the strength of the supporting evidence and
 the impact of the item — in domain-neutral terms.}
```

**Priority** is justified by evidence strength plus impact, not by any domain assumption:

- **P0** — strong evidence, high impact, blocks other work.
- **P1** — strong evidence or high impact; clear value.
- **P2** — moderate evidence/impact; incremental.
- **P3** — speculative or exploratory; revisit later.

## Phase 4: Preview or File

- `--dry-run` or local-write mode: write the issue set to `<artifact-dir>/issues.json` (`{title, body, labels, priority, category}` per item) and report the path.
- Otherwise file each:

```bash
gh issue create --repo <owner/repo> --title "<title>" --body "<body>" --label "<category-label>" [--label "<extra>"]
```

Apply `--labels` to every issue. Link related issues with `blocks`/`blocked by` references after creation.

## Phase 5: Quality Gate (before filing)

For each planned issue, verify: it has ≥2 measurable acceptance criteria; its priority is justified by the cited evidence strength rather than inflated; its context stands alone without internal references. Revise once if any fail; if still flagged, add a `review-warning` label.

## Phase 6: Report

Write a manifest to `<artifact-dir>/<date>-issues.json` (one entry per issue with number/url when filed) and summarize by category:

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
