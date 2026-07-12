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
  local out
  if ! out="$(curl -fsSL --max-time "${CONNECTOR_TIMEOUT_SECONDS:-20}" --retry 2 --retry-delay 1 \
      -H "User-Agent: research-harness-template-continuous-monitoring/1.0 (+https://github.com/modeled-information-format/research-harness-template)" \
      "$@" "$url" 2>/tmp/connector-fetch-err.$$)"; then
    echo "connector_fetch: request failed: $url ($(cat /tmp/connector-fetch-err.$$ 2>/dev/null))" >&2
    rm -f /tmp/connector-fetch-err.$$
    return 1
  fi
  rm -f /tmp/connector-fetch-err.$$
  printf '%s' "$out"
}

# connector_emit <source> <jq-filter> <raw-response-file-or-'-'>
# Applies a jq filter that must itself produce an array of candidate objects
# shaped: {source, id, title, summary, url, published, authors, raw}. Validates
# the result is a JSON array before printing (fail-closed on malformed output).
connector_emit() {
  local source="$1" filter="$2" input="$3"
  local result
  if [ "$input" = "-" ]; then
    result="$(jq -c "$filter" 2>/tmp/connector-emit-err.$$)" || {
      echo "connector_emit[$source]: jq filter failed: $(cat /tmp/connector-emit-err.$$)" >&2
      rm -f /tmp/connector-emit-err.$$
      return 1
    }
  else
    result="$(jq -c "$filter" "$input" 2>/tmp/connector-emit-err.$$)" || {
      echo "connector_emit[$source]: jq filter failed: $(cat /tmp/connector-emit-err.$$)" >&2
      rm -f /tmp/connector-emit-err.$$
      return 1
    }
  fi
  rm -f /tmp/connector-emit-err.$$
  if ! printf '%s' "$result" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "connector_emit[$source]: filter did not produce a JSON array" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

# connector_xml_to_json
# Normalizes Atom/RSS XML (read from stdin) to JSON (printed to stdout) via
# scripts/monitoring/lib/xml_to_json.py — kept in its own file rather than an
# inline heredoc, since a heredoc would consume stdin as the script source
# and leave nothing for the piped feed document.
connector_xml_to_json() {
  python3 "$ROOT/scripts/monitoring/lib/xml_to_json.py"
}

# connector_budget_check <deadline-epoch-seconds>
# Returns non-zero (and prints a message) once the shared per-run budget
# deadline (set by scripts/monitoring/lib/budget.sh) has passed. Connectors
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
