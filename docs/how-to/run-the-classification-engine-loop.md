---
id: how-to-run-the-classification-engine-loop
type: semantic
created: '2026-07-04T23:13:57-04:00'
modified: '2026-07-05T09:29:04-04:00'
namespace: docs/how-to
tags:
  - documentation
  - how-to
title: "How to run the classification engine loop"
diataxis_type: how-to
---

# How to run the classification engine loop

This guide shows an operator how to run the `mif-rh` engine's
confidence-tiered classification cycle against a harness instance:
calibrate thresholds from the corpus, queue scored type suggestions,
confirm or reject them, and mine recurring misses into candidate new
types. The decision record behind these surfaces is
[ADR-0015](../adr/0015-confidence-tier-consumption-and-scored-suggestion-routing.md);
the tier policy itself is MIF ADR-020.

## Before you begin

- Install the engine (v0.4.0 or later). The canonical path is the
  repo's own fetch script, which downloads the pinned release binary
  and verifies its build provenance fail-closed before installing it
  to `bin/mif-rh-cli` (ADR-0016):

  ```bash
  scripts/fetch-engine.sh
  ```

  A PATH-installed `mif-rh-cli` or an explicit `MIF_RH_CLI` override
  (for source builds) also works. Since ADR-0016 the engine is not
  optional: `resolve-ontology.sh` and `ontology-review.sh` delegate to
  it. Earlier releases (v0.2.0 and before) predate `suggest-type`,
  `calibrate` and `expansion-candidates` and will not work. Releases
  before v0.4.0 predate `calibrate --confusions` and the
  `negative_examples` scoring gate (step 1.5 below) and will not
  support curating negative examples, though calibration and
  suggestion still work.
- Run every command below from the harness instance root (the
  directory holding `reports/`, `harness.config.json` and
  `.claude/enabled-packs.json`).
- Vendor your enabled ontology packs first
  ([vendor ontologies on demand](vendor-ontologies-on-demand.md)); the
  engine resolves candidate types from the same catalog the scripts
  use.
- The first embedding run downloads the sentence-transformers model
  (about 90 MB, cached under `~/.cache/mif/models`); later runs are
  offline.

## 1. Calibrate after corpus growth

```bash
mif-rh-cli calibrate
```

Calibration derives the two-threshold tier policy from your own
stamped findings and writes
`reports/_meta/confidence-calibration.json`. The artifact is derived
per-instance data: the template does not commit it (an instance may
choose to commit its own, per ADR-0015), and re-run this step whenever
the corpus grows meaningfully (a new topic, a large review pass). If no
threshold meets the precision target the command fails loudly and
tells you to enrich entity types; do not lower
`--target-precision` to force an artifact.

## 1.5. Curate `negative_examples` from the confusion export

```bash
mif-rh-cli calibrate --confusions reports/_meta/confusions.json
```

This writes a ranked list of `(gold, top1, count, finding_ids)` confusion
pairs: stamped findings whose true type is `gold` but scored highest
against `top1` instead. The confusion export is written before the
threshold sweep, so it is produced even when calibration itself fails to
find a threshold meeting `--target-precision` and writes no calibration
artifact. For a pair worth curating, add a short near-miss phrase to
**`top1`'s** `negative_examples` list in its ontology pack (never
`gold`'s), grounded in the pair's `finding_ids`. Curation is human-only;
MIF ADR-020 forbids auto-mining `negative_examples` from this export.

A curated `negative_examples` entry demotes its type out of tier 1
whenever a candidate's similarity to that negative example meets or exceeds
its similarity to the positive embedding document. This is a non-reordering
gate: it changes a candidate's confidence tier, not its rank, so curating
`negative_examples` and re-running step 1's plain `calibrate` will not move
`tier1_floor`, `tier1_margin`, `tier2_floor`, or the confusion-pair counts
themselves; that is expected, not a sign curation had no effect. Re-run
`calibrate --confusions` after enrichment (new stamped findings, corpus
growth) the same as step 1, and confirm curated negatives are demoting the
candidates they target with `suggest-type` (step 2), checking the
`negative_demoted` field on the affected candidate.

## 2. Queue scored suggestions during review

```bash
mif-rh-cli review <topic> --suggest
```

Alongside the normal review pass, this writes ranked, tier-annotated
type suggestions for unstamped findings to
`reports/_meta/suggestions/<topic>.json`. Suggestions are hypotheses:
nothing auto-writes an `entity_type`, at any tier (the ADR-0011
fail-closed gate is untouched). One-off queries work too:

```bash
mif-rh-cli suggest-type --finding <path> --record
```

`--record` stores tier-3 misses in the search index for step 4.

## 3. Confirm or reject in the enrich step

Run `/ontology-review --enrich` on the topic. The enrich step reads
the suggestion queue, and you confirm or reject each candidate;
confirmed types go through the same typing edit and re-stamp as any
manual typing. Set the status; never delete entries, because a
deleted finding id resurfaces as pending on the next `--suggest`
pass.

## 4. Mine recurring misses into candidate types

```bash
mif-rh-cli expansion-candidates --out clusters.json
scripts/author-ontology.sh <new-id> --from-clusters clusters.json
```

When enough distinct findings across distinct runs cluster by mutual
similarity, they surface here as draft candidate types; the scaffold
gives each cluster a `todo-cluster-N` entry to name, define and
ground before contributing the ontology upstream.

## 5. Expose the corpus to agents over MCP

The same release ships `mif-rh-mcp`, a stdio MCP server the fetch
script installs beside the CLI. The repo's `.mcp.json` wires it up for
Claude Code sessions in the instance root; it exposes `search`,
`find_similar`, `suggest_type` and `corpus_stats`, all read-only
(suggestions over MCP are hypotheses; every write still goes through
the enrich step, per ADR-0011 and ADR-0015). The two search tools
need the index built first:

```bash
bin/mif-rh-cli review --build-index
```

Rebuild it after large review passes; until it exists the search
tools fail loudly with an index-not-built error rather than returning
empty results.

## Verify

```bash
test -f reports/_meta/confidence-calibration.json && echo calibrated
ls reports/_meta/suggestions/ 2>/dev/null
```

A calibrated artifact exists, suggestion queues appear per reviewed
topic, and `mif-rh-cli corpus-stats` reports stamped coverage moving
as you confirm suggestions.
