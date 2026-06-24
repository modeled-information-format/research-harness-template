---
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

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** trend

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

None beyond the core engine. Mermaid rendering is optional (required for the
transitional graph section, which degrades to a text representation when Mermaid
is unavailable).

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

### Enable

```sh
scripts/pack-toggle.sh trend-modeling on
```
