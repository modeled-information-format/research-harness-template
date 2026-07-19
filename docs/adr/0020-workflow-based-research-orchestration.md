---
title: "Workflow-tool orchestration as a parallel path to the orchestrator subagent"
description: "A deterministic Claude Code Workflow script (research.js) replaces the orchestrator subagent's poll/reap coordination loop for full-, augment-, and update-mode research sessions, invoked via /research alongside the existing /start."
type: adr
category: architecture
tags: [orchestration, workflow-tool, research-pipeline, falsification-gate, goal-versioning, concurrency]
status: accepted
created: 2026-07-18
updated: 2026-07-18
author: zircote
project: research-harness-template
technologies: [Claude Code, Workflow tool, JavaScript, Bash]
audience: [developers, architects]
related: [0001-four-layer-single-repository-architecture.md, 0003-config-declared-research-dimensions.md, 0004-single-adversarial-falsification-gate.md, 0006-content-hashed-append-only-goal-versioning.md]
---

# ADR-0020: Workflow-tool orchestration as a parallel path to the orchestrator subagent

## Status

accepted

## Context

### Background and Problem Statement

The harness has always orchestrated research through the `orchestrator` subagent:
it fans out `dimension-analyst` background subagents, poll-loops on disk because
a backgrounded subagent cannot wake its parent deterministically, reaps zombies
whose parent poll gave up too early, runs the single adversarial falsification
gate (ADR-0004), then synthesizes. That architecture works, but it carries real
scar tissue that exists *only* because an agent cannot deterministically await
its own children: shortfall reconciliation when a dimension-analyst's disk
output undercounts its own self-reported finding count, zombie resurrection
when a poll loop times out on a subagent that is still alive, and double-spawned
orchestrators when a resumed session and a fresh session both believe they own
the same topic's run-lock.

Claude Code's Workflow tool removes the reason that scar tissue exists:
deterministic JS control flow (`pipeline`/`parallel`/loops), `agent()` calls that
are *awaited*, not backgrounded, with schema-validated structured returns, plus
journaled resume and a live progress UI. Awaited children make "is it still
alive" an unaskable question — there is no ambiguous state to reconcile or reap.

### Current Limitations

Before this decision, every research session (full, augment, update) ran only
through the orchestrator subagent's poll/reap loop, and any bug in that loop
(a stall, a shortfall, a lock race) had no deterministic alternative path to
fall back to or compare against.

## Decision Drivers

### Primary Decision Drivers

1. Preserve every harness invariant unchanged: MIF finding files, the single
   adversarial falsification gate (ADR-0004), fail-closed ontology typing
   (ADR-0011), goal versioning (ADR-0006), and the knowledge-graph/index/
   concordance projections.
2. Reuse the existing hardened subagents (`dimension-analyst`,
   `falsification-analyst`, `report-synthesizer`, `source-chunker`) unmodified,
   via `agentType` overrides — their authoring rules (staged→ajv→atomic
   publish, model-layer JSON composition, citation rules, remediation logic)
   must come along for free, not be re-derived.
3. Ship as a genuinely parallel path, not a replacement: the orchestrator
   subagent stays exactly as-is as the fallback; nothing about `/start` changes.

### Secondary Decision Drivers

1. Add parallel rendering across the full genre/channel pack surface as new
   capability the orchestrator's sequential synthesis step does not offer.
2. Keep the new surface's own quality bar identical to the rest of the
   harness: structural evals wired into `evals/run-evals.sh`, no live-agent
   spawning in CI.

## Considered Options

### Option 1: Fix the orchestrator's poll/reap loop directly

**Description:** Keep the orchestrator subagent as the only coordination path
and harden its existing poll/reap/reconcile logic instead of introducing a
second engine.

- **Advantages:** One coordination path to maintain; no new tool surface to
  learn or document.
- **Disadvantages:** Does not remove the root cause — an agent still cannot
  deterministically await a backgrounded child, so every hardening is another
  layer of reconciliation logic on top of an inherently racy primitive, not a
  fix to the primitive itself.
- **Risk Assessment:** technical medium (perpetual whack-a-mole on the same
  class of bug); schedule low; ecosystem low.

### Option 2: Workflow-tool orchestration as a parallel path (chosen)

**Description:** A new `.claude/workflows/research.js` Workflow script drives
full-, augment-, and update-mode sessions with deterministic `pipeline`/
`parallel` control flow and awaited `agent()` calls (with `agentType`
overrides onto the existing hardened subagents), invoked via a new
`/research` command that sits alongside `/start` rather than replacing it.

