# Changelog

All notable changes to the research-harness template are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2026-07-12

Epic #416: Continuous Research-Monitoring Capability. A periodically-triggered
scan of weekly news, academic/preprint papers, and current-events signals,
scored against the harness's existing knowledge, with every candidate
recommendation gated through human PR review before anything publishes.

### Added

- **ADR-0019** settles the scheduling/trigger primitive: GitHub Actions cron,
  not a cloud Routine, with write-back via a review PR that doubles as the
  Editorial Gate (research-harness-template#417).
- **Eight Source Connectors** (`scripts/monitoring/connectors/`): arXiv,
  OpenAlex, Crossref, Semantic Scholar, PubMed, bioRxiv/medRxiv, GDELT DOC 2.0,
  Hacker News — each a free, keyless `curl`+`jq` client, no SDK, opt-in
  enhancement env vars default off (research-harness-template#418).
- **Interest-Inference Engine** (`scripts/monitoring/interest-inference.sh`)
  scores candidates against `reports/concordance.json` with a dependency-light
  TF-IDF fallback for uncovered topics; refuses to score against a stale
  concordance (research-harness-template#419).
- **Recommendation Engine** (`scripts/monitoring/recommend.sh`): interest-match
  and gap-detect modes, every recommendation carrying at least one MIF
  citation enforced in code (research-harness-template#420).
- **Continuity Log + fail-closed budget** (`scripts/monitoring/lib/continuity-log.sh`,
  `run-with-budget.sh`): every ingestion failure or budget breach is recorded,
  never silent (research-harness-template#421).
- **Editorial Gate** (`scripts/monitoring/editorial-gate.sh`): structural
  human-review checkpoint, fail-safe default (no decision = rejected), with a
  no-bypass invariant enforced before publish (research-harness-template#422).
- **Output Router** (`scripts/monitoring/output-router.sh`) hands accepted
  recommendations to the existing `publish-report`/`publish-blog` skills
  unmodified — no new output channel (research-harness-template#423).
- **`.github/workflows/monitor.yml` + `monitor-gate.yml`** implement ADR-0019
  end to end: a scheduled run opens one review PR per topic; merging or
  closing it drives accept/reject (research-harness-template#424).
- **`harness.config.json`'s per-topic `continuousMonitoring` block** (schedule,
  queryTerms, sources, budgetSeconds, maxResultsPerSource,
  recommendationThreshold), shipped disabled on the bundled example topic.
- **`evals/monitoring-pipeline.sh`** dry-run eval covering the fail-closed,
  Editorial Gate no-bypass, and full accept-to-publish paths
  (research-harness-template#425).
- **`docs/how-to/enable-continuous-monitoring.md`** operator how-to.

### Fixed

- `reports/concordance.json` had drifted stale since #229 (PR #253's
  retro-classification never triggered a rebuild) — caught by the new
  Interest-Inference freshness guard, rebuilt.
- ADR-0019 initially used this repo's `docs/adr/template.md` shape, which
  cannot be provenance-stamped or pass real `structured-madr` validation
  (missing `## Links`, invalid Audit status). Authored via the `mif-docs:adr`
  skill instead; now passes `smadr` strict mode and MIF conformance levels
  1-3 against the real Action. The same gap affects every other ADR in this
  repo (already tracked, research-harness-template#435).

## [0.13.1] - 2026-07-12

### Fixed

- Added the `[0.13.0]` footer compare-link now that the `v0.13.0` tag exists,
  per #393's convention — it could not be added in the same PR that stripped
  `0.12.3`'s heading brackets, since the tag didn't exist yet at that point.
- **`scripts/build-topic-readme.sh` trims a truncated title's trailing
  whitespace.** The `mif-rh-cli` engine's `harness topic-metadata` cuts a
  long `goal_statement` to build `TITLE` at a fixed character count with no
  word-boundary awareness (modeled-information-format/mif-rs#86); when the
  cut lands right after a space, the generated README's H1 kept the
  trailing space and failed markdownlint's MD009. The script now trims
  `TITLE` defensively after the engine `eval`, independent of when the
  upstream engine bug itself is fixed.

## [0.13.0] - 2026-07-12

Epic #405: `mif-docs-plugin` adopted as the single document-tooling and
provenance substrate for every document-shaped deliverable this harness
produces — closing the gap #228's genre-consolidation left open (schema
conformance via the harness's own vendored `ajv` closure, ADR-0002, but no
witnessed, hook-observed provenance and no wiring for `docs/` at all).

### Added

- **`mif-docs-plugin` wired as a declared, pinned dependency.** `.mcp.json`
  gains the `mif-mcp` server; `.claude/settings.json` gains a top-level
  `mifProvenance: {capture: true, stamp: "auto"}` key read directly by the
  plugin's own `provenance-config.mjs` (research-harness-template#406).
- **ADR-0018** documents `mif-docs-plugin` as the document-tooling and
  provenance substrate, and the deprecation policy every retirement in this
  Epic follows: a document type duplicating an existing `mif-docs` genre gets
  retired outright, not kept in parallel (research-harness-template#407).
- **The canonical report channel now stamps `mif-docs`-witnessed provenance**
  on every rendered `reports/<topic>/<slug>.md` — `report-synthesizer.md`'s
  new Step 4d invokes `Skill(mif-docs:mif-provenance)` after rendering
  (research-harness-template#408).
- **`verify.sh`'s new `gate_m32`** structurally enforces the mif-docs
  conformance floor on every tracked document deliverable: `mif-validate
  --level 1` on every checked file, and `--level 3` (unconditionally, no
  exemptions) on every file that declares a `provenance:` block — proving
  the block is structurally well-formed, not merely present. A fresh CI
  runner has no session ledger, so this can only ever prove structural
  well-formedness, never witnessed authorship — that remains a live-session
  question. New `scripts/fetch-mif-docs-plugin.sh` clones the plugin at its
  pinned SHA into a fail-closed, gitignored cache so CI (and any contributor)
  can run `mif-validate` without a separate sibling checkout
  (research-harness-template#413).

### Changed

- **`architecture-spec`, `feature-spec`, and `kiro-spec` bundled genre packs
  are retired**, in favor of direct `marketplace-ref` consumption of five
  `mif-docs-plugin` genres: `ai-architecture-doc`, `feature-spec`,
  `kiro-requirements`, `kiro-design`, `kiro-tasks`. The `kiro-spec` genre had
  no 1:1 successor — it is replaced by three independently selectable
  genres, each rendered by a separate invocation of the `ai-spec` channel
  (research-harness-template#409, #414).
- **`docs/` (ADRs, Diátaxis explanation/how-to/reference/tutorials, proposals)
  audited against `mif-docs` conformance.** ADRs stay exempt (structured-madr,
  not `mif-validate`, per `mif-docs-plugin`'s own ADR-0001); every other
  tracked doc confirmed or brought to MIF Level 1, with a documented
  authoring convention added to `docs/README.md`
  (research-harness-template#410).
- **`packs/market-research/*` and `packs/trend-modeling/*` audited for
  `mif-docs` duplication** — confirmed no overlap (they are findings-
  methodology skills, not rendered-document genres) and given explicit
  non-duplication disposition notes (research-harness-template#411).
- **All ten channel packs audited for provenance/citation-grounding
  compliance** against Epic #405 / ADR-0018 — confirmed no channel drops
  citation grounding between its sources and its rendered output; `diataxis`
  flagged as a candidate for a future L3/witnessed-provenance upgrade, not
  silently left unconsidered (research-harness-template#412).

### Fixed

- Two files declared `provenance:` without the separately required
  `temporal:` block (`docs/reference/dependencies.md`,
  `docs/reference/mcp-server.md`, among 22 total across `docs/` and the
  example-corpus fixtures) — real gaps `gate_m32`'s uniform, no-exemption
  L3 check caught, not waved through with a carve-out
  (research-harness-template#413).
- Post-migration deprecation sweep (research-harness-template#414): two
  fixture files declared retired genre names with no valid successor
  reference (`architecture-spec` → renamed to its 1:1 successor
  `ai-architecture-doc`; `kiro-spec` → split into the three fixture files
  matching its three genre successors, since no 1:1 successor exists); an
  orphaned worktree lock tied to a three-day-dead process was removed after
  verifying it held zero unmerged commits; four files from unrelated
  concurrent PRs were missing the same required `temporal:` block `gate_m32`
  enforces.

## 0.12.3 - 2026-07-12

### Fixed

- `gate_changelog_links` (#397) no longer runs in an instantiated clone, where
  it always failed: an instance's own git remote never carries the template's
  `v*` release tags, so the gate had no real tag history to check footer
  compare-links against. Guarded with the existing `IS_TEMPLATE` flag
  (`scripts/verify.sh:31`), the same template-only-skip pattern `gate_m7`
  already uses (#401).
- `reports/example-okf-mif-knowledge-spine/synthesis-okf-mif-knowledge-spine.md`
  (part of the shipped, AS-IS example corpus) had an invalid
  `conceptType: synthesis` (not one of `semantic`/`episodic`/`procedural`) and
  a bare `created: 2026-06-28` date instead of a `date-time` string, failing
  external MIF tooling (`mif-rs`/`mif-mcp`) schema validation on every
  instance. Changed to `conceptType: semantic` and
  `created: "2026-06-28T00:00:00Z"` (#402).

## [0.12.2] - 2026-07-11

### Added

- CI now enforces that every `CHANGELOG.md` footer compare-link resolves to a
  real git tag (`scripts/verify.sh`'s new `gate_changelog_links`,
  deliberately narrow so it never fails on the normal bumped-but-not-yet-tagged
  resting state between releases) (#397).
- `release.yml` runs `mif-rh-cli harness reconcile-changelog-links --check`
  after a release publishes and posts a warning annotation if the CHANGELOG
  needs heading-bracket/footer-link reconciliation, without gating the
  release or any other PR (#397).

### Changed

- Pinned `mif-rh-cli` engine version bumped `0.6.1` -> `0.7.0`
  (`scripts/fetch-engine.sh`, `scripts/lib/engine.sh`) to pick up
  `reconcile_changelog_links`/`harness reconcile-changelog-links`
  (research-harness-template#397, mif-rs#82).

### Fixed

- `CLAUDE.md` no longer claims markdownlint's MD052 enforces the CHANGELOG
  bracket/footer invariant — verified empirically false (0 errors on a
  bracketed heading with no matching footer link); `gate_changelog_links`
  enforces it instead.

## [0.12.1] - 2026-07-11

### Fixed

- `scripts/run-lock.sh steal` now refuses (exit 3, unless `FORCE=1`) when a
  topic's `findings/` or `research-progress.md` shows write activity within
  the guard window (`RUN_LOCK_STEAL_GUARD_MIN`, default 10 minutes), closing
  the race where a misread agent-liveness signal
  (e.g. `TaskOutput` reporting `completed` for a still-working orchestrator)
  could force a lock steal against a genuinely-alive writer (#392).
- `start.md`/`resume.md`'s "Monitoring a running session" guidance now
  explicitly warns that `TaskOutput`'s `completed` status on the
  orchestrator's own `Agent` call is not sufficient evidence a session died —
  only the disk-state signals (static finding count and no new progress-log
  entry) are authoritative (#392).
- `orchestrator.md`'s Phase 1/Phase 2 background-spawn poll loops are worded
  more forcefully, with an explicit self-check, so the model can't substitute
  a "wait for completion notification" narration for the required synchronous
  `Bash` poll loop (#392).
- `CHANGELOG.md`'s footer compare-links now only reference tags that were
  actually cut, comparing each release against the previous *real* tag
  instead of the adjacent dated section's version string; backfill-corrected
  the ~9 dated sections that were folded into a later release without ever
  getting their own tag (#393).

## [0.12.0] - 2026-07-11

### Added

- **`reports/_corpus/README.md`**: `scripts/build-topic-readme.sh` gained a
  `_corpus` mode, delegated to from `scripts/synthesize-corpus.sh`, that
  renders a navigable corpus-atlas README alongside `corpus-map.json`/
  `corpus-synthesis.md` — a topic table, verdict/entity/contradiction
  counts, and a Purpose section preserved across rebuilds (#352).

### Changed

- **`scripts/lib/engine.sh` / `scripts/fetch-engine.sh`**: bumped the pinned
  `mif-rh-cli` engine from `0.6.0` to `0.6.1`, picking up the upstream fix
  for `attempted_at` recording as epoch-0 (closes #363, #389).
- **Dependencies**: patch-bumped `astro` (`7.0.3` -> `7.0.7`), `@astrojs/starlight`
  (`0.41.1` -> `0.41.3`), `starlight-links-validator` (`0.25.1` -> `0.25.2`),
  `starlight-llms-txt` (`0.10.0` -> `0.11.0`). Astro's newer default Markdown
  processor ("Sätteri") requires `remarkPlugins`/`rehypePlugins` users to
  install `@astrojs/markdown-remark` explicitly, now added as a direct
  dependency.
- **`scripts/codegen/gen-models.sh`**: bumped the pinned dev-time
  `datamodel-code-generator` from `0.65.0` to `0.68.1` — generated
  `lib/harness_models/*.py` output is byte-identical, no regeneration diff.
- **CI**: bumped the Python runtime pin from `3.12` to `3.14` (`3.12` exited
  upstream bugfix support in 2025-04; `3.14` is in active bugfix support
  until 2027-10). `actions/setup-python` bumped `v6.2.0` -> `v6.3.0`,
  `actions/attest-build-provenance` bumped `v4.1.0` -> `v4.1.1`. Node stays
  pinned at `24` (Active LTS until 2028) — `26` doesn't reach LTS until
  2026-10-28, so it was evaluated and deliberately held back.
  `docs/reference/dependencies.md`'s runtime table is corrected to match the
  actual CI pins (it previously described `node` as floating `lts/*` and
  `python3` as declared `3.12`, neither of which matched `ci.yml`).

### Fixed

- **`.claude/commands/start.md`**: Phase 2 topic-title derivation now strips
  known goal-statement boilerplate phrasing and enforces a word-boundary-safe
  80-char truncation, and always asks the user to confirm the derived title
  (not only when truncation fired) before registering the topic (#353, #391).

### Security

- Evaluated bumping the `js-yaml` npm override (pinned to `4.2.0` to
  remediate CVE-2026-53550 / GHSA-h67p-54hq-rp68, #149) to the latest
  `5.2.1`. Reverted: `@astrojs/starlight` still does a default import of
  `js-yaml` (`import yaml from 'js-yaml'`), which `5.x` no longer exports,
  breaking `npm run build` outright. The `4.2.0` pin already remediates the
  CVE; staying on it is not a security regression.

## 0.11.2 - 2026-07-09

### Fixed

- **`harness.config.schema.json`**: added the missing `"complete"` value to
  `topics[].status`'s enum. The orchestrator's Phase 4 ("Update the topic
  status") and `/topics`' own documented `--filter` example both already
  used `"complete"`, but the schema only declared `active`/`paused`/`archived`,
  so every full research session's Phase 4 step failed `ajv validate` and
  left `harness.config.json` in an invalid state after a successful run.

## 0.11.1 - 2026-07-07

### Added

- **`docs/how-to/negative-examples-curation-workflow.md`**: the reusable,
  multi-agent confusion-driven curation workflow for scaling
  `negative_examples` curation (MIF ADR-020) across many confusion pairs at
  once (#271).
- **`ontology-manager` skill** (`0.4.3` -> `0.5.0`): a new
  `references/negative-examples-curation.md` and decision-tree entry
  codifying the corpus-regen/baseline/partition/draft steps as executable
  guidance for spinning up parallel drafting agents (#271).
- **Local `pre-push` git hook**: enforces the ADR-0010 change-driven
  versioning gate (`scripts/check-version-bump.sh`) before a push leaves
  your machine, not just in CI. Installed automatically via
  `git config core.hooksPath .githooks`, wired through `npm install`'s
  `postinstall`.

## [0.11.0] - 2026-07-07

### Added

- **`mif-rh-cli` powers 30 scripts previously implemented in bash+jq** (#276):
  ontology vendoring/cataloging/authoring (`fetch-ontology.sh`,
  `sync-packs.sh`, `check-ontology-lock.sh`, `sync-registry-ontologies.sh`,
  `author-ontology.sh`), corpus/concordance synthesis (`synthesize-corpus.sh`,
  `import-corpus.sh`, `build-concordance.sh`, `reconcile-session.sh`,
  `synthesize-artifact.sh`, `build-topic-readme.sh`), validation gates
  (`assert-graph-mif.sh`, `check-citation-integrity.sh`,
  `check-shippable-typing.sh`, `falsify.sh`, `check-relationship-targets.sh`,
  `validate-concordance.sh`, plus `verify.sh`'s two whole-registry ontology
  scans), graph/index/membership/rendering (`build-graph.sh`,
  `build-graph-viz.sh`, `build-index.sh`, `resolve-membership.sh`,
  `render-artifact.sh`), versioning/release orchestration
  (`bump-version.sh`, `goal-version.sh`, `check-version-bump.sh`,
  `mif-project.sh`), and feature toggles/packaging (`site-toggle.sh`,
  `pack-toggle.sh`, `wrap-source.sh`). Requires mif-rh-cli >= 0.5.0.

### Fixed

- **CI**: `verify.sh`'s cross-pack relationship-reference and subtype_of
  gates now surface the engine's actual error instead of a misleading
  "orphans found" verdict when the engine call itself fails.
- **CI**: the standalone `copier-update` eval and the version-bump job now
  provision the engine correctly (a fresh copier-generated instance has no
  engine of its own to resolve).
- **CI**: workflow steps that read public release artifacts now mint a
  short-lived App token instead of relying on the ambient `GITHUB_TOKEN`.

## 0.10.1 - 2026-07-06

### Added

- Documented `negative_examples` scoring and the `calibrate --confusions`
  confusion-matrix export, both shipped in mif-rh engine v0.4.0: a new
  curation-workflow section in the engine-cli reference, a new step in
  the classification-engine-loop how-to, a real explanation of the
  non-reordering demotion gate in the classification-engine explanation
  page, and the `negative_demoted`/`negatives_active` fields in the
  mcp-server reference. Bumps the pinned engine version to 0.4.0 in
  `scripts/fetch-engine.sh` and `docs/reference/dependencies.md`.
  Closes #268.

## [0.10.0] - 2026-07-06

### Added

- Registered two new domain ontologies published to the canonical registry
  since the last sync: `heliophysics` and `non-ionizing-radiation` (both
  enabled by default, per `sync-registry-ontologies.sh`'s discovery pass).

### Changed

- Re-vendored every enabled domain ontology pack against the current
  `mif-spec.dev/ontologies` registry index (a fresh `ontologies.lock.json`
  is instance-derived and gitignored in the template, so nothing else here
  is tracked).

## [0.9.0] - 2026-07-05

### Added

- **MCP server wiring** — `scripts/fetch-engine.sh` installs
  `mif-rh-mcp` beside the CLI (same attested, fail-closed download),
  a repo-root `.mcp.json` registers the stdio server for agent
  sessions, and the classification-loop runbook documents the four
  read-only tools and the `--build-index` prerequisite. The template's
  own automation adopts the tools as optional accelerators with lexical
  fallback: the search skill's `--sem` backend is now the engine index,
  dimension-analyst runs a `find_similar` prior-art check before
  emitting findings, corpus-synthesizer can lean on `corpus_stats` and
  semantic lookup during synthesis, and the orchestrator documents the
  ADR-0015 suggest/calibrate cadence after classification passes.

### Changed

- **Engine-only classification (ADR-0016)** — `resolve-ontology.sh` and
  `ontology-review.sh` are now thin wrappers over the `mif-rh` engine
  (`mif-rh-cli` v0.3.1+, hard required; byte-parity with the retired bash
  implementations is enforced fail-closed in mif-rs CI). Provisioning:
  `scripts/fetch-engine.sh` installs an attestation-verified release binary
  to `bin/`; a PATH install or an explicit `MIF_RH_CLI` override also work.
  A missing or too-old engine fails loudly with the remedy; there is no
  silent fallback.

## 0.8.4 - 2026-07-02

### Fixed

- **`render-artifact.sh` stamped an absolute filesystem path into `slug:` when
  `$OUT` was passed as an absolute path** (`report-synthesizer.md`'s own
  documented usage passes an absolute `$REPORTS_DIR`). `SLUGPATH` was derived
  from a bare `dirname "$OUT"`, so an absolute `$OUT` leaked the caller's full
  filesystem path into the rendered frontmatter's `slug:` key -- a route the
  site's cross-link rewriter cannot resolve. `$OUT` is now normalized to
  absolute and stripped of the repo root before deriving `SLUGPATH`, so
  `slug:` is always repo-root-relative regardless of how the caller passed
  `$OUT`. `REPO_ROOT` resolves `pwd` logically, not physically (`pwd -P`):
  callers build `$OUT` with plain `$(pwd)`, so a physical `REPO_ROOT` would
  diverge from that prefix on a checkout reached through a symlink, silently
  reproducing the same leak (caught in review).

## [0.8.3] - 2026-07-02

### Fixed

- **`ontology-review.sh` silently folded discovery-basis guesses into "typed", hiding
  corpus-wide ontology gaps.** `resolve-ontology.sh`'s content-pattern discovery
  fallback (for a finding with no `entity` block) records its guess with
  `basis: "discovery"` and `valid: true`, but never writes that guess back to the
  finding — nothing durable exists on disk. The review script counted any
  `valid: true` record as typed regardless of `basis`, so a topic could read as 100%
  classified while zero of its findings carried a real ontology stamp. The
  ADR-0011 fail-closed shippable-typing gate (`check-shippable-typing.sh`) and its
  `reconcile-session.sh` mirror had the same gap: both checked `basis` against only
  `untyped`/`unresolved`, so a discovery-only shippable finding could ship with no
  durable classification despite the gate's stated fail-closed contract.
- `ontology-review.sh`'s coverage table and summary line now report STAMPED
  (declared/resolved — a real `entity_type` on disk) separately from DISCOVERY
  (guessed, unpersisted); `--strict` is unchanged (still fails only on
  invalid/unresolved, not on discovery-only or untyped — those are backlog, not
  corruption).
- Added `ontology-review.sh --followup <path>`: writes a deterministic JSON backlog
  of every finding that is not durably stamped (discovery-only, untyped, or
  invalid/unresolved), grouped by topic, for tracking and retro-classification.
- `check-shippable-typing.sh` and `reconcile-session.sh` now also block/count a
  shippable finding whose ontology-map record is `basis: "discovery"`, matching
  their existing treatment of `untyped`/`unresolved`.
- Retro-classified the 15 findings in the bundled `example-okf-mif-knowledge-spine`
  topic that the discovery-basis fix above surfaced as never durably stamped.
  Each finding's `entity` block now carries a real `entity_type` chosen from its
  actual content, not the original regex discovery guess (which had put all 15
  under a W3C PROV-O provenance-record type that didn't fit). The topic now
  reads 36/36 stamped, 0 discovery-only.
- **The site's deploy base path was a hardcoded literal (`/research-harness-template`)
  in `astro.config.mjs`, contradicting that file's own stated design** ("neither the
  template nor a clone hand-edits THIS file"). Every clone actually deploys somewhere
  different (site root, a GitHub Pages project page, a custom sub-path), so a clone
  serving from `/` had every internal link 404 unless it hand-patched the supposedly
  byte-identical engine file.
- Added `harness.config.json` `.site.base` (schema + `astro.config.mjs` now reads
  `siteCfg.base ?? "/"`). Default is site root (`/`); the template's own
  `harness.config.json` sets it explicitly to `/research-harness-template` to
  preserve its real GitHub Pages deployment.
- `docs/index.mdx` (the splash page) had every internal link hardcoded with the
  template's own `/research-harness-template` prefix, a literal string independent
  of any config — the only place in the docs tree with this anomaly. Links are now
  base-relative (`/reports/`, `/tutorials/getting-started/`, ...), letting Starlight
  inject the configured base like every other internal link already does.
- `scripts/verify.sh` gate_m23's reports-landing check updated to match (asserts
  the base-relative `link: /reports/`, not the old hardcoded literal).

## 0.8.2 - 2026-07-01

> This entry collapses five version-bump commits (0.9.0, 0.10.0, 0.11.0,
> 0.11.1, 0.11.2) that landed on `main` without ever being cut as a GitHub
> Release. The actual last published release is v0.8.1; this is the next real
> release point, carrying all of that work as a single patch step.

### Fixed

- **Genre-suffixed report filenames (`<slug>.<genre>.md`) no longer 404 on the
  served site.** `astro-rehype-relative-markdown-links` slugifies each link's
  path segment with `github-slugger` — a heading-anchor algorithm that strips
  embedded `.` without inserting a separator, producing a mismatched href
  (`fooengineering` instead of `foo.engineering`) even though Astro's own
  content-collection route (which keeps the dot) resolves fine. `render-
  artifact.sh` now stamps an explicit `slug:` frontmatter field — the route the
  content collection already resolves to — which the plugin honors over its own
  computation.
- Added `scripts/backfill-report-slugs.sh`: idempotent, `--dry-run`-capable
  remediation for reports rendered before this fix, across every topic.
- The Reports table's Genre column showed `—` for every canonically-named
  `report-<genre>.md` deliverable (10 of 15 in the example corpus) because
  `render-artifact.sh` never stamped the artifact's own `genre` field into the
  rendered frontmatter, and `build-topic-readme.sh`'s filename fallback only
  recognized the dotted `<slug>.<genre>.md` convention, not `report-<genre>.md`.
  `render-artifact.sh`'s report channel now stamps `genre:` directly (schema-
  required by `artifact.schema.json`); `file_genre()` also gained a
  `report-<genre>.md` filename fallback for reports rendered before the stamp
  existed.
- **The release-pointer version gate required every PR to move
  `harness.config.json`'s `.version` relative to its own merge-base**, so two
  PRs opened against the same `main` commit collided even though neither
  author did anything wrong — whichever merged first bumped the pointer, and
  the second PR's own diff then showed it unchanged against a now-stale base.
  `scripts/check-version-bump.sh`'s release-pointer rule now compares against
  the last actual git tag release instead of a PR's own base, and only fails
  on a real regression (the pointer at or below that tag). A PR that changes
  files without touching the pointer passes as long as the pointer is already
  ahead of the last release. `[skip-version-check]` is retired along with the
  per-PR pointer obligation it used to waive. Per-pack/per-skill bump-on-change
  is unchanged. See ADR-0010's 2026-07-01 amendment.

### Changed

- The `engineering` report genre is now consumed externally from
  [`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
  (SHA-pinned via `harness.config.json` `packs[]`) instead of the bundled
  `packs/reports/engineering` pack, which is retired. This is the pilot genre
  for the genre-consolidation migration onto `mif-docs` as the single genre
  and conformance authority
  (research-harness-template#228). The genre's capability, including the
  optional Mermaid architecture-diagram figure, is unchanged; its MIF
  frontmatter authoring and conformance now go through `mif-docs`' shared
  `mif-frontmatter` / `mif-validate` substrate.
- The 17 remaining bundled report-genre packs are retired in favor of
  external consumption from `mif-docs-plugin`, completing the
  genre-consolidation migration piloted by `engineering`
  (research-harness-template#228): `academic`, `briefing`, `computing-paper`,
  `humanities-mla`, `humanities-chicago`, `clinical-submission`, `nist-sp`,
  `regulatory-disclosure`, `compliance-audit`, `security-pentest`,
  `legal-memo`, `market-research-report`, `sustainability-report`,
  `trend-analysis`, `competitive-quadrant`, `systematic-review`,
  `exec-summary`. There
  is no longer a `packs/reports/` directory — all 18 report genres now
  resolve via `harness.config.json` `packs[].source` `marketplace-ref`
  entries against the shared `mif-docs` marketplace declaration. Genre
  capability is unchanged; each genre's MIF frontmatter authoring and
  conformance now go through `mif-docs`' shared substrate.
- `scripts/check-pack-docs.py`'s external-pack resolution now tracks which
  family each external name actually resolved into, fixing a name-collision
  bug where a report genre and an unrelated ontology sharing the same name
  (`trend-analysis`) could cross-contaminate each other's outbound-link and
  README-exemption checks.

### Added

- **`harness.config.json` `marketplaces[]`** — declare an external Claude Code
  plugin source once (`name`, `url`, a pinned `ref`); any number of `packs[]`
  entries reference it via `source: {type: "marketplace-ref", marketplace:
  <name>}` instead of each repeating an identical `{type, url, ref}` object. A
  pack's own `ref` overrides the marketplace's for that pack only.
  `scripts/sync-packs.sh` and `scripts/check-pack-docs.py` resolve it; a new
  `verify.sh` gate (5d2) proves the sharing and the per-pack override.
- The `engineering` pack's source is migrated from an inline external object
  to a `mif-docs` marketplace reference, ahead of migrating the harness's
  remaining report genres onto it.
- `render-artifact.sh` now stamps a `version:` frontmatter field on every
  rendered report/blog/book, auto-incremented from the file's own prior value
  when a genre is re-rendered for the same topic (previously silently
  overwritten with no on-disk indicator of revision).
- `build-topic-readme.sh`'s Reports table gained a **Genre** column (`Type |
  Genre | Title`), extracted from the deliverable's own `genre:` frontmatter
  (falling back to a dotted-filename convention), with the `version:` field
  appended as `(vN)` when present. Previously every non-canonically-named
  deliverable fell into the generic "Document" `Type` bucket with no way to
  tell genres apart.

## [0.8.1] - 2026-06-30

### Changed

- Re-cut of 0.8.0 (the v0.8.0 tag was bound to a deleted release); no functional changes. See 0.8.0 notes below.

## [0.8.0] - 2026-06-30

### Changed

- **Domain ontology packs are now vendored on demand, not bundled** (#224,
  completing ADR-0012). The 12 domain packs under `packs/ontologies/*` are
  `git rm`'d and the directory is gitignored; only base layers under
  `schemas/ontologies/` ship committed. Clones/CI vendor the enabled packs from
  the canonical registry (`scripts/fetch-ontology.sh --all-enabled`,
  sha256-verified, pinned in `ontologies.lock.json`) before the catalog is built
  — wired into copier `_tasks` and the CI `verify` job ahead of `verify.sh`. The
  `ontologies.lock.json` pin ships committed and `check-ontology-lock.sh` proves
  no drift (#222 follow-through: lock present + gate-clean). `gate_m22` vendors
  its `software-security` subtype_of exemplar on demand. Override the registry
  source for dev/CI/offline with `$MIF_ONTOLOGY_SOURCE`.

### Added

- **README "not a chatbot deep-research" notice** — clarifies the harness is a
  falsified deep-exploration + knowledge-graph engine (adversarial falsification,
  depth, reusable accreting results), and that AI *will* make mistakes, which is
  why the schema/ontology/MIF/falsification rigor exists.

### Fixed

- `evals/copier-update.sh` now treats copier's post-apply temp-clone cleanup
  race (Python 3.14 `rmtree` "Directory not empty" on `copier._main.new_copy*`)
  as success — the render already landed; the script's assertions verify it — and
  still retries the pre-apply local-clone hardlink race.

## 0.7.1 - 2026-06-30

### Added

- **Ship the cross-topic concordance** `reports/concordance.json` (#218). The
  ontological spine is now rebuilt over the shipped example corpus
  (`scripts/build-concordance.sh`: 36 nodes / 46 edges) and committed, reflecting the
  domain-pack entity types the corpus resolves to (`trend`, `segment`,
  `sizing-estimate`, `value-proposition`, `market-intelligence-report`,
  `critical-uncertainty`, `emerging-issue`, `data-provenance`, …). `verify.sh`'s
  template corpus-shape gate (8c) now allows this deterministic, allowlisted artifact
  alongside `_meta/` and the archived example topic.

### Removed

- **Retired the seed-time `schemas/mif/VENDOR.lock` provenance file** (#223). It is
  moot under on-demand vendoring (ADR-0012, #221): the registry-pinned
  `ontologies.lock.json` + `scripts/check-ontology-lock.sh` now carry vendored-pack
  provenance, and the MIF contract is first-class and editable in-repo. `gate_m12`
  drops its verbatim-set assertion (subsection 12d); it still validates the contract
  and every registry ontology, asserts `id@version` uniqueness, and exercises the
  resolver/pack-enable matrix. Docs reconciled (ADR-0002 audit, ontology-conformance,
  contracts reference, COMPLETION-CRITERIA, `ontology-manager` skill).

## 0.7.0 - 2026-06-30

### Added

- **On-demand ontology vendoring** (ADR-0012). Domain ontologies are fetched from
  the canonical registry (the `ontologies` repo → `mif-spec.dev/ontologies/`) and
  verified fail-closed against a pinned `sha256` index, instead of every clone
  bundling every ontology. New `scripts/fetch-ontology.sh` (resolve the `extends`
  closure, fetch, sha256-verify, materialize `packs/ontologies/<id>/`, pin
  `ontologies.lock.json`); `scripts/check-ontology-lock.sh` (drift gate — a
  vendored copy must match its pinned hash, so fixes go upstream, not in place);
  and `scripts/author-ontology.sh` (when no ontology covers a domain, scaffold one
  from the topic's observed entity types and concierge a draft PR upstream). Base
  layers stay committed. Covered by `evals/ontology-vendoring.sh`. Flipping the
  bundled domain packs to a gitignored on-demand cache (with corpus re-enrichment)
  is a staged follow-up once the registry is served.

## 0.6.1 - 2026-06-30

### Fixed

- **Project hooks skip cleanly when their script is absent.** Each `.claude/settings.json`
  PreToolUse, PostToolUse, and Stop hook command now guards on the script's presence
  (`[ -f "$CLAUDE_PROJECT_DIR/.claude/hooks/…" ] || exit 0`) before invoking it, so a
  partial checkout or any context without the harness hook scripts no-ops the hook
  instead of failing the tool call.

## 0.6.0 - 2026-06-29

### Added

- **`ai-spec` channel + spec-genre packs.** A new `ai-spec` channel pack renders a
  topic's surviving findings into an AI-ready, agent-executable architecture spec — a
  genre-shaping of the `artifact.json` → Markdown pipeline (`finding_refs[]` → grounded
  evidence sections, the goal's `completion_condition.checks[]` → EARS acceptance
  criteria, `artifact.sections[]` → structure). It pairs with a new `packs/genres/`
  family carrying one pack per spec genre: `architecture-spec` (arc42/C4 §1–§12 +
  EARS), `kiro-spec` (requirements → design → tasks), and `feature-spec` (Spec Kit
  single capability). All optional and toggle-ready (`enabled:false`), registered in
  `harness.config.json` and the marketplace.
- **Cognitive-triad explanation** (`docs/explanation/cognitive-triad.md`). Codifies why
  an entity type's `base` is the closed set `_semantic`/`_procedural`/`_episodic`
  (Tulving's memory systems, cited as MIF `Citation` objects), the base-vs-namespace
  distinction, and why a derivation method such as "analytical" is never a base — its
  outputs (`forecast`/`scenario`/`adoption-curve`) are `_semantic`.
- **Worked specimens.** One worked example per genre in the bundled
  `example-okf-mif-knowledge-spine` topic (`*-build-spec.md`), each a MIF Level-1
  deliverable grounded in surviving findings with EARS criteria drawn from the goal checks.

### Changed

- **Five domain ontology packs conformed to the build-spec.** `software-security`,
  `regulatory-legal`, `scientific`, `market-research`, and `trend-analysis` now carry
  prior-art grounding (`source_vocab`/`source_class`/`prior_art`/`disposition`) on every
  entity type and provenance traits resolved from `shared-traits` (seven generic
  provenance traits promoted there). All shipped types preserved; `regulatory-legal`
  gains the missing `compliance-regulation`; `analytical`-rooted types conformed to
  `_semantic`. Packs validate and resolve fail-closed through the catalog.
- The output-conformance hook exempts `*-build-spec.md` (the `ai-spec` channel's
  Level-1 agent-consumable spec) from the Level-3 write-time check.

### Fixed

- `build-topic-readme.sh`: list `*-build-spec.md` deliverables in the topic README
  Reports table (only `*-delta.md` build logs stay excluded), and force `LC_ALL=C`
  on the Reports-table sort so the generated README is byte-identical across build
  hosts (a locale-sensitive `sort -k2` made the README-freshness gate flap between
  macOS and the Linux CI runner).

## [0.5.0] - 2026-06-29

### Added

- **Fail-closed ontology-completeness gate + auto-reconciled spine** (Epic 1). The
  research loop now reconciles the cross-topic concordance as a first-class
  pre-synthesis stage. `scripts/check-shippable-typing.sh` blocks synthesis until
  every shippable (`survived`/`weakened`) finding resolves to a valid ontology type,
  and the orchestrator builds + validates `reports/concordance.json` before spawning
  the report-synthesizer. Falsified, quarantined, and inconclusive findings never
  block; `/ontology-review --enrich` then `/resume` is the unblock path. New
  ADR-0011 records the decision and `gate_m24` enforces it.
- **Ontology-aware synthesis** (Epic 2). `scripts/synthesize-artifact.sh` joins each
  report section to its finding's resolved type (`entityType`/`ontology`/`basis`)
  from `ontology-map.json`, and the `report` channel renders the resolved type in
  its provenance line. The no-map path stays byte-identical, so existing renders are
  unaffected.
- **Cross-topic corpus atlas** (Epic 2). New `scripts/synthesize-corpus.sh`,
  `corpus-synthesizer` agent, and `/synthesize-corpus` command project the spine
  (`reports/concordance.json`) into `reports/_corpus/corpus-synthesis.md` — the whole
  research record across every topic, **including what was falsified or weakened**
  (which the survivors-only report-synthesizer omits). `gate_m25` covers it.
- **Concordance scale-query verbs** in the `graph` skill: `--reuse`,
  `--contradictions`, and `--disproven` over `reports/concordance.json` (graph skill
  bumped to `0.5.0`).
- **Org governance reference** (`docs/reference/org-governance.md`) cross-linking the
  org release, branch-protection, Dependabot auto-merge, and labels runbooks plus the
  reusable-workflow CI architecture, reachable from `SECURITY.md` and `README.md`.

### Fixed

- `copier update` now re-runs `sync-packs.sh` (added to copier `_tasks`), so the
  derived ontology catalog (`.claude/enabled-packs.json`) never goes stale after an
  update — a stale catalog missing an `extends` target would otherwise make the
  fail-closed resolver mark the whole bound corpus invalid.
- `evals/copier-update.sh` now surfaces copier's stderr instead of swallowing it and
  retries the transient local-clone hardlink race, so a genuine failure is
  diagnosable rather than an undiagnosable "flake."

## [0.4.3] - 2026-06-29

### Added

- A MIF-branded **social-preview card** (`.github/social-preview.svg` / `.png`)
  and a README hero banner. The card frames the harness as a MIF-native engine
  across three pillars — MIF substrate, ontological spine, and a living knowledge
  graph that grows each session — the last shown as a typed cyan spine accreting
  amber findings.
- `scripts/bump-version.sh` — a change-driven version-bump tool. It moves the
  template release pointer (`harness.config.json`), the marketplace catalog
  (`.metadata.version`), and inserts the CHANGELOG section, and bumps a pack's
  stamps (`plugin.json`, its `SKILL.md`, and its family-doc row) only when that
  pack is named with `--pack`. It self-verifies and supports `--check` (dry run).
- A **version-consistency gate** in `scripts/verify.sh`: the marketplace catalog
  version equals the template version, and every skill/plugin stamp is well-formed
  semver. It does not force uniformity (independent versions stay legal), replacing
  the previously-claimed (but unenforced) lockstep gate.
- A **bump-on-change CI gate** (`scripts/check-version-bump.sh`, wired as the
  PR-only `version-bump` job): a changed pack or core skill must move its own
  version, and any change must move the `harness.config.json` release pointer, or
  CI fails naming the un-bumped component. `[skip-version-check]` on its own line
  in a commit waives the pointer rule for a change that warrants no release.

### Changed

- **Versioning is now change-driven, not lockstep** (ADR-0010). A pack or skill
  version bumps only when its own files change; `harness.config.json` is the sole
  always-bumps release pointer. A release that touches no pack now changes three
  files instead of ~80, removing the per-release stamp churn and the corruption
  risk it carried. `CLAUDE.md` is updated to document the new model and tool.

## [0.4.2] - 2026-06-28

### Added

- The bundled **archived example research corpus** (`reports/example-okf-mif-knowledge-spine`)
  ships to every clone as its inherited seed fixture — keeping the same name in the template
  and in clones — so a fresh clone shows the engine's worked output immediately. The
  `copier-update` eval asserts it ships archived on copy and survives `copier update` without
  duplication or conflict. (It is served straight out of `reports/`; the prior `example-`-prefix
  rename was dropped — renaming the corpus directory inside copier's update render destabilized
  copier's temp-dir cleanup.)

### Changed

- The bundled example is now a single **archived** research topic served straight out of
  `reports/` — `example-okf-mif-knowledge-spine`, a worked OKF + MIF knowledge-spine corpus
  (36 findings, knowledge graph, falsification report, and a full set of genre reports:
  exec-summary, briefing, market-research-report, market-sizing, competitive-analysis,
  competitive-quadrant, trend-analysis, trend-modeling, academic, engineering, and
  computing-paper). The distribution gate (`verify.sh` 8c) now permits this one served
  example under `reports/` alongside `reports/_meta/`.
- **The site now serves the full topic deliverable tree** — the README (as the topic
  index at `/reports/<topic>/`), the neutral synthesis, the falsification report, the
  research-progress log, and every genre report all render, instead of being excluded
  (these are critical consumer-facing deliverables). `src/content.config.ts` wraps `glob()`
  to DERIVE the Starlight `title` from each file's body `# H1` (so the generated artifacts
  are never mutated and clones get the same behaviour) and re-slugs the README to the topic
  index; a `remarkStripReportH1` plugin drops the duplicate body heading at render. The
  reports **sidebar lists one link per topic** (its README index), not a per-report tree, and
  a `Sidebar` component override adds a client-side **topic filter**. ADR-0009 is amended to
  record this (superseding its README/falsification exclusions).
- The **readme channel** is upgraded toward the `zircote/research` per-topic exemplars:
  a falsification audit-trail line in the header, dimensions rendered with their
  descriptions, a richer Artifacts table (type + size), backtick-quoted tags, an optional
  hero image, and a **Reports table listing the topic's constituents as Type → Title** in a
  deterministic reader-consumption order (executive summary → briefing → synthesis → genre
  reports → falsification report → research progress).
- Site sidebar groups collapse by default so a large corpus stays navigable.

### Removed

- The legacy `example-topic` placeholder and the `topic_id` / `topic_title` copier
  prompts. The inherited archived seed is the clone's starting topic; run `/start` to
  research new topics.

### Fixed

- The rendered site now builds and navigates the full instance corpus, not just
  the example. `harness-instance.md.jinja` ships Starlight frontmatter (it was
  frontmatter-less and aborted `astro build`/`dev` in every clone); Copier
  re-establishes the `docs/reports` and `src/content/docs` symlinks it flattens
  on render, and `gate_m23` now asserts both; and the content glob excludes
  audit/continuity artifacts (`*-falsification-report.md`, `*-delta.md`,
  `*-build-spec.md`) that carry no Starlight frontmatter. (#164, #165)
- `scripts/render-artifact.sh` derived the report intro's "covers N surviving finding(s)"
  from the section count, which undercounts once a genre reshapes sections; it now counts
  `finding_refs` (the true surviving-finding total), accurate for every genre.
- Findings now carry a top-level `namespace` field. The example corpus's 36 findings
  omitted it (it lived only inside the `@id` URN), so `build-index.sh` projected
  `namespace: null` for every finding and namespace-scoped `/search` + the `/topics`
  rollup silently broke (and report synthesis fell back to a `harness/report` namespace).
  The corpus is backfilled, the `dimension-analyst` now emits the field, and a new
  fail-closed gate (`verify.sh` 8e) requires every finding under `reports/**/findings`
  to carry a non-empty top-level `namespace` so the omission can never ship silently.
  The `topics` and `discover` skill evals are realigned to the new manifest (sole
  archived example topic; four research dimensions).

## [0.4.1] - 2026-06-28

### Added

- The Reports surface now has a stable `/reports/` index page
  (`src/pages/reports.astro`) that lists this harness's report topics from the docs
  collection: empty-safe before the first report, the example topic in the template,
  a clone's own reports in an instance. The splash landing gains a "Read the reports"
  hero action and a Reports card, and the Reports sidebar group gains an "Overview"
  link, all pointing at it.
- Auto-redeploy: `docs.yml` fires the `source-updated` `repository_dispatch` the org
  Pages `deploy.yml` listens for after a green build on a push to `main`
  (authenticating as the org GitHub App, scoped to the org Pages repo), so a merge
  republishes the live site automatically. Previously the live site only updated on a
  manual deploy dispatch. `gate_m23` gains 23e (landing surfaced) and 23f (dispatch
  wired; template-only).

## [0.4.0] - 2026-06-28

### Added

- The Astro/Starlight site now renders `reports/` as a first-class surface for
  human reading: each `reports/<topic>/<slug>.md` becomes a page in a **Reports**
  sidebar group (mermaid + relative links resolved), covered by `llms.txt`. The
  template hosts a rendered **example-topic** report so the docs site demonstrates
  the reports surface; a clone is activated reports-primary at instantiation.
- `harness.config.json` gains an optional `site` block (validated by the schema):
  `primarySurface` (`reports|docs|auto`) and `plugins` gates for `llmsTxt`,
  `mermaid`, `imageZoom`, `linksValidator`. `astro.config.mjs` reads it at build
  time, so neither the template nor a clone hand-edits `astro.config.mjs`.
- `scripts/site-toggle.sh` — flip the site surface or an optional plugin from the
  manifest. Two optional Starlight plugins are bundled (default off):
  `starlight-image-zoom` and `starlight-links-validator`.
- `/configure` command + `harness-configurator` agent — a configuration concierge
  that toggles packs and site features, manages ontologies and topics, and re-runs
  the gates.
- Copier post-copy `_tasks` hook (with `_message_after_copy`) activates a clone's
  reports surface on `copier copy --trust`; the bundled example report is excluded
  from clones so `copier update` stays conflict-free.
- `gate_m23` (site projection) and the `site-toggle` eval.

### Changed

- Upgraded the docs site to **Astro 7 / Starlight 0.41** (from Astro 6 / Starlight
  0.40), mirroring the sibling MIF repo. `astro-rehype-relative-markdown-links` is
  retained via a `package.json` `overrides` peer relaxation (it still resolves the
  docs' relative `.md` links on Astro 7); the `gray-matter` patch is retained (the
  relative-links plugin reads link targets through `gray-matter`, which calls the
  `safeLoad` removed in js-yaml 4). The Astro-6-pinned `esbuild` override is dropped.

### Fixed

- `scripts/update.sh` now handles cross-platform reproducibility misses
  (macOS/BSD vs Linux `git archive | gzip -n` bytes) with a sanctioned fail-closed
  fallback: verify the downloaded release asset's attestation, then require
  extracted-content equality with the pinned commit SHA before applying
  `copier update --vcs-ref <sha>` (issue #151).

## [0.3.0] - 2026-06-26

### Added

- MIT `LICENSE` at the repo root (the template is now explicitly MIT-licensed).

### Security

- Remediated GHSA-h67p-54hq-rp68 / CVE-2026-53550 (quadratic-complexity DoS in
  `js-yaml` YAML merge-key handling). `js-yaml` is forced to `>= 4.2.0` via an npm
  `overrides` entry, and `gray-matter` — which hard-pins the unmaintained 3.x line
  and pulled it transitively into the docs build — is patched with `patch-package`
  (`yaml.safeLoad`/`safeDump` → `yaml.load`/`dump`, a faithful rename since those
  are 4.x's safe variants). No upstream fix exists, so the committed lockfile is
  pinned forward to keep instantiated harnesses clean.

## [0.2.0] - 2026-06-25

### Added

- Fail-closed provenance gate before `copier update` (issue #94). `scripts/update.sh`
  is the only supported update path: it resolves the target release tag, pins it to a
  commit SHA, reproduces the release artifact, and verifies its SLSA build-provenance
  attestation with the same primitive as `release.yml`/CI/`SECURITY.md`
  (`gh attestation verify --repo … --signer-workflow …/release.yml`). Any miss exits
  non-zero and never invokes Copier; on success it runs `copier update --vcs-ref
  <verified-sha>` (TOCTOU-closed). The trust root is the signer-workflow identity baked
  into the wrapper, established once at clone and verify-before-apply protected.
  `evals/update-provenance.sh` (run in CI via `run-evals.sh`) asserts the gate fails
  closed; docs: a how-to ("update your harness safely") and an explanation
  ("update-channel provenance model").
- A layered ontology spine. New MIF-compliant intermediate layer
  `engineering-base` (`schemas/ontologies/engineering-base/0.1.0.yaml`, cataloged
  `core=false`) declares the engineering supertypes shared across domains —
  `component`, `architectural-decision`, `design-pattern`, `delivery-metric`,
  `engineering-practice`, `process-discipline` — plus `depends_on`/`implements`.
  The engineering domain packs `extends: engineering-base`, so resolution is
  transitive: binding a domain pack resolves the supertypes its ancestor layers
  declare. The layer is present-but-not-core, so non-engineering topics never
  resolve these types — keeping the upstream-submittable generic core
  domain-neutral. `gate_m21` proves the positive (descendant resolves an
  ancestor-layer type) and the negative (a non-engineering topic does not).
- Cross-cutting universals in `engineering-base` — `control`, `artifact`,
  `policy`, `provenance` — with edges `governs` (control/policy →
  component/artifact), `attests` (provenance → artifact), and `derived_from`
  (artifact lineage). `data-engineering` adds `governed_by` (data-product/storage
  → control/policy), realizing the data/security governance cross-cut.
- Entity-type subsumption: a new first-class `subtype_of` field on entity types
  (declared in `ontology.schema.json`). A subtype is substitutable for its
  supertype at a relationship endpoint, enforced by `validate-concordance.sh` and
  `gate_m22`. `software-security.security-control` is `subtype_of: [control]`, so it
  satisfies the cross-cutting `governs` edge; a non-subtype is rejected.
- A root `CLAUDE.md` orienting Claude Code to the harness (gates, contracts, the
  goal-driven engine, pack control plane, and the conventions that bite). It is
  template-managed and re-applied on update; the new
  `docs/how-to/instantiate-the-harness.md` section recommends instance owners put
  their own clone-specific guidance in a `CLAUDE.local.md` (loaded automatically,
  never touched by `copier update`).

### Changed

- `resolve-ontology.sh` and `validate-concordance.sh` now walk the `extends`
  chain when building a topic's allowed ontology set (fail-closed if an
  `extends` target is not cataloged). `sync-packs.sh` catalogs non-core layers
  under `schemas/ontologies/` as `core=false` (only `mif-base`, `mif-generic`,
  `shared-traits` are core).
- Renamed the `security` ontology pack to `software-security` (extends
  `engineering-base`); moved the SDLC-facing `security-threat`,
  `security-framework`, and `security-incident` supertypes into it from
  `software-engineering`, where the finer STIX/ATT&CK/CWE types refine them.
  Renamed its `control` type to `security-control` (the security specialization of
  the new generic `engineering-base` `control`).
- Deduplicated the engineering domain packs: `software-engineering` (0.5.0) now
  carries only SDLC-operational types (`incident-report`, `runbook`,
  `deployment-procedure`, `migration-guide`); `data-engineering` (0.2.0) carries
  only data-specific types. Both inherit the shared supertypes and the generic
  `technology` (which is a MIF built-in in `mif-generic`) instead of copying them.
- Nothing is vendor-locked. `VENDOR.lock` no longer marks any file `verbatim:true`
  (the MIF contract `ontology.schema.json` + context are unlocked); `gate_m12` now
  asserts the verbatim set is empty. `VENDOR.lock` is retained for provenance
  (source/commit + seed checksums). The contract is first-class and evolves in-repo
  on its way back to MIF — conformance stays fail-closed by validation, not by
  freezing files.
- The graph visualization is now a real interactive force-directed node-link
  diagram (issue #91). `build-graph-viz.sh` replaces the two `<ul>` lists with a
  deterministic SVG layout (seeded circle + fixed-iteration Fruchterman-Reingold,
  no RNG), concept/entity nodes colored and sized by degree, typed edges
  (`supports`/`contradicts`/`derived-from`/`mentions`) with distinct color, dash,
  and arrowheads, edge-type labels, hover tooltips, a legend, and draggable nodes
  — still self-contained vanilla SVG + JS (no CDN, no network). The embedded graph
  JSON escapes `</` so a label containing `</script>` cannot break out of the tag.
- Ephemeral viz HTML no longer dirties the working tree (issue #91).
  `build-graph-viz.sh` defaults its output to a `mktemp` path **outside** the
  project tree (an explicit second argument still writes in-repo); the `verify.sh`
  M-graph gate renders its probe into a temp dir and removes it. Only tracked data
  artifacts (findings, `knowledge-graph.json`, `concordance.json`, maps) belong in
  `reports/` — documented in `docs/reference/scripts.md`.

### Removed

- `compliance-regulation` (modeled in `regulatory-legal` as `legal-act`/
  `obligation`) and the deprecated `adoption-trend` (superseded by
  `trend-analysis`'s `trend`) are dropped from the engineering packs. Pre-stable
  clean break — no back-compat aliases.

## [0.1.2] - 2026-06-24

### Added

- `SECURITY.md` with a "Verifying Release Artifacts" section documenting the
  strict `gh attestation verify` command (pinned to the release workflow via
  `--signer-workflow`) and how to report vulnerabilities.

### Changed

- The release workflow re-verifies the SLSA build-provenance attestation
  before publishing (fail-closed) and pins trust to the release workflow with
  `--signer-workflow`, so a tag never publishes an unverified artifact and an
  attestation from any other workflow in the repository is rejected.

## [0.1.1] - 2026-06-23

First release of the domain-general research harness template.

### Added

- **Four-layer architecture** in one repository — engine (`.claude/agents` and
  `.claude/commands`), contracts (`schemas/`), harness services (topic registry,
  knowledge graph, search, discovery), and outputs (`reports/`, channels, packs)
  — all shipping on clone. See
  [ADR 0001](docs/adr/0001-four-layer-single-repository-architecture.md).
- **MIF Level-3 I/O conformance**: findings are individual MIF memory units
  validated against the vendored `schemas/mif/` closure.
- **Goal-driven sessions**: a content-hashed, append-only goal
  (`schemas/goal.schema.json`) initiates, steers, and gates each run.
- **Config-declared dimensions** read from `harness.config.json` (`technical`,
  `landscape`, `trajectory`) — not a fixed taxonomy.
- **Single adversarial falsification gate** assigning ordinal verdicts
  (`falsified` / `weakened` / `survived` / `inconclusive`) with one-round
  remediation.
- **Packs and plugins**: one plugin per skill, toggled via the
  `harness.config.json` `packs[]` control plane and the
  `.claude-plugin/marketplace.json` marketplace. Channel packs (book, Diátaxis,
  PDF, NotebookLM, GitHub Discussions, GitHub Issues), report genres,
  methodologies, and ontologies.
- **Output channels**: blog (first-class, always on) and the canonical MIF
  Level-3 report channel as the source of truth.
- **Diátaxis documentation set** under `docs/` (tutorials, how-to, reference,
  explanation) plus Architectural Decision Records under `docs/adr/`.
- **Attested delivery**: SHA-pinned GitHub Actions enforced by a `pin-check`
  CI gate, and a release workflow that attests a reproducible source tarball
  with SLSA build provenance via `actions/attest-build-provenance`.
- **Distribution** as a Copier living template and a Claude Code plugin
  marketplace.

[Unreleased]: https://github.com/modeled-information-format/research-harness-template/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.2...v0.13.0
[0.12.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.1...v0.12.2
[0.12.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.1...v0.8.3
[0.8.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.5.0...v0.8.0
[0.5.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/modeled-information-format/research-harness-template/releases/tag/v0.1.1

<!--
Dated sections above with no bracketed heading (0.6.0, 0.6.1, 0.7.0, 0.7.1,
0.8.2, 0.8.4, 0.10.1, 0.11.1, 0.11.2, 0.12.3) moved the `harness.config.json` version
pointer per ADR-0010's change-driven model but were folded into a later
release before a GitHub Release/tag was ever published for them, so they omit
a footer compare-link — nothing real exists to compare against. Convention
(#393): a footer compare-link is only emitted once a real Release/tag exists
for a dated section, and it compares against the previous *actual* tag, not
the adjacent dated section's version string. If a future dated section's
version pointer gets folded into a later release without its own tag, strip
its brackets and omit its footer link the same way when that becomes known.
-->
