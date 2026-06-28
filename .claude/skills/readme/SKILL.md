---
name: readme
description: "Create, update, and validate a topic's navigation README at reports/<topic>/README.md — the per-topic index (title, verdict-aware metadata header, purpose, dimensions, synthesis-grade key findings, reports table, findings-by-dimension table, optional artifacts, tags) modeled on the per-directory READMEs of a research corpus. Use this skill whenever a report topic is created or mutated and its README must be reconciled: after a research session synthesizes, after findings or reports change, or when the user asks to 'update the README', 'reindex the topic readme', 'reconcile READMEs', or 'regenerate the topic index'. Reads harness.config.json topics[], reports/<topic>/findings/*.json, and goal.json — counts are computed, key findings are synthesized."
version: 2.0.0
argument-hint: "[--topic <id>] [--all] [--check]"
allowed-tools: Read, Bash, Edit, Glob, Grep, Write
---

# readme — the per-topic navigation index

Every report topic carries a navigation `README.md` at `reports/<topic>/README.md`,
modeled on a research corpus's per-directory READMEs. Its structure:

```text
# <Title>

**Research ID:** <slug>
**Created:** <date> | **Updated:** <date>
**Findings:** <N> (survived S, weakened W) | **Sources:** <N> unique URLs
**Falsification:** <date> — survived S, weakened W[, quarantined Q] ([report](…))   ← when a falsification report exists
**Status:** <status>

---

![<title>](_assets/<topic>-readme-hero.*)   ← optional, only when the hero asset exists

## Purpose            — 1–2 sentences, what the session decides/answers
## Dimensions         — bulleted; each dimension with its harness.config description
## Key Findings       — 4–10 SYNTHESIS-GRADE bullets (see below)
## Reports            — Type → Title table of the topic's constituents, in reader-consumption order
## Findings by Dimension — table of per-dimension counts
## Artifacts          — (only if channel-pack assets exist) File / Type / Size table
## Tags               — backtick-quoted tag tokens
```

The README is the **served topic index**: the site's content loader derives its Starlight
title from the H1, so it renders as the topic's landing page at `/reports/<topic>/`, with
the constituent report tree reached from its Reports table — the sidebar links only to this
index, not the per-report tree (ADR-0009). It remains a **navigation projection, not a MIF
Level-3 report**: like the `blog`/`book` channels it carries no MIF frontmatter and is exempt
from the output-conformance gate. Its source of truth is the MIF substrate
(`reports/<topic>/findings/*.json`, `goal.json`, `harness.config.json`). The Reports table is
ordered by a single canonical Type map in `scripts/build-topic-readme.sh` (executive summary →
briefing → synthesis → genre reports → falsification report → research progress).

## When this runs

This skill wraps `scripts/build-topic-readme.sh` — the deterministic structural
engine — and is responsible for the one thing the script cannot do: **author
synthesis-grade Key Findings.**

- **At synthesis:** the `report-synthesizer` agent (which holds the surviving
  findings) writes the synthesis-grade Key Findings as part of Phase 4. That is
  the primary path — the README ships synthesis-grade, not skeletal.
- **In the orchestration flow:** `/start` invokes this skill after the
  orchestrator returns, to (re)synthesize prose and validate.
- **On demand / safety net:** run it any time; the `check-readme-reindex`
  PostToolUse hook flags out-of-band edits.

## Pipeline

1. **Resolve the topic set.** `--topic <id>` (one), `--all` (every
   `harness.config.json` topic), or the active session's topic when no flag.

2. **Build the deterministic backbone.** Computes every count, date, the verdict
   breakdown, the source total, dimension rollup, and the report/artifact tables —
   never author these by hand:

   ```bash
   bash scripts/build-topic-readme.sh <topic>
   ```

3. **Author synthesis-grade Key Findings and Purpose (the core of this skill).**
   First **`Read reports/<topic>/README.md`** — the file step 2 just generated;
   the `Edit` tool refuses to write a file it has not read this session. Then read
   the actual findings (`reports/<topic>/findings/*.json` — title, summary,
   `content`, citations, verdict) and **rewrite the `## Key Findings` section** so
   it reads like the corpus exemplar, then tighten `## Purpose` to 1–2 sentences.
   Edit only those two sections; the script preserves them on later rebuilds.

   **Key Findings bar — match this, do NOT regress to a list of finding titles:**
   - 4–10 bullets that **synthesize ACROSS findings** — each bullet states an
     insight, a tension, or a converging consensus, not a single finding restated.
   - Carry the **specifics** that make it credible: named standards/tools/products,
     numbers, dates, versions, thresholds — drawn from the findings' content.
   - Lead with the decision-relevant signal (what the evidence establishes, where
     it is thin, what the call turns on), ordered by the goal's priorities.
   - Respect verdict nuance: `weakened` findings carry caveats; `inconclusive`
     ones are reported as open, never asserted; `falsified` ones are excluded.
   - Every bullet must trace to surviving finding content — invent nothing.

   Example of the bar (one bullet from the corpus):
   > A credible dual-format consensus is converging: RFC 9457 Problem Details as
   > the transport envelope, MCP-style `structuredContent` + `isError` as the
   > machine channel, miette/rustc-style human rendering with primary span and
   > cause chain… — shipped-and-proven, not aspirational.

   Contrast — the skeletal output this skill must REPLACE:
   > - Copier propagates upstream template changes to instantiated projects.

4. **Validate (the gate).** Must pass before reporting done:

   ```bash
   bash scripts/build-topic-readme.sh <topic> --check
   ```

   Non-zero exit means the README is wrong — fix it, do not ship it. Markdown
   lint is enforced separately by the bundled `md_guard` hook on write.

5. **`--all`:** loop steps 2–4 over every topic.

## Non-negotiables

- **Key Findings are synthesized, not listed.** A README whose Key Findings are
  one-finding-per-bullet restatements has failed this skill — re-synthesize.
- The README never carries MIF frontmatter and never claims a verdict (that is
  `publish-report`).
- Counts, dates, verdict breakdown, tables, and tags are deterministic — from the
  script, never invented.
- The `--check` gate must pass before the README is reported reconciled.
- `--topic` / `--all` only — never hardcode a topic id; this is a template.
