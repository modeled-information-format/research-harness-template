---
id: reference-engine-cli
type: semantic
created: '2026-07-05T10:16:37-04:00'
modified: '2026-07-05T10:16:37-04:00'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: mif-rh-cli"
diataxis_type: reference
---

# Reference: mif-rh-cli

`mif-rh-cli` is the compiled ontology-resolution and classification engine
for research-harness-template corpora (ADR-0016), built from the `mif-rs`
repository. `scripts/resolve-ontology.sh` and `scripts/ontology-review.sh`
delegate to it; it is hard-required, with no bash fallback. Install it with
`scripts/fetch-engine.sh` (attested, fail-closed), put a `mif-rh-cli` on
`PATH`, or set `MIF_RH_CLI` to an explicit binary path. Version floor:
`0.3.1`. Flags below are the binary's own `--help` output.

For the read-only MCP server that exposes a subset of this engine's data to
Claude Code sessions, see [mcp-server.md](mcp-server.md). For the operator
workflow across these subcommands, see
[How to run the classification engine loop](../how-to/run-the-classification-engine-loop.md).

## Global options

```text
mif-rh-cli [OPTIONS] <COMMAND>
```

| Option | Description |
| --- | --- |
| `--format <FORMAT>` | Error rendering format: `pretty` or `json`. Defaults to `pretty` on a terminal and `json` otherwise. |
| `-h`, `--help` | Print help. |
| `-V`, `--version` | Print version. |

## resolve

Resolve one finding against its topic's bound ontologies.

```text
mif-rh-cli resolve [OPTIONS] <FINDING>
```

| Argument / option | Description |
| --- | --- |
| `<FINDING>` | Path to the finding JSON file. |
| `--topic <TOPIC>` | The finding's topic. If omitted, derived from `finding`'s path (`reports/<topic>/...`). |
| `--catalog <CATALOG>` | Path to the ontology catalog. Defaults to `.claude/enabled-packs.json`. |
| `--config <CONFIG>` | Path to the harness config. Defaults to `harness.config.json`. |
| `--map <MAP>` | Path to write the updated `ontology-map.json` record to. If omitted and the topic's `reports/<topic>/` directory exists, defaults to `reports/<topic>/ontology-map.json`; otherwise no map is written. |
| `--root <ROOT>` | Base directory ontology catalog `source` paths resolve against. Defaults to the current directory. |

## review

Rebuild `ontology-map.json` for one or more topics and aggregate coverage.

```text
mif-rh-cli review [OPTIONS]
```

| Option | Description |
| --- | --- |
| `--topic <TOPIC>` | Topic to review. Repeatable. Defaults to every configured topic. |
| `--strict` | Fail only on invalid/unresolved mappings, never on discovery-only/untyped findings alone. |
| `--reports-dir <REPORTS_DIR>` | Root `reports/` directory. Defaults to `reports`. |
| `--config <CONFIG>` | Path to the harness config. Defaults to `harness.config.json`. |
| `--catalog <CATALOG>` | Path to the ontology catalog. Defaults to `.claude/enabled-packs.json`. |
| `--followup <FOLLOWUP>` | Path to write a backlog of findings that still need attention. |
| `--root <ROOT>` | Base directory ontology catalog `source` paths resolve against. Defaults to the current directory. |
| `--relationship-script <RELATIONSHIP_SCRIPT>` | Path to `check-relationship-targets.sh`, run once, corpus-wide, after classification. Defaults to `<root>/scripts/check-relationship-targets.sh` if that file exists; otherwise the check is skipped. Unix-only: spawned directly via its `#!` shebang, which Windows does not honor. |
| `--build-index` | Rebuild the corpus-wide search index (every topic in `config`, not just `--topic`) after classification, for `mif-rh-mcp`'s `search`/`find_similar` tools. Off by default: index building re-embeds every finding and is far more expensive than classification alone. |
| `--index <INDEX>` | Path to the search index database. Defaults to `<reports-dir>/_meta/search-index.sqlite`. |
| `--suggest` | After classification, write tier-annotated entity-type suggestions for this review's not-durably-stamped findings to `<reports-dir>/_meta/suggestions/<topic>.json` (preserving any confirmed/rejected verdicts), and record tier-3 misses in the index for `expansion-candidates`. Off by default: suggesting re-embeds findings, which the fail-closed classification path must never pay for. |
| `--calibration <CALIBRATION>` | Path to the confidence-calibration artifact used by `--suggest`. Defaults to `<reports-dir>/_meta/confidence-calibration.json`. |

