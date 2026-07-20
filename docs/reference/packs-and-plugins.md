---
id: reference-packs-and-plugins
type: semantic
created: '2026-06-23T09:41:01-04:00'
modified: '2026-07-20T02:05:07.545Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: packs and plugins"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-23T09:41:01-04:00'
  ttl: P6M
  recordedAt: '2026-06-23T09:41:01-04:00'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:cc83f20c-2193-42dd-b5b5-72fe80571327
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.215
---

# Reference: packs and plugins

This page is the exhaustive reference for the harness's extension surface: the
plugin shape, the pack taxonomy, the manifest fields, the control plane that
toggles them, and the bundled inventory. For the rationale behind the model see
[Explanation: pack structure](../explanation/pack-structure.md) and
[ADR 0005](../adr/0005-packs-and-plugins-extension-model.md).

## Model: one plugin per skill

Every optional capability ships as a **Claude Code plugin, and each plugin
contains exactly one skill**. Plugins are grouped into *pack families* by
directory, but the plugin boundary is the individual skill — a clone enables
exactly the skills it wants without adopting a whole family.

```text
packs/
├── market-research/    # family: methodologies (5 plugins)
│   ├── competitive-analysis/
│   ├── customer-research/
│   ├── financial-analysis/
│   ├── market-sizing/
│   └── regulatory-review/
├── channels/           # family: render adapters (10 plugins)
│   ├── ai-spec/
│   ├── book/
│   ├── diataxis/
│   ├── pdf/
│   └── …               #   6 more — see the Bundled inventory below
└── trend-modeling/     # family: scenario methodology (1 plugin)
    └── trend-modeling/
```

`packs/ontologies/` is not a bundled directory: domain ontologies are vendored
on demand from the canonical registry (ADR-0012), materializing under
`packs/ontologies/<id>/` only once `scripts/fetch-ontology.sh` vendors one — it
may be absent or empty on a fresh, unvendored clone. See
[Ontology packs](packs/ontologies.md) and `scripts/fetch-ontology.sh`.

