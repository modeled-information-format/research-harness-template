#!/usr/bin/env bash
# stdin-detach.sh — regression eval for the wrap-source stdin hang
# (research-harness-template#531). An explicit `--content ""` used to be
# treated as "content not provided", silently falling through to the
# engine's stdin path, which blocks forever in read() whenever stdin is an
# open pipe that never EOFs — exactly what backgrounded invocations of
# verify.sh/run-evals.sh hand every descendant. The smoke test's
# empty-content refusal case then hung the entire gate suite.
#
# Covers, each under a deliberately never-EOF stdin (< <(sleep 60)):
#   1. wrap-source.sh --content "" exits promptly with a refusal (never
#      blocks reading stdin; exit code is the engine's refusal, not 124).
#   2. The full engine smoke test completes promptly (its own stdin is
#      detached, so no child can inherit the poisoned pipe).
#
# Exit 0 = both hold. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  stdin-detach: %s\n' "$1"; }

# Case 1: explicit empty content is forwarded and refused, never a stdin read.
timeout 15 bash scripts/wrap-source.sh --url "https://example.com/doc" \
  --content-type "text/html" --namespace "harness/eval" --slug "empty" \
  --out "$TMP/empty.json" --content "" < <(sleep 60) >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 124 ]; then
  note "wrap-source --content \"\" blocked on stdin (timed out) — #531 regression"
  fail=1
elif [ "$RC" -eq 0 ]; then
  note "empty content was accepted (must be refused)"
  fail=1
fi

# Case 2: the smoke test is immune to a poisoned inherited stdin.
if ! timeout 60 bash evals/smoke-test.sh < <(sleep 90) >/dev/null 2>&1; then
  note "smoke test failed or hung under a never-EOF stdin"
  fail=1
fi

[ "$fail" -eq 0 ] && note "no gate-path child blocks on inherited stdin"
exit "$fail"
