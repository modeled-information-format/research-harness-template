#!/usr/bin/env bash
# mif-project.sh — project a MIF-L3 markdown report (YAML frontmatter + Markdown
# body) into its JSON-LD finding projection and validate it at MIF Level 3
# (SPEC §10, output conformance). The frontmatter is the authoritative MIF
# concept; the body is the MIF `content`. A report is "L3 MIF compliant
# markdown" iff this projection validates against schemas/findings.schema.json
# (the same bar as a finding) AND passes the citation-integrity gate (which
# rejects a falsified verdict and dead/malformed citations).
#
# Write-then-validate: render-artifact.sh's `report` channel calls this right
# after writing the .md and fails non-zero if the report does not project to a
# valid L3 finding. gate_m10 in verify.sh calls it over every emitted report.
#
# Since research-harness-template#276 (Category B cutover), both halves
# delegate to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI. The
# projection + schema-validation half moved in Story #298; the
# citation-integrity half (scripts/check-citation-integrity.sh) moved in
# Story #287 — still called as its own step below.
#
# Usage: mif-project.sh <report.md> [--json-out <out.json>]
#   exit 0 = projects to a valid L3 finding; non-zero = not compliant.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

# Resolve the report path against the INVOKING cwd before we cd to the repo root,
# so a caller-relative path (e.g. from an eval working dir) still resolves.
MD="${1:?usage: mif-project.sh <report.md> [--json-out <out.json>]}"
[ -f "$MD" ] || { echo "mif-project: report not found: $MD" >&2; exit 2; }
MD="$(cd "$(dirname "$MD")" && pwd)/$(basename "$MD")"
JSON_OUT=""
if [ "${2:-}" = "--json-out" ]; then
  JSON_OUT="${3:?--json-out needs a path}"
  case "$JSON_OUT" in /*) : ;; *) JSON_OUT="$(pwd)/$JSON_OUT" ;; esac
fi

TMPD="$(mktemp -d)"; TMP="$TMPD/projection.json"; trap 'rm -rf "$TMPD"' EXIT

if ! "$ENGINE" harness project-report "$MD" \
      --schema "$ROOT/schemas/findings.schema.json" \
      --ref "$ROOT/schemas/mif/mif.schema.json" \
      --ref "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
      --json-out "$TMP"; then
  "$ENGINE" harness project-report "$MD" \
      --schema "$ROOT/schemas/findings.schema.json" \
      --ref "$ROOT/schemas/mif/mif.schema.json" \
      --ref "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
      --json-out "$TMP" 2>&1 | sed 's/^/  /' >&2
  exit 1
fi

# Citation-integrity (rejects a falsified verdict + dead/malformed citations).
if ! "$ROOT/scripts/check-citation-integrity.sh" "$TMP" >/dev/null 2>&1; then
  echo "mif-project: $MD — fails citation-integrity gate:" >&2
  "$ROOT/scripts/check-citation-integrity.sh" "$TMP" 2>&1 | sed 's/^/  /' >&2 || true
  exit 1
fi

[ -n "$JSON_OUT" ] && cp "$TMP" "$JSON_OUT"
echo "mif-project: $MD projects to a valid MIF L3 finding"
