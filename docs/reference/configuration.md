---
id: reference-configuration
type: semantic
created: '2026-06-28T03:52:14-04:00'
modified: '2026-07-05T10:10:48-04:00'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: configuration"
diataxis_type: reference
---

# Reference: configuration

`harness.config.json` is the one file a clone edits — the deploy contract,
validated by `harness.config.schema.json` (the schema is authoritative; this page
summarizes it). The [`/configure`](commands.md) command edits it through the
harness's tooling rather than by hand.

## Top-level blocks

| Block | Purpose |
| --- | --- |
| `version` | Manifest/release version (semver), bumped in lockstep across the template. |
| `mifConformanceLevel` | MIF floor for every artifact crossing the project boundary (SPEC §10 fixes it at 3). |
| `features` | Opt-in feature flags (e.g. `internalCitations`); strict by default. |
| `voice` | Human-voice profile and prose rules. |
| `topics[]` | The topic registry: `id`, `title`, `namespace`, `status`, per-topic `ontologies`. |
| `dimensions[]` | Config-declared research dimensions (`id`, `description`, optional `pack`). |
| `outputs[]` | Output channels (`channel`, `enabled`, `mifExempt` + reason). |
| `freshness` | Source-type staleness windows. |
| `site` | Astro/Starlight site-projection controls (below). |
| `packs[]` | The pack control plane (enable/disable + source). |
| `ontologies[]` | The ontology control plane (enable to catalog). |
| `marketplaces[]` | External plugin sources declared once (`name`, `url`, pinned `ref`); a `packs[]` entry references one by name via `source: {type: "marketplace-ref", marketplace: <name>}` instead of repeating the source object per pack. Declaring a marketplace does not enable anything — see [Packs and Plugins](packs-and-plugins.md). |

## The `site` block

Optional. Controls the Astro/Starlight site that renders `reports/` (and `docs/`)
for human reading. `astro.config.mjs` reads it at build time, so neither the
template nor a clone hand-edits `astro.config.mjs`. Absent ⇒ all defaults. Flip it
with [`site-toggle.sh`](scripts.md) or [`/configure`](commands.md) — see
[How to configure the reports site](../how-to/configure-the-site.md).

```jsonc
"site": {
  "base": "/",                     // deploy base path, default "/" (site root)
  "primarySurface": "docs",        // "reports" | "docs" | "auto"
  "plugins": {
    "llmsTxt": true,               // installed, default ON
    "mermaid": true,               // installed, default ON
    "imageZoom": false,            // installed, default OFF
    "linksValidator": false        // installed, default OFF
  }
}
```

- **`base`** — the site's deploy base path (Astro's `base` config). Default
  `/` (site root) — correct for local dev, a custom domain, or a GitHub Pages
  user/org root site. Set it to `/<repo-name>` only when deploying as a
  GitHub Pages **project** site (`https://<org>.github.io/<repo-name>/`).
  `astro.config.mjs` reads this at build time, same as every other `.site.*`
  control — never hand-edit the constant into that file (see
  [ADR-0013](../adr/0013-configurable-site-base-path.md)).
- **`primarySurface`** — which surface leads the sidebar. `reports` puts the
  Reports group on top; `docs` keeps the docs groups on top with Reports after
  them; `auto` resolves to reports when any rendered report exists, else docs. The
  landing (`/`) stays the docs index in every case. The template pins `docs` (it
  ships the example report yet stays a docs site); a clone is flipped to `reports`
  by the copier post-copy task.
- **`plugins`** — gates for optional enhancements. Each flag gates an
  already-installed plugin; it does not add a dependency. `llmsTxt` and `mermaid`
  default on; `imageZoom` and `linksValidator` default off. `linksValidator` fails
  the build on broken internal links (including links to non-page report siblings),
  so enable it only once your reports' links resolve.
