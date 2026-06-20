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
# Usage: mif-project.sh <report.md> [--json-out <out.json>]
#   exit 0 = projects to a valid L3 finding; non-zero = not compliant.

set -uo pipefail

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

cd "$(dirname "$0")/.." || exit 2

# A temp dir so the projection carries a .json extension (ajv-cli selects its
# parser by file extension; an extensionless file is mis-parsed).
TMPD="$(mktemp -d)"; TMP="$TMPD/projection.json"; TMPE="$TMPD/err"; trap 'rm -rf "$TMPD"' EXIT

# Project frontmatter + body -> finding JSON (the JSON-LD projection of the MIF
# concept). Split the frontmatter from the body with plain text ops (finding the
# '---' delimiters is not YAML parsing), convert the frontmatter YAML -> JSON with
# yq (the YAML analog of jq — consistent jq/yq tooling), and fold the body in as
# MIF `content` unless the frontmatter already sets it.
if [ "$(sed -n '1p' "$MD")" != "---" ]; then
  echo "mif-project: $MD — no opening YAML frontmatter delimiter ('---' on line 1)" >&2; exit 1
fi
close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$MD")
if [ -z "$close" ]; then
  echo "mif-project: $MD — no closing frontmatter delimiter" >&2; exit 1
fi
sed -n "2,$((close-1))p" "$MD" > "$TMPD/fm.yaml"
sed -n "$((close+1)),\$p" "$MD" > "$TMPD/body.md"

if ! yq -p=yaml -o=json '.' "$TMPD/fm.yaml" > "$TMPD/fm.json" 2>"$TMPE"; then
  echo "mif-project: $MD — frontmatter is not valid YAML:" >&2; sed 's/^/  /' "$TMPE" >&2; exit 1
fi
if ! jq -e 'type=="object"' "$TMPD/fm.json" >/dev/null 2>&1; then
  echo "mif-project: $MD — frontmatter is not a mapping" >&2; exit 1
fi
# Fold the body in as `content` if the frontmatter does not set it (trim the body's
# surrounding blank lines). --rawfile avoids any arg-escaping of the body text.
if ! jq --rawfile body "$TMPD/body.md" '
      (if ((.content // "") == "") then .content = ($body | sub("^\\s+";"") | sub("\\s+$";"")) else . end)
      | (if ((.content // "") == "") then .content = (.title // "") else . end)
    ' "$TMPD/fm.json" > "$TMP" 2>"$TMPE"; then
  echo "mif-project: $MD — projection assembly failed:" >&2; sed 's/^/  /' "$TMPE" >&2; exit 1
fi

# Validate the projection at MIF L3 (same ajv closure as findings).
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/findings.schema.json \
      -r schemas/mif/mif.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$TMP" >/dev/null 2>&1; then
  echo "mif-project: $MD — projection does NOT validate against findings.schema.json (not MIF L3):" >&2
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/findings.schema.json \
      -r schemas/mif/mif.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$TMP" 2>&1 | sed 's/^/  /' >&2 || true
  exit 1
fi

# Citation-integrity (rejects a falsified verdict + dead/malformed citations).
if ! scripts/check-citation-integrity.sh "$TMP" >/dev/null 2>&1; then
  echo "mif-project: $MD — fails citation-integrity gate:" >&2
  scripts/check-citation-integrity.sh "$TMP" 2>&1 | sed 's/^/  /' >&2 || true
  exit 1
fi

[ -n "$JSON_OUT" ] && cp "$TMP" "$JSON_OUT"
echo "mif-project: $MD projects to a valid MIF L3 finding"
