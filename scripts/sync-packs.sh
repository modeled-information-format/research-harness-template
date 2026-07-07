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
ROOT="$(pwd)"

CFG="${1:-harness.config.json}"
OUT="${2:-.claude/enabled-packs.json}"
SETTINGS="${3:-.claude/settings.local.json}"
[ -f "$CFG" ] || { echo "sync-packs: config not found: $CFG" >&2; exit 2; }

# Resolve the materialized enablement (sidecar + the native enabledPlugins map)
# in one python pass so a manifest/parse failure is fatal (no stale OUT).
python3 - "$CFG" "$OUT" "$SETTINGS" <<'PY' || { echo "sync-packs: materialization failed" >&2; exit 1; }
import json, sys
cfg_path, out_path, settings_path = sys.argv[1:4]
cfg = json.load(open(cfg_path))
enabled = [p for p in cfg.get("packs", []) if p.get("enabled")]
marketplaces_by_name = {m["name"]: m for m in cfg.get("marketplaces", []) if isinstance(m, dict) and "name" in m}

# Each bundled plugin is one skill nested under its pack (packs/<pack>/<skill>/);
# resolve its directory from the marketplace's source path by plugin name rather
# than assuming packs/<name>/. Also the source of the marketplace's own name
# (used to key enabledPlugins as "<pack>@<marketplace>") — read once here
# rather than via a second read of the same file elsewhere in this script.
try:
    market_doc = json.load(open(".claude-plugin/marketplace.json"))
    market = market_doc.get("name", "research-harness")
    src_by_name = {p["name"]: p.get("source", "") for p in market_doc.get("plugins", [])}
except (OSError, ValueError):
    market = "research-harness"
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
    elif isinstance(src, dict) and src.get("type") == "marketplace-ref":
        # Resolve against the declared marketplaces[] entry by name; a pack-local
        # `ref` overrides the marketplace's own ref for this pack only.
        mkt_name = src.get("marketplace")
        mkt = marketplaces_by_name.get(mkt_name)
        entry = {"name": name, "source": "external", "type": "marketplace-ref",
                 "marketplace": mkt_name, "skills": []}
        if mkt is None:
            entry["url"] = None
            entry["ref"] = None
            entry["error"] = f"unresolved marketplace {mkt_name!r}: not declared in marketplaces[]"
        else:
            entry["url"] = mkt.get("url")
            entry["ref"] = src.get("ref", mkt.get("ref"))
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
# Rebuilds the sidecar's `.ontologies` key: every committed base layer under
# schemas/ontologies/ (core, if its id is mif-base/mif-generic/shared-traits)
# plus every ontology enabled in $CFG that is vendored under packs/ontologies/.
# A topic may bind only a cataloged id (gate_m12 enforces binding -> catalog ->
# registry). Since research-harness-template#276 (Story #277, Category A
# cutover), this delegates to the mif-rh engine (mif-rh-cli), hard required:
# install it with scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set
# MIF_RH_CLI.
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5
exec "$ENGINE" ontology sync --root "$ROOT" --config "$CFG" --catalog "$OUT"
