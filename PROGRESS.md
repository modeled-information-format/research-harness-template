# Build Progress

Per-milestone build state for the research-harness template. One entry per
milestone, updated as work proceeds (started + completed), recording: state, the
PR number, the acceptance-gate verdict, and the date. Mirrors the eight
milestones of `IMPLEMENTATION-PLAN.md` / GitHub milestones #1–#8.

| Milestone | State | PR | Acceptance gate | Date |
| --- | --- | --- | --- | --- |
| 1 — Contracts | done | #39 | PASS | 2026-06-19 |
| 2 — Scaffold | done | #40 | PASS | 2026-06-19 |
| 3 — Engine | done | #41 | PASS | 2026-06-19 |
| 4 — Harness services | done | #42 | PASS | 2026-06-19 |
| 5 — Packs | done | #43 | PASS | 2026-06-19 |
| 6 — Outputs | done | #44 | PASS | 2026-06-19 |
| 7 — Distribution | done | #45 | PASS | 2026-06-19 |
| 8 — Corpus/KG migration | done | #46 | PASS | 2026-06-19 |

## Milestone 1 — Contracts

**Started** 2026-06-19. Branch `milestone-1-contracts`.

Delivers the typed substrate every later phase exchanges: the MIF-backed findings
schema (built on the real vendored MIF v1.0 schema under `schemas/mif/`),
`harness.config.schema.json` + sample manifest, `pack.schema.json` + sample pack
manifest + `marketplace.json`, the `STRUCTURED-DATA.md` jq write-then-validate
protocol, and the citation-integrity gate. CI (`ci.yml`) and the accretive build
gate (`scripts/verify.sh`) are bootstrapped here so every later PR is CI-gated.

