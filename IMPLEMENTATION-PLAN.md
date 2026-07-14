# Research Harness Template — Implementation Plan

This is the build roadmap for the research-harness template. It is derived from
the design specification (Greenfield Research-Harness Template — Design
Specification) and sequences that spec's decision ledger (its sections 4 and 4a)
into dependency-ordered phases. The original build spanned eight phases
(Contracts through Corpus/KG migration); the plan has since grown phase-by-phase
alongside `scripts/verify.sh`'s own `gate_mN` milestone gates, currently through
Phase 32. Each phase number below matches the milestone number of the same name
in `COMPLETION-CRITERIA.md` (`Phase N` ⇔ `Milestone #N`) — read that document
alongside this one for the full per-milestone acceptance-gate detail; this
document stays the terser work-item/dependency planning view.

This document is preparation for implementation. It plans and tracks the build;
it does not itself scaffold or build the template. Each phase maps to a GitHub
milestone of the same number, and every work item is tracked as an issue
labelled by its disposition.

Disposition legend: KEEP (carry as-is), REDESIGN (rework), ADD (build new), CUT
(do not carry, recorded by design).

## Phase 1 — Contracts (Milestone #1)

The typed substrate every later phase exchanges. Build the contracts first so
agents, services, packs, and outputs all speak one schema.

Depends on: nothing — this is the foundation.

Work items:

- REDESIGN — Adopt a single MIF-backed findings/knowledge schema (§6c).
- KEEP — Keep the Structured Data Protocol: jq write-then-validate (§7a).
- REDESIGN — Publish harness.config.json plus its JSON Schema (§7).
- ADD — Define the pack.json plugin contract and marketplace.json (§7b).
- ADD — Add the verifier / citation-integrity gate (§6b).

Acceptance gate: each schema validates a sample artifact with ajv or jq, and the
pack contract validates a sample pack manifest.

## Phase 2 — Scaffold (Milestone #2)

Create the repository skeleton from the spec's section 7a tree, with flat skills
and bundled gates so a clone is runnable and self-documenting.

Depends on: Phase 1 (schemas to place under schemas/).

Work items:

- ADD — Scaffold the section 7a tree: flat .claude/skills, agents, commands,
  hooks; .claude-plugin/marketplace.json; packs/; schemas/; scripts/; docs/;
  evals/; reports/ (§7a).
- REDESIGN — Bundle enforcement hooks with the engine (§7a).
- KEEP — Bundle the md-fix skill and markdown hooks (§7a).
- KEEP — Bundle a merged Diataxis documentation set (§7a).

Acceptance gate: a clone opens in Claude Code with no errors, the bundled hooks
fire, and the flat skills are discovered at `.claude/skills/<name>/SKILL.md`.

## Phase 3 — Engine (Milestone #3)

The orchestrator and its agents, reduced to one adversarial gate, driven by a
measurable session goal.

Depends on: Phase 1 (contracts) and Phase 2 (tree).

Work items:

- KEEP — Keep the swarm orchestrator and parallel dimension-analyst fan-out
  (§6b).
- KEEP — Port the orchestrator agent: phase-owning and goal-driven (§6b).
- REDESIGN — Make dimension-analyst dimensions config-declared and
  domain-general (§4a).
- KEEP — Port the falsification-analyst as the single verification gate (§6b).
- KEEP — Port the source-chunker (RLM) agent (§4a).
- REDESIGN — Redesign report-synthesizer as the domain-general output entry
  (§6d).
- KEEP — Keep the adversarial falsification gate (§6b).
- CUT — Drop the four codex review gates (§6b).
- KEEP — Keep continuity: the progress file and resume (§6b).
- KEEP — Wire goal-oriented execution: goal-writer to session goal (§2, §6b).

Acceptance gate: the orchestrator runs toward a sample session goal, one agent
emits a schema-valid MIF finding, and exactly one falsification gate runs.

## Phase 4 — Harness services (Milestone #4)

Search, exploration, discovery, and the knowledge graph, all over the MIF
substrate rather than tag-derived recomputation.

