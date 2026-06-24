#!/usr/bin/env bash
# sync-packs.sh — materialize the harness.config.json packs[] control plane into
# Claude Code's NATIVE plugin enablement (SPEC §7b). For each ENABLED pack it
# resolves the namespaced skills the pack contributes (pack:skill) and:
#   1. writes Claude Code's native `enabledPlugins` into settings.local.json
#      (the mechanism the runtime actually reads — "<pack>@<marketplace>": true).
#      This is INSTANCE-LOCAL materialized state (gitignored): it derives from
#      this repo's harness.config.json packs[], so it differs per instance and
#      must NOT live in the template-managed, byte-identical .claude/settings.json.
#      Claude Code deep-merges enabledPlugins across settings.json + settings.local.json,
#      so the runtime sees these enablements alongside settings.json's hooks.
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
# Usage: sync-packs.sh [<harness.config.json>] [<enabled-packs.json>] [<settings.local.json>]
#        defaults: harness.config.json  .claude/enabled-packs.json  .claude/settings.local.json

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CFG="${1:-harness.config.json}"
OUT="${2:-.claude/enabled-packs.json}"
SETTINGS="${3:-.claude/settings.local.json}"
[ -f "$CFG" ] || { echo "sync-packs: config not found: $CFG" >&2; exit 2; }

MARKET=$(jq -r '.name // "research-harness"' .claude-plugin/marketplace.json 2>/dev/null)

# Resolve the materialized enablement (sidecar + the native enabledPlugins map)
# in one python pass so a manifest/parse failure is fatal (no stale OUT).
python3 - "$CFG" "$OUT" "$SETTINGS" "$MARKET" <<'PY' || { echo "sync-packs: materialization failed" >&2; exit 1; }
import json, sys
cfg_path, out_path, settings_path, market = sys.argv[1:5]
cfg = json.load(open(cfg_path))
enabled = [p for p in cfg.get("packs", []) if p.get("enabled")]

# Each bundled plugin is one skill nested under its pack (packs/<pack>/<skill>/);
# resolve its directory from the marketplace's source path by plugin name rather
# than assuming packs/<name>/.
try:
    market_doc = json.load(open(".claude-plugin/marketplace.json"))
    src_by_name = {p["name"]: p.get("source", "") for p in market_doc.get("plugins", [])}
except (OSError, ValueError):
    src_by_name = {}

packs, enabled_plugins = [], {}
for p in enabled:
    name = p["name"]
    src = p.get("source")
    enabled_plugins[f"{name}@{market}"] = True
    if src == "bundled":
        base = src_by_name.get(name, f"packs/{name}").lstrip("./")
        mf = f"{base}/.claude-plugin/plugin.json"
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

# 2. native enablement — merge into the (instance-local) settings file without
#    disturbing other local keys (e.g. skillOverrides). settings_path defaults to
#    .claude/settings.local.json; the runtime deep-merges its enabledPlugins with
#    the template-managed .claude/settings.json.
try:
    settings = json.load(open(settings_path))
except (OSError, ValueError):
    settings = {}
settings["enabledPlugins"] = enabled_plugins
json.dump(settings, open(settings_path, "w"), indent=2); open(settings_path, "a").write("\n")
print(f"sync-packs: {len(enabled)} pack(s) enabled -> {settings_path} enabledPlugins + {out_path}")
PY

# --- Ontology catalog (SPEC §8c) ---
# Append the enabled ontology subset to the sidecar. Version is read from the
# vendored YAML with yq (the python pass above is stdlib-only — no PyPI YAML).
# Core ontologies (schemas/ontologies/) are ALWAYS cataloged; extended ontologies
# (packs/ontologies/<id>/) only when enabled in the config's ontologies[]. A topic
# may bind only a cataloged id (gate_m12 enforces binding -> catalog -> registry).
# yq is required here — fail fast rather than silently emit an empty catalog (which
# would cause confusing downstream resolver failures under `set -u`).
command -v yq >/dev/null 2>&1 || { echo "sync-packs: yq is required to build the ontology catalog" >&2; exit 1; }
onto='[]'
add_onto(){ # id version source core — skip a malformed ontology (empty/null id or version)
  { [ -z "$1" ] || [ "$1" = "null" ] || [ -z "$2" ] || [ "$2" = "null" ]; } && return 0
  onto=$(jq -c --arg id "$1" --arg v "$2" --arg s "$3" --argjson core "$4" \
    '. + [{id:$id, version:$v, source:$s, core:$core}]' <<<"$onto"); }
for y in schemas/ontologies/*/*.yaml; do
  [ -e "$y" ] || continue
  add_onto "$(yq -r '.ontology.id' "$y")" "$(yq -r '.ontology.version' "$y")" "$y" true
done
while IFS= read -r oid; do
  [ -z "$oid" ] && continue
  y="packs/ontologies/$oid/$oid.ontology.yaml"
  [ -f "$y" ] && add_onto "$oid" "$(yq -r '.ontology.version' "$y")" "$y" false
done < <(jq -r '.ontologies[]? | select(.enabled) | .id' "$CFG")
jq --argjson onto "$onto" '.ontologies = $onto' "$OUT" > "$OUT.onto.tmp" && mv "$OUT.onto.tmp" "$OUT"
echo "sync-packs: cataloged $(jq '.ontologies | length' "$OUT") ontolog(ies) (core + enabled)"
