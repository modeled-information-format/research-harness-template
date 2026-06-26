---
title: "Reference: core skills"
diataxis_type: reference
---

# Reference: core skills

Skills are Claude sub-agents that extend the harness with read-only or
structured-write capabilities invoked via `/skill-name` in a session.
All ten listed here are core (non-pack); they ship with the template.

See [dependencies](dependencies.md) for tool installation requirements.

---

## discover

Audits the corpus for coverage gaps, clusters, and stale findings from the
MIF substrate.

**What it does:** Reads `research-index.json` and `knowledge-graph.json`
to surface where the corpus is thin (`--gaps`), where findings clump
(`--clusters`), and which findings have aged past a configurable threshold
(`--stale`). The `--all` flag runs all three passes in sequence.

**When it triggers:** Invoked when the user says "where are my gaps", "what's
stale", "audit the corpus", or similar coverage-audit phrasing.

**Benefit:** Surfaces blind spots and over-researched clusters so follow-on
sessions are directed at genuine gaps rather than re-covering ground.

**Dependencies:** `jq`, `research-index.json`, `knowledge-graph.json`,
`harness.config.json`.

---

## graph

Builds, refreshes, and queries the MIF-native knowledge graph.

**What it does:** Orchestrates `scripts/build-graph.sh` (incremental build),
`scripts/build-concordance.sh` (cross-topic ontological spine),
`scripts/assert-graph-mif.sh` (acceptance gate), `scripts/build-graph-viz.sh`
(standalone HTML visualisation), and `scripts/validate-concordance.sh`.
Query modes (`--node <urn>`, `--between <id1> <id2>`, `--kind`, `--stats`)
read the graph directly with `jq`.

**When it triggers:** Invoked when the user asks to build or refresh the graph,
query entity relationships, visualise the corpus, or validate concordance.

**Benefit:** Exposes typed relationships and cross-topic entity co-occurrences
that flat index search cannot surface.

**Dependencies:** `jq`, `knowledge-graph.json` (built on first run).

---

## lab

Interactive reasoning and hypothesis exploration over the corpus.

**What it does:** Provides four modes — `--seed` (select a finding cluster to
reason from), `--hypothesis` (stress-test a claim against the corpus without
running the full falsification pipeline), `--interrogate` (structured Q&A over
a finding set), and `--namespace` (scope reasoning to one topic). Stays
strictly within the existing corpus; never invents findings or writes to disk.

**When it triggers:** Invoked when the user wants to reason about findings,
explore a hypothesis, or interrogate a cluster interactively before committing
to a full research session.

**Benefit:** Low-cost reasoning pass before expensive orchestrator sessions;
surfaces where evidence is thin before `/falsify` is invoked.

**Handoffs:** `/search`, `/discover`, `/graph`, `/falsify`, `/start`.

**Dependencies:** `jq`, `knowledge-graph.json`.

---

## md-fix

Remediates non-compliant Markdown without suppressing diagnostics.

**What it does:** Runs `python3 .claude/hooks/markdown/md_remediate.py` to
apply mechanical fixes (trailing whitespace, missing blank lines, code-fence
language identifiers, etc.). Supports `--check` (report only), `--dry-run`
(preview changes), `--apply-allowlist` (carry over an existing allowlist), and
`--no-spell` (skip spell-check pass). Never inserts `markdownlint-disable`
comments. Escalates judgment-call violations to a sub-agent.

**When it triggers:** Invoked after markdownlint reports violations, or when
the user asks to fix or clean Markdown files.

**Benefit:** Closes lint violations mechanically, preserving authorial intent
and never hiding failures behind suppression comments.

**Dependencies:** `python3`, `.claude/hooks/markdown/md_remediate.py`.

---

## ontology-manager

Creates, validates, inspects, and converts MIF ontology YAML.

**What it does:** Wraps four scripts in the skill's own `scripts/` directory:
`scaffold_ontology.sh` (generate a starter YAML), `validate_ontology.sh`
(assert conformance against `schemas/mif/ontology.schema.json`),
`inspect_ontology.sh` (print declared types and domain coverage), and
`convert_format.sh` (translate between supported ontology formats). The
vendored schema is `schemas/mif/ontology.schema.json`.

**When it triggers:** Invoked when the user asks to create a new ontology,
validate an existing one, inspect type coverage, or convert ontology format.

**Benefit:** Ensures all domain packs and the `mif-generic` base ontology
remain schema-valid before they are bound to findings.

**Dependencies:** `yq` (mikefarah v4), `jq`, `ajv`.

---

## publish-blog

Renders surviving findings into a publishable blog post.

