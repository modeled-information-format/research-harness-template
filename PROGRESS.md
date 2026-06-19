# Build Progress

Per-milestone build state for the research-harness template. One entry per
milestone, updated as work proceeds (started + completed), recording: state, the
PR number, the acceptance-gate verdict, and the date. Mirrors the eight
milestones of `IMPLEMENTATION-PLAN.md` / GitHub milestones #1–#8.

| Milestone | State | PR | Acceptance gate | Date |
| --- | --- | --- | --- | --- |
| 1 — Contracts | done | #39 | PASS | 2026-06-19 |
| 2 — Scaffold | in_progress | — | — | 2026-06-19 |
| 3 — Engine | pending | — | — | — |
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
