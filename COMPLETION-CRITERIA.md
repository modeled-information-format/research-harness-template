# Completion Criteria — Research Harness Template Build

Authoritative definition of "done" for the full build of this template: all
eight milestones implemented, tested, reviewed, and verified. The build goal
references this document. Every criterion below must hold, and the named command
output must appear in the working transcript.

Read alongside `IMPLEMENTATION-PLAN.md` (the phased plan) and the design
specification (the Greenfield Research-Harness Template Design Specification,
sections 1 through 10). Commands assume the working directory is the repository
root, so `gh` resolves `{owner}/{repo}` from the local remote.

## Scope

Implement every phase in dependency order: Contracts, Scaffold, Engine, Harness
services, Packs, Outputs, Distribution, Corpus/KG migration. No phase is
optional; partial completion is not done.

Each milestone is delivered as its own pull request: branch from `main`,
implement, open a PR that closes the milestone's issues, pass CI and review, then
merge. One PR per milestone — eight in total. Progress is persisted to
`PROGRESS.md` (not only printed): update and commit it as each milestone starts
and completes.

## Global completion gates

All of the following hold, each proven by the named command's output.

### G1 — Backlog cleared

- `gh issue list --state open | wc -l` prints `0`.
- `gh api repos/{owner}/{repo}/milestones --jq 'map(.open_issues)|add'` prints
  `0` (every milestone has zero open issues).
- Each issue was closed by its implementing commit (`Closes #N`), not by hand.

### G2 — Structure matches section 7a

- The repository tree matches the spec's section 7a layout. Print it.
- Skills are flat: every skill is `.claude/skills/<name>/SKILL.md`, with no
  grouping subdirectories.
- Present: `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`,
  `.claude-plugin/marketplace.json`, `schemas/mif/`, `scripts/`, `docs/`,
  `evals/`, `reports/`.
- Every pack under `packs/<name>/` is a plugin with `.claude-plugin/plugin.json`
  and its own flat `skills/`.

### G3 — Contracts validate

- A JSON Schema validator (ajv-cli or python `jsonschema`) reports VALID,
  exit 0, for each schema against its paired sample: findings, harness.config,
  pack. Output shown.
- The findings schema references or extends the REAL MIF schema vendored under
  `schemas/mif/` from `/Users/AllenR1_1/Projects/zircote/MIF`. Not invented.

### G4 — Tested

- `bash scripts/verify.sh` exits 0, full output shown. It runs, at minimum:
  every per-milestone acceptance gate below, all schema validations, and the
  eval suite.
- The citation-integrity gate flags a BAD sample and passes a GOOD sample; both
  runs shown.

### G5 — Lint clean

- `markdownlint-cli2 "**/*.md"` reports 0 errors. Output shown.

### G6 — CI green

- A GitHub Actions workflow exists and runs verify, lint, and evals on push.
- The latest run on `main` is success: `gh run list --branch main --limit 1`
  shown as completed / success.

### G7 — Reviewed

- A code review of the final state was run (`/code-review` or the repo's review
  gate) and every must-fix finding resolved.
- The review summary is printed, showing 0 unresolved must-fix findings.

### G8 — Shipped

- All work committed and pushed to `main`. Print
  `git -C research-harness-template log --oneline -10`.
- Local HEAD equals remote: `gh api repos/{owner}/{repo}/commits/main --jq
  '.sha[0:7]'` matches the local short HEAD. Output shown.

### G9 — One PR per milestone

- Each milestone landed via its own pull request (branch, PR, merge to `main`);
  eight merged PRs total. `gh pr list --state merged --limit 50 | wc -l` prints
  `8` or more.
- Each merged PR maps to exactly one milestone and closed that milestone's issues
  via `Closes #N` in the PR body. No milestone implementation was committed
  directly to `main`.

### G10 — Progress persisted

- `PROGRESS.md` exists and is committed, with one entry per milestone recording:
  state (done), the PR number, the acceptance-gate verdict, and the date.
- It is updated as work proceeds, not only at the end. Print it; it shows all
  eight milestones marked done with their PR numbers.

## Per-milestone acceptance gates

A milestone is done only when its PR is merged to `main`, its issues are closed,
its acceptance gate is demonstrated, and `PROGRESS.md` records it. Fold each gate
into `scripts/verify.sh` wherever a command can assert it.

### Milestone 1 — Contracts

- Gate: each schema validates a sample with ajv or jq, and the pack contract
  validates a sample pack manifest.
- Deliver: MIF-backed findings schema (from the real MIF schema),
  `harness.config.schema.json`, `pack.schema.json` plus a sample
  `marketplace.json`, `STRUCTURED-DATA.md` (jq write-then-validate), and the
  citation-integrity gate script.

### Milestone 2 — Scaffold

- Gate: a clone is structurally valid: flat `SKILL.md` discovery paths resolve;
  `settings.json`, `marketplace.json`, and every `plugin.json` parse as valid
  JSON; the bundled hooks are wired. `scripts/verify.sh` asserts this.
- Deliver: the section 7a tree, bundled enforcement hooks, md-fix plus markdown
  hooks, and a merged Diataxis doc set.

### Milestone 3 — Engine

- Gate: a smoke test runs the orchestrator toward a sample session goal on a
  fixture; exactly one falsification gate runs; the run emits a finding that
  validates against the MIF-backed schema. Output shown.
- Deliver: orchestrator, dimension-analyst, falsification-analyst,
  source-chunker, and report-synthesizer as flat agents; a single adversarial
  gate; continuity (progress file plus resume); goal-oriented execution wired to
  `goal-writer`. The four codex gates are NOT carried.

### Milestone 4 — Harness services

