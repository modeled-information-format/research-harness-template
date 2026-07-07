# Curating `negative_examples` at scale (steps 1-4)

Executable guidance for the corpus-regen, baseline-calibration, and
partition-and-draft steps of the confusion-driven `negative_examples`
curation workflow (MIF ADR-020) — the part worth codifying for spinning up
parallel drafting agents. Human spot-check, curation, and evidence (steps
5-7) are **not** covered here — they must not be delegated to an agent; see
[the full how-to](../../../../docs/how-to/negative-examples-curation-workflow.md#5-human-spot-check-a-sample-per-batch).

## Step 1-2: regenerate the corpus, baseline calibrate

```bash
mif-rh-cli resolve reports/<topic>/findings/<finding>.json --topic <topic>  # per finding
mif-rh-cli review --strict                                                  # once, last, never mid-fan-out

mif-rh-cli calibrate --target-precision 0.60 \
  --confusions reports/_meta/confusions-060-before.json \
  --out reports/_meta/cal-060-before.json
mif-rh-cli calibrate --target-precision 0.95 \
  --confusions reports/_meta/confusions-095-before.json \
  --out reports/_meta/cal-095-before.json
```

## Step 3: partition confusion pairs into per-topic drafting batches

```bash
jq '.[0]' reports/_meta/confusions-060-before.json   # inspect this corpus's finding_ids shape first

for topic in $(jq -r '.[].finding_ids[0]' reports/_meta/confusions-060-before.json \
    | grep -oE '(corpus-)?[a-z0-9-]+' | sort -u); do
  jq -c --arg t "$topic" '[.[] | select(.finding_ids[0] | test($t))]' \
    reports/_meta/confusions-060-before.json > "batch-${topic}.json"
done
```

One batch file per topic present in the export. Spin up one drafting agent
per batch (a lead agent fans these out in parallel; each drafting agent
only ever reads its own batch's `finding_ids`, never writes to an ontology
pack).

## Step 4: brief for each drafting agent

Give each drafting agent its batch file and this brief, verbatim:

> For each `(gold, top1, count, finding_ids)` entry in your batch: read the
> real finding content behind `finding_ids`. Draft one `negative_examples`
> candidate **on `top1`** (the type that incorrectly won) — never on
> `gold`. Paraphrase; never copy the source finding text verbatim. Add a
> one-line "why confusable" note. Cite the grounding `finding_ids`. Output
> a draft artifact only — do not write to any ontology pack YAML.

Expected output per entry:

```markdown
### <top1>: negative_example candidate (confused with <gold>, count=<N>)
**Proposed negative_example:** "<paraphrased near-miss text>"
**Why confusable:** <one-line semantic-overlap note>
**Grounded in:** <finding_id>, <finding_id>
```

Collect every batch's output into one draft document before handing it to
the human spot-check step — see the how-to for steps 5-7.
