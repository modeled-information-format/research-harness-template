---
name: regulatory-review
description: Use when the user asks to "analyze regulations", "regulatory landscape", "compliance requirements", "legal considerations", "regulatory risk", "industry regulations", "compliance analysis", "regulatory trends", or needs guidance on regulatory environments, compliance requirements, or legal market factors.
version: 0.4.0
---

# Regulatory Review

Assess the legal and compliance landscape affecting a market or product. Findings are research-grade, not compliance-grade — flag regulatory dependencies for qualified review.

## Required Frameworks

| Framework | Output Section | Required | Condition |
| --- | --- | --- | --- |
| Framework Identification | Applicable Frameworks | yes | — |
| Industry-to-Framework Mapping | Regulatory Mapping | yes | — |
| Penalty Ranges | Enforcement & Penalties | yes | — |
| Risk Matrix | Risk Assessment | yes | — |
| Cross-border Mechanisms | Cross-border Analysis | conditional | multi-jurisdiction scope |

## Major Frameworks

**Data privacy** — GDPR (EU), CCPA/CPRA (California), LGPD (Brazil), PIPL (China). **Financial** — Dodd-Frank, SOX (US), PSD2, MiCA (EU). **Healthcare** — HIPAA, HITECH, FDA 21 CFR (US), MDR (EU). **Children's** — COPPA / COPPA 2.0 (proposed), Age-Appropriate Design Codes; under-13 requires verifiable parental consent before collecting any personal info. **Consumer/advertising** — FTC Act §5, Prop 65, FDA DSHEA. **AI/tech** — EU AI Act, NYC Local Law 144 (bias audits), state AI bills, EEOC AI guidance.

### AI/ML Bias Audits

When AI/ML drives decisions affecting people (hiring, lending, insurance, housing): annual independent bias audit + 10-day candidate notice (NYC LL 144); high-risk conformity assessment (EU AI Act); adverse-impact / four-fifths analysis (EEOC, Title VII); algorithmic fairness assessment (Colorado SB 21-169).

## Industry → Framework Mapping

| Industry | Primary | Secondary |
| --- | --- | --- |
| Healthcare/Telehealth | HIPAA, HITECH, FDA 21 CFR | GDPR, state telehealth |
| Fintech/Crypto | Dodd-Frank, SEC, FCA | MiCA, MSB licensing, BSA/FinCEN |
| AI in Employment | NYC LL 144, EEOC, EU AI Act | state AI bills, CCPA/CPRA |
| Children's Apps | COPPA, FTC Act | CCPA minors, app-store policy |
| Medical Devices | FDA 21 CFR, EU MDR | TGA, PMDA, ISO 13485 |
| E-commerce/Supplements | FDA DSHEA, FTC Act, Prop 65 | CCPA/CPRA, cGMP |
| SaaS/Data Processing | GDPR, CCPA/CPRA | ePrivacy, HIPAA, PCI DSS |

## Risk Assessment

Categories: compliance risk (gaps vs. existing rules), regulatory-change risk (new/changing law), enforcement risk (scrutiny), reputational risk. Score each in a matrix:

| Risk | Likelihood | Impact | Trend | Mitigation |
| --- | --- | --- | --- | --- |
| [Risk] | H/M/L | H/M/L | INC/DEC/CONST | [Action] |

## Trend Indicators (INC / DEC / CONST)

- **INC** — new legislation, more enforcement, growing attention, international coordination.
- **DEC** — deregulation, reduced enforcement, political shift to less oversight.
- **CONST** — established framework, predictable enforcement, no pending change.

Current direction is INC across data privacy, AI/ML, crypto/fintech, big-tech competition, cybersecurity, and children's privacy.

## Cross-Border Transfers

When operations span jurisdictions, identify the mechanism: Standard Contractual Clauses (non-adequate countries; Transfer Impact Assessment required), adequacy decisions (verify current status — Schrems II), Binding Corporate Rules (intra-group, DPA approval), data localization (China/Russia/India), or consent-based (not for bulk transfers).

## Penalty Reference Ranges

| Framework | Maximum Penalty |
| --- | --- |
| GDPR | up to 4% global revenue or EUR 20M |
| HIPAA | $50K-$1.9M per violation category/year |
| COPPA | ~$50,120 per violation (adjusted) |
| NYC LL 144 | $500-$1,500 per violation/day |
| FTC Act | injunctive relief + restitution |
| FDA (devices) | warning letters, seizure, injunction, criminal |

## Output Rules

1. Use the exact section headings below; do not rename or skip.
2. Every Risk Matrix row includes a Trend column (`INC`/`DEC`/`CONST`).
3. Every Trend Analysis bullet uses `Area: INC/DEC/CONST - [Evidence]`.
4. Recommendations include ≥1 each of Immediate, Medium-term, and Monitoring action.
5. Compliance Assessment uses status symbols `✓` / `△` / `✗`.
6. Never write "This is not legal advice" in the output (disclaimer lives here, not in outputs).
7. Always include Monitoring Indicators with ≥3 specific sources (named regulatory bodies, legislative trackers).
8. Address cross-border transfer mechanisms when multiple jurisdictions are involved.
9. Address COPPA and parental consent when users may be minors.
10. Provide compliance-cost ranges by Technology, Personnel, Legal/Consulting, Training, Audit.

Render any regulatory timeline or approval-flow figure as a Mermaid `timeline` or
`flowchart`. Any figure, chart, or diagram is rendered as a fenced Mermaid code block (a
`mermaid` info-string fence), never ASCII art, an image link, or Graphviz/DOT; a
required figure is never silently omitted — if the data cannot support it, say so in
prose. Plain tabular matter stays a Markdown table.

## Output Structure

```markdown
## Regulatory Review Summary
### Regulatory Landscape        [narrative overview]
### Key Frameworks              [≥3: name | applicability | status]
### Compliance Assessment       [✓/△/✗ | gap | priority]
### Regulatory Risk Matrix      [likelihood | impact | trend]
### Trend Analysis              [≥3 bullets: Area: INC/DEC/CONST - Evidence]
### Estimated Compliance Costs  [Technology/Personnel/Legal/Training/Audit]
### Recommendations            [Immediate / Medium-term / Monitoring]
### Monitoring Indicators       [≥3 named sources]
```

## Confidence Tiers

High = published regulation or official government announcement. Medium = proposed regulation in comment period or credible policy analysis. Low = speculative on political signals. Cross-reference trends (policy direction) and competitive (competitors' compliance status). Alert on a new regulation with <12 months to deadline, action against a major competitor, or a policy shift enabling/blocking entry.

## Disclaimer

This skill provides research frameworks only. Consult qualified legal counsel for compliance decisions.
