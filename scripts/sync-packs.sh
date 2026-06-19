#!/usr/bin/env bash
# sync-packs.sh — materialize the harness.config.json packs[] control plane into
# Claude Code's NATIVE plugin enablement (SPEC §7b). For each ENABLED pack it
# resolves the namespaced skills the pack contributes (pack:skill) and:
#   1. writes Claude Code's native `enabledPlugins` into settings.json
#      (the mechanism the runtime actually reads — "<pack>@<marketplace>": true);
#   2. writes a detailed sidecar (.claude/enabled-packs.json) recording each
#      enabled pack's source and resolved skills, for tooling and the gate.
# Disabled packs are omitted from both, so their skills are not active. This is
# the mechanism behind "enabling a pack adds its namespaced skills and disabling
# removes them".
#
#   bundled pack  -> read packs/<name>/.claude-plugin/plugin.json provides.skills
#   external pack -> recorded as an external enablement (git/marketplace source);
#                    its skills resolve once the clone fetches the plugin.
#
# Usage: sync-packs.sh [<harness.config.json>] [<enabled-packs.json>] [<settings.json>]
#        defaults: harness.config.json  .claude/enabled-packs.json  .claude/settings.json

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CFG="${1:-harness.config.json}"
OUT="${2:-.claude/enabled-packs.json}"
SETTINGS="${3:-.claude/settings.json}"
[ -f "$CFG" ] || { echo "sync-packs: config not found: $CFG" >&2; exit 2; }

MARKET=$(jq -r '.name // "research-harness"' .claude-plugin/marketplace.json 2>/dev/null)

# Resolve the materialized enablement (sidecar + the native enabledPlugins map)
# in one python pass so a manifest/parse failure is fatal (no stale OUT).
python3 - "$CFG" "$OUT" "$SETTINGS" "$MARKET" <<'PY' || { echo "sync-packs: materialization failed" >&2; exit 1; }
import json, sys
cfg_path, out_path, settings_path, market = sys.argv[1:5]
cfg = json.load(open(cfg_path))
enabled = [p for p in cfg.get("packs", []) if p.get("enabled")]

packs, enabled_plugins = [], {}
for p in enabled:
    name = p["name"]
    src = p.get("source")
    enabled_plugins[f"{name}@{market}"] = True
    if src == "bundled":
        mf = f"packs/{name}/.claude-plugin/plugin.json"
        entry = {"name": name, "source": "bundled"}
        try:
            m = json.load(open(mf))
            entry["kind"] = m.get("kind")
            entry["skills"] = (m.get("provides") or {}).get("skills", [])
        except (OSError, ValueError) as e:
            entry["skills"] = []
            entry["error"] = f"unreadable manifest {mf}: {e}"
        packs.append(entry)
    else:
        packs.append({"name": name, "source": "external",
                      "type": (src or {}).get("type"), "url": (src or {}).get("url"),
                      "skills": []})

# 1. sidecar
sidecar = {"@type": "EnabledPacks", "generator": "sync-packs.sh (SPEC §7b)",
           "enabledPlugins": [p["name"] for p in packs], "packs": packs}
json.dump(sidecar, open(out_path, "w"), indent=2); open(out_path, "a").write("\n")

# 2. native enablement — merge into settings.json without disturbing hooks etc.
try:
    settings = json.load(open(settings_path))
except (OSError, ValueError):
    settings = {}
settings["enabledPlugins"] = enabled_plugins
json.dump(settings, open(settings_path, "w"), indent=2); open(settings_path, "a").write("\n")
print(f"sync-packs: {len(enabled)} pack(s) enabled -> {settings_path} enabledPlugins + {out_path}")
PY
