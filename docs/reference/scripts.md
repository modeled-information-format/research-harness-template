---
id: reference-scripts
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-09T19:35:00-04:00'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: scripts"
diataxis_type: reference
---

# Reference: scripts

All scripts shipped with the template core (shell, plus one Python codegen
helper and one `jq` filter). Most are invoked by agents, commands, and skills,
but several are run directly by adopters — for example `pack-toggle.sh` to
enable a pack and `verify.sh` as the conformance gate. `jq` is a near-universal
dependency; see [dependencies](dependencies.md) for installation.

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
(ADR-0016). See [dependencies](dependencies.md) for the `mif-rh-cli` version
floor, [engine-cli.md](engine-cli.md) for its subcommand surface, and
[mcp-server.md](mcp-server.md) for the MCP server the same install ships.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/fetch-engine.sh` | Downloads the pinned `mif-rh-cli` and `mif-rh-mcp` release binaries for the current platform from the `mif-rs` repository, verifies each one's build provenance with `gh attestation verify` (fail-closed), and installs both to `bin/`. | `gh` |
| `scripts/lib/engine.sh` | Sourced library, not a standalone script. Provides `engine_bin()`: resolves the `mif-rh-cli` binary (`$MIF_RH_CLI` override, then `PATH`, then `bin/mif-rh-cli`), checks its reported version against the pinned floor, and fails loudly naming `fetch-engine.sh` as the fix. Sourced by `resolve-ontology.sh` and `ontology-review.sh`. | `grep`, `head`, `awk` |

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
| `scripts/run-lock.sh` | Topic-level mutual-exclusion lock (directory-based atomic test-and-set). Prevents concurrent writers on the same topic. Staleness window: `RUN_LOCK_STALE_MIN` (default 240 min). Operations: `acquire`, `release`, `refresh`, `steal`. | coreutils (`find`, `touch`, `mkdir`, `rm`, `cat`) |
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
| `scripts/codegen/gen-models.sh` | Regenerates Python TypedDict models under `lib/harness_models/<name>.py`. Pipeline: bundle schemas → `datamodel-codegen` → `black` format. Set `CHECK=1` to verify without writing. Pinned versions: `datamodel-code-generator==0.65.0`, `black==26.5.1`. | `python3`, venv |
| `scripts/codegen/bundle_schema.py` | Stdlib JSON-Schema bundler: inlines external `$ref`s into `#/$defs`. Offline and cycle-safe. Called by `gen-models.sh`. | Python stdlib only |

---

## MIF Container export/import (Epic #275)

