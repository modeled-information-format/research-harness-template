#!/usr/bin/env bash
# import-check.sh — deterministic eval for the research-import DryRun/Review/
# Apply pipeline (research-harness-template#592, Epic #548, following #590's
# vendoring and #591's docs).
#
# Mirrors the pivot-check.sh / add-dimensions-check.sh precedent: hermetic
# where the module's own logic can express it, REAL script invocation /
# structural greps where behavior is delegated or inherently model-driven —
# stated explicitly below, never faked as deterministic. Per #592's own
# acceptance criteria ("All assertions run against the real
# scripts/mif-container-import.sh gate ... not a mocked or stubbed
# substitute"), every DryRun and Apply agent() call in every case below is
# stubbed to invoke the REAL scripts/mif-container-import.sh — the module's
# own delegation target — and report back what that real invocation actually
# did (real exit status, real stderr, real on-disk files), never a
# hand-fabricated pass/fail verdict. Only the Review phase (a genuine sonnet
# @id-collision / provenance / scope-fit judgment) and research-falsify's
# skeptic voting are stubbed with a canned decision — that is a live model
# call this eval cannot reproduce deterministically, said plainly, not faked.
#
#   A. Structural proof: the DryRun phase's prompt invokes the REAL
#      `bash scripts/mif-container-import.sh "${CDIR}" "${TOPIC}" --dry-run`
#      (WITH --dry-run) and the Apply phase's prompt invokes the identical
#      script WITHOUT --dry-run — extracted by phase() marker span (never a
#      header comment: the module's own header ALSO mentions the script, so
#      a naive whole-file grep would pass even if a phase's prompt regressed
#      to a freehand check). scripts/mif-container-import.sh confirmed to
#      exist on disk (a renamed/moved script would go stale here, not just
#      in prose).
#
#   B. DryRun-reject: a REAL fixture container — built by fully exporting a
#      FRESH, synthetic, from-scratch source topic this eval registers and
#      populates itself (never the org's real bundled sample topic: that
#      topic's own export unconditionally drags in its ~11 rendered
#      deliverable-genre reports regardless of subset scope — confirmed
#      empirically while writing this eval, see the note below Part D —
#      which then fail mif-project.sh's gate against an unrelated fresh
#      destination topic; a synthetic from-scratch source topic has no
#      deliverables at all, so this class of failure cannot occur) — with
#      one resource's bytes corrupted after its digest was declared (same
#      technique as mif-container-nfr-verification.sh's own NFR-2, applied
#      here specifically through the --dry-run code path, which that eval
#      does not cover). research-import.js's DryRun-phase agent() call is
#      stubbed to invoke the REAL scripts/mif-container-import.sh --dry-run
#      and report its real exit status/output. Asserts: the module
#      short-circuits with {ok:false, stage:'dry-run'}; Review/Apply are
#      NEVER called (asserted from the driver's own call log, stubbed to
#      throw if invoked); and NOTHING lands under the destination topic's
#      findings/ — a real, empty directory, since step 2's digest check runs
#      and fails BEFORE the --dry-run/apply branch is even reached, so this
#      holds independent of the flag.
#
#   C. Review NO-GO: the SAME real DryRun invocation, this time against an
#      uncorrupted, valid container (passes for real) — but the Review
#      phase's agent() call is stubbed to return proceed:false (a genuine
#      sonnet scope-fit/collision/provenance judgment this eval cannot
#      reproduce deterministically — stated plainly, not faked). Apply is
#      asserted NEVER called (stubbed to throw if invoked), and since
#      --dry-run never writes regardless of outcome, the destination topic's
#      findings/ is asserted empty here too.
#
#   D. Apply-success + needsGating partition for BOTH trust settings: the
#      SAME synthetic source topic carries exactly 2 hand-authored findings
#      — one with a REAL foreign verification block (verdict: survived,
#      verdict_basis, attempted_at all set, as a finding gated by another
#      harness instance would carry) and one with scripts/falsify.sh's OWN
#      documented not-yet-tested placeholder (verdict: inconclusive,
#      verdict_basis set, deliberately NO attempted_at — falsify.sh's own
#      header: "A finding with no fixture entry is recorded as a PLACEHOLDER
#      `inconclusive` ... WITHOUT `attempted_at`" — this is the real,
#      documented, schema-valid shape of "genuinely unverified" this system
#      actually uses; findings.schema.json requires verdict+verdict_basis
#      unconditionally, attempted_at is what distinguishes "never gated"
#      from "gated", exactly what research-falsify.js's own Enumerate phase
#      already keys on). The Apply-phase agent() call is stubbed to invoke
#      the REAL scripts/mif-container-import.sh (no --dry-run) and then
#      enumerate the REAL on-disk written finding files for real
#      extensions.harness.verification.attempted_at presence/absence — never
#      a fabricated applied/unverified/withForeignVerdicts list. Driven
#      TWICE against the SAME real container/topic (the second real
#      invocation of the script is a genuine, real, idempotent no-op upsert
#      — SKIPPED, not a duplicate write, per the script's own upsert-by-
#      digest logic) — once per trustImportedVerdicts setting — asserting
#      the needsGating/trustedForeignVerdicts partition is correct for both.
#
#   E. Falsify regate hookup: a structural cross-check (research-import.js's
#      own documented call-site note `scope: { ids: needsGating },
#      regate: true`; research-falsify.js's documented scope shape and its
#      REGATE_SCOPE_QUALIFIES check), then a REAL end-to-end run of
#      research-falsify.js fed the REAL needsGating produced by D's
#      trustImportedVerdicts:false case, proving the two independently-
#      vendored modules' interface boundary actually holds without tripping
#      the "regate=true requires an explicit scope" guard error — mirroring
#      #588's pivot->falsify interface fixture (research-falsify.js's own
#      Enumerate-phase agent() call is stubbed to an empty working set here,
#      same as that precedent: the point of this fixture is the parameter
#      boundary, not a live falsification round, which falsify-verdict-
#      merge.sh's own eval already covers).
#
# Real repo-root mutation, guarded: research-import.js has no harnessDir
# parameterization of its own for scripts/mif-container-import.sh — that
# script always resolves ROOT from its own file location and operates
# against THIS repo's real harness.config.json/reports/, exactly like every
# other caller (mif-container-export.sh, mif-container-nfr-verification.sh).
# Every synthetic topic registered below is scoped to this eval's own unique
# ids; harness.config.json/reports/concordance.json are backed up and
# restored via a cp-based (never git-based) snapshot, guarded by the SAME
# $ROOT/.eval-corpus-mutation.lock mkdir-based lock
# mif-container-nfr-verification.sh already uses for this exact shared
# real-corpus-mutation window — a git-based revert would clobber a
# genuinely concurrent session's own uncommitted state in this shared
# workspace (CLAUDE.local.md's own documented failure mode); a cp-based
# restore only ever reverts what THIS eval itself added.
#
# Hermetic w.r.t. the ontology engine: the fixture container is built
# subset-only from finding(s) resolving to the always-on mif-generic base
# core (never a vendored domain pack), so this eval needs no mif-rh-cli
# engine and no `scripts/fetch-ontology.sh` vendoring step, unlike
# mif-container-nfr-verification.sh's own real-topic round-trip (which
# exercises 2 vendored domain packs deliberately, a different, complementary
# concern).
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool/fixture is missing.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

