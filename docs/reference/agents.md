---
title: "Reference: agents"
diataxis_type: reference
---

# Reference: agents

Agents are named subagents spawned programmatically during a research session.
They run as background Claude instances with defined inputs, outputs, and tool
allowlists. The five listed here are core (non-pack); they ship with the
template.

The pipeline is: orchestrator → dimension-analyst (fan-out) →
falsification-analyst → report-synthesizer. The source-chunker is spawned
on-demand by dimension-analysts that encounter oversized documents.

See [dependencies](dependencies.md) for tool installation requirements.

---

## orchestrator

Owns the end-to-end research session lifecycle.

**Role:** Phase-owning coordinator. Acquires the topic-level run lock, fans
out `dimension-analyst` subagents (one per config-declared dimension, up to
`MAX_CONCURRENCY` in parallel), runs the falsification gate in bounded slices
via `falsification-analyst`, spawns `report-synthesizer`, and owns
`research-progress.md` (the session checkpoint file). Supports three modes:
`full` (complete session), `update` (refresh stale findings for the current
goal version), and `augment` (add one or more new dimensions).

**Spawned by:** `/start`, `/resume`.

**Inputs:**

| Variable | Description |
| --- | --- |
| `GOAL_FILE` | Path to `reports/<topic>/goal.json` |
| `TOPIC` | Human-readable topic title |
| `TOPIC_SLUG` | Machine-safe topic identifier |
| `REPORTS_DIR` | Path to `reports/<topic>/` |
| `MODE` | `full \| update \| augment` |
| `DIMENSION` | Specific dimension name when `MODE=augment` |
| `MAX_CONCURRENCY` | Max parallel dimension-analyst subagents |
| `QUERY_BUDGET` | Max web queries per dimension |
| `CLAIM_BUDGET` | Max findings per dimension |

**Outputs:** `research-progress.md`, per-dimension finding sets written by
subagents, final report from `report-synthesizer`.

**Dependencies:** `scripts/run-lock.sh`, `scripts/reconcile-session.sh`,
`scripts/falsify.sh`. Model: `sonnet`.

---

## dimension-analyst

Researches one declared dimension to saturation.

**Role:** Focused web researcher. Receives a single config-declared dimension
and researches it exhaustively (dozens to hundreds of findings). Writes each
finding as an individual MIF JSON file under `REPORTS_DIR/findings/` using
`harness_models.emit.write()` for schema-validated authoring. Hands oversized
source documents (> 50 K tokens) to `source-chunker`. Never runs the
falsification gate.

**Spawned by:** `orchestrator` (one instance per dimension).

**Inputs:**

| Variable | Description |
| --- | --- |
| `DIMENSION` | The single dimension this analyst owns |
| `GOAL_FILE` | Path to the session goal JSON |
| `REPORTS_DIR` | Path to `reports/<topic>/` |
| `QUERY_BUDGET` | Max web queries |
| `CLAIM_BUDGET` | Max findings to emit |

**Outputs:**

| Field | Description |
| --- | --- |
| `finding_files` | List of paths written under `REPORTS_DIR/findings/` |
| `oversized_sources` | Sources handed off to `source-chunker` |
| `unresolved_gaps` | Coverage gaps the analyst could not close |

**Dependencies:** `harness_models.emit.write()`, `scripts/wrap-source.sh`,
`scripts/write-finding.sh`. Model: `sonnet`.

---

## falsification-analyst

Adversarially tests findings and writes ordinal verdicts.

**Role:** Single-pass adversarial reviewer. For each finding in scope, fetches
web-only evidence to challenge the claim, then writes the verdict block through
`scripts/falsify.sh` — the only authorised write path. Verdicts are ordinal:
`falsified | weakened | survived | inconclusive`. One-round rule: one pass
per finding, no retry loops. Remediation: `falsified` findings are quarantined,
`weakened` findings are downgraded one evidence level, `survived` and
`inconclusive` findings are annotated. Enforces budget limits (fail-loud, not
silent truncation).

