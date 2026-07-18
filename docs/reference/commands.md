---
id: reference-commands
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-18T00:25:52.278Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: commands"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-24T10:25:46-04:00'
  ttl: P6M
  recordedAt: '2026-06-24T10:25:46-04:00'
provenance:
  '@type': Provenance
  agent: claude-code/claude-fable-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:7b4efc9f-b778-4d49-b1e4-c009adbd178a
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.212
---

# Reference: commands

Commands are slash-command entry points invoked directly in a Claude session.
All eleven listed here are core (non-pack); they ship with the template.

See [dependencies](dependencies.md) for tool installation requirements.

---

## /configure

The configuration concierge for the harness manifest.

**Purpose:** Applies a configuration change to `harness.config.json` through the
harness's own tooling, then validates it against `harness.config.schema.json` and
re-runs the gates. Covers packs (`scripts/pack-toggle.sh`), the reports/docs site
surface and optional plugins (`scripts/site-toggle.sh`), ontologies (defers binding
to `/ontology-review`), and topic/dimension/output/voice/freshness edits. It never
hand-rolls what a script already owns, and never reports a change done while a gate
is red.

**Usage:**

```text
/configure [packs|site|ontologies|topics|verify] [<free-form request>]
```

With no area it surveys the current configuration and suggests next steps.

**What it delegates to:** `harness-configurator` agent, which drives
`scripts/pack-toggle.sh`, `scripts/site-toggle.sh`, `scripts/sync-packs.sh`, and the
`/ontology-review` command/skill.

**Dependencies:** `harness.config.json`, `harness.config.schema.json`,
`scripts/pack-toggle.sh`, `scripts/site-toggle.sh`, `jq`, `ajv`.

---

## /export

Builds a MIF Container manifest plus resource files from a registered topic.

