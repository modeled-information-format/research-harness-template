---
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

---

## Graph and index

Scripts that build or maintain the knowledge graph, research index, and
cross-topic concordance.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/build-graph.sh` | Builds the MIF-native knowledge graph from findings. Nodes: one concept per finding plus one entity per `EntityReference`. Edges: typed relationships and mention links. | `jq` |
| `scripts/assert-graph-mif.sh` | Acceptance gate: asserts all node and edge IDs are `urn:mif:` URNs and that at least one typed relationship edge exists. | `jq` |
| `scripts/build-graph-viz.sh` | Renders the knowledge graph as a standalone, dependency-free HTML file. | `jq` |
| `scripts/build-concordance.sh` | Builds the cross-topic ontological spine (`reports/concordance.json`) by merging all topics' findings. Deterministic and idempotent. | `jq` |
| `scripts/validate-concordance.sh` | Fail-closed ontology conformance check for the concordance: asserts every node `entityType` and relationship type is declared by the bound ontology and that `from`/`to` domains are consistent. | `jq`, `yq` |
| `scripts/build-index.sh` | Incremental maintenance of `research-index.json` — a flat projection of all MIF findings. Also projects goal-version membership (SPEC §11). | `jq` |

---

## Findings and session

Scripts that create, validate, falsify, and checkpoint findings, and that
manage the session run lock.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/write-finding.sh` | Stage-validate-rename atomic write: a finding is visible on disk only after it passes schema validation (crash-safe). | `ajv` |
| `scripts/wrap-source.sh` | Normalises a raw source to a MIF source-envelope at the ingestion boundary, validates at L3 before an analyst consumes it. | `jq`, `ajv` |
| `scripts/falsify.sh` | Deterministic falsification substrate: writes an ordinal verdict into `extensions.harness.verification`, logs one `falsification-gate: run` line per invocation, enforces the one-round rule. | `jq` |
| `scripts/reconcile-session.sh` | Derives a durable session checkpoint (`state.json`) from disk. A finding is DONE iff it validates against the full schema (which requires a `verification` block) **and** its verdict is not `falsified` — a falsified-but-valid finding is intentionally not done. Idempotent and byte-deterministic. | `jq`, `ajv` |
| `scripts/run-lock.sh` | Topic-level mutual-exclusion lock (directory-based atomic test-and-set). Prevents concurrent writers on the same topic. Staleness window: `RUN_LOCK_STALE_MIN` (default 240 min). Operations: `acquire`, `release`, `refresh`, `steal`. | coreutils (`find`, `touch`, `mkdir`, `rm`, `cat`) |
| `scripts/goal-version.sh` | Computes a content-hash goal version ID (`gv-<sha256[:12]>`) by normalising the goal JSON (removing lineage fields, sorting keys). | `jq`, `sha256sum` / `shasum` / `openssl` |
| `scripts/resolve-membership.sh` | Deterministic scope-resolution for a goal version: emits `reports/<topic>/goals/goal-<version>.members.json` with `members[]`, `stale[]`, and `gap_dimensions[]`. | `jq` |
| `scripts/check-citation-integrity.sh` | Citation-integrity gate: asserts at least one citation per finding; each citation traceable (well-formed `http(s)` URL *format* or an `internal:` source with a `note`) and carrying a `citationRole`; no `falsified` finding ships; and no citation URL is pre-marked dead via `extensions.harness.citationStatus.deadUrls[]`. It validates URL format and the marked-dead list — it does **not** probe URL liveness. | `jq` |
| `scripts/build-topic-readme.sh` | Builds and validates the per-topic navigation README. Computes deterministic backbone (counts, dates, tables); preserves synthesis-grade Key Findings across rebuilds. | `jq` |
| `scripts/import-corpus.sh` | Imports an existing MIF corpus into an instantiated harness: validates each unit, registers the topic, rebuilds the index and graph. | `jq`, `ajv` |

---

## Packs and ontology

Scripts that manage capability packs, ontology resolution, and artifact synthesis.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/sync-packs.sh` | Materialises `harness.config.json` `packs[]` into `.claude/enabled-packs.json` and the instance-local `.claude/settings.local.json` `enabledPlugins` (gitignored; deep-merged with the template-managed `settings.json`). | `jq`, `python3` (embedded materialization), `yq` (ontology catalog) |
| `scripts/pack-toggle.sh` | Flips a pack's `enabled` flag in `harness.config.json` then re-materialises via `sync-packs.sh`. | `jq`; plus `python3` + `yq` via `sync-packs.sh` |
| `scripts/resolve-ontology.sh` | Topical ontology resolution for one MIF finding. Fail-closed: an unresolvable type returns non-zero. Falls back to discovery-pattern classification. | `yq`, `jq`, `ajv` |
| `scripts/ontology-review.sh` | Reviews and validates ontology coverage across topics; refreshes `reports/<topic>/ontology-map.json`. | `jq`, `yq`, `ajv` |
| `scripts/check-pack-docs.py` | Verifies pack documentation is complete and bidirectionally cross-linked: every pack-family component is documented and every doc links back. Run as a CI gate (`.github/workflows/docs.yml`). | Python stdlib only |
| `scripts/synthesize-artifact.sh` | Deterministic substrate for the report-synthesizer: consumes surviving findings (verdict ≠ `falsified`) and produces a typed `Artifact` (`schemas/artifact.schema.json`). Genre-neutral. | `jq` |
| `scripts/render-artifact.sh` | Renders a typed `Artifact` to an output channel (`report`, `blog`, `book`). The `report` channel calls `mif-project.sh` for L3 validation; `blog`/`book` carry MIF L1 frontmatter. | `jq`, `scripts/mif-project.sh` |
| `scripts/mif-project.sh` | Projects a MIF L3 markdown report (YAML frontmatter + body) into a JSON-LD finding projection and validates at MIF L3. Used by `render-artifact.sh` and the `gate_m10` harness gate. | `jq`, `yq`, `ajv` |

---

## Codegen

Scripts that regenerate the Python TypedDict authoring layer from JSON Schemas.
These are dev/build-time only; generated files are committed.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/codegen/gen-models.sh` | Regenerates Python TypedDict models under `lib/harness_models/<name>.py`. Pipeline: bundle schemas → `datamodel-codegen` → `black` format. Set `CHECK=1` to verify without writing. Pinned versions: `datamodel-code-generator==0.65.0`, `black==26.5.1`. | `python3`, venv |
| `scripts/codegen/bundle_schema.py` | Stdlib JSON-Schema bundler: inlines external `$ref`s into `#/$defs`. Offline and cycle-safe. Called by `gen-models.sh`. | Python stdlib only |

---

## Release and verification

Scripts that verify harness integrity and attestation.

| Script | Purpose | Key dependency |
| --- | --- | --- |
| `scripts/verify.sh` | Harness build gate. Runs accretive gate functions (`gate_mN`) in sequence. Detects template vs instance context. Exits 0 only when all gates pass. | `jq`, `yq`, `ajv`, `ajv-formats` |
| `scripts/update.sh` | The only supported way a clone updates from the template: a fail-closed provenance gate in front of `copier update` that pins the update to a verified release commit and reproduces the release artifact before applying. | `git`, `gh`, `copier` |
