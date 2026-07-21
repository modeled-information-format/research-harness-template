#!/usr/bin/env bash
# Voice-enforcement hook (generic, configurable). Authored prose in this harness
# should read in the project's chosen voice. This hook is the deterministic
# backstop that memory and instructions cannot provide: it mechanically rejects
# the unambiguous mechanical rules the project enables, and reminds the author to
# apply the full profile via /human-voice:human-voice.
#
# CONFIGURABLE — consumers select the profile and the rule set in
# harness.config.json `voice` (all optional; generic defaults shown):
#   "voice": {
#     "profile": "default",          # the human-voice profile id authors apply
#     "rules": {
#       "noAiPunctuation": true,     # em/en dash, ellipsis, bullet, smart quotes, emoji
#       "noContractions": false,     # off by default; a profile-specific style
#       "warnBuzzwords": true        # non-blocking AI buzzword / filler warnings
#     }
#   }
# Absent block => the generic baseline (noAiPunctuation + warnBuzzwords on,
# noContractions off). Adding/authoring the actual prose profiles is the
# human-voice plugin's job (multiple profiles supported); this block only selects
# the active one and the deterministic rules this gate enforces. Env vars
# (VOICE_PROFILE, VOICE_NO_AI_PUNCTUATION, VOICE_NO_CONTRACTIONS,
# VOICE_WARN_BUZZWORDS) override config when set.
#
# Two tiers, mirroring check-citation-leak.sh:
#   post : PostToolUse on Write|Edit — if the file is an authored prose surface,
#          emit additionalContext listing violations and the profile mandate.
#          Non-blocking, so the author sees it immediately.
#   stop : Stop — scan git-dirty authored surfaces; if any still carry a
#          MECHANICAL violation, BLOCK (decision:block) so the turn cannot end
#          with un-voiced prose. Buzzwords alone never block.
#
# Authored prose surface = the harness publication channels, ALL nested under
# reports/<slug>/ — never a top-level blog/ or book/ directory (research-
# harness-instance decision: nothing this harness produces lives outside
# reports/<topic>/):
#   reports/<slug>/<slug>.md                       (canonical report)
#   reports/<slug>/<slug>.blog.md                  (blog channel, general)
#   reports/<slug>/<slug>.<genre>.blog.md          (blog channel, a genre)
#   reports/<slug>/book/{chapters,appendices,front-matter}/*.md   (book channel)
# Continuity logs (research-progress.md), findings JSON, sources, and quarantine
# are NOT authored prose and are excluded.

MODE="${1:-post}"

# Resolve config (generic defaults when harness.config.json or the voice block is
# absent). Env vars override config, so a hook env can pin behavior too.
CFG="${CLAUDE_PROJECT_DIR:-.}/harness.config.json"
cfg () { jq -r "$1" "$CFG" 2>/dev/null; }
VOICE_PROFILE="${VOICE_PROFILE:-$(cfg '.voice.profile // "default"')}"
{ [ -z "$VOICE_PROFILE" ] || [ "$VOICE_PROFILE" = "null" ]; } && VOICE_PROFILE="default"
RULE_PUNCT="${VOICE_NO_AI_PUNCTUATION:-$(cfg '.voice.rules.noAiPunctuation // true')}"
RULE_CONTRACTIONS="${VOICE_NO_CONTRACTIONS:-$(cfg '.voice.rules.noContractions // false')}"
RULE_BUZZ="${VOICE_WARN_BUZZWORDS:-$(cfg '.voice.rules.warnBuzzwords // true')}"
# Empty covers a missing harness.config.json entirely (jq emits nothing), which
# must fall back to the same generic baseline as an absent voice block (#688).
{ [ -z "$RULE_PUNCT" ] || [ "$RULE_PUNCT" = "null" ]; } && RULE_PUNCT=true
{ [ -z "$RULE_CONTRACTIONS" ] || [ "$RULE_CONTRACTIONS" = "null" ]; } && RULE_CONTRACTIONS=false
{ [ -z "$RULE_BUZZ" ] || [ "$RULE_BUZZ" = "null" ]; } && RULE_BUZZ=true

# Mechanical violation patterns. Lines that are markdown link references (verbatim
# citation titles) are stripped before scanning, so a source's own punctuation
# never trips the gate.
EMDASH=$'—'      # — em dash
ENDASH=$'–'      # – en dash
HELLIP=$'…'      # … horizontal ellipsis
LSQUO=$'‘'; RSQUO=$'’'; LDQUO=$'“'; RDQUO=$'”'  # smart quotes
CONTRACTIONS="(it's|don't|can't|won't|isn't|aren't|wasn't|weren't|doesn't|didn't|hasn't|haven't|hadn't|you're|we're|they're|that's|there's|here's|what's|let's|I'm|I've|we've|you've|they've|we'll|you'll|they'll|I'll|shouldn't|wouldn't|couldn't)"
BUZZWORDS="delve|realm|pivotal|revolutioniz|seamless|cutting-edge|game-chang|leverage|synergy|paradigm|holistic|it's worth noting|generally speaking|in order to|due to the fact|at the end of the day|to be honest|in all honesty"