Depends on: Phase 1 (MIF substrate) and Phase 3 (engine produces findings).

Work items:

- REDESIGN — Make the knowledge graph first-class over MIF (§6c).
- REDESIGN — Rebuild the search skill over the MIF index (§4a).
- KEEP — Port the lab skill for interactive exploration (§4a).
- KEEP — Port the discover skill: gaps, clusters, stale (§4a).
- REDESIGN — Fold the graph skill into the MIF-native graph (§4a).
- KEEP — Port the topics skill: registry listing (§4a).
- REDESIGN — Replace reindex/build scripts with incremental MIF maintenance
  (§4a).

Acceptance gate: search, discover, lab, graph, and topics all operate over a MIF
sample, and the graph builds from MIF entities/relations, not tags.

## Phase 5 — Packs (Milestone #5)

Everything optional as plugins on the single extension surface, enabled and
sourced through the manifest.

Depends on: Phase 1 (pack contract), Phase 2 (marketplace), Phase 3 (engine).

Work items:

- CUT — Demote market-research to an optional methodology pack (§7b).
- CUT — Demote issue-architect / GitHub-issues to an optional channel pack
  (§7b).
- ADD — Build the reports genre pack: exec-summary, academic, engineering,
  trend-analysis, briefing; financial and market on demand (§6d).
- KEEP — Ship trend-modeling as an optional methodology pack (§7b).
- CUT — Move discuss (GitHub Discussions) into the channels pack (§7b).
- KEEP — Move nlm-artifacts into the channels pack, optional (§7b).
- KEEP — Move report-pdf into the channels pack, optional (§7b).

Acceptance gate: enabling a pack adds its namespaced skills and disabling removes
them, and an external/private plugin is ingested as a pack via the manifest.

## Phase 6 — Outputs (Milestone #6)

Blog and book as first-class outputs over the typed findings-to-artifact
contract.

Depends on: Phase 1 (contract), Phase 4 (services), Phase 5 (channels pack).

Work items:

- ADD — Promote blog and book to first-class outputs over a typed contract
  (§6d).

Acceptance gate: a sample findings set renders to both a blog post and a book
chapter through the same typed contract.

## Phase 7 — Distribution (Milestone #7)

Package the whole as a living, upgradable template with evals in CI.

Depends on: Phase 2 (tree) and all prior phases (the packaged whole).

Work items:

- ADD — Adopt a Copier-class template with update propagation (§7).
- KEEP — Ship evals and run them in template CI (§7).

Acceptance gate: a copier update re-applies a template change to an instantiated
harness, and the eval suite passes in CI.

## Phase 8 — Corpus/KG migration (Milestone #8)

Drop the legacy migration and plan the first real use: importing the existing
corpus and, above all, its knowledge graph.

Depends on: Phase 1 (MIF schema), Phase 4 (graph), Phase 7 (a working template).

Work items:

- CUT — Drop the legacy v1-to-v2 migrate skill (§4a).
- ADD — Plan the corpus and knowledge-graph import as the first real use; keep
  the MIF substrate and contracts compatible with that import (§10).

Acceptance gate: a sample of the existing corpus and its knowledge graph imports
into a fresh harness with provenance and edges intact.

## Phase 9 — Citation feature flag (Milestone #9)

An opt-in flag for instances that intentionally cite internal (non-URL)
documents, without weakening the strict default for everyone else.

Depends on: Phase 1 (contracts — the citation-integrity gate).

Work items:

- ADD — Add an opt-in `features.internalCitations` config flag to
  `harness.config.json`.

Acceptance gate: an internal-citation sample passes the citation-integrity
gate when the flag is enabled, and is rejected under the strict URL-required
default.

## Phase 10 — MIF I/O conformance (Milestone #10, SPEC §10)

Every basic markdown report the harness emits is MIF Level 3; every ingested
source is a validated MIF source-envelope; exceptions are declared, never
silent.

Depends on: Phase 1 (contracts), Phase 6 (outputs).

Work items:

- REDESIGN — Make the generic `report` channel the canonical MIF Level-3
  source of truth.
