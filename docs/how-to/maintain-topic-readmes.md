---
title: "How to maintain topic READMEs"
diataxis_type: how-to
---

# How to maintain topic READMEs

Every report topic carries a navigation `README.md` at `reports/<topic>/README.md`
— a compact index of what the topic holds: title; a metadata header with research
id, created/updated dates, a verdict-aware finding count (`survived`/`weakened`/
`quarantined`), the unique-source total, and status; purpose; dimensions;
**synthesis-grade key findings**; a reports table; a findings-by-dimension table;
an optional artifacts table; and tags. It is modeled on the per-directory READMEs
in a research corpus.

The README is a **navigation projection, not a report of record.** Like the
`blog` and `book` channels it is MIF-exempt — it carries no MIF frontmatter and is
excluded from the output-conformance gate. Its source of truth is the MIF
substrate: `reports/<topic>/findings/*.json`, the session `goal.json`, and the
`harness.config.json` manifest entry. It is always reproducible from them, so the
counts and tables are never hand-authored.

## When it is reconciled

- **Automatically, at synthesis.** The `orchestrator` rebuilds and validates the
  README in Phase 4 of every topic-mutating run (`/start`, `/start --update`,
  `/start --augment`), so a completed session always leaves the README current.
- **On out-of-band edits.** When you write a finding, a report, or the manifest
  by hand, the `check-readme-reindex` PostToolUse hook reminds you to reconcile
  the affected topic's README.

## Reconcile it yourself

The **Key Findings** are synthesis-grade: 4–10 bullets that synthesize *across*
findings (insights, tensions, converging consensus — never one-finding-per-bullet
restatements), carrying the specifics that make them credible. At synthesis time
the `report-synthesizer` agent authors them (it holds the surviving findings); the
deterministic script only seeds a summary-based draft.

Use the `readme` skill — it builds the deterministic backbone, synthesizes the
Key Findings and Purpose from the findings, and runs the validation gate:

```text
readme --topic <id>     # one topic
readme --all            # every topic in harness.config.json
```

Or drive the script directly when you only need the deterministic projection (no
prose refinement):

```bash
bash scripts/build-topic-readme.sh <topic>            # write reports/<topic>/README.md
bash scripts/build-topic-readme.sh <topic> --check    # structural validation gate
```

## What the validation gate checks

`build-topic-readme.sh <topic> --check` fails closed (non-zero exit) unless:

- the README exists and has every required section (Purpose, Dimensions, Key
  Findings, Reports, Findings by Dimension, Tags);
- the stated `**Findings:** N` count matches the finding files on disk;
- the Key Findings are synthesized, not the auto-generated draft; and
- every file linked in any table (Reports and the optional Artifacts table) exists.

Markdown formatting is enforced separately by the bundled `md_guard` hook on
write. A just-created topic with zero findings still produces a valid README.

## What is preserved across rebuilds

Rebuilds refresh only the deterministic content — finding/source counts, the
Updated date, dimensions, the report table, and tags. The **Purpose** and **Key
Findings** prose and the original **Created** date are preserved if the README
already exists, so prose the `readme` skill or a human refined is never clobbered
by the next synthesis (the same contract the reference reindexer follows).

An **Artifacts** table is emitted only when channel-pack outputs exist on disk
under `reports/<topic>/_assets/` or `reports/<topic>/slides/` (audio, slides,
infographics, mind maps) — it is omitted entirely for topics without assets, so a
plain research topic is never cluttered with an empty table.