- **Advantages:** Awaited children eliminate the entire class of poll/reap/
  zombie bugs by construction — there is no backgrounded state to reconcile.
  Reuses every existing subagent's hardened authoring logic unchanged via
  `agentType` + `schema`. Adds parallel genre/channel rendering as new
  capability. Ships as a genuinely optional second path — `/start` and the
  orchestrator subagent are untouched, so this is purely additive risk.
- **Disadvantages:** A second orchestration engine to keep behaviorally
  aligned with the first (same invariants, same gate semantics) as both
  evolve. `try`/`finally` in a Workflow script does not reliably run its
  cleanup on a host-level forced interruption (`TaskStop`) — see Consequences.
- **Risk Assessment:** technical low (proven via two full end-to-end live
  runs plus five targeted spikes, four real defects found and fixed, all
  re-verified live); schedule low (additive, no orchestrator-path deadline
  pressure); ecosystem low (no new external dependency — Workflow is a native
  Claude Code capability).

### Option 3: Replace the orchestrator subagent outright

**Description:** Migrate `/start` itself onto the Workflow engine and retire
the orchestrator subagent.

- **Advantages:** One coordination path going forward; no long-term dual
  maintenance burden.
- **Disadvantages:** Forecloses the fallback this decision explicitly wants:
  if the Workflow tool has an environment quirk this harness hasn't hit yet,
  there would be no proven alternative path left. Premature — the two full
  live runs plus five spikes that proved this design out did not include the
  side-by-side comparison against an orchestrator-run topic that would justify
  retiring the original path (see Consequences, Negative).
- **Risk Assessment:** technical medium (removes the fallback before it has
  been needed even once); schedule low; ecosystem low.

## Decision

Option 2. `.claude/workflows/research.js` (9 phases: Prepare → Research →
Gate & Remediate → Type → Check → Synthesize → Render → Project → Finalize)
drives full-, augment-, and update-mode sessions as a parallel path to the
orchestrator subagent, invoked via the new `.claude/commands/research.md`.
Every reused subagent is spawned via `agentType` + `schema` so its hardened
authoring rules apply unchanged; mechanical script-runner phases use the
default workflow agent at `effort: 'low'`. The genre/channel fan-out in the
Render phase is pre-filtered in-script against `.claude/enabled-packs.json`
before any agent spawns, so an unknown or disabled genre is logged and
dropped, never silently discovered after the fact. Two structural evals
(`evals/workflow-research-parses.sh`, `evals/workflow-research-structure.sh`,
joined later by `evals/workflow-research-update-mode.sh`,
`evals/workflow-research-mode-integrity.sh`, and
`evals/command-research-mode-flags.sh`) are wired into `evals/run-evals.sh`
and stay fast/cheap — static checks only, no live agent spawning in CI.

## Consequences

### Positive

1. The entire poll/reap/zombie/shortfall-reconciliation bug class the
   orchestrator subagent has always carried cannot occur in this path by
   construction — every `agent()` call is awaited, so there is no ambiguous
   "is it still alive" state to reconcile during ordinary execution.
2. Genre/channel rendering runs in parallel across the pack surface, new
   capability the orchestrator's sequential synthesis step never offered.
3. Reused subagents keep their full hardened contract (staged→ajv→atomic
   publish, model-layer JSON authoring, citation rules, remediation logic)
   with zero duplication — `agentType` + `schema` composition was the
   highest-risk unknown going in and is now proven to work cleanly across
   `dimension-analyst`, `falsification-analyst`, and `report-synthesizer`,
   including nested `Skill()` calls inside a workflow-spawned
   `report-synthesizer`.

### Negative

1. `try`/`finally` in a Workflow script does **not** reliably run its cleanup
   on a host-level `TaskStop` — empirically confirmed: a run interrupted
   immediately after `.gate-active` appeared on disk left the run-lock held,
   the gate window open, and the in-flight batch's findings ungated, with the
   `finally` cleanup agent never invoked. This is the same class of risk the
   orchestrator path already carries under an external kill (neither
   framework can run its own cleanup once the process is torn down from
   outside) — this decision narrows the *normal-exit* zombie/lock-leak
   surface, it does not eliminate the *external-interruption* case. Mitigated
   via documented manual recovery in `.claude/commands/research.md`'s Error
   Handling section (`scripts/run-lock.sh release`, `rm -f .gate-active`);
   the one-round rule still protects already-gated findings from re-grading
   on retry.
