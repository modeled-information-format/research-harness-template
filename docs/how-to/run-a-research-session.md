---
title: "How to run a research session"
diataxis_type: how-to
---

# How to run a research session

A research session is goal-driven: the orchestrator runs toward a measurable
**session goal** — a verifiable completion condition — not an open-ended prompt
(design spec §2, §6b).

> The engine agents and commands referenced here are delivered in Milestone 3
> (Engine). This guide describes the intended flow and is the contract those
> commands implement.

## 1. Author the goal

Turn your raw ask into a measurable goal with the `goal-writer` command. The goal
declares the decision the research must enable, what is in and out of scope, and
the checks that gate "done".

## 2. Start the session

The orchestrator owns phase management. It spawns parallel dimension-analysts
(one per configured dimension), each researching independently and emitting
MIF-backed findings validated against `schemas/findings.schema.json`.

## 3. Falsify

Exactly one adversarial gate runs: the falsification-analyst treats each finding
as a hypothesis, searches for disconfirming evidence, and assigns an ordinal
verdict (`falsified` / `weakened` / `survived` / `inconclusive`). Falsified
findings are quarantined; weakened ones have their confidence lowered.

## 4. Synthesize and publish

`report-synthesizer` consumes the surviving findings. Outputs render through the
typed findings→artifact contract — blog is first-class; book and other channels
arrive via optional channel packs.

In the same phase the orchestrator reconciles the topic's navigation
`README.md` so its counts, dimensions, key findings, and report table stay
current — see [Maintain topic READMEs](maintain-topic-readmes.md).

## Continuity

Progress is written to a progress file on every phase transition, so a session
can be resumed after interruption.
