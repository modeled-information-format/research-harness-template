---
id: explanation-pack-structure
type: semantic
created: '2026-06-19T20:44:52-04:00'
modified: '2026-07-01T07:01:43-04:00'
namespace: docs/explanation
tags:
  - documentation
  - explanation
title: "Explanation: pack structure — one plugin per skill"
diataxis_type: explanation
---

# Explanation: pack structure — one plugin per skill

## The convention

Every optional capability ships as a **plugin, and each plugin contains exactly
one skill**. Plugins are grouped into *pack families* by directory, but the
plugin boundary is the individual skill:

```text
packs/
├── market-research/              # family: methodology
│   ├── competitive-analysis/     #   a plugin
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/competitive-analysis/SKILL.md
│   ├── customer-research/
│   ├── financial-analysis/
│   ├── market-sizing/
│   └── regulatory-review/
├── channels/                     # family: render adapters
│   ├── notebooklm/
│   ├── pdf/
│   ├── github-discuss/
│   └── github-issues/
└── trend-modeling/
    └── trend-modeling/
```

There is no `packs/reports/` directory: every report genre (`academic`,
`engineering`, `exec-summary`, and the rest — see
[Report packs](../reference/packs/reports.md)) is consumed externally from
`mif-docs-plugin` rather than bundled, so the "reports" family has no local
plugin directory to illustrate here.

Each `packs/<family>/<skill>/` is a self-contained Claude Code plugin: its
`.claude-plugin/plugin.json` (validated against `schemas/pack.schema.json`) plus
a flat `skills/<skill>/SKILL.md` and that skill's `evals/`.

## Why

The point is **selective adoption**. A clone that wants the executive-summary
genre but not the academic one enables `exec-summary` and leaves `academic`
disabled — it is never forced to adopt a whole pack to get one skill. New
capabilities are added the same way: drop a new `packs/<family>/<skill>/` plugin,
register it in `.claude-plugin/marketplace.json`, and toggle it in
`harness.config.json` `packs[]`. Nothing else changes.

This applies to **all** families uniformly — `market-research`, `channels`, and
`trend-modeling` follow the same one-plugin-per-skill shape as `reports`, so the
extension surface is consistent everywhere.

## The control plane

`harness.config.json` `packs[]` lists each plugin by its (bare) name with an
`enabled` flag and a `source` (`bundled`, or an external git/marketplace plugin).
`scripts/sync-packs.sh` resolves each enabled plugin's directory from the
marketplace `source` path and materializes the set into Claude Code's native
`enabledPlugins` in the instance-local `.claude/settings.local.json`
(`<skill>@research-harness`; gitignored, deep-merged with the template-managed
`.claude/settings.json`). `scripts/pack-toggle.sh <skill> on|off` flips one plugin.

By default the five `reports` genres are enabled; every other plugin is
disabled and opt-in.
