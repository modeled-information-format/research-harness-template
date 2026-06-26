---
title: "Explanation: architecture"
diataxis_type: explanation
---

# Explanation: architecture

## One repository, four layers

The defining defect of the prior system was that the capability was split across
two repositories that had to be assembled by hand: the engine (a Claude Code
plugin) and the harness layer (a corpus repo). Neither alone was a research
harness (design spec §1, §3 L1).

The template unifies both halves. The boundary between engine and harness
services is a **module boundary inside one repo**, not a repo boundary
(§6a). The four layers — engine, contracts, harness services, outputs — all ship
on clone.

## MIF is the spine

There is one authoritative interchange format for findings *and* the knowledge
graph: [MIF](https://github.com/zircote/MIF) (§6c). A finding is a MIF memory
unit; the knowledge graph is MIF EntityReferences and typed relationships;
citations are MIF Citation objects; provenance is the MIF W3C-PROV block. This
collapses the prior schema drift into one machine-validated contract and makes
the graph first-class instead of tag-derived.

Where the harness needs a pattern MIF core does not carry (the falsification
lifecycle, quarantine state, session lineage), it closes the gap **locally** as
a harness-owned MIF extension under `extensions.harness` — never by forking MIF
(§8b).

## Packs are the only extension surface

The core researches anything. Every optional domain, deliverable genre, render
channel, and vocabulary arrives as a **pack**, and a pack is a Claude Code
plugin (§7b). The core hardwires none of them; `harness.config.json` `packs[]`
is the control plane that enables or disables each one and can ingest
external/private plugins. Packs compose with the core, never patch it.

## Enforcement travels with the engine

The quality gates are bundled hooks under `.claude/hooks/`, wired in
`.claude/settings.json`: the markdown anti-evasion guard (`md_guard.py`, which
never suppresses a diagnostic), the research-pipeline reminder, and the
citation-leak gate for published outputs. Because they ship with the template,
the gates are portable on clone — the prior system left them corpus-side, so
they did not travel with the tool (§3 L7).
