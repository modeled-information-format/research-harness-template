---
id: reference-scripts
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-24T14:44:50.128Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: scripts"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-24T10:25:46-04:00'
  ttl: P6M
  recordedAt: '2026-06-24T10:25:46-04:00'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ee7af76f-5362-4cb2-a83d-8b11eae113dc
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.218
---

# Reference: scripts

All scripts shipped with the template core (shell, plus one Python codegen
helper and one `jq` filter). Most are invoked by agents, commands, and skills,
but several are run directly by adopters — for example `pack-toggle.sh` to
enable a pack and `verify.sh` as the conformance gate. `jq` is a near-universal
dependency; see [dependencies](../dependencies/) for installation.

**Artifact placement.** Scripts must write non-committed (ephemeral or derived)
artifacts to a `mktemp` path **outside** the project tree — never next to their
input inside the repo, where they dirty the working tree and block `copier
update`. Only **tracked data artifacts** — findings, the knowledge graph
(`knowledge-graph.json`), the concordance (`concordance.json`), and maps —
belong in `reports/`. The HTML graph viz is ephemeral: `build-graph-viz.sh`
defaults to `mktemp` and only writes into `reports/` when an explicit output
path is passed.

**Exception:** the dimension-analyst's finding-publish staging directory
(`.claude/agents/dimension-analyst.md` Step 5, issue #357) and
`scripts/write-finding.sh`'s own staging directory (issue #360) are both
created via `mktemp -d` **inside** the findings directory they publish into,
not outside the tree. Both use `ln` (a hard link) for the final publish,
which requires the staging file and its destination to share a filesystem —
a `/tmp` mktemp risks crossing filesystems (`EXDEV`) and defeating the whole
mechanism. The directories are gitignored (`.staging-*/`, `.wf-staging-*/`)
so neither dirties the tree or blocks `copier update`.

---

## Graph and index

Scripts that build or maintain the knowledge graph, research index, and
cross-topic concordance.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/build-graph.sh` | Builds the MIF-native knowledge graph from findings. Nodes: one concept per finding plus one entity per `EntityReference`. Edges: typed relationships and mention links. | `jq` |
| `scripts/assert-graph-mif.sh` | Acceptance gate: asserts all node and edge IDs are `urn:mif:` URNs and that at least one typed relationship edge exists. | `mif-rh-cli` (engine) |
| `scripts/build-graph-viz.sh` | Renders the knowledge graph as a standalone, dependency-free HTML file. | `jq` |
| `scripts/build-concordance.sh` | Builds the cross-topic ontological spine (`reports/concordance.json`) by merging all topics' findings. Deterministic and idempotent. | `jq` |
| `scripts/validate-concordance.sh` | Fail-closed ontology conformance check for the concordance: asserts every node `entityType` and relationship type is declared by the bound ontology and that `from`/`to` domains are consistent. | `mif-rh-cli` (engine) |
| `scripts/build-index.sh` | Incremental maintenance of `research-index.json` — a flat projection of all MIF findings. Also projects goal-version membership (SPEC §11). | `jq` |

---

## Engine

Scripts that install and locate the `mif-rh` compiled ontology engine
(ADR-0016). See [dependencies](../dependencies/) for the `mif-rh-cli` version
floor, [../engine-cli/](../engine-cli/) for its subcommand surface, and
[../mcp-server/](../mcp-server/) for the MCP server the same install ships.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/fetch-engine.sh` | Downloads the pinned `mif-rh-cli` and `mif-rh-mcp` release binaries for the current platform from the `mif-rs` repository, verifies each one's build provenance with `gh attestation verify` (fail-closed), and installs both to `bin/`. | `gh` |
| `scripts/lib/engine.sh` | Sourced library, not a standalone script. Provides `engine_bin()`: resolves the `mif-rh-cli` binary (`$MIF_RH_CLI` override, then `PATH`, then `bin/mif-rh-cli`), checks its reported version against the pinned floor, and fails loudly naming `fetch-engine.sh` as the fix. Sourced by `resolve-ontology.sh` and `ontology-review.sh`. | `grep`, `head`, `awk` |
| `scripts/fetch-mif-docs-plugin.sh` | Clones `mif-docs-plugin` at the SHA pinned in `harness.config.json` `marketplaces[]` (ADR-0018) into `.mif-docs-plugin-cache/` (gitignored — an intentional vendored-tool cache exception to the "ephemeral artifacts go to `mktemp`" convention above, same category as `bin/`: a fetched dependency, not derived research output), fails closed if the checked-out HEAD doesn't match the pin exactly, `npm ci`s its dependencies, and hydrates its MIF schema cache. Completion is recorded in a `.provisioned-ref` sentinel written only after install + hydration both succeed (#677): cache reuse requires the checked-out ref AND the sentinel to agree, so a run that checked out the pin but died before/during `npm ci` re-runs install/hydration on the next invocation instead of reporting a false cache hit. Destination honors `--dest` if given, else `$MIF_DOCS_PLUGIN_ROOT` (same variable `gate_m32` reads), else the default path. Required before `verify.sh`'s `gate_m32` (research-harness-template#413) can run `mif-validate`. | `git`, `npm`, `jq` |

---

## Findings and session

Scripts that create, validate, falsify, and checkpoint findings, and that
manage the session run lock.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/write-finding.sh` | Stage-validate-rename atomic write: a finding is visible on disk only after it passes schema validation (crash-safe). | `ajv` |
| `scripts/wrap-source.sh` | Normalises a raw source to a MIF source-envelope at the ingestion boundary, validates at L3 before an analyst consumes it. | `jq`, `ajv` |
| `scripts/falsify.sh` | Deterministic falsification substrate: writes an ordinal verdict into `extensions.harness.verification`, logs one `falsification-gate: run` line per invocation, enforces the one-round rule. | `mif-rh-cli` (engine) |
| `scripts/reconcile-session.sh` | Derives a durable session checkpoint (`state.json`) from disk. A finding is DONE iff it validates against the full schema (which requires a `verification` block) **and** its verdict is not `falsified` — a falsified-but-valid finding is intentionally not done. Idempotent and byte-deterministic. | `jq`, `ajv` |
| `scripts/run-lock.sh` | Topic-level mutual-exclusion lock (directory-based atomic test-and-set). Prevents concurrent writers on the same topic. Staleness window: `RUN_LOCK_STALE_MIN` (default 240 min). Operations: `acquire`, `release`, `refresh`, `steal`. `acquire`/`steal` stamp a unique per-acquisition ownership token in `$LOCK/.owner-token` and print it on stdout; `refresh` requires that token and refuses (without touching the lock) if it no longer matches, and `release`'s token argument is optional but skips removal on a mismatch — so a caller (run as a separate process from `acquire`) can never extend or delete a different run's lock at the same path after a steal/staleness race (research-harness-template#798, same defect class `scripts/lib/container-lock.sh`'s `container_lock_refresh` fixed for #763). | coreutils (`find`, `touch`, `mkdir`, `rm`, `cat`) |
| `scripts/goal-version.sh` | Computes a content-hash goal version ID (`gv-<sha256[:12]>`) by normalising the goal JSON (removing lineage fields, sorting keys). | `jq`, `sha256sum` / `shasum` / `openssl` |
| `scripts/resolve-membership.sh` | Deterministic scope-resolution for a goal version: emits `reports/<topic>/goals/goal-<version>.members.json` with `members[]`, `stale[]`, and `gap_dimensions[]`. | `jq` |
| `scripts/check-citation-integrity.sh` | Citation-integrity gate: asserts at least one citation per finding; each citation traceable (well-formed `http(s)` URL *format* or an `internal:` source with a `note`) and carrying a `citationRole`; no `falsified` finding ships; and no citation URL is pre-marked dead via `extensions.harness.citationStatus.deadUrls[]`. It validates URL format and the marked-dead list — it does **not** probe URL liveness. | `mif-rh-cli` (engine) |
| `scripts/build-topic-readme.sh` | Builds and validates the per-topic navigation README. Computes deterministic backbone (counts, dates, tables); preserves synthesis-grade Key Findings across rebuilds. `<topic>` = `_corpus` builds `reports/_corpus/README.md` instead, from `corpus-map.json` (research-harness-template#352) — no goal/findings of its own, so it skips the mif-rh-cli topic-metadata rollup entirely (the only path here that's `jq`-only; every other topic still hard-requires the engine). | `jq`, `mif-rh-cli` (engine) |
| `scripts/import-corpus.sh` | Imports an existing MIF corpus into an instantiated harness: validates each unit, registers the topic, rebuilds the index and graph. | `jq`, `ajv` |

---

## Packs and ontology

Scripts that manage capability packs, ontology resolution, and artifact synthesis.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/sync-packs.sh` | Materialises `harness.config.json` `packs[]` into `.claude/enabled-packs.json` and the instance-local `.claude/settings.local.json` `enabledPlugins` (gitignored; deep-merged with the template-managed `settings.json`). | `jq`, `python3` (embedded materialization), `yq` (ontology catalog) |
| `scripts/pack-toggle.sh` | Flips a pack's `enabled` flag in `harness.config.json` then re-materialises via `sync-packs.sh`. | `jq`; plus `python3` + `yq` via `sync-packs.sh` |
| `scripts/resolve-ontology.sh` | Topical ontology resolution for one MIF finding. Thin wrapper (ADR-0016): execs the `mif-rh-cli` engine, hard-required, no bash fallback. Fail-closed: an unresolvable type returns non-zero. Falls back to discovery-pattern classification. | `mif-rh-cli` |
| `scripts/ontology-review.sh` | Reviews and validates ontology coverage across topics; refreshes `reports/<topic>/ontology-map.json`. Thin wrapper (ADR-0016): execs the `mif-rh-cli` engine, hard-required, no bash fallback. Reports stamped (durable `entity` on disk) separately from discovery-only (a content-pattern guess never written back) and untyped; `--followup <path>` writes a JSON backlog of everything not durably stamped, grouped by topic. | `mif-rh-cli` |
| `scripts/check-relationship-targets.sh` | Proves every finding's `relationships[].target` resolves to a real finding `@id` in the active corpus. Run once, corpus-wide, by `ontology-review.sh` after its per-topic loop (`--relationship-script`). | `mif-rh-cli` (engine) |
| `scripts/check-shippable-typing.sh` | Fail-closed pre-synthesis gate (ADR-0011): a finding that ships (`verdict` in `survived`/`weakened`) must resolve to a valid ontology type. Blocks synthesis (exit 1) on an untyped/unresolved/invalid/unparsable shippable finding; falsified/quarantined/inconclusive findings never block. Read-only. | `mif-rh-cli` (engine) |
| `scripts/check-ontology-lock.sh` | Fail-closed integrity gate: every enabled domain ontology is pinned in `ontologies.lock.json` and present under `packs/ontologies/<id>/`, and every pinned, vendored ontology's file hashes to its pinned sha256. Passes cleanly when no lock exists (on-demand vendoring not adopted). | `jq`, `sha256sum` / `shasum` |
| `scripts/fetch-ontology.sh` | On-demand vendoring (ADR-0012) of one domain ontology pack: resolves its `extends` closure from the canonical registry index, fetches each non-committed layer, sha256-verifies every file fail-closed, materializes it under `packs/ontologies/<id>/`, and pins the result in `ontologies.lock.json`. Source precedence: `$MIF_ONTOLOGY_SOURCE`, `.ontologies.source`, then the canonical `https://mif-spec.dev/ontologies`. | `jq`, `yq`, `curl` (or a local dir source), `sha256sum` / `shasum` |
| `scripts/sync-registry-ontologies.sh` | Pulls new domain ontologies published to the canonical registry that `harness.config.json` has never heard of, enables each by default, then vendors and catalogs everything currently enabled. Delegates to `fetch-ontology.sh` and `sync-packs.sh`. | `jq`, `curl` |
| `scripts/author-ontology.sh` | When on-demand resolution finds no ontology for a domain, scaffolds one from the corpus's own `ontology-map.json` (or from `mif-rh-cli expansion-candidates` output via `--from-clusters`) and concierges a PR to the canonical registry. | `jq`, `git`, `gh` |
| `scripts/check-pack-docs.py` | Verifies pack documentation is complete and bidirectionally cross-linked: every pack-family component is documented and every doc links back. Run as a CI gate (`.github/workflows/docs.yml`). | Python stdlib only |
| `scripts/check-coverage-doc.py` | research-harness-template#481: verifies `docs/reference/coverage.md`'s Discovered counts, per-category headings, Total row, and Assertion line against the real repo state (recomputes the same five counts the page's own reproduce commands document). Run as a CI gate (`.github/workflows/docs.yml`). | Python stdlib only |
| `scripts/synthesize-artifact.sh` | Deterministic substrate for the report-synthesizer: consumes surviving findings (verdict ≠ `falsified`) and produces a typed `Artifact` (`schemas/artifact.schema.json`). Joins each section to its finding's resolved ontology type from `reports/<topic>/ontology-map.json` (`entityType`/`ontology`/`basis`); the no-map path stays byte-identical. Genre-neutral. | `jq` |
| `scripts/render-artifact.sh` | Renders a typed `Artifact` to an output channel (`report`, `blog`, `book`). The `report` channel calls `mif-project.sh` for L3 validation; `blog`/`book` carry MIF L1 frontmatter. | `jq`, `scripts/mif-project.sh` |
| `scripts/synthesize-corpus.sh` | Builds the cross-topic **corpus atlas** from the spine (`reports/concordance.json`): `reports/_corpus/corpus-map.json` (deterministic projection — topics, verdict distribution, entity reuse, contradictions, disproven), `corpus-synthesis.md` (atlas with a preserved synthesis section), and `README.md` (the site landing page, via `build-topic-readme.sh`'s `_corpus` mode). Reads concordance structure only (scales); `--check` gates all three. | `jq`, `mif-rh-cli` (engine) |
| `scripts/mif-project.sh` | Projects a MIF L3 markdown report (YAML frontmatter + body) into a JSON-LD finding projection and validates at MIF L3. Used by `render-artifact.sh` and the `gate_m10` harness gate. | `jq`, `yq`, `ajv` |

---

## Site

Scripts that control the Astro/Starlight site that renders `reports/` (and the
Diátaxis `docs/`) for human reading.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/site-toggle.sh` | Flips the `harness.config.json` `.site` control plane that `astro.config.mjs` reads at build time: `primary <reports\|docs\|auto>` chooses which surface leads the sidebar; `plugin <llmsTxt\|mermaid\|imageZoom\|linksValidator> <on\|off>` gates an optional Astro/Starlight enhancement. Applies on the next `npm run build`/`npm run dev`. | `jq` |
| `scripts/backfill-report-slugs.sh` | One-time remediation for reports rendered before `render-artifact.sh` started stamping `slug:`/`version:` frontmatter, so the site's cross-link rewriter (which slugifies filenames with a HEADING-anchor algorithm) does not 404 on genre-suffixed filenames. Idempotent: a file already carrying both keys is untouched. | coreutils (`sed`, `awk`, `grep`, `find`) |

---

## Codegen

Scripts that regenerate the Python TypedDict authoring layer from JSON Schemas.
These are dev/build-time only; generated files are committed.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/codegen/gen-models.sh` | Regenerates Python TypedDict models under `lib/harness_models/<name>.py`. Pipeline: bundle schemas → `datamodel-codegen` → `black` format. Set `CHECK=1` to verify without writing. Pinned versions: `datamodel-code-generator==0.68.1`, `black==26.5.1`. | `python3`, venv |
| `scripts/codegen/bundle_schema.py` | Stdlib JSON-Schema bundler: inlines external `$ref`s into `#/$defs`. Offline and cycle-safe. Called by `gen-models.sh`. | Python stdlib only |

---

## MIF Container export/import (Epic #275)

| Script | What it does | Toolchain |
| --- | --- | --- |
| `scripts/mif-container-digest.sh` | The container digest engine (Story #312, ADR-0017 AD-2): `resource <file>` prints a `sha256:<64-hex>` digest over the file's raw bytes; `manifest [< digests]` reads resource digests from stdin, sorts them (`LC_ALL=C`, matching this repo's other determinism-critical sorts), and hashes the sorted list — order-independent, fail-closed on an unreadable file or a missing sha256 tool. | coreutils (`sha256sum` or `shasum`) |
| `scripts/mif-container-resolve-scope.sh` | The export-scope resolver (Story #315, ADR-0017 AD-4, closure-first/marker-fallback): consumes `build-graph.sh`'s `knowledge-graph.json` and a JSON array of in-scope `urn:mif:concept:` ids; with `--closure`, transitively expands scope over relationship edges (never entity/mentions edges — entities aren't a packageable resource); prints `{resourceIds, boundaryReferences}`, classifying every excluded edge target `cross-topic`/`unresolvable`/`out-of-scope`, never a silent drop. | `jq` |
| `scripts/mif-container-import.sh` | The fail-closed import gate (Stories #318/#324/#328, ADR-0017): a strict, ordered 5-step sequence into an existing `harness.config.json` topic — manifest schema validation, per-resource + manifest-level digest verification plus a bulk `findings.schema.json` pre-check (before anything is written), ontology-binding compatibility against the destination's cataloged packs, an idempotent upsert-by-`@id` write (new `@id`s via `scripts/write-finding.sh`; existing `@id`s overwritten in place — via a per-field reconciliation policy, AD-6, not a blind replace: `provenance`/`extensions.harness.verification`/`extensions.harness.gathered_under` stay origin-scoped from the destination, `tags[]` unions both sides, everything else reconciles toward the incoming value — only if the digest differs). The manifest's ontology-map resource is written verbatim to `reports/<topic>/ontology-map.json` for a **full-scope** import, skipped as a no-op once the destination already matches; for a **subset** import — whose map only covers the exported ids — its entries are instead upserted into the destination's array by `finding_id` (order-preserving for existing entries, append-only for genuinely new ids), keeping every destination entry not present in the incoming set, never a verbatim overwrite that would delete typing for every other finding already there. The topic's own deliverables (`report`/`falsification-report`/`readme`/`goal`/`artifact` resources, research-harness-template#437) are also written here: `goal`/`artifact` are pre-validated against their own schemas and `report` against `scripts/mif-project.sh` (schema + citation-integrity + non-falsified verdict) in the same step-2 bulk pre-pass, then all five are published via a verbatim overwrite-if-digest-differs (re-verified immediately before staging, closing the same TOCTOU window findings' overwrite path already closes) — no per-field reconciliation, since there is nothing to merge field-by-field in a whole rendered report/goal. Then `build-graph.sh`/`build-topic-readme.sh`/`build-concordance.sh` plus a candidate-sameAs scan (`scripts/mif-container-detect-sameas.sh`) — note `build-topic-readme.sh` here deterministically REBUILDS the imported `README.md` keyed to the destination topic's own registered identity, so it is not expected to stay byte-identical to the source. `--dry-run` runs the validation steps only. An `mkdir`-based lock (`reports/<topic>/.container.lock`) fails a concurrent **import** invocation closed (AC12) instead of racing — `mif-container-export.sh` acquires the same lock before reading anything, so a concurrent **export** mid-import also fails closed instead of reading an inconsistent snapshot. | `jq`, `ajv` |
| `scripts/mif-container-detect-sameas.sh` | Candidate concordance `sameAs` detector (Story #324, Task #327, ADR-0017 AD-6): scans `reports/concordance.json` for same-kind nodes with different `@id`s but a normalized-identical `label`, writing `{"proposals": [...]}` to `reports/concordance-sameas-proposals.json`. Detection only — never rewrites an `@id` or merges anything; a human confirms any real match. | `jq` |
| `scripts/mif-container-export.sh` | The export builder (Story #328, Task #329): read-only against `reports/<topic>/`'s corpus content (AC10; `reports/<topic>/.container.lock` is acquired and released around the read, issue #375, the same mkdir-based mutual exclusion `mif-container-import.sh` uses, so a concurrent export/import against the same topic fails closed instead of racing) — builds a self-contained `mif-package.json` + resource files under a fresh `<output-dir>` for a full topic or (`--subset <in-scope-ids.json>` [`--closure`]) a scope resolved via `scripts/mif-container-resolve-scope.sh`. Copies in-scope findings plus a filtered `ontology-map.json` (full: the whole file; subset: only in-scope entries), derives `ontologyBindings[]` from the in-scope entries' `resolved_ontology` (falling back to the topic's full set when the subset resolves to zero findings, since the schema requires a non-empty `ontologyBindings[]` even for a valid empty-scope export). Also packages the topic's own deliverables — rendered report(s), the falsification report, `README.md`, `goal.json`, `artifact.json` (research-harness-template#437) — unconditionally regardless of full/subset scope (they are topic-level documents, not per-finding data) and each with the same mandatory per-resource digest; all optional, so a topic missing any of them still exports cleanly. Self-validates the finished manifest against `schemas/mif-container.schema.json` before reporting success. Wrapped by the `/export` command; `/import` wraps `mif-container-import.sh`. | `jq`, `ajv` |
| `scripts/lib/container-lock.sh` | Sourced library, not a standalone script (issue #375/#382). Shared `mkdir`-based mutual-exclusion lock, parameterized by lock-dir path — used by `mif-container-export.sh`/`mif-container-import.sh` for `reports/<topic>/.container.lock` (so a concurrent export/import against the same topic fails closed instead of racing) and, since issue #628, by `research-projection.js`'s Report phase for the independent `reports/<topic>/.projection-lock` (so two concurrent projection runs on the same topic with different genre/slug no longer race on the shared, well-known `artifact.json`/`report-finding*.json` intermediates — see that module's own header for why those paths can't simply be genre-suffixed the way `research-deliverables.js`'s blog/book intermediates are). The two lock namespaces are deliberately independent, same as `.container.lock` and `.run-lock` already are. Mirrors `run-lock.sh`'s staleness/steal semantics: a lock older than `CONTAINER_LOCK_STALE_MIN` (default 240min) is treated as abandoned and safely stolen. The reclaim itself is serialized behind a separate `mkdir`-based steal-mutex (research-harness-template#739) so two concurrent stealers can never both win — a bare rm-then-re-mkdir is NOT atomic on its own and let two racers both report success while only one actually held the lock. | none (pure shell) |
| `scripts/mif-container-migration-eval-bench.sh` | Story #334 (Epic #275, AD-7): a one-time (or run-on-demand) benchmark, not wired into `verify.sh`/`run-evals.sh`. Builds a synthetic topic of N schema-valid findings (default 4300, matching ADR-0014's own reference bottleneck scale) and times full export, import into a fresh topic, and re-import into the same topic — the numbers a human reads to judge whether AD-7's migration trigger (a real perf bottleneck at that scale) has been hit. | `jq`, `ajv` |

---

## Release and verification

Scripts that verify harness integrity and attestation.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/verify.sh` | Harness build gate. Runs accretive gate functions (`gate_mN`) in sequence. Detects template vs instance context. Exits 0 only when all gates pass. | `jq`, `yq`, `ajv`, `ajv-formats` |
| `scripts/lib/unreadable-probe.sh` | Sourced library, not a standalone script (research-harness-template#777). Pure classification helper for `gate_m27`'s unreadable-file fail-closed probe: `m27_classify_unreadable_probe <bypassed> <rc> <out>` prints `skip` when `chmod 000` didn't actually deny the current process read access (root / another DAC-override-capable process, so the probe's premise doesn't hold), `ok`/`bad` otherwise per the genuine digest-script outcome. No filesystem access itself, so it unit-tests deterministically regardless of which user runs the suite (`evals/gate-m27-root-safe-unreadable-check.sh`). Sourced by `verify.sh`. | none (pure shell) |
| `scripts/bump-version.sh` | Change-driven version bump (ADR-0010). Moves the release pointer (`harness.config.json`), the marketplace catalog (`.metadata.version`), and inserts the dated `CHANGELOG.md` section; bumps a pack's `plugin.json` + `SKILL.md` + family-doc row only when named with `--pack <component>`. Accepts `patch`/`minor`/`major` or an explicit `X.Y.Z`; `--check` dry-runs; self-verifies. | `jq`, `awk`, `sed` |
| `scripts/check-version-bump.sh` | CI enforcement for change-driven versioning (ADR-0010, amended). Fails when a changed pack/core-skill did not move its own version (diffed against a base ref, default `origin/main`), or when `harness.config.json`'s release pointer is not strictly ahead of the last git tag release — a per-release invariant, not a per-PR one. Wired as the PR-only `version-bump` CI job. | `git`, `jq` |
| `scripts/check-workflow-syntax.sh` | Parse-check for Workflow-runtime modules (`.claude/workflows/*.js`, #552). Those modules use the runtime's async-function-body shape (top-level `return`/`await` are legal), so a bare `node --check` rejects a valid module; this checker strips the `export` keyword and compiles the source as an async function body instead, failing loudly (file + error) on genuine syntax errors. Compile-only — nothing executes. Wired into `verify.sh`'s `gate_workflows`; regression eval `evals/workflow-parse-check.sh`. | `node` |
| `scripts/check-workflow-forbidden-globals.sh` | Static regression gate for #618: greps every Workflow-runtime module (`.claude/workflows/*.js`) for `new Date(`, `Date.now(`, and `Math.random(` — calls the runtime disallows inside a script's own body (breaks deterministic resume). A comment-aware state-machine tokenizer strips `//`/`/* */` comments and the static-text portions of strings/template literals first (so it doesn't false-positive on this module's or research-falsify.js's own prose), but scans a template literal's `${...}` expressions as real code, since a forbidden call written inside one is exactly as real a violation as a bare top-level call. Compile-only — nothing executes. Wired into `verify.sh`'s `gate_workflows`, alongside `check-workflow-syntax.sh`; regression eval `evals/workflow-forbidden-globals-check.sh`. | `node` |
| `scripts/lint-goal.sh` | Deterministic verifiability lint for a session goal (#554): ajv schema gate against `schemas/goal.schema.json` (fail-closed), step-shaped `completion_condition.checks[]` assertions (leading imperative research verb — a step, not an end-state fact), and `dimensions[]` entries not declared in the config (`--config`, default `harness.config.json`). The research-goal workflow's Gate phase runs it as the deterministic floor under the agent-judgment lint; regression eval `evals/goal-lint-repair.sh`. | `jq`, `ajv` |
| `scripts/check-mermaid.py` | Structural validator for Mermaid diagrams in Markdown: flags empty blocks, unknown diagram types, markdown-escape corruption (a `\*`/`\_` leaked into a fence), and unbalanced brackets. Used by the `mermaid-render` eval; full grammar validation is left to `mmdc` (intentionally not a runtime dependency). | Python stdlib only |
| `scripts/update.sh` | The only supported way a clone updates from the template: a fail-closed provenance gate in front of `copier update` that pins the update to a verified release commit and reproduces the release artifact before applying. | `git`, `gh`, `copier` |
| `scripts/install-hooks.sh` | Called from `package.json`'s `postinstall`. Wires `core.hooksPath` to `.githooks/` unless a contributor already configured a different `hooksPath` on purpose (leaves it alone, warns on stderr). Always exits 0 — best-effort, never fails the install. | `git` |
| `scripts/install-monitoring-workflows.sh` | Materializes the continuous-monitor pack's GitHub Actions workflows (`packs/monitoring/continuous-monitor/workflows/*.yml`, the canonical sources copier ships) into `.github/workflows/` — the documented opt-in for instantiated clones, which never receive workflow files from copier (#517). Idempotent; `--check` reports drift without writing (non-zero exit when a copy differs); notes loudly when the pack is disabled. `verify.sh`'s `gate_monitoring_workflow_sync` holds installed copies byte-identical to their pack sources. | `jq` |
