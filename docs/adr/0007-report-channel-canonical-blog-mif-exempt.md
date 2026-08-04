---
title: "Canonical report channel as L3 source of truth; blog channel MIF-exempt"
description: "Make the report channel the canonical L3 artifact graded by the gate, and exempt published channels by manifest declaration only."
type: adr
category: data
tags: [report, blog, channels, mif-exempt, citation-leak]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [MIF, Markdown, JSON Schema]
audience: [developers, architects]
related: [0002-mif-level-3-io-conformance.md, 0004-single-adversarial-falsification-gate.md]
---

# ADR-0007: Canonical report channel as L3 source of truth; blog channel MIF-exempt

## Status

Accepted

## Context

### Background and Problem Statement

The harness emits research into more than one channel: a canonical markdown
report and published prose (blog, and channel packs such as book). The question
is which channel is the authoritative L3 artifact, and how a published channel is
exempted from the L3 gate without exempting it silently
(`docs/explanation/mif-io-conformance.md`, `harness.config.json` `outputs[]`).

### Current Limitations

All channels are MIF Level-1 outputs, but holding a published format to the full
L3 conformance gate is the wrong bar — a blog post's published format is
orthogonal to the structured finding graph, and embedding internal finding
identity in published prose would leak it.

## Decision Drivers

### Primary Decision Drivers

1. Exactly one channel must be the canonical L3 source of truth, graded by the
   falsification gate.
2. Published prose must not leak internal MIF finding identity (citation-leak
   gate).

### Secondary Decision Drivers

1. Any exemption from the L3 gate must be declared in a manifest, never silent.
2. A published format orthogonal to MIF must not be forced into L3.

## Considered Options

### Option 1: Every channel is canonical L3

**Description:** Hold blog and report identically to the full L3 conformance gate.

- **Advantages:** Uniform rules across every channel.
- **Disadvantages:** Forces internal finding identity into published prose (which the citation-leak gate exists to prevent) and over-constrains formats like pdf or audio that are orthogonal to MIF.
- **Risk Assessment:** technical medium; schedule low; ecosystem high.

### Option 2: No canonical channel

**Description:** Treat all channels as equal projections, none privileged.

- **Advantages:** No channel is privileged over another.
- **Disadvantages:** There is no single graded source of truth; the falsification bar has nothing definitive to grade.
- **Risk Assessment:** technical low; schedule low; ecosystem high.

### Option 3: Report canonical, published channels declared-exempt

**Description:** Make the generic `report` channel the L3 source of truth graded by the gate; let `blog` and channel packs declare exemption in a manifest.

- **Advantages:** `reports/<topic>/<slug>.md` is the canonical L3 artifact carrying `extensions.harness.verification`, held to the same bar as a finding; `blog` declares `outputs[].mifExempt: true` with a recorded reason and is kept leak-free by the citation-leak gate; genres are L3 by default (exemption is for orthogonal formats, never genres); `gate_m10` logs every exempt surface.
- **Disadvantages:** Two conformance regimes (graded report vs exempt published) must be kept straight by authors.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 3: report canonical, published channels declared-exempt.** In
`harness.config.json` `outputs[]`, `report` is the canonical L3 source of truth
graded by the gate; `blog` is enabled with `mifExempt: true` and a stated
`mifExemptReason`. Published channels are projections of the same artifact,
exempt only because their format is orthogonal to MIF, and only when declared in
a manifest (`outputs[].mifExempt` for first-class channels, pack `mif.exempt` for
channel packs).

## Consequences

### Positive

1. There is exactly one graded source of truth, and published prose stays
   leak-free.
2. Exemption is auditable — every exempt surface is logged by `gate_m10`,
   fail-closed on the report.

### Negative

1. Authors must remember which channel is graded and which is a declared
   projection.

### Neutral

1. The blog is a first-class published projection, not a second-class output — it
   is simply graded differently from the canonical report.

## Decision Outcome

A canonical, gate-graded report plus manifest-declared exemptions for published
formats keeps exactly one trustworthy source of truth while letting prose
channels publish in their own format without leaking finding identity. The
two-regime burden on authors is mitigated by deterministic logging of every
exempt surface.

## Related Decisions

- [ADR-0002: MIF Level-3 I/O conformance](../0002-mif-level-3-io-conformance/)
- [ADR-0004: Single adversarial falsification gate](../0004-single-adversarial-falsification-gate/)

## Links

- `docs/explanation/mif-io-conformance.md`
- `harness.config.json` (`outputs[]`)

## More Information

- **Date:** 2026-06-23
- **Source:** `docs/explanation/mif-io-conformance.md`, `harness.config.json` (`outputs[]`)

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Report channel declared canonical | `harness.config.json` (`outputs[]` report) | compliant |
| Blog exemption declared with reason | `harness.config.json` (`outputs[]` blog, `mifExempt`, `mifExemptReason`) | compliant |
| L3 conformance model documented | `docs/explanation/mif-io-conformance.md` | compliant |

**Summary:** `outputs[]` declares the report channel canonical and the blog channel `mifExempt` with a stated reason; the conformance model is documented.

**Action Required:** None
