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
#   - a KNOWN FALSE DENY (issue #372), on the other side of the same tradeoff: any Bash
#     command that merely quotes "falsify.sh" as documentation text (e.g. a
#     `gh issue create --body "..."` heredoc reproducing a bug that mentions the script
#     name and an example findings/ path) is denied even though it never invokes the
#     script. Workaround: avoid quoting the script name directly in such text (a
#     paraphrase, or breaking up the string, avoids the substring match), or file/comment
#     from outside a gated topic's window if a literal repro string is unavoidable. Not
#     fixed by narrowing the substring check further -- see #384, which found that every
#     attempt to do so (this hook's second attempt, reverted) let a REAL invocation
#     silently bypass the gate instead, which is unbounded worse than this false deny.
set -uo pipefail
# Repo root: CLAUDE_PROJECT_DIR in the hook, else two levels up from .claude/hooks/<this>.
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

INPUT=$(cat /dev/stdin 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on a command that MENTIONS the gate script -- a broad, unanchored
# substring match, deliberately never narrowed to "invocation position" (issue
# #372 tried exactly that: anchoring to command-start / after a shell operator,
# optionally through a bash/sh prefix, to stop this check tripping on a
# `gh issue create --body "... scripts/falsify.sh \"reports/.../findings/
# foo.json\" ..."` heredoc that only quotes the script name as documentation
# text, never invoking it). That anchor was reverted: review found it let a
# REAL invocation through ungated whenever it didn't match one of the
# enumerated shapes -- env-var-prefixed (`FOO=bar scripts/falsify.sh ...`),
# `command`/`env`/`time`/`sudo`-wrapped, a `for`/`while` loop or `xargs -I{}`
# fan-out, `sh -c "..."`, a quoted command name, or (confirmed live, and this
# repo's OWN established convention in .claude/skills/publish-report/evals/
# evals.json) a `$CLAUDE_PROJECT_DIR/scripts/falsify.sh ...` path -- silently
# bypassing the one-round-rule gate this hook exists to enforce. A false ALLOW
# here is unbounded worse than a false DENY (the gh-issue-create case above):
# an annoying deny has a known workaround (quote the path unquoted, or avoid
# quoting the script name in doc text -- see LIMITATIONS at the top of this
# file); a false allow permanently corrupts the corpus. Distinguishing "quoted
# doc text passed to an unrelated command" from "a real invocation, however
# shaped" is a shell-parsing problem no regex anchor here can solve safely --
# see #384 for the actual fix (falsify.sh checks a gate token/env var instead
# of this hook inferring invocation shape from command text).
printf '%s' "$CMD" | grep -qF 'falsify.sh' || exit 0

# Only guard grading of a topic's SESSION FINDINGS (reports/<topic>/findings/*.json).
# Anything else (report-finding, fixtures) is a legit non-gate use -> allow.
# The prefix is a POSITIVE path-character class (alnum, /, ., _, -), not a
# negative "not whitespace" one (issue #356): "F=reports/t/findings/f.json" used
# to have the greedy [^[:space:]]* prefix swallow "F=" itself, corrupting the
# extracted path and the TOPIC_DIR computed from it. An earlier fix attempt
# just excluded '=' from the negative class, but that still let a QUOTED
# assignment's leading quote character through ('F="reports/..."' -- the
# stray '"' corrupts TOPIC_DIR the same way "F=" did). A positive class only
# matching real path characters closes both the unquoted- and quoted-
# assignment shapes, while still matching an absolute path's leading
# directories, preserving the case statement below's absolute-path branch.
FINDINGS=$(printf '%s' "$CMD" | grep -oE '[[:alnum:]/._-]*reports/[^[:space:]]+/findings/[^[:space:]]+\.json')
[ -n "$FINDINGS" ] || exit 0

# EVERY targeted topic must have an open + fresh gate window — a command grading findings in
# more than one topic is denied unless EACH topic's window is open (one topic's window cannot
# authorize grading another's). A marker left by a crashed gate ages out of the freshness
# window, so a stale window cannot silently re-open the gate for a later analyst.
while IFS= read -r FINDING; do
  [ -n "$FINDING" ] || continue
  TOPIC_DIR=$(dirname "$(dirname "$FINDING")")
  case "$TOPIC_DIR" in
    /*) MARKER="$TOPIC_DIR/.gate-active" ;;
    *)  MARKER="$ROOT/$TOPIC_DIR/.gate-active" ;;
  esac
  if [ -f "$MARKER" ] && [ -n "$(find "$MARKER" -mmin -240 2>/dev/null)" ]; then continue; fi
  DENIED=1; break
done <<EOF
$FINDINGS
EOF
[ "${DENIED:-}" = 1 ] || exit 0

# Outside the window: DENY (JSON contract, same shape md_guard uses).
REASON="Blocked: scripts/falsify.sh is the orchestrator's SINGLE Phase-2 falsification gate, and this topic's gate window is not open (${TOPIC_DIR}/.gate-active is absent). A dimension-analyst must NEVER grade the session findings — a premature, fixture-less stamp is permanent under the one-round rule and corrupts siblings. The orchestrator (Phase 2) and the /falsify command open the per-topic window and own the single pass; let them run it."
jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
