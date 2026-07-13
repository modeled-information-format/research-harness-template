#!/usr/bin/env bash
# mif-container-nfr-verification.sh — Story #331 (Epic #275, ADR-0017).
#
# Proves the 8 EARS-notation non-functional requirements from
# docs/proposals/mif-container-format/ai-architecture-doc.md's "Non-Functional
# Requirements" section against the REAL bundled sample topic
# (example-okf-mif-knowledge-spine, 36 real findings with real relationship
# edges and 3 real ontology bindings -- the always-on mif-generic base core
# plus the market-research and trend-analysis domain packs), not just
# gate_m26-m31's
# synthetic/small fixtures -- matching feature-spec.md's own framing of this
# Story: "a round-trip eval (export -> import into a fresh instance -> export
# again) proving the manifest digest is byte-identical across the cycle, run
# against a real topic, not only a synthetic fixture."
#
# NFR-1: manifest-digest determinism (two independent builds of the same
#        topic produce a byte-identical manifestDigest).
# NFR-2: fail-closed digest verification BEFORE write -- any single mismatch
#        rejects the ENTIRE import, never a partial write.
# NFR-3: fail-closed ontology-binding version mismatch.
# NFR-4: idempotent upsert-by-@id -- re-importing the same container twice
#        never creates a duplicate finding file.
# NFR-5: an excluded subset/incremental reference target emits an explicit
#        boundaryReferences[] entry, not a silent drop.
# NFR-6: closure takes precedence over marking -- a target reachable via
#        dependency closure is included directly, never marked as a boundary.
# NFR-7: the manifest stays structurally readable by a base-profile-only
#        reader -- schema-valid against schemas/mif-container.schema.json
#        ALONE, with no domain ontology schema required, even though the
#        real topic carries 3 ontology bindings (base core + 2 domain packs).
# NFR-8: an unrecognized container profile fails closed with a named error.
#
# Also proves the Story's own headline claim: export -> import into a fresh
# instance -> export again reproduces a byte-identical manifest digest.
#
# Exit 0 = every NFR holds against the real topic. Exit 1 = one failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

EXPORT="scripts/mif-container-export.sh"
IMPORT="scripts/mif-container-import.sh"
TOPIC="example-okf-mif-knowledge-spine"
TOPIC_DIR="reports/$TOPIC"
FAIL=0
note() { printf '  mif-container-nfr-verification: %s\n' "$1"; }
pass() { note "PASS: $1"; }
bad()  { note "FAIL: $1"; FAIL=$((FAIL + 1)); }

# The real topic is bound to 2 on-demand-vendored domain packs
# (market-research, trend-analysis; ADR-0012/#224) -- not bundled, so a bare
# `git clone` needs them fetched before import's ontology-binding
# compatibility check (NFR-3, step 3) can see them as cataloged. CI already
# vendors --all-enabled before this eval runs; a local run vendors just these
# two itself (gate_m22's own established pattern for a gate that needs one
# specific domain pack), so this eval works standalone too.
if [ ! -f packs/ontologies/market-research/market-research.ontology.yaml ] \
   || [ ! -f packs/ontologies/trend-analysis/trend-analysis.ontology.yaml ]; then
  if ! command -v mif-rh-cli > /dev/null 2>&1 && [ -x bin/mif-rh-cli ]; then
    PATH="$PWD/bin:$PATH"
  fi
  if ! command -v mif-rh-cli > /dev/null 2>&1; then
    bash scripts/fetch-engine.sh > /dev/null 2>&1 || { note "FAIL: could not install the mif-rh-cli engine needed to vendor ontologies"; exit 1; }
    PATH="$PWD/bin:$PATH"
  fi
  scripts/fetch-ontology.sh market-research trend-analysis > /dev/null 2>&1 \
    || { note "FAIL: could not vendor market-research/trend-analysis (the real topic's own domain bindings)"; exit 1; }
fi

T="$(mktemp -d)" || { note "FAIL: could not create scratch dir"; exit 1; }

