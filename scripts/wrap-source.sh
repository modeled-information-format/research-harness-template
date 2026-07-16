#!/usr/bin/env bash
# wrap-source.sh — normalize a raw ingested source into a MIF source-envelope at
# the ingestion boundary (SPEC §10, inbound conformance) and validate it at MIF
# Level 3 BEFORE any analyst consumes it. Mirrors import-corpus.sh's
# validate-or-abort: a source that does not validate is refused, not silently
# passed downstream. The resulting urn:mif:source:<ns>:<slug> id is what a
# finding's citation references, so a claim traces back to the primary text the
# analyst actually read.
#
# Since research-harness-template#276 (Story #302, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage:
#   wrap-source.sh --url <url> --content-type <mime> --namespace <ns> \
#                  --slug <slug> --out <path.json> [--title <t>] \
#                  [--content-file <f> | --content <text>] [--source-type <st>]
#
# Content is taken from --content-file, then --content, then stdin.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

URL="" CT="" NS="" SLUG="" OUT="" TITLE="" CFILE="" CONTENT="" STYPE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2;;
    --content-type) CT="$2"; shift 2;;
    --namespace) NS="$2"; shift 2;;
    --slug) SLUG="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --content-file) CFILE="$2"; shift 2;;
    --content) CONTENT="$2"; CONTENT_SET=1; shift 2;;
    --source-type) STYPE="$2"; shift 2;;
    *) echo "wrap-source: unknown arg: $1" >&2; exit 2;;
  esac
done
: "${URL:?--url required}" "${CT:?--content-type required}" "${NS:?--namespace required}" \
  "${SLUG:?--slug required}" "${OUT:?--out required}"

if [ -n "$CFILE" ]; then
  [ -f "$CFILE" ] || { echo "wrap-source: content file not found: $CFILE" >&2; exit 2; }
fi

ARGS=(harness wrap-source --url "$URL" --content-type "$CT" --namespace "$NS" --slug "$SLUG" --out "$OUT"
      --schema "$ROOT/schemas/mif/source-envelope.schema.json"
      --ref "$ROOT/schemas/mif/mif.schema.json"
      --ref "$ROOT/schemas/mif/definitions/entity-reference.schema.json")
[ -n "$TITLE" ] && ARGS+=(--title "$TITLE")
[ -n "$STYPE" ] && ARGS+=(--source-type "$STYPE")
if [ -n "$CFILE" ]; then
  ARGS+=(--content-file "$CFILE")
elif [ -n "${CONTENT_SET:-}" ]; then
  # An EXPLICIT --content is always forwarded, even when its value is empty
  # (research-harness-template#531): [ -n "$CONTENT" ] treated --content ""
  # as "not provided" and silently fell through to the engine's stdin path,
  # which blocks forever on a read() whenever stdin is an open pipe that
  # never EOFs (any backgrounded invocation of verify.sh/run-evals.sh,
  # whose smoke test exercises exactly this empty-content refusal case).
  # The engine sees the empty content and refuses it immediately instead.
  ARGS+=(--content "$CONTENT")
fi

# When content came from a flag/file, the engine must NOT touch stdin: it
# treats an empty --content as "not provided" and falls back to reading
# stdin (mif-rh harness_wrap), which blocks forever on a never-EOF pipe
# (#531). Detach stdin on every explicit-content path; only the documented
# stdin path (no --content-file, no --content) keeps it attached.
if [ -n "$CFILE" ] || [ -n "${CONTENT_SET:-}" ]; then
  exec "$ENGINE" "${ARGS[@]+"${ARGS[@]}"}" </dev/null
fi
exec "$ENGINE" "${ARGS[@]+"${ARGS[@]}"}"