- Gate: search, discover, lab, graph, and topics each operate over a MIF sample;
  the knowledge graph is built from MIF entities and relations, not tags. A
  script asserts the graph nodes and edges derive from MIF ids. Output shown.
- Deliver: a MIF-native knowledge graph, the five services, and incremental
  index-maintenance scripts.

### Milestone 5 — Packs

- Gate: enabling a pack through the manifest adds its namespaced skills and
  disabling removes them; an external or private plugin is ingested as a pack. A
  script toggles a pack and asserts skill presence and absence. Output shown.
- Deliver: market-research and trend-modeling methodology packs, the reports
  genre pack, and the channels pack (notebooklm, pdf, github-discuss,
  github-issues), each a plugin.

### Milestone 6 — Outputs

- Gate: a sample findings set renders to both a blog post and a book chapter
  through the same typed findings-to-artifact contract. Both artifacts produced;
  output shown.
- Deliver: blog and book as first-class outputs over the typed contract.

### Milestone 7 — Distribution

- Gate: a `copier update` re-applies a template change to an instantiated
  harness (shown), and the eval suite passes in CI (see G6).
- Deliver: a Copier-class template with update propagation; evals run in CI.

### Milestone 8 — Corpus/KG migration

- Gate: a sample of an existing corpus plus its knowledge graph imports into a
  fresh harness with provenance and graph edges intact; a script asserts node
  and edge counts and that provenance is preserved. Output shown.
- Deliver: the legacy v1-to-v2 migrate skill dropped; a corpus and
  knowledge-graph import path implemented as the first real use.

### Milestone 10 — MIF I/O conformance (SPEC §10)

- Gate: `verify.sh` `gate_m10` shows every basic markdown report projects to a
  valid MIF Level-3 finding (the same bar as a finding: `mif-project.sh` →
  `findings.schema.json` + citation-integrity, carrying a real, non-falsified
  verification verdict); every ingested source validates as a MIF source-envelope;
  and every MIF-exempt channel is declared and logged (no silent caps). The report
  emit path is write-then-validated and fails closed; a Stop-hook backstop
  (`check-output-conformance.sh`) warns on any non-conformant report.
- Deliver: the generic `report` channel as the canonical MIF Level-3 source of
  truth; manifest-declared exemption (`outputs[].mifExempt`, pack `mif.exempt`) for
  orthogonal-format channels (blog, book, pdf, notebooklm, github-issues,
  github-discuss); `wrap-source.sh` boundary normalization for ingested sources;
  and the §10 floor stated to bind every artifact the harness **emits and
  ingests**, not findings alone. Genres are L3 by default; exemption is for
  orthogonal formats, never genres.

### Milestone 11 — Session-recovery durability (SPEC §6b)

- Gate: `verify.sh` `gate_m11` shows, against a fixture session, that
  `scripts/reconcile-session.sh` derives a `state.json` checkpoint validating
  against `schemas/session-state.schema.json`; that reconcile is idempotent (two
  runs print byte-identical plans); that gated+valid findings are recorded done
  while invalid and `*.tmp` partial writes are excluded from done-counts; that
  `scripts/write-finding.sh` is atomic-to-valid (a finding lands only after it
  validates); and that a fully-gated session reconciles to an empty plan. Purely
  additive — no existing gate is weakened.
- Deliver: a disk-derived, idempotent reconcile checkpoint so `/resume` never
  reworks completed findings, and crash-safe (stage + validate + atomic rename)
  finding writes.

### Milestone 12 — MIF ontology conformance (SPEC §8c)

- Gate: `verify.sh` `gate_m12` shows that the vendored `ontology.schema.json`
  validates its sample; that every registry ontology (core + the six example data
  packs) validates against the contract; that `id@version` is unique; that
  `VENDOR.lock` checksums match the verbatim vendored files; that
  `scripts/resolve-ontology.sh` resolves a typed finding to exactly one bound
  ontology and validates its entity (additive) while undeclared, missing-required,
  and unbound-for-topic findings fail; that it fails safe on a missing catalog; that
  binding → catalog → registry integrity holds; and that the pack-enable path works
  end to end. Purely additive — no existing gate is weakened.
- Deliver: ontology vendored from MIF (contract + base + examples + `ontology-manager`
  skill), an always-on generic ontology (`mif-generic`), example ontologies as
  optional per-topic data packs, topic-onboarding ontology selection, and a
  deterministic topical resolver that records each finding's mapping to
  `reports/<topic>/ontology-map.json`.

## Constraints

- Author every artifact from the design spec and the real MIF schema. Never
  invent a contract, schema, or behaviour; trace each to its source.
- Skills are flat per the Agent Skills spec. Packs are Claude Code plugins,
  enabled and sourced through `harness.config.json`.
- Built artifacts contain NO corpus finding ids (such as `f_tech_*`) and NO
  `reports/<slug>` paths. They are clean, standalone engineering artifacts.
- Touch ONLY this repository and its GitHub issues, milestones, and Actions. Do
  NOT modify anything under `zircote/research` or `zircote/MIF`; read them
  freely.
- Close each issue via its implementing commit (`Closes #N`).
- If `git push` returns 404, push using the active `gh` token (repo scope).
  Never force-push or delete files. Ask before any other destructive or
  outward-facing step.
- Deliver each milestone on its own branch via one pull request; do NOT commit
  milestone implementation directly to `main`. CI (G6) and review (G7) gate every
  PR before merge.
- Work milestone by milestone in dependency order (1 through 8). After each,
  update and commit `PROGRESS.md` and print its remaining-open-issue count.

## Bound

If the end state is not reached, stop after 200 turns or when genuinely blocked,
and report exactly which milestones and issues remain and what blocks each.
