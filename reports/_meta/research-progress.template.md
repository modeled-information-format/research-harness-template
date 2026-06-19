# Research progress — {topic}

Continuity file (SPEC §4 "research-progress.md continuity + resume — KEEP"). The
orchestrator rewrites this on every phase transition; `/resume` reads it to
recover a session after interruption. Append-only history below; the header is
the current state.

- **Topic:** {topic}
- **Goal:** `reports/{topic}/goal.json`
- **Phase:** initialize | fan-out | falsify | synthesize | done
- **Round:** {n} / {max_rounds}
- **Dimensions:** {dimension}: pending|in_progress|complete (one line each)
- **Findings:** {count} emitted, {survived} survived, {weakened} weakened, {quarantined} quarantined
- **Updated:** {iso-8601}

## Completion checks

One line per `completion_condition.checks[]` from the goal, with its current
verdict (hold / not-yet) and the proving fact.

## History

Append one entry per phase transition: `{iso-8601} — {phase} — {one-line note}`.