# research-harness-template#492: this eval is the ONLY one that mutates the
# real, shared, tracked harness.config.json/concordance.json in place (every
# other eval and verify.sh's own Milestone 8 corpus-import test operate on an
# isolated copy under their own mktemp dir instead). Nothing protected that
# mutation window before this fix -- an orphaned leftover process from a
# killed prior run (killing a parent script's PID does NOT stop its
# already-spawned children; confirmed empirically -- they keep mutating
# shared repo state in the background, unnoticed) or a second, genuinely
# concurrent session running verify.sh/run-evals.sh in the SAME worktree
# (this workspace routinely runs several sessions at once) could race this
# exact backup/mutate/restore window against a second overlapping
# invocation, producing exactly the class of transient, hard-to-reproduce
# "engine smoke test failed"/"eval suite failed" flake #492 reports (a
# later Milestone reading harness.config.json mid-mutation by the OTHER
# invocation). Guarded with the same mkdir-based lock
# scripts/mif-container-export.sh/import.sh already use for per-topic
# locking (scripts/lib/container-lock.sh) -- a repo-root lock instead of a
# per-topic one, since the resource being protected here is the shared
# harness.config.json/concordance.json pair, not one topic's directory.
. "$ROOT/scripts/lib/container-lock.sh"
LOCK_DIR="$ROOT/.eval-corpus-mutation.lock"
container_lock_acquire "$LOCK_DIR" "mif-container-nfr-verification"
acquire_rc=$?
if [ "$acquire_rc" -ne 0 ]; then
  if [ "$acquire_rc" -eq 3 ]; then
    note "FAIL: another verify.sh/eval run is already mutating harness.config.json/concordance.json (lock: $LOCK_DIR) -- wait for it to finish and retry"
  else
    note "FAIL: could not acquire the lock at $LOCK_DIR (not contention -- rc=$acquire_rc): ${CONTAINER_LOCK_LAST_ERROR:-unknown error}"
  fi
  rm -rf "$T"
  exit 1
fi
# Minimal early trap for the window between a successful acquisition and the
# full cleanup() trap being installed further down -- if the script is
# interrupted (SIGINT/TERM) or hits an early exit in that window, this at
# least releases the lock rather than leaving it held until it ages into
# staleness. `trap cleanup EXIT` below REPLACES this (traps don't stack), so
# once the full trap is installed it takes over entirely.
trap 'container_lock_release "$LOCK_DIR"; rm -rf "$T"' EXIT

# --- Guarded backup of everything this eval mutates (real corpus, global
#     concordance files, harness.config.json) -- same pattern gate_m31 uses,
#     hardened after its own Story #328 review finding (an unchecked backup
#     here would make the restore silently no-op too, corrupting real
#     tracked files on a rare I/O failure). ---
cp harness.config.json "$T/harness.config.json.orig" \
  || { note "FAIL: could not back up harness.config.json"; container_lock_release "$LOCK_DIR"; rm -rf "$T"; exit 1; }
cp reports/concordance.json "$T/concordance.json.orig" \
  || { note "FAIL: could not back up reports/concordance.json"; container_lock_release "$LOCK_DIR"; rm -rf "$T"; exit 1; }
had_sameas=0
[ -f reports/concordance-sameas-proposals.json ] && {
  had_sameas=1
  cp reports/concordance-sameas-proposals.json "$T/concordance-sameas-proposals.json.orig" \
    || { note "FAIL: could not back up concordance-sameas-proposals.json"; container_lock_release "$LOCK_DIR"; rm -rf "$T"; exit 1; }
}
# Each NFR block below that needs a synthetic destination topic gets its OWN
# id (never reused across blocks) -- register_topic() appends unconditionally
# to harness.config.json's topics[] with no dedup, so reusing one id across
# multiple register_topic() calls in the same run would leave duplicate
# .topics[] entries (found in review: confirmed by 4 independent review
# angles across the Story #328/#331 review passes).
NFR2_TOPIC="nfr-verification-nfr2"
NFR3_TOPIC="nfr-verification-nfr3"
NFR8_TOPIC="nfr-verification-nfr8"
DUP_TOPIC="nfr-verification-dup-check"
ROUNDTRIP_TOPIC="nfr-verification-roundtrip"
ALL_SYNTHETIC_TOPICS=("$NFR2_TOPIC" "$NFR3_TOPIC" "$NFR8_TOPIC" "$DUP_TOPIC" "$ROUNDTRIP_TOPIC")

