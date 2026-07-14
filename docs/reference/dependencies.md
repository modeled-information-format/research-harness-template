---
id: reference-dependencies
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-14T02:29:28.000Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: dependencies and requirements"
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
    '@id': urn:mif:activity:claude-code-session:581ee0b6-ce7b-4099-a6dd-2fbb44ce2e1c
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Reference: dependencies and requirements

This page is the authoritative list of every external tool and runtime the
harness and its packs need to function. It tells an adopter exactly what to
install, the minimum version, and which component requires it. For per-pack
detail see [the pack catalog](packs/index.md); for the tools each script calls
see [scripts](scripts.md).

## How versions were verified

Versions below were checked **at authoring time on the development host and
against the CI workflow**, not recalled from memory:

- Runtime floors marked *repo-declared* come from `.github/workflows/ci.yml`
  (`python-version: '3.14'`, `node-version: '24'`, `yq` pinned to
  `v4.53.3`).
- *Verified present* versions are the output of the tool's own `--version` on
  the host where these docs were authored. Reproduce any of them with the
  command in the "Check" column.
- The harness pins **no upper bound** on the optional CLIs (`gh`, `pandoc`,
  `nlm`, `jq`): install the current stable release from the tool's official
  source. The "Minimum" column states the floor the harness actually relies on;
  where none is declared, use a currently-supported release.

## Core runtime (always required)

These are needed to clone and run the engine itself — independent of which packs
you enable.

| Tool | Minimum | Required by | Check |
| --- | --- | --- | --- |
| `git` | any supported | Clone the template; `git grep` identity-leak gate in `verify.sh`; `git archive` release tarball (`release.yml`) | `git --version` |
| `mif-rh-cli` | `0.7.0+` — *repo-pinned in `scripts/fetch-engine.sh`* | Ontology classification (`resolve-ontology.sh`, `ontology-review.sh` delegate to it, ADR-0016) plus the suggest/calibrate loop — see [engine-cli.md](engine-cli.md) for the full subcommand surface and [mcp-server.md](mcp-server.md) for its MCP server | `mif-rh-cli --version` |
| `jq` | 1.7+ (1.8.2 verified) | The engine — index, graph, findings, render, falsify (most scripts) | `jq --version` |
| `yq` (mikefarah) | `v4.53.3` — *repo-pinned in CI* (4.53.3 verified) | YAML frontmatter and ontology YAML in `verify.sh`, `mif-project.sh`, `validate-concordance.sh`; ontology catalog materialization in `sync-packs.sh` | `yq --version` |
| `node` | Active LTS — *repo-declared* `'24'` (24.x verified) | `npm` to install the validation toolchain (`ajv-cli`, `ajv-formats`, `markdownlint-cli2`); `npx` for Mermaid | `node --version` |
| `python3` | 3.14 — *repo-declared* (3.14 verified) | `codegen/gen-models.sh` + `bundle_schema.py` (self-provisioned pinned venv), `sync-packs.sh` (embedded materialization), `.claude/hooks/markdown/md_remediate.py` | `python3 --version` |

`jq` and `yq` carry the heaviest load: `jq` drives the index, graph, session,
and render scripts; `yq` reads every YAML input. If the engine's schema gates
are to run, both must be present.

### Pins deliberately held back

Two pins were evaluated for a bump and intentionally left in place — noted
here so a future contributor doesn't "fix" them without the context:

- **`node` stays at `'24'`.** `v26` exists but is not yet an LTS line
  (`lts: false` per Node's release schedule); it reaches Active LTS on
  2026-10-28. Revisit once it does.
- **The npm `overrides.js-yaml` pin stays at `4.2.0`.** It exists to force a
  version above `js-yaml`'s CVE-2026-53550 / GHSA-h67p-54hq-rp68 vulnerable
  range (`<= 4.1.1`), a transitive pull-in via `gray-matter`'s hard pin on
  `js-yaml ^3.13.1`. The latest `5.2.1` was tried and reverted: `@astrojs/starlight`
  does a default import (`import yaml from 'js-yaml'`) that `5.x` no longer
  exports, which breaks `npm run build` outright. `4.2.0` already remediates
  the CVE, so staying on it is not a security regression — re-evaluate when
  `@astrojs/starlight` drops (or updates) its `js-yaml` default import.

## Validation toolchain (required for schema validation and docs)

`ajv` validates JSON against the vendored MIF schema closure, and the
documentation gate runs `markdownlint-cli2`. CI installs both globally with
`npm`. `ajv` is **not** only for the `verify.sh` gate — the finding and session
scripts that write or reconcile MIF data (`write-finding.sh`, `wrap-source.sh`,
`reconcile-session.sh`, `import-corpus.sh`, `render-artifact.sh`, and others)
validate with `ajv` too, so it is effectively a core dependency.

| Tool | Minimum | Required by | Install / Check |
| --- | --- | --- | --- |
| `ajv-cli` + `ajv-formats` | current | `verify.sh` plus the finding/session scripts (`write-finding.sh`, `wrap-source.sh`, `reconcile-session.sh`, …) — schema validation against draft-2020 schemas | `npm install -g ajv-cli ajv-formats` · `ajv help` |
| `markdownlint-cli2` | current | Documentation lint gate (`.markdownlint-cli2.jsonc`) | `npm install -g markdownlint-cli2` · `markdownlint-cli2 --version` |

## Document tooling (`mif-docs-plugin`)

The harness's document-level frontmatter authoring, validation, and provenance
(as distinct from the findings/knowledge-graph schema substrate above, which
stays harness-local per ADR-0002) route through the
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin),
declared as a `marketplaces[]` entry in `harness.config.json` and consumed by
several `packs[]` genres already (`docs/reference/packs/reports.md`).

