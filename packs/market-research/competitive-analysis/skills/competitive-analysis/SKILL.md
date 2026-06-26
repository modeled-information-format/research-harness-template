---
name: competitive-analysis
description: Use when the user asks to "analyze competitors", "map competitive landscape", "Porter's 5 Forces analysis", "competitor comparison", "competitive positioning", "identify competitors", "competitive intelligence", or needs competitor research methodology, market positioning analysis, or competitive strategy frameworks.
version: 0.3.0
---

# Competitive Analysis

Systematically evaluate competitors to understand positioning, identify gaps, and inform strategy. Produces a finding per insight with a confidence tier and trend indicator.

## Required Frameworks

| Framework | Output Section | Required | Condition |
| --- | --- | --- | --- |
| Porter's 5 Forces | Porter's 5 Forces Analysis | yes | — |
| Competitor Matrix | Competitive Matrix | yes | — |
| Positioning Map | Positioning Map | conditional | 2+ comparable dimensions available |
| Trend Indicators (INC/DEC/CONST) | throughout | yes | — |

## When to Use

Entering a new market, evaluating positioning, identifying feature/pricing gaps, assessing competitive threats, planning differentiation, or producing board/investor-ready landscape documents — including emerging markets with only indirect or potential competitors.

## Handling Incomplete Prompts

When the request lacks a market, industry, or competitor list, do NOT fabricate analysis. Acknowledge the request, ask clarifying questions (market/industry, product, known competitors, goal, target segment), and describe expected deliverables. Be helpful — never refuse outright.

## Adapting for Emerging Markets / New Categories

Competitive analysis is MORE important for new categories, not less.

1. Identify current substitutes (manual processes, consultants, existing tools, DIY).
2. Map indirect competitors from adjacent markets who could pivot in.
3. Identify potential entrants — well-funded adjacent players most likely to enter.
4. Adapt Porter's: rivalry typically LOW (temporary), threat of new entry HIGH, threat of substitution VERY HIGH.
5. Address first-mover and category-creation dynamics (advantages and risks).
6. Recommend on category definition, switching costs, and monitoring entrants.

## Porter's 5 Forces

For each force provide an explicit rating (HIGH/MODERATE/LOW/VERY HIGH), industry-specific factors, and an implications statement.

1. **Competitive Rivalry** — competitor count/size, growth rate, differentiation, exit barriers. High rivalry = challenging margins.
2. **Supplier Power** — concentration, switching costs, unique inputs, forward-integration threat. High power = cost pressure.
3. **Buyer Power** — concentration, purchase volume, switching costs, price sensitivity. High power = pricing pressure.
4. **Threat of Substitution** — alternatives, price-performance trade-off, switching costs, propensity to substitute. High threat = innovation pressure.
5. **Threat of New Entry** — capital requirements, economies of scale, brand loyalty, regulatory barriers. High threat = margin pressure.

## Competitor Matrix

| Dimension | Competitor A | Competitor B | Your Position |
| --- | --- | --- | --- |
| Market Share | % | % | % |
| Pricing | $-$$$ | $-$$$ | $-$$$ |
| Key Features | List | List | List |
| Strengths | List | List | List |
| Weaknesses | List | List | List |
| Trend | INC/DEC/CONST | INC/DEC/CONST | - |

## Positioning Map

Visualize positioning on two key dimensions (e.g., feature richness vs. premium positioning) as a Mermaid `quadrantChart` with labeled axes and all competitors as data points. When the user specifies axes, use those exact dimensions. Precede the chart with a rationale table explaining each placement.

## Research Process

1. **Identify competitors** — direct, indirect, potential entrants, substitutes.
2. **Gather intelligence** — websites, press, financials, job postings, social, reviews, analyst reports. Search patterns: `"[competitor] pricing"`, `"[competitor] vs [alternative]"`, `"[competitor] review"`, `"[competitor] funding/revenue"`.
3. **Analyze** — map to Porter's, build matrix, create positioning map, assign INC/DEC/CONST trends.
4. **Synthesize** — advantages/disadvantages, market gaps, threat assessment, recommendations.

## Trend Indicators (INC / DEC / CONST)

Apply three-valued logic to competitor trajectories:

- **INC** — growing share, expanding features, positive momentum.
- **DEC** — losing share, reducing investment, negative signals.
- **CONST** — stable, maintaining but not growing.

## Output Structure

```markdown
## Competitive Landscape Overview
## Porter's 5 Forces Analysis        [force-by-force with ratings]
## Competitor Profiles               [top 3-5]
## Competitive Matrix
## Positioning Map                   [Mermaid quadrant chart]
## Key Insights                      [insight + implication]
## Strategic Recommendations         [specific, actionable, context-tailored]
```

When the user states a context (e.g., "small dev teams", "board presentation"), tailor every section to it. Generic analysis is not acceptable.

## Confidence Tiers

- **High** — 3+ independent, recent (<12mo) sources that converge.
- **Medium** — 2 sources, OR sources >12mo old, OR indirect evidence.
- **Low** — single source, inference, or extrapolation.

Cross-reference sizing (validate share figures against TAM) and customer (switching costs, satisfaction gaps). Alert on an undiscovered competitor with >10% share, a share shift >20% in 12 months, or a disruptive new entrant.

## Best Practices

Refresh quarterly, cross-validate across sources, note source reliability and dates, distinguish fact from speculation, consider regional variation, and watch competitor job postings for strategy hints.
