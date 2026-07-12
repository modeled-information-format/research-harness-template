---
id: how-to-export-and-import-a-topic
type: semantic
created: '2026-07-12T16:00:00Z'
modified: '2026-07-12T15:44:55.012Z'
namespace: docs/how-to
tags:
  - documentation
  - how-to
  - container
  - export-import
title: "Export and import a topic between harness instances"
description: "Move a research-harness topic — findings, ontology typing, tags, verification verdicts — from one instantiated harness to another using the MIF Container manifest, via /export and /import."
diataxis_type: how-to
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-12T16:00:00Z'
  ttl: P6M
  recordedAt: '2026-07-12T16:00:00Z'
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:3eeb65b8-4027-4e9e-afbe-ccfe2ae33a26
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Export and import a topic between harness instances

This moves an already-researched **topic** — its findings, citations, ontology
typing, concordance edges, verification verdicts, tags, and provenance — from
one instantiated harness clone to another (two clones, two orgs, a fork), via
the MIF Container manifest format (ADR-0017).

> This is **not** the same feature as [importing an existing
> corpus](import-a-corpus.md). That path brings an external corpus into a
> **freshly instantiated, empty** harness once, at setup time. This one moves
> an already-registered topic between two harnesses that are each already up
> and running, any number of times, in either direction.

## What you need

- A **registered topic** at the source: it must already exist under
  `harness.config.json`'s `topics[]` and have findings under
  `reports/<topic>/`.
- A **registered topic at the destination** to import into (`/configure` can
  register one if it doesn't exist yet).
- `jq` and `ajv-cli` (already required by `scripts/verify.sh`) — no other new
  dependency.

## Export a topic

Full export — every finding in the topic:

```text
/export <topic> <output-dir>
```

Subset export — only the findings named in a JSON array of
`urn:mif:concept:...` ids:

```text
/export <topic> <output-dir> --subset <in-scope-ids.json>
```

Add `--closure` to a subset export to pull in anything those ids reference
that isn't itself in scope, rather than leaving it as a boundary marker (see
[the explanation doc](../explanation/mif-container-format.md) for what a
boundary marker is and when you'd want one instead).

Pass `--source-instance <name>` to stamp a stable label for the exporting
instance on the manifest. Without it, the command defaults to a label derived
from the topic's own namespace — fine for a one-off, but if you'll be
exporting from this instance repeatedly, pick an explicit name once and reuse
it.

`<output-dir>` must not already exist, or must be empty — the export never
overwrites a directory's existing contents. When it finishes, `<output-dir>`
holds `mif-package.json` (the manifest) plus every resource file it names,
and the command has already self-checked the manifest against
`schemas/mif-container.schema.json` before reporting success.

## Move the container

`<output-dir>` is a self-contained, ordinary directory — copy it however you
already move files between the two instances (a shared volume, `scp`, a zip
of the directory, a PR attachment). Nothing about it depends on git or any
particular transport.

## Import a topic

```text
/import <container-dir> <topic>
```

`<topic>` is the **destination's** topic slug — it does not need to match the
source's topic name. Add `--dry-run` to run every validation step without
writing anything, useful for checking a container will actually apply before
you commit to it.

Import is **fail-closed and all-or-nothing**: manifest schema validation,
per-resource and manifest digest verification, and an ontology-binding
compatibility check against the destination's own vendored packs all have to
pass before anything is written — a failure at any step rejects the whole
import, never a partial write.

A finding whose `@id` doesn't exist at the destination yet is written as new.
One whose `@id` already exists is updated in place, but not by blind
overwrite — see [the reconciliation
policy](../explanation/mif-container-format.md#origin-scoped-reconciliation-in-plain-terms)
for exactly which fields the destination keeps versus which the incoming
container overwrites.

One asymmetry to know about ontology typing: a **full** import writes the
destination's `ontology-map.json` verbatim from the container. A **subset**
import only covers the ids it exported, so it upserts just those entries and
leaves every other finding's typing at the destination untouched — a subset
import can never delete typing for findings it didn't touch.

## What a rejected import looks like

Every rejection names the step that failed and writes nothing:

- **Manifest doesn't validate against the container schema** — the container
  itself is malformed; nothing about the destination is touched.
- **A resource's digest doesn't match the manifest** — the file was altered
  or corrupted in transit; the whole import is rejected, not just that one
  resource.
- **An ontology binding isn't an exact version match** at the destination —
  the destination hasn't vendored (or has a different version of) an
  ontology pack a finding depends on. M1 requires an exact match; there is no
  best-effort re-typing fallback yet.

In every case, re-running with `--dry-run` first tells you which of these it
is without touching the destination at all.

## What's next

For why the format is shaped this way — the manifest fields, the integrity
model, and exactly what "origin-scoped reconciliation" keeps versus
overwrites — read [Understanding the MIF Container
format](../explanation/mif-container-format.md).
