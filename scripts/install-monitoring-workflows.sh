#!/usr/bin/env bash
# install-monitoring-workflows.sh — materialize the continuous-monitor
# pack's GitHub Actions workflows into this clone's .github/workflows/
# (research-harness-template#517).
#
# Why this exists: copier.yml excludes .github/workflows/* wholesale (the
# template's own CI must never leak into instances), which also kept
# monitor.yml/monitor-gate.yml — the pack's unattended production callers —
# out of every instantiated clone, with no documented opt-in. The canonical
# workflow sources ship WITH the pack (packs/monitoring/continuous-monitor/
# workflows/, which copier does deliver); this script is the documented
# opt-in that copies them into .github/workflows/ where Actions can run
# them. The template repo keeps live copies of the same files; verify.sh's
# gate_monitoring_workflow_sync holds every installed copy byte-identical
# to its pack source, so drift after a `copier update` is caught, not
# silent.
#
# Usage: install-monitoring-workflows.sh [--check]
#   --check   Report what would be installed/updated without writing.
#
# Idempotent: unchanged files are left alone and reported as up to date.
# Re-run after any `copier update` that changes the pack's workflow sources.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SRC_DIR="$ROOT/packs/monitoring/continuous-monitor/workflows"
DEST_DIR="$ROOT/.github/workflows"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

[ -d "$SRC_DIR" ] || {
  echo "install-monitoring-workflows: pack workflow sources not found at $SRC_DIR" >&2
  exit 2
}

# Enablement is advisory here, not blocking: the workflows themselves gate
# on the packs[] control plane at runtime (run-monitoring.sh exits 0 when
# the pack is disabled), so installing them early is harmless — but say so.
PACK_ENABLED="$(jq -r '(.packs[]? | select(.name == "continuous-monitor") | .enabled) // false' "$ROOT/harness.config.json" 2>/dev/null || echo false)"
if [ "$PACK_ENABLED" != "true" ]; then
  echo "install-monitoring-workflows: note: the 'continuous-monitor' pack is not enabled in harness.config.json packs[] -- the workflows will install but no-op until it is" >&2
fi

CHANGED=0
for src in "$SRC_DIR"/*.yml; do
  name="$(basename "$src")"
  dest="$DEST_DIR/$name"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "install-monitoring-workflows: $name up to date"
    continue
  fi
  CHANGED=1
  if [ "$CHECK" -eq 1 ]; then
    if [ -f "$dest" ]; then
      echo "install-monitoring-workflows: would UPDATE $dest (differs from pack source)"
    else
      echo "install-monitoring-workflows: would INSTALL $dest"
    fi
    continue
  fi
  mkdir -p "$DEST_DIR"
  cp "$src" "$dest"
  echo "install-monitoring-workflows: installed $dest"
done

if [ "$CHECK" -eq 1 ] && [ "$CHANGED" -eq 1 ]; then
  exit 1
fi
exit 0