## calibrate

Derive the corpus's confidence-calibration artifact from its stamped
findings (`stamped-quantile-v1`, MIF ADR-020 PDD-2).

```text
mif-rh-cli calibrate [OPTIONS]
```

| Option | Description |
| --- | --- |
| `--reports-dir <REPORTS_DIR>` | Root `reports/` directory. Defaults to `reports`. |
| `--config <CONFIG>` | Path to the harness config. Defaults to `harness.config.json`. |
| `--catalog <CATALOG>` | Path to the ontology catalog. Defaults to `.claude/enabled-packs.json`. |
| `--root <ROOT>` | Base directory ontology catalog `source` paths resolve against. Defaults to the current directory. |
| `--target-precision <TARGET_PRECISION>` | Minimum empirical top-1 precision the tier-1 gate must achieve. Default `0.95`. |
| `--tier2-target <TIER2_TARGET>` | Minimum gold-in-candidates rate above the tier-2 floor. Default `0.5`. |
| `--sample <SAMPLE>` | Cap the number of stamped samples used (deterministic, seed-keyed). Defaults to every stamped finding. |
| `--seed <SEED>` | Seed for the deterministic sample selection. Default `0`. |
| `--out <OUT>` | Where to write the calibration artifact. Defaults to `<reports-dir>/_meta/confidence-calibration.json`. |

If no threshold meets `--target-precision`, the command fails loudly rather
than writing an artifact. The output shape is
[`CalibrationConfig`](mcp-server.md#confidence-calibrationjson).

## suggest-type

Suggest candidate entity types for a text or a finding, ranked by embedding
similarity with confidence tiers (MIF ADR-020). Prints a JSON array of
hypotheses; never writes to `reports/`.

```text
mif-rh-cli suggest-type [OPTIONS] [TEXT]
```

| Argument / option | Description |
| --- | --- |
| `[TEXT]` | The text to classify. Omit when using `--finding`. |
| `--finding <FINDING>` | Path to a finding JSON file whose indexed text (discovery text, else its entity's name) is the query. |
| `--topic <TOPIC>` | The topic whose bound ontologies supply candidate entity types. Required with `TEXT`; with `--finding` it may instead derive from the finding's `reports/<topic>/...` path. |
| `--catalog <CATALOG>` | Path to the ontology catalog. Defaults to `.claude/enabled-packs.json`. |
| `--config <CONFIG>` | Path to the harness config. Defaults to `harness.config.json`. |
| `--root <ROOT>` | Base directory ontology catalog `source` paths resolve against. Defaults to the current directory. |
| `--limit <LIMIT>` | Maximum number of ranked candidates to return. Default `10`. |
| `--calibration <CALIBRATION>` | Path to the confidence-calibration artifact. Defaults to `reports/_meta/confidence-calibration.json`; when absent, conservative built-in thresholds apply and candidates carry `calibrated: false`. |
| `--record` | Record the query as a tier-3 miss in the search index when its best candidate is `trigger_expansion` (or no candidate exists), feeding `expansion-candidates`. Requires `--finding` (a miss is a property of a finding, not of ad-hoc text). |
| `--index <INDEX>` | Path to the search index database `--record` writes to. Defaults to `reports/_meta/search-index.sqlite`. |

Each returned candidate is one [`TypeSuggestion`](mcp-server.md#suggest_type).

## expansion-candidates

Cluster recorded tier-3 misses into ontology-expansion candidates (recurring,
mutually-similar misses across runs, never a single miss). Prints JSON, or
writes it with `--out` for `author-ontology.sh --from-clusters`.

```text
mif-rh-cli expansion-candidates [OPTIONS]
```

| Option | Description |
| --- | --- |
| `--index <INDEX>` | Path to the search index database holding recorded misses. Defaults to `reports/_meta/search-index.sqlite`. |
| `--calibration <CALIBRATION>` | Path to the confidence-calibration artifact carrying the clustering knobs. Defaults to `reports/_meta/confidence-calibration.json`. |
| `--out <OUT>` | Write the clusters JSON here instead of stdout. |
