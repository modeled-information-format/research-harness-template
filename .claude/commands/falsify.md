---
name: falsify
description: Run the single adversarial falsification gate over a session's findings. Delegates to the falsification-analyst agent, which assigns ordinal verdicts and applies remediation.
argument-hint: "[--topic <id>] [--scope all|dimension:<dim>|finding:<@id>] [--query-budget <n>] [--claim-budget <n>]"
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Glob
  - Read
---

# Falsify

Runs the harness's **single** adversarial verification gate (SPEC §6b — the four
codex review gates are explicitly cut). It is a thin delegator: it spawns the
`falsification-analyst` agent, which treats each finding as a hypothesis, runs
web-only disconfirming search, assigns an ordinal verdict (falsified | weakened |
survived | inconclusive), writes it through `scripts/falsify.sh` into
`extensions.harness.verification`, and applies remediation itself (falsified →
quarantine, weakened → downgrade one level, survived/inconclusive → annotate).
This command does NOT perform remediation — the agent owns it.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — which session to falsify. Required when more than one exists.
- `--scope` — default `all`. One of:
  - `all` — every active finding under `reports/<topic>/`.
  - `dimension:<dim>` — findings whose `extensions.harness.dimension == <dim>`;
    `<dim>` must be a dimension declared in `harness.config.json` `dimensions[]`.
  - `finding:<@id>` — a single finding by its MIF `@id`. Invalid scope → error
    and stop.
- `--query-budget <n>` — disconfirming queries per claim. Default 6, clamp to
  1–10.
- `--claim-budget <n>` — max claims this run. Default 50, clamp to 1–500.

## Phase 0: Resolve the session

```bash
ls reports/*/research-progress.md 2>/dev/null
```

- None → "No research session found. Run `/start <topic>` first." Stop.
- One, no `--topic` → use it.
- Multiple, no `--topic` → list topic ids and ask which to falsify.

Set `REPORTS_DIR="reports/<topic>"`. If `--scope dimension:<dim>` was given,
confirm `<dim>` is in the config:

```bash
jq -e --arg d "<dim>" '.dimensions | any(.id == $d)' harness.config.json >/dev/null \
  || { echo "Unknown dimension '<dim>' — not in harness.config.json dimensions[]." >&2; }
```

## Phase 1: Validate the working-set size

The agent fails loudly (not silently truncates) when the working set exceeds the
claim budget, so check first:

```bash
case "$SCOPE" in
  all) COUNT=$(ls "$REPORTS_DIR"/findings/*.json 2>/dev/null | wc -l | tr -d ' ') ;;
  dimension:*) DIM="${SCOPE#dimension:}"; COUNT=0
    for f in "$REPORTS_DIR"/findings/*.json; do
      [ -e "$f" ] || continue
      [ "$(jq -r '.extensions.harness.dimension // empty' "$f")" = "$DIM" ] && COUNT=$((COUNT+1))
    done ;;
  finding:*) COUNT=1 ;;
esac
```

If `COUNT > CLAIM_BUDGET`, ask the user (increase budget to `COUNT*3`, narrow
scope, or cancel) before spawning. Do NOT silently truncate.

## Phase 2: Gate in resumable bounded slices (reaps a stalled sub-agent)

A deep finding set takes a long time to gate. A **single** long-running gate sub-agent that
is interrupted — the session closes, the background task is killed, a web call stalls —
leaves most findings ungated with no signal: a **dangling session the parent cannot reap**.
So drive the gate off **disk state**, not the sub-agent's return. Gate the ungated remainder
in **bounded slices**, re-reading disk each round, until every in-scope finding is gated or
progress stops. The one-round rule (`attempted_at`) makes a re-spawn idempotent — an
already-gated finding is skipped — so re-gating the remainder never re-grades and always
resumes cleanly (this is also what makes re-running `/falsify` safe).

**Open the gate window once** (`scripts/falsify.sh` is blocked outside it by the
`guard-falsify-gate.sh` PreToolUse hook), then loop:

```bash
touch "$REPORTS_DIR/.gate-active"          # opens THIS topic's gate window
BATCH=12; NOPROG=0                          # slice size; consecutive no-progress rounds
# @ids of UNGATED findings (missing verification.attempted_at). For SCOPE narrow the set:
#   dimension:<d> -> add `select(.extensions.harness.dimension=="<d>")`; finding:<id> -> just that file.
ungated(){ for f in "$REPORTS_DIR"/findings/*.json; do
  jq -e '.extensions.harness.verification.attempted_at? // empty | length>0' "$f" >/dev/null 2>&1 \
    || jq -r '.["@id"]' "$f"; done; }
```

Each round:

