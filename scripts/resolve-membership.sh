#!/usr/bin/env bash
# resolve-membership.sh — the deterministic scope-resolution pass (SPEC §11).
#
# For a goal version, classify the topic's existing findings against that version's
# contract and emit the authoritative per-version members file
# reports/<topic>/goals/goal-<version>.members.json:
#
#   { version, generated, members[], stale[], gap_dimensions[] }
#
#   members        — findings IN SCOPE for this version (dimension is one of the
#                    goal's dimensions AND verdict is not "falsified").
#   stale          — in-scope findings whose verification has decayed under
#                    source-type decay (re_verify_by = attempted_at + TTL, where
#                    TTL is the MIN over the finding's citations' citationType
#                    windows from harness.config freshness; a finding with no
#                    attempted_at is freshness-unknown -> stale).
#   gap_dimensions — goal dimensions with no in-scope finding (must be researched).
#
# This is the DETERMINISTIC floor. Ambiguous in/out-of-scope judgement (against the
# goal's out_of_scope/non_goals prose) is layered on top by the goal-writer command,
# which calls this and then refines the members file. The result is a re-derivable
# projection; build-index.sh mirrors goal_versions[] onto each finding from it.
#
# Usage: resolve-membership.sh <topic> [<goal-version>]
#        version defaults to the content hash of reports/<topic>/goal.json.

set -uo pipefail

die() { echo "resolve-membership: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"

HERE="$(cd "$(dirname "$0")" && pwd)"
# Anchor to the repo root (the script lives in <root>/scripts) when not told
# otherwise, so the script is runnable from any working directory.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HERE/.." && pwd)}"
CONFIG="$PROJECT_DIR/harness.config.json"

TOPIC="${1:?usage: resolve-membership.sh <topic> [<goal-version>]}"
TOPIC_DIR="$PROJECT_DIR/reports/$TOPIC"
GOAL="$TOPIC_DIR/goal.json"
FINDINGS_DIR="$TOPIC_DIR/findings"

[ -f "$GOAL" ] || die "no goal for topic \"$TOPIC\": $GOAL"

VERSION="${2:-$(bash "$HERE/goal-version.sh" "$GOAL")}"

DIMS=$(jq -c '.dimensions // []' "$GOAL")
FRESH=$(jq -c '.freshness // {}' "$CONFIG" 2>/dev/null || echo '{}')

# Collect finding files space-safely (the harness is a template cloned into
# arbitrary paths, which may contain spaces).
FILES=()
while IFS= read -r -d '' f; do FILES+=("$f"); done \
  < <(find "$FINDINGS_DIR" -maxdepth 1 -name '*.json' -print0 2>/dev/null | sort -z)

if [ ${#FILES[@]} -eq 0 ]; then
  CLASSIFIED='{"member_objs":[],"stale":[]}'
else
  CLASSIFIED=$(jq -s \
    --argjson dims "$DIMS" \
    --argjson fresh "$FRESH" '
    ($fresh.default_days // 180) as $def
    | ($fresh.by_citation_type // {}) as $byt
    | map(
        (.["@id"]) as $id
        | (.extensions.harness.dimension // null) as $dim
        | ((.extensions.harness.verification.verdict // "none") != "falsified"
           and ($dims | index($dim)) != null) as $in
        # TTL = MIN over the finding citations whose citationType has a window;
        # select(. != null) guards an untyped citation ($byt[null] would throw).
        | ([ .citations[]?.citationType | select(. != null) ]
           | map($byt[.] // $def) | (min // $def)) as $ttl
        | (.extensions.harness.verification.attempted_at // null) as $att
        | { id: $id, dim: $dim, in_scope: $in,
            stale: (
              if ($in | not) then false
              # Parse at DAY granularity from the date portion so every valid
              # RFC3339 form (Z, numeric offset, fractional) and bare date works;
              # freshness windows are measured in days, so time-of-day is moot.
              else (if $att == null then null
                    else (($att[0:10] + "T00:00:00Z") | fromdateiso8601?) end) as $t
                   | if $t == null then true else (now > ($t + $ttl*86400)) end
              end) }
      )
    | { member_objs: [ .[] | select(.in_scope) | {id, dim} ],
        stale:       [ .[] | select(.in_scope and .stale) | .id ] }' \
    "${FILES[@]}")
fi

[ -n "$CLASSIFIED" ] || die "classification failed for $TOPIC (malformed finding?)"

GENERATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUT_DIR="$TOPIC_DIR/goals"
OUT="$OUT_DIR/goal-$VERSION.members.json"
mkdir -p "$OUT_DIR"

# Preserve exclusions: ids the goal-writer's judgement removed as out-of-scope on a
# prior resolve of THIS version. Re-resolving (e.g. after gap research) honors them
# so a deterministic pass never re-adds what was deliberately excluded. The `// []`
# already guarantees a value in every branch (missing/corrupt file -> []).
EXCL=$(jq -c '.excluded // []' "$OUT" 2>/dev/null || echo '[]')

# Write atomically: render to a temp and rename only on success, so a jq failure
# never truncates an existing members file (which would lose the excluded[] record).
TMP_OUT="$OUT.tmp.$$"
jq -n \
  --arg version "$VERSION" \
  --arg generated "$GENERATED" \
  --argjson dims "$DIMS" \
  --argjson c "$CLASSIFIED" \
  --argjson excl "$EXCL" '
  ($c.member_objs | map(select(.id as $i | ($excl | index($i)) == null))) as $kept
  | {
      version: $version,
      generated: $generated,
      members: ($kept | map(.id)),
      stale: ($c.stale - $excl),
      excluded: $excl,
      gap_dimensions: ($dims - ($kept | map(.dim) | unique))
    }' > "$TMP_OUT" || { rm -f "$TMP_OUT"; die "failed to resolve membership for $TOPIC"; }
mv "$TMP_OUT" "$OUT"

echo "wrote $OUT"
jq -r '"  members: \(.members|length) | stale: \(.stale|length) | excluded: \(.excluded|length) | gap_dimensions: \(.gap_dimensions | if length==0 then "none" else join(", ") end)"' "$OUT"