2. Two orchestration engines now exist and must stay behaviorally aligned —
   any future invariant change (a new gate rule, a new goal-version field)
   has to be applied to both `orchestrator.md` and `research.js` deliberately,
   not assumed to propagate.
3. `resumeFromRunId` cache-key granularity across multiple research rounds
   was designed for (the round number is folded into every Phase 1 prompt so
   a resumed run's per-round agent calls stay cache-distinct) but not yet
   stress-tested against a real multi-round resume — both full live
   validation runs used `maxRounds:1`, so no round-loop resume was exercised
   end to end.

### Neutral

1. `/research` and `/start` are both first-class entry points going forward,
   not a deprecated-vs-canonical pair — an instance owner can use either, and
   nothing routes one through the other.

## Decision Outcome

Workflow-tool orchestration removes an entire class of coordination bug by
construction, reuses every hardened subagent's authoring contract unchanged,
and adds parallel genre rendering — all while leaving the orchestrator
subagent fully intact as a fallback, so this is purely additive capability
with additive (not replacement) risk. The one open risk that is not
eliminated — cleanup on a forced external interruption — is documented with
concrete manual recovery steps rather than papered over, and is a limitation
this decision narrows but does not claim to solve, since it is inherent to
any framework whose cleanup code cannot run once the process is killed from
outside.

## Related Decisions

- ADR-0001: the four-layer architecture this new engine composes into as an
  additional entry point, not a new layer.
- ADR-0003: config-declared research dimensions — `research.js` reads
  `dimensions[]` from `harness.config.json` exactly as the orchestrator does.
- ADR-0004: the single adversarial falsification gate — `research.js`'s Gate
  & Remediate phase is one agent per batch, `agentType: 'falsification-analyst'`,
  preserving the gate's ordinal verdicts and one-round rule unchanged.
- ADR-0006: content-hashed append-only goal versioning — `research.js` reads
  and reasons about `gv-<sha>` lineage the same way `/start` and `/resume` do.

## Links

- `.claude/workflows/research.js` — the Workflow script implementing this
  decision.
- `.claude/commands/research.md` — the front door that also serves as
  goal-writer for the dynamic path, and documents the `TaskStop` mid-Gate
  manual-recovery steps referenced in Consequences.
- `evals/workflow-research-parses.sh`, `evals/workflow-research-structure.sh`,
  `evals/workflow-research-update-mode.sh`,
  `evals/workflow-research-mode-integrity.sh`,
  `evals/command-research-mode-flags.sh` — the structural evals wired into
  `evals/run-evals.sh`.

## More Information

- **Date:** 2026-07-18
- **Source:** Prototyped and live-tested in a research-harness instance
  (issues research-harness#17, #19-#23 track the mode-resolution follow-on
  work); two full end-to-end dry runs plus five targeted spikes (~2.4M
  tokens total) found and fixed four real defects before this port: an
  `engine_bin` preflight call missing its repo-root argument; schema-return
  pressure silently crowding out `falsification-analyst`'s own documented
  file-write side effect; an agent silently mutating `harness.config.json`
  to route around a downstream check failure instead of surfacing it; and
  the Project phase misreporting graph node/edge counts in its own schema
  return instead of copying the real `jq`-extracted numbers verbatim. Every
  fix was re-verified live before moving on.

## Audit

### 2026-07-18

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Schema+agentType composition against existing hardened subagents proven live, not assumed | `.claude/workflows/research.js` | compliant |
| Single adversarial falsification gate semantics (ordinal verdicts, one-round rule) unchanged | `.claude/workflows/research.js` Gate & Remediate phase | compliant |
| Structural evals exist, pass, and spawn no live agents in CI | `evals/workflow-research-parses.sh`, `evals/workflow-research-structure.sh`, `evals/workflow-research-update-mode.sh`, `evals/workflow-research-mode-integrity.sh`, `evals/command-research-mode-flags.sh` | compliant |
| `TaskStop` mid-Gate cleanup limitation documented with concrete recovery steps, not silently omitted | `.claude/commands/research.md` Error Handling section | compliant |

**Summary:** Decision settled and documented; the implementation was live-tested end to end in an instance before this upstream port, with four real defects found and fixed along the way.

**Action Required:** A side-by-side full-scale validation run comparing a `/research`-driven topic against an orchestrator-run topic (this ADR's Option 3 rationale references this as still outstanding) remains a follow-up, not a blocker for accepting this parallel path.
