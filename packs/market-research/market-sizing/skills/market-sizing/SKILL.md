---
name: market-sizing
description: Use when the user asks to "calculate market size", "TAM SAM SOM analysis", "estimate market opportunity", "market sizing", "total addressable market", "serviceable market", "market potential", or needs market-size estimation methodologies, opportunity calculations, or growth projections.
version: 0.3.0
---

# Market Sizing (TAM/SAM/SOM)

Quantify the revenue opportunity in a market. The TAM/SAM/SOM framework refines from total market to realistically achievable share.

## Required Frameworks

| Framework | Output Section | Required |
| --- | --- | --- |
| Methodology Selection | Methodology | yes |
| TAM/SAM/SOM Hierarchy | Market Sizing Summary | yes |
| Scenario Modeling | Scenarios | yes |
| Growth Projections (CAGR + INC/DEC/CONST) | Market Sizing Summary | yes |

## Key Definitions

- **TAM** — total global demand; assumes 100% share (theoretical ceiling).
- **SAM** — portion of TAM targetable with the current business model (geographic/segment constraints).
- **SOM** — realistic share achievable near-term (1-3 years) given competition, resources, and go-to-market.

## Methodology Selection

| User Signal | Methodology |
| --- | --- |
| "TAM SAM SOM", no pricing data | Top-Down |
| Provides pricing / unit / customer data | Bottom-Up |
| "value", "pain point cost", "willingness to pay" | Value Theory |
| "growth trends", "CAGR" | Top-Down + Trend Analysis |
| "bear/base/bull", "scenarios" | Any + Scenario Modeling |
| Vague, no segment | Top-Down (state assumptions) |
| Known declining market | Top-Down + DEC handling |

## Calculation Methodologies

**Top-Down** — start with industry market size from analyst reports, apply the target-segment percentage, adjust for geography, factor growth. Example: Global SaaS $200B → HR SaaS 15% = $30B → North America 40% = $12B (SAM) → 2% achievable = $240M (SOM). Fast but source-dependent.

**Bottom-Up** — build from unit economics; use the user's pricing figure when given. Identify addressable customer count, price per customer, then total revenue (show the multiplication). Example: 50,000 SMBs × $5,000 = $250M (SOM); 500,000 SMBs = $2.5B (SAM); +enterprise = $10B (TAM). More defensible, slower.

**Value Theory** — size by value delivered. Compute the customer pain-point cost (use the user's figure, e.g., "$4.5M per breach"), estimate the fraction the solution addresses, apply a capture rate (typically 10-30%, stated explicitly), then still produce full TAM/SAM/SOM. Example: $100K/yr problem × 20% capture × 100,000 customers = $2B.

## Trend Indicators (INC / CONST / DEC)

Always include a Trend column. Document evidence for each:

- **INC** — growing >10%/yr ("Analyst projects 25% CAGR through 2027").
- **CONST** — 0-10%/yr ("Mature market, 3% annual growth").
- **DEC** — contracting; show negative rate ("displaced legacy tech; revenue -12% YoY").

When the user asks about growth/CAGR specifically, add a sub-trend table breaking growth down by segment.

## Data Sources

- **Primary** — analyst reports (Gartner, Forrester, IDC), government statistics (Census, BLS), trade associations, public-company financials.
- **Secondary** — research firms (Statista, IBISWorld), news citing research, industry publications.
- **Estimation (use carefully)** — job counts × salary, search-volume proxies, downloads × price, traffic estimates.

## Critical Output Requirements

Every output MUST include all of:

1. A **"Market Sizing Summary"** table with TAM, SAM, SOM rows.
2. **Concrete dollar values** (`$18.5B`, `$240M`) — NEVER placeholders (`$X.XB`, `$XXM`, `[insert]`).
3. An explicit **methodology name** (Top-Down / Bottom-Up / Value Theory / Hybrid).
4. A **"Key Assumptions"** section with ≥2 numbered, specific assumptions.
5. A **"Data Sources"** section naming ≥1 source.
6. A **"Confidence Level"** section (High/Medium/Low + explanation).
7. **TAM > SAM > SOM** ordering.

## Output Structure

```markdown
## Market Sizing Summary

| Metric | Value | Growth | Trend |
|--------|-------|--------|-------|
| TAM | $18.5B | 15% CAGR | INC |
| SAM | $4.6B | 14% CAGR | INC |
| SOM | $92M | - | - |

## Methodology            [named]
## TAM Calculation        [step-by-step, cited, concrete]
## SAM Derivation         [narrowing % from TAM]
## SOM Justification      [share rationale]
## Key Assumptions        [≥2 numbered]
## Data Sources           [≥1 named]
## Confidence Level       [High/Medium/Low + why]
```

## Scenario Modeling

When scenarios are requested, satisfy **Bear < Base < Bull** for every metric, each with a driver rationale. Never use placeholder values in scenario tables.

| Scenario | TAM | SAM | SOM |
| --- | --- | --- | --- |
| Bear | $5B | $500M | $10M |
| Base | $8B | $800M | $25M |
| Bull | $12B | $1.2B | $50M |

## Validation

Before finalizing: TAM > SAM > SOM holds; no placeholders (`$X`, `[insert`, `$XXM`, `TBD`); any user-provided price/cost appears verbatim; a requested methodology is named; every trend indicator has a supporting data point.

## Handling Vague & Declining Markets

- **Vague** ("market size for drones") — state scope assumptions explicitly, name major segments, still produce full TAM/SAM/SOM, ask clarifying questions, never return a single number.
- **Declining** — use DEC with negative rates (`-12.5% CAGR`), add a year-over-year decline table, note entry/operating risks, still provide complete TAM/SAM/SOM, cite sources.

## Confidence Tiers

High = top-down and bottom-up converge within 20%. Medium = single methodology with 2+ supporting points. Low = single data point or methodology gaps. Cross-reference financial (revenue validates potential) and competitive (player count and share). Flag conflicts where summed competitor revenue exceeds total market size.
