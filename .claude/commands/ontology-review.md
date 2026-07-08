---
name: ontology-review
description: Review, validate, enrich, and author the ontology mapping of existing topics and their findings — audit coverage (including discovery-only findings that read as classified but carry no durable stamp), surface invalid/unresolved classifications, bind ontologies to unbound topics, retro-classify untyped/discovery-only findings, track a followup backlog, and use the ontology-manager skill to create/expand/enrich ontologies for new requirements.
argument-hint: "[--topic <id>] [--enrich] [--strict] [--followup <path>]"
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
onboarding step in `/start` (which only covers new topics). Four uses in one tool:
**review** (audit coverage), **validate** (surface classifications that do not
resolve), **enrich** (bind an ontology to an unbound topic and retro-classify its
untyped findings), and **author** (Phase 3 — use the `ontology-manager` skill to
create a new ontology, expand entity types, or enrich an existing ontology for new
requirements). The deterministic engine is `scripts/ontology-review.sh`; this command
adds the agent layer (binding selection, retro-classification, and authoring via the
`ontology-manager` skill).

Parse `$ARGUMENTS`: `--topic <id>` scopes to one topic (default: all topics);
`--enrich` turns on the binding/retro-classification pass (default: review only);
`--strict` makes the review exit non-zero if any finding is invalid/unresolved
(discovery-only and untyped findings do NOT fail `--strict` — they are backlog,
not corruption; use `--followup` to track them); `--followup <path>` writes a JSON
backlog of every finding that is not durably stamped, grouped by topic.

## Phase 1: Review + validate (deterministic, always)

Refresh every topic's `reports/<topic>/ontology-map.json` from disk and print a
coverage table (stamped / discovery-only / untyped / invalid per topic):

```bash
scripts/ontology-review.sh ${TOPIC:+--topic "$TOPIC"} ${STRICT:+--strict} --followup reports/_meta/ontology-followup.json
```

Read the result with the user:

- **stamped** — the finding's OWN `entity.entity_type` resolved to a bound ontology
  and its entity validated. This is a durable, real classification on disk.
