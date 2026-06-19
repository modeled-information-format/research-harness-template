# Build Progress

Per-milestone build state for the research-harness template. One entry per
milestone, updated as work proceeds (started + completed), recording: state, the
PR number, the acceptance-gate verdict, and the date. Mirrors the eight
milestones of `IMPLEMENTATION-PLAN.md` / GitHub milestones #1–#8.

| Milestone | State | PR | Acceptance gate | Date |
| --- | --- | --- | --- | --- |
| 1 — Contracts | done | #39 | PASS | 2026-06-19 |
| 2 — Scaffold | done | #40 | PASS | 2026-06-19 |
| 3 — Engine | in_progress | — | — | 2026-06-19 |
| 4 — Harness services | pending | — | — | — |
| 5 — Packs | pending | — | — | — |
| 6 — Outputs | pending | — | — | — |
| 7 — Distribution | pending | — | — | — |
| 8 — Corpus/KG migration | pending | — | — | — |

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
