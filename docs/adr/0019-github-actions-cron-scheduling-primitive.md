---
title: "GitHub Actions cron as the continuous-monitoring scheduling/trigger primitive"
description: "Continuous research-monitoring runs on a GitHub Actions cron schedule with git-native write-back via a review PR, not a cloud Routine or /loop."
type: adr
category: architecture
tags: [scheduling, continuous-monitoring, github-actions, cron, editorial-gate, write-back]
status: accepted
created: 2026-07-12
updated: 2026-07-12
author: zircote
project: research-harness-template
technologies: [GitHub Actions, Claude Code, Bash]
audience: [developers, architects, operators]
related: [0007-report-channel-canonical-blog-mif-exempt.md, 0008-attested-fail-closed-supply-chain.md]
---

# ADR-0019: GitHub Actions cron as the continuous-monitoring scheduling/trigger primitive

## Status

accepted

## Context

### Background and Problem Statement

Epic research-harness-template#416 (Continuous Research-Monitoring Capability)
needs a periodic trigger that scans external sources on a schedule, infers an
interest profile, produces candidate recommendations, and gets them in front
of a human reviewer before anything publishes. The source architecture doc's
AD-3 left the scheduling/trigger primitive `Proposed`: a native Claude Code
scheduling mechanism, or GitHub Actions cron. The choice constrains everything
downstream that touches scheduling or write-back — a cloud Routine has no
local file access, so a Routine-triggered run would need to delegate the
actual write-back to a separate mechanism that does.

### Current Limitations

The harness has no scheduling primitive of its own today. Every existing run
(`/start`, `/falsify`, `/resume`) is user-initiated inside an interactive
Claude Code session. Nothing currently runs unattended, and nothing writes to
`reports/<topic>/` without a human driving the session.

## Decision Drivers

### Primary Decision Drivers