- ADD — Add manifest-declared MIF exemption (`outputs[].mifExempt`, pack
  `mif.exempt`) for orthogonal-format channels (blog, book, pdf, notebooklm,
  github-issues, github-discuss).
- ADD — Add `wrap-source.sh` boundary normalization so every ingested source
  validates as a MIF source-envelope.
- ADD — Add the `check-output-conformance.sh` Stop-hook backstop that warns
  on any non-conformant report.

Acceptance gate: every basic markdown report projects to a valid MIF
Level-3 finding; every ingested source validates as a MIF source-envelope;
every MIF-exempt channel is declared and logged, never silently capped.

## Phase 11 — Session-recovery durability (Milestone #11, SPEC §6b)

A disk-derived, idempotent reconcile checkpoint so `/resume` never reworks
completed findings, and crash-safe finding writes.

Depends on: Phase 3 (engine — findings + continuity), Phase 4 (harness
services).

Work items:

- ADD — Add `scripts/reconcile-session.sh`, a disk-derived, idempotent
  `state.json` checkpoint (`schemas/session-state.schema.json`).
- REDESIGN — Make `scripts/write-finding.sh` atomic-to-valid (stage +
  validate + atomic rename).

Acceptance gate: reconcile is idempotent (two runs print byte-identical
plans); gated+valid findings are recorded done while invalid and `*.tmp`
partial writes are excluded; a fully-gated session reconciles to an empty
plan.

## Phase 12 — MIF ontology conformance (Milestone #12, SPEC §8c)

Ontology vendored from MIF, an always-on generic ontology, and a
deterministic per-finding resolver, moving to on-demand vendoring (ADR-0012).

Depends on: Phase 1 (contracts), Phase 4 (harness services — the knowledge
graph).

Work items:

- ADD — Vendor the ontology contract + base + example ontologies from MIF,
  plus the `ontology-manager` skill.
- ADD — Add the always-on generic ontology (`mif-generic`) and per-topic
  example ontologies as optional data packs.
- ADD — Add `scripts/resolve-ontology.sh`, a deterministic per-finding
  ontology resolver recording `reports/<topic>/ontology-map.json`.
- ADD — Add `/ontology-review` authoring (create/expand/enrich) via the
  `ontology-manager` skill.
