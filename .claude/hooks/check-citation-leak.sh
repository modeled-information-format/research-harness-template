#!/usr/bin/env bash
# Citation-leak hook (bundled enforcement, SPEC §7a / §6d). Published outputs must
# read as if written from public primary sources alone: no internal-research
# references (finding ids, reports/<slug> paths, corpus methodology tokens) may
# leak into a blog post or a book chapter.
#
# Self-contained: it greps the published-output surfaces directly, so it works as
# soon as it is bundled (the blog/book output skills land in Milestone 6).
#
# Two non-blocking tiers, mirroring md_guard:
#   post : PostToolUse on Write|Edit — if the edited file is a published-output
#          surface and it leaks, emit additionalContext quoting the lines.
#   stop : Stop — scan git-dirty published-output files; on any leak emit a
#          top-level systemMessage. Warn-only, never blocks the stop.
#
# Published-output surface = blog/**/*.md and book/*/{chapters,appendices,front-matter}/*.md.
# Build-time scaffolding (OUTLINE.md, *.json, provenance/, artifacts/) is excluded.

MODE="${1:-post}"
LEAK_RE='f_[a-z]+_[0-9]+|reports/[a-z0-9][a-z0-9-]+/|findings_[a-z]+\.json|extensions\.harness'

is_published_surface () { # echo "yes" or ""
  case "$1" in
    blog/*.md|blog/*/*.md) echo yes ;;
    book/*/chapters/*.md|book/*/appendices/*.md|book/*/front-matter/*.md) echo yes ;;
    *) echo "" ;;
  esac
}

emit_context () { # additionalContext (PostToolUse, non-blocking)
  jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
}

case "$MODE" in
  post)
    INPUT=$(cat /dev/stdin)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    REL="${FILE_PATH#"${CLAUDE_PROJECT_DIR:-}"/}"
    case "$REL" in blog/*|book/*) : ;; *) exit 0 ;; esac
    [ "$(is_published_surface "$REL")" = yes ] || exit 0
    [ -f "${CLAUDE_PROJECT_DIR:-.}/$REL" ] || exit 0
    HITS=$(grep -nE "$LEAK_RE" "${CLAUDE_PROJECT_DIR:-.}/$REL" 2>/dev/null | head -12)
    if [ -n "$HITS" ]; then
      emit_context "Citation-leak gate: published file ${REL} references internal research. The output must read as if written from public primary sources alone. Re-author each flagged passage FROM THE PRIMARY SOURCE — do not just delete the reference token. Leaked lines:
${HITS}"
    fi
    exit 0
    ;;

  stop)
    cat /dev/stdin >/dev/null 2>&1
    cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
    command -v git >/dev/null 2>&1 || exit 0
    CHANGED=$(git status --porcelain --untracked-files=all -- \
                'blog/*.md' 'blog/*/*.md' \
                'book/*/chapters/*.md' 'book/*/appendices/*.md' 'book/*/front-matter/*.md' 2>/dev/null | sed 's/^...//')
    [ -z "$CHANGED" ] && exit 0
    LEAKY=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      if grep -qE "$LEAK_RE" "$f" 2>/dev/null; then
        LEAKY="${LEAKY}${f} "
      fi
    done <<< "$CHANGED"
    [ -z "$LEAKY" ] && exit 0
    jq -n --arg files "$LEAKY" '{systemMessage: ("Citation-leak gate: published file(s) still reference internal research and must be fixed before this output is reported complete: " + $files + "— re-author each flagged passage from the PRIMARY SOURCE. Published outputs may not reference finding ids, reports/<slug>/ paths, or corpus methodology in any form.")}'
    exit 0
    ;;

  *) exit 0 ;;
esac