cleanup() {
  local restore_failed=0
  cp "$T/harness.config.json.orig" harness.config.json \
    || { note "FAIL: could not restore harness.config.json from backup -- check $T/harness.config.json.orig manually"; restore_failed=1; }
  cp "$T/concordance.json.orig" reports/concordance.json \
    || { note "FAIL: could not restore reports/concordance.json from backup -- check $T/concordance.json.orig manually"; restore_failed=1; }
  if [ "$had_sameas" -eq 1 ]; then
    cp "$T/concordance-sameas-proposals.json.orig" reports/concordance-sameas-proposals.json \
      || { note "FAIL: could not restore reports/concordance-sameas-proposals.json from backup -- check $T/concordance-sameas-proposals.json.orig manually"; restore_failed=1; }
  else
    rm -f reports/concordance-sameas-proposals.json
  fi
  for t in "${ALL_SYNTHETIC_TOPICS[@]}"; do
    rm -rf "reports/$t"
  done
  # On a restore failure, the backups under $T are exactly what an operator
  # needs to recover manually -- deleting $T here (as an earlier version of
  # this fix did unconditionally) would destroy the only copies of the
  # pre-mutation content the FAIL message above just told them to go check.
  if [ "$restore_failed" -eq 0 ]; then
    rm -rf "$T"
  else
    note "preserving $T (contains the pre-mutation backups) for manual recovery"
  fi
  # Release last: a second invocation denied by the lock must never see it
  # freed before harness.config.json/concordance.json are actually restored.
  container_lock_release "$LOCK_DIR"
  # A restore failure must never be swallowed by whatever exit code the main
  # script body was already about to report (e.g. every NFR passing, exit
  # 0) -- that would report success while leaving the repo in a corrupted,
  # dirty state. `exit` inside an EXIT trap overrides the pending exit code.
  [ "$restore_failed" -eq 0 ] || exit 1
}
trap cleanup EXIT

register_topic() {
  local id="$1"
  jq --arg id "$id" '.topics += [{id: $id, title: "NFR verification synthetic instance", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$T/harness.config.json.next" \
    && mv "$T/harness.config.json.next" harness.config.json \
    || { note "FAIL: could not register synthetic topic $id in harness.config.json"; exit 1; }
  mkdir -p "reports/$id/findings"
}

# =====================================================================
# NFR-1: manifest-digest determinism -- two independent builds of the
# same real topic produce a byte-identical manifestDigest.
# =====================================================================
"$EXPORT" "$TOPIC" "$T/build-a" > /dev/null 2>&1 || { bad "NFR-1: first build of the real topic failed"; }
"$EXPORT" "$TOPIC" "$T/build-b" > /dev/null 2>&1 || { bad "NFR-1: second build of the real topic failed"; }
digest_a="$(jq -r '.manifestDigest' "$T/build-a/mif-package.json" 2>/dev/null)"
digest_b="$(jq -r '.manifestDigest' "$T/build-b/mif-package.json" 2>/dev/null)"
if [ -n "$digest_a" ] && [ "$digest_a" = "$digest_b" ]; then
  pass "NFR-1 manifest-digest determinism ($digest_a)"
else
  bad "NFR-1 manifest-digest determinism (a=$digest_a b=$digest_b)"
fi

# Every NFR-2..8 check and the round-trip claim below depend on build-a being
# a real, valid fixture. If NFR-1's own build silently produced a broken or
# missing manifest, letting the script continue would make every later check
# pass or fail for the wrong reason (proving nothing about its own NFR). Fail
# closed here instead of limping forward on a broken fixture.
if [ ! -s "$T/build-a/mif-package.json" ] || [ -z "$digest_a" ]; then
  bad "build-a fixture is missing or invalid -- aborting, no later NFR check can be trusted against it"
  exit 1
fi

# =====================================================================
# NFR-2: fail-closed digest verification BEFORE write -- corrupting one
# resource's bytes (without updating its manifest-declared digest)
# rejects the ENTIRE import into a fresh topic, nothing written.
# =====================================================================
register_topic "$NFR2_TOPIC"
cp -r "$T/build-a" "$T/build-a-corrupt"
corrupt_finding="$(find "$T/build-a-corrupt/findings" -maxdepth 1 -name '*.json' | LC_ALL=C sort | head -1)"
if [ -z "$corrupt_finding" ]; then
  bad "NFR-2: build-a-corrupt has no finding files to corrupt -- fixture is empty, cannot test digest rejection"
