---
id: how-to-run-a-research-session
type: semantic
created: '2026-06-19T15:19:39-04:00'
modified: '2026-07-05T10:10:09-04:00'
namespace: docs/how-to
tags:
  - documentation
  - how-to
title: "How to run a research session"
diataxis_type: how-to
---

# How to run a research session

A research session is goal-driven: the orchestrator runs toward a measurable
**session goal** — a verifiable completion condition — not an open-ended prompt
(design spec §2, §6b).

> Drive this flow with `/goal-writer`, `/start`, `/status`, `/resume`, and
> `/falsify`. `scripts/verify.sh`'s Milestone 3 gate keeps these commands and
> their five backing agents present and passing a smoke test.

## 1. Author the goal

Turn your raw ask into a measurable goal with the `/goal-writer` command. The
goal declares the decision the research must enable, what is in and out of
scope, and the checks that gate "done".

## 2. Start the session

Run `/start`. It delegates to the orchestrator, which owns phase management:
it spawns parallel dimension-analysts (one per configured dimension), each
researching independently and emitting MIF-backed findings validated against
`schemas/findings.schema.json`.

## 3. Falsify

The orchestrator runs exactly one adversarial gate as its own Phase 2: the
falsification-analyst treats each finding as a hypothesis, searches for
disconfirming evidence, and assigns an ordinal verdict (`falsified` /
`weakened` / `survived` / `inconclusive`). Falsified findings are quarantined;
weakened ones have their confidence lowered. Run `/falsify` standalone to
re-test a finding set, for example after `/start --augment`.

## 4. Synthesize and publish

`report-synthesizer` consumes the surviving findings. Outputs render through the
typed findings→artifact contract — blog is first-class; book and other channels
arrive via optional channel packs.

In the same phase the orchestrator reconciles the topic's navigation
`README.md` so its counts, dimensions, key findings, and report table stay
current — see [Maintain topic READMEs](maintain-topic-readmes.md).

## Continuity

Progress is written to a progress file on every phase transition, so a session
can be resumed after interruption with `/resume`. Check progress at any time
with `/status`.
