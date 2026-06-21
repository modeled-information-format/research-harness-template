#!/usr/bin/env bash
# guard-falsify-gate.sh — PreToolUse(Bash) deterministic guard for the SINGLE
# falsification gate (SPEC §6b). scripts/falsify.sh is the orchestrator's one
# Phase-2 pass over a topic's findings; it must NOT run ad-hoc — e.g. a dimension-
# analyst looping it over reports/<topic>/findings/ self-grades its siblings, and
# the one-round rule (attempted_at) then makes that premature, evidence-less stamp
# PERMANENT (the real gate skips it).
#
# This is a PHASE gate, not an identity gate, and it is SCOPED to the contamination
# vector — grading a topic's SESSION FINDINGS (reports/<topic>/findings/*.json):
#   - the orchestrator / `/falsify` open a per-topic window by creating
#     reports/<topic>/.gate-active for the duration of the pass;
#   - a falsify.sh tool-call over that topic's findings/ OUTSIDE the window is DENIED.
# falsify.sh over a NON-findings target (a report-finding, a test fixture) is a legit
# non-gate use (report-synthesizer, publish-report, the smoke/eval harnesses) and is
# always allowed. The test harnesses also call falsify.sh as a subprocess of
# `bash scripts/<x>.sh`, which is not a falsify.sh tool-command, so they are unaffected.
#
# LIMITATIONS (by design — this is a phase gate, not a sandbox). It stops the EMERGENT
# failure (an analyst looping/globbing falsify.sh over reports/<topic>/findings/, which it
# catches), not a DETERMINED evasion by an actor with Bash:
#   - cd-into-findings then a relative arg (`cd reports/t/findings && falsify.sh f.json`)
#     has no findings path in the command, so it is not matched;
#   - the marker is a file the guarded agent could itself `touch` to forge a window;
#   - the verdict could be written without falsify.sh at all (jq/Edit on the finding).
# Those are covered by the layers around this hook: the dimension-analyst is explicitly
# prohibited from writing verification / running the gate, and code review catches the rest.
# If jq is missing the hook fails OPEN (allow) — jq is a hard harness dependency, so its
# absence means the harness is already non-functional, not a bypass an analyst can induce
# (the analyst does not author this hook's stdin).
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

INPUT=$(cat /dev/stdin 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on a command that invokes the gate script.
printf '%s' "$CMD" | grep -qF 'falsify.sh' || exit 0

# Only guard grading of a topic's SESSION FINDINGS (reports/<topic>/findings/*.json).
# Anything else (report-finding, fixtures) is a legit non-gate use -> allow.
FINDING=$(printf '%s' "$CMD" | grep -oE '[^[:space:]]*reports/[^[:space:]]+/findings/[^[:space:]]+\.json' | head -1)
[ -n "$FINDING" ] || exit 0

# Derive the per-topic gate marker: reports/<topic>/findings/<f>.json -> reports/<topic>/.gate-active
TOPIC_DIR=$(dirname "$(dirname "$FINDING")")
case "$TOPIC_DIR" in
  /*) MARKER="$TOPIC_DIR/.gate-active" ;;
  *)  MARKER="$ROOT/$TOPIC_DIR/.gate-active" ;;
esac
# Allow while THIS topic's gate window is open AND fresh. A marker left behind by a crashed
# gate (a `touch` with no matching `rm`) stops authorizing once it ages past the window, so a
# stale window cannot silently re-open the gate for a later analyst (bounds the crash-leak).
if [ -f "$MARKER" ] && [ -n "$(find "$MARKER" -mmin -240 2>/dev/null)" ]; then exit 0; fi

# Outside the window: DENY (JSON contract, same shape md_guard uses).
REASON="Blocked: scripts/falsify.sh is the orchestrator's SINGLE Phase-2 falsification gate, and this topic's gate window is not open (${TOPIC_DIR}/.gate-active is absent). A dimension-analyst must NEVER grade the session findings — a premature, fixture-less stamp is permanent under the one-round rule and corrupts siblings. The orchestrator (Phase 2) and the /falsify command open the per-topic window and own the single pass; let them run it."
jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
