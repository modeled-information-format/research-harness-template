---
title: "How to evolve a research goal"
diataxis_type: how-to
---

# How to evolve a research goal

Research goals drift — you add a dimension, revise the decision, narrow the scope,
or a source goes out of date. The harness treats the goal as an **append-only
versioned contract** (SPEC §11): you mint a new version, and the findings you
already gathered are **reused** across versions rather than re-collected. See
[the living-corpus model](../explanation/living-corpus.md) for the why.

## The two-step flow

```bash
/goal-writer --reshape "drop the trajectory dimension, add an economic dimension, weigh cost in the decision"
/start --update
```

1. **`/goal-writer --reshape <what changed>`** evolves the goal: it snapshots the
   prior version, applies your delta, mints a new content-hashed version
   (`gv-<hash>`, recorded with `supersedes` + a `revision` block), and classifies
   every existing finding against the new contract — **carry** (still in scope),
   **stale** (in scope but its verification has decayed), or **gap** (a dimension
   with no in-scope finding). It writes the per-version members file and then
   stops. If you omit the delta, it asks what changed.
2. **`/start --update`** researches only the **gap** dimensions and **re-verifies**
   only the **stale** findings, reusing every carried, still-fresh finding as-is.

## What "in scope" and "stale" mean

- **In scope for a version** — the finding's dimension is one of that version's
  `dimensions` and its verdict is not `falsified`, and it is not excluded by the
  version's `out_of_scope` / `non_goals`. A finding can be in scope for **many**
  versions at once (`goal_versions[]`).
- **Stale** — the finding's last verification (`verification.attempted_at`) is
  older than its **source-type decay** window. The window is the shortest among
  its citations' types (configured in `harness.config.json` `freshness`): a
  `specification` or `book` stays fresh for years; a `website` or `article` for
  months. A finding never verified yet counts as stale.

## Inspect the result

```bash
# the version id of the current goal
bash scripts/goal-version.sh reports/<topic>/goal.json

# the classification for that version
jq '{members:(.members|length), stale:(.stale|length), gap:.gap_dimensions}' \
  reports/<topic>/goals/goal-<version>.members.json
```

## Notes

- **Goal versions are immutable.** A reshape never edits a version in place; it
  appends a new one. "Did we meet goal vN" stays a provable fact.
- **Findings are never deleted on a scope change.** A finding dropped from the
  current version is kept in the corpus — it still serves the earlier versions it
  was in scope for. Archival is reserved for genuine retirement.
- **The membership set is a projection.** `goal_versions[]` and `stale_in[]` on a
  finding's index entry are rebuilt by `scripts/build-index.sh` from the
  authoritative members files; never hand-edit them.
- Reshaping is **not** a `start` flag — it authors a new goal version, which is
  `goal-writer`'s job. `start` never authors or mutates a goal.
