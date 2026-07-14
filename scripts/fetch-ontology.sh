#!/usr/bin/env bash
# fetch-ontology.sh — on-demand vendoring of a domain ontology pack.
#
# Given an ontology id, this resolves the id's `extends` closure from the
# canonical registry index, fetches each domain layer that is not already
# present, VERIFIES every fetched file's sha256 against the index (fail-closed),
# materializes it as a harness pack under packs/ontologies/<id>/, and pins the
# result in ontologies.lock.json.
#
# Base layers (mif-base, mif-generic, shared-traits, engineering-base) ship
# committed under schemas/ontologies/<id>/ and are NEVER fetched — an extends
# ancestor that resolves to a committed base layer is satisfied locally.
#
# Source (where the index + yaml files live), in precedence order:
#   1. $MIF_ONTOLOGY_SOURCE         (env override; a dir path or http(s):// base)
#   2. .ontologies.source           (file in repo root, one line)
#   3. https://mif-spec.dev/ontologies   (canonical default)
# A local directory source (dev/CI/offline) is read with cp; an http source is
# read with curl. The index is always <source>/index.json.
#
# Since research-harness-template#276 (Story #277, Category A cutover),
# this delegates entirely to the mif-rh engine (mif-rh-cli), which
# implements the resolution/fetch/verify/vendor/pin logic above natively.
# The engine is hard required: install it with scripts/fetch-engine.sh, put
# mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# --refresh is passed through to `ontology fetch` (rht#270/#339): once the
# installed mif-rh-cli supports pin-holding, an id already pinned in
# ontologies.lock.json is left untouched (with a warning) when its version
# differs from the registry's current one, unless --refresh is passed to
# advance it deliberately, so a corpus does not have an ontology's schema
# silently advance underneath its already-stamped findings just because the
# registry published a newer version. An engine that predates pin-holding
# does not have a --refresh flag at all and rejects it with a hard argument
# error, and never holds a pinned id regardless; see scripts/fetch-engine.sh
# for the pinned release this repo currently installs.
#
# Usage: fetch-ontology.sh <id> [<id> ...] [--refresh]
#        fetch-ontology.sh --all-enabled [--refresh]  # fetch every enabled domain ontology
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

refresh=""
args=()
for arg in "$@"; do
  case "$arg" in
    --refresh) refresh="--refresh" ;;
    *) args+=("$arg") ;;
  esac
done

if [ "${args[0]:-}" = "--all-enabled" ]; then
  exec "$ENGINE" ontology fetch --all-enabled --root "$ROOT" --config "$ROOT/harness.config.json" ${refresh:+"$refresh"}
fi
[ "${#args[@]}" -ge 1 ] || {
  echo "fetch-ontology: usage: fetch-ontology.sh <id> [<id> ...] [--refresh] | --all-enabled [--refresh]" >&2
  exit 2
}
exec "$ENGINE" ontology fetch "${args[@]+"${args[@]}"}" --root "$ROOT" ${refresh:+"$refresh"}
