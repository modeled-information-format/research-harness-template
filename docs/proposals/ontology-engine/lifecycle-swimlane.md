---
id: explanation-ontology-engine-lifecycle-swimlane
type: semantic
created: '2026-07-01T00:00:00Z'
modified: '2026-07-01T00:00:00Z'
namespace: proposals/ontology-engine
title: "Research lifecycle swimlane: current bash scripts vs. proposed compiled engine scope"
diataxis_type: explanation
tags:
  - explanation
  - ontology
  - diagram
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-01T00:00:00Z'
  ttl: P6M
  recordedAt: '2026-07-01T00:00:00Z'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  trustLevel: high_confidence
relationships:
  - type: relates-to
    target: /docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: 'Research lifecycle swimlane: current bash scripts vs. proposed compiled engine scope'
  entity_type: explanation-document
---

# Research lifecycle swimlane: current bash scripts vs. proposed compiled engine scope

Supporting diagram for `docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md`
and the `docs/proposals/ontology-engine/` doc-set. Traces one topic's full
research lifecycle — `/start` through synthesis — by actor lane, grounded in
the actual call sites in `.claude/agents/orchestrator.md` and
`.claude/agents/report-synthesizer.md` (not idealized). Node color marks each
script's status relative to this proposal:

- **Green** — in scope for the ADR-0014 proof-of-concept
  (`ontology-review.sh` / `resolve-ontology.sh`).
- **Amber** — named in ADR-0014's Option 2 ("big-bang rewrite") as a
  candidate for a *later*, separate generalization decision — explicitly
  **not** authorized by this proposal.
- **Gray** — everything else: unaffected either way.

```mermaid
flowchart TB
  classDef inscope fill:#1f6f4a,stroke:#0d3b26,color:#fff
  classDef candidate fill:#8a6d1f,stroke:#4d3c10,color:#fff
  classDef unaffected fill:#3a3a3a,stroke:#1a1a1a,color:#eee

  subgraph L0["User / Commands"]
    direction TB
    U1["/start (topic init,<br/>ontology binding)"]
    U2["/resume"]
    U3["/ontology-review --enrich<br/>(unblock a withheld synthesis)"]
    U4["/synthesize-corpus<br/>(cross-topic, on demand)"]
  end

  subgraph L1["Orchestrator — Phase 0-3"]
    direction TB
    O0["Phase 0: run-lock.sh acquire"]
    O1["Phase 1: fan out<br/>dimension-analysts"]
    O2["Phase 2: falsify.sh<br/>(the one adversarial gate)"]
    O3["Phase 3: completion check<br/>(loop or hold)"]
  end

  subgraph L2["Dimension-Analyst"]
    direction TB
    DA1["write finding-*.json"]
    DA2["resolve-ontology.sh<br/>(per finding, inline)"]
  end

  subgraph L3["Orchestrator — Phase 4 (Synthesize)"]
    direction TB
    P4a["resolve-membership.sh +<br/>build-index.sh<br/>(provenance/membership)"]
    P4b["run-lock.sh refresh"]
    P4c["ontology-review.sh --topic<br/>(rebuild THIS topic's map)"]
    P4d["check-shippable-typing.sh<br/>(ADR-0011 fail-closed gate)"]
    P4gate{"gate pass?"}
    P4e["build-concordance.sh"]
    P4f["validate-concordance.sh"]
    P4g["reconcile-session.sh<br/>(state.json checkpoint)"]
    P4withheld[".synthesis-withheld sentinel<br/>+ run-lock.sh release<br/>(STOP — /resume re-enters here)"]
  end

  subgraph L4["Report-Synthesizer"]
    direction TB
    RS1["synthesize-artifact.sh"]
    RS2["render-artifact.sh<br/>(stamp genre/version)"]
    RS3["build-topic-readme.sh"]
    RS4["check-citation-integrity.sh"]
    RS5["mif-project.sh"]
  end

  subgraph L5["Corpus-Synthesizer (separate, on demand)"]
    direction TB
    CS1["synthesize-corpus.sh<br/>(cross-topic atlas)"]
  end

  U1 --> O0
  U2 --> O0
  O0 --> O1
  O1 --> DA1 --> DA2 --> O1
  O1 --> O2 --> O3
  O3 -->|more work| O1
  O3 -->|complete| P4a
  P4a --> P4b --> P4c --> P4d --> P4gate
  P4gate -->|no| P4withheld
  P4withheld -.->|unblock| U3
  U3 -.-> P4c
  P4gate -->|yes| P4e --> P4f --> P4g --> RS1
  RS1 --> RS2 --> RS3 --> RS4 --> RS5
  U4 --> CS1

  class DA2,P4c inscope
  class P4d,P4g,P4e,P4f,CS1 candidate
  class U1,U2,U3,U4,O0,O1,O2,O3,DA1,P4a,P4b,P4gate,P4withheld,RS1,RS2,RS3,RS4,RS5 unaffected
```

## Reading the lanes

- **`resolve-ontology.sh`** runs inline, once per finding, inside the
  dimension-analyst's write loop (Phase 1) — this is the highest-frequency
  call site and the direct source of the measured per-finding subprocess
  cost.
- **`ontology-review.sh --topic`** runs once per topic per Phase 4 (every
  completed research run), immediately before the ADR-0011 fail-closed gate
  — a slow rebuild here delays every synthesis, not just a manual audit.
- Both are **in scope** for the ADR-0014 proof-of-concept (green). Every
  other script in Phase 4's gate chain — `check-shippable-typing.sh`,
  `build-concordance.sh`, `validate-concordance.sh`, `reconcile-session.sh`
  — and the separate, on-demand `synthesize-corpus.sh` are named in
  ADR-0014's Option 2 as *candidates* for a later, explicitly separate
  generalization decision (amber) — not authorized by the current proposal.
- The `report-synthesizer` lane (artifact rendering, README maintenance,
  citation integrity) is untouched by either the current proof-of-concept or
  the deferred candidates — it operates on already-typed findings and has no
  ontology-resolution cost of its own.
