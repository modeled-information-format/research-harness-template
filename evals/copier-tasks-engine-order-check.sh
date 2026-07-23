#!/usr/bin/env bash
# copier-tasks-engine-order-check.sh — regression eval for
# research-harness-template#733.
#
# copier.yml's `_tasks` list ran `site-toggle.sh` FIRST, before
# `fetch-engine.sh` (fourth), even though site-toggle.sh has hard-required
# the mif-rh-cli engine since #276 -- so a fresh instance with no cached
# bin/mif-rh-cli failed the very first `_tasks` entry with exit 5 on every
# `copier copy`/`copier update`. The prior fix comment only accounted for
# fetch-ontology.sh/sync-packs.sh (below fetch-engine.sh), missing that
# site-toggle.sh (above it) had independently acquired the same dependency.
#
# CI never caught this because verify.sh already fetches the engine before
# any _tasks-equivalent step runs (ADR-0016) -- by the time a real
# `copier copy`/`copier update` eval exercises `_tasks` in CI, the engine is
# already cached, masking the ordering bug that reproduces on every real
# uncached instance. This eval is static analysis (no real copier run, no
# engine fetch) specifically so it can't be masked the same way: it proves
# fetch-engine.sh's position in the LIST precedes every task whose invoked
# script sources scripts/lib/engine.sh, regardless of whether the engine
# happens to be cached in the environment the eval runs in.
#
#   bash evals/copier-tasks-engine-order-check.sh   # exit 0 iff the order holds
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail() { echo "copier-tasks-engine-order-check: $1" >&2; exit 1; }

# Template-only (#401): an instantiated clone never carries copier.yml, so this
# must SKIP (exit 0), not fail -- run-evals.sh invokes this eval unconditionally
# (no `[ -f copier.yml ]` guard at the call site, unlike evals/site-toggle.sh's
# check #5), so a `fail` here turned into a permanent FAIL on every real clone.
if [ ! -f copier.yml ]; then
  echo "copier-tasks-engine-order-check: SKIP (copier.yml not found -- template-only check, #401)"
  exit 0
fi

# Extract the ordered list of quoted `_tasks:` entries (one per line, as
# authored: `  - "bash scripts/foo.sh ..."`). Restrict to the block between
# `_tasks:` and the next top-level (`_message_after_copy:`) key so an
# unrelated quoted string elsewhere in the file can't be mistaken for a task.
tasks="$(awk '
  /^_tasks:/ { in_block = 1; next }
  in_block && /^_message_after_copy:/ { in_block = 0 }
  in_block && /^[[:space:]]*- "/ { print }
' copier.yml)"
[ -n "$tasks" ] || fail "no _tasks entries found -- extraction pattern may be broken, or copier.yml's _tasks block was restructured"

# Which scripts genuinely hard-require the mif-rh-cli engine: anything that
# actually SOURCES scripts/lib/engine.sh (a `. path/to/engine.sh` or
# `source path/to/engine.sh` line), not merely mentioning the path in a
# comment (fetch-engine.sh itself references "scripts/lib/engine.sh" in its
# own header comment without sourcing it -- a plain substring grep would
# misclassify the provisioner as a requirer). Determined from the real source
# tree, not a hand-maintained list, so a future script gaining the dependency
# (or losing it) is picked up automatically.
engine_requiring="$(grep -lE '^[[:space:]]*(\.|source)[[:space:]]+.*scripts/lib/engine\.sh' scripts/*.sh 2>/dev/null | sed 's#.*/##')"
[ -n "$engine_requiring" ] || fail "no scripts found sourcing scripts/lib/engine.sh -- detection pattern may be broken"

fetch_engine_idx=-1
first_violation=""
idx=0
while IFS= read -r line; do
  idx=$((idx + 1))
  case "$line" in
    *fetch-engine.sh*)
      fetch_engine_idx="$idx"
      ;;
  esac
  # Does this task invoke one of the engine-requiring scripts?
  for s in $engine_requiring; do
    case "$line" in
      *"$s"*)
        if [ "$fetch_engine_idx" = -1 ]; then
          # fetch-engine.sh hasn't appeared yet in the list -- this task would
          # run against a possibly-uninstalled engine.
          first_violation="task #$idx invokes $s before fetch-engine.sh has run (line: $(echo "$line" | sed 's/^[[:space:]]*//'))"
        fi
        ;;
    esac
  done
  [ -n "$first_violation" ] && break
done <<<"$tasks"

[ -z "$first_violation" ] || fail "$first_violation"
[ "$fetch_engine_idx" != -1 ] || fail "fetch-engine.sh is not in the _tasks list at all"

echo "copier-tasks-engine-order-check: fetch-engine.sh (task #$fetch_engine_idx) precedes every engine-requiring task in _tasks"
exit 0