**Spawned by:** `orchestrator` (falsification gate phase), `/falsify` command.

**Inputs:** Findings to test (paths or scope selector), `QUERY_BUDGET`,
`CLAIM_BUDGET`.

**Outputs:** Verdict rollup; updated `extensions.harness.verification` blocks
written through `scripts/falsify.sh`.

**Dependencies:** `scripts/falsify.sh`. Model: `opus`.

---

## report-synthesizer

Produces publishable outputs from the verified finding set.

**Role:** Synthesis and rendering agent. Operates on two orthogonal axes:
channel (`report` — first-class MIF L3; `blog` — first-class MIF-exempt;
`book` and others via optional packs) and genre (exec-summary, academic,
engineering, etc., from the optional `reports` pack). Steps: load goal and
surviving findings → resolve genre → synthesize typed `Artifact`
(`scripts/synthesize-artifact.sh`) → render output per channel
(`scripts/render-artifact.sh`) → for `report` channel, validate at MIF L3
(`scripts/mif-project.sh`) → reconcile the topic README (`readme` skill).
Citation-integrity gate (`scripts/check-citation-integrity.sh`) runs before
any output ships.

**Spawned by:** `orchestrator` (final phase of a session).

**Inputs:** `GOAL_FILE`, surviving finding paths, channel selector, optional
genre.

**Outputs:** Rendered output file(s) at `reports/<topic>/<slug>.md`;
updated `reports/<topic>/README.md`.

**Dependencies:** `scripts/synthesize-artifact.sh`, `scripts/render-artifact.sh`,
`scripts/mif-project.sh`, `scripts/check-citation-integrity.sh`,
`schemas/artifact.schema.json`. Model: `opus`.

---

## corpus-synthesizer

Produces the cross-topic **corpus atlas** from the ontological spine.

**Role:** Cross-topic synthesis agent. Projects `reports/concordance.json` across every topic
into `reports/_corpus/corpus-synthesis.md` — the whole research record, including what was
falsified (which the survivors-only `report-synthesizer` omits). Steps: build the deterministic
backbone (`scripts/synthesize-corpus.sh`) → author synthesis-grade Cross-Corpus Insights
(cross-topic entity reuse, converging vs. contradicting evidence, what was disproven) traced to
concordance node ids → gate with `synthesize-corpus.sh --check`.

**Spawned by:** `/synthesize-corpus` (user-invoked; cross-session, not tied to one `/start`).
The orchestrator suggests it but does not auto-run it (the corpus spans all topics).

**Inputs:** `reports/concordance.json` (assumed built + valid).

**Outputs:** `reports/_corpus/corpus-map.json` (deterministic projection) and
`reports/_corpus/corpus-synthesis.md` (the atlas).

**Dependencies:** `scripts/synthesize-corpus.sh`, `scripts/build-concordance.sh`. Model: `opus`.

---

## source-chunker

Handles oversized source documents for dimension-analysts.

**Role:** Content-type-aware chunker for documents that exceed the
dimension-analyst's token budget (> 50 K tokens). Detects content type, selects
a chunking strategy, and processes chunks sequentially — writing per-chunk
findings back to `REPORTS_DIR/findings/` through the same validated write path
as a dimension-analyst.

**Spawned by:** `dimension-analyst` (on-demand when a source exceeds the token
threshold).

**Inputs:**

| Variable | Description |
| --- | --- |
| `SOURCE` | Path or URL of the oversized document |
| `DIMENSION` | The parent dimension this source belongs to |
| `GOAL_FILE` | Path to the session goal JSON |
| `REPORTS_DIR` | Path to `reports/<topic>/` |

**Outputs:**

| Field | Description |
| --- | --- |
| `finding_files` | Paths of findings written from this source |
| `source_metadata` | Detected content type and chunk count |
| `processing_notes` | Any content that could not be chunked |

**Dependencies:** `scripts/write-finding.sh`, `scripts/wrap-source.sh`.
Model: `haiku`.
