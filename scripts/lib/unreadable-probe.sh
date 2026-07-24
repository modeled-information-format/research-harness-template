#!/usr/bin/env bash
# unreadable-probe.sh — classify the outcome of gate_m27's 27f "unreadable file
# fails closed" probe (research-harness-template#777).
#
# `chmod 000` does not deny root -- or any other DAC_OVERRIDE-capable process,
# e.g. a root-uid Docker/devcontainer `verify.sh` run -- the ability to read a
# file. Asserting the fail-closed behavior without checking that first means
# the assertion's premise silently doesn't hold: a working, unmodified digest
# script gets marked broken (root reads the file fine, gets a real digest,
# rc=0) even though the code path under test was never actually exercised.
#
# This is pure classification logic (no filesystem access, no privilege
# dependency) so it can be unit-tested deterministically regardless of which
# user runs the test suite -- see evals/gate-m27-root-safe-unreadable-check.sh.

# m27_classify_unreadable_probe <bypassed 0|1> <rc> <out>
#   bypassed=1  — the current process could still read the file after
#                 chmod 000 (root / DAC override): the fail-closed premise
#                 does not hold, so no ok/bad verdict can be drawn.
#   bypassed=0  — the file was genuinely unreadable; rc/out are the real
#                 digest-script outcome to judge.
# Prints exactly one of: skip | ok | bad
m27_classify_unreadable_probe() {
  local bypassed="$1" rc="$2" out="$3"
  if [ "$bypassed" = "1" ]; then
    echo "skip"
  elif [ "$rc" -ne 0 ] && [ "$out" != "sha256:" ]; then
    echo "ok"
  else
    echo "bad"
  fi
}
