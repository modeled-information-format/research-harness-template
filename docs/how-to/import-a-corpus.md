---
title: "How to import an existing corpus"
diataxis_type: how-to
---

# How to import an existing corpus

The harness can import an existing research corpus — and, above all, its
knowledge graph — into a **freshly instantiated harness**, with provenance and
graph edges intact (design spec §10). This is the first real use of the MIF
substrate: because a corpus is already MIF (findings are MIF concept units, the
graph is MIF EntityReferences and typed relationships), the import is lossless.

> This runs against **your own instantiated harness**, never against the
> template. The template ships clean and standalone; a corpus only ever lands in
> an instance's `reports/`. Importing the prior corpus into the template would
> defeat the point of a clean, reusable template.

## What you need

A source corpus directory containing:

- `findings/*.json` — the MIF concept units (each must validate against
  `schemas/findings.schema.json` and carry a `provenance` block).
- optionally `knowledge-graph.json` — the corpus's existing graph, used to
  confirm the edge set survives the import.

## Import

From your instantiated harness:

```bash
scripts/import-corpus.sh <source-corpus-dir> <topic-id>
```

This validates every finding against the MIF-backed schema (refusing to import
anything that fails), copies them under `reports/<topic-id>/findings/`, registers
the topic in your `harness.config.json`, and rebuilds the index and graph over
the imported substrate. The W3C-PROV provenance block travels with each unit
untouched.

## Verify the import

The build gate's import check (`gate_m8` in `scripts/verify.sh`) asserts, against
a sample corpus, that the imported finding count, graph node count, and graph
edge count all match the source, that provenance is preserved on every finding,
and that the rebuilt graph still derives from `urn:mif:` ids — proving the edges
survive. Run `scripts/assert-graph-mif.sh reports/<topic-id>/knowledge-graph.json`
on your own import to confirm the same.

## Internal and document sources (feature-flagged)

Some findings cite internal documents (ADRs, named reports) with **no web URL**,
carried as first-class internal citations (`citationType: "internal:document"`,
the quote in `note`). The citation-integrity gate accepts them **only when the
instance opts in** via `harness.config.json`:

```json
{ "features": { "internalCitations": true } }
```

`internalCitations` defaults to `false` — the template ships strict (http(s)-only
citations). Enable it in an instance whose corpus carries internal sources; leave
it off to keep the strict default.

## What is not carried

The legacy v1→v2 **migrate skill is intentionally dropped** (design spec §4a): a
one-time migration shim has no role in a greenfield template. Bringing an
existing corpus forward is done by the import path — a clean MIF-to-MIF import —
not by a migration of legacy in-place state.
