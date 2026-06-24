# Documentation

The harness ships one merged [Diátaxis](https://diataxis.fr/) documentation set,
so a clone is self-documenting (design spec §4a, "Diataxis docs — KEEP → bundle").

| Quadrant | For | Start here |
| --- | --- | --- |
| [Tutorials](tutorials/) | Learning by doing | [getting-started.md](tutorials/getting-started.md) |
| [How-to guides](how-to/) | Achieving a task | [run-a-research-session.md](how-to/run-a-research-session.md), [adopt-packs.md](how-to/adopt-packs.md), [verify-a-release.md](how-to/verify-a-release.md) |
| [Reference](reference/) | Looking up facts | [contracts.md](reference/contracts.md), [dependencies.md](reference/dependencies.md), [coverage.md](reference/coverage.md) |
| [Explanation](explanation/) | Understanding why | [architecture.md](explanation/architecture.md), [pack-structure.md](explanation/pack-structure.md), [living-corpus.md](explanation/living-corpus.md) |

## Adopting the harness

These pages cover the full adoptable surface — every pack, skill, command,
agent, and script, plus what you must install and how to verify a release.

| Page | What it gives you |
| --- | --- |
| [Dependencies and requirements](reference/dependencies.md) | Every external tool/runtime, minimum version, install command, and which component needs it |
| [Documentation coverage](reference/coverage.md) | Audit index proving every pack, skill, command, agent, and script is documented |
| [Pack catalog](reference/packs/index.md) | Every bundled pack — purpose, dependencies, benefits, and how to enable it |
| [Core skills](reference/core-skills.md) · [Commands](reference/commands.md) · [Agents](reference/agents.md) · [Scripts](reference/scripts.md) | The non-pack core surface |
| [How to adopt a pack](how-to/adopt-packs.md) | Enable/disable a pack and satisfy its prerequisites |
| [How to verify a release](how-to/verify-a-release.md) | Confirm a downloaded artifact with `gh attestation verify` |