WF=".claude/workflows/research-import.js"
FALSIFY_WF=".claude/workflows/research-falsify.js"
IMPORT_SCRIPT="scripts/mif-container-import.sh"
EXPORT_SCRIPT="scripts/mif-container-export.sh"
DIGEST_SCRIPT="scripts/mif-container-digest.sh"

fail=0
note() { printf '  import-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
command -v ajv >/dev/null 2>&1 || { note "ajv is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-import workflow must ship (Epic #548, Task #590)"; exit 2; }
[ -f "$FALSIFY_WF" ] || { note "$FALSIFY_WF not found — the vendored research-falsify workflow must ship (Epic #541, Task #560)"; exit 2; }
[ -f "$IMPORT_SCRIPT" ] || { note "$IMPORT_SCRIPT not found — the fail-closed import gate this module delegates to must exist (ADR-0017)"; exit 2; }
[ -f "$EXPORT_SCRIPT" ] || { note "$EXPORT_SCRIPT not found — needed to build a REAL fixture container from a synthetic source topic"; exit 2; }
[ -f "$DIGEST_SCRIPT" ] || { note "$DIGEST_SCRIPT not found — needed to compute a real resource digest for the digest-rejection fixture"; exit 2; }

TMP="$(mktemp -d)" || { note "could not create scratch dir"; exit 1; }

# ============================================================================
# Guarded repo-root mutation: same mkdir-based lock + cp-based backup/restore
# idiom as mif-container-nfr-verification.sh, reused verbatim (not
# reinvented) since both evals mutate the exact same shared real-corpus
# state (harness.config.json, reports/concordance.json).
# ============================================================================
# shellcheck source=scripts/lib/container-lock.sh
. "$ROOT/scripts/lib/container-lock.sh"
LOCK_DIR="$ROOT/.eval-corpus-mutation.lock"
lock_stderr_file="$(mktemp)"
container_lock_acquire "$LOCK_DIR" "import-check" 2>"$lock_stderr_file"
acquire_rc=$?
lock_stderr="$(cat "$lock_stderr_file" 2>/dev/null)"
rm -f "$lock_stderr_file"
if [ "$acquire_rc" -ne 0 ]; then
  if [ "$acquire_rc" -eq 3 ]; then
    holder="$(cat "$LOCK_DIR/owner" 2>/dev/null || echo unknown)"
    note "another verify.sh/eval run is already mutating harness.config.json/concordance.json (lock: $LOCK_DIR, held by '$holder') — wait for it to finish and retry"
  else
    note "could not acquire the lock at $LOCK_DIR (not contention — rc=$acquire_rc): ${CONTAINER_LOCK_LAST_ERROR:-unknown error}"
    [ -n "$lock_stderr" ] && printf '%s\n' "$lock_stderr" >&2
  fi
  rm -rf "$TMP"
  exit 1
fi
[ -n "$lock_stderr" ] && printf '%s\n' "$lock_stderr" >&2
trap 'container_lock_release "$LOCK_DIR"; rm -rf "$TMP"' EXIT

cp harness.config.json "$TMP/harness.config.json.orig" \
  || { note "could not back up harness.config.json"; exit 1; }
cp reports/concordance.json "$TMP/concordance.json.orig" \
  || { note "could not back up reports/concordance.json"; exit 1; }
had_sameas=0
[ -f reports/concordance-sameas-proposals.json ] && {
  had_sameas=1
  cp reports/concordance-sameas-proposals.json "$TMP/concordance-sameas-proposals.json.orig" \
    || { note "could not back up concordance-sameas-proposals.json"; exit 1; }
}

SRC_TOPIC="import-check-src"
DRYRUN_TOPIC="import-check-dryrun-reject"
REVIEW_TOPIC="import-check-review-nogo"
APPLY_TOPIC="import-check-apply-success"
ALL_SYNTHETIC_TOPICS=("$SRC_TOPIC" "$DRYRUN_TOPIC" "$REVIEW_TOPIC" "$APPLY_TOPIC")

cleanup() {
  local restore_failed=0
  cp "$TMP/harness.config.json.orig" harness.config.json \
    || { note "could not restore harness.config.json from backup — check $TMP/harness.config.json.orig manually"; restore_failed=1; }
  cp "$TMP/concordance.json.orig" reports/concordance.json \
    || { note "could not restore reports/concordance.json from backup — check $TMP/concordance.json.orig manually"; restore_failed=1; }
  if [ "$had_sameas" -eq 1 ]; then
    cp "$TMP/concordance-sameas-proposals.json.orig" reports/concordance-sameas-proposals.json \
      || { note "could not restore reports/concordance-sameas-proposals.json from backup"; restore_failed=1; }
  else
    rm -f reports/concordance-sameas-proposals.json
  fi
  for t in "${ALL_SYNTHETIC_TOPICS[@]}"; do
    rm -rf "reports/$t"
  done
  if [ "$restore_failed" -eq 0 ]; then
    rm -rf "$TMP"
  else
    note "preserving $TMP (contains the pre-mutation backups) for manual recovery"
  fi
  container_lock_release "$LOCK_DIR"
  [ "$restore_failed" -eq 0 ] || exit 1
}
trap cleanup EXIT

register_topic() {
  local id="$1"
  jq --arg id "$id" '.topics += [{id: $id, title: "import-check eval synthetic instance", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$TMP/harness.config.json.next" \
    && mv "$TMP/harness.config.json.next" harness.config.json \
    || { note "could not register synthetic topic $id in harness.config.json"; exit 1; }
  mkdir -p "reports/$id/findings"
}
register_topic "$SRC_TOPIC"
register_topic "$DRYRUN_TOPIC"
register_topic "$REVIEW_TOPIC"
register_topic "$APPLY_TOPIC"

# ============================================================================
# Build a REAL base container: FULLY exported (never a subset — there is
# nothing to subset) from a FRESH, synthetic, from-scratch source topic this
# eval registers and populates itself, carrying exactly 2 hand-authored
# findings and nothing else (no deliverables of any kind — no report/goal/
# README/artifact files — so mif-container-export.sh's own step 2b, which
# unconditionally packages a topic's deliverables regardless of subset
# scope, has nothing to sweep in). This deliberately avoids reusing the
# org's real bundled sample topic (example-okf-mif-knowledge-spine): an
# earlier version of this eval subset-exported 2 findings from THAT topic
# and hit a REAL failure — its ~11 rendered deliverable-genre report files
# (report-academic.md, report-engineering.md, ...) got pulled into the
# export regardless of the --subset scope, and then failed
# mif-project.sh's schema/citation-integrity gate once imported into an
# unrelated, empty destination topic (those reports were rendered against
# THAT topic's own goal/citation context, which doesn't exist at the fresh
# destination). A synthetic source topic sidesteps the whole failure class.
#
#   FOREIGN_ID: verdict: survived, verdict_basis + attempted_at all set —
#     a real foreign verification block, as a finding gated by ANOTHER
#     harness instance would carry.
#   UNVERIFIED_ID: verdict: inconclusive, verdict_basis set, NO
#     attempted_at — scripts/falsify.sh's OWN documented not-yet-tested
#     placeholder ("A finding with no fixture entry is recorded as a
#     PLACEHOLDER `inconclusive` ... WITHOUT `attempted_at`"), the real,
#     schema-valid shape of "genuinely unverified" this system actually
#     uses (findings.schema.json requires verdict+verdict_basis
#     unconditionally; attempted_at is what distinguishes never-gated from
#     gated, exactly what research-falsify.js's own Enumerate phase keys
#     on).
# ============================================================================
FOREIGN_ID="urn:mif:concept:harness/$SRC_TOPIC:foreign-0001"
UNVERIFIED_ID="urn:mif:concept:harness/$SRC_TOPIC:unverified-0001"
python3 - "$ROOT/reports/$SRC_TOPIC/findings/foreign.json" "$FOREIGN_ID" "$SRC_TOPIC" <<'PY'
import json, sys
out_path, fid, topic = sys.argv[1], sys.argv[2], sys.argv[3]
finding = {
    "@context": "https://mif-spec.dev/schema/context.jsonld",
    "@type": "Concept",
    "@id": fid,
    "conceptType": "semantic",
    "namespace": f"harness/{topic}",
    "title": "import-check eval fixture: a finding with a real foreign verification block",
    "content": "Fixture content standing in for a finding gated by another harness instance's own adversarial gate, exported and re-imported here (research-harness-template#592).",
    "summary": "Fixture finding carrying a foreign verification block for the import-check eval.",
    "created": "2026-06-01T00:00:00Z",
    "modified": "2026-06-01T00:00:00Z",
    "temporal": {"@type": "TemporalMetadata", "validFrom": "2026-06-01T00:00:00Z"},
    "tags": ["import-check-eval"],
    "provenance": {"@type": "Provenance", "sourceType": "agent_inferred", "confidence": 0.8, "trustLevel": "high_confidence"},
    "citations": [{
        "@type": "Citation", "citationType": "documentation", "citationRole": "supports",
        "title": "import-check eval fixture citation", "url": "https://example.com/import-check-eval-foreign",
        "accessed": "2026-06-01",
    }],
    "extensions": {"harness": {
        "dimension": "technical",
        "verification": {
            "verdict": "survived",
            "verdict_basis": "Foreign instance's own adversarial gate found no credible disconfirming evidence.",
            "attempted_at": "2026-06-01T00:30:00Z",
        },
    }},
}
json.dump(finding, open(out_path, "w"), indent=2)
PY
python3 - "$ROOT/reports/$SRC_TOPIC/findings/unverified.json" "$UNVERIFIED_ID" "$SRC_TOPIC" <<'PY'
import json, sys
out_path, fid, topic = sys.argv[1], sys.argv[2], sys.argv[3]
finding = {
    "@context": "https://mif-spec.dev/schema/context.jsonld",
    "@type": "Concept",
    "@id": fid,
    "conceptType": "semantic",
    "namespace": f"harness/{topic}",
    "title": "import-check eval fixture: a genuinely unverified finding (falsify.sh's own not-yet-tested placeholder)",
    "content": "Fixture content standing in for a finding never yet run through any harness instance's falsification gate — scripts/falsify.sh's own documented placeholder shape (verdict: inconclusive, no attempted_at) for research-harness-template#592.",
    "summary": "Fixture finding carrying no attempted_at for the import-check eval.",
    "created": "2026-06-01T00:00:00Z",
    "modified": "2026-06-01T00:00:00Z",
    "temporal": {"@type": "TemporalMetadata", "validFrom": "2026-06-01T00:00:00Z"},
    "tags": ["import-check-eval"],
    "provenance": {"@type": "Provenance", "sourceType": "agent_inferred", "confidence": 0.8, "trustLevel": "high_confidence"},
    "citations": [{
        "@type": "Citation", "citationType": "documentation", "citationRole": "supports",
        "title": "import-check eval fixture citation", "url": "https://example.com/import-check-eval-unverified",
        "accessed": "2026-06-01",
    }],
    "extensions": {"harness": {
        "dimension": "technical",
        "verification": {
            "verdict": "inconclusive",
            "verdict_basis": "not adversarially tested (scripts/falsify.sh's own documented placeholder shape)",
        },
    }},
}
json.dump(finding, open(out_path, "w"), indent=2)
PY
jq -n --arg fid1 "$FOREIGN_ID" --arg fid2 "$UNVERIFIED_ID" \
  '[{finding_id: $fid1, entity_type: "technology", resolved_ontology: "mif-generic@1.0.0", basis: "declared", valid: true},
    {finding_id: $fid2, entity_type: "technology", resolved_ontology: "mif-generic@1.0.0", basis: "declared", valid: true}]' \
  > "reports/$SRC_TOPIC/ontology-map.json"