Acceptance gate: each schema validates its paired sample with ajv; the pack
contract validates a sample pack manifest; the citation-integrity gate flags a
BAD sample and passes a GOOD one. Asserted by `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #39 (squash-merged to `main`). Acceptance gate
PASS: `bash scripts/verify.sh` exit 0; CI green; code review (4 must-fix items
resolved: citation-gate jq hardening, contamination-scan `git grep`, marketplace
`owner`). Closed issues #1–#5.

## Milestone 2 — Scaffold

**Started** 2026-06-19. Branch `milestone-2-scaffold`.

Delivers the section 7a repository tree (flat `.claude/skills`, `agents`,
`commands`, `hooks`; `docs/` Diataxis; `evals/`, `packs/`, `reports/`), the
bundled enforcement hooks (markdown anti-evasion `md_guard`/`md_lint_core`/
`md_remediate`, `check-research-pipeline.sh`, `check-citation-leak.sh`) wired in
`.claude/settings.json`, the `md-fix` skill, and the merged Diataxis doc set.

Acceptance gate: a clone is structurally valid — flat `SKILL.md` discovery paths
resolve; `settings.json`, `marketplace.json`, and every `plugin.json` parse as
valid JSON; the bundled hooks are present, executable, and compile. Asserted by
`gate_m2` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #40 (squash-merged). Acceptance gate PASS:
`verify.sh` 12 checks; CI green; code review (untracked `.pyc` + `.gitignore`,
`MultiEdit` matcher, narrowed leak pattern). Closed issues #6–#9.

## Milestone 3 — Engine

**Started** 2026-06-19. Branch `milestone-3-engine`.

Delivers the five flat engine agents (orchestrator, dimension-analyst,
falsification-analyst, source-chunker, report-synthesizer) — domain-general
ports/redesigns of the corpus agents, with the four codex review gates dropped
and a single adversarial falsification gate retained; the goal-driven commands
(goal-writer, start, status, resume, falsify, topics); the session-goal contract
(`schemas/goal.schema.json` + sample goal); the deterministic falsification gate
(`scripts/falsify.sh`); continuity (progress-file template + resume); and the
engine smoke test (`evals/smoke-test.sh`).

Acceptance gate: the smoke test runs the orchestrator pipeline toward the sample
session goal on a fixture, runs exactly one falsification gate, and emits a
finding that validates against the MIF-backed findings schema. Asserted by
`gate_m3` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #41 (squash-merged). Acceptance gate PASS:
`verify.sh` 16 checks incl. the smoke test; CI green; code review (neutralized a
market-research pack example, completed the ajv verify recipes). Closed #10–#19.

## Milestone 4 — Harness services

**Started** 2026-06-19. Branch `milestone-4-services`.

Delivers the MIF-native knowledge graph (`scripts/build-graph.sh` derives nodes
from MIF EntityReferences + concepts and edges from typed MIF `relationships[]`,
never tags; `scripts/assert-graph-mif.sh` proves every node/edge is a `urn:mif:`
id), the incremental index (`scripts/build-index.sh`), the graph visualization
(`scripts/build-graph-viz.sh`), the five service skills (search, discover, lab,
graph, topics) operating over the MIF substrate, and a three-finding MIF sample
corpus that exercises entities and typed relationships.

Acceptance gate: search, discover, lab, graph, and topics each operate over the
MIF sample; the knowledge graph is built from MIF entities and relations, not
tags, and `assert-graph-mif.sh` asserts nodes/edges derive from MIF ids.
Asserted by `gate_m4` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #42 (squash-merged). Acceptance gate PASS:
`verify.sh` 21 checks; CI green; code review (closed the graph referentially with
external stub nodes, relaxed the entity assertion, made the gap check honest).
Closed #20–#26.

## Milestone 5 — Packs

**Started** 2026-06-19. Branch `milestone-5-packs`.

Delivers four bundled packs, each a Claude Code plugin validated against
`pack.schema.json`: `market-research` (methodology, disabled by default;
competitive/sizing/financial/regulatory/customer), `trend-modeling`
(methodology; INC/DEC/CONST), `reports` (genre; exec-summary/academic/
engineering/trend-analysis/briefing), and `channels` (channel; notebooklm/pdf/
github-discuss/github-issues). The control plane is `harness.config.json`
`packs[]`; `scripts/sync-packs.sh` materializes it into the enabled-skill set and
`scripts/pack-toggle.sh` flips a pack.

Acceptance gate: enabling a pack through the manifest adds its namespaced skills
and disabling removes them; an external/private plugin is ingested as a pack.
Asserted by `gate_m5` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #43 (squash-merged). Acceptance gate PASS:
`verify.sh` 26 checks; CI green; code review (made sync materialize into native
`enabledPlugins`, hardened the sync pass). Closed #27–#33.

## Milestone 6 — Outputs

**Started** 2026-06-19. Branch `milestone-6-outputs`.

Delivers blog and book as first-class outputs over the typed findings→artifact
contract: `schemas/artifact.schema.json` (the genre/channel-neutral intermediate
the report-synthesizer produces), `scripts/synthesize-artifact.sh` (surviving
findings → artifact), `scripts/render-artifact.sh` (one artifact → blog post or
book chapter), and the always-on `publish-blog` and `book-author` skills.

Acceptance gate: a sample findings set renders to both a blog post and a book
chapter through the same typed contract, both citation-leak clean. Asserted by
`gate_m6` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #44 (squash-merged). Acceptance gate PASS:
`verify.sh` 30 checks; CI green; code review (synthesizer fails loud on no
publishable content; book-render audience guard). Closed #34.

## Milestone 7 — Distribution

**Started** 2026-06-19. Branch `milestone-7-distribution`.

Delivers the Copier-class living template: `copier.yml` (instantiation Q&A,
`_templates_suffix: ".jinja"` so the harness files copy verbatim and keep passing
their own gates) + `.copier-answers.yml.jinja` + a templated identity file; the
shipped eval suite (`evals/run-evals.sh`: engine smoke, citation integrity,
MIF-graph derivation, blog+book outputs) run in CI; and the copier-update eval
(`evals/copier-update.sh`) that instantiates the harness, changes the template,
runs `copier update`, and asserts propagation. CI installs copier + Python and
runs the evals and the copier-update demo.

Acceptance gate: `copier update` re-applies a template change to an instantiated
harness, and the eval suite passes in CI. Asserted by `gate_m7` in
`scripts/verify.sh`.

**Completed** 2026-06-19 via PR #45 (squash-merged). Acceptance gate PASS:
`verify.sh` 33 checks; CI green (copier runs on ubuntu/py3.12); code review
(dropped a PyYAML dependency that broke CI). Closed #35–#36.

## Milestone 8 — Corpus/KG import

**Started** 2026-06-19. Branch `milestone-8-corpus-import`.

Delivers the corpus-and-knowledge-graph import path as the first real use of the
MIF substrate (SPEC §10): `scripts/import-corpus.sh` brings an existing MIF
corpus into a user's freshly instantiated harness — validating each unit against
the MIF-backed schema, preserving the W3C-PROV provenance block, registering the
topic, and rebuilding the index and graph with edges intact. A synthetic
`evals/fixtures/sample-corpus/` (findings + its shipped knowledge graph)
demonstrates it. The legacy v1→v2 migrate skill is intentionally dropped (CUT).

Crucially, the import targets an **instantiated harness**, never this template —
the template ships clean and standalone. `gate_m8` proves the import into a
temporary fresh harness (matching finding/node/edge counts, provenance preserved,
graph MIF-derived) and asserts the template repo's own `reports/` stays free of
any imported corpus.

Acceptance gate: a sample corpus + its knowledge graph imports into a fresh
harness with provenance and edges intact; a script asserts node and edge counts
and provenance preservation. Asserted by `gate_m8` in `scripts/verify.sh`.

**Completed** 2026-06-19 via PR #46. Acceptance gate PASS: `verify.sh` 39 checks
incl. the import into a temporary fresh harness (3 findings, 7 nodes, 10 edges,
provenance preserved); the template repo `reports/` ships clean. Closed #37–#38.

## Build complete

All eight milestones are done, each delivered as its own merged pull request:
M1 #39, M2 #40, M3 #41, M4 #42, M5 #43, M6 #44, M7 #45, M8 #46. The full build
gate (`bash scripts/verify.sh`) passes 39 checks; `markdownlint-cli2 "**/*.md"`
reports 0 errors; CI runs verify, the eval suite, the copier-update demo, and
lint on every push.