- REDESIGN — Move from a seed-time `VENDOR.lock` to on-demand vendoring
  (ADR-0012), unlocking the ontology contract/definitions for authoring
  (#223).

Acceptance gate: every registry ontology validates against the contract;
`id@version` is unique; the resolver binds a finding to exactly one
ontology and fails on undeclared/missing-required/unbound-for-topic
findings; the pack-enable path works end to end.

## Phase 13 — Ontological spine / concordance (Milestone #13, SPEC §8d)

A unified, ontology-typed, fail-closed cross-topic concordance.

Depends on: Phase 12 (ontology conformance).

Work items:

- ADD — Add `schemas/concordance.schema.json` and
  `scripts/build-concordance.sh` to merge topics into one schema-valid
  concordance.
- ADD — Add `scripts/validate-concordance.sh`, fail-closed on an undeclared
  entityType, an undeclared relationship type, or a from/to domain
  violation.

Acceptance gate: concept nodes are stamped with resolved ontology
entityType + verdict; a falsified finding is present and flagged, not
excluded; an entity referenced in two topics is one node merged by
`urn:mif:` @id; the build is deterministic.

## Phase 14 — Falsification gate safety (Milestone #14, issues #356/#372/#384)

An honest-default verdict plus a phase-gate mechanism closing several
real-invocation bypass classes found in live review.

Depends on: Phase 3 (engine — the falsification gate).

Work items:

- REDESIGN — Make an ungated falsification verdict default to
  `inconclusive` (never a false `survived`), withholding `attempted_at` so
  it is not permanently gate-locked.
- ADD — Add the `guard-falsify-gate.sh` PreToolUse hook enforcing a
  per-topic, freshness-windowed gate on findings-grade `falsify.sh`
  invocations.
- REDESIGN — Make `falsify.sh` itself independently refuse to grade outside
  a fresh gate window, closing every real-invocation bypass shape the
  hook's own substring match can miss.

Acceptance gate: the phase-gate hook and `falsify.sh`'s own independent
check each deny grading outside a topic's fresh gate window, and every
known real-invocation bypass shape stays denied.

## Phase 15 — Living corpus: goal evolution (Milestone #15, SPEC §11)

Content-hashed goal versions, reshape reuse of in-scope findings, and the
reuse-and-stop loop `/start --update` walks.

Depends on: Phase 3 (engine — goal-writer), Phase 4 (harness services — the
index).

Work items:

- ADD — Add `scripts/goal-version.sh`, a content-hashed, stable,
  lineage-invariant goal identity.
- ADD — Add `schemas/goal.schema.json` `version`/`supersedes`/`revision`
  fields.
- ADD — Add `scripts/resolve-membership.sh`, reshape reuse across goal
  versions with per-goal-version freshness and gap computation.
- ADD — Add `extensions.harness.gathered_under` to findings and project
  `goal_versions[]` into the index.

Acceptance gate: `goal-version.sh` produces a stable, content-sensitive
identity; reshape reuse carries in-scope findings across goal versions and
computes the resulting gap; a new gap finding closes the gap and an
excluded one stays excluded across a re-resolve.

## Phase 16 — Diátaxis channel MIF Level-1 frontmatter (Milestone #16, SPEC §6d/§10)

A public-facing Diátaxis documentation tree carrying MIF Level-1 identity
without leaking internal research identifiers.

Depends on: Phase 5 (packs), Phase 10 (MIF I/O conformance).

Work items:

- ADD — Add the `diataxis` channel pack rendering findings to a Diátaxis
  tree.
- ADD — Add `schemas/diataxis-doc.schema.json` (MIF L1 concept +
  `diataxis_type` marker).

Acceptance gate: every rendered doc projects to a valid MIF L1 concept with
exactly one `diataxis_type` marker and no internal-research identity in its
body, and the rendered set is complete (reference/explanation/how-to/
tutorials + indexes), not a stub.

## Phase 17 — Topic README freshness (Milestone #17, issue #84)

A deterministic README rebuild wired into every mutation path that changes
a topic's substrate.

Depends on: Phase 4 (harness services).

Work items:

- ADD — Add `scripts/build-topic-readme.sh`'s freshness-check mode
  alongside its existing build mode.
- REDESIGN — Wire the README rebuild into every shell-write mutation path
  (`falsify.sh`, `publish-report`) a PostToolUse hook cannot observe.

Acceptance gate: a topic README stays metadata-fresh against its substrate
across every mutation path, including the shell-write paths a PostToolUse
hook cannot observe; authored Key Findings prose survives rebuild even
under a cosmetically-perturbed heading.

## Phase 18 — Supervising a running orchestrator (Milestone #18)

Idle/stall guidance for a human or agent supervisor, plus a Phase 1
heartbeat.

Depends on: Phase 3 (engine — the orchestrator).

Work items:

- ADD — Document idle/stall supervision guidance in `start.md`/`resume.md`.
- ADD — Add a coarse Phase 1 fan-out heartbeat to `research-progress.md` in
  `orchestrator.md`.

Acceptance gate: `start.md`/`resume.md` document the idle-is-not-a-stall
supervision signal, and `orchestrator.md` emits a Phase 1 fan-out heartbeat.

## Phase 19 — Instance-safe CI (Milestone #19, issue #85)

A propagation gate that fails closed in the template but safely no-ops in
an instantiated clone, and markdownlint-safe progress-log headings.

Depends on: Phase 7 (distribution — the copier template/instance split).

Work items:

- REDESIGN — Tighten `evals/copier-update.sh`'s instance-skip guard to the
  exact work-tree-AND-untracked-`copier.yml` condition.
- REDESIGN — Make `orchestrator.md` emit the progress-log title H1 exactly
  once and drop fixed cross-session snapshot headings.

Acceptance gate: `copier-update.sh` behaviorally skips inside an
instantiated clone, and `orchestrator.md` emits the progress-log H1 exactly
once with no fixed cross-session heading.

## Phase 20 — Cross-pack relationship reference integrity (Milestone #20, research-harness-template#276/Story #287)

A whole-registry relationship-endpoint integrity scan closing a gap a
per-ontology gate cannot see on its own.

Depends on: Phase 12 (ontology conformance).

Work items:

- ADD — Delegate a whole-registry relationship-endpoint integrity scan to
  the `mif-rh` engine (`harness check-ontology-registry`).

Acceptance gate: every cross-pack relationship endpoint across the whole
ontology registry resolves to a declared entity type.

## Phase 21 — Layered ontology spine (Milestone #21)

Transitive `extends` resolution through non-core ancestor layers, with an
enforced upstream-submission boundary.

Depends on: Phase 12 (ontology conformance), Phase 20 (registry integrity).

Work items:

- ADD — Support transitive `extends` resolution through non-core ancestor
  ontology layers, with an enforced upstream-submission boundary.

Acceptance gate: a topic binding only a descendant ontology pack resolves
an ancestor layer's type transitively, while an unrelated pack does not.

## Phase 22 — Entity-type subsumption (Milestone #22)

`subtype_of` enforced substitutability at relationship endpoints.

Depends on: Phase 13 (concordance — `validate-concordance.sh`), Phase 21
(layered spine).

Work items:

- ADD — Add `subtype_of` subsumption enforcement (Liskov substitutability)
  to `validate-concordance.sh`, plus a registry-wide subtype-parent
  integrity scan.

Acceptance gate: a `subtype_of` type is substitutable at a relationship
endpoint typed for its supertype, and every `subtype_of` parent across the
registry is declared.

## Phase 23 — Site projection (Milestone #23, research-harness-template#414)

Reports as a first-class Starlight surface, config-driven from
`harness.config.json`'s `.site` block.

Depends on: Phase 6 (outputs), Phase 7 (distribution).

Work items:

- ADD — Bind `docs/` and `reports/` into one Starlight content collection
  via a title-deriving loader.
- ADD — Make `astro.config.mjs` read `harness.config.json`'s new `.site`
  block to gate site plugins and `primarySurface`.
- ADD — Add a copier `_tasks` hook flipping an instantiated clone to
  reports-primary.

Acceptance gate: the site renders the full topic deliverable tree,
`astro.config.mjs` gates every site plugin off `harness.config.json`'s
`.site` block, and a stable `/reports/` landing page is reachable from the
splash and sidebar.

## Phase 24 — Fail-closed ontology-completeness gate (Milestone #24, ADR-0011)

A fail-closed shippable-finding-typing gate wired ahead of synthesis.

Depends on: Phase 13 (concordance), Phase 22 (subsumption).

Work items:

- ADD — Add `scripts/check-shippable-typing.sh`, blocking synthesis on any
  untyped/unstamped/unparseable shippable finding.
- REDESIGN — Wire the typing gate plus concordance build/validate into
  orchestrator Phase 4, strictly before the synthesizer is spawned.

Acceptance gate: any untyped, discovery-only, or unparseable shippable
finding blocks synthesis, and the typing gate runs before the synthesizer
is spawned.

## Phase 25 — Cross-topic corpus atlas (Milestone #25)

A deterministic, fail-closed synthesis layer above the per-topic
synthesizer.

Depends on: Phase 13 (concordance).

Work items:

- ADD — Add `scripts/synthesize-corpus.sh`, projecting a cross-topic
  `corpus-map.json` and `corpus-synthesis.md`.

Acceptance gate: `synthesize-corpus.sh` projects a deterministic
cross-topic `corpus-map.json` and `corpus-synthesis.md` that keeps
falsified findings in the full record.

## Phase 26 — MIF Container manifest schema (Milestone #26, Epic #275/Story #308, ADR-0017)

The structural contract for a portable, instance-scoped export/import
bundle.

Depends on: Phase 13 (concordance — ontology-typed findings to export).

Work items:

- ADD — Add `schemas/mif-container.schema.json`, the structural contract
  for a portable, instance-scoped export/import bundle.

Acceptance gate: the Container manifest schema validates full/empty/subset
export samples and fails closed on every structural loophole review found
(bad profile, missing digest, mismatched `mifType`/`ontologyType`, path
traversal).

## Phase 27 — MIF Container digest engine (Milestone #27, Epic #275/Story #312)

The shared per-resource/per-manifest digest primitive every other Container
script builds on.

Depends on: Phase 26 (Container schema).

Work items:

- ADD — Add `scripts/mif-container-digest.sh`, the shared
  per-resource/per-manifest sha256 digest primitive.

Acceptance gate: resource and manifest digests are deterministic,
order-independent, and content-sensitive, and fail closed on a missing or
unreadable file.

## Phase 28 — MIF Container export-scope resolver (Milestone #28, Epic #275/Story #315)

Turns an in-scope finding-id set into the `resourceIds`/
`boundaryReferences` pair a Container manifest needs.

Depends on: Phase 4 (harness services — the knowledge graph), Phase 26
(Container schema).

Work items:

- ADD — Add `scripts/mif-container-resolve-scope.sh`, resolving an in-scope
  finding-id set to `resourceIds`/`boundaryReferences`, with `--closure` as
  an explicit opt-in.

Acceptance gate: the scope resolver marks every out-of-scope reference as a
boundary reference by default, and `--closure` transitively expands scope
to every reachable concept instead.

## Phase 29 — MIF Container fail-closed import gate (Milestone #29, Epic #275/Story #318)

Atomic per-import validation, idempotent re-import, and a topic-scoped
stale-aware lock.

Depends on: Phase 26 (Container schema), Phase 27 (digest engine).

Work items:

- ADD — Add `scripts/mif-container-import.sh`: atomic validation, idempotent
  re-import, a topic-scoped stale-aware lock, never a partial write on
  rejection.

Acceptance gate: import is idempotent on unmodified content, rejects the
entire import before any write on a digest/ontology/schema mismatch, and
fails closed on a concurrent or stale lock.

## Phase 30 — MIF Container origin tagging + reconciliation policy (Milestone #30, Epic #275/Story #324)

Origin-scoped reconciliation plus read-only candidate sameAs detection.

Depends on: Phase 29 (import gate).

Work items:

- REDESIGN — Add an origin-scoped reconciliation policy to import
  (verdict/`gathered_under`/provenance never overwritten; `tags[]` union).
- ADD — Add read-only candidate sameAs detection surfacing possible
  cross-topic duplicates without auto-merging.

Acceptance gate: a re-imported finding's verdict/`gathered_under`/
provenance stay origin-scoped (never overwritten by the incoming import),
and a candidate sameAs match surfaces as a proposal without ever
auto-merging.

## Phase 31 — MIF Container export builder + /export /import commands (Milestone #31, Epic #275/Story #328)

The export half of the Container round-trip, verified lossless end to end.

Depends on: Phase 28 (scope resolver), Phase 29 (import gate).

Work items:

- ADD — Add `scripts/mif-container-export.sh` and the `/export`/`/import`
  commands, sharing the stale-aware lock with import.

Acceptance gate: a full export→import round-trip into a fresh topic
reproduces the exact same finding set, ontology-map, and topic
deliverables, and export shares the same stale-aware lock as import.

## Phase 32 — mif-docs conformance floor (Milestone #32, research-harness-template#413, ADR-0018)

A structural conformance floor against `mif-docs-plugin`'s real validator,
completing the substrate migration (ADR-0018).

Depends on: Phase 16 (Diátaxis docs), Phase 23 (site projection).

Work items:

- ADD — Add a `gate_m32` CI floor running `mif-docs-plugin`'s own
  `mif-validate --level 1`/`--level 3` against every fixture/template
  document this repo commits.

Acceptance gate: every fixture/template document this repo commits passes
`mif-docs-plugin`'s `mif-validate --level 1`, and any document declaring
provenance also passes `--level 3`.
