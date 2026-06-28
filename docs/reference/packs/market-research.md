---
title: "Market-research packs"
diataxis_type: reference
---

# Market-research packs

Market-research packs are methodology dimensions. Each one adds a research skill that
the core engine invokes to analyze a specific aspect of a market. Methodology packs
contribute structured analytical frameworks; they do not produce standalone deliverables —
their outputs feed the findings corpus that report and channel packs consume.
Market-research packs have no *required* external dependencies beyond the core engine. Some packs emit Mermaid diagrams, which you can optionally render with `@mermaid-js/mermaid-cli` (for example in PDF/HTML output).
For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## competitive-analysis

**Version:** 0.4.0 | **Kind:** methodology | **Dimension:** competitive

**Source:** [`packs/market-research/competitive-analysis/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/market-research/competitive-analysis)

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

### Constraints

- Opt-in: ships disabled; enable with `scripts/pack-toggle.sh competitive-analysis on`.
- No external dependencies beyond the core engine; Mermaid rendering of the positioning map is optional.
- Bound to Porter's 5 Forces and INC/DEC/CONST trend logic as required analytical frames.
- Positioning map is conditional on 2+ comparable dimensions present in the findings.
- Analysis runs over the findings corpus; claims must meet confidence tiers (High/Medium/Low).

### Goals

- Deliver a `competitive` dimension finding covering Porter's 5 Forces with explicit force ratings.
- Produce a competitor matrix with INC/DEC/CONST trajectory indicators per player.
- Emit a Mermaid `quadrantChart` positioning map when data supports two-dimensional comparison.
- Supply strategic recommendations tailored to the stated research context.

### Enable

```sh
scripts/pack-toggle.sh competitive-analysis on
```

---

## customer-research

**Version:** 0.4.0 | **Kind:** methodology | **Dimension:** customer

**Source:** [`packs/market-research/customer-research/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/market-research/customer-research)

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

### Constraints

- Opt-in: ships disabled; enable with `scripts/pack-toggle.sh customer-research on`.
- No external dependencies beyond the core engine.
- Bound to four required frameworks: Persona Development, JTBD, Journey Mapping, and Segmentation — all must appear in every output.
- Every persona requires name, role, company size, key pain points, and buying triggers; ≥3 customer segments are required; placeholder values are prohibited.
- Analysis runs over the findings corpus; all claims must cite specific sources.

### Goals

- Deliver a `customer` dimension finding covering all four frameworks in a single pass.
- Produce ≥3 prioritized segments each with size estimate, growth direction (INC/DEC/CONST), and confidence level.
- Map the six-stage customer journey (Awareness through Retention/Advocacy) with pain points and opportunities per stage.
- Surface JTBD statements grounded in customer goals and record open questions as explicit gaps.

### Enable

```sh
scripts/pack-toggle.sh customer-research on
```

---

## financial-analysis

**Version:** 0.4.0 | **Kind:** methodology | **Dimension:** financial

**Source:** [`packs/market-research/financial-analysis/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/market-research/financial-analysis)

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

### Constraints

- Opt-in: ships disabled; enable with `scripts/pack-toggle.sh financial-analysis on`.
- No external dependencies beyond the core engine.
- Bound to five required frameworks: Unit Economics, Revenue Model Classification, Pricing Strategy, Cost Structure, and Rule of 40.
- Outputs must use actual figures — placeholder values are prohibited; reported vs. estimated figures must be distinguished with data recency noted.
- Analysis runs over the findings corpus; a confidence tier (High/Medium/Low) is required for every output.

### Goals

- Deliver a `financial` dimension finding covering unit economics (CAC, LTV, LTV:CAC ratio, Payback Period).
- Produce a Rule of 40 assessment and SaaS benchmark comparison by stage (Early/Growth/Scale).
- Classify revenue streams with INC/DEC/CONST trend indicators.
- Model Bear/Base/Bull scenarios when requested, each with driver rationale.
- Flag sustainability risks such as LTV:CAC < 1, revenue-model mismatch, or margin compression.

### Enable

```sh
scripts/pack-toggle.sh financial-analysis on
```

---

## market-sizing

**Version:** 0.4.0 | **Kind:** methodology | **Dimension:** sizing

**Source:** [`packs/market-research/market-sizing/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/market-research/market-sizing)

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

### Constraints

- Opt-in: ships disabled; enable with `scripts/pack-toggle.sh market-sizing on`.
- No external dependencies beyond the core engine.
- Bound to the TAM > SAM > SOM hierarchy; concrete dollar values are required — placeholder values (`$X`, `TBD`, `[insert]`) are prohibited.
- Every output must name an explicit methodology (Top-Down, Bottom-Up, or Value Theory), state ≥2 key assumptions, cite ≥1 data source, and declare a confidence level (High/Medium/Low).
- Analysis runs over the findings corpus; top-down and bottom-up results must be cross-validated when both are available.

### Goals

- Deliver a `sizing` dimension finding with a complete TAM/SAM/SOM table using concrete dollar values.
- Apply the appropriate sizing methodology based on available data and name it explicitly.
- Include CAGR figures and INC/DEC/CONST trend indicators for each tier.
- Model Bear/Base/Bull scenarios with driver rationale when requested.
- Flag cross-validation conflicts where summed competitor revenue exceeds total market size.

### Enable

```sh
scripts/pack-toggle.sh market-sizing on
```

---

## regulatory-review

**Version:** 0.4.0 | **Kind:** methodology | **Dimension:** regulatory

**Source:** [`packs/market-research/regulatory-review/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/market-research/regulatory-review)

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

### Constraints

- Opt-in: ships disabled; enable with `scripts/pack-toggle.sh regulatory-review on`.
- No external dependencies beyond the core engine.
- Outputs are research-grade only; qualified legal counsel review is required before acting on findings.
- Bound to the industry-to-framework mapping table (seven categories) and a risk matrix with INC/DEC/CONST trend indicators; recommendations must include ≥1 Immediate, ≥1 Medium-term, and ≥1 Monitoring action.
- Cross-border transfer mechanism analysis is conditional on multi-jurisdiction scope; analysis runs over the findings corpus.

### Goals

- Deliver a `regulatory` dimension finding that maps applicable frameworks to the target industry or product.
- Produce a risk matrix covering compliance, regulatory-change, enforcement, and reputational risk with trend indicators.
- Document penalty reference ranges for applicable frameworks (GDPR, HIPAA, COPPA, NYC LL 144, FTC Act, FDA).
- Include cross-border transfer mechanism analysis (SCCs, adequacy decisions, BCRs) when multiple jurisdictions are in scope.
- Surface AI/ML bias audit requirements (NYC LL 144, EU AI Act, EEOC) when AI drives decisions affecting people.

### Enable

```sh
scripts/pack-toggle.sh regulatory-review on
```
