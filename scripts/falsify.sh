#!/usr/bin/env bash
# Falsification gate (SPEC §6b) — the SINGLE adversarial verification pass the
# harness runs. The falsification-analyst agent drives this against live web
# search; this script is the deterministic substrate it writes through, and the
# offline gate the smoke test exercises.
#
# It treats a finding as a hypothesis, consults an (offline, fixture-supplied)
# body of disconfirming evidence, assigns an ordinal verdict, and writes the
# verdict back into extensions.harness.verification. It logs exactly one
# "falsification-gate: run" line to stderr per invocation so a caller can assert
# the gate ran exactly once.
#
# Verdict model (SPEC §6b / falsification-analyst Step 5):
#   falsified  >=1 credible source directly contradicts the claim
#   weakened   >=1 credible source qualifies/narrows the claim
#   survived   adversarial queries ran; no disconfirming evidence found
#   inconclusive  could not test (budget, vague claim, already falsified)
#
# Usage:
#   falsify.sh <finding.json> [<evidence-fixture.json>]
#
# Evidence fixture: a JSON object keyed by finding @id, each value
#   { "verdict": "...", "basis": "...", "disconfirming": ["url", ...] }.
# A finding with no fixture entry is recorded as a PLACEHOLDER `inconclusive` (it was not
# adversarially tested) WITHOUT `attempted_at`, so a later real gate run can still overwrite
# it. Output: the updated finding JSON on stdout.
#
# Since research-harness-template#276 (Story #287, Category B cutover), verdict
# resolution (fixture lookup, the one-round rule, the merge into
# extensions.harness.verification) delegates to the mif-rh engine (mif-rh-cli),
# hard required: install it with scripts/fetch-engine.sh, put mif-rh-cli on
# PATH, or set MIF_RH_CLI.
#
# Phase-2 gate enforcement (SPEC §6b / #384) lives HERE, not in the PreToolUse
# hook (.claude/hooks/guard-falsify-gate.sh). The hook can only regex-match raw
# Bash command TEXT, which is ambiguous (quoting, wrapping, loops, doc-text
# mentions) and was reverted twice over that ambiguity (#356, #372). This
# script's own $FINDING argument is unambiguous — no shell-quoting shape to
# guess — so grading a topic's SESSION FINDINGS (reports/<topic>/findings/*.json)
# is gated directly against that topic's .gate-active marker (opened by the
# orchestrator's Phase 2 loop / the /falsify command). A non-findings target
# (a report-finding, a test fixture) is always a legit non-gate use and is
# never gated. The hook stays as an early, defense-in-depth layer; it is no
# longer the sole enforcement point.

set -uo pipefail

FINDING="${1:?usage: falsify.sh <finding.json> [<evidence-fixture.json>]}"
FIXTURE="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve $FINDING to an absolute, dot-free path BEFORE the gate check
# below, not after. A bare relative argument invoked from inside the
# findings/ directory itself (`cd reports/t/findings && falsify.sh f.json`)
# has no "findings/" path segment in the RAW argument, so matching against
# $FINDING as typed misses this shape entirely -- review caught this live:
# it reproduces the exact "cd-into-findings" bypass guard-falsify-gate.sh's
# own LIMITATIONS block already documents as a hook-miss, except here it
# would have been a silent miss in the script that was supposed to close it.
#
# A plain $PWD-prefix-if-relative (this repo's usual portable pattern --
# see render-artifact.sh's identical comment) is not enough on its own: a
# caller passing a DOTTED relative path from inside findings/ (e.g.
# `./f.json`) would resolve to ".../findings/./f.json", and `dirname` twice
# over that yields TOPIC_DIR=".../findings" (the dirname of "findings/."
# is "findings" itself) instead of the real topic dir one level up --
# review caught this too, live: it doesn't let anything bypass the gate
# (the wrong MARKER path just never exists, so it fails CLOSED, denying a
# legitimate call), but it's still wrong. `cd` into the finding's own
# directory and read `pwd` -- the shell's own portable path-canonicalization,
# no GNU `realpath` needed -- so "." and ".." segments resolve the same way
# a real invocation's cwd would, then rejoin with the file's basename.
FINDING_DIR="$(cd "$(dirname "$FINDING")" 2>/dev/null && pwd)"
if [ -n "$FINDING_DIR" ]; then
  FINDING_ABS="$FINDING_DIR/$(basename "$FINDING")"
else
  # dirname doesn't exist -- can't canonicalize; fall back to the plain
  # prefix so the gate check below still applies its best-effort classification (a
  # nonexistent $FINDING fails for its own reason once the engine reads it).
  case "$FINDING" in
    /*) FINDING_ABS="$FINDING" ;;
    *)  FINDING_ABS="$PWD/$FINDING" ;;
  esac
fi

case "$FINDING_ABS" in
  */findings/*.json)
    # TOPIC_DIR is always absolute here -- it's derived from $FINDING_ABS,
    # which the resolution above guarantees is absolute regardless of how
    # $FINDING was originally spelled.
    TOPIC_DIR="$(dirname "$(dirname "$FINDING_ABS")")"
    MARKER="$TOPIC_DIR/.gate-active"
    if [ ! -f "$MARKER" ] || [ -z "$(find "$MARKER" -mmin -240 2>/dev/null)" ]; then
      echo "falsify.sh: refusing to grade session finding '$FINDING' -- ${TOPIC_DIR}/.gate-active is absent or stale. Only the orchestrator's Phase 2 pass / the /falsify command may open this topic's gate window (SPEC §6b)." >&2
      exit 3
    fi
    ;;
esac

# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

if [ -n "$FIXTURE" ]; then
  exec "$ENGINE" harness falsify "$FINDING" "$FIXTURE"
else
  exec "$ENGINE" harness falsify "$FINDING"
fi