for f in "reports/$SRC_TOPIC/findings/foreign.json" "reports/$SRC_TOPIC/findings/unverified.json"; do
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/findings.schema.json -r schemas/mif/mif.schema.json -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$f" > "$TMP/src-finding-ajv.log" 2>&1 \
    || { note "the synthetic source finding $f is not schema-valid: $(cat "$TMP/src-finding-ajv.log")"; fail=1; }
done

rm -rf "$TMP/base-container"
"$EXPORT_SCRIPT" "$SRC_TOPIC" "$TMP/base-container" --source-instance "import-check-eval-source" \
  > "$TMP/base-export.log" 2>&1
if [ ! -f "$TMP/base-container/mif-package.json" ]; then
  note "building the REAL base fixture container failed: $(cat "$TMP/base-export.log")"
  exit 1
fi
BASE_RESOURCE_COUNT="$(jq '.resources | length' "$TMP/base-container/mif-package.json")"

# ============================================================================
# A. Structural proof: the DryRun phase invokes the REAL script WITH
#    --dry-run, the Apply phase invokes the identical script WITHOUT it.
#    Extracted by phase() marker span, never a whole-file grep (the module's
#    own header comment ALSO mentions the script).
# ============================================================================
dry_span="$(awk '/^phase\(.DryRun.\)/,/^phase\(.Review.\)/' "$WF")"
[ -n "$dry_span" ] || { note "could not locate the DryRun phase body (phase('DryRun') .. phase('Review') span) in $WF — has the phase-marker shape changed?"; fail=1; }
apply_span="$(awk '/^phase\(.Apply.\)/{f=1} f{print}' "$WF")"
[ -n "$apply_span" ] || { note "could not locate the Apply phase body (phase('Apply') .. EOF span) in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF 'bash scripts/mif-container-import.sh "${CDIR}" "${TOPIC}" --dry-run' <<<"$dry_span" \
  || { note "DryRun phase prompt no longer invokes the literal 'bash scripts/mif-container-import.sh \"\${CDIR}\" \"\${TOPIC}\" --dry-run' — regression risk toward a freehand/prose-derived validation"; fail=1; }
grep -qF 'bash scripts/mif-container-import.sh "${CDIR}" "${TOPIC}"\` (no --dry-run)' <<<"$apply_span" \
  || { note "Apply phase prompt no longer invokes the literal 'bash scripts/mif-container-import.sh \"\${CDIR}\" \"\${TOPIC}\"' (no --dry-run) — regression risk toward re-running the dry-run gate, or a freehand apply"; fail=1; }

# ============================================================================
# Shared driver: runs the REAL research-import.js module via the
# Workflow-runtime's own async-function-body framing (mirrors
# scripts/check-workflow-syntax.sh and the add-dimensions-check.sh /
# pivot-check.sh precedent).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, stubsPath, outPath] = process.argv;
if (!wfPath || !argsJsonPath || !stubsPath || !outPath) {
  console.error('usage: driver.cjs <research-import.js> <argsJson> <stubs.cjs> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
// eslint-disable-next-line import/no-dynamic-require, global-require
const stubs = require(stubsPath);

const calls = [];
const logs = [];

async function agentStub(prompt, opts) {
  const label = opts && opts.label;
  calls.push({ label });
  const handler = stubs[label];
  if (!handler) throw new Error('agentStub: unexpected label ' + label);
  return handler(prompt, opts);
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
function workflowStub() { throw new Error('workflow() should not be called by research-import.js'); }

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls, logs }, null, 2));
})();
NODE

