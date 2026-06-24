---
diataxis_type: how-to
---

# How to adopt a pack

This guide shows an adopting user how to turn a bundled pack on or off and
satisfy its prerequisites. For what each pack does and what it needs, see the
[pack catalog](../reference/packs/index.md); for the model and manifest fields,
see [packs and plugins](../reference/packs-and-plugins.md).

## Before you begin

- Have the [core runtime](../reference/dependencies.md) installed (`git`, `jq`,
  `node`, `python3`). Every pack relies on the core engine.
- Check whether your target pack needs an extra tool — the catalog and the
  [dependencies reference](../reference/dependencies.md) list these per pack
  (for example `pandoc` for `pdf`, `gh` for the GitHub channels, `nlm` for
  `notebooklm`). Install the tool first; a pack with a missing tool reports the
  install step and stops rather than erroring.

## Steps

1. Confirm the pack is registered. A pack must already be declared in
   `harness.config.json` `packs[]` before it can be toggled. The bundled packs
   are all declared; list them with:

   ```sh
   jq -r '.packs[].name' harness.config.json
   ```

2. Enable the pack. This flips its `enabled` flag and re-materializes the active
   set:

   ```sh
   scripts/pack-toggle.sh <pack-name> on
   ```

   `pack-toggle.sh` calls `scripts/sync-packs.sh` for you, which writes Claude
   Code's native `enabledPlugins` into `.claude/settings.json` and records the
   resolved skills in `.claude/enabled-packs.json`.

3. Verify the pack is active:

   ```sh
   jq -r '.enabledPlugins[]' .claude/enabled-packs.json
   ```

   The pack name should appear in the list.

4. Install any tool the pack requires, if you have not already, then exercise
   the pack's skill (the catalog entry names the trigger).

## Disable a pack

```sh
scripts/pack-toggle.sh <pack-name> off
```

Disabled packs are omitted from both `.claude/settings.json` and
`.claude/enabled-packs.json`, so their skills are no longer active.

## Defaults

By default the five `reports` genres (`academic`, `briefing`, `engineering`,
`exec-summary`, `trend-analysis`) are enabled; every other pack is disabled and
opt-in. The blog channel is a first-class, always-on output and is not a pack.

## Ontology packs use a different surface

This guide covers the skill, channel, and genre plugin packs in
`harness.config.json` `packs[]`. **Ontology data packs are not toggled with
`pack-toggle.sh`** — they live in `harness.config.json` `ontologies[]` and are
enabled and bound to a topic differently. See
[Ontology packs](../reference/packs/ontologies.md#enabling-and-binding-an-ontology).
