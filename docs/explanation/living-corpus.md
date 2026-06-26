---
title: "Explanation: the living corpus — goal evolution and finding reuse"
diataxis_type: explanation
---

# Explanation: the living corpus — goal evolution and finding reuse

> **Status: design proposal, not yet implemented.** This document records the
> intended model for how a research session's goal evolves over time and how
> existing findings are reused across goal versions. It is an input to the
> project's ADRs and to a future design-spec section (proposed **§11**); the
> harness does not yet behave this way. Where a decision is settled it is marked
> **Settled**; unresolved choices are collected under [Open questions](#open-questions).

Research is not a one-shot. Over the life of a topic the question sharpens: a
dimension is added, a hypothesis is revised, scope shifts, a completion check
changes, a source decays. The corpus is **living** — hence *corpus*. The problem
this model solves: let the goal evolve **without** discarding the findings already
gathered, and **without** breaking the harness's ability to say a session met its
goal.

## The principle: version the goal, never mutate it

The goal (`reports/<topic>/goal.json`, `schemas/goal.schema.json`) is the
harness's one verifiability contract: "did we answer the question" is a printable
fact *only because* the contract did not move underneath the run (design spec §2,
§6b). Mutating a goal in place destroys that — you could never again prove a
session met its goal.

So the living-ness does **not** live in a mutable goal. It lives in:

1. an **append-only lineage of goal versions** (each version a fixed, checkable snapshot),
2. **findings that are reused across versions** rather than re-gathered, and
3. (a future layer) **hypotheses that outlive any single goal**.

Each goal version remains immutable; the corpus evolves around it.

## Goal versions and lineage

**Settled.** A goal evolution appends a new version to a per-topic lineage; prior
versions are retained. A version is identified by a **content hash of the
normalized goal**, e.g. `gv-<sha256(goal.json)[:12]>`, because:

- it is decoupled from commit timing — the harness runs against the working tree,
  so a goal is often uncommitted mid-session;
- it is **self-verifying** — recomputing the hash proves a finding really matches
  *that* goal version.

A human alias (`v1`, `v2`) and the git SHA are recorded **as provenance metadata**
alongside the hash, never as the identity. (A short git SHA identifies a *commit*,
not the goal's content, so it is an audit anchor, not a key.)

## Findings are reused across versions (many-to-many)

**Settled.** A finding is *produced once* and then *qualifies for* many goal
versions. Membership is many-to-many, not a single binding. Two fields, two
questions:

- `provenance.gathered_under` — **single, immutable**: the version whose research
  first produced this finding. (*Where did it come from.*)
- `goal_versions[]` — **the membership set** of versions the finding currently
  serves, e.g. `["gv-ab12cd34ef56", "gv-9f0021aa…"]`. (*Who may use it.*)

Conflating the two is the trap; provenance is one, membership is many.

## Membership is a computed projection, never hand-authored

**Settled (mechanism).** `goal_versions[]` must be **re-derivable**, the same way
the research index and knowledge graph are projections of findings — otherwise it
rots the moment scope shifts. Membership for a goal version is resolved by a
two-stage **scope-resolution pass**, mirroring the existing falsification pattern:

1. **Deterministic pre-filter** (cheap, exact): the finding's
   `extensions.harness.dimension` is in the version's `dimensions`; namespace/tags
   match; verdict ≠ `falsified`; the claim is not in `out_of_scope` / `non_goals`.
2. **Judge the ambiguous remainder** (model call, only where needed): does this
   finding actually bear on *this* version's decision and checks?

**Open (authority location).** Where the materialized result lives is unsettled —
see [Open questions](#open-questions). The current lean: the **authority** is a
per-version resolved members file (`goal-<hash>.members.json`), so a goal
evolution writes **one** file rather than touching N findings; `goal_versions[]`
on each finding is a **derived mirror**, rebuilt by the same pass that builds the
index, so findings stay self-describing without being the source of truth.

## Membership is not freshness (reuse vs. trust)

**Settled.** Being *in scope* for a version does not mean a finding's *verdict* is
still trustworthy for it — a source may have decayed, or the version may have
added a check that stresses the claim differently. Freshness (`verified_at` /
`re-verify-by`) is tracked **separately** from membership:

| State | Action |
| --- | --- |
| in-scope ∧ fresh | **reuse as-is** (zero re-research — the point of the model) |
| in-scope ∧ stale | **re-falsify** only this finding |
| out-of-scope | drop from this version's working set; **keep in the corpus** for the versions it still serves |

The research a goal evolution actually has to perform is then the clean delta:

```text
gap(vN) = checks/dimensions(vN) − { findings : vN ∈ goal_versions ∧ fresh }
```

Only the true gap is gathered. That is the waste this model eliminates.

## Lifecycle: reshape authors, start runs

**Settled.** The two responsibilities stay on the seams the harness already holds
(`/goal-writer` authors contracts and stops; `/start` never authors a goal):

- **`/goal-writer --reshape`** takes the delta, mints `vN+1` (content-hashed,
  appended to lineage), runs the scope-resolution pass to classify existing
  findings (**carry / re-verify / gap**) and materialize membership, prints the
  delta + gap report, and **stops**. Authoring and any elicitation live here.
- A **membership-aware `/start --update`** then loads the now-current goal version
  and runs only `re-verify + gap`, reusing every in-scope-∧-fresh finding. No new
  behavior is required of `start`.

There is deliberately **no behavior-bearing `--reshape` flag on `start`.** If one
is ever added it is pure sugar that chains the two calls — never its own logic.
This preserves the invariant that `start` never authors a goal.

## Archive becomes rare and safe

**Settled.** With many-membership, a finding leaves the corpus only when it is out
of scope for **every live goal version** (or is explicitly retired) — a dimension
dropped in `v3` does not orphan `v2`'s findings. Retirement **archives, never
deletes** (provenance is the corpus's value). "Archive" is therefore a genuine
end-of-life event, not a side effect of ordinary goal drift.

## The deeper layer: first-class hypotheses (future)

Today a hypothesis is implicit — the falsification gate treats each *finding* as a
hypothesis under test (§6b), but nothing persists "what we currently believe"
across findings or across goals. Promoting a **hypothesis to a MIF concept** that
findings support/refute, with an aggregate verdict that strengthens, weakens, or
overturns as evidence accretes, is what turns "findings gathered for a goal" into
"an evolving belief network that outlives the goal that spawned it." This is the
true living-corpus upgrade and is sequenced **after** goal versioning and
membership prove out.

## What this reuses, and what it adds

**Reuses** (already in the harness): the ordinal verdict system and
`extensions.harness.verification`; W3C-PROV provenance; the index and graph as
projections of findings; `discover` (gaps and stale findings); `--augment` /
`--update`; the cross-topic concordance; `research-progress.md` as the continuity
log; the single falsification gate.

**Adds**: goal versioning + lineage; the scope-resolution pass and materialized
membership; finding freshness fields; (later) first-class hypotheses.

## Open questions

1. **Membership authority location.** Per-version members file as authority with a
   derived `goal_versions[]` mirror on findings (O(1) writes per evolution, no
   drift), **vs.** the set living natively on each finding (fully self-describing,
   but N writes per evolution and easier to drift). This changes the schema and
   the reshape command.
2. **Reshape delta input.** Passed as **args**
   (`/goal-writer --reshape "drop trajectory, add hypothesis X"` — scriptable,
   fits the autonomous/loop style) **vs.** **elicited** (goal-writer asks). Affects
   whether reshape carries elicitation.
3. **Freshness model.** What drives `re-verify-by` — a fixed TTL, per-dimension
   volatility, or source-type decay — and whether re-verification is scheduled
   (via the cron/`schedule` surface) or only on reshape.

## Sequencing

1. Goal versioning + `/goal-writer --reshape` with finding classification.
2. Finding ↔ membership projection + freshness fields (lights up `discover`, the
   README/synthesis, and scheduled re-verification).
3. First-class hypotheses.

This explanation, together with the design specification, is the input from which
the project's ADRs are drafted.