| Script | What it does | Toolchain |
| --- | --- | --- |
| `scripts/mif-container-digest.sh` | The container digest engine (Story #312, ADR-0017 AD-2): `resource <file>` prints a `sha256:<64-hex>` digest over the file's raw bytes; `manifest [< digests]` reads resource digests from stdin, sorts them (`LC_ALL=C`, matching this repo's other determinism-critical sorts), and hashes the sorted list — order-independent, fail-closed on an unreadable file or a missing sha256 tool. | coreutils (`sha256sum` or `shasum`) |
| `scripts/mif-container-resolve-scope.sh` | The export-scope resolver (Story #315, ADR-0017 AD-4, closure-first/marker-fallback): consumes `build-graph.sh`'s `knowledge-graph.json` and a JSON array of in-scope `urn:mif:concept:` ids; with `--closure`, transitively expands scope over relationship edges (never entity/mentions edges — entities aren't a packageable resource); prints `{resourceIds, boundaryReferences}`, classifying every excluded edge target `cross-topic`/`unresolvable`/`out-of-scope`, never a silent drop. | `jq` |
| `scripts/mif-container-import.sh` | The fail-closed import gate (Stories #318/#324/#328, ADR-0017): a strict, ordered 5-step sequence into an existing `harness.config.json` topic — manifest schema validation, per-resource + manifest-level digest verification plus a bulk `findings.schema.json` pre-check (before anything is written), ontology-binding compatibility against the destination's cataloged packs, an idempotent upsert-by-`@id` write (new `@id`s via `scripts/write-finding.sh`; existing `@id`s overwritten in place — via a per-field reconciliation policy, AD-6, not a blind replace: `provenance`/`extensions.harness.verification`/`extensions.harness.gathered_under` stay origin-scoped from the destination, `tags[]` unions both sides, everything else reconciles toward the incoming value — only if the digest differs). The manifest's ontology-map resource is written verbatim to `reports/<topic>/ontology-map.json` for a **full-scope** import, skipped as a no-op once the destination already matches; for a **subset** import — whose map only covers the exported ids — its entries are instead upserted into the destination's array by `finding_id` (order-preserving for existing entries, append-only for genuinely new ids), keeping every destination entry not present in the incoming set, never a verbatim overwrite that would delete typing for every other finding already there. Then `build-graph.sh`/`build-topic-readme.sh`/`build-concordance.sh` plus a candidate-sameAs scan (`scripts/mif-container-detect-sameas.sh`). `--dry-run` runs the validation steps only. An `mkdir`-based lock (`reports/<topic>/.container.lock`) fails a concurrent **import** invocation closed (AC12) instead of racing — `mif-container-export.sh` acquires the same lock before reading anything, so a concurrent **export** mid-import also fails closed instead of reading an inconsistent snapshot. | `jq`, `ajv` |
| `scripts/mif-container-detect-sameas.sh` | Candidate concordance `sameAs` detector (Story #324, Task #327, ADR-0017 AD-6): scans `reports/concordance.json` for same-kind nodes with different `@id`s but a normalized-identical `label`, writing `{"proposals": [...]}` to `reports/concordance-sameas-proposals.json`. Detection only — never rewrites an `@id` or merges anything; a human confirms any real match. | `jq` |
| `scripts/mif-container-export.sh` | The export builder (Story #328, Task #329): read-only against `reports/<topic>/`'s corpus content (AC10; `reports/<topic>/.container.lock` is acquired and released around the read, issue #375, the same mkdir-based mutual exclusion `mif-container-import.sh` uses, so a concurrent export/import against the same topic fails closed instead of racing) — builds a self-contained `mif-package.json` + resource files under a fresh `<output-dir>` for a full topic or (`--subset <in-scope-ids.json>` [`--closure`]) a scope resolved via `scripts/mif-container-resolve-scope.sh`. Copies in-scope findings plus a filtered `ontology-map.json` (full: the whole file; subset: only in-scope entries), derives `ontologyBindings[]` from the in-scope entries' `resolved_ontology` (falling back to the topic's full set when the subset resolves to zero findings, since the schema requires a non-empty `ontologyBindings[]` even for a valid empty-scope export), and self-validates the finished manifest against `schemas/mif-container.schema.json` before reporting success. Wrapped by the `/export` command; `/import` wraps `mif-container-import.sh`. | `jq`, `ajv` |

---

## Release and verification

Scripts that verify harness integrity and attestation.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/verify.sh` | Harness build gate. Runs accretive gate functions (`gate_mN`) in sequence. Detects template vs instance context. Exits 0 only when all gates pass. | `jq`, `yq`, `ajv`, `ajv-formats` |
| `scripts/bump-version.sh` | Change-driven version bump (ADR-0010). Moves the release pointer (`harness.config.json`), the marketplace catalog (`.metadata.version`), and inserts the dated `CHANGELOG.md` section; bumps a pack's `plugin.json` + `SKILL.md` + family-doc row only when named with `--pack <component>`. Accepts `patch`/`minor`/`major` or an explicit `X.Y.Z`; `--check` dry-runs; self-verifies. | `jq`, `awk`, `sed` |
| `scripts/check-version-bump.sh` | CI enforcement for change-driven versioning (ADR-0010, amended). Fails when a changed pack/core-skill did not move its own version (diffed against a base ref, default `origin/main`), or when `harness.config.json`'s release pointer is not strictly ahead of the last git tag release — a per-release invariant, not a per-PR one. Wired as the PR-only `version-bump` CI job. | `git`, `jq` |
| `scripts/check-mermaid.py` | Structural validator for Mermaid diagrams in Markdown: flags empty blocks, unknown diagram types, markdown-escape corruption (a `\*`/`\_` leaked into a fence), and unbalanced brackets. Used by the `mermaid-render` eval; full grammar validation is left to `mmdc` (intentionally not a runtime dependency). | Python stdlib only |
| `scripts/update.sh` | The only supported way a clone updates from the template: a fail-closed provenance gate in front of `copier update` that pins the update to a verified release commit and reproduces the release artifact before applying. | `git`, `gh`, `copier` |
