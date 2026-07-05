---
id: tutorials-getting-started
type: semantic
created: '2026-06-19T15:19:39-04:00'
modified: '2026-07-05T10:10:09-04:00'
namespace: docs/tutorials
tags:
  - documentation
  - tutorial
title: "Getting started"
diataxis_type: tutorial
---

# Getting started

This tutorial walks you from a fresh clone to a validated harness. You will edit
the manifest, run the build gate, and confirm the bundled enforcement hooks are
wired.

## Prerequisites

- `jq` (structured-data processor)
- `ajv` (`ajv-cli`) and `ajv-formats` (`npm install -g ajv-cli ajv-formats`)
- `markdownlint-cli2` (`npm install -g markdownlint-cli2`)
- `python3` (the markdown enforcement hooks)
- `mif-rh-cli` v0.3.1 or newer, the classification engine the build gate's
  ontology checks require (install with `scripts/fetch-engine.sh`, or provide
  it on `PATH` or via `MIF_RH_CLI`; see
  [ADR-0016](../adr/0016-engine-only-classification.md))

## 1. Declare your harness

Open `harness.config.json`. It is the one file you edit to stand up your own
multi-topic harness. Set your topics, the research dimensions you want the
engine to fan out across, your output targets, and which packs are enabled.

The manifest is validated against `harness.config.schema.json` — your editor
will flag mistakes inline via the `$schema` reference.

## 2. Run the build gate

```bash
bash scripts/verify.sh
```

This validates every contract against its sample, runs the citation-integrity
gate, and runs each milestone's structural checks. It must exit `0`.

## 3. Confirm the harness is clean

```bash
markdownlint-cli2 "**/*.md"
```

Zero errors is the bar. If the markdown enforcement hooks are wired (they are,
in `.claude/settings.json`), Claude Code auto-fixes most markdown on edit and
warns — never suppresses — on the rest.

## Next

- [Run a research session](../how-to/run-a-research-session.md)
- [Understand the architecture](../explanation/architecture.md)
