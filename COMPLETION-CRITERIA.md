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

### Milestone 9 — Citation feature flag (features.internalCitations)

- Gate: `verify.sh` `gate_m9` shows an internal-citation sample validates and
  PASSES `check-citation-integrity.sh` when `harness.config.json`'s
  `features.internalCitations` is `true`, and is REJECTED under the strict
  default (flag `false`/absent) since it carries no http(s) URL.
- Deliver: an opt-in `features.internalCitations` config flag that relaxes the
  citation-integrity gate to accept internal (non-URL) citation sources for
  instances that intentionally cite internal documents, while the strict
  default (URL required) is unchanged for every existing instance.

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
  packs) validates against the contract; that `id@version` is unique; that the
  ontology **contract and definitions are unlocked/editable** (no verbatim lock —
  on-demand vendoring per ADR-0012 supersedes the retired seed-time `VENDOR.lock`,
  #223); that the `ontology-manager` skill scaffolds a contract-valid NEW
  ontology and the registry is extensible (count rises); that
  `scripts/resolve-ontology.sh` resolves a typed finding to exactly one bound
  ontology and validates its entity (additive) while undeclared, missing-required,
  and unbound-for-topic findings fail; that it fails safe on a missing catalog; that
  binding → catalog → registry integrity holds; and that the pack-enable path works
  end to end. The supply-chain assertion is intentionally **contract-scoped** (so
  ontologies can be authored); every other gate is additive and unweakened.
- Deliver: ontology vendored from MIF (contract + base + examples + `ontology-manager`
  skill), an always-on generic ontology (`mif-generic`), example ontologies as
  optional per-topic data packs, topic-onboarding ontology selection, a deterministic
  topical resolver that records each finding's mapping to
  `reports/<topic>/ontology-map.json`, and `/ontology-review` authoring (create /
  expand / enrich ontologies via the `ontology-manager` skill).

### Milestone 13 — Ontological spine / concordance (SPEC §8d)

- Gate: `verify.sh` `gate_m13` shows, against a two-topic fixture corpus, that the
  `schemas/concordance.schema.json` validates its sample; that `scripts/build-concordance.sh`
  merges topics into a schema-valid `concordance.json`; that `scripts/validate-concordance.sh` is
  fail-closed (a conformant concordance passes, while an undeclared `entityType`, an undeclared
  relationship type, and a `from`/`to` domain violation each fail); that concept nodes are
  stamped with their resolved ontology `entityType` + verdict; that a falsified finding is
  present and flagged (not excluded); that an entity referenced in two topics is one node
  merged by `urn:mif:` @id; and that the build is deterministic. Purely additive.
- Deliver: a unified, ontology-typed, fail-closed cross-topic concordance — concept nodes
  stamped with ontology type + verdict, entities merged across topics by @id, the full
  research record (falsified flagged not excluded), and ontology conformance enforced
  over the graph (entity types + relationship from/to domains).

### Milestone 14 — Falsification gate safety (honest default + phase-gate hook, issues #356/#372/#384)

- Gate: `verify.sh` `gate_m14` shows `falsify.sh` defaults a finding with no
  evidence-fixture entry to a placeholder `inconclusive` verdict that omits
  `attempted_at` (never a false `survived`, and not permanently gate-locked
  by the one-round rule), while an explicit fixture verdict is recorded
  unchanged; the `guard-falsify-gate.sh` PreToolUse hook denies a
  findings-grade `falsify.sh` invocation outside its topic's gate window (and
  on a STALE window), allows it within a fresh window, always allows a
  non-findings report-finding target, and denies when ANY topic's window is
  closed in a multi-topic command; a wide set of real-invocation bypass
  shapes (env-var prefixes, `command`/`env`/`time`/`sudo`, loops, `xargs`,
  alternate interpreters, quoted paths) stay denied with no window open,
  while a known, accepted false-deny (a command that only quotes
  `falsify.sh` as documentation text) is intentionally not narrowed away;
  and `falsify.sh` itself independently refuses to grade a session finding
  with no/stale window open (including from a cwd already inside
  `findings/`, with a bare or dotted relative path), while never gating an
  unrelated `findings/` path outside `reports/<topic>/`.
