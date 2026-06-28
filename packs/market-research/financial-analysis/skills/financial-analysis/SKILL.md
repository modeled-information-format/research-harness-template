---
name: financial-analysis
description: Use when the user asks to "analyze financials", "revenue model", "unit economics", "pricing analysis", "cost structure", "profitability analysis", "financial projections", "business model economics", or needs financial-metric, revenue-analysis, or economic-viability guidance.
version: 0.3.0
---

# Financial Analysis

Evaluate economic viability and business-model health through metrics, projections, and benchmarking.

## Required Frameworks

| Framework | Output Section | Required |
| --- | --- | --- |
| Unit Economics | Unit Economics | yes |
| Revenue Model Classification | Revenue Model | yes |
| Pricing Strategy | Pricing Analysis | yes |
| Cost Structure | Cost Structure | yes |
| Rule of 40 | Profitability Assessment | yes |

## Unit Economics

- **CAC** — sales & marketing spend ÷ new customers (SaaS benchmark $50-$500+).
- **LTV** — ARPU ÷ churn × gross margin.
- **LTV:CAC** — target ≥3:1; `<1:1 unsustainable; >`5:1 may be under-investing.
- **Payback Period** — CAC ÷ (ARPU × gross margin); target <12mo for SaaS.

## Revenue Metrics

MRR (recurring revenue), ARR (MRR × 12), ARPU (revenue ÷ customers), NRR ((start MRR + expansion − contraction − churn) ÷ start MRR; target >100%). Growth: MoM, YoY, CAGR = ((End ÷ Start)^(1/years)) − 1.

## Revenue Models

| Model | Key Metrics | Trend |
| --- | --- | --- |
| Subscription (SaaS) | MRR, ARR, churn, NRR | INC |
| Usage-Based | usage growth, ARPU, expansion | INC |
| Transactional | volume, take rate, AOV | CONST |
| Marketplace | GMV, take rate, liquidity | CONST |
| Enterprise Licensing | deal size, renewal, services % | DEC |

## Pricing Analysis

| Strategy | Description | Best For |
| --- | --- | --- |
| Cost-plus | cost + margin | commodities |
| Value-based | % of customer value | differentiated products |
| Competitive | relative to alternatives | crowded markets |
| Penetration | low to gain share | new entrants |
| Premium | high for positioning | luxury/enterprise |

Pricing power: **Strong** (increases stick, low churn), **Moderate** (some sensitivity), **Weak** (commodity, price-driven).

## Cost Structure

Fixed (rent, salaries, infra → operating leverage), variable (COGS, commissions, hosting → scales with revenue), semi-variable (support, marketing). Gross margin norms: SaaS 70-85%, services 30-50%, marketplace varies by take rate. High fixed + low variable = high operating leverage (good growing, risky declining).

## Profitability

| Metric | Formula | Benchmark |
| --- | --- | --- |
| Gross Margin | (Rev − COGS) / Rev | 70%+ SaaS |
| Operating Margin | Op. Income / Rev | 20%+ mature |
| Net Margin | Net Income / Rev | 10%+ profitable |

**Rule of 40 (SaaS)** — Growth % + Profit Margin % ≥ 40. Growing 50% allows −10% margin; growing 20% needs 20% margin; below 40 is an investor concern.

## SaaS Benchmarks by Stage

| Metric | Early | Growth | Scale |
| --- | --- | --- | --- |
| Growth Rate | >100% | 50-100% | 20-50% |
| Gross Margin | 60%+ | 70%+ | 75%+ |
| NRR | >100% | >110% | >120% |
| LTV:CAC | >3:1 | >3:1 | >4:1 |
| Payback | <18mo | <12mo | <12mo |

## Projections

1. **Revenue** — customer growth × ARPU, with expansion/contraction and INC/DEC/CONST trends.
2. **Cost** — fixed + (variable rate × revenue), step functions for scaling.
3. **Cash flow** — operating generation, capital requirements, runway.

Scenario table (Bear < Base < Bull on growth, margin, cash position).

Render financial trend and projection charts (revenue, cost, cash flow over time) as a
Mermaid `xychart-beta`. Any figure, chart, or diagram is rendered as a fenced Mermaid
code block (a `mermaid` info-string fence), never ASCII art, an image link, or
Graphviz/DOT; a required figure is never silently omitted — if the data cannot support
it, say so in prose. Plain tabular matter stays a Markdown table.

## Output Structure

```markdown
## Financial Analysis Summary
### Business Model       [type, revenue streams, pricing strategy]
### Key Metrics          [table: value | benchmark | assessment]
### Unit Economics       [CAC, LTV, payback, LTV:CAC]
### Trend Indicators     [revenue / margin / unit-economics: INC/DEC/CONST]
### Financial Health Assessment
### Projections          [3-year scenarios]
### Recommendations
```

## Confidence Tiers

High = public financial data (filings, earnings) with 2+ quarters. Medium = credible analyst estimates or partial public data. Low = proxy-estimated or single data point. Cross-reference sizing (market size validates revenue potential) and competitive (competitor revenue/pricing). Alert on LTV:CAC < 1, revenue-model mismatch, or margin compression threatening viability. Distinguish reported vs. estimated figures and note data recency.
