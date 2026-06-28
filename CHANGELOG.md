# Changelog

All notable changes to the research-harness template are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/seed-example-topic.sh` — a copier post-copy `_task` that renames the shipped
  example topic to `okf-mif-knowledge-spine` (strips the `example-` prefix across the
  directory name, every finding/report `@id` namespace, the manifest, and goal check
  paths) so each clone starts with it as a seed fixture. Idempotent and self-cleaning
  (it discards the prefixed copy copier re-ships on update and is a no-op in the template
  itself), which keeps `copier update` conflict-free. The `copier-update` eval now asserts
  the seed renames + archives on copy and survives update without duplication.

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

[Unreleased]: https://github.com/modeled-information-format/research-harness-template/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/modeled-information-format/research-harness-template/releases/tag/v0.1.2
[0.1.1]: https://github.com/modeled-information-format/research-harness-template/releases/tag/v0.1.1
