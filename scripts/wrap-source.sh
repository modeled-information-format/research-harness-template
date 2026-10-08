#!/usr/bin/env bash
# wrap-source.sh — normalize a raw ingested source into a MIF source-envelope at
# the ingestion boundary (SPEC §10, inbound conformance) and validate it at MIF
# Level 3 BEFORE any analyst consumes it. Mirrors import-corpus.sh's
# validate-or-abort: a source that does not validate is refused, not silently
# passed downstream. The resulting envelope id -- urn:mif:<uuid5 of
# "source:<ns>:<slug">> (MIF 1.4; `scripts/mif-id.sh source:<ns>:<slug>` prints
# it) -- is what a finding's citation references, so a claim traces back to the
# primary text the analyst actually read. The legacy urn:mif:source:<ns>:<slug>
# form is kept in the envelope's `aliases`.
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
# shellcheck source=scripts/lib/mif-id.sh
. "$ROOT/scripts/lib/mif-id.sh"
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

# MIF 1.4 id shim (scripts/lib/mif-id.sh): the pinned engine still composes
# urn:mif:source:<ns>:<slug>, which the vendored MIF 1.4 schema rejects. It
# composes into a scratch file, validating against a copy of the MIF schema
# with only the @id pattern relaxed; this wrapper then rewrites the id to its
# urn:mif:<uuid> form (mif-rs#164's own rule) and re-validates the result
# against the REAL vendored schemas before anything reaches --out.
WS_TMP="$(mktemp -d)" || { echo "wrap-source: mktemp failed" >&2; exit 5; }
trap 'rm -rf "$WS_TMP"' EXIT
mif_compat_schema "$ROOT/schemas/mif/mif.schema.json" "$WS_TMP/mif-compat.schema.json" \
  || { echo "wrap-source: could not prepare the engine compatibility schema" >&2; exit 5; }
ARGS=(harness wrap-source --url "$URL" --content-type "$CT" --namespace "$NS" --slug "$SLUG" --out "$WS_TMP/engine.json"
      --schema "$ROOT/schemas/mif/source-envelope.schema.json"
      --ref "$WS_TMP/mif-compat.schema.json"
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
  # NOTE the engine ALSO treats an empty --content as absent and falls back
  # to stdin (mif-rs#105) -- the real mitigation is the stdin detach at the
  # exec below, which turns that fallback into an instant EOF and the
  # engine's normal empty-content refusal.
  ARGS+=(--content "$CONTENT")
fi

# When content came from a flag/file, the engine must NOT touch stdin: it
# treats an empty --content as "not provided" and falls back to reading
# stdin (mif-rh harness_wrap), which blocks forever on a never-EOF pipe
# (#531). Detach stdin on every explicit-content path; only the documented
# stdin path (no --content-file, no --content) keeps it attached.
# The engine's stdout is captured, not passed through: on success it is only
# a "wrote <scratch path> (<pre-migration id>)" line, superseded by this
# wrapper's own report below; on failure it is replayed to stderr so no
# engine diagnostic is lost.
if [ -n "$CFILE" ] || [ -n "${CONTENT_SET:-}" ]; then
  "$ENGINE" "${ARGS[@]+"${ARGS[@]}"}" </dev/null >"$WS_TMP/engine.out"
else
  "$ENGINE" "${ARGS[@]+"${ARGS[@]}"}" >"$WS_TMP/engine.out"
fi
rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$WS_TMP/engine.out" >&2
  exit "$rc"
fi

# Same namespace/slug record mif-rs#164 adds under extensions.harness.source,
# so the envelope stays findable by topic now that its id is opaque.
if ! mif_json_migrate_id "$WS_TMP/engine.json" "$WS_TMP/envelope.json" \
     '.extensions.harness.source.namespace = $ns | .extensions.harness.source.slug = $slug' \
     --arg ns "$NS" --arg slug "$SLUG"; then
  echo "wrap-source: could not assign the MIF 1.4 source id" >&2
  exit 1
fi
# Re-validate the migrated envelope against the REAL vendored schemas (the
# engine only saw the relaxed @id pattern). ajv-cli + ajv-formats are part of
# the harness toolchain; a missing validator is named as such, never reported
# as an invalid source, and a real validation failure shows ajv's errors.
if ! command -v ajv >/dev/null 2>&1; then
  echo "wrap-source: ajv (ajv-cli + ajv-formats, see CLAUDE.md toolchain) is not on PATH — cannot validate the envelope; nothing written to $OUT" >&2
  exit 5
fi
TMO=""
if command -v timeout >/dev/null 2>&1; then TMO="timeout 30"
elif command -v gtimeout >/dev/null 2>&1; then TMO="gtimeout 30"
fi
$TMO ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s "$ROOT/schemas/mif/source-envelope.schema.json" \
  -r "$ROOT/schemas/mif/mif.schema.json" \
  -r "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
  -d "$WS_TMP/envelope.json" >"$WS_TMP/ajv.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  if [ "$rc" -eq 124 ]; then
    echo "wrap-source: validating the envelope TIMED OUT after 30s — refused; nothing written to $OUT" >&2
  else
    echo "wrap-source: the envelope does NOT validate against the vendored MIF schemas — refused; nothing written to $OUT" >&2
    sed 's/^/  /' "$WS_TMP/ajv.out" >&2
  fi
  exit 1
fi
mkdir -p "$(dirname "$OUT")" && cp "$WS_TMP/envelope.json" "$OUT" \
  || { echo "wrap-source: failed to write $OUT" >&2; exit 1; }
echo "wrap-source: wrote $OUT ($(jq -r '."@id"' "$OUT"), $CT)"
