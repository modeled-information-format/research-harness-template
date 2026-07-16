---
name: continuous-monitor
description: "Unattended, scheduled monitoring of external research sources (arXiv, OpenAlex, Crossref, Semantic Scholar, PubMed, bioRxiv/medRxiv, GDELT, Hacker News) for a topic, gated end to end through a mandatory human Editorial Gate before anything publishes. An OPTIONAL methodology pack (enable the `continuous-monitor` pack AND set `continuousMonitoring.enabled: true` on the topic). Use this skill when the user wants to enable, inspect, or manually run continuous research monitoring for a topic, review a monitoring run's candidate recommendations, or check the Continuity Log for a skipped/failed source. Triggers on 'continuous monitoring', 'monitor this topic', 'schedule research monitoring', 'check for new sources', 'run the monitoring pipeline', 'review monitoring recommendations'."
version: 0.15.3
argument-hint: "<topic-id> [<run-id>]"
allowed-tools: Read, Bash, Glob, Grep
---

# continuous-monitor — scheduled external-source monitoring with a mandatory human gate

Continuous monitoring is a **methodology pack** (SPEC §7b): it contributes a
background research-discovery capability the same way `competitive-analysis` or
`trend-modeling` contribute a research dimension, except its normal caller is a
scheduled GitHub Actions workflow rather than an interactive dimension-analyst
fan-out. Enable the bundled `continuous-monitor` pack (`scripts/pack-toggle.sh
continuous-monitor on`) AND opt a topic in via its own `continuousMonitoring`
block in `harness.config.json` (see
[How to enable continuous research monitoring](../../../../../docs/how-to/enable-continuous-monitoring.md)) —
**both** gates must be on; either one alone does nothing (research-harness-template#483).

## Why this pack is invoked two different ways

Every other pack in this harness is invoked by an agent reading its `SKILL.md`
inside an interactive Claude Code session. This pack's actual production
callers are `.github/workflows/monitor.yml` (Phase 1: run the pipeline, open a
review PR) and `.github/workflows/monitor-gate.yml` (Phase 2: react to that PR
closing, publish or reject) — both invoke this pack's `scripts/` directly by
path, exactly the way `packs/channels/diataxis`'s `scripts/render-diataxis.sh`
is invoked directly rather than through a chat turn. A pack's `scripts/`
directory has always been callable this way; continuous monitoring is simply
the first pack whose primary caller is unattended CI rather than a human
prompt. This `SKILL.md` documents the same pipeline for interactive/manual use
(inspecting a run, re-triggering it by hand, debugging a stuck topic) — it is
not a second implementation, just the human-facing entry point onto the exact
same scripts the workflows call.

## Pipeline

```text
Source Connectors -> Interest-Inference -> Recommendation Engine
  -> [review PR: the Editorial Gate] -> Output Router -> reports/<topic>/findings/
```

| Script | What it does |
| --- | --- |
| `scripts/run-monitoring.sh <topic> <run-id>` | Phase 1 orchestrator: checks the `continuous-monitor` pack is enabled AND the topic's own `continuousMonitoring.enabled`, runs enabled Source Connectors under a budget, rebuilds the concordance/index, scores via Interest-Inference, writes `reports/<topic>/monitoring/runs/<run-id>/recommendations.json`. Stops before the Editorial Gate. |
| `scripts/run-with-budget.sh` | Wraps one connector in a hard wall-clock `timeout`; fails closed and logs to the Continuity Log rather than partial-succeeding. |
| `scripts/connectors/{arxiv,openalex,crossref,semantic-scholar,pubmed,biorxiv,gdelt,hn}.sh` | The eight keyless Source Connectors. Query-taking connectors accept `<query>` as a JSON array of atomic terms/phrases (what `run-monitoring.sh` passes from `queryTerms[]`) or a plain string treated as one term, and dispatch per the target API's own query grammar (#513): phrase-quoted boolean OR in one request (arXiv, PubMed, GDELT) or one request per term with merge/dedup (HN, OpenAlex, Crossref, Semantic Scholar). GDELT detects its HTTP-200 plaintext rate-limit notice and retries once after `GDELT_RETRY_DELAY_SECONDS` (default 6) before failing closed with the true cause (#515). |
| `scripts/interest-inference.sh` | Scores candidates against the monitored topic's own concordance nodes (`--topic`, #514) plus the topic's queryTerms as a first-class signal, with a TF-IDF fallback when neither matches. |
| `scripts/recommend.sh` | `interest-match` (rank scored candidates) and `gap-detect` (coverage-gap suggestions) modes. |
| `scripts/editorial-gate.sh` | The mandatory human-review checkpoint: splits recommendations into accepted/rejected per a decisions map, fail-safe default (no decision = rejected). |
| `scripts/output-router.sh` | Hands Editorial-Gate-accepted recommendations to the harness's existing `scripts/write-finding.sh`/`scripts/check-citation-integrity.sh` — no bespoke publish path. |
| `scripts/run-gate-and-publish.sh <topic> <run-id> <recommendations.json> <merged>` | Phase 2 orchestrator: builds a whole-batch accept/reject decision from a PR's merged state, runs `editorial-gate.sh` then `output-router.sh`. |

## Manual invocation

Run a monitoring pass for one topic by hand (the same call `monitor.yml` makes):

```bash
bash "$CLAUDE_PROJECT_DIR/packs/monitoring/continuous-monitor/scripts/run-monitoring.sh" <topic-id> "run-$(date -u +%Y%m%dT%H%M%SZ)-manual"
```

Inspect the result:

```bash
jq . "reports/<topic-id>/monitoring/runs/<run-id>/recommendations.json"
```

Every recommendation reaching this file has already passed schema validation
(`schemas/monitoring-recommendation.schema.json`) but has **not** yet passed
the Editorial Gate — merging or closing the PR `monitor.yml` opens from it is
what decides accept/reject; do not hand-run `output-router.sh` against it
without going through `editorial-gate.sh` first (it enforces NFR6: every
recommendation must already carry a valid gate stamp).

Check the Continuity Log for a skipped or failed source:

```bash
jq -c 'select(.event_type != "gate_rejected")' "reports/<topic-id>/monitoring/continuity-log.jsonl"
```

## Constraints

- Every connector is keyless by default (NFR2/NFR3); `SEMANTIC_SCHOLAR_API_KEY`/
  `NCBI_API_KEY` are optional rate-limit enhancements, never required.
- Every recommendation carries at least one MIF citation (NFR5), enforced in
  code — a citation-less recommendation raises rather than being produced.
- No recommendation reaches `reports/<topic>/findings/` without an explicit
  Editorial Gate accept (NFR6) — the fail-safe default on an undecided
  recommendation is reject, never accept-by-omission.
