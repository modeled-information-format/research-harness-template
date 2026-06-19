#!/usr/bin/env bash
# sync-packs.sh — materialize the harness.config.json packs[] control plane into
# Claude Code's native plugin enablement (SPEC §7b). For each ENABLED pack it
# resolves the namespaced skills the pack contributes (pack:skill) and writes the
# materialized enablement set. Disabled packs are omitted, so their skills are not
# active. This is the mechanism behind "enabling a pack adds its namespaced skills
# and disabling removes them".
#
#   bundled pack  -> read packs/<name>/.claude-plugin/plugin.json provides.skills
#   external pack -> recorded as an external enablement (git/marketplace source);
#                    its skills resolve once the clone fetches the plugin.
#
# Usage: sync-packs.sh [<harness.config.json>] [<out.json>]
#        defaults: harness.config.json  ->  .claude/enabled-packs.json

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CFG="${1:-harness.config.json}"
OUT="${2:-.claude/enabled-packs.json}"
[ -f "$CFG" ] || { echo "sync-packs: config not found: $CFG" >&2; exit 2; }

# Build the materialized enablement. For each enabled pack, resolve its provided
# skills from the bundled plugin manifest (or mark external).
jq -n --slurpfile cfg "$CFG" --arg root "$(pwd)" '
  [ $cfg[0].packs[] | select(.enabled == true) ] as $enabled
  | {
      "@type": "EnabledPacks",
      generator: "sync-packs.sh (SPEC §7b)",
      enabledPlugins: [ $enabled[].name ],
      packs: [
        $enabled[]
        | . as $p
        | if (.source == "bundled")
          then {
            name: $p.name, source: "bundled",
            manifest: ("packs/" + $p.name + "/.claude-plugin/plugin.json")
          }
          else {
            name: $p.name, source: "external",
            type: $p.source.type, url: $p.source.url
          }
          end
      ]
    }
' > "$OUT.tmp"

# Second pass: for bundled packs, inline the namespaced skills from their manifests.
python3 - "$OUT.tmp" "$OUT" <<'PY'
import json, os, sys
tmp, out = sys.argv[1], sys.argv[2]
data = json.load(open(tmp))
for p in data["packs"]:
    if p.get("source") == "bundled":
        mf = p.pop("manifest")
        try:
            m = json.load(open(mf))
            p["skills"] = (m.get("provides") or {}).get("skills", [])
            p["kind"] = m.get("kind")
        except (OSError, ValueError):
            p["skills"] = []
            p["error"] = f"unreadable manifest: {mf}"
    else:
        p["skills"] = []  # resolved after the clone fetches the external plugin
json.dump(data, open(out, "w"), indent=2)
open(out, "a").write("\n")
os.remove(tmp)
PY

N=$(jq -r '.enabledPlugins | length' "$OUT")
echo "sync-packs: $N pack(s) enabled -> $OUT"
