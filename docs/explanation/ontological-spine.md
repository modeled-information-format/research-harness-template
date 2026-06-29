---
title: "The ontological spine — a cross-topic concordance"
diataxis_type: explanation
---

# The ontological spine — a cross-topic concordance

The per-topic knowledge graph (`build-graph.sh`) answers "what connects within this
topic." The **ontological spine** answers "what does the corpus know" — one unified,
ontology-typed graph spanning every topic: a unified **concordance** of knowledge as it was
researched, falsified, validated, and organized.

## What it is

`scripts/build-concordance.sh` merges every topic's findings into a single `concordance.json`:

- **Concept nodes** — one per finding, **stamped** with its resolved ontology
  `entityType` (from `reports/<topic>/ontology-map.json`), its source `ontology`, and
  its falsification **verdict**.
- **Entity nodes** — referenced MIF entities, **merged across topics by `urn:mif:`
  @id**: the same entity referenced in two topics is one node whose `topics` span both.
  This is what stitches separate topics into a connected concordance.
- **Edges** — typed `relationships[]` plus `mentions` (finding → entity).

It is **deterministic** (sorted, no wall-clock) — "living" means an on-demand rebuild
reflects the current corpus, not an incremental cache.

## The full record, not just the survivors

Unlike the report-synthesizer (which ships only non-falsified findings), the concordance
shows the **entire research record**: every finding is a node carrying its verdict, and
**falsified findings are flagged, not excluded**. The concordance is where you see what was
disproven alongside what held — research as it actually unfolded.

## Fail-closed conformance

`scripts/validate-concordance.sh` enforces that the concordance is genuinely *ontological*, not just
labelled:

- Every node `entityType` must be declared by an ontology **bound to that node's
  topic(s)** — the always-on core (`mif-generic`/`mif-base`) ∪ each topic's bound
  ontologies ∪ those bound ontologies' transitive `extends` ancestors (so an inherited
  supertype like `engineering-base`'s `component` resolves under a topic that binds
  `software-engineering`). An undeclared type **fails**.
- Every relationship edge `type` must be declared by a bound ontology, and the edge's
  endpoints must satisfy that relationship's `from`/`to` **domains** (e.g. k12
  `belongs_to` only goes `title → program`). An undeclared type or a domain violation
  **fails**.
- It fails closed on a broken toolchain or a jq error — never passes vacuously.

`gate_m13` proves all of it against a two-topic fixture: schema-valid build, fail-closed
conformance (undeclared type / undeclared relationship / domain violation each fail),
stamped concept nodes, falsified-flagged, cross-topic @id merge, and determinism.

## How it closes the gap

The ontology gate (`gate_m12`) validates a finding's *own* type. The spine extends that
to the **graph**: the resolved ontology type and verdict are promoted onto concept
nodes, and every node/edge type in the cross-topic graph is held to the ontology — so
the knowledge graph is itself ontology-conformant, fail-closed, across the whole corpus.

## The spine feeds synthesis

The spine is no longer write-only — it feeds the deliverables two ways:

- **Per-topic synthesis is ontology-aware.** `scripts/synthesize-artifact.sh` joins each section
  to its finding's resolved type from `reports/<topic>/ontology-map.json` (`entityType`,
  `ontology`, `basis`), so a report reflects the *resolved* ontological type and an epistemic
  `basis` — a `discovery` type is a classifier inference; a `declared` type is author-asserted —
  not the finding's raw self-typing. The report channel renders it in each section's provenance.
- **The corpus atlas is the spine's full-record projection.** `scripts/synthesize-corpus.sh`
  (driven by the `corpus-synthesizer` agent / `/synthesize-corpus`) turns the concordance into
  `reports/_corpus/corpus-synthesis.md`: cross-topic entity reuse, converging vs. contradicting
  evidence, and — unlike the survivors-only report-synthesizer — **what was disproven**
  (falsified findings are flagged and surfaced, not dropped). `graph --concordance --reuse`,
  `--contradictions`, and `--disproven` query the same projection ad hoc.
