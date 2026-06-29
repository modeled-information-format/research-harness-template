---
name: synthesize-corpus
description: Build the cross-topic corpus atlas — project the ontological spine across all topics into reports/_corpus/corpus-synthesis.md, including what was disproven.
allowed-tools:
  - Agent
  - Bash
  - Read
---

# Synthesize Corpus

Builds the **corpus atlas**: a single cross-topic view of the ontological spine
(`reports/concordance.json`) spanning every topic — what the whole corpus knows, including what
was falsified. This is distinct from a per-topic report (`/start` → `report-synthesizer`), which
ships only one topic's surviving findings.

## Preconditions

The atlas projects the cross-topic concordance. Ensure it is built and current:

```bash
[ -s reports/concordance.json ] || bash scripts/build-concordance.sh
```

The orchestrator reconciles the spine every research run (ADR-0011); build it on demand here if
it is absent.

## Run

Spawn the `corpus-synthesizer` over the whole reports tree. The atlas spans ALL topics, so it is
a cross-session, cross-topic artifact (not tied to one `/start` session):

```text
Agent(
  subagent_type: "corpus-synthesizer",
  prompt: """
    Build the cross-topic corpus atlas from reports/concordance.json. Run
    `scripts/synthesize-corpus.sh reports` for the backbone, then author synthesis-grade
    Cross-Corpus Insights (cross-topic entity reuse, converging vs. contradicting evidence, and
    what was disproven), trace every claim to a concordance node id, and pass
    `scripts/synthesize-corpus.sh reports --check`. Your FINAL MESSAGE is your return value.
  """
)
```

## Output

- `reports/_corpus/corpus-map.json` — the deterministic cross-topic projection.
- `reports/_corpus/corpus-synthesis.md` — the human-facing atlas (incl. *What Was Disproven*).
