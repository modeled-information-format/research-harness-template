---
name: configure
description: Configure the research harness — toggle packs and site features, manage ontologies and topics, tune the manifest, and verify. A broad concierge that edits harness.config.json and drives the existing toggle scripts, then re-runs the gates. Use it to set up, adjust, or troubleshoot a harness without hand-editing the manifest.
argument-hint: "[packs|site|ontologies|topics|verify] [<free-form request>]"
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Glob
  - Grep
  - Read
  - Skill
  - Write
---

# Configure

The harness's configuration concierge. `harness.config.json` is the one file a
clone edits (SPEC §7), but it has many control planes — topics, dimensions,
outputs, packs, ontologies, voice, freshness, and the `site` projection. This
command delegates to the `harness-configurator` agent, which makes the change
through the **existing tooling** (never by hand-rolling), validates it against
`harness.config.schema.json`, and re-runs the gates before reporting done.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets. The first token MAY be an area selector; the rest is
a free-form request. With no area, infer it from the request.

- `packs` — enable/disable a pack, or recommend packs for a goal. Wraps
  `scripts/pack-toggle.sh <name> on|off` (which re-materializes via
  `scripts/sync-packs.sh`). Packs are declared in `harness.config.json packs[]`
  and registered in `.claude-plugin/marketplace.json`.
- `site` — choose which surface leads the reports/docs site, or toggle an optional
  Astro/Starlight plugin. Wraps `scripts/site-toggle.sh primary <reports|docs|auto>`
  and `scripts/site-toggle.sh plugin <llmsTxt|mermaid|imageZoom|linksValidator> <on|off>`.
- `ontologies` — enable an ontology in `ontologies[]` and bind it to topics. Defer
  the binding + corpus re-resolution to the `/ontology-review` command/skill.
- `topics` — register, retitle, or re-scope a topic (`topics[]`: id, title,
  namespace, status, ontologies). Also covers `dimensions[]`, `outputs[]`,
  `voice`, and `freshness`.
- `verify` — run the gates and report (`bash scripts/verify.sh`; advise
  `scripts/ontology-review.sh` after ontology/pack-binding changes).

With no arguments, the agent surveys the current manifest and offers the most
useful next configuration steps.

## Behavior

1. Resolve the area (explicit token or inferred) and the concrete change requested.
2. Spawn the `harness-configurator` agent with the area, the request, and the
   manifest path:

   ```text
   Agent(
     subagent_type: "harness-configurator",
     name: "harness-configurator",
     prompt: """
       AREA: {packs|site|ontologies|topics|verify|survey}
       REQUEST: {the sanitized free-form request}
       CONFIG: harness.config.json
     """
   )
   ```

3. The agent makes the change via the existing scripts / guided manifest edits,
   validates against `harness.config.schema.json`, and re-runs the gates. Relay
   its result. If the change is ambiguous or destructive (disabling an in-use pack,
   re-scoping a bound topic), the agent asks via `AskUserQuestion` first.
