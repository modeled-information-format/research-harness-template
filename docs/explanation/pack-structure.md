---
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
├── reports/                      # family: deliverable genres (container, NOT a plugin)
│   ├── exec-summary/             #   a plugin
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/exec-summary/SKILL.md
│   ├── academic/                 #   a plugin
│   ├── trend-analysis/
│   └── briefing/                 #   `engineering` is consumed externally from
│                                  #   mif-docs-plugin instead, not bundled here
├── market-research/              # family: methodology
│   ├── competitive-analysis/     #   a plugin
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