- Deliver: an honest-default falsification verdict (`inconclusive`, not
  `survived`, for anything never actually graded) plus a phase-gate
  mechanism — a PreToolUse hook AND an independent check inside `falsify.sh`
  itself — that only allows grading session findings inside a topic's own
  fresh gate window, closing the "stray/non-gate invocation contaminates the
  verdict" failure and multiple real-invocation bypass classes found across
  issues #356, #372, and #384.

### Milestone 15 — Living corpus: goal evolution + finding reuse (SPEC §11)

- Gate: `verify.sh` `gate_m15` shows `goal-version.sh` produces a stable,
  lineage-invariant, content-sensitive `gv-<hash>` identity; a versioned goal
  (`version`/`supersedes`/`revision`) validates against `goal.schema.json`
  with `revision.date` enforced as an RFC 3339 date; a finding carrying
  `extensions.harness.gathered_under` still validates against
  `findings.schema.json`; reshaping a goal's dimensions reuses in-scope
  findings from the prior version, drops out-of-scope ones (still stale, not
  attempted), and computes the resulting gap dimension; freshness flips on a
  recent `attempted_at` and the membership mirror projects `goal_versions[]`
  into the index; and the core reuse-and-stop loop holds end to end — a new
  finding stamped `gathered_under=<version>` joins membership and closes the
  gap on resolve, and excluding it (as `goal-writer` does) persists across a
  re-resolve, reopening the gap.
- Deliver: goal versioning (content-hashed, stable identity across cosmetic
  edits, sensitive to real content changes) plus membership resolution that
  reuses prior-version findings instead of rerunning research from scratch,
  tracks per-goal-version freshness decay, and closes the loop
  `/start --update` walks — new findings join membership and close gaps;
  excluded findings stay excluded.

### Milestone 16 — Diátaxis channel MIF Level-1 frontmatter (SPEC §6d, §10)

- Gate: `verify.sh` `gate_m16` shows the `diataxis-doc` L1 schema (MIF base
  concept + a `diataxis_type` marker) validates its sample; rendering the
  sample findings corpus to a Diátaxis tree produces docs that each project
  to a valid MIF L1 concept, carry exactly one `diataxis_type` marker and one
  body H1, keep the body free of internal `urn:mif:`/finding-id/`reports/`
  path identity, lint clean under markdownlint when available, and form a
  COMPLETE set — one reference page per surviving finding, one explanation
  and how-to per dimension, and the tutorials plus every index/landing page
  present, not a stub subset.
- Deliver: the `diataxis` channel pack, which projects a findings corpus into
  a public-facing Diátaxis documentation tree (reference/explanation/how-to/
  tutorials) carrying MIF Level-1 identity without leaking internal research
  identifiers — the generic `report` channel stays the canonical Level-3
  source of truth, and this channel remains declared `mif.exempt` from the
  L3 floor by design.

### Milestone 17 — Topic README freshness (deterministic metadata stays current vs. substrate, issue #84)

- Gate: `verify.sh` `gate_m17` shows a hermetic fixture: a freshly built
  topic README is fresh against its substrate, and a new finding added
  afterward makes it stale, proving the freshness check detects drift in
  both directions; every registered topic with a README on disk is checked
  fresh against its live substrate as a CI backstop; the shell-write
  mutation paths a PostToolUse hook can't observe (`falsify.sh`
  verdict/quarantine changes, a report rendered via shell redirect) are
  documented to also trigger a README rebuild; and prose preservation
  survives a cosmetically-perturbed `## Key Findings` heading (trailing
  space) without clobbering authored synthesis prose.
- Deliver: `scripts/build-topic-readme.sh`'s freshness/build-mode split plus
  wiring into `falsify.sh` and `publish-report` so a topic's `README.md`
  never silently drifts from its findings substrate after any of the
  mutation paths that change it.

### Milestone 18 — Supervising a running orchestrator (idle/stall guidance + Phase 1 heartbeat)