# strip_links: blank out citation / source-metadata lines so verbatim source
# titles (which legitimately contain em dashes and apostrophes) are not scanned.
# Exempts markdown link references, any line carrying a URL, and structured
# citation fields (title/url/source/citation/@id), which hold publisher-verbatim
# text. Exempt lines are REPLACED with empty lines, never deleted (#688): the
# scanners downstream use `grep -n`, and deleting lines would renumber the
# filtered stream so every reported line number after the first exempt line
# pointed at the wrong line of the real file.
strip_links () {
  awk '/\]\(http|http[s]?:\/\/|^[[:space:]]*[">-]*[[:space:]]*"?(title|url|source|citation|@id|name)"?[[:space:]]*:/ { print ""; next } { print }' "$1" 2>/dev/null
}

mech_hits () { # $1=file ; prints mechanical violations (empty => clean), per enabled rules
  local body; body=$(strip_links "$1")
  {
    [ "$RULE_PUNCT" = true ] && printf '%s\n' "$body" | grep -nE "$EMDASH|$ENDASH|$HELLIP|$LSQUO|$RSQUO|$LDQUO|$RDQUO" | sed 's/^/  char: /'
    [ "$RULE_CONTRACTIONS" = true ] && printf '%s\n' "$body" | grep -nEi "\b$CONTRACTIONS\b" | sed 's/^/  contraction: /'
  } | head -20
}

buzz_hits () { # $1=file ; prints buzzword/filler warnings (when enabled)
  [ "$RULE_BUZZ" = true ] || return 0
  strip_links "$1" | grep -nEi "$BUZZWORDS" | sed 's/^/  buzzword: /' | head -10
}

is_authored_surface () { # echo "yes" or ""
  case "$1" in
    reports/*/*.blog.md|reports/*/*.book.md) echo yes ;;
    reports/*/research-progress.md) echo "" ;;
    reports/*/findings/*|reports/*/sources/*|reports/*/quarantine/*|reports/*/_meta/*) echo "" ;;
    reports/*/*.md)
      # canonical report only: reports/<slug>/<slug>.md (basename == dirname)
      d=$(basename "$(dirname "$1")"); b=$(basename "$1" .md)
      [ "$d" = "$b" ] && echo yes || echo "" ;;
    reports/*/book/chapters/*.md|reports/*/book/appendices/*.md|reports/*/book/front-matter/*.md) echo yes ;;
    *) echo "" ;;
  esac
}

PROFILE_NOTE="Authored prose in this repo must read in the configured voice profile ('${VOICE_PROFILE}'). Apply it via /human-voice:human-voice and fix each line below at the source; do not merely strip the character. Configure the profile and rules in harness.config.json \`voice\`."

case "$MODE" in
  post)
    INPUT=$(cat /dev/stdin)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    REL="${FILE_PATH#"${CLAUDE_PROJECT_DIR:-}"/}"
    [ "$(is_authored_surface "$REL")" = yes ] || exit 0
    ABS="${CLAUDE_PROJECT_DIR:-.}/$REL"
    [ -f "$ABS" ] || exit 0
    MECH=$(mech_hits "$ABS")
    BUZZ=$(buzz_hits "$ABS")
    [ -z "$MECH" ] && [ -z "$BUZZ" ] && exit 0
    MSG="Voice gate (${VOICE_PROFILE}): ${REL} violates the configured published-voice rules.
${PROFILE_NOTE}"
    [ -n "$MECH" ] && MSG="${MSG}

MECHANICAL (must fix):
${MECH}"
    [ -n "$BUZZ" ] && MSG="${MSG}

BUZZWORD/FILLER (review):
${BUZZ}"
    jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
    exit 0
    ;;

  stop)
    cat /dev/stdin >/dev/null 2>&1
    cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
    command -v git >/dev/null 2>&1 || exit 0
    CHANGED=$(git status --porcelain --untracked-files=all -- \
                'reports/*/*.md' \
                'reports/*/book/chapters/*.md' 'reports/*/book/appendices/*.md' 'reports/*/book/front-matter/*.md' 2>/dev/null | sed 's/^...//')
    [ -z "$CHANGED" ] && exit 0
    OFFENDERS=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      [ "$(is_authored_surface "$f")" = yes ] || continue
      if [ -n "$(mech_hits "$f")" ]; then OFFENDERS="${OFFENDERS}${f} "; fi
    done <<< "$CHANGED"
    [ -z "$OFFENDERS" ] && exit 0
    jq -n --arg files "$OFFENDERS" --arg p "$VOICE_PROFILE" '{decision:"block", reason:("Voice gate (" + $p + "): authored prose still carries mechanical voice violations and may not be reported complete: " + $files + "- rewrite each in the configured voice via /human-voice:human-voice. Verbatim source-link titles are exempt and not flagged.")}'
    exit 0
    ;;

  *) exit 0 ;;
esac
