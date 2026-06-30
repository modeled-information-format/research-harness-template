# ai-spec

Renders a topic's surviving findings into an AI-ready, agent-executable architecture spec: a
genre-shaping of the `artifact.json` -> Markdown pipeline (finding_refs -> evidence, goal checks ->
EARS, sections -> structure). Pairs with a spec-genre pack (architecture-spec / kiro-spec /
feature-spec).

This `channels` pack is documented in the MIF research-harness reference:

- **[ai-spec — pack reference](https://modeled-information-format.github.io/research-harness-template/reference/packs/channels/#ai-spec)** — its purpose, constraints, goals,
  and how to enable it.

**Dependencies:** `scripts/synthesize-artifact.sh`, `scripts/render-artifact.sh`, a bound
spec-genre pack, `schemas/artifact.schema.json`, `reports/<topic>/goal.json`

The pack source lives in this directory. It ships disabled; enable it with
`scripts/pack-toggle.sh ai-spec on`. See the
[MIF research-harness docs](https://modeled-information-format.github.io/research-harness-template/) for the full pack catalog.
