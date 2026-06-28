---
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

## The `site` block

Optional. Controls the Astro/Starlight site that renders `reports/` (and `docs/`)
for human reading. `astro.config.mjs` reads it at build time, so neither the
template nor a clone hand-edits `astro.config.mjs`. Absent ⇒ all defaults. Flip it
with [`site-toggle.sh`](scripts.md) or [`/configure`](commands.md) — see
[How to configure the reports site](../how-to/configure-the-site.md).

```jsonc
"site": {
  "primarySurface": "docs",        // "reports" | "docs" | "auto"
  "plugins": {
    "llmsTxt": true,               // installed, default ON
    "mermaid": true,               // installed, default ON
    "imageZoom": false,            // installed, default OFF
    "linksValidator": false        // installed, default OFF
  }
}
```

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
