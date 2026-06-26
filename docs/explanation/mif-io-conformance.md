---
title: "MIF I/O conformance"
diataxis_type: explanation
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
