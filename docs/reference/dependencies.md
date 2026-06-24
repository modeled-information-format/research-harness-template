---
diataxis_type: reference
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
  (`python-version: '3.12'`, `node-version: 'lts/*'`, `yq` pinned to
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
| `jq` | 1.7+ (1.8.2 verified) | The engine — index, graph, findings, render, falsify (most scripts) | `jq --version` |
| `yq` (mikefarah) | `v4.53.3` — *repo-pinned in CI* (4.53.3 verified) | YAML frontmatter and ontology YAML in `verify.sh`, `mif-project.sh`, `resolve-ontology.sh`, `validate-concordance.sh`; ontology catalog materialization in `sync-packs.sh` | `yq --version` |
| `node` | Active LTS — *repo-declared* `lts/*` (26.x verified) | `npm` to install the validation toolchain (`ajv-cli`, `ajv-formats`, `markdownlint-cli2`); `npx` for Mermaid | `node --version` |
| `python3` | 3.12 — *repo-declared* (3.14 verified) | `codegen/gen-models.sh` + `bundle_schema.py` (self-provisioned pinned venv), `sync-packs.sh` (embedded materialization), `.claude/hooks/markdown/md_remediate.py` | `python3 --version` |

`jq` and `yq` carry the heaviest load: `jq` drives the index, graph, session,
and render scripts; `yq` reads every YAML input. If the engine's schema gates
are to run, both must be present.

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

## Instantiation (the recommended adoption path)

The harness is a [Copier](https://copier.readthedocs.io/) template. The
recommended way to adopt it is `copier copy`, which records a
`.copier-answers.yml` so you can later pull template improvements with
`copier update` — see [How to instantiate the harness](../how-to/instantiate-the-harness.md).

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
[`SECURITY.md`](../../SECURITY.md).

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
| `verify.sh` conformance gate | `ajv-cli` + `ajv-formats`, plus `jq`, `yq` |
| `node` | install path for `ajv`/`markdownlint-cli2` (`npm`) and Mermaid (`npx`) |
| Documentation lint gate | `markdownlint-cli2` |
| Instantiate / update the template | `copier` |
| Release verification | `gh` (2.x+) |
| `notebooklm` channel | `nlm` (+ `nlm login`), `jq`, `python3` |
| `pdf` channel | `pandoc`, a PDF engine, `@mermaid-js/mermaid-cli`, `jq` |
| `github-discuss`, `github-issues` channels | `gh`, `jq` |
| `diataxis` channel | `jq` |
| `engineering`, `trend-analysis`, `competitive-analysis`, `trend-modeling` | `@mermaid-js/mermaid-cli` (optional, diagrams only) |
| Ontology data packs | core runtime only (`yq`, `jq`, `ajv` for resolution) |