else
  printf '\n' >> "$corrupt_finding"
  "$IMPORT" "$T/build-a-corrupt" "$NFR2_TOPIC" > /dev/null 2>&1
  rc_nfr2=$?
  count_nfr2="$(find "reports/$NFR2_TOPIC/findings" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc_nfr2" -ne 0 ] && [ "$count_nfr2" = "0" ]; then
    pass "NFR-2 fail-closed digest rejection (rc=$rc_nfr2, nothing written)"
  else
    bad "NFR-2 fail-closed digest rejection (rc=$rc_nfr2, count=$count_nfr2)"
  fi
fi
rm -rf "reports/$NFR2_TOPIC"

# =====================================================================
# NFR-3: fail-closed ontology-binding version mismatch -- a bogus
# non-cataloged version for a real bound pack rejects the entire import.
# =====================================================================
register_topic "$NFR3_TOPIC"
# Target the market-research pack explicitly by packId, not by array index --
# jq's `unique`-driven ontologyBindings ordering is incidental (alphabetical),
# not a contract, so an index-0 assumption would silently start testing a
# different pack's rejection path if the real topic's binding set ever grows
# a pack that sorts earlier.
if ! jq -e '.ontologyBindings[] | select(.packId == "market-research")' "$T/build-a/mif-package.json" > /dev/null 2>&1; then
  bad "NFR-3: build-a's manifest has no market-research ontology binding to bump -- cannot test rejection"
else
  jq '(.ontologyBindings[] | select(.packId == "market-research") | .version) = "99.99.99"' \
    "$T/build-a/mif-package.json" > "$T/build-a/mif-package.json.bumped"
  mkdir -p "$T/build-a-badbinding/findings"
  cp -r "$T/build-a/findings/." "$T/build-a-badbinding/findings/"
  cp "$T/build-a/ontology-map.json" "$T/build-a-badbinding/ontology-map.json"
  cp "$T/build-a/mif-package.json.bumped" "$T/build-a-badbinding/mif-package.json"
  "$IMPORT" "$T/build-a-badbinding" "$NFR3_TOPIC" > /dev/null 2>&1
  rc_nfr3=$?
  count_nfr3="$(find "reports/$NFR3_TOPIC/findings" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc_nfr3" -ne 0 ] && [ "$count_nfr3" = "0" ]; then
    pass "NFR-3 fail-closed ontology-binding rejection (rc=$rc_nfr3, nothing written)"
  else
    bad "NFR-3 fail-closed ontology-binding rejection (rc=$rc_nfr3, count=$count_nfr3)"
  fi
fi
rm -rf "reports/$NFR3_TOPIC"

# =====================================================================
# NFR-4: idempotent upsert-by-@id -- re-importing the SAME container
# twice into the same fresh topic never creates a duplicate file.
# =====================================================================
register_topic "$DUP_TOPIC"
"$IMPORT" "$T/build-a" "$DUP_TOPIC" > /dev/null 2>&1
rc_first="$?"
count_after_first="$(find "reports/$DUP_TOPIC/findings" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
"$IMPORT" "$T/build-a" "$DUP_TOPIC" > /dev/null 2>&1
rc_second="$?"
count_after_second="$(find "reports/$DUP_TOPIC/findings" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rc_first" -eq 0 ] && [ "$rc_second" -eq 0 ] && [ "$count_after_first" = "$count_after_second" ] && [ "$count_after_first" != "0" ]; then
  pass "NFR-4 idempotent upsert-by-@id (count stayed $count_after_first across two imports)"
else
  bad "NFR-4 idempotent upsert-by-@id (rc1=$rc_first rc2=$rc_second count1=$count_after_first count2=$count_after_second)"
fi

