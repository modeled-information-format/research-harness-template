---
id: explanation-classification-engine
type: semantic
created: '2026-07-05T00:00:00Z'
modified: '2026-07-05T00:00:00Z'
namespace: docs/explanation
tags:
  - documentation
  - explanation
title: "The classification engine"
diataxis_type: explanation
---

# The classification engine

`resolve-ontology.sh` and `ontology-review.sh` keep their names, flags, and
documented contracts, but since
[ADR-0016](../adr/0016-engine-only-classification.md) they delegate to a
compiled binary, `mif-rh-cli`, rather than to a bash-and-`yq`/`jq`/`ajv`
pipeline. This page explains why a compiled engine replaced the bash pair,
what boundary it preserves from the earlier design, how the confidence-tier
classification model works at a concept level, and why its agent-facing MCP
surfaces stay read-only.

## Why a compiled binary replaced two bash scripts

The bash pipeline spawned `yq`, `jq`, and `ajv` as separate subprocesses per
finding. That cost is fixed per invocation and paid once per finding, so it
scales linearly with corpus size and has no ceiling: a full-corpus review of
a real, 4296-finding corpus took over twenty minutes
([ADR-0014](../adr/0014-compiled-ontology-engine-cli-and-mcp.md)). A compiled
engine replaces N subprocess spawns per finding with N in-process
deserializations inside one long-lived process, which is the dominant source
of the measured speedup: the same real corpus completed in under a second
once the engine existed.

Speed alone would not justify the change if it cost the deterministic
contract the bash pipeline earned. It does not, because the engine is
required to reproduce the bash pair's observable behavior exactly (same
flags, same exit codes, same stdout table and summary format) before it is
trusted with anything, and that equivalence is proven continuously, not
assumed once: a parity suite in `modeled-information-format/mif-rs` runs
library-level and binary-level cases against a pinned checkout of this
repository on every change to the engine. Before
[ADR-0016](../adr/0016-engine-only-classification.md), that parity suite was
a bridge between two coexisting implementations; after it, the bash bodies
are retired and the suite is a regression net for the one implementation
that remains. The engine also reloads its catalog, configuration, and
vendored ontology packs fresh from disk on every call, with no caching, so a
live ontology-pack change takes effect on the next invocation exactly as it
did under the bash pipeline.

The engine is hard-required, provisioned in a fixed order (an explicit
`MIF_RH_CLI` override, then PATH, then an attested download installed by
`scripts/fetch-engine.sh`), and its absence or an out-of-date version is a
loud, named failure rather than a silent fallback to a different code path.
That posture trades the bash pipeline's zero-toolchain-install property for
one hard runtime dependency, accepted because the dependency is a single
attested binary rather than a matched set of shell tools, and because a
missing dependency now fails loudly at the point of use instead of quietly
degrading.

## The classification-and-resolution boundary the engine preserves

The harness has always separated two questions that can be proven to
different degrees: which `entity_type` a finding resembles (classification),
and whether a stamped type actually resolves against a topic's bound
ontologies and satisfies its schema (resolution). See
[ontology conformance](ontology-conformance.md) for the full account of that
split. Classification is agent-mediated and best-effort, whether it comes
from a content-pattern guess, an agent's own judgment during topic
onboarding, or now the engine's embedding-based suggestions described below.
Resolution is fully deterministic and is what the fail-closed ontology gate
enforces.

ADR-0016 changed which process performs the classification-and-resolution
work, not where the line between them falls. A guess, from any source, is
never a durable stamp until an analyst or reviewer confirms it and the
finding's `entity` block is written and re-resolved. The engine's confidence
tiers make this explicit rather than implicit, as the next section covers.

## The confidence-tier model, at a concept level

Beyond the original content-pattern discovery guess, the engine can score a
finding's likely type against an ontology's declared `aliases`, `exemplars`,
and `negative_examples` (MIF ontology schema 1.1.0) using embedding
similarity, and sort the result into one of three tiers by comparing that
score against two thresholds: a candidate scoring above the upper threshold,
with an additional margin over the runner-up candidate, is
`auto_classify_eligible`; a candidate between the two thresholds is
`flag_for_review`; a candidate below the lower threshold is
`trigger_expansion`, a signal that no cataloged type fits well, which is
information about the ontology rather than about the finding.