- **discovery-only** — the finding has NO `entity` block at all; `resolve-ontology.sh`
  guessed a type at review time by matching the finding's content against the bound
  ontology's own discovery patterns, and recorded that guess in `ontology-map.json`
  (`basis: "discovery"`) — but **never wrote it back to the finding**. Re-running
  review re-derives the same guess (or a different one, if the finding's prose or the
  ontology's patterns changed); nothing durable exists until an analyst stamps the
  finding's `entity` block for real. A topic can show 100% coverage here while zero
  findings on disk carry an ontology stamp — treat this bucket as real backlog, not a
  clean result.
- **untyped** — no `entity`/`ontology` stamped and no discovery-pattern match either
  (valid; just not classified, with no auto-suggestion available).
- **invalid/unresolved** — a stamped type that does not resolve (undeclared,
  ambiguous without `ontology.id`, unbound) or whose entity fails the type schema.
  **These are real errors** — list each (`jq '.[]|select(.valid==false)'
  reports/<topic>/ontology-map.json`) and fix the finding's `entity`, or remove the
  bad stamp. Re-run Phase 1 to confirm they clear.

`--followup <path>` writes every discovery-only, untyped, and invalid finding —
grouped by topic, each with its `finding_id`, on-disk `file`, `basis`, and (for
discovery-only) the guessed `entity_type` as a starting point — to a single JSON
backlog (`{topics: {<topic>: [...]}, total_needs_followup: N}`). Re-running is
idempotent; the file is deterministic (sorted, no timestamps), so `git diff` on it
shows real corpus movement, not noise. Use it to size and prioritize the retro-
classification work in Phase 2, or hand it to another session/agent as a work queue.

If `--enrich` is not set, stop here — this is a read-only audit (only the derived
`ontology-map.json`, and `ontology-followup.json` if `--followup` was passed, are
written).

## Phase 2: Enrich (only with `--enrich`)

For each topic that is **core-only** or has many **untyped or discovery-only**
findings (the followup backlog from Phase 1 is the worklist — plus, when the
compiled engine has been run with `mif-rh-cli review --topic <id> --suggest`,
the scored suggestion queue `reports/_meta/suggestions/<topic>.json`; see
step 4 and ADR-0015):

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

2. **Retro-classify untyped AND discovery-only findings.** For each finding under
   the topic that Phase 1 reported as untyped or discovery-only (the followup
   backlog), review its content against the available types — the generic core
   (`mif-generic`: concept, person, organization, technology, file — always
   available) plus the bound domain ontology (inspect with
   `.claude/skills/ontology-manager/scripts/inspect_ontology.sh`). For a
   discovery-only finding, `ontology-followup.json` already carries a guessed
   `entity_type` — treat it as a starting hypothesis to confirm or correct, not a
   fact; the guess came from a regex content-pattern match, not analyst judgment.
   When the guess is unclear or absent, use the engine's read-only aids before
   falling back to judgment alone: `mif-rh-cli suggest-type --finding <path>`
   (or the always-available MCP tools `suggest_type`/`find_similar`/`search`),
   which rank candidate types by embedding similarity against the bound
   ontology — a hypothesis to weigh, never a type to auto-write, exactly like
   the guessed `entity_type` above.
   If the finding clearly *is* one of the available types, stamp its MIF `entity`
   block (`{name, entity_type, …domain fields}`; add `ontology.id` to disambiguate
   a name shared by generic and domain), then atomically rewrite it (stage + ajv on
   your own fields + rename, the crash-safe write pattern). Stamp only types you
   are confident in; leave the rest untyped — do not invent mappings.

3. **Calibrate, then (re-)queue scored suggestions.** Before trusting or
   working the suggestion queue below, confirm
   `reports/_meta/confidence-calibration.json` exists and reflects the current
   corpus (re-run after meaningful growth — a new topic, a large review pass):

   ```bash
   mif-rh-cli calibrate
   mif-rh-cli review --topic "$TOPIC" --suggest
   ```

   Skipping this is not harmless: without a calibration artifact, every
   candidate falls back to conservative built-in thresholds
   (`calibrated: false`), which biases scoring toward tier 3
   (`trigger_expansion`) regardless of true fit. See
   `docs/how-to/run-the-classification-engine-loop.md` for the full loop
   (calibration cadence, `--confusions` curation, MCP exposure).

4. **Work the scored suggestion queue (if present).** When
   `reports/_meta/suggestions/<topic>.json` exists (written by `mif-rh-cli review
   --suggest`, ADR-0015), enrich ALSO reads it. Each entry carries a ranked list
   of scored candidates (`{entity_type, ontology_id, score, tier, margin?,
   calibrated}`) for one finding. For each `"pending"` entry, review its
   candidates against the finding's content and set the entry's `status` to
   `confirmed` or `rejected` — **never delete an entry** (the engine preserves
   non-pending statuses across re-runs; deleting one would resurface it as
   pending). A confirmed candidate is still a hypothesis until stamped: it goes
   through the exact same typing edit as step 2 (stamp the finding's `entity`
   block, atomic rewrite) and a Phase 1 re-run to re-stamp resolution — **never
   a direct auto-write of `entity_type`**, at any tier, including tier 1
   `auto_classify_eligible` (the ADR-0011 invariant).

5. **Re-review.** Re-run Phase 1 for the topic and confirm the new mappings resolve
   (typed count up, invalid count 0).

## Phase 3: Author, expand, and enrich ontologies (the `ontology-manager` skill)

When review surfaces findings that no existing type fits — a new domain, a missing
entity type, or a type whose schema is too thin — author the ontology rather than
mis-classify. **Invoke the `ontology-manager` skill** (`Skill: ontology-manager`) for
the work; ontology definition files are unlocked for editing (only the vendored
*contract* `schemas/mif/ontology.schema.json` is checksum-locked). Every result must
re-validate, and `gate_m12` re-checks every ontology against the contract on build.

- **Create a brand-new ontology** (a new scheme for a new requirement):

  ```bash
  mkdir -p packs/ontologies/<id>
  bash .claude/skills/ontology-manager/scripts/scaffold_ontology.sh \
    <id> 0.1.0 --extends mif-base > packs/ontologies/<id>/<id>.ontology.yaml
  # add domain entity types with yq, then validate:
  bash .claude/skills/ontology-manager/scripts/validate_ontology.sh \
    packs/ontologies/<id>/<id>.ontology.yaml      # ajv vs the contract; must say VALID
  ```

  Register it as an optional data pack (`ontology.pack.json` `kind: ontology`) and
  enable/bind it via `/start` Phase 2b or this command's Phase 2.

- **Mine recorded tier-3 misses into a draft ontology** (when step 3 above
  keeps recording `trigger_expansion` misses for a topic — recurring,
  mutually-similar misses across runs, never a single miss — instead of
  scaffolding blank):

  ```bash
  mif-rh-cli expansion-candidates --out clusters.json
  scripts/author-ontology.sh <new-id> --from-clusters clusters.json
  ```

  Each cluster becomes a `todo-cluster-N` entry in the drafted ontology to
  name, define, and ground before validating it the same way
  (`validate_ontology.sh`) and enabling/binding it via `/start` Phase 2b or
  this command's Phase 2.

- **Add / expand entity types in an existing ontology:**

  ```bash
  yq -i '.entity_types += [{
    "name":"<type>", "base":"semantic",
    "schema":{"required":["name"], "properties":{"name":{"type":"string"}}}
  }]' <ontology>.ontology.yaml
  bash .claude/skills/ontology-manager/scripts/validate_ontology.sh <ontology>.ontology.yaml
  ```

- **Enrich an existing ontology** (improve fields, add relationships):

  ```bash
  # add/strengthen a field on a type, or add a relationship between types:
  yq -i '(.entity_types[] | select(.name=="<type>") | .schema.properties.<field>) =
           {"type":"string","description":"<desc>"}' <ontology>.ontology.yaml
  yq -i '.relationships.<rel> = {"description":"<desc>","from":["<a>"],"to":["<b>"]}' \
         <ontology>.ontology.yaml
  bash .claude/skills/ontology-manager/scripts/validate_ontology.sh <ontology>.ontology.yaml
  ```

Use `inspect_ontology.sh <file> --section entities` to see what a target ontology
already declares before expanding it. Any edited ontology must still pass
`validate_ontology.sh` (and `scripts/verify.sh` `gate_m12`); a change that breaks the
contract is rejected, not shipped.

## Idempotence + safety

- Re-running review rebuilds `ontology-map.json` (and, with `--followup`, the
  followup backlog) from disk — running it twice yields byte-identical output.
  Enrichment only adds confident classifications; it never rewrites a finding's
  research content, only its `entity` block.
- A finding whose stamped type does not resolve is reported, never silently accepted
  — the deterministic resolver and `gate_m12` are the floor.
- A discovery-only finding's guessed type is never treated as a durable stamp by
  any gate — `--strict` does not pass it as classified, and the shippable-typing
  gate (ADR-0011) still blocks synthesis on it exactly as it would on a genuinely
  untyped finding, since neither carries a real `entity` block on disk.

## Output

A per-topic coverage table (stamped / discovery-only / untyped / invalid), the list
of any invalid/unresolved mappings to fix, the followup backlog under `--followup`,
and (under `--enrich`) the bindings added, findings classified, and suggestion-queue
entries confirmed/rejected.