**What it does:** Runs `scripts/synthesize-artifact.sh` over surviving findings
(verdict ≠ `falsified`) to produce a typed `Artifact`, then renders it via
`scripts/render-artifact.sh` with the `blog` channel. Applies the
citation-integrity gate (`scripts/check-citation-integrity.sh`). The blog
output carries `mifExempt: true` in frontmatter — it is a first-class output
but not held to MIF L3 conformance. Falsified and quarantined findings are
never included.

**When it triggers:** Invoked on "publish blog", "render the blog post",
"generate a blog from findings", or similar phrasing.

**Benefit:** Produces a publication-ready blog post grounded exclusively in
surviving, citation-verified findings without manual prose assembly.

**Dependencies:** `scripts/synthesize-artifact.sh`, `scripts/render-artifact.sh`,
`scripts/check-citation-integrity.sh`.

---

## publish-report

Renders surviving findings into the canonical MIF Level-3 report.

**What it does:** Synthesizes surviving findings into a typed `Artifact`
(`scripts/synthesize-artifact.sh`), runs the adversarial falsification gate
on the report's central claims (`scripts/falsify.sh`), then renders and
validates the L3 report (`scripts/render-artifact.sh` → `scripts/mif-project.sh`).
A `falsified` verdict quarantines the report; it is never shipped. The report
is never MIF-exempt and never carries a hand-authored verification verdict.

**When it triggers:** Invoked on "publish report", "generate the MIF report",
"emit the canonical report", "L3 report from findings", or similar phrasing.

**Benefit:** Produces the harness's source-of-truth report, validated at MIF
L3 with a real (not hand-authored) falsification verdict.

**Dependencies:** `scripts/synthesize-artifact.sh`, `scripts/falsify.sh`,
`scripts/render-artifact.sh`, `scripts/mif-project.sh`.

---

## readme

Creates and updates the per-topic navigation README.

**What it does:** Wraps `scripts/build-topic-readme.sh` for the deterministic
structural backbone (counts, dates, verdict breakdown, dimension rollup, report
and artifact tables), then authors synthesis-grade Key Findings — cross-finding
insights with specifics, not per-finding restatements. Validates with
`--check` before reporting done. Arguments: `--topic <id>` (one topic),
`--all` (every registered topic), `--check` (validate without writing).

**When it triggers:** Invoked after a research session synthesizes, after
findings or reports change, or when the user asks to "update the README",
"reindex the topic readme", "reconcile READMEs", or "regenerate the topic
index".

**Benefit:** Keeps the per-topic README current and synthesis-grade without
manual counting or prose assembly.

**Dependencies:** `scripts/build-topic-readme.sh`, `jq`,
`reports/<topic>/findings/*.json`, `goal.json`, `harness.config.json`.

---

## search

Queries the MIF research index by free text or structured filters.

**What it does:** Runs `jq` filters over `research-index.json` — a flat
projection of all MIF findings carrying `id`, `title`, `namespace`,
`dimension`, `tags`, `verdict`, and `citations`. Supports free-text query
(matched against title and tags), `--tag`, `--namespace`, `--dimension`,
`--verdict`, and `--limit` filters, plus an optional semantic backend
(`--sem`) that falls back to lexical when absent. Rebuilds the index with
`bash scripts/build-index.sh <findings-dir>` if stale.

**When it triggers:** Invoked when the user wants to find findings, look up
what is known about a subject, or asks "what do I have on X", "find findings
about Y", "search research for Z".

**Benefit:** Fast, dependency-light corpus search without reading individual
finding files.

**Dependencies:** `jq`, `research-index.json`.

---

## topics

Lists registered research topics with finding and verdict rollup.

**What it does:** Reads the `topics[]` registry from `harness.config.json`
and joins each topic's `id`, `title`, MIF `namespace`, and `status` against
per-topic finding and verdict counts from `research-index.json`. Arguments:
`-t <query>` (resolve one topic by id, title substring, or namespace),
`--status <status>` (filter by status). A topic with zero findings is reported
as declared-but-unstarted.

**When it triggers:** Invoked when the user asks "what topics do I have",
"list topics", "show the registry", "what am I researching", "topic status",
or wants a corpus overview by topic.

**Benefit:** Single command to orient across the full topic registry with live
finding and verdict counts from the index.

**Note:** `topics` exists as both a skill and a command. The skill includes
finding/verdict rollup from the index; the command (`/topics`) provides a
simpler manifest-only registry view without index data. See
[commands](./commands.md#topics).

**Dependencies:** `jq`, `harness.config.json`, `research-index.json`.
