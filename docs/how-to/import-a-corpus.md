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

## Importing a legacy sigint corpus (sigint → MIF)

The import path above is MIF-to-MIF. A legacy **sigint** corpus is shaped
differently — aggregated `reports/<topic>/findings_<dim>.json` wrappers
(`{dimension, findings:[…]}`, or a bare findings array), not individual MIF
units — so it must be converted first. The harness ships a converter:

First enable the conversion path in `harness.config.json` (it is opt-in;
`convert-sigint-corpus.sh` refuses to run otherwise):

```json
{ "features": { "sigintCorpusImport": true } }
```

```bash
# 1. Convert one sigint topic dir into a MIF staging dir (findings/*.json).
#    Pass the SAME <topic-id> you will import under — it is baked into every
#    unit's @id and namespace, so a mismatch registers the topic and the units
#    under different namespaces. (If omitted, it defaults to the dir basename.)
scripts/convert-sigint-corpus.sh <sigint-topic-dir> <staging-dir> <topic-id>

# 2. Import the staged MIF units under the SAME <topic-id>
scripts/import-corpus.sh <staging-dir> <topic-id>
```

`convert-sigint-corpus.sh` maps each sigint finding to a MIF unit: a `urn:mif:`
id, `provenance.sourceType = external_import` (W3C-PROV preserved), the source's
own dimension carried into `extensions.harness.dimension`, the prior adversarial
verdict carried into `extensions.harness.verification`, and `updates_finding`
carried as a typed `updates` relationship whose target is resolved to the
converted in-corpus `@id` (so delta findings link to the real node, not a
placeholder). Citations are real `http(s)` URLs where the source had one
(including bare-domain and embedded-URL recovery).

`gate_m9` in `scripts/verify.sh` proves the convert→import round-trip against
`evals/fixtures/sample-sigint-corpus` (lossless count, provenance preserved,
namespace matches the import topic, MIF-derived graph, and both feature flags
enforced).

### Internal / document sources (feature-flagged)

Many legacy findings cite internal documents (ADRs, named reports) with **no web
URL**. The converter emits those as first-class internal citations
(`citationType: "internal:document"`, the quote in `note`). The citation-integrity
gate accepts them **only when the instance opts in** via `harness.config.json`:

```json
{ "features": { "internalCitations": true, "sigintCorpusImport": true } }
```

Both flags default to `false` — the template ships strict (http(s)-only
citations). `sigintCorpusImport` gates the converter itself; `internalCitations`
gates whether the citation-integrity gate accepts internal sources. Enable both
in an instance importing a legacy corpus with internal sources; leave them off to
keep the strict default.

## Getting the converter into your instance

The converter and the `features` flags are template improvements. A `copier`
instance pulls them with `copier update`; a snapshot/clone instance must adopt
copier first or copy the files by hand. See
[How to instantiate the harness](instantiate-the-harness.md).

## What is not carried

The legacy v1→v2 **migrate skill is intentionally dropped** (design spec §4a): a
one-time migration shim has no role in a greenfield template. Bringing an
existing corpus forward is done by the import path — a clean MIF-to-MIF import,
or the sigint→MIF conversion above — not by a migration of legacy in-place state.