- Gate: `verify.sh` `gate_m18` shows `start.md` and `resume.md` document how
  a supervisor should wait on a running session (the growing
  `findings/*.json` count is the live progress signal; an idle notification
  or a quiet `research-progress.md` is not itself a stall), and
  `orchestrator.md` emits a coarse Phase 1 "fan-out started" heartbeat to
  `research-progress.md` so a supervisor sees progress between Session
  Initialized and Dimensions Complete instead of a long silent gap.
- Deliver: documented supervision guidance plus an orchestrator heartbeat so
  a human or agent watching a long-running research session can distinguish
  real progress from a stall during the otherwise-silent dimension fan-out
  phase.

### Milestone 19 — Instance-safe CI: template-only propagation gate + idempotent progress-log headings (issue #85)

- Gate: `verify.sh` `gate_m19` shows `evals/copier-update.sh`'s instance-skip
  guard matches the exact condition (a work-tree check AND a negated
  tracked-`copier.yml` check, not merely "some `git ls-files` call exists")
  and behaviorally SKIPs when run inside a throwaway repo with no tracked
  `copier.yml` (an instantiated clone) rather than failing CI there; and
  `orchestrator.md` emits the `research-progress.md` title H1 in exactly one
  place (file creation, never per-session) and uses no fixed cross-session
  snapshot heading (e.g. a bare `## Findings Summary`), so a multi-session
  progress log never trips markdownlint's duplicate/multiple-H1 rules.
