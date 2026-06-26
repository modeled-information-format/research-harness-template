# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Instance owners:** this `CLAUDE.md` is template-managed (re-applied by
> `bash scripts/update.sh`). Put your clone's own guidance — active topics, house
> style, local paths — in a `CLAUDE.local.md` beside it; Claude Code loads both,
> and the template never touches `CLAUDE.local.md`. See
> [docs/how-to/instantiate-the-harness.md](docs/how-to/instantiate-the-harness.md).

## What this repo is

A single Copier-distributable **template** repository that a user clones (or
instantiates) to get a complete, self-contained AI research harness. There is no
application build step and no runtime package: the "product" is the orchestration
engine (Claude Code agents/commands/skills), the MIF-backed contracts (`schemas/`),
the shell tooling (`scripts/`), and the bundled packs — all shipped on clone.

Everything in and out of the harness is [MIF](https://github.com/zircote/MIF)
(Modeled Information Format). A finding is a MIF memory unit; the knowledge graph
is MIF EntityReferences + typed relationships; citations and provenance are MIF
objects. Patterns MIF core lacks (falsification lifecycle, quarantine, session
lineage) are closed **locally** under `extensions.harness` — never by forking MIF.

## Quality gates (run before reporting any change complete)

CI (`.github/workflows/ci.yml`, on push/PR to `main`) runs exactly these. Run the
same locally:

```bash
bash scripts/verify.sh                                   # full build gate: schema validation,
                                                         # citation-integrity, 22 per-milestone gates
CHECK=1 bash scripts/codegen/gen-models.sh               # fail if generated models drift from schemas
bash evals/run-evals.sh                                  # eval suite (engine smoke, model authoring, lint teeth, …)
bash evals/copier-update.sh                              # copier-update propagation
markdownlint-cli2 --config .markdownlint-cli2.jsonc "**/*.md"   # must be 0 errors
```

- `verify.sh` runs all gates as a fixed array (`GATES=(gate_m1 … gate_m22)`); there
  is **no single-gate CLI selector** — to iterate on one gate, run the whole script
  (fast) or `source` it and call the `gate_mN` function directly. It prints
  `verify.sh: N passed, 0 failed` on success and is the authoritative gate.
- A single eval: `python3 evals/test_models.py`, `bash evals/smoke-test.sh`, etc.
  (see the `run "<name>" <cmd>` lines in `evals/run-evals.sh`).
- **`verify.sh` gates fixtures, not an instance's imported `reports/` corpus** — in
  a clone it can pass green while real findings fail to resolve. The corpus-level
  gate is `scripts/ontology-review.sh [--strict]` (per-finding `ajv`, so slow — run
  it in the background). Never run `ontology-review`/`verify` **concurrently**: they
  race on shared temp/catalog state and produce spurious failures. After any
  ontology, pack-binding, or `copier update` change, run **both**.
- Toolchain: `jq`, `yq`, `ajv-cli` + `ajv-formats`, `markdownlint-cli2`, `copier`,
  `python3`. No `make`/`npm`/`pyproject` build — scripts are invoked directly.

## Generated code — do not hand-edit

`lib/harness_models/*.py` are stdlib `TypedDict` authoring models generated from
`schemas/*.schema.json` by `scripts/codegen/gen-models.sh` (datamodel-code-generator
with black, both pinned, run in a gitignored `.venv-codegen`). The generated modules
**are committed**, and CI enforces byte-identity (`CHECK=1`). If you change a
schema, regenerate (`bash scripts/codegen/gen-models.sh`) and commit the result.
Runtime stays pure stdlib; the codegen toolchain is dev/build-time only.

## Architecture: four layers, one repo

1. **Engine** — `.claude/agents/` (`orchestrator`, `dimension-analyst`,
   `falsification-analyst`, `source-chunker`, `report-synthesizer`) and the
   `.claude/commands/` (`start`, `falsify`, `goal-writer`, `resume`, `status`,
   `topics`, `ontology-review`) that delegate to them.
2. **Contracts** — `schemas/`: findings, goal, artifact, concordance, pack,
   session-state, plus `schemas/mif/` and `harness.config.schema.json`.
3. **Harness services** — flat skills in `.claude/skills/` (`search`, `discover`,
   `lab`, `graph`, `topics`, …) operating directly on the MIF substrate.
4. **Outputs** — the `report` channel is the canonical MIF **Level-3** source of
   truth (`reports/<topic>/<slug>.md`); `blog` is the first-class published
   projection; book/other channels and all deliverable genres are optional packs.

The engine↔services boundary is a **module boundary inside one repo**, not a repo
boundary. The research flow is goal-driven: `/start` ensures a `goal.json`
(`schemas/goal.schema.json`) exists, then the orchestrator loops **fan-out
dimension-analysts → single adversarial falsification gate → report-synthesizer**
until the goal's `completion_condition.checks` hold or its `bound` is hit. The
falsification gate is deliberately the *single* adversarial gate (see
`docs/adr/0004-…`).

## harness.config.json is the one file users edit

It is the deploy contract (validated by `harness.config.schema.json`): topics,
research `dimensions`, `outputs`, enabled `packs[]`, and `ontologies[]`. The
canonical version string also lives here.

## Packs are the only extension surface

Every optional capability is a Claude Code **plugin, one skill per plugin**, under
`packs/<family>/<skill>/` (`.claude-plugin/plugin.json` validated against
`schemas/pack.schema.json` + `skills/<skill>/SKILL.md`). The core hardwires none.
`harness.config.json` `packs[]` is the control plane:

```bash
bash scripts/sync-packs.sh                 # materialize enabled packs into the native enabledPlugins map
bash scripts/pack-toggle.sh <skill> on|off # flip one plugin
```

`sync-packs.sh` writes the resolved set into the **gitignored, instance-local**
`.claude/settings.local.json` (deep-merged with the template-managed
`.claude/settings.json`). `enabledPlugins` must never go in `settings.json`
(`gate_m5` enforces this; `settings.json` is byte-identical template-and-instance
so `copier update` never conflicts on it).

Ontology packs (`packs/ontologies/*`, `schemas/ontologies/*`) type findings: an
always-on generic core + optional domain ontologies, layered via `extends`,
enforced fail-closed by `resolve-ontology.sh` / `validate-concordance.sh`. Types
compose into the cross-topic **concordance** (`reports/concordance.json`).

## Template vs instance

The distributable template carries `copier.yml`; an instantiated clone does not.
`verify.sh` is byte-identical in both and detects context — template-only gates
(e.g. distribution, in-place corpus import) skip in an instance, but all
*capability* gates run everywhere. Never special-case files that `copier update`
must merge cleanly.

## Conventions that bite if missed

- **Version bumps are manual and lockstep.** A release version is stamped in
  `harness.config.json`, every core + pack `SKILL.md` frontmatter, every pack
  `plugin.json`, `marketplace.json`, and the rendered
  `docs/reference/packs/{channels,market-research,reports,trend-modeling}.md`.
  There is no bump script — change all of them together and re-run `verify.sh`
  (the SKILL.md frontmatter gate fails if any stamp drifts from `harness.config`).
  **The authoritative way to get the set right is to mirror the previous bump
  commit** (`git show <prev-release-commit> --name-only`), expanded to packs added
  since. **Do NOT touch these — they version independently of the template
  release:** `packs/ontologies/**` (`ontology.pack.json` + `*.ontology.yaml` carry
  their own `version`), `docs/reference/packs/ontologies.md`, and the
  `software-security`/ontology version fixtures inside `scripts/verify.sh`. Also
  leave CHANGELOG **history** lines, the `ontology-manager` `yq` example, and
  ontology changelog comments alone — they reference past versions, not the stamp.
  CHANGELOG follows Keep a Changelog: **insert a new `## [X.Y.Z] - YYYY-MM-DD`
  header directly under `## [Unreleased]`** (do not overwrite the prior dated
  section); the existing Unreleased items roll into it.
- **Releases are GitHub-Release-driven, not bare-tag.** `release.yml` triggers on
  `release: published` (+ `workflow_dispatch`), so a published Release named
  `vX.Y.Z` is what fires SLSA attestation — `git push --tags` alone does not.
  Land the lockstep bump on `main` first, then publish the `vX.Y.Z` Release at
  that commit.
- **Ephemeral artifacts go to `mktemp` outside the tree**, never into `reports/`.
  Only tracked data artifacts (findings, `knowledge-graph.json`,
  `concordance.json`, maps) belong in `reports/`. Writing derived output in-repo
  dirties the tree and blocks `copier update`. See `docs/reference/scripts.md`.
- **The ontology catalog `.claude/enabled-packs.json` is derived and gitignored.**
  `sync-packs.sh` rebuilds it from `schemas/ontologies/*` plus the *enabled* packs.
  Run it after any pack enable/binding or `copier update`: a stale catalog missing
  an `extends` target makes the fail-closed resolver mark the *entire* bound corpus
  invalid (it aborts resolution, it does not skip).
- **Relocating an entity type between ontologies is a migration.** A finding pins
  its type in a top-level `ontology.id` + `entity.entity_type` block, enforced
  strictly: a type that resolves under a *different* ontology than its pin names is a
  hard fail, not a fallback. Re-pin or drop the pin on every affected finding
  (`/ontology-review --enrich` is that pass).
- **Supply chain is fail-closed.** Every downloaded tool is verified
  (build-provenance attestation → pinned-SHA-256 checksum waterfall); every GitHub
  Action `uses:` is pinned to a 40-char SHA (the `pin-check` CI job enforces it).
- **Enforcement hooks travel with the engine** (`.claude/hooks/`, wired in
  `.claude/settings.json`): citation-leak gate, research-pipeline reminder, voice
  check, and the markdown `md_guard` (which never suppresses a diagnostic).

## Docs

`docs/` is a merged Diátaxis set (tutorials / how-to / reference / explanation).
Start with `docs/explanation/architecture.md`, `pack-structure.md`,
`ontological-spine.md`, and `docs/reference/scripts.md`. `COMPLETION-CRITERIA.md`
and `IMPLEMENTATION-PLAN.md` define the build milestones the `gate_mN` gates map to.
