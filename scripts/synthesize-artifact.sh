#!/usr/bin/env bash
# synthesize-artifact.sh — the report-synthesizer's deterministic substrate
# (SPEC §6d). Consumes the SURVIVING findings (verdict != falsified) under a
# findings dir and produces one typed Artifact (schemas/artifact.schema.json):
# the genre/channel-neutral intermediate that every output channel renders.
#
# Since research-harness-template#276 (Story #282, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: synthesize-artifact.sh <findings-dir> [<genre>] [<out.json>]
#        defaults: genre=general  out=<findings-dir>/../artifact.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

DIR="${1:?usage: synthesize-artifact.sh <findings-dir> [genre] [out.json]}"
[ -d "$DIR" ] || { echo "synthesize: not a directory: $DIR" >&2; exit 2; }
GENRE="${2:-general}"

if [ -n "${3:-}" ]; then
  exec "$ENGINE" harness synthesize-artifact "$DIR" "$GENRE" "$3"
fi
exec "$ENGINE" harness synthesize-artifact "$DIR" "$GENRE"
