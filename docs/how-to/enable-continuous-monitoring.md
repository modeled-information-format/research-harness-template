---
id: how-to-enable-continuous-monitoring
type: procedural
created: '2026-07-12T21:00:00Z'
modified: '2026-07-16T17:32:37.781Z'
namespace: how-to/monitoring
title: How to Enable Continuous Research Monitoring for a Topic
tags:
  - how-to
  - continuous-monitoring
  - harness-config
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-12T00:00:00Z'
  recordedAt: '2026-07-12T00:00:00Z'
  ttl: P6M
relationships:
  - type: relates-to
    target: /reference/dependencies.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: Enable Continuous Research Monitoring for a Topic
  entity_type: how-to-guide
provenance:
  '@type': Provenance
  agent: claude-code/claude-fable-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ea77f44f-898f-452b-97c5-a752ed5af5a0
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.211
---

# How to Enable Continuous Research Monitoring for a Topic

Turn on a scheduled, unattended scan of external sources for one of your
topics, with every candidate recommendation routed through a human review
step before anything publishes.

## Prerequisites

- A topic already registered in `harness.config.json`'s `topics[]`.
- Write access to open and merge/close pull requests on this repository.
- If you want either optional rate-limit enhancement, a Semantic Scholar
  or NCBI API key (neither is required for the default path).

Continuous monitoring is a **pack** (`packs/monitoring/continuous-monitor`,
research-harness-template#483) with two independent enablement gates — both
are required, neither alone does anything:

## Step 0 — Enable the `continuous-monitor` pack

```bash
scripts/pack-toggle.sh continuous-monitor on
```

This is the repo-wide master switch (`harness.config.json` `packs[]`). Step 1
below is the *per-topic* opt-in on top of it — a topic can set
`continuousMonitoring.enabled: true` and still have nothing run if this pack
itself is off, and vice versa.

## Step 1 — Add a `continuousMonitoring` block to your topic

Edit `harness.config.json` and add a `continuousMonitoring` object to your
topic's entry in `topics[]`:

```json
"continuousMonitoring": {
  "enabled": true,
  "schedule": "0 6 * * 1",
  "queryTerms": ["your topic's", "key search", "terms"],
  "sources": ["arxiv", "openalex", "crossref", "semantic-scholar", "pubmed", "biorxiv", "gdelt", "hn"],
  "budgetSeconds": 30,
  "maxResultsPerSource": 20,
  "recommendationThreshold": 0.02
}
```

Omit `sources` to run all eight connectors. `schedule` is a standard 5-field
cron expression.

Each `queryTerms[]` entry is an **atomic term or phrase**: connectors dispatch
every entry per their own API's query grammar (phrase-quoted boolean OR in one
request for arXiv/PubMed/GDELT; one request per term, merged and deduplicated,
for HN/OpenAlex/Crossref/Semantic Scholar) — an entry is never flattened into
a shared blob with the other terms. The same terms are a first-class relevance
signal in Interest-Inference scoring, alongside the topic's own concordance
nodes: there a term counts as matched when all of its meaningful tokens appear
in a candidate, so word-order and punctuation variants still match.

## Step 2 — Validate the config

```bash
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s harness.config.schema.json -d harness.config.json
```

Confirm it prints `harness.config.json valid`.

## Step 3 — Install the monitoring workflows (instantiated clones)

`copier.yml` excludes `.github/workflows/*` from instantiation, so an
instantiated clone does **not** receive `monitor.yml`/`monitor-gate.yml`
automatically (#517). The canonical workflow sources ship with the pack;
materialize them into your clone's `.github/workflows/`:

```bash
bash scripts/install-monitoring-workflows.sh
```

Re-run it after any `copier update` (it is idempotent; `--check` reports
drift without writing — `verify.sh`'s `gate_monitoring_workflow_sync` fails
if an installed copy drifts from its pack source). The template repo itself
already carries live copies; this step is a no-op there.

To deliberately customize an installed copy (e.g. a different cron cadence),
add a `# harness-workflow: unmanaged` comment to it: the installer then
leaves that file alone and the sync gate waives byte-identity for it — you
own keeping the fork current from then on.

## Step 4 — Commit and push

```bash
git add harness.config.json .github/workflows/monitor.yml .github/workflows/monitor-gate.yml
git commit -m "feat: enable continuous monitoring for <your-topic-id>"
git push
```

The scheduled workflow (`.github/workflows/monitor.yml`) picks up your
topic on its next scheduled run, or trigger it immediately:

```bash
gh workflow run continuous-monitoring --field topic=<your-topic-id>
```

## Step 5 — Review the pull request it opens

Each run that produces at least one candidate opens one pull request
titled `monitor(<topic>): N candidate recommendation(s) for review`,
listing every candidate with its mode (`interest-match` or `gap-detect`)
and score. Read the list.

## Step 6 — Accept or reject the batch

- **Merge the pull request** to accept every recommendation in it.
  `interest-match` recommendations publish as real findings under
  `reports/<topic>/findings/` (verdict `inconclusive`, pending a full
  `/falsify` pass) through the same `publish-report`/`publish-blog`
  skills every other finding uses. `gap-detect` recommendations are not
  published as findings; they land in
  `reports/<topic>/monitoring/recommended-research-areas.jsonl` as
  research-area suggestions for you to act on separately.
- **Close the pull request without merging** to reject the whole batch.
  Every recommendation is recorded in
  `reports/<topic>/monitoring/continuity-log.jsonl`.

## Step 7 — Check the Continuity Log for a skipped or failed source

```bash
jq -c 'select(.event_type != "gate_rejected")' \
  reports/<topic>/monitoring/continuity-log.jsonl
```

Each line names the source, the reason, and (for a budget breach) the
configured `budgetSeconds`.

Continuous monitoring is now enabled for the topic, running on the
configured schedule with every recommendation gated through PR review.

<!--
Operational note: the monitor.yml/monitor-gate.yml workflows request
contents:write and pull-requests:write via the AUTOMERGE_CLIENT_APP_ID
app-token pattern (repos/.github/auth/apps.json's `automerge` app,
already installed org-wide with exactly this permission set for
Dependabot/catalog-hub auto-merge) -- not CI_CLIENT_APP_ID, which is
deliberately read-only. This mint was live-verified in Actions CI via a
manual workflow_dispatch run (2026-07-12): the token mint, engine fetch,
ontology vendoring, and pipeline invocation all succeeded. Every
pipeline script itself (run-monitoring.sh, run-gate-and-publish.sh,
every stage script) had already been live-tested end-to-end against
real data before that.

MIF Level 2: namespace, modified, temporal validity (ttl P6M --
continuous-monitoring is new capability, shorter review window than a
mature procedure's usual P1Y), and a typed relates-to link to
/reference/dependencies.md, which now documents each connector's
endpoint and opt-in enhancement flags (research-harness-template#455).
-->
