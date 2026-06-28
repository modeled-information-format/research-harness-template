#!/usr/bin/env bash
# mermaid-render.sh — eval: a Mermaid diagram in a section body survives rendering
# intact and validates. Guards the render-artifact.sh fix that excludes fenced code
# blocks from the prose deglob/autolink pass (escaping "*"/"_" or autolinking a URL
# inside a ```mermaid fence corrupts the diagram). Self-contained; writes only to a
# private mktemp dir. Exit 0 iff every assertion holds.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# An artifact whose section body carries a Mermaid figure with characters the prose
# pass would mangle: a space-flanked "*", a space-flanked "_", and a bare URL.
jq -n '{
  "@type":"Artifact", title:"Mermaid render eval", genre:"engineering",
  finding_refs:["urn:mif:concept:eval:m"],
  sources:[{title:"S", url:"https://example.com/s", citationType:"website", citationRole:"supports"}],
  sections:[{heading:"Architecture", supports:["urn:mif:concept:eval:m"],
    body:"Prose with weight * 2 and a _ b.\n\n```mermaid\nflowchart TD\n  A[Start] --> B{weight * 2}\n  B --> C[node_done]\n  C --> D[docs https://example.com/x]\n```\n\nEnd."}]
}' > "$TMP/art.json"

for ch in blog book; do
  scripts/render-artifact.sh "$TMP/art.json" "$ch" "$TMP/$ch.md" >/dev/null
  # exactly one mermaid fence survives
  [ "$(grep -c '```mermaid' "$TMP/$ch.md")" -ge 1 ] || { echo "no mermaid fence in $ch" >&2; exit 1; }
  # the diagram body is uncorrupted: no escaped "\*" / "\_" inside the fence
  block="$(sed -n '/```mermaid/,/```/p' "$TMP/$ch.md")"
  case "$block" in
    *'\*'*|*'\_'*) echo "mermaid corrupted in $ch: $block" >&2; exit 1 ;;
  esac
  # no ASCII-art diagram markers leaked into the body
  if grep -qE '\+----|--->|==>|digraph\{' "$TMP/$ch.md"; then
    echo "ASCII-art diagram marker in $ch" >&2; exit 1
  fi
  # the surviving block is structurally valid Mermaid
  python3 scripts/check-mermaid.py "$TMP/$ch.md" >/dev/null
  # prose OUTSIDE the fence is still escaped (the deglob pass still runs on prose)
  grep -q 'weight \\\* 2' "$TMP/$ch.md" || { echo "prose not escaped in $ch" >&2; exit 1; }
done

# Auto-generation: a section that carries entity/relationship data GENERATES a
# Mermaid graph rather than omitting it. Synthesize the shipped sample findings
# (which carry entities + relationships) and assert the rendered output contains
# >=1 generated graph that validates.
SF="reports/_meta/sample-session/findings"
scripts/synthesize-artifact.sh "$SF" general "$TMP/auto.json" >/dev/null
scripts/render-artifact.sh "$TMP/auto.json" blog "$TMP/auto.md" >/dev/null
[ "$(grep -c '```mermaid' "$TMP/auto.md")" -ge 1 ] || { echo "no auto-generated graph from graph-bearing findings" >&2; exit 1; }
python3 scripts/check-mermaid.py "$TMP/auto.md" >/dev/null

# Every Mermaid block committed in the repo is structurally valid too.
# (portable across bash 3.2 / 4+: no mapfile)
MM="$(git grep -l '```mermaid' -- '*.md' 2>/dev/null || true)"
[ -z "$MM" ] || python3 scripts/check-mermaid.py $MM >/dev/null
echo "mermaid-render: OK"