run_import() { # run_import <caseName> <argsJsonFile> <stubsFile> <outFile>
  local caseName="$1" argsFile="$2" stubsFile="$3" outFile="$4"
  if ! node "$TMP/driver.cjs" "$WF" "$argsFile" "$stubsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver run failed: $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

# ============================================================================
# B. DryRun-reject: corrupt one resource's bytes (after its digest was
#    declared) in a COPY of the real base container. The DryRun stub invokes
#    the REAL script --dry-run; Review/Apply must never be called.
# ============================================================================
rm -rf "$TMP/dryrun-container"
cp -r "$TMP/base-container" "$TMP/dryrun-container"
corrupt_target="$(find "$TMP/dryrun-container/findings" -maxdepth 1 -name '*.json' | LC_ALL=C sort | head -1)"
if [ -z "$corrupt_target" ]; then
  note "B: the base container has no finding files to corrupt — cannot build the DryRun-reject fixture"
  fail=1
else
  printf '\n' >> "$corrupt_target"

  cat > "$TMP/stubs-dryrun-reject.cjs" <<NODE
'use strict';
const { execFileSync } = require('child_process');
const ROOT = '$ROOT';
const CONTAINER = '$TMP/dryrun-container';
const TOPIC = '$DRYRUN_TOPIC';
module.exports = {
  'import:dry-run': async () => {
    try {
      const out = execFileSync('bash', [ROOT + '/$IMPORT_SCRIPT', CONTAINER, TOPIC, '--dry-run'], { stdio: 'pipe' }).toString();
      return { passed: true, manifestValid: true, digestsValid: true, ontologyBindingsCompatible: true, resourceCount: $BASE_RESOURCE_COUNT, output: out.slice(0, 2000) };
    } catch (e) {
      const out = ((e.stderr && e.stderr.toString()) || '') + ((e.stdout && e.stdout.toString()) || '') || e.message;
      return {
        passed: false,
        manifestValid: !/manifest does not validate|unrecognized container profile/i.test(out),
        digestsValid: !/digest mismatch/i.test(out),
        ontologyBindingsCompatible: !/ontology-binding incompatible/i.test(out),
        resourceCount: 0,
        output: out.slice(0, 2000),
      };
    }
  },
  'import:review': async () => { throw new Error('import:review must NOT be called when DryRun fails'); },
  'import:apply': async () => { throw new Error('import:apply must NOT be called when DryRun fails'); },
};
NODE
  printf '{"harnessDir":".","topic":"%s","containerDir":"%s"}' "$DRYRUN_TOPIC" "$TMP/dryrun-container" > "$TMP/args-dryrun-reject.json"
  run_import dryrun-reject "$TMP/args-dryrun-reject.json" "$TMP/stubs-dryrun-reject.cjs" "$TMP/out-dryrun-reject.json"

  if [ -f "$TMP/out-dryrun-reject.json" ]; then
    python3 - "$TMP/out-dryrun-reject.json" "reports/$DRYRUN_TOPIC" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
topic_dir = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('B: driver did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('B: module short-circuits with ok:false, stage:dry-run', r.get('ok') is False and r.get('stage') == 'dry-run', json.dumps(r))
detail = r.get('detail') or {}
check('B: the REAL script actually reported passed:false (not a placeholder)', detail.get('passed') is False, json.dumps(detail))
check('B: the real rejection output names a digest mismatch', 'digest mismatch' in (detail.get('output') or ''), detail.get('output'))
labels = [c['label'] for c in d['calls']]
check('B: only import:dry-run was called (Review/Apply never reached)', labels == ['import:dry-run'], json.dumps(labels))
found_count = len([f for f in os.listdir(os.path.join(topic_dir, 'findings')) if f.endswith('.json')]) if os.path.isdir(os.path.join(topic_dir, 'findings')) else -1
check('B: nothing landed under the destination topic findings/ (real, empty directory)', found_count == 0, f'count={found_count}')
check('B: no knowledge-graph.json was built for the destination topic', not os.path.isfile(os.path.join(topic_dir, 'knowledge-graph.json')))
check('B: no ontology-map.json was written for the destination topic', not os.path.isfile(os.path.join(topic_dir, 'ontology-map.json')))
sys.exit(0 if ok else 1)
PY
    rc=$?
    [ "$rc" -eq 0 ] || fail=1
  fi
fi

# ============================================================================
# C. Review NO-GO: a REAL, uncorrupted container — DryRun passes for real.
#    Review is stubbed to return proceed:false. Apply must never be called.
# ============================================================================
cat > "$TMP/stubs-review-nogo.cjs" <<NODE
'use strict';
const { execFileSync } = require('child_process');
const ROOT = '$ROOT';
const CONTAINER = '$TMP/base-container';
const TOPIC = '$REVIEW_TOPIC';
module.exports = {
  'import:dry-run': async () => {
    const out = execFileSync('bash', [ROOT + '/$IMPORT_SCRIPT', CONTAINER, TOPIC, '--dry-run'], { stdio: 'pipe' }).toString();
    return { passed: true, manifestValid: true, digestsValid: true, ontologyBindingsCompatible: true, resourceCount: $BASE_RESOURCE_COUNT, output: out.slice(0, 2000) };
  },
  'import:review': async () => ({
    proceed: false,
    reasons: ['scope: sampled container findings are mostly out of scope against the topic goal (eval fixture judgment — a live sonnet scope-fit call cannot be reproduced deterministically here, stated explicitly, not faked)'],
    collisions: [],
  }),
  'import:apply': async () => { throw new Error('import:apply must NOT be called on a Review NO-GO'); },
};
NODE
printf '{"harnessDir":".","topic":"%s","containerDir":"%s"}' "$REVIEW_TOPIC" "$TMP/base-container" > "$TMP/args-review-nogo.json"
run_import review-nogo "$TMP/args-review-nogo.json" "$TMP/stubs-review-nogo.cjs" "$TMP/out-review-nogo.json"

if [ -f "$TMP/out-review-nogo.json" ]; then
  python3 - "$TMP/out-review-nogo.json" "reports/$REVIEW_TOPIC" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
topic_dir = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('C: driver did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('C: module short-circuits with ok:false, stage:review', r.get('ok') is False and r.get('stage') == 'review', json.dumps(r))
detail = r.get('detail') or {}
check('C: NO-GO reasons carry the stated scope-fit reason', any('scope' in x for x in (detail.get('reasons') or [])), json.dumps(detail))
labels = [c['label'] for c in d['calls']]
check('C: dry-run and review were called, apply was NOT (never reached)', labels == ['import:dry-run', 'import:review'], json.dumps(labels))
found_count = len([f for f in os.listdir(os.path.join(topic_dir, 'findings')) if f.endswith('.json')]) if os.path.isdir(os.path.join(topic_dir, 'findings')) else -1
check('C: nothing landed under the destination topic findings/ (--dry-run never writes, Apply never ran)', found_count == 0, f'count={found_count}')
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# D. Apply-success + needsGating partition for BOTH trust settings. The
#    fixture container is the same real base container built above — it
#    already carries exactly FOREIGN_ID (a real foreign verification block,
#    attempted_at set) and UNVERIFIED_ID (falsify.sh's own documented
#    not-yet-tested placeholder, no attempted_at) from a real, from-scratch
#    synthetic source topic — no cloning/patching/re-digesting needed here.
# ============================================================================
rm -rf "$TMP/apply-container"
cp -r "$TMP/base-container" "$TMP/apply-container"

cat > "$TMP/stubs-apply-success.cjs" <<NODE
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const ROOT = '$ROOT';
const CONTAINER = '$TMP/apply-container';
const TOPIC = '$APPLY_TOPIC';
const FINDINGS_DIR = path.join(ROOT, 'reports', TOPIC, 'findings');
module.exports = {
  'import:dry-run': async () => {
    const out = execFileSync('bash', [ROOT + '/$IMPORT_SCRIPT', CONTAINER, TOPIC, '--dry-run'], { stdio: 'pipe' }).toString();
    return { passed: true, manifestValid: true, digestsValid: true, ontologyBindingsCompatible: true, resourceCount: $BASE_RESOURCE_COUNT, output: out.slice(0, 2000) };
  },
  'import:review': async () => ({ proceed: true, reasons: [], collisions: [] }),
  'import:apply': async () => {
    const out = execFileSync('bash', [ROOT + '/$IMPORT_SCRIPT', CONTAINER, TOPIC], { stdio: 'pipe' }).toString();
    const files = fs.readdirSync(FINDINGS_DIR).filter((f) => f.endsWith('.json')).sort();
    const importedIds = [];
    const withForeignVerdicts = [];
    const unverified = [];
    for (const f of files) {
      const doc = JSON.parse(fs.readFileSync(path.join(FINDINGS_DIR, f), 'utf8'));
      const id = doc['@id'];
      importedIds.push(id);
      const v = (doc.extensions && doc.extensions.harness && doc.extensions.harness.verification) || {};
      if (v.attempted_at) withForeignVerdicts.push(id); else unverified.push(id);
    }
    return { applied: true, importedIds, withForeignVerdicts, unverified, output: out.slice(0, 2000) };
  },
};
NODE

# Run TWICE against the SAME real container/topic (a real, idempotent
# second script invocation — SKIPPED not duplicated) — once per
# trustImportedVerdicts setting, since the setting is read from args BEFORE
# Apply runs and only affects the module's OWN post-processing of the real
# applied.* lists, not what the script itself does.
printf '{"harnessDir":".","topic":"%s","containerDir":"%s","trustImportedVerdicts":false}' "$APPLY_TOPIC" "$TMP/apply-container" > "$TMP/args-apply-false.json"
run_import apply-false "$TMP/args-apply-false.json" "$TMP/stubs-apply-success.cjs" "$TMP/out-apply-false.json"
printf '{"harnessDir":".","topic":"%s","containerDir":"%s","trustImportedVerdicts":true}' "$APPLY_TOPIC" "$TMP/apply-container" > "$TMP/args-apply-true.json"
run_import apply-true "$TMP/args-apply-true.json" "$TMP/stubs-apply-success.cjs" "$TMP/out-apply-true.json"

if [ -f "$TMP/out-apply-false.json" ] && [ -f "$TMP/out-apply-true.json" ]; then
  python3 - "$TMP/out-apply-false.json" "$TMP/out-apply-true.json" "$TMP/needs-gating-false.json" "$FOREIGN_ID" "$UNVERIFIED_ID" <<'PY'
import json, sys
d_false = json.load(open(sys.argv[1], encoding='utf-8'))
d_true = json.load(open(sys.argv[2], encoding='utf-8'))
foreign_id, unverified_id = sys.argv[4], sys.argv[5]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('D: trustImportedVerdicts:false driver did not throw', d_false['threw'] is None, str(d_false['threw']))
check('D: trustImportedVerdicts:true driver did not throw', d_true['threw'] is None, str(d_true['threw']))
r_false = d_false.get('result') or {}
r_true = d_true.get('result') or {}
check('D: both runs report ok:true', r_false.get('ok') is True and r_true.get('ok') is True, json.dumps([r_false, r_true]))

imported_false = set(r_false.get('imported') or [])
imported_true = set(r_true.get('imported') or [])
check('D: both runs imported exactly the 2 real findings (foreign + unverified)', imported_false == {foreign_id, unverified_id} and imported_true == imported_false, json.dumps([sorted(imported_false), sorted(imported_true)]))

needs_gating_false = set(r_false.get('needsGating') or [])
needs_gating_true = set(r_true.get('needsGating') or [])
trusted_false = set(r_false.get('trustedForeignVerdicts') or [])
trusted_true = set(r_true.get('trustedForeignVerdicts') or [])

check('D: trustImportedVerdicts:false — needsGating == unverified + withForeignVerdicts (BOTH ids, imported evidence never exempt by default)',
      needs_gating_false == imported_false, f'needsGating={sorted(needs_gating_false)} imported={sorted(imported_false)}')
check('D: trustImportedVerdicts:false — trustedForeignVerdicts is empty (nothing trusted by default)',
      trusted_false == set(), json.dumps(sorted(trusted_false)))
check('D: trustImportedVerdicts:true — needsGating == ONLY the unverified finding',
      needs_gating_true == {unverified_id}, f'needsGating={sorted(needs_gating_true)} expected=[{unverified_id!r}]')
check('D: trustImportedVerdicts:true — trustedForeignVerdicts == the foreign-verdict finding',
      trusted_true == {foreign_id}, f'trusted={sorted(trusted_true)} expected=[{foreign_id!r}]')

labels_false = [c['label'] for c in d_false['calls']]
labels_true = [c['label'] for c in d_true['calls']]
check('D: both runs called dry-run, review, apply in that order', labels_false == ['import:dry-run', 'import:review', 'import:apply'] and labels_true == labels_false, json.dumps([labels_false, labels_true]))

# Persist the FALSE-trust run's real needsGating (the union case, the one
# that genuinely needs regate:true for the foreign-verdict subset) for
# part E to feed into a REAL research-falsify.js run — never a placeholder.
json.dump(sorted(needs_gating_false), open(sys.argv[3], 'w', encoding='utf-8'))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# E. Falsify regate hookup — structural parameter-shape cross-check, then a
#    REAL end-to-end run of research-falsify.js fed the REAL needsGating
#    produced by D's trustImportedVerdicts:false case.
# ============================================================================
grep -qF 'scope: { ids: needsGating }, regate: true' "$WF" \
  || { note "$WF's documented call-site note no longer shows 'scope: { ids: needsGating }, regate: true' — the falsify regate hookup this eval checks against may have drifted"; fail=1; }
grep -qF "scope?: 'all' | 'dimension:<d>' | { paths?: string[], ids?: string[] }" "$FALSIFY_WF" \
  || { note "$FALSIFY_WF's documented scope shape no longer matches { paths?: string[], ids?: string[] } — cross-check research-import.js's needsGating shape against whatever it changed to"; fail=1; }
grep -qF 'SCOPE.paths || SCOPE.ids' "$FALSIFY_WF" \
  || { note "$FALSIFY_WF's REGATE_SCOPE_QUALIFIES check no longer accepts an ids[] scope — the import->falsify regate hookup would silently break"; fail=1; }
grep -qF 'regate: true' "$WF" \
  || { note "$WF no longer documents that regate: true is required alongside scope:{ids:needsGating} for the foreign-verdict case (#591's interface note)"; fail=1; }

if [ -f "$TMP/needs-gating-false.json" ]; then
  NEEDS_GATING_JSON="$(cat "$TMP/needs-gating-false.json")"
  cat > "$TMP/falsify-driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, outPath] = process.argv;
const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
const calls = [];

async function agentStub(prompt, opts) {
  calls.push({ label: opts && opts.label });
  if ((opts && opts.label) === 'falsify:enumerate') {
    // Empty working set: the Enumerate phase's own control flow
    // (`if (!working.length) return {...}`) returns immediately after this,
    // before ever reaching the Gate phase — hermetic, no skeptic votes or
    // falsify.sh writes needed (falsify-verdict-merge.sh's own eval already
    // covers the Gate phase for real). allFindingIds/skippedAlreadyVerifiedIds
    // are itemized (#625) but all empty here, so #625's reconciliation check
    // (every allFindingIds entry covered by workingSet ∪ skippedAlreadyVerifiedIds)
    // is vacuously satisfied and no retry fires.
    return { workingSet: [], skippedAlreadyVerifiedIds: [], allFindingIds: [] };
  }
  throw new Error('falsify-driver stub: unexpected label ' + (opts && opts.label));
}
function phaseStub() {}
function logStub() {}
function workflowStub() { throw new Error('workflow() should not be called by research-falsify.js in this eval'); }

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls }, null, 2));
})();
NODE

  printf '{"harnessDir":".","topic":"%s","scope":{"ids":%s},"regate":true}' "$APPLY_TOPIC" "$NEEDS_GATING_JSON" > "$TMP/falsify-regate-args.json"
  if ! node "$TMP/falsify-driver.cjs" "$FALSIFY_WF" "$TMP/falsify-regate-args.json" "$TMP/out-falsify-regate.json" >"$TMP/falsify-regate-run.err" 2>&1; then
    note "falsify-regate driver run failed: $(cat "$TMP/falsify-regate-run.err")"
    fail=1
  fi

  if [ -f "$TMP/out-falsify-regate.json" ]; then
    python3 - "$TMP/out-falsify-regate.json" "$NEEDS_GATING_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
