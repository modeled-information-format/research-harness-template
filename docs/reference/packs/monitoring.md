---
id: reference-packs-monitoring
type: semantic
created: '2026-07-14T02:24:39.962Z'
modified: '2026-07-14T13:17:40.615Z'
namespace: docs/reference/packs
tags:
  - documentation
  - reference
title: "Monitoring pack"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-14T02:24:39.962Z'
  ttl: P6M
  recordedAt: '2026-07-14T02:24:39.962Z'
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:0cbc1511-6559-422f-9909-b895e058b431
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.209
---

# Monitoring pack

The monitoring pack is a methodology capability: unattended, scheduled scanning of
external sources for a topic, scored against the concordance and ranked into candidate
recommendations, every one of which passes through a mandatory human Editorial Gate
before it is ever projected into a real MIF finding.

**Repackaged from core to a pack (research-harness-template#483).** Epic #416 originally
shipped this as `scripts/monitoring/**`, gated by a bespoke `continuousMonitoring` config
flag, rather than a `packs/<family>/<skill>/` plugin — a real deviation from
[Explanation: pack structure](../../explanation/pack-structure.md)'s stated convention.
It is now `packs/monitoring/continuous-monitor/`, wired through `harness.config.json`
`packs[]` like every other pack.

**Invoked two different ways, deliberately.** Every other pack in this harness is
invoked by an agent reading its `SKILL.md` in an interactive session. This pack's actual
production callers are the two unattended GitHub Actions workflows,
`.github/workflows/monitor.yml` (Phase 1: run the pipeline, open a review PR) and
`.github/workflows/monitor-gate.yml` (Phase 2: react to that PR closing, publish or
reject) — both call this pack's `scripts/` directly by path. This is not a new wiring
convention: a pack's `scripts/` directory has always been directly callable this way
(`packs/channels/diataxis/scripts/render-diataxis.sh` is the existing precedent). The
pack's `SKILL.md` documents the identical pipeline for interactive/manual invocation —
inspecting a run, re-triggering it by hand, debugging a stuck topic — it is not a second
implementation.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## continuous-monitor

**Version:** 0.15.3

**Source:** [`packs/monitoring/continuous-monitor/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/monitoring/continuous-monitor)

### Purpose

Runs eight keyless Source Connectors (arXiv, OpenAlex, Crossref, Semantic Scholar,
PubMed, bioRxiv/medRxiv, GDELT, Hacker News) under a per-connector wall-clock budget,
rebuilds the concordance/index (AD-2 ordering), scores candidates via Interest-Inference
(with a TF-IDF fallback for uncovered topics), and ranks them through the Recommendation
Engine (`interest-match` and `gap-detect` modes). The review pull request the scheduled
workflow opens from that output **is** the Editorial Gate (ADR-0019): merging it accepts
every recommendation in it into `reports/<topic>/findings/`; closing it without merging
rejects the whole batch to the Continuity Log.

### When to use

Enable `continuous-monitor` when a topic's research should keep discovering new
candidate sources between sessions, on a schedule, without an operator needing to
remember to re-run `/start` — but every candidate must still clear a human review gate
before it becomes a real finding.

### What it provides

| Stage | Script | What it does |
| --- | --- | --- |
| Orchestration (Phase 1) | `scripts/run-monitoring.sh` | Checks both enablement gates (below), runs Source Connectors under budget, rebuilds concordance/index, scores, writes `recommendations.json`. |
| Budget enforcement | `scripts/run-with-budget.sh` | Wraps one connector in a hard `timeout`; fails closed, logs to the Continuity Log. |
| Source Connectors | `scripts/connectors/{arxiv,openalex,crossref,semantic-scholar,pubmed,biorxiv,gdelt,hn}.sh` | Eight keyless clients (documented per-source in [dependencies.md](../dependencies.md#continuous-monitoring-source-apis-optional)). |
| Scoring | `scripts/interest-inference.sh` | Scores candidates against `reports/concordance.json`, TF-IDF fallback for uncovered topics. |
| Ranking | `scripts/recommend.sh` | `interest-match` and `gap-detect` modes; every recommendation carries at least one MIF citation (NFR5), enforced in code. |
| Editorial Gate | `scripts/editorial-gate.sh` | Splits recommendations into accepted/rejected per an explicit decisions map; fail-safe default (no decision = rejected). |
| Publish | `scripts/output-router.sh` | Hands accepted recommendations to `scripts/write-finding.sh`/`scripts/check-citation-integrity.sh` unmodified; `gap-detect` suggestions go to `reports/<topic>/monitoring/recommended-research-areas.jsonl` instead. |
| Orchestration (Phase 2) | `scripts/run-gate-and-publish.sh` | Builds a whole-batch accept/reject decision from a PR's merged state, runs `editorial-gate.sh` then `output-router.sh`. |

### Dependencies

`jq`, `python3`, `curl`, `timeout`, `ajv-cli` + `ajv-formats` (the Continuity Log's
schema gate hard-requires it), `git` (the AD-2 staleness check). Every connector is
keyless by design (NFR2/NFR3); `SEMANTIC_SCHOLAR_API_KEY`/`NCBI_API_KEY` are optional
rate-limit enhancements, never required.

### Constraints

- **Two independent gates, both required.** `harness.config.json` `packs[]` must have
  `{"name": "continuous-monitor", "enabled": true}` (the capability must exist in this
  instance at all) **and** the topic's own `continuousMonitoring.enabled` must be `true`
  (this specific topic opts in). Either one off means the scheduled workflow does
  nothing for that topic — `scripts/run-monitoring.sh` checks the `packs[]` gate first,
  before ever consulting the per-topic block.
- Ships disabled; enable with `scripts/pack-toggle.sh continuous-monitor on`, then opt
  a topic in per [How to enable continuous research monitoring](../../how-to/enable-continuous-monitoring.md).
- No recommendation reaches `reports/<topic>/findings/` without an explicit Editorial
  Gate accept (NFR6) — undecided is always rejected, never accepted by omission.
- Scheduling precision is bounded by GitHub Actions' own `schedule:` trigger (ADR-0019)
  — fine for a weekly/periodic cadence, not for sub-hour polling.

### Goals

- Discover candidate sources for a topic on a schedule, without requiring an open,
  interactive Claude Code session.
- Never publish a candidate without an explicit human accept, recorded via the review
  PR the scheduled workflow opens.
- Reuse the harness's existing publish surfaces (`write-finding.sh`,
  `check-citation-integrity.sh`, the `report`/`blog` channels) rather than a bespoke
  publish path.
- Fail closed on every ambiguous case: a connector timeout, an unscored candidate, or
  an undecided recommendation is always treated as "did not happen" / "rejected," never
  partially applied.

### Enable

```sh
scripts/pack-toggle.sh continuous-monitor on
```

Then add a `continuousMonitoring` block to the target topic in `harness.config.json` —
see [How to enable continuous research monitoring](../../how-to/enable-continuous-monitoring.md).
