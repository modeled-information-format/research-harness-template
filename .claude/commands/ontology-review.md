---
name: ontology-review
description: Review, validate, and enrich the ontology mapping of existing topics and their findings — audit coverage, surface invalid/unresolved classifications, bind ontologies to unbound topics, and retro-classify untyped findings.
argument-hint: "[--topic <id>] [--enrich] [--strict]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# ontology-review — review · validate · enrich ontology coverage

Map ontologies onto **existing** topics and findings — the counterpart to the
onboarding step in `/start` (which only covers new topics). Three uses in one tool:
**review** (audit coverage), **validate** (surface classifications that do not
resolve), and **enrich** (bind an ontology to an unbound topic and retro-classify its
untyped findings). The deterministic engine is `scripts/ontology-review.sh`; this
command adds the agent layer (binding selection + retro-classification).

Parse `$ARGUMENTS`: `--topic <id>` scopes to one topic (default: all topics);
`--enrich` turns on the binding/retro-classification pass (default: review only);
`--strict` makes the review exit non-zero if any finding is invalid/unresolved.

## Phase 1: Review + validate (deterministic, always)

Refresh every topic's `reports/<topic>/ontology-map.json` from disk and print a
coverage table (typed / untyped / invalid per topic):

```bash
scripts/ontology-review.sh ${TOPIC:+--topic "$TOPIC"} ${STRICT:+--strict}
```

Read the result with the user:

- **typed** — finding's `entity_type` resolved to a bound ontology and its entity
  validated.
- **untyped** — no `entity`/`ontology` stamped (valid; just not classified).
- **invalid/unresolved** — a stamped type that does not resolve (undeclared,
  ambiguous without `ontology.id`, unbound) or whose entity fails the type schema.
  **These are real errors** — list each (`jq '.[]|select(.valid==false)'
  reports/<topic>/ontology-map.json`) and fix the finding's `entity`, or remove the
  bad stamp. Re-run Phase 1 to confirm they clear.

If `--enrich` is not set, stop here — this is a read-only audit (only the derived
`ontology-map.json` is written).

## Phase 2: Enrich (only with `--enrich`)

For each topic that is **core-only** or has many **untyped** findings:

1. **Bind a domain ontology (optional).** Match the topic (its title + finding
   content) against the catalog (`packs/ontologies/*` entity types). If one clearly
   fits, propose it; **if ambiguous or none fits, ask the user** (AskUserQuestion;
   offer top candidates + "stay core-only"). To bind, enable the pack and write the
   binding, then re-catalog (same as `/start` Phase 2b):

   ```bash
   ONTO=<chosen-id>
   jq --arg o "$ONTO" --arg t "$TOPIC" '
     (.ontologies[] | select(.id==$o) | .enabled) = true
     | (.topics[] | select(.id==$t) | .ontologies) = [$o]' \
     harness.config.json > tmp.$$ && mv tmp.$$ harness.config.json
   ajv validate --spec=draft2020 --strict=false -s harness.config.schema.json -d harness.config.json
   scripts/sync-packs.sh
   ```

2. **Retro-classify untyped findings.** For each untyped finding under the topic,
   review its content against the available types — the generic core (`mif-generic`:
   concept, person, organization, technology, file — always available) plus the bound
   domain ontology (inspect with
   `.claude/skills/ontology-manager/scripts/inspect_ontology.sh`). If the finding
   clearly *is* one of them, stamp its MIF `entity` block (`{name, entity_type,
   …domain fields}`; add `ontology.id` to disambiguate a name shared by generic and
   domain), then atomically rewrite it (stage + ajv on your own fields + rename, the
   crash-safe write pattern). Stamp only types you are confident in; leave the rest
   untyped — do not invent mappings.

3. **Re-review.** Re-run Phase 1 for the topic and confirm the new mappings resolve
   (typed count up, invalid count 0).

## Idempotence + safety

- Re-running review rebuilds `ontology-map.json` from disk — running it twice yields
  byte-identical maps. Enrichment only adds confident classifications; it never
  rewrites a finding's research content, only its `entity` block.
- A finding whose stamped type does not resolve is reported, never silently accepted
  — the deterministic resolver and `gate_m12` are the floor.

## Output

A per-topic coverage table, the list of any invalid/unresolved mappings to fix, and
(under `--enrich`) the bindings added and findings classified.