1. PDD-1: Zero new paid infrastructure and no single-vendor lock-in beyond
   what the harness already depends on (this Epic's own driver list).
2. PDD-2: Must run unattended — an instance owner's machine being off, or no
   Claude Code session being open, must not stop the scheduled run.
3. PDD-3: Write-back must land in `reports/<topic>/` as git-native artifacts
   (NFR7), and every candidate recommendation must pass through a mandatory
   human Editorial Gate before publish (NFR6) — no fully automated path.

### Secondary Decision Drivers

1. SDD-1: Reuse infrastructure this repo already operates (GitHub Actions,
   its GitHub App token pattern in `ci.yml`, SHA-pinned actions) rather than
   introducing a new operational surface.
2. SDD-2: The mechanism must be something every `copier`-instantiated clone
   gets automatically, without per-instance cloud account setup.

## Considered Options

### Option 1: Cloud Routine (Anthropic-managed)

**Description:** A Claude Code Routine, scheduled via `/schedule`, runs on
Anthropic-managed infrastructure independent of any local machine or open
session.

- **Advantages:** No machine needs to be on; persistent across restarts;
  no local terminal/session dependency.
- **Disadvantages:** No access to local files — each run gets a fresh clone
  with no working-tree state, so it cannot commit or push on its own; it
  would need to delegate the actual write-back to a second mechanism (e.g.
  triggering a GitHub Actions workflow), which duplicates the scheduling
  surface for no benefit once that second mechanism exists anyway. Minimum
  interval is 1 hour (not a blocker for a weekly cadence, but a real
  constraint). Introduces a dependency on Anthropic-managed infrastructure
  and per-task connector configuration as an operational surface every
  instance owner would need to understand.
- **Risk Assessment:** technical medium (delegation mechanism is a second
  moving part); schedule medium (two systems to wire and keep in sync);
  ecosystem medium (a new account-level dependency for every instance).

### Option 2: GitHub Actions cron (chosen)

**Description:** A scheduled workflow (`schedule:` trigger, cron syntax)
runs on GitHub-hosted runners, checks out the repository, executes the
monitoring pipeline directly, and writes results back to `reports/<topic>/`
using the same GitHub App token pattern `ci.yml` already uses for
attested, least-privilege git operations.

- **Advantages:** Runs unattended with no machine or session dependency;
  full git working-tree access on every run (a real checkout, not a stub);
  zero new infrastructure — this repo and its CI already depend on GitHub
  Actions entirely; every `copier`-instantiated clone gets the workflow
  file automatically via the normal propagation path; a PR opened by the
  workflow doubles as the Editorial Gate's human checkpoint using tooling
  every operator already has (native GitHub PR review) — merge is accept,
  close is reject, satisfying NFR6 structurally rather than by convention.
- **Disadvantages:** Minimum practical interval is bounded by what's
  reasonable for a scheduled CI job (GitHub's own `schedule:` trigger can
  drift under load and is not to-the-minute precise) — acceptable for a
  weekly/periodic research-monitoring cadence, not for sub-hour polling.
- **Risk Assessment:** technical low (same toolchain and auth pattern
  `ci.yml`/`release.yml` already prove out); schedule low (no second
  system to build); ecosystem low (no new account-level dependency).

### Option 3: Hybrid — cloud Routine triggers a GitHub Actions workflow

**Description:** A Routine fires on Anthropic's schedule and calls the
GitHub API (`repository_dispatch` or `workflow_dispatch`) to kick off a
workflow that does the actual work and write-back.

- **Advantages:** Combines Routine-level scheduling flexibility with
  GitHub Actions' write-back access.
- **Disadvantages:** Two scheduling systems for one trigger with no
  capability GitHub Actions' own `schedule:` trigger doesn't already
  provide on its own; the Routine becomes a pure pass-through with no
  independent value once the workflow already does the real work; more
  operational surface for instance owners to configure and monitor.
- **Risk Assessment:** technical medium (two systems, one dependent on
  the other's availability); schedule medium; ecosystem medium (Routine
  account setup for zero net capability gain over Option 2 alone).

## Decision

Option 2. Continuous monitoring runs on a GitHub Actions `schedule:` cron
trigger, in a new `.github/workflows/monitor.yml` (Story: Scheduler/Trigger
wiring, research-harness-template#424, implements this concretely). The
workflow checks out the repo, runs the monitoring pipeline (Source
Connectors → Interest-Inference Engine → Recommendation Engine), then
commits accepted-candidate output to a dedicated branch
(`monitor/<topic>/<run-id>`) and opens a pull request against the default
branch using the same GitHub App token pattern `ci.yml` already uses
(`steps.app-token.outputs.token`). That pull request **is** the Editorial
Gate: merging it is the accept path into `publish-report`/`publish-blog`
(Output Router, research-harness-template#423); closing it without merge is
the reject path into the Continuity Log
(research-harness-template#421/#422). No code path writes directly to
`reports/<topic>/` on the default branch without going through this PR.

## Consequences

### Positive

1. No new paid infrastructure or account-level dependency — every
   `copier`-instantiated clone gets scheduling for free via the workflow
   file, matching this Epic's own zero-new-infrastructure driver.
2. The Editorial Gate reuses infrastructure every operator already
   understands (PR review) instead of a bespoke approval UI.
3. Full git write-back access on every run; no delegation mechanism to
   build, test, or keep in sync with a second scheduling system.

### Negative

1. Scheduling precision is bounded by GitHub Actions' `schedule:` trigger,
   which can run late under platform load — acceptable for this workload's
   weekly/periodic cadence, would not be for sub-hour polling.
2. A public repository's Actions minutes are shared with `ci.yml`/
   `release.yml`; a monitoring run's cost must stay bounded by NFR1's
   per-run budget so it doesn't crowd out other workflows.

### Neutral

1. Every instance owner who enables continuous monitoring gets one more
   scheduled workflow to be aware of in their Actions usage, the same way
   they already have `ci.yml`, `docs.yml`, and `release.yml`.

## Decision Outcome

GitHub Actions cron gives continuous monitoring unattended scheduling and
direct git write-back using infrastructure this repo already operates, and
folds the mandatory Editorial Gate into the review step of a PR the
scheduled workflow itself opens — no separate approval mechanism to design,
build, or explain to instance owners.

## Related Decisions

- ADR-0007: the report channel this Epic's Output Router publishes into.
- ADR-0008: the attested, fail-closed supply-chain posture the new workflow
  follows (SHA-pinned actions, App-token auth).

## More Information

- **Date:** 2026-07-12
- **Source:** research-harness-template#416, research-harness-template#417,
  Claude Code docs — [Run prompts on a schedule](https://code.claude.com/docs/en/scheduled-tasks)
  (session-scoped `/loop`/cron: 7-day expiry, requires an open session,
  ruled out for unattended production use) and its linked comparison of
  cloud Routines vs. Desktop scheduled tasks vs. GitHub Actions (Routines:
  no local file access, fresh clone per run, 1-hour minimum interval;
  Desktop: requires the operator's own machine to be on).

## Audit

### 2026-07-12

**Status:** Accepted

| Finding | Files | Assessment |
| --- | --- | --- |
| Scheduling primitive comparison sourced from current Claude Code docs, not assumed from training data | this ADR's More Information section | compliant |
| Write-back mechanism named concretely (PR-based, not a stub) | `.github/workflows/monitor.yml` (research-harness-template#424, not yet landed at ADR authoring time) | pending — tracked by #424 |

**Summary:** Decision settled and documented; concrete workflow implementation tracked by Story #424 per the Epic's build order.

**Action Required:** None for this ADR; research-harness-template#424 implements the decision.
