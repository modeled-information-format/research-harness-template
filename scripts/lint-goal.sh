#!/usr/bin/env bash
# lint-goal.sh — deterministic verifiability lint for a session goal (#554).
#
# The research-goal workflow's Gate phase (.claude/workflows/research-goal.js)
# runs a verifiability lint before accepting a drafted goal. Agent judgment
# covers the fuzzy end of that lint ("is this assertion transcript-verifiable"),
# but two failure classes are machine-checkable and must never depend on model
# judgment to be caught — this script is that deterministic floor:
#
#   1. schema gate — the goal must validate against schemas/goal.schema.json
#      (ajv, draft2020 + ajv-formats). A schema-invalid goal fails closed here
#      and never reaches the content lint.
#   2. step-shaped check assertions — a completion_condition.check whose
#      assertion STARTS with an imperative research verb ("Search for …",
#      "Review the …") describes a step to take, not an end-state fact a
#      transcript can verify. Flagged per check, naming the verb.
#   3. off-config dimensions — every goal dimensions[] entry must be one of
#      the config-declared dimension ids (harness.config.json dimensions[].id).
#
# Exit 0 = no issues (prints "lint-goal: OK — <file>").
# Exit 1 = one or more lint issues, each printed on its own line.
# Exit 2 = usage / missing file. Exit 5 = missing toolchain.
#
# Usage: lint-goal.sh <goal.json> [--config <harness.config.json>]
#        (config defaults to the repo root harness.config.json)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "usage: lint-goal.sh <goal.json> [--config <harness.config.json>]" >&2
  exit 2
}

GOAL=""
CONFIG="$ROOT/harness.config.json"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:?--config needs a path}"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -n "$GOAL" ] && usage; GOAL="$1"; shift ;;
  esac
done
[ -n "$GOAL" ] || usage
[ -f "$GOAL" ] || { echo "lint-goal: not a file: $GOAL" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "lint-goal: config not a file: $CONFIG" >&2; exit 2; }

for tool in jq ajv; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "lint-goal: $tool is required but not on PATH" >&2
    exit 5
  }
done

issues=0
flag() { printf 'lint-goal: %s: %s\n' "$GOAL" "$1"; issues=$((issues + 1)); }

# --- 1. Schema gate (fail closed: schema-invalid never reaches the content lint).
if ! ajv_out=$(ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s "$ROOT/schemas/goal.schema.json" -d "$GOAL" 2>&1); then
  flag "schema: ajv validation failed against schemas/goal.schema.json"
  printf '%s\n' "$ajv_out" | sed 's/^/  /'
  printf 'lint-goal: FAIL — %s (1 issue; schema gate, content lint not reached)\n' "$GOAL"
  exit 1
fi

# --- 2. Step-shaped check assertions.
# The deterministic subset of the workflow's "step, not end-state" judgment
# flag: an assertion whose FIRST word is an imperative research verb is a step.
STEP_VERB_RE='^[[:space:]]*(search|find|look|read|review|gather|collect|browse|survey|explore|investigate|research|compile|query|fetch|scan|interview|ask)([[:space:]]|$)'
while IFS= read -r check; do
  id=$(jq -r '.id' <<<"$check")
  assertion=$(jq -r '.assertion' <<<"$check")
  verb=$(printf '%s\n' "$assertion" | grep -i -oE "$STEP_VERB_RE" | head -1 | tr -d '[:space:]' || true)
  if [ -n "$verb" ]; then
    flag "check '$id': step-shaped assertion (starts with imperative research verb '$verb', not an end-state fact): \"$assertion\""
  fi
done < <(jq -c '.completion_condition.checks[]' "$GOAL")

# --- 3. Off-config dimensions.
# Config-declared set: harness.config.json dimensions[].id (plain-string
# entries are accepted too, for reduced fixture configs).
declared=$(jq -c '[.dimensions // [] | .[] | if type == "object" then .id else . end]' "$CONFIG")
if [ "$(jq 'length' <<<"$declared")" -eq 0 ]; then
  flag "config $CONFIG declares no dimensions[] — cannot lint the goal's dimension set"
else
  while IFS= read -r dim; do
    flag "dimension '$dim' is not config-declared (allowed: $(jq -r 'join(", ")' <<<"$declared"))"
  done < <(jq -r --argjson ok "$declared" '.dimensions[] | select(. as $d | $ok | index($d) | not)' "$GOAL")
fi

if [ "$issues" -gt 0 ]; then
  printf 'lint-goal: FAIL — %s (%d issue(s))\n' "$GOAL" "$issues"
  exit 1
fi
printf 'lint-goal: OK — %s\n' "$GOAL"
exit 0
