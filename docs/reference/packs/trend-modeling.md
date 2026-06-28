---
title: "Trend-modeling pack"
diataxis_type: reference
---

# Trend-modeling pack

The trend-modeling pack is a methodology dimension. It applies three-valued logic —
INC (increasing), DEC (decreasing), CONST (constant) — to analyze markets when precise
numerical data is unavailable. It enables meaningful directional analysis with minimal
information and produces a complete enumeration of consistent scenarios.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## trend-modeling

**Version:** 0.4.1 | **Kind:** methodology | **Dimension:** trend

**Source:** [`packs/trend-modeling/trend-modeling/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/trend-modeling/trend-modeling)

### Purpose

Models market or system behavior by assigning INC / DEC / CONST to a set of variables
and systematically generating all scenarios consistent with the declared relationships
between them. A Mermaid `stateDiagram-v2` transitional scenario graph is required.

The three values extend with acceleration modifiers when the data supports them:
AG (accelerating growth), DG (decelerating growth), AD (accelerating decline),
DD (decelerating decline). Pairwise relationships are expressed as `INC(X, Y)`
(X and Y move together) or `DEC(X, Y)` (X and Y move oppositely).

### When to use

Use `trend-modeling` when:

- Data is scarce or unreliable
- Relationships between variables are qualitative rather than quantitative
- Uncertainty is high and quick directional insight is needed
- Scenario planning is required but numerical constants or parameters are unavailable

### What it provides

Six required output sections:

| Section | Content |
| --- | --- |
| Variables | Variable name, current state, trend, confidence |
| Relationship Matrix | INC / DEC pairwise relationships between all variables |
| Generated Scenarios | All consistent variable assignments; terminal flag per scenario |
| Transitional Graph | Mermaid `stateDiagram-v2` showing scenario transitions |
| Terminal Scenario Analysis | Equilibrium conditions, trade-offs, recommendation |
| Trade-offs | Multi-objective conflicts at terminal scenarios |

### Dependencies

None beyond the core engine. The transitional graph is emitted as a Mermaid
`stateDiagram-v2` code block (plain text), so the pack runs with no extra tools.
Mermaid tooling is optional and only needed to *render* that block into an image
(for example in PDF or HTML output).

### Benefits

- Three-valued logic produces a complete list of all consistent futures without
  requiring numerical parameters — the full scenario space is enumerable from
  qualitative inputs alone
- Terminal scenario identification surfaces equilibrium states automatically, so
  planners know where the system converges rather than guessing
- INC / DEC / CONST notation integrates directly with the same trend vocabulary used
  by competitive-analysis, financial-analysis, market-sizing, and regulatory-review,
  making cross-dimension synthesis coherent
- Transitional graph makes scenario paths and branching points visible, so the
  transitions between scenarios receive as much attention as the endpoints

### Confidence tiers

| Tier | Basis |
| --- | --- |
| High | Inputs validated by 3+ independent dimension findings |
| Medium | Inputs from 2 dimensions with reasonable assumptions |
| Low | Speculative or single-dimension basis |

Alert conditions: a scenario with >50% probability of adverse outcome, a bifurcation
point within the planning horizon, or a terminal scenario that invalidates core
business assumptions.

### Constraints

- Ships disabled; enable with `scripts/pack-toggle.sh trend-modeling on`.
- Formal notation is limited to three values (INC / DEC / CONST) plus optional
  acceleration modifiers — no numerical parameters are accepted.
- Mermaid CLI is optional; the `stateDiagram-v2` block is emitted as plain text
  and only needs Mermaid tooling to render it into an image.
- All input variables and declared relationships must be grounded in the findings
  corpus; speculative relationships must be documented explicitly.

### Goals

- Produce a complete, enumerated list of all internally consistent scenarios from
  qualitative variable assignments.
- Identify and flag terminal scenarios — equilibrium states where the system
  converges — automatically.
- Emit a `stateDiagram-v2` transitional graph that makes scenario paths and
  branching points explicit.
- Deliver multi-objective trade-off analysis at each terminal scenario with a
  priority-aligned recommendation.
- Assign a confidence tier (High / Medium / Low) scaled to the number of
  independent dimension findings supplying the input variables.

### Enable

```sh
scripts/pack-toggle.sh trend-modeling on
```
