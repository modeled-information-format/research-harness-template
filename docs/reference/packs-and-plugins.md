---
title: "Reference: packs and plugins"
diataxis_type: reference
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
├── channels/           # family: render adapters (9 plugins)
│   ├── book/
│   ├── diataxis/
│   ├── pdf/
│   └── …               #   6 more — see the Bundled inventory below
├── trend-modeling/     # family: scenario methodology (1 plugin)
│   └── trend-modeling/
└── ontologies/         # family: MIF entity/relationship extensions (12 plugins)
    ├── scientific/
    └── …               #   11 more — see the Bundled inventory below
```

There is no `packs/reports/` directory: all 18 report genres are consumed
externally from `mif-docs-plugin` (SHA-pinned via `harness.config.json`
`marketplaces[]`) rather than bundled, completing the genre-consolidation
migration in
[discussion #228](https://github.com/modeled-information-format/research-harness-template/discussions/228).
See [Report packs](packs/reports.md) for the full genre-by-genre reference.

The harness bundles **27 pack plugins** across four families: 9 channels,
5 market-research methodologies, 12 ontologies, and 1 trend-modeling
methodology. The [Packs reference](packs/index.md) and the per-family pages
document every bundled one — its use, constraints, and goals.

Each `packs/<family>/<plugin>/` is self-contained: a `.claude-plugin/plugin.json`
(validated against `schemas/pack.schema.json`), a flat `skills/<skill>/SKILL.md`,
and that skill's `evals/`.

## Pack taxonomy

The `kind` field classifies what a pack contributes to the core. It is an `enum`
in `schemas/pack.schema.json`.

| `kind` | Family directory | Contributes |
| --- | --- | --- |
| `methodology` | `market-research/`, `trend-modeling/` | Research dimensions and analyst skills |
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

The harness bundles **27 pack plugins** across four families. Each family has a
dedicated reference page documenting every component's purpose, constraints, and
goals; the counts below match `ls packs/<family>/` exactly.

**Channels** — render adapters ([`packs/channels/`](packs/channels.md), 9 plugins):
`book`, `diataxis`, `ectd`, `github-discuss`, `github-issues`, `jats`,
`notebooklm`, `pdf`, `xbrl`.

**Report genres** — deliverable templates ([`packs/reports.md`](packs/reports.md),
18 plugins, all consumed externally from
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
— no `packs/reports/` directory; `academic`, `briefing`, `engineering`,
`exec-summary`, and `trend-analysis` are enabled by default, the rest are
opt-in): `academic`, `briefing`, `clinical-submission`, `competitive-quadrant`,
`compliance-audit`, `computing-paper`, `engineering`, `exec-summary`,
`humanities-chicago`, `humanities-mla`, `legal-memo`, `market-research-report`,
`nist-sp`, `regulatory-disclosure`, `security-pentest`, `sustainability-report`,
`systematic-review`, `trend-analysis`.

**Market-research methodologies** — research dimensions
([`packs/market-research/`](packs/market-research.md), 5 plugins):
`competitive-analysis`, `customer-research`, `financial-analysis`,
`market-sizing`, `regulatory-review`.

**Trend-modeling** — three-valued scenario methodology
([`packs/trend-modeling/`](packs/trend-modeling.md), 1 plugin): `trend-modeling`.

**Ontologies** — MIF entity/relationship/trait vocabularies
([`packs/ontologies/`](packs/ontologies.md), 12 plugins):
`biology-research-lab`, `data-engineering`, `market-research`, `observability`,
`psycholinguistics`, `regenerative-agriculture`, `regenerative-agriculture-research`,
`regulatory-legal`, `scientific`, `software-engineering`, `software-security`,
`trend-analysis`.

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
