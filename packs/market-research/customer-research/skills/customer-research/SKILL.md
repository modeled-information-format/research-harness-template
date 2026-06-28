---
name: customer-research
description: Use when the user asks to "understand customers", "customer research", "user personas", "customer needs analysis", "buyer journey mapping", "voice of customer", "customer segmentation", "user research", or needs guidance on customer-discovery methodologies, persona development, or buyer behavior.
version: 0.4.1
---

# Customer Research

Systematically gather insights about target users to inform product and market decisions — needs, behaviors, and preferences.

## Required Frameworks

| Framework | Output Section | Required |
| --- | --- | --- |
| Persona Development | Customer Personas | yes |
| Jobs-to-be-Done | JTBD Analysis | yes |
| Journey Mapping | Customer Journey | yes |
| Segmentation & Prioritization | Customer Segments | yes |

## Research Types

- **Quantitative** — surveys, usage analytics, A/B results, market-share data, NPS/satisfaction.
- **Qualitative** — interviews, focus groups, observation, support-ticket analysis, review mining (G2, Capterra, TrustRadius, app stores, Reddit, social, forums). Look for repeated complaints, feature requests, competitor comparisons, use cases, and emotional language.

## Persona Development

Capture demographics (role, industry, company size, location), psychographics (goals, pain points, decision style, information sources, tech comfort), and behaviors (current solutions, buying process, triggers, evaluation criteria).

```markdown
## [Persona Name]
### Profile         [role, company size/industry, experience]
### Goals           [primary, secondary, tertiary]
### Pain Points     [major → minor]
### Quote           ["representative statement"]
### Buying Behavior [trigger, research, decision influence, timeline]
### Preferred Channels
```

## Jobs-to-be-Done

Focus on what customers are trying to accomplish across functional jobs (core task, measurable outcome), emotional jobs (how they want to feel, social perception), and related jobs (before/after the core job).

Statement format: **"When [situation], I want to [motivation], so I can [expected outcome]."**

## Customer Journey

Stages: Awareness → Consideration → Decision → Purchase → Onboarding → Retention/Advocacy. Map each in a table:

| Stage | Actions | Thoughts | Emotions | Pain Points | Opportunities |
| --- | --- | --- | --- | --- | --- |

When the journey is shown as a figure rather than the stage table above, render it as a
Mermaid `timeline` (or `journey`). Any figure, chart, or diagram is rendered as a fenced
Mermaid code block (a `mermaid` info-string fence), never ASCII art, an image link, or
Graphviz/DOT; a required figure is never silently omitted — if the data cannot support
it, say so in prose. Plain tabular matter stays a Markdown table.

## Segmentation

Criteria: demographic (size, industry, role), behavioral (usage, buying frequency), needs-based (problem severity, sophistication), value-based (revenue potential, strategic fit). Prioritize:

| Segment | Size | Need Intensity | Accessibility | Competition | Priority |
| --- | --- | --- | --- | --- | --- |
| [Name] | S/M/L | H/M/L | H/M/L | H/M/L | 1-5 |

## Output Structure

```markdown
## Customer Research Summary
### Key Segments       [description, size]
### Personas
### Jobs-to-be-Done
### Journey Insights    [awareness / consideration / decision]
### Pain Points (Ranked)
### Opportunities       [unmet needs]
### Trend Indicators    [sophistication / willingness-to-pay / switching: INC/DEC/CONST]
```

## Mandatory Output Rules

1. Every persona includes name, role, company size, key pain points, buying triggers.
2. Every segment includes a size estimate, growth direction (INC/DEC/CONST), and confidence level.
3. All claims cite specific sources.
4. NEVER use placeholder values (`$X`, `TBD`, `[insert]`).
5. Identify at least 3 customer segments.
6. Record open questions and unknowns as explicit gaps in the findings.

## Trend Indicators (INC / DEC / CONST)

Apply to customer-behavior metrics: customer sophistication, willingness to pay, and switching propensity. INC = rising, DEC = falling, CONST = stable.

## Confidence Tiers

High = multiple customer data sources (surveys, reviews, interviews) align. Medium = 2 sources or strong proxy indicators. Low = single source or inferred from adjacent markets. Cross-reference competitive (feature gaps → unmet needs) and financial (willingness to pay, price sensitivity). Alert on an unmet need with no existing solution, a newly discovered segment, or a switching-cost barrier that invalidates competitive assumptions.

## Best Practices

Talk to actual customers (including churned and non-customers), distinguish stated vs. revealed preferences, quantify qualitative insights where possible, and refresh regularly as behaviors change.
