#!/usr/bin/env bash
# synthesis-citation-check.sh — regression eval for the research-synthesis
# citation-integrity gate (research-harness-template#566, Epic #542).
#
# The vendored workflow module (.claude/workflows/research-synthesis.js) is
# an evaluator-optimizer loop: a haiku Select phase computes the citable
# survivor set, a sonnet Draft phase writes a typed synthesis document, and
# an opus Critique phase grades it (including citation-key integrity)
# through a bounded repair loop. UNLIKE research-falsify.js's mergeVotes()/
# claimBudget (#562) — pure functions this module can extract and run
# verbatim — the Select and Critique phases here have NO equivalent pure
# function: they are entirely `agent()` (model) calls driven by prompt text.
# This eval was designed against that real constraint, checked case by case
# rather than assumed:
#
#   A. Select-phase structural exclusion (fixture-level, no model call). No
#      extractable pure selection function exists, so this reimplements the
#      module's OWN DOCUMENTED selection rule (quoted verbatim from its
#      Select-phase prompt below) as a small, hermetic jq-driven scan, run
#      against a seeded fixture corpus carrying one finding in EVERY state
#      that matters: survived / weakened / inconclusive (all citable),
#      unverified (ungated, no verification block at all), falsified
#      (quarantined) and — the case that actually proves exclusion is
#      STRUCTURAL, not verdict-based — a finding with a perfectly good
#      'survived' verdict sitting under archive/. The reimplementation is
#      cross-checked against the module's own source text (grep) so it
#      cannot silently drift from what is actually prompted.
#
#   B. Repair-round bound (<=2). The while-loop + its bounded-exit branch is
#      extracted VERBATIM (same brace-matched technique as #562) from
#      research-synthesis.js and driven with a stubbed `agent`/`log`,
#      proving BEHAVIORALLY — not just via a grep of the constant — that a
#      critique that never converges is bounded at exactly MAX_REPAIR (2)
#      rounds and logs the unresolved-check message rather than looping
#      further; that a critique converging early stops before the bound;
#      and that an already-clean critique never enters the loop at all. A
#      defense-in-depth grep of the MAX_REPAIR constant is also included,
#      matching the falsify-verdict-merge precedent's structural-grep
#      pattern for non-model-testable behavior.
#
#   C. Citation-key integrity — GENUINE SUBSTRATE GAP, documented rather
#      than faked (per #566's own instructions). There is no client-side
#      citation-set validator anywhere in this module or the repo for a
#      SYNTHESIS document's finding-@id references: scripts/
#      check-citation-integrity.sh is a DIFFERENT gate entirely (it checks
#      that raw FINDINGS carry traceable external-source citations; it has
#      no notion of a synthesis document or a survivor-@id closed set —
#      verified by reading it, not assumed). The actual out-of-set-citation
#      check — "does this synthesis cite an @id outside the closed survivor
#      set" — is delegated ENTIRELY to the opus Critique phase's model
#      judgment via the `VALID FINDING IDS` prompt clause. CI cannot run
#      that model call, so this eval does NOT assert a pass/fail verdict on
#      any synthesis fixture — doing so would be exactly the "faking a
#      deterministic assertion for an inherently non-deterministic gate"
#      #566 explicitly warns against. What IS asserted, deterministically:
#        (i)  the WIRING is correct — survivorIds is built from `sel.
#             survivors` (the Select phase's OWN closed output), not from
#             the whole corpus, and the critique prompt embeds that exact
#             set under `VALID FINDING IDS` with an explicit instruction to
#             flag any claim citing outside it (all three grepped verbatim
#             from the module source);
#        (ii) the eval's OWN seeded fixtures are correctly shaped — a
#             synthesis-good.json fixture citing only in-survivor-set ids,
#             and a synthesis-bad-outofset.json fixture seeded with #566's
#             own named acceptance criterion, a claim citing
#             finding-falsified's @id (quarantined, outside the survivor
#             set) — a pure self-consistency check on the fixtures
#             themselves, never a claim about what the production gate
#             would do with them.
#      LIMITATION, stated plainly: whether the opus critic actually catches
#      the seeded out-of-set citation in synthesis-bad-outofset.json is NOT
#      exercised by this eval and cannot be, deterministically, in CI. It
#      requires a live model call. This is the same class of limitation
#      #560/#541 named for falsification-gate voting itself — a legitimate,
#      documented gap, not a silently-skipped assertion.
#
# Hermetic: only evals/fixtures/synthesis-citation/*, mktemp scratch, and
# node/jq/ajv already required elsewhere in this suite. No network, no
# model/API calls.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  synthesis-citation-check: %s\n' "$1"; }