| Tool | Minimum | Required by | Check |
| --- | --- | --- | --- |
| `mif-docs-plugin` | pinned ref in `harness.config.json` `marketplaces[]` (`mif-docs`) | `mif-frontmatter`, `mif-validate`, `mif-provenance` skills; every externally-sourced report genre | n/a — Claude Code plugin, resolved via the marketplace pin |
| `mif-mcp` (from `mif-docs-plugin`) | matches the plugin pin above | `.mcp.json`'s `mif-mcp` server — `validate_mif_document`, `ingest_mif_document`, `resolve_ontology_reference`, `search_documents`, `find_similar_documents`, `corpus_stats` | `which mif-mcp` |

Provenance capture (`mif-provenance`'s hook-observed stamping) is opt-in and
configured via the `mifProvenance` key in `.claude/settings.json`
(`capture`/`stamp`) — this repo enables it by default
(`capture: true, stamp: "auto"`) so a document authored in a **fresh** harness
session, with capture already active when the session started, gets witnessed
provenance instead of only asserted frontmatter. This does **not** retroactively
cover a session where capture was just enabled or the plugin just updated —
Claude Code snapshots the hook set at session start, so enablement mid-session
does not wire hooks into that already-running session. Run the `mif-provenance`
`status` command to confirm hooks are actually active for the current session
before relying on stamping; if `status` reports no `session_start` line,
restart the session rather than continuing to author and hoping.

## Instantiation (the recommended adoption path)

The harness is a [Copier](https://copier.readthedocs.io/) template. The
recommended way to adopt it is `copier copy`, which records a
`.copier-answers.yml` (commit it — it is the merge base for `copier update`) so you
can later pull template improvements with `copier update` — see
[How to instantiate the harness](../how-to/instantiate-the-harness.md).

| Tool | Minimum | Required by | Install / Check |
| --- | --- | --- | --- |
| `copier` | 9.x (9.15.2 verified) | Instantiating and updating the template | `pipx install copier` · `copier --version` |

The GitHub "Use this template" path does not need `copier`, but `copier update`
will not work until you adopt Copier.

## Release verification (recommended)

| Tool | Minimum | Required by | Check |
| --- | --- | --- | --- |
| `gh` (GitHub CLI) | 2.x with `attestation` subcommand (2.95.0 verified) | Verifying SLSA build-provenance attestations on releases | `gh --version` |

`gh attestation verify` is the supported way to confirm a downloaded release
artifact. See the procedure in
[How to verify a release](../how-to/verify-a-release.md) and the policy in
[`SECURITY.md`](https://github.com/modeled-information-format/research-harness-template/blob/main/SECURITY.md).

## Optional channel packs

These tools are only needed if you enable the channel pack that uses them. Each
pack degrades gracefully — it reports the missing tool and stops rather than
erroring — so a clone without these tools still runs the core engine and every
pack that does not need them.

| Tool | Minimum | Required by pack | Check |
| --- | --- | --- | --- |
| `gh` (GitHub CLI) | 2.x (2.95.0 verified) | `github-discuss`, `github-issues` | `gh --version` |
| `nlm` (NotebookLM CLI) | 0.7.x (0.7.7 verified) | `notebooklm` | `nlm --version` |
| `pandoc` | 3.x (3.10 verified) | `pdf` | `pandoc --version` |
| PDF engine — `xelatex` / `weasyprint` / `wkhtmltopdf` | any one | `pdf` (pandoc needs an engine) | check whichever you installed, e.g. `xelatex --version`, `weasyprint --version`, or `wkhtmltopdf --version` |
| `@mermaid-js/mermaid-cli` (run via `npx`) | current | `pdf` diagrams; optional in `engineering`, `trend-analysis`, `competitive-analysis`, `trend-modeling` | `npx --yes @mermaid-js/mermaid-cli --version` |

Notes:

- The `notebooklm` pack drives the NotebookLM CLI, distributed as the `nlm`
  binary; the goal's `notebooklm-mcp-cli` naming refers to the same NotebookLM
  command-line ecosystem. After install, authenticate once with `nlm login`.
- Mermaid rendering is independently optional inside the `pdf` pack: if
  `mermaid-cli` is unavailable or a diagram fails, the pack leaves the raw
  diagram block as text and continues.
- The `pdf` pack needs **both** `pandoc` and at least one PDF engine; install
  one engine (for example `brew install --cask mactex-no-gui`, or
  `pip3 install weasyprint`).

## Continuous monitoring source APIs (optional)

Every connector (`packs/monitoring/continuous-monitor/scripts/connectors/`) is keyless by design
(NFR2/NFR3): each is a plain `curl` + `jq` client against a free REST/RSS
API, no account or payment required for its default path. The pipeline
around the connectors does add two hard runtime dependencies beyond the
core toolchain: `timeout` (`packs/monitoring/continuous-monitor/scripts/run-with-budget.sh`'s
per-connector budget enforcement) and `ajv`/`ajv-formats` (the Continuity
Log's schema validation, `packs/monitoring/continuous-monitor/scripts/lib/continuity-log.sh` —
already a required part of this repo's toolchain per the table above, but
called out here since a from-scratch environment running only the
connectors in isolation would still need it).

| Connector | Endpoint | Keyless default | Opt-in enhancement |
| --- | --- | --- | --- |
| `arxiv.sh` | `export.arxiv.org/api/query` (Atom) | Yes, no rate-limit tier | none |
| `openalex.sh` | `api.openalex.org/works` | Yes | `mailto` param (already sent) joins the polite pool; no key exists |
| `crossref.sh` | `api.crossref.org/works` | Yes | `mailto` param (already sent) joins the polite pool; no key exists |
| `semantic-scholar.sh` | `api.semanticscholar.org/graph/v1` | Yes | `SEMANTIC_SCHOLAR_API_KEY` env var raises the rate limit; unset by default, never required |
| `pubmed.sh` | `eutils.ncbi.nlm.nih.gov/entrez/eutils` | Yes | `NCBI_API_KEY` env var raises the rate limit; unset by default, never required |
| `biorxiv.sh` | `api.biorxiv.org/details` | Yes | none |
| `gdelt.sh` | `api.gdeltproject.org/api/v2/doc/doc` | Yes | none |
| `hn.sh` | `hn.algolia.com/api/v1` | Yes | none |

Both optional environment variables default unset, keeping every connector on
its free/keyless path unless an operator deliberately opts in — per NFR2, a
paid or higher-tier source is never the default. Public keyless APIs
(Semantic Scholar and GDELT observed directly) apply their own rate limits
regardless of key; a connector that hits one fails closed with the HTTP
status on stderr rather than returning a silently truncated or stale result
(Story: Continuity Log + fail-closed ingestion budget, research-harness-template#421,
is what a monitoring run wires this into).

## Install quick reference

The harness does not bundle these tools. Install the current stable release from
each project's official source — for example on macOS with Homebrew plus the
package-manager installs CI uses:

```sh
# Core runtime + release verification
brew install git jq yq node python pandoc gh
# Validation toolchain (CI installs these globally with npm)
npm install -g ajv-cli ajv-formats markdownlint-cli2
# Instantiation
pipx install copier
# notebooklm channel: install per the NotebookLM CLI project, then authenticate
nlm login
# Mermaid is fetched on demand by the pdf pack via npx (no global install needed).
```

Always confirm the version you installed with the matching "Check" command
above; do not assume the version from documentation. CI pins `yq` to a specific
release (`v4.53.3`) and verifies its download against a build-provenance
attestation or a pinned SHA-256 before installing.

## Dependency-to-component summary

| Component | Needs |
| --- | --- |
| Core engine + most scripts | `git`, `jq`, `yq`, `ajv-cli` + `ajv-formats`, `python3` |
| `verify.sh` conformance gate | `ajv-cli` + `ajv-formats`, plus `jq`, `yq`, `mif-rh-cli` (its ontology-resolution gates delegate to the engine, ADR-0016) |
| `node` | install path for `ajv`/`markdownlint-cli2` (`npm`) and Mermaid (`npx`) |
| Documentation lint gate | `markdownlint-cli2` |
| Instantiate / update the template | `copier` |
| Release verification | `gh` (2.x+) |
| `notebooklm` channel | `nlm` (+ `nlm login`), `jq`, `python3` |
| `pdf` channel | `pandoc`, a PDF engine, `@mermaid-js/mermaid-cli`, `jq` |
| `github-discuss`, `github-issues` channels | `gh`, `jq` |
| `diataxis` channel | `jq` |
| `engineering`, `trend-analysis`, `competitive-analysis`, `trend-modeling` | `@mermaid-js/mermaid-cli` (optional, diagrams only) |
| Ontology data packs | core runtime plus `mif-rh-cli` (finding resolution, ADR-0016); `yq`, `jq`, `ajv` for registry YAML validation |