There is no `packs/reports/` directory: all 32 report genres are consumed
externally from `mif-docs-plugin` (SHA-pinned via `harness.config.json`
`marketplaces[]`) rather than bundled, completing the genre-consolidation
migration in
[discussion #228](https://github.com/modeled-information-format/research-harness-template/discussions/228).
See [Report packs](packs/reports.md) for the full genre-by-genre reference.

There is likewise no `packs/genres/` directory: all 5 spec genres
(`ai-architecture-doc`, `feature-spec`, `kiro-requirements`, `kiro-design`,
`kiro-tasks`) are consumed externally from `mif-docs-plugin` the same way,
per ADR-0018 and
[research-harness-template#409](https://github.com/modeled-information-format/research-harness-template/issues/409)
— see [Genre packs](packs/genres.md).

The harness bundles **17 pack plugins** across four families: 10 channels,
5 market-research methodologies, 1 trend-modeling methodology, and 1
monitoring methodology (`continuous-monitor`, research-harness-template#483).
Report genres (32), spec genres (5), and domain ontologies (23) are all
consumed externally or vendored on demand rather than bundled — see each
family's own page for its full inventory. The [Packs reference](packs/index.md) and
the per-family pages document every one — its use, constraints, and goals.

Each `packs/<family>/<plugin>/` is self-contained: a `.claude-plugin/plugin.json`
(validated against `schemas/pack.schema.json`), a flat `skills/<skill>/SKILL.md`,
and that skill's `evals/`.

## mif-docs-plugin: the document-tooling and provenance substrate

`mif-docs-plugin` is more than a genre source. Since Epic #405 (ADR-0018),
it is the single document-tooling and provenance substrate for every
document-shaped deliverable this harness produces — not just the report/spec
genres it externally sources (above), but the frontmatter authoring,
conformance validation, and witnessed-provenance stamping mechanism itself:

- **`mif-frontmatter`, `mif-validate`, `mif-provenance`** — the shared skills
  that author, validate, and stamp MIF frontmatter on any document-shaped
  file, independent of which genre (if any) renders it. `.mcp.json` wires
  the `mif-mcp` server; `.claude/settings.json`'s `mifProvenance` key
  enables capture by default. See
  [Dependencies](dependencies.md#document-tooling-mif-docs-plugin).
- **`verify.sh`'s `gate_m32`** structurally enforces this floor on every
  tracked document deliverable: MIF Level 1 always, and Level 3
  (unconditionally, no exemptions) on every file that declares a
  `provenance:` block — see [Scripts](scripts.md).
- **Scope boundary, unchanged by this Epic:** `mif-docs`'s conformance
  validation is a different, complementary mechanism from the harness-local
  `ajv` schema-conformance gate for findings/knowledge-graph data
  (ADR-0002) — a finding's `entity_type`/`ontology.id` typing and the
  concordance it composes into are not document-shaped and stay outside
  `mif-docs`'s remit entirely.

See [ADR-0018](../adr/0018-mif-docs-plugin-as-document-tooling-substrate.md)
for the full rationale and the deprecation policy every genre retirement in
Epic #405 followed.

## Pack taxonomy

The `kind` field classifies what a pack contributes to the core. It is an `enum`
in `schemas/pack.schema.json`.

| `kind` | Family directory | Contributes |
| --- | --- | --- |
| `methodology` | `market-research/`, `trend-modeling/`, `monitoring/` | Research dimensions and analyst skills |
| `genre` | `reports/` | Deliverable templates for the report channel |
| `channel` | `channels/` | Render adapters (blog, book, PDF, NotebookLM, GitHub) |
| `ontology` | `ontologies/` | MIF entity, relationship, and trait extensions |

## Manifest fields (`schemas/pack.schema.json`)

A pack's `plugin.json` is a Claude Code plugin manifest plus the harness-local
classification fields below. `additionalProperties` is `true`, so standard
plugin keys are preserved.

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | Pack name and skill namespace (`^[a-z][a-z0-9-]*$`); skills resolve as `pack:skill`. |
| `version` | yes | Semantic version (`MAJOR.MINOR.PATCH`). |
| `kind` | yes | One of `methodology`, `genre`, `channel`, `ontology`. |
| `description` | no | Short human description. |
| `mif` | no | MIF output-conformance declaration (see below). |
| `provides` | no | What the pack adds, namespaced: `skills`, `agents`, `commands`, `dimensions`, `genres`, `channels`, `ontologies`. |
| `license`, `author`, `keywords` | no | Standard metadata. |

### MIF conformance and exemption

A channel pack whose target format is orthogonal to MIF (PDF, audio, an external
service body) declares `mif.exempt: true` with a required `mif.reason`, so the
MIF Level-3 output-conformance gate logs its outputs instead of requiring an L3
projection. Genre packs are L3 by default and **must not** declare exemption —
exemption is for orthogonal *formats*, never for genres (see
[ADR 0007](../adr/0007-report-channel-canonical-blog-mif-exempt.md)).

## Control plane

`harness.config.json` `packs[]` is the single control plane. Each entry names a
plugin with an `enabled` flag and a `source` (`bundled`, an inline external
git/marketplace plugin, or a reference into `marketplaces[]`).

```json
{ "name": "briefing", "enabled": true, "source": "bundled" }
```

### Declared marketplaces — one dependency, many packs

`harness.config.json` `marketplaces[]` declares an external plugin source
**once** (`name`, `url`, a pinned `ref`); any number of `packs[]` entries then
reference it by name instead of each repeating an identical `{type, url, ref}`
object. Use this whenever two or more packs come from the same external
plugin (e.g. every genre skill `mif-docs-plugin` ships), or to declare a
dependency on an external plugin before any pack references it (e.g. adding
`human-voice` as a marketplace ahead of consuming one of its skills).

```json
{
  "marketplaces": [
    { "name": "mif-docs", "url": "https://github.com/modeled-information-format/mif-docs-plugin", "ref": "<pinned-sha>" }
  ],
  "packs": [
    { "name": "engineering", "enabled": true, "source": { "type": "marketplace-ref", "marketplace": "mif-docs" } }
  ]
}
```

A pack's own `source.ref` overrides the marketplace's `ref` for that one pack,
for the rare case a specific skill needs a newer (or older) pin than the rest
of the marketplace. Declaring a marketplace does not enable anything by
itself — a `packs[]` entry's `enabled` flag still controls that per pack, same
as any other source.

| Operation | Command |
| --- | --- |
| Flip one plugin | `scripts/pack-toggle.sh <plugin> on` (or `off`) |
| Materialize the enabled set | `scripts/sync-packs.sh` |

`sync-packs.sh` resolves each enabled plugin's directory from the marketplace
`source` and writes the result into two places:

1. Claude Code's native `enabledPlugins` in `.claude/settings.local.json` (the
   mechanism the runtime reads — `<plugin>@research-harness: true`). This is
   **instance-local** materialized state: it derives from this repo's
   `harness.config.json` `packs[]`, so it is gitignored and never lives in the
   template-managed, byte-identical `.claude/settings.json`. Claude Code
   deep-merges `enabledPlugins` across `settings.json` and `settings.local.json`,
   so the runtime sees these enablements alongside the shared hooks.
2. A sidecar `.claude/enabled-packs.json` recording each enabled plugin's source
   and resolved skills, for tooling and the conformance gate (also gitignored).

Disabled plugins appear in neither, so their skills are not active. By default
the five `reports` genres are enabled; every other plugin is disabled and opt-in.

### Template-managed vs instance-local config

`.claude/settings.json` is **template-managed**: it carries the harness hooks and
is kept byte-identical template-and-instance so `copier update` never conflicts on
it. Anything **instance-local** — the materialized `enabledPlugins`
(`settings.local.json`), the `enabled-packs.json` sidecar, and personal overrides
like `skillOverrides` — lives in `.claude/settings.local.json` (gitignored,
deep-merged by the runtime) and is rebuilt by `sync-packs.sh`. The Copier answers
file `.copier-answers.yml` is the one instance-specific file that **is** committed:
it records the template commit `copier update` uses as its merge base.

## Marketplace registration

`.claude-plugin/marketplace.json` is the marketplace manifest (`name`,
`research-harness`). Its `plugins[]` array maps each plugin `name` to its
`source` path under `packs/` and a description. A plugin must be registered here
before `harness.config.json` can reference it by name.

## Bundled inventory

This inventory covers **54 pack plugins** across six families — matching
`harness.config.json` `packs[]` exactly. Each family has a dedicated reference
page documenting every component's purpose, constraints, and goals; for
channels, market-research, trend-modeling, and monitoring, the counts below
also match `ls packs/<family>/` directly. Report genres and spec genres are the
exception: all 32 report genres and all 5 spec genres are consumed externally
from `mif-docs-plugin` (no `packs/reports/` or `packs/genres/` directory
exists to `ls`), so those two counts instead match each family's reference
page and `harness.config.json` `packs[]`.

**Channels** — render adapters ([`packs/channels/`](packs/channels.md), 10 plugins):
`ai-spec`, `book`, `diataxis`, `ectd`, `github-discuss`, `github-issues`, `jats`,
`notebooklm`, `pdf`, `xbrl`.

**Report genres** — deliverable templates ([`packs/reports.md`](packs/reports.md),
32 plugins, all consumed externally from
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
— no `packs/reports/` directory; `academic`, `briefing`, `engineering`,
`exec-summary`, and `trend-analysis` are enabled by default, the rest are
opt-in): `academic`, `adr`, `arc42-arch-doc`, `briefing`, `c4-model-diagram`,
`changelog`, `clinical-submission`, `competitive-quadrant`,
`compliance-audit`, `computing-paper`, `diataxis-explanation`,
`diataxis-how-to`, `diataxis-reference`, `diataxis-tutorial`, `engineering`,
`exec-summary`, `google-design-doc`, `humanities-chicago`, `humanities-mla`,
`legal-memo`, `market-research-report`, `nist-sp`, `playbook`, `prd`,
`python-pep`, `regulatory-disclosure`, `rust-rfc`, `security-pentest`,
`sre-runbook`, `sustainability-report`, `systematic-review`, `trend-analysis`.

**Spec genres** — architecture/requirements deliverable templates
([`packs/genres.md`](packs/genres.md), 5 plugins, all consumed externally from
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
per ADR-0018 — no `packs/genres/` directory):
`ai-architecture-doc`, `feature-spec`, `kiro-design`, `kiro-requirements`,
`kiro-tasks`.

**Market-research methodologies** — research dimensions
([`packs/market-research/`](packs/market-research.md), 5 plugins):
`competitive-analysis`, `customer-research`, `financial-analysis`,
`market-sizing`, `regulatory-review`.

**Trend-modeling** — three-valued scenario methodology
([`packs/trend-modeling/`](packs/trend-modeling.md), 1 plugin): `trend-modeling`.

**Monitoring** — unattended, scheduled external-source monitoring
([`packs/monitoring/`](packs/monitoring.md), 1 plugin): `continuous-monitor`.

Domain ontologies are not one of the five families above — `packs/ontologies/`
isn't a bundled directory; it's populated on demand from the canonical
registry per ADR-0012, with the enabled set declared in `harness.config.json`
`ontologies[]`; see [Ontology packs](packs/ontologies.md) and
`scripts/fetch-ontology.sh`.

The blog channel is a first-class, always-on harness output (not a pack). The
report channel is the canonical MIF Level-3 source of truth.

## Adding a pack

1. Create `packs/<family>/<plugin>/` with `.claude-plugin/plugin.json` (valid
   against `schemas/pack.schema.json`) and `skills/<skill>/SKILL.md`.
2. Register the plugin `name` → `source` in `.claude-plugin/marketplace.json`.
3. Add `{ "name": "<plugin>", "enabled": false, "source": "bundled" }` to
   `harness.config.json` `packs[]`.
4. Enable it with `scripts/pack-toggle.sh <plugin> on` and run
   `scripts/sync-packs.sh`.

Nothing in the core changes — the extension surface is uniform across all
families.
