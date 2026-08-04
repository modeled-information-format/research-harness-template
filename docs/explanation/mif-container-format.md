---
id: explanation-mif-container-format
type: semantic
created: '2026-07-12T15:54:17Z'
modified: '2026-07-12T16:22:20.007Z'
namespace: docs/explanation
tags:
  - documentation
  - explanation
  - container
  - export-import
title: "Understanding the MIF Container format"
description: "Why topic export/import is a research-harness-template-local format, what the manifest actually holds, and what origin-scoped reconciliation keeps versus overwrites on import."
diataxis_type: explanation
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-12T15:54:17Z'
  ttl: P6M
  recordedAt: '2026-07-12T15:54:17Z'
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ae91b6b6-8d5c-4bea-963d-9e4b7907cf09
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Understanding the MIF Container format

## Why a topic-scoped format, not an org-wide one

An earlier draft of this feature argued it needed to wait on, or reconcile
with, the org-wide "MIF Container Profile" proposed separately in
`modeled-information-format/MIF#77` (an envelope for MNEMOS/Charon and other
MIF-ecosystem tools). ADR-0017 rejects that framing as scope creep: this
container is a `research-harness-template`-local schema
(`schemas/mif-container.schema.json`) built for one narrow job — moving a
research-harness **topic** (findings, citations, ontology typing, verdicts,
provenance) between two harness clones. It is independent of, and not
blocked on, whatever the org-wide profile eventually becomes. If that
profile is ever accepted and adopted as this schema's basis, that would be a
deliberate, budgeted follow-up decision — a breaking rewrite of the manifest
shape, not a quiet migration — not something this format waits on today.

The design is modeled on the OKF/Frictionless **Data Package** family
(`datapackage.json`, Table Schema) — the closest real, multi-portal-adopted
prior art the commissioning research found, closer than a git bundle, an OCI
artifact, or npm's `package-lock.json` — corrected on the two weaknesses
that research corroborated in Data Package itself: an opt-in integrity model,
and a v1-to-v2 migration that broke reference tooling for months.

## The manifest, in one picture

Every export produces one `mif-package.json`, validated against
`schemas/mif-container.schema.json`:

| Field | What it holds |
| --- | --- |
| `profile` | The manifest format's own versioned URI. An unrecognized value fails closed rather than being parsed best-effort. |
| `sourceInstance` | A label for the exporting instance — separate from any individual finding's own provenance, used only by the reconciliation policy below. |
| `exportScope` | `full`, `incremental`, or `subset`, plus the topic slug and when it was generated. |
| `ontologyBindings` | The exact ontology pack/version each packaged finding depends on. |
| `resources` | The manifest's own `resources[]` array (Data Package's naming), one entry per packaged file, each carrying a `mifType` discriminator and its own digest. |
| `boundaryReferences` | Explicit markers for any subset-excluded cross-reference — see below. |
| `manifestDigest` | One digest over every resource digest, so the whole container's integrity is checked in one step. |
| `createdAt` | When the export ran. |

The container mints no new identifiers of its own: every packaged finding
keeps the exact `urn:mif:concept:<namespace>:<slug>` id it already had. Only
the export act itself — the manifest — gets an identifier.

## Integrity: two digests, checked by default

Data Package's own integrity check is opt-in — a per-resource hash the
reader only verifies if it chooses to. This format makes it mandatory: every
resource carries a SHA-256 digest, verified on import with no flag to skip
it, and the manifest itself carries one more digest over all of those —
one check that covers the whole container in a single comparison, not just
each file in isolation.

## Subset exports: closure first, marker fallback, never silent

A subset export names an explicit set of findings to include. When one of
those findings references something outside that set, the export has two
options, tried in order:

1. **Closure** (`--closure`) — pull the referenced-but-out-of-scope target
   into the export too, so the subset stays self-contained.
2. **Boundary marker** — when closure wasn't requested (or isn't possible),
   the reference is recorded explicitly in `boundaryReferences[]` instead of
   being silently dropped or rewritten.

Silently dropping a cross-reference is never an option this format takes —
every excluded reference is either pulled in or named.

## Origin-scoped reconciliation, in plain terms

When an imported finding's `@id` already exists at the destination, the
import doesn't blindly overwrite it. Three named field-classes each get a
different treatment:

| Treatment | Fields | What happens |
| --- | --- | --- |
| **Origin-scoped** — destination always wins | `.provenance` (the finding's own W3C-PROV block), `.extensions.harness.verification` (the falsification verdict), `.extensions.harness.gathered_under` (session lineage) | The destination's existing value is kept — **even if the destination never had one and the incoming container does.** Absence at the destination is itself part of the destination's own state; a foreign verdict or session id doesn't become true just because the destination happened not to record one of its own. |
| **Union** | `.tags[]` | Both sides' tags are kept together, never replaced. |
| **Reconcile** — incoming wins | Everything else: content, summary, title, citations, relationships, ontology, entity | The whole point of re-importing an updated finding is that these fields actually update. |

Notice what this buys you: a finding you've already put through your own
falsification gate keeps *your* verdict when a stale or differently-verified
copy comes in from elsewhere, and a document you've hand-annotated with
`provenance` keeps that record rather than being told it was authored
somewhere else. Only the substantive content is meant to travel.

This is distinct from — and doesn't consult — the container-level
`sourceInstance` tag, which only labels where the container came from; it
plays no role in which field wins per finding.

## What this isn't

- **Not the same feature as [importing an existing
  corpus](../../how-to/import-a-corpus/).** That path is a one-time,
  first-clone-only adoption of an external corpus into a *freshly
  instantiated, empty* harness. This format moves an already-registered
  topic between two harnesses that are each already running, any number of
  times, in either direction.
- **Not the org-wide MIF Container Profile** (`MIF#77`) — see the first
  section above.
- **Not yet a `mif-rh-cli` subcommand.** M1 ships as a shell/skill pair
  (`/export`, `/import`) matching the existing `search`/`discover`/`graph`
  command pattern. Nothing measured so far indicates an export/import
  performance problem that would justify moving the logic into the compiled
  engine; that migration is a candidate M2 if a real bottleneck shows up,
  not a redesign already in motion.

## Where to go next

Ready to move a topic? The [how-to
guide](../../how-to/export-and-import-a-topic/) walks the whole export →
move → import journey. For the full decision record — the options
considered, the Stories that built each piece — see
[ADR-0017](../../adr/0017-mif-container-instance-scoped-export-import-format/).