1. `ungated | head -n "$BATCH" > "$REPORTS_DIR/.gate-batch"`; `REM=$(ungated | wc -l)`.
2. **If `REM` is 0 the gate is COMPLETE** — break the loop.
3. Spawn ONE analyst over the slice (`SCOPE: batch:$REPORTS_DIR/.gate-batch`), Phase 2b below.
   Then **do NOT block on its return — poll disk**: in a bounded `Bash` loop, `sleep` a short
   interval (~20s) and re-count how many of the batch's `@id`s now carry `attempted_at`. Stop
   polling when the batch is fully gated OR no new finding gates across ~3 consecutive polls
   (the slice hung or was interrupted), then go to step 4. Disk state — not the sub-agent's
   return — is the only signal this command (`Bash`/`Read` only) can act on, which is what lets
   it move past a non-returning slice instead of hanging.
4. Re-read disk. If this round gated **zero** new findings (the sub-agent stalled before writing
   any verdict), `NOPROG=$((NOPROG+1))`; else `NOPROG=0`.
5. **Give up safely after two dead rounds:** when `NOPROG` reaches 2, STOP — do NOT hang and do
   NOT stamp a fake verdict. Report the PARTIAL result (Phase 3) with the ungated count and tell
   the user to **re-run `/falsify`** to finish (it resumes via the one-round rule).

**Close the window** when the loop exits (complete or given up):

```bash
rm -f "$REPORTS_DIR/.gate-active" "$REPORTS_DIR/.gate-batch"
```

### Phase 2b: the per-slice analyst spawn (nameless background subagent)

```text
Agent(
  subagent_type: "falsification-analyst",
  run_in_background: true,
  prompt: """
    Adversarially falsify EXACTLY the findings in this batch for this topic.
    REPORTS_DIR: {REPORTS_DIR}
    SCOPE: batch:{REPORTS_DIR}/.gate-batch
    QUERY_BUDGET: {query_budget}
    CLAIM_BUDGET: {claim_budget}

    Follow your agent definition (Steps 1–8). Web-only evidence (WebSearch/WebFetch). Write
    each verdict through scripts/falsify.sh into extensions.harness.verification, apply the
    one-round rule, apply remediation (falsified -> quarantine, weakened -> downgrade one
    level, survived/inconclusive -> annotate), append to the {date}-falsification-report.md.
    Your FINAL MESSAGE is your return value: the verdict roll-up for this batch.
  """
)
```

## Phase 3: Aggregate verdicts from disk and report

**The finding files on disk are the source of truth, not the sub-agent return** — the loop
may have spanned several slices and a stalled slice may have returned nothing. Tally the
verdicts by reading `extensions.harness.verification.verdict` across the in-scope finding
files (plus the `quarantine/` siblings for `falsified`); also count any still-ungated
findings (no `attempted_at`):

```bash
for f in "$REPORTS_DIR"/findings/*.json "$REPORTS_DIR"/quarantine/*.json; do
  jq -r '.extensions.harness.verification.verdict // "ungated"' "$f" 2>/dev/null
done | sort | uniq -c
```

Append a gate entry to `reports/<topic>/research-progress.md` (mark it **PARTIAL** if any
finding remains ungated):

```markdown
## {ISO_DATE} — Falsification Gate {(PARTIAL — re-run /falsify to finish) if ungated>0}
- Scope: {scope}
- Verdicts: falsified={N}, weakened={N}, survived={N}, inconclusive={N}; ungated={N}
- Remediation: {N} quarantined, {N} downgraded, {N} annotated
- Epistemic caveat: survived = no disconfirmation within the query budget; not proof.
```

Present the verdict counts (state plainly if the gate is **partial** and how many findings
remain ungated — never imply a partial gate is complete), the report path
(`reports/<topic>/{date}-falsification-report.md`), the quarantined finding ids, and next
steps:

- If findings remain **ungated** (the gate was interrupted), tell the user to **re-run
  `/falsify`** — it resumes from disk and skips what is already gated.

- If any finding was **falsified**, recommend `/start --augment <affected-dimension>`
  to re-research with the disconfirming evidence in mind before synthesizing.
- Otherwise the active set is the surviving + downgraded findings; suggest
  `/status` or `/resume`.

## Phase 4: Done

There is no team to tear down — each slice's verdicts and remediation are persisted in the
finding files on disk (the gate window is closed in Phase 2). Confirm the window marker is
gone (`ls "$REPORTS_DIR"/.gate-active` returns nothing) so a future gate is not left runnable,
then report and stop.

## Integration note

The orchestrator runs this same gate as its Phase 2 inside every session. Use
`/falsify` standalone to re-test a finding set (e.g. after `/start --augment`), or to
falsify a single finding by `@id`. The one-round rule means a finding already
carrying a verdict this session is passed through unchanged.