**Purpose:** Thin delegator to `scripts/mif-container-export.sh` (ADR-0017,
Story #328) — never implements export logic itself. Read-only against
`reports/<topic>/`. Supports a full-topic export or a `--subset` of
`urn:mif:concept:...` ids (optionally expanded via `--closure`, ADR-0017 AD-4).
The finished `<output-dir>/mif-package.json` is self-validated against
`schemas/mif-container.schema.json` before the command reports success.

**Usage:**

```text
/export <topic> <output-dir> [--subset <in-scope-ids.json>] [--closure] [--source-instance <name>]
```

**What it delegates to:** `scripts/mif-container-export.sh`.

**Dependencies:** `scripts/mif-container-resolve-scope.sh`,
`scripts/mif-container-digest.sh`, `schemas/mif-container.schema.json`, `jq`, `ajv`.

**Docs:** [how-to](../how-to/export-and-import-a-topic.md) ·
[explanation](../explanation/mif-container-format.md).

---

## /falsify

Runs the adversarial falsification gate on one or more findings.

**Purpose:** Acquires the topic-level run lock (`scripts/run-lock.sh`), then
delegates to the `falsification-analyst` agent in a bounded slice loop. Each
slice polls disk state between passes. Verdicts are ordinal:
`falsified | weakened | survived | inconclusive`. One-round rule: the analyst
makes one pass per finding; no retry loops.

**Usage:**

```text
/falsify --topic <id> [--scope <scope>] [--query-budget <N>] [--claim-budget <N>]
```

`--scope` accepts `all`, `dimension:<dim>`, or `finding:<@id>`.

**What it delegates to:** `falsification-analyst` agent.

**Dependencies:** `scripts/run-lock.sh`, `scripts/falsify.sh`.

---

## /goal-writer

Authors the session goal JSON and `/goal` prose for a topic.

**Purpose:** Writes `reports/<topic>/goal.json`, validates it against
`schemas/goal.schema.json`, and produces the companion `/goal` prose section.
The `--reshape` flag evolves an existing goal using append-only versioning
(SPEC §11): dimensions and checks may be added but not removed. Computes the
content-hash goal version (`gv-<sha256[:12]>`) via `scripts/goal-version.sh`
and resolves carry/stale/gap membership via `scripts/resolve-membership.sh`.
Does not spawn the orchestrator.

**Engine counterpart:** `/goal-writer` stays the interactive, user-facing
path. The engine path a research pipeline composes is the `research-goal`
Workflow-runtime module (`.claude/workflows/research-goal.js` — see
[engine workflows](engine-workflows.md)): the same contract (this command's
manual is its Draft phase's operating manual; `schemas/goal.schema.json`;
ADR-0006 append-only lineage), returned as a typed, non-interactive result
with an `ajv` + verifiability-lint gate after every link and a bounded
repair loop. For engine-composed goal authoring that deterministic chaining
supersedes prompt-discipline gating; the interactive path is not superseded.

**Usage:**

```text
/goal-writer --topic <id> [--reshape]
```

**What it delegates to:** Nothing — writes directly after schema validation.

**Dependencies:** `scripts/goal-version.sh`, `scripts/resolve-membership.sh`,
`schemas/goal.schema.json`, `ajv`.

---

## /import

Applies a MIF Container manifest into a registered topic through the
fail-closed import gate.

**Purpose:** Thin delegator to `scripts/mif-container-import.sh` (ADR-0017,
Stories #318/#324/#328) — never implements import logic itself. A strict,
ordered sequence (manifest schema validation, digest verification,
ontology-binding compatibility, idempotent upsert-by-`@id` with a per-field
reconciliation policy, then the deterministic rebuilders plus a candidate
sameAs scan): a failure at any step rejects the entire import, never a
partial write. `--dry-run` runs validation only.

The manifest's ontology-map resource is written verbatim to the destination
topic only for a **full-scope** import — a **subset** import leaves the
destination's `ontology-map.json` untouched, since overwriting it with a
subset's partial map would delete typing for every other finding already
there.

**Usage:**

```text
/import <container-dir> <topic> [--dry-run]
```

**What it delegates to:** `scripts/mif-container-import.sh`.

**Dependencies:** `scripts/mif-container-digest.sh`,
`schemas/mif-container.schema.json`, `schemas/findings.schema.json`, `jq`, `ajv`.

**Docs:** [how-to](../how-to/export-and-import-a-topic.md) ·
[explanation](../explanation/mif-container-format.md).

---

## /ontology-review

Reviews, enriches, and validates ontology coverage for a topic.

**Purpose:** Three sequential phases. Phase 1 (deterministic): runs
`scripts/ontology-review.sh` to refresh `reports/<topic>/ontology-map.json`
and report coverage gaps. Phase 2 (enrich, optional): binds the ontology and
retro-classifies existing findings; when the compiled engine's scored
suggestion queue `reports/_meta/suggestions/<topic>.json` exists (written by
`mif-rh-cli review --suggest`; ADR-0015), enrich also reviews its pending
entries' scored candidates and sets each entry's status to confirmed or
rejected — entries are never deleted, and a confirmed candidate still goes
through the normal typing edit and resolve re-stamp, never a direct
auto-write. Phase 3 (author, optional): invokes the `ontology-manager` skill
to create or update ontology YAML. The `--strict` flag fails on any
unresolved type.

**Usage:**

```text
/ontology-review [--topic <id>] [--enrich] [--strict]
```

**What it delegates to:** `scripts/ontology-review.sh` (Phase 1), `ontology-manager`
skill (Phase 3 when authoring is needed).

**Dependencies:** `scripts/ontology-review.sh`, `mif-rh-cli` (the engine it delegates to, ADR-0016).

---

## /resume

Resumes a paused or interrupted research session.

**Purpose:** Reads the session continuity file for the topic, validates the
current goal against `schemas/goal.schema.json`, runs
`scripts/reconcile-session.sh` to derive a fresh checkpoint from disk (a
finding is DONE iff it schema-validates — which requires a `verification` block
— **and** its verdict is not `falsified`; a falsified-but-valid finding is left
not-done so its dimension is reworked), then re-spawns the `orchestrator` agent
in `full` mode with the reconciled state.

**Usage:**

```text
/resume --topic <id>
```

**What it delegates to:** `orchestrator` agent.

**Dependencies:** `scripts/reconcile-session.sh`, `schemas/goal.schema.json`.

---

## /start

Starts a new research session or extends an existing one.

**Purpose:** Registers the topic in `harness.config.json` if not present.
Supports three modes: `full` (complete session from scratch), `augment`
(add one or more dimensions to an existing session), and `update` (refresh
stale findings for the current goal version). Phase 2b incorporates any bound
ontology into the session context. Delegates all research work to the
`orchestrator` agent. After the orchestrator returns, invokes the `readme`
skill to reconcile the per-topic navigation README.

**Usage:**

```text
/start --topic <id> [--goal <goal-json-path>] [--augment [<dim>]] [--update]
```

**What it delegates to:** `orchestrator` agent, then `readme` skill.

**Dependencies:** `harness.config.json`, `schemas/goal.schema.json`,
`scripts/reconcile-session.sh`.

---

## /status

Reports read-only session state for a topic.

**Purpose:** Reads `research-progress.md` for the active topic, counts
findings on disk, produces a verdict rollup (survived/weakened/falsified/
inconclusive), and reports per-dimension finding counts. No writes; no agents
spawned. Safe to run at any point in a session.

**Usage:**

```text
/status [--topic <id>]
```

**What it delegates to:** Nothing — read-only.

**Dependencies:** `research-progress.md`, `reports/<topic>/findings/*.json`,
`jq`.

---

## /synthesize-corpus

Builds the cross-topic **corpus atlas** from the ontological spine.

**Purpose:** Projects `reports/concordance.json` across every topic into the corpus atlas — what
the whole corpus knows, including what was disproven. Distinct from a per-topic report
(`/start` → `report-synthesizer`, survivors only). Cross-session and cross-topic, not tied to one
`/start`. Builds the spine on demand if absent.

**Usage:**

```text
/synthesize-corpus
```

**What it delegates to:** `corpus-synthesizer` (over the whole `reports/` tree).

**Dependencies:** `scripts/synthesize-corpus.sh`, `scripts/build-concordance.sh`,
`reports/concordance.json`.

---

## /topics

Lists the topic registry from the harness manifest.

**Purpose:** Reads `harness.config.json` `topics[]` and presents each topic's
`id`, `title`, `namespace`, and `status`. Supports `--filter <status>` to
narrow to topics at a given status, and `--ids` to emit only topic ids (useful
for scripting). Simpler than the `topics` skill — no index rollup, just the
manifest view.

**Usage:**

```text
/topics [--filter <status>] [--ids]
```

**What it delegates to:** Nothing — read-only manifest view.

**Note:** The `topics` skill (invoked as a skill, not a command) adds live
finding and verdict rollup from `research-index.json`. See
[core-skills](./core-skills.md#topics).

**Dependencies:** `harness.config.json`.