# =====================================================================
# NFR-5 / NFR-6: boundary-marker emission and closure precedence, using
# a REAL relationship edge from the bundled topic:
#   landscape-frictionless-data-packages -> landscape-okf-google-open-knowledge-format
# =====================================================================
SRC_ID="urn:mif:concept:harness/$TOPIC:landscape-frictionless-data-packages"
TGT_ID="urn:mif:concept:harness/$TOPIC:landscape-okf-google-open-knowledge-format"
printf '["%s"]\n' "$SRC_ID" > "$T/nfr56-subset-ids.json"
GRAPH="$T/nfr56-graph.json"
if ! bash scripts/build-graph.sh "$TOPIC_DIR/findings" "$GRAPH" > /dev/null 2>&1; then
  bad "NFR-5/NFR-6: build-graph.sh failed -- cannot test boundary-marker/closure behavior without a graph"
else

# NFR-5: without --closure, the excluded target must appear as a named
# boundary reference, not a silent drop.
if ! scripts/mif-container-resolve-scope.sh "$GRAPH" "$T/nfr56-subset-ids.json" > "$T/nfr5-result.json" 2>/dev/null; then
  bad "NFR-5 boundary-marker emission (mif-container-resolve-scope.sh failed, not a boundary-marking regression)"
else
  boundary_has_target="$(jq --arg t "$TGT_ID" '[.boundaryReferences[]? | select(.target == $t)] | length' "$T/nfr5-result.json" 2>/dev/null)"
  if [ "${boundary_has_target:-0}" -gt 0 ]; then
    pass "NFR-5 boundary-marker emission (real edge to $TGT_ID marked, not dropped)"
  else
    bad "NFR-5 boundary-marker emission (target not found in boundaryReferences)"
  fi
fi

# NFR-6: WITH --closure, the same target is included directly and must
# NOT appear as a boundary reference.
if ! scripts/mif-container-resolve-scope.sh "$GRAPH" "$T/nfr56-subset-ids.json" --closure > "$T/nfr6-result.json" 2>/dev/null; then
  bad "NFR-6 closure precedence (mif-container-resolve-scope.sh --closure failed, not a closure-precedence regression)"
else
  resource_has_target="$(jq --arg t "$TGT_ID" '[.resourceIds[]? | select(. == $t)] | length' "$T/nfr6-result.json" 2>/dev/null)"
  boundary_has_target_closure="$(jq --arg t "$TGT_ID" '[.boundaryReferences[]? | select(.target == $t)] | length' "$T/nfr6-result.json" 2>/dev/null)"
  if [ "${resource_has_target:-0}" -gt 0 ] && [ "${boundary_has_target_closure:-1}" = "0" ]; then
    pass "NFR-6 closure precedence (target included directly, not marked)"
  else
    bad "NFR-6 closure precedence (resource_has_target=$resource_has_target boundary_has_target=$boundary_has_target_closure)"
  fi
fi
fi

# =====================================================================
# NFR-7: the manifest for a topic bound to N (here: 3) ontology bindings
# (the always-on mif-generic base core plus 2 domain packs) stays
# structurally readable by a base-profile-only reader -- schema-valid
# against schemas/mif-container.schema.json ALONE, no domain ontology
# schema required.
# =====================================================================
binding_count="$(jq '.ontologyBindings | length' "$T/build-a/mif-package.json" 2>/dev/null)"
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/mif-container.schema.json -d "$T/build-a/mif-package.json" > /dev/null 2>&1
rc_nfr7=$?
# The real topic carries exactly 3 ontologyBindings entries (mif-generic, the
# always-on base/generic core, plus the market-research and trend-analysis
# domain packs) -- assert this floor (-ge 3) rather than an under-specified
# -ge 2 that wouldn't actually prove the real topic's bindings were
# exercised. "bindings" (not "domain bindings") in the message below because
# one of the 3 is the base core, not a domain pack.
if [ "$rc_nfr7" -eq 0 ] && [ "${binding_count:-0}" -ge 3 ]; then
  pass "NFR-7 base-profile-only schema readability ($binding_count ontology bindings incl. domain packs, no domain schema needed)"
else
  bad "NFR-7 base-profile-only schema readability (rc=$rc_nfr7, bindings=$binding_count)"
fi