The two thresholds and the margin are not constants baked into the engine.
They are derived, per-instance data (`reports/_meta/confidence-calibration.json`,
written by `mif-rh-cli calibrate` from the instance's own stamped findings),
because a threshold tuned against one corpus's distribution of scores has no
reason to hold for a different corpus with a different mix of domains and
ontologies. Recalibrating as a corpus grows is expected, not a one-time
setup step.

`auto_classify_eligible` names a confidence band, not a write authorization.
[ADR-0015](../adr/0015-confidence-tier-consumption-and-scored-suggestion-routing.md)
routes every tier's output into a scored suggestion queue
(`reports/_meta/suggestions/<topic>.json`) that a reviewer works through
`/ontology-review --enrich`: each entry is confirmed or rejected, never
deleted, so review history persists and a rejected suggestion does not
resurface as pending on the next run. Recurring tier-3 misses cluster across
runs into expansion candidates that `scripts/author-ontology.sh
--from-clusters` mines into draft entity-type scaffolds. At every tier, the
path from a suggestion to a durable `entity_type` stamp is the same typing
edit and resolve pass that a manually classified finding goes through.

## How `negative_examples` shape the tier boundary

`aliases` and `exemplars` both strengthen a type's *positive* signal: the
engine concatenates them into that type's embedding document, so a finding
resembling any of them scores that type higher. `negative_examples` works
the opposite way, and does not touch scoring at all. A curated
`negative_examples` entry is never concatenated into any embedding document;
instead, at suggestion time, the engine separately embeds each of a
candidate type's curated negative examples and compares them to the query.
If the query's similarity to any curated negative example meets or exceeds
its similarity to the type's positive embedding document, that candidate is
barred from `auto_classify_eligible`, regardless of its raw score.

This is a demotion gate, not a score penalty: it never reorders candidates
relative to one another, only caps the confidence tier a demoted candidate
can reach. A type with no curated `negative_examples` is never demoted by
this mechanism. The purpose is narrower than "make the model better",
specifically countering near-miss confusions a corpus's own confusion export
(`mif-rh-cli calibrate --confusions`) has already surfaced: real findings
whose true type lost to a specific, identifiable neighbor type at the
scoring layer. Because the two mechanisms operate on different data
(`calibrate`'s own tier1_floor/tier1_margin/tier2_floor thresholds come from
raw pre-demotion scores), curating `negative_examples` does not move those
calibrated numbers on a re-run; it only changes which candidates clear the
tier they compute. MIF ADR-020 requires `negative_examples` to be
human-curated from a real confusion export, never auto-mined, precisely
because a badly chosen negative example demotes silently and can suppress a
type that should legitimately win.

## Why the MCP surfaces stay read-only

The engine exposes `search`, `suggest_type` (`suggest-type` at the CLI),
`find_similar`, and `corpus_stats` as MCP tools, callable by an agent at any
point in a session rather than only at the fixed points where the
deterministic scripts run. That agent-facing reach is exactly why the MCP
server has no write access to `reports/`: an agent invoking `suggest_type`
mid-session is asking a question, and the invariant this harness commits to
([ADR-0011](../adr/0011-fail-closed-ontology-completeness-gate.md)) is that
a shippable finding ships only with a durable, valid `entity` stamp, proven
by the deterministic gate. If a query tool could also write, that invariant
would depend on every agent's discipline never to let a good-looking
suggestion skip the gate; making the write path structurally unavailable
removes that dependency instead of documenting around it.
[ADR-0015](../adr/0015-confidence-tier-consumption-and-scored-suggestion-routing.md)
extends the same posture to the scored suggestion queue: routing embedding-
derived scores through a purpose-built queue, rather than through the
deterministic review artifact the gate consumes, keeps a model-dependent
signal outside the gate's input surface entirely.

## See also

- [The ontological spine](ontological-spine.md), for how a resolved type
  and verdict compose into the cross-topic concordance.
- [Ontology conformance](ontology-conformance.md), for the full
  classification-versus-resolution account and the ontology registry the
  engine resolves against.
- [How to run the classification engine loop](../how-to/run-the-classification-engine-loop.md),
  for the operator-facing steps: calibrate, queue suggestions, confirm or
  reject, and mine expansion candidates.
- ADR-0014, ADR-0015, and ADR-0016, for the decision record behind the
  engine's scope, the suggestion-routing contract, and the hard cutover.
