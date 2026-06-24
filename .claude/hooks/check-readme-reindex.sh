#!/usr/bin/env bash
# check-readme-reindex.sh — PostToolUse hook (the README "channel").
#
# Fires when a report topic is created or mutated — a finding or a rendered report
# is written/edited — and DETERMINISTICALLY rebuilds that topic's navigation README
# by invoking scripts/build-topic-readme.sh directly, so the README's metadata
# (counts, verdict rollup, dimensions, reports/findings tables, tags) never drifts
# stale on agent non-compliance. The rebuild runs in `build` mode, which preserves
# any authored Purpose / Key Findings prose, so the emitted reminder then prompts
# only the *prose* refinement via the `readme` skill. This is the safety net for
# edits made through the Write|Edit|MultiEdit tools; the same deterministic build
# also runs in the orchestrator's Phase 4 and in the shell-write mutation paths
# (falsify, publish-report) that this PostToolUse hook never observes.
#
# FAIL-SAFE & NON-BLOCKING: the rebuild can never block or fail the user's write —
# its exit status is consumed in an `if`, the hook always exits 0, and a FAILED
# rebuild (e.g. an unregistered topic) is reported truthfully in the reminder
# rather than announced as success. The manifest branch stays a reminder only
# (rebuilding every topic could exceed the hook timeout). Excludes README.md
# itself so the rebuild's own write never re-triggers this hook (a shell write,
# not a tool call, so no PostToolUse fires).

INPUT=$(cat /dev/stdin 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0

# Normalize to a path relative to the project root.
REL_PATH="${FILE_PATH#"${CLAUDE_PROJECT_DIR:-}"/}"

emit() {
  jq -n --arg ctx "$1" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
}

# Deterministically rebuild one topic's README metadata. Build mode preserves
# authored prose. Returns the build's exit status so the caller can report the
# truth (a failed rebuild — e.g. an unregistered topic — must not be announced as
# success); the caller consumes the status in an `if`, so the hook still never
# blocks the user's write and always exits 0.
rebuild_topic_readme() { # rebuild_topic_readme <topic> -> build exit status
  bash "${CLAUDE_PROJECT_DIR:-.}/scripts/build-topic-readme.sh" "$1" >/dev/null 2>&1
}

case "$REL_PATH" in
  # Never self-trigger on the README the skill writes; research-progress.md is
  # continuity (rewritten every phase), not a report — stay silent on both.
  reports/*/README.md|reports/*/research-progress.md)
    exit 0
    ;;
  reports/*/findings/*.json|reports/*/findings_*.json)
    TOPIC=$(printf '%s' "$REL_PATH" | sed -E 's#reports/([^/]+)/.*#\1#')
    # _meta is scaffolding (sample sessions, templates), not a registered topic.
    [ "$TOPIC" = "_meta" ] && exit 0
    if rebuild_topic_readme "$TOPIC"; then
      emit "Findings changed for topic '$TOPIC'; its navigation README was auto-rebuilt (deterministic counts/verdicts/tables). Refine its Purpose and Key Findings prose via the readme skill ('readme --topic $TOPIC') before reporting the topic complete, then '--check'. New/changed findings must be falsified first (see the research-lifecycle reminder)."
    else
      emit "Findings changed for topic '$TOPIC', but the README auto-rebuild did NOT run (is '$TOPIC' registered in harness.config.json?). Reconcile before reporting the topic complete: register the topic if needed, then run the readme skill ('readme --topic $TOPIC') or 'bash scripts/build-topic-readme.sh $TOPIC' then '--check'. New/changed findings must be falsified first (see the research-lifecycle reminder)."
    fi
    ;;
  reports/*/*.md)
    TOPIC=$(printf '%s' "$REL_PATH" | sed -E 's#reports/([^/]+)/.*#\1#')
    [ "$TOPIC" = "_meta" ] && exit 0
    if rebuild_topic_readme "$TOPIC"; then
      emit "Report '$REL_PATH' changed; the navigation README for topic '$TOPIC' was auto-rebuilt (Reports table + counts). Refine its Purpose and Key Findings prose via the readme skill if needed ('readme --topic $TOPIC'), then '--check'."
    else
      emit "Report '$REL_PATH' changed, but the README auto-rebuild for topic '$TOPIC' did NOT run (is '$TOPIC' registered in harness.config.json?). Reconcile it: 'bash scripts/build-topic-readme.sh $TOPIC' (or the readme skill), then '--check'."
    fi
    ;;
  harness.config.json)
    emit "harness.config.json changed (the topic registry). Reconcile every topic README so the indices match the manifest: run the readme skill with '--all', or 'bash scripts/build-topic-readme.sh <topic>' for each affected topic, then '--check'."
    ;;
  *)
    exit 0
    ;;
esac
exit 0
