---
id: explanation-mif-io-conformance
type: semantic
created: '2026-06-20T06:10:40-04:00'
modified: '2026-07-12T14:24:33.354Z'
namespace: docs/explanation
tags:
  - documentation
  - explanation
title: "MIF I/O conformance"
diataxis_type: explanation
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ae91b6b6-8d5c-4bea-963d-9e4b7907cf09
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# MIF I/O conformance

Every piece of information the harness produces **into** and **out of** the
project is MIF — including reports. This is the §10 conformance floor
(`harness.config.json` `mifConformanceLevel: 3`) made to bind the whole I/O
surface, not findings alone.

## The invariant

MIF Level 3 (provenance + citations + entities + extensions) binds every artifact
that crosses the project boundary:

- **Findings** — already MIF L3 (`schemas/findings.schema.json`).
- **Generic reports** — basic markdown reports (`reports/<topic>/<slug>.md`) are
  MIF L3, held to the **same bar as a finding**.
- **Ingested sources** — wrapped as validated MIF source-envelopes at the
  ingestion boundary.

## Generic report vs channel projection

MIF v1.0 is markdown-native: a concept is YAML frontmatter (authoritative) over a
Markdown body (the `content`), with the JSON-LD a *projection* of it. So a report
**is** a MIF document — its frontmatter carries the MIF identity, citations,
provenance, and the falsification verdict; its body is the human-readable content.
`scripts/mif-project.sh` projects frontmatter+body to JSON and validates it against
`findings.schema.json`.

The generic `report` channel is the **canonical source of truth**. The published
channels (`blog` and channel packs, including `book`) are **projections** of the same
artifact, rendered for human/format-specific consumption. They declare exemption
because their formats are orthogonal to MIF — the citation-leak gate keeps published
prose free of internal MIF identity, so the MIF lives in the report, not the post.

## Falsification-graded — same rigor, same limits, as a finding

Because a report carries `extensions.harness.verification`, it is held to the same
falsification bar as a finding. Be precise about what that buys and what it does
not:

- **What the gate enforces (deterministic):** a report cannot ship without a
  verification block that is *present, well-formed, non-`falsified`, and
  citation-clean*. `mif-project.sh` + the citation-integrity gate reject anything
  else, and a `falsified` report is quarantined. This is structural conformance,
  and it fails closed.
- **What rests on agent discipline (not deterministic):** that the verdict was
  *actually earned* by disconfirming search over the report's claims. Exactly as
  for a finding, the truthfulness of the verdict depends on the
  `falsification-analyst` doing real work — no gate can prove a `survived` verdict
  was honestly derived. A fabricated verdict is an agent-integrity violation for a
  report precisely as it is for a finding; the harness gives reports the same
  rigor as findings, and the same residual trust assumption, no more.

## Two-layer conformance: schema shape vs. witnessed provenance

The invariant above is a **schema-conformance** gate: it proves a report's
JSON-LD projection matches `findings.schema.json`, including a well-formed
`provenance` block — but a schema gate cannot distinguish a witnessed
provenance block from a model-asserted one that merely has the right shape.
`report-synthesizer`'s Step 4d closes that gap by stamping **witnessed**
provenance via `mif-docs-plugin`'s `mif-provenance` skill (ADR-0018) after
`render-artifact.sh` has already write-then-validated the report's schema
conformance. The two mechanisms are complementary, not redundant:

- **Schema conformance** (this document's invariant, ADR-0002): does the
  report's frontmatter/body project losslessly to a valid MIF L3 document?
  Enforced deterministically by `render-artifact.sh` → `mif-project.sh`.
- **Witnessed provenance** (`mif-provenance`, ADR-0018): does the
  `provenance` block's `agent`/`agentVersion`/`wasGeneratedBy` actually
  match what the session's hook-observed ledger recorded touching this
  file? A schema-valid block can still be fabricated; a witnessed one
  cannot — `stamp` declines rather than write an unwitnessed claim.

A report can be schema-conformant without being witnessed (if capture was
never enabled, or the file predates capture) — this is a legitimate,
lower-provenance-tier state the harness reports honestly rather than
silently upgrading. See `docs/reference/dependencies.md` for how capture is
enabled.

## Exemption — declared, never silent

A report is exempt only when its format is orthogonal to the result, and only when
declared in a manifest: `outputs[].mifExempt` for first-class channels, pack
`mif.exempt` for channel packs. **Genres are L3 by default** — exemption is for
orthogonal *formats* (pdf, audio, an external-service body), never for genres.
`gate_m10` logs every exempt surface, so nothing is skipped silently.

## Enforcement: fail-closed outbound, best-effort inbound

Be precise about the guarantee:

- **Outbound is deterministically fail-closed on structural conformance.** Reports
  are emitted by scripts that write-then-validate (`render-artifact.sh` →
  `mif-project.sh`, non-zero on a non-conformant report), and `verify.sh`
  `gate_m10` blocks the build. A Stop-hook backstop
  (`check-output-conformance.sh`) warns on any git-dirty non-conformant report.
  "Conformant" means the structural bar above (present, well-formed,
  non-`falsified`, citation-clean verdict) — not a proof that falsification
  actually ran, which rests on agent discipline as it does for findings.
- **Inbound is best-effort.** `WebFetch`/`WebSearch` happen inside an LLM agent, so
  boundary normalization is enforced by **agent instruction** (`wrap-source.sh`)
  plus **envelope validation** of the envelopes that exist (`gate_m10`). It is not
  deterministically gated — an agent could read content without wrapping it, and no
  gate would catch that. This asymmetry is stated plainly rather than implied away.

See [contracts](../reference/contracts.md) for the schemas and scripts.