# =====================================================================
# NFR-8: an unrecognized container profile fails closed with a named
# "unrecognized container profile" error, not best-effort parsing.
# =====================================================================
register_topic "$NFR8_TOPIC"
mkdir -p "$T/build-a-badprofile/findings"
cp -r "$T/build-a/findings/." "$T/build-a-badprofile/findings/"
cp "$T/build-a/ontology-map.json" "$T/build-a-badprofile/ontology-map.json"
jq '.profile = "https://example.invalid/schema/not-a-real-profile/v99"' "$T/build-a/mif-package.json" > "$T/build-a-badprofile/mif-package.json"
nfr8_output="$("$IMPORT" "$T/build-a-badprofile" "$NFR8_TOPIC" 2>&1)"
rc_nfr8=$?
if [ "$rc_nfr8" -ne 0 ] && printf '%s' "$nfr8_output" | grep -q "unrecognized container profile"; then
  pass "NFR-8 fail-closed on unrecognized profile (named error, not best-effort parsing)"
else
  bad "NFR-8 fail-closed on unrecognized profile (rc=$rc_nfr8, output did not name the error)"
fi
rm -rf "reports/$NFR8_TOPIC"

# =====================================================================
# Story #331 headline claim: export -> import into a fresh instance ->
# export again reproduces a byte-identical manifest digest.
#
# research-harness-template#437: the manifest now also carries the topic's
# own deliverables, including README.md -- which import's own step 5
# (build-topic-readme.sh) deterministically REBUILDS keyed to the
# DESTINATION topic's own registered identity (title, namespace), not a
# verbatim copy of the source. A byte-identical MANIFEST digest across a
# round-trip into a topic with a different registered title/namespace is
# therefore no longer the right claim for the whole manifest -- this is
# intentional, correct behavior (README must reflect where it actually
# lives, not lie about its origin), not a regression. The invariant this
# eval actually cares about -- every piece of real CONTENT survives the
# round-trip byte-for-byte -- still holds and is what is checked here:
# every non-readme resource's path+digest is unchanged.
# =====================================================================
register_topic "$ROUNDTRIP_TOPIC"
"$IMPORT" "$T/build-a" "$ROUNDTRIP_TOPIC" > /dev/null 2>&1
rc_roundtrip_import=$?
"$EXPORT" "$ROUNDTRIP_TOPIC" "$T/build-c" > /dev/null 2>&1
rc_roundtrip_export=$?
# path+digest PAIRS, not just the digest multiset (Copilot review, PR #491):
# a bare digest-set comparison would false-green if a resource were dropped
# and a different one added whose digest happened to coincide (or if any
# two resources ever shared a digest) -- resources[].path never encodes the
# topic id (paths are "findings/<slug>.json", "reports/<name>.md",
# "goal.json", ...), so a real round-trip's paths are stable across a
# destination with a different registered title/namespace, same as the
# digests themselves.
content_pairs_a="$(jq -r '.resources[] | select(.mifType != "readme") | "\(.path)\t\(.digest)"' "$T/build-a/mif-package.json" 2>/dev/null | LC_ALL=C sort)"
content_pairs_c="$(jq -r '.resources[] | select(.mifType != "readme") | "\(.path)\t\(.digest)"' "$T/build-c/mif-package.json" 2>/dev/null | LC_ALL=C sort)"
if [ "$rc_roundtrip_import" -eq 0 ] && [ "$rc_roundtrip_export" -eq 0 ] \
   && [ -n "$content_pairs_a" ] && [ "$content_pairs_a" = "$content_pairs_c" ]; then
  pass "round-trip content-digest byte-identity (export -> import into fresh instance -> export again: every non-readme resource's path+digest unchanged; README.md is expected to differ, since it deterministically reflects the destination topic's own identity)"
else
  bad "round-trip content-digest byte-identity (rc_import=$rc_roundtrip_import rc_export=$rc_roundtrip_export match=$([ "$content_pairs_a" = "$content_pairs_c" ] && echo yes || echo no))"
fi

if [ -z "$(git status --porcelain "$TOPIC_DIR" 2>/dev/null)" ]; then
  pass "the real topic's own reports/<topic>/ was never touched by this eval"
else
  bad "the real topic's reports/<topic>/ was left dirty"
  git status --porcelain "$TOPIC_DIR" >&2
fi

if [ "$FAIL" -eq 0 ]; then
  note "all 8 NFRs + the round-trip claim hold against the real topic ($TOPIC)"
  exit 0
else
  note "$FAIL check(s) failed"
  exit 1
fi
