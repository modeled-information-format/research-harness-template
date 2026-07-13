---
title: "Single adversarial falsification gate with ordinal verdicts"
description: "Run one adversarial verification pass that assigns ordinal verdicts, applies proportionate remediation, and enforces a one-round rule."
type: adr
category: architecture
tags: [falsification, verification, quality-gate, verdicts, remediation]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [MIF, Bash, jq, Claude Code]
audience: [developers, architects]
related: [0002-mif-level-3-io-conformance.md, 0007-report-channel-canonical-blog-mif-exempt.md]
---

# ADR-0004: Single adversarial falsification gate with ordinal verdicts

## Status

Accepted

## Context

### Background and Problem Statement

Research findings are only as trustworthy as the scrutiny they survive. The
harness needs a verification step that treats each finding as a hypothesis under
test and actively seeks disconfirming evidence (`falsification-analyst` agent,
`scripts/falsify.sh`, design spec §6b). The question is how many passes run, what
verdict vocabulary they emit, and how remediation is applied.

### Current Limitations

Verification can recurse forever, and multiple competing gates would produce
contradictory verdicts. Without a defined vocabulary and a termination rule,
verification is neither machine-actionable nor bounded.

## Decision Drivers

### Primary Decision Drivers

1. Verification must be adversarial: seek to refute, not to confirm.
2. The process must terminate — no unbounded re-falsification recursion.

### Secondary Decision Drivers

1. Verdicts must be machine-actionable and ordered, not free text.
2. Remediation must be deterministic and proportionate to the verdict.

## Considered Options

### Option 1: No gate

**Description:** Ship findings as gathered, with no verification pass.

- **Advantages:** Fastest path from gathering to publication.
- **Disadvantages:** Unverified claims ship; the harness has no defensible quality bar.
- **Risk Assessment:** technical low; schedule low; ecosystem high.

### Option 2: Binary pass/fail gate

**Description:** A single gate accepts or rejects each finding outright.

- **Advantages:** Simple to reason about.
- **Disadvantages:** Collapses real nuance — a claim that is narrowed by evidence is neither cleanly accepted nor cleanly rejected, forcing a lossy choice.
- **Risk Assessment:** technical low; schedule low; ecosystem medium.

### Option 3: Single gate with ordinal verdicts

**Description:** One adversarial pass decomposes a finding into atomic claims, runs disconfirming web search, assigns an ordinal verdict, applies proportionate remediation, and enforces a one-round rule.

- **Advantages:** Verdicts are ordered (`falsified` = ≥1 credible source contradicts; `weakened` = ≥1 source narrows; `survived` = queries ran, nothing disconfirming found; `inconclusive` = could not test); remediation is deterministic (falsified → quarantine, weakened → downgrade one level, survived/inconclusive → annotate only); the one-round rule stops recursion.
- **Disadvantages:** The truthfulness of a `survived` verdict rests on agent discipline; no gate can prove disconfirming search was honestly performed.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 3: a single gate with ordinal verdicts.** The
`falsification-analyst` is the one adversarial pass. It writes the verdict
through `scripts/falsify.sh` into `extensions.harness.verification`, applies
proportionate remediation, and enforces the one-round rule —
`falsify.sh` refuses to re-falsify a finding that already carries an
`attempted_at` verdict and logs exactly one gate-run line so a caller can assert
the gate ran once.

## Consequences

### Positive

1. Verdicts are ordered, machine-actionable, and lead to deterministic
   remediation; the gate fails closed on structural conformance.
2. The one-round rule guarantees termination.

### Negative

1. Verdict honesty is a residual agent-integrity assumption that no gate can
   prove.

### Neutral

1. Findings carry their verdict inline under `extensions.harness.verification`,
   so the record travels with the finding.

## Decision Outcome

A single adversarial gate gives every finding an ordered, actionable verdict and
proportionate remediation, while the one-round rule bounds the process. The
residual trust in verdict honesty is stated plainly rather than implied away, and
is the same assumption that applies to any agent-driven research step.

## Related Decisions

- [ADR-0002: MIF Level-3 I/O conformance](0002-mif-level-3-io-conformance.md)
- [ADR-0007: Canonical report channel; blog MIF-exempt](0007-report-channel-canonical-blog-mif-exempt.md)

## Links

- `scripts/falsify.sh`, design spec §6b (falsification-analyst)

## More Information

- **Date:** 2026-06-23
- **Source:** `scripts/falsify.sh`, design spec §6b (falsification-analyst)

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Gate substrate writes the verdict | `scripts/falsify.sh` | compliant |
| Verdict stored in the MIF extension | `schemas/findings.schema.json` (`extensions.harness.verification`) | compliant |
| One-round rule enforced | `scripts/falsify.sh` (`attempted_at` guard) | compliant |

**Summary:** `scripts/falsify.sh` implements the ordinal verdict model, writes to `extensions.harness.verification`, and enforces the one-round rule via the `attempted_at` guard.

**Action Required:** None
