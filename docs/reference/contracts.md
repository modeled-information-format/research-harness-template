# Reference: contracts

The typed substrate every layer exchanges. All contracts live under `schemas/`.

## Findings — `schemas/findings.schema.json`

A finding **is** a MIF v1.0 memory unit (design spec §6c). The schema
`allOf`-extends the real vendored MIF schema (`schemas/mif/mif.schema.json`) with
two harness-local requirements (§8b):

- `citations` — a non-empty array of MIF Level 3 citations (citation-integrity).
- `extensions.harness` — `dimension` (the config-declared dimension) and
  `verification` (the adversarial-falsification verdict: one of `falsified`,
  `weakened`, `survived`, `inconclusive`, with a `verdict_basis`).

Validate with the vendored MIF closure registered:

```bash
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/findings.schema.json \
  -r schemas/mif/mif.schema.json \
  -r schemas/mif/definitions/entity-reference.schema.json \
  -d <finding>.json
```

## Manifest — `harness.config.schema.json`

The deploy contract. Required: `version`, `topics`, `dimensions`, `packs`.
`packs[].source` is either the `"bundled"` constant or an external/private
plugin object (`{type, url, ref}`). See `harness.config.json` for a sample.

## Pack — `schemas/pack.schema.json`

A pack is a Claude Code plugin. Required: `name`, `version`, `kind` (one of
`methodology`, `genre`, `channel`, `ontology`). `provides.skills` lists the
plugin's skills. The bundled plugins are listed in
`.claude-plugin/marketplace.json`.

**One plugin per skill** (see [pack-structure](../explanation/pack-structure.md)):
each skill is its own plugin under `packs/<pack>/<skill>/`, so a clone enables
exactly the skills it wants without adopting a whole pack. The pack directory
(`packs/reports/`, `packs/market-research/`, …) is a *family container*, not a
plugin; the plugins are its `<skill>/` subdirectories.

## Structured Data Protocol

See [STRUCTURED-DATA.md](../../schemas/STRUCTURED-DATA.md): write JSON with `jq`,
then validate immediately. A write is not complete until the artifact validates.

## Citation-integrity gate

`scripts/check-citation-integrity.sh <findings.json>` asserts every finding has
at least one well-formed, live citation and no `falsified` verdict. Exit 0 =
pass, exit 1 = violation (one diagnostic line per violation).
