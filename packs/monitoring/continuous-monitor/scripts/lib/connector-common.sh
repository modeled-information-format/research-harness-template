#!/usr/bin/env bash
# connector-common.sh — shared helpers for Source Connectors (research-harness-template#418).
#
# Every connector is a thin, keyless-by-default HTTP client (NFR2/NFR3): plain
# curl against a free RSS/Atom feed or REST API, normalized to the candidate-item
# shape validated by schemas/monitoring-candidate.schema.json. No connector links
# a commercial SDK; swapping a source's transport later only touches its own
# connector script.
#
# Sourced, not executed: `. "$(dirname "$0")/../lib/connector-common.sh"`.
set -uo pipefail

# connector_fetch <url> [extra curl args...]
# Fail-closed HTTP GET: bounded timeout/retries, non-2xx or timeout is a hard
# failure (exit non-zero, message on stderr) — callers must not swallow this,
# it is exactly the signal Story #421's budget enforcement fails-closed on.
connector_fetch() {
  local url="$1"; shift || true
  local out err_file
  # mktemp, not a predictable /tmp/name.$$ path (symlink/clobber attack on
  # a shared multi-user /tmp -- a fixed PID-based name is guessable).
  err_file="$(mktemp)"
  if ! out="$(curl -fsSL --max-time "${CONNECTOR_TIMEOUT_SECONDS:-20}" --retry 2 --retry-delay 1 \
      -H "User-Agent: research-harness-template-continuous-monitoring/1.0 (+https://github.com/modeled-information-format/research-harness-template)" \
      "$@" "$url" 2>"$err_file")"; then
    echo "connector_fetch: request failed: $url ($(cat "$err_file" 2>/dev/null))" >&2
    rm -f "$err_file"
    return 1
  fi
  rm -f "$err_file"
  printf '%s' "$out"
}

# connector_emit <source> <jq-filter> <raw-response-file-or-'-'>
# Applies a jq filter that must itself produce an array of candidate objects
# shaped: {source, id, title, summary, url, published, authors, raw}. Validates
# the result is a JSON array before printing (fail-closed on malformed output).
connector_emit() {
  local source="$1" filter="$2" input="$3"
  local result
  # mktemp, not a predictable /tmp/name.$$ path -- same rationale as
  # connector_fetch above.
  local err_file
  err_file="$(mktemp)"
  if [ "$input" = "-" ]; then
    result="$(jq -c "$filter" 2>"$err_file")" || {
      echo "connector_emit[$source]: jq filter failed: $(cat "$err_file")" >&2
      rm -f "$err_file"
      return 1
    }
  else
    result="$(jq -c "$filter" "$input" 2>"$err_file")" || {
      echo "connector_emit[$source]: jq filter failed: $(cat "$err_file")" >&2
      rm -f "$err_file"
      return 1
    }
  fi
  rm -f "$err_file"
  if ! printf '%s' "$result" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "connector_emit[$source]: filter did not produce a JSON array" >&2
    return 1
  fi

  # Schema-validate each item against monitoring-candidate.schema.json,
  # dropping (not failing the whole connector over) any item that doesn't
  # conform -- an external API's occasional malformed record shouldn't take
  # down an otherwise-good batch the way a connector-level network failure
  # should (NFR1's fail-closed posture is about the connector call itself).
  local schema="${ROOT:-}/schemas/monitoring-candidate.schema.json"
  if command -v ajv >/dev/null 2>&1 && [ -f "$schema" ]; then
    local count total kept=0 dropped=0 item tmp_item
    total="$(printf '%s' "$result" | jq 'length')"
    local valid_items="[]"
    for ((count = 0; count < total; count++)); do
      item="$(printf '%s' "$result" | jq -c ".[$count]")"
      tmp_item="$(mktemp).json"
      printf '%s' "$item" > "$tmp_item"
      if ajv validate --spec=draft2020 --strict=false -c ajv-formats -s "$schema" -d "$tmp_item" >/dev/null 2>&1; then
        valid_items="$(printf '%s' "$valid_items" | jq -c --argjson it "$item" '. + [$it]')"
        kept=$((kept + 1))
      else
        dropped=$((dropped + 1))
      fi
      rm -f "$tmp_item"
    done
    if [ "$dropped" -gt 0 ]; then
      echo "connector_emit[$source]: dropped $dropped/$total item(s) failing monitoring-candidate.schema.json" >&2
    fi
    result="$valid_items"
  fi

  printf '%s\n' "$result"
}

# _connector_common_dir: this file's OWN directory, self-located via
# BASH_SOURCE rather than inherited from a caller's $ROOT/$SCRIPT_DIR --
# this file is sourced by both top-level pack scripts and connectors/*.sh
# (different depths), so xml_to_json.py (its own sibling, always) must
# resolve independently of whatever the caller happened to compute.
_connector_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# connector_xml_to_json
# Normalizes Atom/RSS XML (read from stdin) to JSON (printed to stdout) via
# this file's own sibling xml_to_json.py — kept in its own file rather than
# an inline heredoc, since a heredoc would consume stdin as the script
# source and leave nothing for the piped feed document.
connector_xml_to_json() {
  python3 "$_connector_common_dir/xml_to_json.py"
}

# connector_budget_check <deadline-epoch-seconds>
# Returns non-zero (and prints a message) once the shared per-run budget
# deadline (set by run-with-budget.sh, this pack's per-connector timeout
# wrapper) has passed. Connectors
# that fetch in a loop (pagination) should check this between pages.
connector_budget_check() {
  local deadline="$1"
  local now
  now="$(date +%s)"
  if [ "$now" -ge "$deadline" ]; then
    echo "connector_budget_check: per-run budget deadline exceeded" >&2
    return 1
  fi
  return 0
}
