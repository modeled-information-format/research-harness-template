---
id: how-to-vendor-ontologies-on-demand
type: semantic
created: '2026-06-30T09:56:57-04:00'
modified: '2026-07-07T20:20:30-04:00'
namespace: docs/how-to
tags:
  - documentation
  - how-to
title: "Vendor ontologies on demand"
description: "Fetch a domain ontology from the canonical registry, verify it against its pinned hash, and author-and-contribute a new one when none exists."
diataxis_type: how-to
---

# Vendor ontologies on demand

Domain ontologies are fetched from the canonical registry (the `ontologies` repo,
served at `https://mif-spec.dev/ontologies/`) and verified fail-closed against a
pinned `sha256`. Base layers (`mif-base`, `mif-generic`, `shared-traits`,
`engineering-base`) ship committed and are never fetched. See
[ADR-0012](../../adr/0012-on-demand-ontology-vendoring/).

## Fetch a domain ontology

```sh
scripts/fetch-ontology.sh scientific          # one ontology + its extends closure
scripts/fetch-ontology.sh --all-enabled       # every ontology enabled in harness.config.json
scripts/sync-packs.sh                          # refresh the catalog after fetching
```

Each fetch resolves the `extends` closure, fetches every domain layer not already
present, verifies its `sha256` against the registry index (a mismatch aborts and
writes nothing), materializes `packs/ontologies/<id>/`, and pins the result in
`ontologies.lock.json`.

## An already-pinned ontology does not silently advance

`ontologies.lock.json` is the version pin, not just a record of the last
fetch, on an installed `mif-rh-cli` that supports pin-holding (check
`scripts/fetch-engine.sh` for the pinned release this repo currently
installs; an older engine has no `--refresh` flag and does not hold a
pinned id). On a supporting engine, re-running `scripts/fetch-ontology.sh`
for an id already in the lock leaves it at its pinned version, even if the
registry now offers a newer one:

```text
ontology fetch: nothing newly vendored (every requested layer is either already vendored or held at its pinned version)
WARNING: 1 ontology pack left at the pinned version, not the registry's current one: observability (pinned 0.1.0, registry has 0.2.0). Pass --refresh to advance deliberately.
```

This is deliberate: a schema version bump can add required fields to an
entity type, which would otherwise invalidate every already-stamped finding
of that type the moment `copier update` re-ran vendoring underneath you
(see [issue #270](https://github.com/modeled-information-format/research-harness-template/issues/270)
for the incident that prompted this). Advance the pin only when you are
ready to handle the schema change:

```sh
scripts/fetch-ontology.sh observability --refresh    # advance one id
scripts/fetch-ontology.sh --all-enabled --refresh     # advance every enabled id that has drifted
```

After advancing, find findings the new schema may affect (any finding
typed with an entity type the bumped ontology changed) and run
`/ontology-review --enrich` on the affected topics to reconcile them
against the new required fields before treating the corpus as clean again.

## Point at a source

Resolution order: `$MIF_ONTOLOGY_SOURCE`, then `.ontologies.source` (one line in
the repo root), then the default `https://mif-spec.dev/ontologies`. Use a local
directory for offline or CI runs:

```sh
MIF_ONTOLOGY_SOURCE=/path/to/ontologies/ontologies scripts/fetch-ontology.sh --all-enabled
```

## Verify vendored copies have not drifted

```sh
scripts/check-ontology-lock.sh    # every enabled domain ontology matches its pinned sha256
```

Vendored copies are **not** edited in place — a fix belongs **upstream** in the
`ontologies` repo, after which you re-fetch. The gate fails on any local drift.

## When the registry index has moved (re-pinning)

`ontologies.lock.json` pins the registry index's own sha256 as a trust root,
established on first fetch. If the registry publishes a new index, for
example after an upstream pack version bump, `scripts/fetch-ontology.sh`
refuses the fetch instead of silently accepting a new trust root:

```text
fetch-ontology: registry index sha256 changed from the pinned value for source <source>
  -> the trust root moved; refusing (clear .index_sha256 in ontologies.lock.json to re-pin deliberately)
```

This is expected the first time you re-vendor after an upstream registry
change (often following an
[update to a newer template release](../update-your-harness/)), not evidence
of tampering. Confirm the change is legitimate against the `ontologies`
repo's own history, then clear the `index_sha256` field in
`ontologies.lock.json` and re-run the fetch to re-pin the new index
deliberately.

## When no ontology exists: author one from your research

If a topic needs a domain the registry does not cover, fetch fails with a pointer
to author one. The harness drafts it from the entity types your findings already
used:

```sh
scripts/author-ontology.sh clinical-trials my-topic            # scaffold a draft
scripts/author-ontology.sh clinical-trials my-topic --open-pr  # concierge a draft PR upstream
```

The draft lists the topic's observed entity types (generic-fallback ones first),
with grounding (`source_vocab` / `source_class` / `prior_art`) stubbed `TODO` for
you to fill with a cited authority before the upstream PR merges.
