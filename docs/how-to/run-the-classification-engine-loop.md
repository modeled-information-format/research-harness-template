---
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

- Install the engine (v0.3.1 or later). The canonical path is the
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
  `calibrate` and `expansion-candidates` and will not work.
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

## Verify

```bash
test -f reports/_meta/confidence-calibration.json && echo calibrated
ls reports/_meta/suggestions/ 2>/dev/null
```

A calibrated artifact exists, suggestion queues appear per reviewed
topic, and `mif-rh-cli corpus-stats` reports stamped coverage moving
as you confirm suggestions.
