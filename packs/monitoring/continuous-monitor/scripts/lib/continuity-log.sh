#!/usr/bin/env bash
# continuity-log.sh — Continuity Log sink (research-harness-template#421).
#
# Every ingestion failure, budget breach, and Editorial Gate rejection
# (research-harness-template#422) is appended here, never dropped silently
# (NFR1). One JSON object per line, git-native under
# reports/<topic>/monitoring/continuity-log.jsonl (NFR7), each line
# schema-validated against schemas/monitoring-continuity-log-entry.schema.json
# before it's appended -- an entry that fails to validate is a bug in this
# script, and is refused rather than silently corrupting the log.
#
# Sourced, not executed: `. "$(dirname "$0")/lib/continuity-log.sh"`.
set -uo pipefail

# monitoring_base_dir <root> <subject>
# A topic's monitoring artifacts live under reports/<topic>/monitoring/; a
# first-class monitoring domain's (#521 -- an id in monitoringDomains[],
# decoupled from topics[]) under reports/_monitoring/<domain>/. The
# distinction is config-driven, so every path-deriving caller (run dirs,
# this log, the gate) agrees on one mapping.
monitoring_base_dir() {
  local root="$1" subject="$2"
  local cfg="${HARNESS_CONFIG:-$root/harness.config.json}"
  if jq -e --arg d "$subject" '(.monitoringDomains // [])[] | select(.id == $d)' "$cfg" >/dev/null 2>&1; then
    printf '%s' "$root/reports/_monitoring/$subject"
  else
    printf '%s' "$root/reports/$subject/monitoring"
  fi
}

# continuity_log_append <root> <subject> <run_id> <event_type> <source> <reason> [details-json]
continuity_log_append() {
  local root="$1" topic="$2" run_id="$3" event_type="$4" src="$5" reason="$6"
  # NOT "${7:-{}}" -- nested braces in a parameter-expansion default value
  # are mis-scanned by this bash version (it appends a stray trailing "}"
  # instead of treating "{}" as the whole default), verified empirically.
  local details="${7:-}"
  [ -z "$details" ] && details="{}"
  local log_dir
  log_dir="$(monitoring_base_dir "$root" "$topic")"
  local log_file="$log_dir/continuity-log.jsonl"
  mkdir -p "$log_dir"

  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local entry
  entry="$(jq -nc \
    --arg run_id "$run_id" \
    --arg timestamp "$timestamp" \
    --arg topic "$topic" \
    --arg event_type "$event_type" \
    --arg source "$src" \
    --arg reason "$reason" \
    --argjson details "$details" \
    '{run_id: $run_id, timestamp: $timestamp, topic: $topic, event_type: $event_type, source: $source, reason: $reason, details: $details}')" || {
    echo "continuity_log_append: failed to build entry JSON" >&2
    return 1
  }

  local schema="$root/schemas/monitoring-continuity-log-entry.schema.json"
  # Hard-required, not "validate if available": this header's own contract
  # is "an entry that fails to validate is refused", which a missing ajv
  # would otherwise silently bypass. Fail closed instead, matching
  # write-finding.sh's precedent (ajv is unconditional there too).
  if ! command -v ajv >/dev/null 2>&1; then
    echo "continuity_log_append: 'ajv' is required on PATH to schema-validate log entries and was not found" >&2
    return 1
  fi
  if [ -f "$schema" ]; then
    # A real temp file, not /dev/stdin -- ajv-cli does not reliably read a
    # piped special file as -d's data argument (verified empirically: it
    # reports the JSON's own top-level keys as "missing"). The .json suffix
    # is required too -- ajv-cli infers the parser from the extension, and
    # an extensionless mktemp file gets parsed as YAML (verified: "Unexpected
    # token ':'" on plain JSON without it).
    local tmp_entry
    tmp_entry="$(mktemp).json"
    printf '%s' "$entry" > "$tmp_entry"
    local valid=0
    ajv validate --spec=draft2020 --strict=false -c ajv-formats -s "$schema" -d "$tmp_entry" >/dev/null 2>&1 || valid=1
    rm -f "$tmp_entry"
    if [ "$valid" -ne 0 ]; then
      echo "continuity_log_append: refusing to write a schema-invalid entry: $entry" >&2
      return 1
    fi
  fi

  printf '%s\n' "$entry" >> "$log_file"
  echo "continuity-log[$topic]: $event_type from $src: $reason" >&2
}
