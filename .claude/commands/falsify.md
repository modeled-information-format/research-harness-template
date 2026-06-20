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
  all) COUNT=$(ls "$REPORTS_DIR"/*.json 2>/dev/null | grep -v goal.json | wc -l | tr -d ' ') ;;
  dimension:*) DIM="${SCOPE#dimension:}"; COUNT=0
    for f in "$REPORTS_DIR"/*.json; do
      [ "$(basename "$f")" = goal.json ] && continue
      [ "$(jq -r '.extensions.harness.dimension // empty' "$f")" = "$DIM" ] && COUNT=$((COUNT+1))
    done ;;
  finding:*) COUNT=1 ;;
esac
```

If `COUNT > CLAIM_BUDGET`, ask the user (increase budget to `COUNT*3`, narrow
scope, or cancel) before spawning. Do NOT silently truncate.

## Phase 2: Spawn the falsification-analyst (nameless subagent)

Spawn the analyst as a **nameless background subagent** and read its return — no
team, no `SendMessage`. (The platform roster is flat; coordination is via the
finding files the analyst writes and its return value.)

```text
Agent(
  subagent_type: "falsification-analyst",
  run_in_background: true,
  prompt: """
    Adversarially falsify the active findings for this topic.
    REPORTS_DIR: {REPORTS_DIR}
    SCOPE: {scope}              — all | dimension:<config-dim> | finding:<MIF @id>
    QUERY_BUDGET: {query_budget}
    CLAIM_BUDGET: {claim_budget}

    Follow your agent definition (Steps 1–8). Web-only evidence
    (WebSearch/WebFetch). Write each verdict through scripts/falsify.sh into
    extensions.harness.verification, apply the one-round rule, apply remediation
    (falsified -> quarantine, weakened -> downgrade one level, survived/
    inconclusive -> annotate), write the {date}-falsification-report.md. Your
    FINAL MESSAGE is your return value: the verdict roll-up.
  """
)
```

## Phase 3: Receive verdicts and report

Read the subagent's returned roll-up:
`{report, verdicts: {falsified, weakened, survived, inconclusive}, quarantined,
downgraded}`. Web search is slow — allow generous time; if the return is empty,
check for the report file before aborting.

Append a gate entry to `reports/<topic>/research-progress.md`:

```markdown
## {ISO_DATE} — Falsification Gate
- Scope: {scope}
- Verdicts: falsified={N}, weakened={N}, survived={N}, inconclusive={N}
- Remediation: {N} quarantined, {N} downgraded, {N} annotated
- Epistemic caveat: survived = no disconfirmation within the query budget; not proof.
```

Present the verdict counts, the report path
(`reports/<topic>/{date}-falsification-report.md`), the quarantined finding ids,
and next steps:

- If any finding was **falsified**, recommend `/augment <affected-dimension>` to
  re-research with the disconfirming evidence in mind before synthesizing.
- Otherwise the active set is the surviving + downgraded findings; suggest
  `/status` or `/resume`.

## Phase 4: Done

There is no team to tear down — the subagent has already returned and its verdicts
and remediation are persisted in the finding files. Report and stop.

## Integration note

The orchestrator runs this same gate as its Phase 2 inside every session. Use
`/falsify` standalone to re-test a finding set (e.g. after `/augment`), or to
falsify a single finding by `@id`. The one-round rule means a finding already
carrying a verdict this session is passed through unchanged.