- Deliver: a copier-update propagation eval that fails closed in the
  template but safely no-ops in an instantiated clone, and a progress-log
  heading discipline in the orchestrator that stays markdownlint-clean
  across an arbitrary number of research sessions on the same topic (issue
  #85's D1 and D2).

### Milestone 20 — Cross-pack relationship reference integrity (research-harness-template#276, Story #287)

- Gate: `verify.sh` `gate_m20` shows, via the `mif-rh-cli` engine's
  `harness check-ontology-registry`, that every relationship from/to
  endpoint declared across ALL registry ontologies — including cross-pack
  edges like security's `realizes`/`mitigates_threat` targeting
  software-engineering's `security-incident`/`security-threat` — resolves to
  an entity type declared in SOME registry ontology, so a future rename in
  one pack can't silently dangle an edge declared in another.
- Deliver: a whole-registry relationship-endpoint integrity scan (delegated
  to the `mif-rh` engine) that `gate_m12`'s per-ontology validation cannot
  see on its own, closing the cross-pack dangling-reference gap.

### Milestone 21 — Layered ontology spine (transitive extends + upstream boundary)

- Gate: `verify.sh` `gate_m21` shows, against a self-contained catalog, that
  a topic binding only a descendant pack (software-engineering) resolves a
  type declared by a non-core ANCESTOR layer (engineering-base) reached
  transitively through `extends` — not because that ancestor is always-on —
  while a topic binding an unrelated non-engineering pack does NOT resolve
  that same type, proving the domain vocabulary never leaks into the
  always-on generic core.
- Deliver: transitive `extends` resolution through the ontology spine plus
  an enforced upstream-submission boundary, so domain packs can layer on
  shared ancestor vocabulary without that vocabulary becoming implicitly
  global.

### Milestone 22 — Entity-type subsumption (enforced substitutability)

- Gate: `verify.sh` `gate_m22` shows a `subtype_of` relationship (e.g.
  software-security's `security-control` `subtype_of` engineering-base's
  `control`) makes the finer type substitutable at a relationship endpoint
  typed for its supertype (Liskov substitutability) — a `security-control`
  source satisfies a `governs` edge requiring `control`/`policy`, while a
  non-subtype source is rejected — and that every `subtype_of` parent
  declared across the whole registry (via the `mif-rh` engine) itself
  resolves to a declared type.
- Deliver: `subtype_of` subsumption enforcement in `validate-concordance.sh`
  plus a registry-wide subtype-parent integrity scan, so finer domain
  entity types can stand in for their declared supertypes at relationship
  endpoints without a schema author having to enumerate every subtype
  explicitly.

### Milestone 23 — Site projection (reports surface + feature flags, research-harness-template#414)

- Gate: `verify.sh` `gate_m23` shows the Astro/Starlight content loader
  binds both `docs/` and `reports/` into one collection via a
  title-deriving glob (so the full topic deliverable tree — README,
  synthesis, falsification report, research-progress — renders, with only
  `_meta`/findings and build-log files excluded); `astro.config.mjs` reads
  `harness.config.json`'s `.site` block to gate each site plugin and
  `primarySurface` rather than hardcoding them, builds an index-only reports
  sidebar, and registers a topic-filter Sidebar override; the manifest
  schema validates the `.site` block; the template ships and serves its own
  archived example topic while staying docs-primary (a copier hook flips a
  clone to reports-primary); and a stable `/reports/` landing page is
  reachable from the splash and sidebar.
- Deliver: `harness.config.json`'s `.site` block as the control plane for
  the Astro/Starlight site (never hand-edited `astro.config.mjs`), a
  reports-as-first-class-surface content loader, and a config-driven
  docs-primary/reports-primary toggle activated by the copier `_tasks` hook
  on instantiation.

### Milestone 24 — Fail-closed ontology-completeness gate + auto-reconciled spine (ADR-0011)

- Gate: `verify.sh` `gate_m24` shows `check-shippable-typing.sh` blocks
  synthesis (fail closed, pointing at `/ontology-review --enrich`) on any
  shippable (survived/weakened) finding that is untyped, discovery-only
  (guessed but never durably stamped), unparseable, or backed by an
  unparseable or wrong-shape `ontology-map.json` — while a falsified finding
  never blocks, a fully-typed shippable corpus passes and its concordance
  builds/validates, discovery covers both the nested `findings/` and flat
  `finding-*.json` layouts, and every blocker names the offending file; and
  orchestrator Phase 4 is wired to run the typing gate plus concordance
  build/validate strictly before the synthesizer is spawned, so the gate
  cannot be bypassed by synthesis running first.
- Deliver: a fail-closed shippable-finding-typing gate wired ahead of
  synthesis (ADR-0011), so a corpus can never ship an untyped or unstamped
  finding into the concordance by omission, undercounting, or a corrupted
  ontology-map.

### Milestone 25 — Cross-topic corpus atlas (synthesize-corpus.sh)

- Gate: `verify.sh` `gate_m25` shows, against a two-topic concordance
  fixture, that `synthesize-corpus.sh` projects a `corpus-map.json` covering
  topics, verdict distribution, cross-topic entity reuse, and
  contradictions, and renders a `corpus-synthesis.md` that keeps the FULL
  record — a falsified finding still appears under "What Was Disproven"
  rather than being dropped as the per-topic synthesizer does; that two
  builds are byte-identical (deterministic, no wall-clock content); and
  that `--check` fails closed on an unauthored draft, passes once
  cross-topic insights are authored, and the build itself fails closed when
  the concordance is missing.
- Deliver: a cross-topic corpus atlas — a deterministic, fail-closed
  synthesis layer one level above the per-topic synthesizer that surfaces
  cross-topic entity reuse and contradictions while preserving the full
  research record, falsified findings included.

### Milestone 26 — MIF Container manifest schema (Epic #275, Story #308, ADR-0017)

- Gate: `verify.sh` `gate_m26` shows `schemas/mif-container.schema.json`
  validates a full-export sample (with a required-but-empty
  `boundaryReferences[]`), a zero-finding-topic sample, and a subset-export
  sample carrying a `boundaryReferences[]` entry; fails closed on an
  unrecognized `profile` value and a manifest missing `manifestDigest`; and
  — across a set of review-caught structural loopholes — rejects a subset
  export with a null (not merely absent) selector, couples a resource's
  `mifType`/`ontologyType` pairing (an ontology-map/concordance resource
  must carry `ontologyType` as null, present not omitted; a finding
  resource must carry a non-null one), rejects a full export carrying any
  `boundaryReferences[]` entry or omitting the array entirely, rejects a
  non-null selector on a full/incremental export, and rejects a resource
  path containing `..` or an absolute path (directory-traversal guard) —
  while still validating a subset export whose selector legitimately
  matches zero resources.
- Deliver: `schemas/mif-container.schema.json`, the structural contract for
  a portable, instance-scoped MIF export/import bundle (ADR-0017) — a
  manifest describing its export scope, ontology bindings, packaged
  resources with per-resource digests, and any boundary references it
  deliberately excludes.

### Milestone 27 — MIF Container digest engine (Epic #275, Story #312)

- Gate: `verify.sh` `gate_m27` shows per-resource digests are deterministic,
  match `sha256sum`/`shasum` directly, and are content-sensitive; manifest
  digests are order-independent (inputs sorted before hashing, NFR-1) and
  are still well-defined over an empty resource set (matching the
  empty-topic sample's `manifestDigest`); a missing or unreadable input
  file fails closed with a named error rather than a silent/malformed
  digest; and extra positional arguments are rejected rather than silently
  ignored.
- Deliver: `scripts/mif-container-digest.sh`, the shared per-resource and
  per-manifest sha256 digest primitive every other MIF Container script
  (export, import, resolve-scope) builds integrity checking on top of.

### Milestone 28 — MIF Container export-scope resolver (Epic #275, Story #315)

- Gate: `verify.sh` `gate_m28` shows the resolver, against a fixture
  knowledge graph: for a full in-scope set, every concept-to-concept
  relationship is already satisfied while entity-mention edges still
  surface as boundary references (entities are never a packageable
  resource); for a partial in-scope set with no closure, an
  excluded-but-referenced concept becomes an explicit out-of-scope boundary
  reference rather than being silently dropped; with `--closure`,
  dependency closure takes precedence over marking and transitively pulls
  in every reachable concept (AD-4), while entity mentions still never get
  closure-included; a different-namespace target classifies "cross-topic"
  and a same-namespace missing target classifies "unresolvable" (namespace
  check ordered before node-presence, closing a real classification bug);
  an empty in-scope set is valid, not an error; the resolver fails closed on
  missing arguments, a missing graph file, or a malformed ids file; a graph
  missing `.edges[]` fails fast under `--closure` rather than hanging (a
  real prior infinite-loop bug); a malformed-but-concept-prefixed target
  still surfaces as an "unresolvable" boundary reference rather than
  vanishing; a malformed first element in the in-scope set doesn't poison
  topic-namespace inference for the rest of the set; and duplicate ids in
  the in-scope input are deduplicated in `resourceIds` with or without
  `--closure`.
- Deliver: `scripts/mif-container-resolve-scope.sh`, which turns a
  caller-supplied in-scope finding-id set into the `resourceIds`/
  `boundaryReferences` pair a MIF Container manifest needs, with
  dependency-closure as an explicit opt-in over the graph.

### Milestone 29 — MIF Container fail-closed import gate (Epic #275, Story #318)

- Gate: `verify.sh` `gate_m29` shows re-importing a topic's own unmodified
  content is a true idempotent no-op (0 written, matched by @id and digest,
  NFR-4); a per-resource digest mismatch or an ontology-binding version
  mismatch rejects the ENTIRE import before any write (NFR-2/NFR-3), never
  a partial/best-effort write; `--dry-run` validates every step and writes
  nothing (AC11); importing into an unregistered topic fails closed; a
  brand-new @id is written as a new finding file and a re-import of the
  same @id with different content overwrites in place, never duplicating;
  an @id containing regex-special characters is matched literally, not as a
  pattern; a multi-resource manifest with one schema-invalid finding
  rejects the whole import in bulk pre-validation, before any write happens
  (closing a real partial-write bug); a concurrent invocation against the
  same topic fails closed on an mkdir-based lock (AC12), while a STALE lock
  (issue #382) is safely stolen rather than wedging the topic forever; and
  a corrupted destination `ontology-map.json` rejects the whole subset
  import before any write (issue #376).
- Deliver: `scripts/mif-container-import.sh`, the fail-closed MIF Container
  import path — atomic per-import validation (digests, ontology bindings,
  schema), idempotent re-import, a topic-scoped stale-aware lock, and never
  a partial write on any rejection path.

### Milestone 30 — MIF Container origin tagging + reconciliation policy (Epic #275, Story #324)

- Gate: `verify.sh` `gate_m30` shows re-importing an existing @id whose
  incoming content carries a different verification verdict,
  `gathered_under`, and provenance does NOT overwrite those three
  origin-scoped fields — the destination's own values survive (AD-6) —
  while other fields (e.g. summary) do reconcile toward the incoming value
  and `tags[]` reconciles toward a union rather than a replace; importing a
  finding whose label normalizes identically to an existing different-@id
  finding's label surfaces a candidate sameAs proposal in
  `reports/concordance-sameas-proposals.json` without rewriting either @id
  or merging anything, and the detector never modifies `concordance.json`
  itself (detection-only) and fails closed on a missing concordance file;
  and a corrupt destination finding (reconciliation merge throws) rejects
  the WHOLE import, including an otherwise-independent valid new-@id
  resource in the same manifest.
- Deliver: an origin-scoped reconciliation policy for re-imported findings
  (verdict/`gathered_under`/provenance never overwritten by an incoming
  import; `tags[]` union) plus read-only candidate sameAs detection that
  surfaces possible cross-topic entity duplicates without ever
  auto-merging them.

### Milestone 31 — MIF Container export builder + /export /import commands (Epic #275, Story #328)

- Gate: `verify.sh` `gate_m31` shows a full export packages every finding in
  the topic plus its `ontology-map.json` and the topic's own deliverables
  (report, falsification report, README, goal — traveling unconditionally
  regardless of export scope, research-harness-template#437) without ever
  mutating `reports/<topic>/` (AC10); the exported manifest validates
  against the Container schema; a subset export resolves exactly the
  requested findings plus `ontology-map.json` and the topic deliverables,
  and a selector matching zero findings is still a valid export, not an
  error; export fails closed on an unregistered topic, a non-empty output
  directory, and a concurrent invocation against an already-held (or fresh)
  `.container.lock`, while a STALE lock is safely stolen (issue #382,
  including a `CONTAINER_LOCK_STALE_MIN="00"` misconfiguration falling back
  safely, and a live holder's lock being refreshed so it never ages into
  false staleness); and a full export→import round-trip into a fresh topic
  reproduces the exact same @id set, `ontology-map.json`, and topic
  deliverables (byte-identical where step 5 never rebuilds them; README's
  curated Key Findings prose specifically survives the rebuild) —
  including regression coverage that a subset import into an
  already-populated destination never shrinks its `ontology-map.json` (no
  data loss) and does upsert its own in-scope entries by `finding_id`
  without disturbing untouched ones (issue #376), and that a malformed
  finding file makes export fail closed rather than silently undercounting.
- Deliver: `scripts/mif-container-export.sh` plus the `/export` and
  `/import` commands — the export half of the MIF Container round-trip,
  sharing the stale-aware lock primitive with import, and a verified
  lossless export→import round-trip for a whole topic.

### Milestone 32 — mif-docs conformance floor (research-harness-template#413, ADR-0018)

- Gate: `verify.sh` `gate_m32` shows every fixture/template document this
  repo commits — the Diátaxis doc set, the bundled example topic's
  rendered deliverables, and `docs/proposals/` — passes `mif-docs-plugin`'s
  own `mif-validate --level 1` (schema shape + lossless round-trip), and any
  document whose frontmatter already declares a `provenance:` block
  additionally passes `--level 3` (the declared provenance is structurally
  well-formed, though this does not and cannot prove it was witnessed in a
  live session — that remains a `mif-provenance`-in-session concern this CI
  gate cannot answer). ADRs are exempt (structured-madr governs them, not
  `mif-validate`, per `mif-docs-plugin`'s own ADR-0001).
- Deliver: a structural conformance floor enforcing that this repo's own
  document-shaped deliverables stay MIF-conformant against
  `mif-docs-plugin`'s real validator rather than a self-reported claim,
  completing the substrate migration to `mif-docs-plugin` as this repo's
  document tooling (ADR-0018, research-harness-template#405).

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