WF=.claude/workflows/research-synthesis.js
FX=evals/fixtures/synthesis-citation

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-synthesis workflow must ship (Epic #542, Task #564)"; exit 2; }

# ============================================================================
# A: Select-phase structural exclusion. Reimplements the module's OWN
# documented rule (quoted from its Select prompt) as a hermetic jq scan
# against a seeded fixture corpus, cross-checked against the module's own
# source text so the reimplementation cannot silently drift from what is
# actually prompted.
# ============================================================================
RDIR="$TMP/reports/synthesis-eval-topic"
mkdir -p "$RDIR/findings" "$RDIR/quarantine" "$RDIR/archive"
cp "$FX/finding-survived.json"     "$RDIR/findings/"
cp "$FX/finding-weakened.json"     "$RDIR/findings/"
cp "$FX/finding-inconclusive.json" "$RDIR/findings/"
cp "$FX/finding-unverified.json"   "$RDIR/findings/"
cp "$FX/finding-falsified.json"    "$RDIR/quarantine/"
cp "$FX/finding-archived.json"     "$RDIR/archive/"

select_survivors() { # select_survivors <rdir> -> "<survivors> <excluded> <unverified>"
  local rdir="$1" survivors=0 unverified=0 excluded=0 f v
  # ONLY globs findings/ -- quarantine/ and archive/ are never scanned for
  # verdicts at all. This is the structural (directory-based) exclusion the
  # module documents; a verdict-based reimplementation would have to
  # explicitly special-case 'falsified', which this deliberately never does.
  for f in "$rdir"/findings/*.json; do
    [ -e "$f" ] || continue
    if jq -e '.extensions.harness | has("verification")' "$f" >/dev/null 2>&1; then
      v="$(jq -r '.extensions.harness.verification.verdict' "$f")"
      case "$v" in
        survived|weakened|inconclusive) survivors=$((survivors + 1)) ;;
        *)
          note "select_survivors: unexpected verdict '$v' found under findings/ — falsified findings must never appear there (research-falsify.js's remediation already quarantines them)"
          echo "-1 -1 -1"; return 1 ;;
      esac
    else
      unverified=$((unverified + 1))
    fi
  done
  for f in "$rdir"/quarantine/*.json "$rdir"/archive/*.json; do
    [ -e "$f" ] || continue
    excluded=$((excluded + 1))
  done
  echo "$survivors $excluded $unverified"
}

read -r got_survivors got_excluded got_unverified <<< "$(select_survivors "$RDIR")"
[ "$got_survivors" = "3" ] \
  || { note "survivor count: got $got_survivors, want 3 (survived+weakened+inconclusive all citable)"; fail=1; }
[ "$got_excluded" = "2" ] \
  || { note "excluded count: got $got_excluded, want 2 (quarantine+archive, by directory)"; fail=1; }
[ "$got_unverified" = "1" ] \
  || { note "unverified count: got $got_unverified, want 1 (no verification block at all)"; fail=1; }

# The critical proof that exclusion is STRUCTURAL, not verdict-based: the
# archived finding genuinely carries a clean 'survived' verdict (a positive
# control) yet is excluded purely because it lives under archive/, not
# findings/.
archived_verdict="$(jq -r '.extensions.harness.verification.verdict' "$RDIR/archive/finding-archived.json")"
[ "$archived_verdict" = "survived" ] \
  || { note "test setup broken: finding-archived.json verdict='$archived_verdict', want 'survived' (must be a verdict-clean positive control to prove directory-based exclusion)"; fail=1; }
archived_id="$(jq -r '."@id"' "$RDIR/archive/finding-archived.json")"
findings_ids="$(jq -r '."@id"' "$RDIR"/findings/*.json)"
grep -qxF "$archived_id" <<< "$findings_ids" \
  && { note "the archived finding's @id ($archived_id) leaked into findings/ — the fixture-setup step placed it wrong, this eval would no longer be testing directory-based exclusion"; fail=1; }

# Cross-check: the reimplementation above matches what the module ACTUALLY
# prompts, not an invented rule — grepped verbatim from the Select phase.
grep -qF 'Structurally EXCLUDE everything under' "$WF" \
  || { note "$WF Select prompt lost the structural quarantine/archive exclusion clause"; fail=1; }
grep -qF '${RDIR}/quarantine/ or ${RDIR}/archive/' "$WF" \
  || { note "$WF Select prompt no longer names both quarantine/ and archive/ as structurally excluded"; fail=1; }
grep -qF 'do not re-derive falsified status from the verdict field' "$WF" \
  || { note "$WF Select prompt lost the never-re-derive-from-verdict instruction (the exact thing this eval's archived-finding positive control proves)"; fail=1; }
grep -qF 'Count findings with NO verification block in unverified' "$WF" \
  || { note "$WF Select prompt lost the unverified/ungated counting instruction"; fail=1; }
grep -qF 'survived, weakened, or inconclusive' "$WF" \
  || { note "$WF Select prompt no longer names all three citable verdicts (survived/weakened/inconclusive)"; fail=1; }

# ============================================================================
# B: repair-round bound. The while-loop + bounded-exit branch is extracted
# VERBATIM (brace-matched, never re-typed) from research-synthesis.js and
# driven with a stubbed agent()/log() -- a real behavioral proof, not just a
# grep of the constant.
# ============================================================================
cat > "$TMP/extract-repair-loop.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-repair-loop.cjs <research-synthesis.js> <tmpdir>');
  process.exit(2);
}
const src = fs.readFileSync(wfPath, 'utf8');

function extractBlockFrom(text, searchIdx, spanStartIdx) {
  const braceStart = text.indexOf('{', searchIdx);
  if (braceStart < 0) throw new Error('no opening brace found');
  let depth = 0, i = braceStart;
  for (; i < text.length; i++) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) break; }
  }
  if (depth !== 0) throw new Error('unbalanced braces');
  return text.slice(spanStartIdx, i + 1);
}
function extractSpan(text, startMarker, throughMarker) {
  const s = text.indexOf(startMarker);
  if (s < 0) throw new Error(`start marker not found: ${JSON.stringify(startMarker)}`);
  const t = text.indexOf(throughMarker, s);
  if (t < 0) throw new Error(`through-marker not found after start: ${JSON.stringify(throughMarker)}`);
  return extractBlockFrom(text, t, s);
}

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ok  ${name}`);
  else { failed = 1; console.log(`FAIL  ${name}${detail ? ' -- ' + detail : ''}`); }
}

// Verbatim extraction of `let rounds = 0` through the bounded-exit `if`
// block's closing brace -- the SAME span the module runs, never a bash/JS
// reimplementation of the loop arithmetic.
let runRepairLoop;
try {
  const spanText = extractSpan(
    src,
    'let rounds = 0',
    'if (critique && !critique.clean && rounds >= MAX_REPAIR) {',
  );
  const harnessSrc =
    'async function runRepairLoop(critique, draft, MAX_REPAIR, agent, log, critiquePrompt, CRITIQUE_SCHEMA) {\n' +
    spanText + '\n' +
    '  return { rounds, critique };\n' +
    '}\n' +
    'module.exports = { runRepairLoop };\n';
  const harnessPath = path.join(tmpDir, 'repair-loop-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ runRepairLoop } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the repair loop from ${wfPath}: ${e.message}`);
  process.exit(1);
}

function stub() {
  const calls = [];
  const logs = [];
  return { calls, logs };
}

async function driveBoundedCase() {
  const { calls, logs } = stub();
  const agent = async (_prompt, opts) => {
    calls.push(opts.label);
    if (opts.label.startsWith('synthesis:recritique-')) {
      return { clean: false, issues: ['still bad'], perCheck: [] };
    }
    return { ok: true };
  };
  const log = (msg) => logs.push(msg);
  const draft = { synthesisPath: '/tmp/fake-synthesis.json' };
  const critiquePrompt = (p) => `critique ${p}`;
  const CRITIQUE_SCHEMA = {};
  const initialCritique = { clean: false, issues: ['initial'], perCheck: [] };
  const MAX_REPAIR = 2;
  const { rounds, critique } = await runRepairLoop(initialCritique, draft, MAX_REPAIR, agent, log, critiquePrompt, CRITIQUE_SCHEMA);
  check('bounded case: a never-converging critique stops at exactly MAX_REPAIR (2) rounds, never more', rounds === 2, `rounds=${rounds}`);
  check('bounded case: agent invoked exactly 2 calls/round (repair + recritique)', calls.length === 4, JSON.stringify(calls));
  check(
    'bounded case: call sequence is repair-1, recritique-1, repair-2, recritique-2',
    JSON.stringify(calls) === JSON.stringify(['synthesis:repair-1', 'synthesis:recritique-1', 'synthesis:repair-2', 'synthesis:recritique-2']),
    JSON.stringify(calls),
  );
  check('bounded case: final critique still unclean (the bound never fabricates convergence)', critique.clean === false, JSON.stringify(critique));
  check(
    'bounded case: the bounded-exit branch actually logged (fail-closed with an explicit unresolved-check report, not a silent stop)',
    logs.some((m) => m.includes('bounded at') && m.includes('without converging')),
    JSON.stringify(logs),
  );
}

async function driveConvergesEarlyCase() {
  const { calls, logs } = stub();
  const agent = async (_prompt, opts) => {
    calls.push(opts.label);
    if (opts.label.startsWith('synthesis:recritique-')) {
      // Converges on the FIRST repair round -- proves the loop stops as
      // soon as the critic is satisfied, regardless of the bound.
      return { clean: true, issues: [], perCheck: [] };
    }
    return { ok: true };
  };
  const log = (msg) => logs.push(msg);
  const draft = { synthesisPath: '/tmp/fake-synthesis.json' };
  const critiquePrompt = (p) => `critique ${p}`;
  const CRITIQUE_SCHEMA = {};
  const initialCritique = { clean: false, issues: ['initial'], perCheck: [] };
  const MAX_REPAIR = 2;
  const { rounds, critique } = await runRepairLoop(initialCritique, draft, MAX_REPAIR, agent, log, critiquePrompt, CRITIQUE_SCHEMA);
  check('converges-early case: stops at round 1, not the full bound', rounds === 1, `rounds=${rounds}`);
  check('converges-early case: only 2 agent calls total (repair-1, recritique-1)', calls.length === 2, JSON.stringify(calls));
  check('converges-early case: final critique is clean', critique.clean === true, JSON.stringify(critique));
  check('converges-early case: the bounded-exit message never logs on a clean outcome', !logs.some((m) => m.includes('bounded at')), JSON.stringify(logs));
}

async function driveAlreadyCleanCase() {
  const { calls, logs } = stub();
  const agent = async (_prompt, opts) => { calls.push(opts.label); return { ok: true }; };
  const log = (msg) => logs.push(msg);
  const draft = { synthesisPath: '/tmp/fake-synthesis.json' };
  const critiquePrompt = (p) => `critique ${p}`;
  const CRITIQUE_SCHEMA = {};
  const initialCritique = { clean: true, issues: [], perCheck: [] };
  const MAX_REPAIR = 2;
  const { rounds, critique } = await runRepairLoop(initialCritique, draft, MAX_REPAIR, agent, log, critiquePrompt, CRITIQUE_SCHEMA);
  check('already-clean case: an already-clean critique never enters the loop -- zero repair rounds', rounds === 0, `rounds=${rounds}`);
  check('already-clean case: zero agent calls (no wasted repair/recritique)', calls.length === 0, JSON.stringify(calls));
  check('already-clean case: critique unchanged', critique.clean === true, JSON.stringify(critique));
}

(async () => {
  await driveBoundedCase();
  await driveConvergesEarlyCase();
  await driveAlreadyCleanCase();
  process.exit(failed);
})();
NODE

if ! node "$TMP/extract-repair-loop.cjs" "$WF" "$TMP" > "$TMP/repair-loop.out" 2>&1; then
  note "repair-loop extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/repair-loop.out"
  fail=1
else
  sed 's/^/    /' "$TMP/repair-loop.out"
fi

# Defense-in-depth structural grep of the bound constant itself, matching
# the falsify-verdict-merge (#562) precedent's structural-grep pattern.
# NOTE: the default is an explicit undefined-check, not `|| 2` -- `|| 2` was a
# real bug (a caller-supplied maxRepairRounds:0, meaning "no repair loop",
# is falsy and silently replaced by 2), fixed on review (PR #568).
# research-harness-template#654: the args-derived local was renamed from
# `args` to `A` (every atomic module normalizes a top-level standalone
# Workflow-tool invocation, where `args` can arrive as a JSON-encoded
# STRING -- #617/#654) -- the undefined-vs-0 semantics this grep proves are
# unchanged, only the local identifier is.
grep -qE "MAX_REPAIR = \(A && A\.maxRepairRounds\) !== undefined \? A\.maxRepairRounds : 2" "$WF" \
  || { note "$WF's MAX_REPAIR default no longer distinguishes an explicit 0 from unset -- the <=2 repair-round bound this eval proves no longer matches the module's actual default"; fail=1; }
grep -qF 'rounds < MAX_REPAIR' "$WF" \
  || { note "$WF's repair while-loop no longer bounds on MAX_REPAIR"; fail=1; }

# ============================================================================
# C: citation-key integrity -- wiring check (deterministic) + fixture
# self-consistency check (deterministic), NOT a claim about what the
# production opus critic would do (that is inherently non-deterministic and
# cannot run in CI -- see the header comment above; #566 explicitly calls
# for stating this rather than faking an assertion).
# ============================================================================
grep -qF 'const survivorIds = new Set(sel.survivors.map((s) => s.id))' "$WF" \
  || { note "$WF lost the survivorIds construction from sel.survivors (the Select phase's OWN closed output) -- the citation gate's valid-id set would no longer trace back to the structural exclusion in Part A"; fail=1; }
grep -qF 'VALID FINDING IDS (the ONLY citable set): ${JSON.stringify(Array.from(survivorIds))}' "$WF" \
  || { note "$WF critique prompt no longer embeds the closed survivorIds set as VALID FINDING IDS"; fail=1; }
grep -qF 'flag any synthesis claim citing an @id outside the valid set' "$WF" \
  || { note "$WF critique prompt lost the explicit out-of-set-citation instruction to the critic"; fail=1; }

# Fixture self-consistency: synthesis-good.json cites ONLY ids inside the
# survivor set computed in Part A; synthesis-bad-outofset.json cites the
# quarantined finding's @id (outside it) -- this proves the SEEDED
# ACCEPTANCE-CRITERION FIXTURE is correctly shaped, not that any gate
# rejects it (no deterministic gate to run it through exists).
survivor_ids='["urn:mif:concept:synthesis-eval:survived-0001","urn:mif:concept:synthesis-eval:weakened-0001","urn:mif:concept:synthesis-eval:inconclusive-0001"]'
good_outside=$(jq --argjson ids "$survivor_ids" '[.claims[].citedId] - $ids | length' "$FX/synthesis-good.json")
[ "$good_outside" = "0" ] \
  || { note "synthesis-good.json cites $good_outside id(s) outside the survivor set -- fixture is not a clean positive control"; fail=1; }
bad_outside=$(jq --argjson ids "$survivor_ids" '[.claims[].citedId] - $ids | length' "$FX/synthesis-bad-outofset.json")
[ "$bad_outside" = "1" ] \
  || { note "synthesis-bad-outofset.json cites $bad_outside id(s) outside the survivor set, want exactly 1 (the seeded out-of-set citation)"; fail=1; }
bad_target=$(jq --argjson ids "$survivor_ids" -r '[.claims[].citedId] - $ids | .[0]' "$FX/synthesis-bad-outofset.json")
[ "$bad_target" = "urn:mif:concept:synthesis-eval:falsified-0001" ] \
  || { note "synthesis-bad-outofset.json's out-of-set citation is '$bad_target', want the quarantined finding's @id (urn:mif:concept:synthesis-eval:falsified-0001) -- #566's own named acceptance criterion"; fail=1; }

[ "$fail" -eq 0 ] && note "Select-phase exclusion is structural (by directory, proven against a verdict-clean archived positive control) and matches the module's own documented rule; the repair loop is bounded at exactly MAX_REPAIR=2 rounds (proven by driving the extracted loop, both bounded and early-convergence cases) and the module keeps that bound; the citation-integrity gate's wiring (closed survivorIds -> critique prompt -> explicit instruction) is intact and the seeded out-of-set-citation fixture is correctly shaped -- though whether the opus critic itself catches it is a genuine, documented, non-deterministic gap this eval cannot close in CI"
exit "$fail"
