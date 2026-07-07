---
id: how-to-negative-examples-curation-workflow
type: semantic
created: '2026-07-07T18:08:52-04:00'
modified: '2026-07-07T18:08:52-04:00'
namespace: docs/how-to
tags:
  - documentation
  - how-to
title: "Curate negative_examples at scale across a domain pack"
description: "Run the repeatable, multi-agent confusion-driven curation workflow: regenerate a corpus, baseline calibration, partition confusion pairs for parallel drafting, and evidence the before/after effect."
diataxis_type: how-to
---

# Curate negative_examples at scale across a domain pack

This guide scales `negative_examples` curation (MIF ADR-020) across many
confusion pairs at once — the workflow to reach for when a domain ontology
pack (or a fresh corpus of several packs) needs its classification boundary
sharpened, not just a single pair fixed by hand. For the single-pair,
single-operator mechanics this workflow reuses — what a `negative_examples`
entry is, why curation is human-only, how a curated entry demotes a
candidate at runtime — see [How to run the classification engine
loop](run-the-classification-engine-loop.md#15-curate-negative_examples-from-the-confusion-export)
and the [`calibrate` reference](../reference/engine-cli.md#calibrate). This
guide does not repeat those mechanics; it covers doing them at scale without
losing the human-curation guarantee ADR-020 requires.

Concrete precedent: this workflow ran end to end for `mif-rs` epic #34 /
`ontologies`#39 — a 666-finding, six-topic corpus, 234 confusion pairs
drafted across 6 parallel agents partitioned by topic, curated into 8
ontology packs (`ontologies` v0.4.0). See MIF ADR-020's consequences log for
the shipped numbers.

## Before you begin

- Engine v0.4.0 or later (`calibrate --confusions` and the
  `negative_examples` scoring gate were added then). Install via
  `scripts/fetch-engine.sh`.
- Run every command below from the harness instance root.
- Vendor the ontology packs the corpus targets first ([vendor ontologies on
  demand](vendor-ontologies-on-demand.md)).

## 1. Regenerate or reuse a stamped reference corpus

Resolve every finding in scope against its topic's bound ontologies:

```bash
mif-rh-cli resolve reports/<topic>/findings/<finding>.json --topic <topic>
```

Only after every finding in the target corpus has been authored and
resolved, rebuild the aggregate `ontology-map.json` coverage:

```bash
mif-rh-cli review --strict
```

Run `review` once, at the end — never mid-fan-out. A `review` pass rebuilds
coverage from whatever is on disk at that moment; running it before every
finding is resolved just wastes the pass on an incomplete corpus and forces
a second run.

## 2. Baseline `calibrate` at both standard targets

```bash
mif-rh-cli calibrate --target-precision 0.60 \
  --confusions reports/_meta/confusions-060-before.json \
  --out reports/_meta/cal-060-before.json
mif-rh-cli calibrate --target-precision 0.95 \
  --confusions reports/_meta/confusions-095-before.json \
  --out reports/_meta/cal-095-before.json
```

This is free grounding data, and it doubles as your "before" evidence for
step 7 — run it before any curation exists in the packs this corpus targets.
Confirm the clean starting state:

```bash
grep -rc negative_examples packs/ontologies/*/*.ontology.yaml | grep -v ':0$'
```

An empty result confirms no vendored ontology pack carries `negative_examples`
yet. Narrow the glob to the specific packs this corpus targets if only some
of the vendored packs are in scope.

## 3. Partition the ranked confusion pairs across parallel drafting agents

Each `--confusions` output is a flat list of `(gold, top1, count,
finding_ids)` entries. Inspect one to see how this corpus keys its findings:

```bash
jq '.[0]' reports/_meta/confusions-060-before.json
```

Group the pairs by which corpus topic the pairs' `gold` types live in, so
each drafting agent works one coherent topic's real finding content instead
of a random cross-section of unrelated ones. Extract the topic as an actual
path segment, not a loose substring match — a blind `grep -oE` over hyphenated
tokens picks up spurious matches from every path component (`reports`,
`findings`, the finding's own filename), not just the topic. For the standard
`reports/<topic>/findings/...` shape:

```bash
for topic in $(jq -r '.[].finding_ids[0]
    | select(test("reports/[^/]+/findings/"))
    | capture("reports/(?<topic>[^/]+)/findings/").topic' \
    reports/_meta/confusions-060-before.json | sort -u); do
  jq -c --arg t "$topic" \
    '[.[] | select(.finding_ids[0] | test("reports/" + $t + "/findings/"))]' \
    reports/_meta/confusions-060-before.json > "batch-${topic}.json"
done
```

If this corpus keys `finding_ids` a different way (e.g. a topic-qualified
URN instead of a `reports/` path), adjust the `capture` and `select` patterns
to that shape — the point is an exact topic-segment match, not a substring
scan, so the batch files stay one-per-topic. One batch file per topic, sized
so each drafting agent gets a manageable, topically coherent slice. The
concrete run above split 234 pairs across 6 topics, one drafting agent per
topic.

## 4. Draft negative_examples candidates on the confused (top1) type

Brief each drafting agent (or, for a single batch, do this yourself) with:

- Read the real finding content behind each pair's `finding_ids` — not just
  the `(gold, top1)` labels.
- Draft the candidate on **`top1`** — the type that incorrectly won — never
  on `gold`.
- Paraphrase; never copy the source finding text verbatim.
- Add a one-line "why confusable" note explaining the semantic overlap.
- Cite the grounding `finding_ids` so a human curator can verify against
  source.
- Produce a draft artifact only — never write directly to an ontology pack.
  MIF ADR-020 requires `negative_examples` be human-curated, never
  auto-mined; this step's output is the curator's input, not the curation.

Draft format, one entry per pair:

```markdown
### <top1>: negative_example candidate (confused with <gold>, count=<N>)
**Proposed negative_example:** "<paraphrased near-miss text — reads as
genuine content about `gold`, but plausibly confusable with `top1`>"
**Why confusable:** <one-line semantic-overlap note>
**Grounded in:** <finding_id>, <finding_id>
```

## 5. Human spot-check a sample per batch

Before any batch's drafts move forward, sample entries from it and check:

- **Semantic correctness** — the entry genuinely reads as `gold` content,
  not `top1` content mislabeled.
- **Landed on `top1`, not `gold`** — a drafting agent occasionally inverts
  this; catch it here, not after curation.
- **Genuinely grounded** — spot-check that the cited `finding_ids` actually
  support the phrase.
- **No verbatim copying** from the source finding.

Send a batch with template placeholders, ungrounded claims, or inversions
back to the drafting pass rather than hand-fixing entries in bulk — a
structural defect in one entry is often systemic across its batch.

## 6. Human curates and approves final strings into the ontology pack YAML

Only after spot-check, add each approved string to `top1`'s
`negative_examples` list in its ontology pack YAML (see the
[ontology-manager skill](../../.claude/skills/ontology-manager/SKILL.md)
for the `yq -i` mutation pattern), then validate the file:

```bash
bash .claude/skills/ontology-manager/scripts/validate_ontology.sh \
  packs/ontologies/<pack>/<pack>.ontology.yaml
```

ADR-020 requires this explicit human approval step for every string that
lands in the YAML — step 4's draft artifact is never applied automatically.

## 7. Re-run calibrate and report before/after evidence

```bash
mif-rh-cli calibrate --target-precision 0.60 \
  --confusions reports/_meta/confusions-060-after.json \
  --out reports/_meta/cal-060-after.json
mif-rh-cli calibrate --target-precision 0.95 \
  --confusions reports/_meta/confusions-095-after.json \
  --out reports/_meta/cal-095-after.json
```

`negative-demotion-v1` is a non-reordering gate (see the [`calibrate`
reference](../reference/engine-cli.md#calibrate)), so expect
`tier1_floor`/`tier1_margin`/`tier2_floor` and the confusion-pair counts to
be unchanged from step 2's baseline — that is the expected result, not a
sign curation had no effect. Measure the actual effect via the demotion
rate instead, re-querying each curated pair's grounding findings:

```bash
mif-rh-cli suggest-type --finding <finding> \
  --calibration reports/_meta/cal-060-after.json \
  | jq '.[] | select(.negative_demoted == true)'
```

Report the before/after evidence as: a results table (state x target x
`tier1_floor`/`tier1_margin`/`tier2_floor`/confusion-pair count), an
explicit note that those four numbers are architecturally insensitive to
`negative_examples` and why, and the demotion-rate measurement (pairs
checked, errors, and the fraction whose `top1` now demotes) as the metric
that actually reflects the curation's effect.

## Verify

```bash
test -f reports/_meta/cal-060-after.json && test -f reports/_meta/cal-095-after.json && echo calibrated
grep -rc negative_examples packs/ontologies/*/*.ontology.yaml | awk -F: '$2>0'
```

Calibration artifacts exist for both targets, and at least one ontology
pack in scope now carries curated `negative_examples` entries.
