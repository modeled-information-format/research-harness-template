#!/usr/bin/env bash
# monitoring-workflow-install.sh — regression eval for the monitoring
# workflow delivery gap (research-harness-template#517): copier excludes
# .github/workflows/* wholesale, so instances could never receive
# monitor.yml/monitor-gate.yml and the documented commands failed in every
# instantiated clone. The fix ships the canonical workflow sources with the
# pack and materializes them via scripts/install-monitoring-workflows.sh.
#
# Covers, against a throwaway fake-instance tree under mktemp (never the
# real repo):
#   1. The pack ships both workflow sources (monitor.yml, monitor-gate.yml).
#   2. Install materializes byte-identical copies into .github/workflows/.
#   3. Idempotence: a second run reports up-to-date and changes nothing.
#   4. Drift detection: after the pack source changes, --check exits
#      non-zero naming the update, and a real run reconverges the copy.
#   5. The disabled-pack advisory note is emitted (installing while the
#      pack is off is allowed but must not be silent).
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  monitoring-workflow-install: %s\n' "$1"; }

SRC_DIR="packs/monitoring/continuous-monitor/workflows"

# Case 1: the pack ships both sources.
for f in monitor.yml monitor-gate.yml; do
  [ -f "$SRC_DIR/$f" ] || { note "pack workflow source missing: $SRC_DIR/$f"; fail=1; }
done
[ "$fail" -eq 0 ] || exit 1

# Fake instance: the script resolves ROOT from its own location, so give it
# a full miniature tree.
FAKE="$TMP/instance"
mkdir -p "$FAKE/scripts" "$FAKE/$SRC_DIR"
cp scripts/install-monitoring-workflows.sh "$FAKE/scripts/"
cp "$SRC_DIR"/*.yml "$FAKE/$SRC_DIR/"
printf '{"packs": [{"name": "continuous-monitor", "enabled": false}]}' > "$FAKE/harness.config.json"

# Case 2 + 5: first install materializes identical copies and notes the
# disabled pack.
if ! bash "$FAKE/scripts/install-monitoring-workflows.sh" > "$TMP/run1.out" 2> "$TMP/run1.err"; then
  note "first install failed: $(cat "$TMP/run1.err")"
  fail=1
fi
for f in monitor.yml monitor-gate.yml; do
  cmp -s "$FAKE/$SRC_DIR/$f" "$FAKE/.github/workflows/$f" || { note "installed $f is not byte-identical to its pack source"; fail=1; }
done
grep -q "not enabled" "$TMP/run1.err" || { note "disabled-pack advisory note missing from stderr"; fail=1; }

# Case 3: idempotence.
bash "$FAKE/scripts/install-monitoring-workflows.sh" > "$TMP/run2.out" 2>/dev/null || { note "second install run failed"; fail=1; }
grep -q "up to date" "$TMP/run2.out" || { note "second run did not report up to date"; fail=1; }
grep -q "installed" "$TMP/run2.out" && { note "second run reinstalled unchanged files"; fail=1; }

# Case 6 (ordered here so case 4's drift below still ends converged): an
# explicitly unmanaged copy is never overwritten (deliberate instance
# customization, e.g. a different cron cadence).
printf '\n# harness-workflow: unmanaged\n# custom cadence\n' >> "$FAKE/.github/workflows/monitor-gate.yml"
bash "$FAKE/scripts/install-monitoring-workflows.sh" > "$TMP/run-unmanaged.out" 2>/dev/null || { note "install failed with an unmanaged copy present"; fail=1; }
grep -q "unmanaged" "$TMP/run-unmanaged.out" || { note "installer did not report the unmanaged copy"; fail=1; }
grep -q "harness-workflow: unmanaged" "$FAKE/.github/workflows/monitor-gate.yml" || { note "installer overwrote an unmanaged copy"; fail=1; }

# Case 4: drift after a pack-source change (the copier-update scenario).
printf '\n# drifted\n' >> "$FAKE/$SRC_DIR/monitor.yml"
if bash "$FAKE/scripts/install-monitoring-workflows.sh" --check > "$TMP/run3.out" 2>/dev/null; then
  note "--check exited 0 despite a drifted source"
  fail=1
fi
grep -q "would UPDATE" "$TMP/run3.out" || { note "--check did not name the drifted file"; fail=1; }
bash "$FAKE/scripts/install-monitoring-workflows.sh" >/dev/null 2>&1 || { note "reconverging install failed"; fail=1; }
cmp -s "$FAKE/$SRC_DIR/monitor.yml" "$FAKE/.github/workflows/monitor.yml" || { note "copy did not reconverge to the changed source"; fail=1; }

[ "$fail" -eq 0 ] && note "pack ships sources; install is idempotent, drift-aware, and loud about a disabled pack"
exit "$fail"
