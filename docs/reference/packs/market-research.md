---
diataxis_type: reference
---

# Market-research packs

Market-research packs are methodology dimensions. Each one adds a research skill that
the core engine invokes to analyze a specific aspect of a market. Methodology packs
contribute structured analytical frameworks; they do not produce standalone deliverables —
their outputs feed the findings corpus that report and channel packs consume.

All market-research packs have no external dependencies beyond the core engine.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## competitive-analysis

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** competitive

### Purpose

Analyzes the competitive landscape using Porter's 5 Forces, a competitor matrix, and
a positioning map. Trend indicators (INC / DEC / CONST) annotate each competitor's
trajectory. The positioning map is a Mermaid `quadrantChart` and is conditional on
two or more comparable dimensions being present.

### When to use

Use `competitive-analysis` when research requires understanding market structure,
competitor positioning, competitive intensity, or direction of travel for individual
players.

### What it provides

- Porter's 5 Forces analysis (required)
- Competitor matrix with INC / DEC / CONST trajectory indicators (required)
- Mermaid `quadrantChart` positioning map (conditional: 2+ comparable dimensions)

### Dependencies

None beyond the core engine. Mermaid rendering is optional.

### Benefits

- INC / DEC / CONST trajectory indicators make directional competitive change legible
  without requiring precise numerical data
- Conditional positioning map avoids forcing a chart when the data does not support
  meaningful two-dimensional comparison
- Porter's 5 Forces provides a consistent structural frame across all competitive findings

### Enable

```sh
scripts/pack-toggle.sh competitive-analysis on
```

---

## customer-research

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** customer

### Purpose

Structures customer understanding through four frameworks: Persona Development, Jobs
to Be Done (JTBD), Journey Mapping, and Segmentation. Journey Mapping covers six
stages: Awareness → Consideration → Decision → Purchase → Onboarding →
Retention / Advocacy.

### When to use

Use `customer-research` when research requires understanding who the customer is, what
they are trying to accomplish, how they move through the buying and usage cycle, or how
the market segments by need or behavior.

### What it provides

- Persona Development framework
- Jobs to Be Done (JTBD) framework
- Customer Journey Map across six stages (Awareness through Retention/Advocacy)
- Market Segmentation framework

### Dependencies

None beyond the core engine.

### Benefits

- Four frameworks in a single skill means customer understanding accumulates across
  dimensions rather than requiring separate passes
- Six-stage journey model captures the full post-purchase lifecycle, not just acquisition
- JTBD framing keeps persona insights grounded in customer goals rather than demographics

### Enable

```sh
scripts/pack-toggle.sh customer-research on
```

---

## financial-analysis

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** financial

### Purpose

Analyzes financial characteristics of a market or business. Covers unit economics
(CAC, LTV, LTV:CAC ratio, Payback Period), the Rule of 40, SaaS benchmark comparisons
by stage (Early / Growth / Scale), and a revenue-model table with INC / DEC / CONST
trend indicators.

### When to use

Use `financial-analysis` when research requires understanding the economics of a market —
whether a business model is viable, how unit economics compare to stage benchmarks, or
which revenue streams are growing versus declining.

### What it provides

- Unit economics: CAC, LTV, LTV:CAC ratio, Payback Period
- Rule of 40 calculation and interpretation
- SaaS benchmark comparison by stage (Early / Growth / Scale)
- Revenue model table with INC / DEC / CONST trend indicators

### Dependencies

None beyond the core engine.

### Benefits

- Stage-specific SaaS benchmarks give findings context relative to comparable companies,
  not just absolute numbers
- Rule of 40 provides a single composite health signal that combines growth and
  profitability
- INC / DEC / CONST revenue-model trends make directional financial change readable
  without requiring precise forecasts

### Enable

```sh
scripts/pack-toggle.sh financial-analysis on
```

---

## market-sizing

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** sizing

### Purpose

Quantifies the revenue opportunity in a market using the TAM / SAM / SOM hierarchy.
Supports three calculation methodologies — Top-Down, Bottom-Up, and Value Theory —
selected based on the available data. All outputs require concrete dollar values,
a named methodology, key assumptions, at least one data source, and a stated
confidence level.

### When to use

Use `market-sizing` when research requires a defensible market-opportunity estimate —
for investment analysis, go-to-market planning, or prioritization between market segments.

### What it provides

- TAM / SAM / SOM hierarchy with concrete dollar values (no placeholders)
- Three methodology modes: Top-Down, Bottom-Up, Value Theory
- Scenario modeling (Bear / Base / Bull) when requested
- Growth projections with INC / DEC / CONST trend indicators and CAGR figures
- Required sections: Methodology, Key Assumptions (≥2), Data Sources (≥1),
  Confidence Level

### Dependencies

None beyond the core engine.

### Benefits

- Three methodology modes mean the skill adapts to available data rather than requiring
  a specific data format
- Mandatory concrete dollar values and named methodology make outputs auditable and
  comparable across findings
- Bear / Base / Bull scenario modeling makes uncertainty explicit rather than collapsing
  it to a single point estimate

### Enable

```sh
scripts/pack-toggle.sh market-sizing on
```

---

## regulatory-review

**Version:** 0.1.2 | **Kind:** methodology | **Dimension:** regulatory

### Purpose

Assesses the legal and compliance landscape affecting a market or product. Maps
industries to applicable frameworks (GDPR, CCPA/CPRA, HIPAA, HITECH, COPPA, FDA,
Dodd-Frank, EU AI Act, NYC LL 144, and others), produces a risk matrix with
INC / DEC / CONST trend indicators, documents penalty reference ranges, and covers
cross-border transfer mechanisms when multiple jurisdictions are in scope.

Outputs are research-grade, not compliance-grade. Qualified legal counsel review is
required before acting on findings.

### When to use

Use `regulatory-review` when research requires understanding regulatory exposure, mapping
applicable frameworks to an industry or product, or tracking the direction of regulatory
change over time.

### What it provides

- Industry-to-framework mapping table (seven industry categories, primary and secondary
  frameworks)
- Risk matrix: Likelihood / Impact / Trend (INC / DEC / CONST) / Mitigation per risk
- Penalty reference ranges for major frameworks (GDPR, HIPAA, COPPA, NYC LL 144,
  FTC Act, FDA)
- Cross-border transfer mechanism analysis (SCCs, adequacy decisions, BCRs, data
  localization, consent) — conditional on multi-jurisdiction scope
- AI / ML bias audit requirements (NYC LL 144, EU AI Act, EEOC, Colorado SB 21-169)
  when AI drives decisions affecting people

### Dependencies

None beyond the core engine.

### Benefits

- INC / DEC / CONST trend indicators on the risk matrix make the direction of regulatory
  change legible, not just the current exposure level
- Penalty reference ranges ground risk severity in real enforcement figures
- Cross-border mechanism section is conditional, so it only appears when the findings
  scope includes multiple jurisdictions

### Enable

```sh
scripts/pack-toggle.sh regulatory-review on
```