needs_gating = json.loads(sys.argv[2])
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

threw = d.get('threw')
check('E: research-falsify.js did NOT throw the "regate=true requires an explicit scope" guard error given scope:{ids: needsGating}',
      not (threw and 'requires an explicit scope' in threw.get('message', '')), json.dumps(threw))
check('E: research-falsify.js completed with no throw at all, given the REAL import needsGating as scope.ids', threw is None, json.dumps(threw))
r = d.get('result') or {}
check('E: an empty working set (no findings on disk in this hermetic slice) short-circuits to gated:0 with no Gate-phase call needed',
      r.get('gated') == 0, json.dumps(r))
check(f'E: the fed scope.ids is exactly the REAL needsGating produced by D ({needs_gating!r}), not a placeholder', len(needs_gating) == 2)
sys.exit(0 if ok else 1)
PY
    rc=$?
    [ "$rc" -eq 0 ] || fail=1
  fi
else
  note "no needs-gating-false.json captured from fixture D — skipping the falsify-regate end-to-end check (fixture D itself already failed above)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the DryRun and Apply phases are structurally proven to invoke the REAL scripts/mif-container-import.sh, with and without --dry-run; a REAL corrupted-digest container (built from a fresh synthetic source topic, no deliverable-report contamination) is rejected at dry-run through the real gate with Review/Apply never called and nothing written; a REAL valid container hits a Review NO-GO (a live sonnet scope-fit judgment this eval cannot reproduce deterministically, stated plainly) with Apply never called and nothing written; the same real container (one real foreign-verdict finding, one carrying falsify.sh's own documented not-yet-tested placeholder) imports for real through the non-dry-run gate and the needsGating/trustedForeignVerdicts partition is correct for BOTH trustImportedVerdicts settings, verified against the real on-disk written files, not a fabricated list; and research-falsify.js accepts the REAL needsGating output as scope:{ids:[...]},regate:true without tripping its guard error, proving the two independently-vendored modules' interface actually lines up end to end — mirroring #588's pivot->falsify interface fixture for this Epic's own action D -> falsify boundary."
else
  echo "import-check: FAILED (see notes above)"
fi
exit "$fail"
