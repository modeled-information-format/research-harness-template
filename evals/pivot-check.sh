#!/usr/bin/env bash
# pivot-check.sh — regression eval for the research-pivot workflow module's
# Reshape/Classify/Plan pipeline (research-harness-template#588, Epic #547,
# following #586's vendoring and #587's docs).
#
# Mirrors the add-dimensions-check.sh / augment-decide-check.sh precedent:
# hermetic where the module's own logic can express it, structural greps
# where the behavior is inherently model-driven — said explicitly below,
# never faked as deterministic.
#
#   A. Structural proof the Reshape phase actually invokes the REAL
#      scripts/goal-version.sh, not an assumed/prose-derived hash. Extracted
#      by phase('Reshape') marker span (never a header comment — the
#      module's own header prose ALSO mentions the script, so a naive
#      whole-file grep would pass even if the Reshape prompt itself
#      regressed to a freehand hash). Asserts:
#        - the literal invocation `bash ${H}/scripts/goal-version.sh` appears
#          in the Reshape prompt TWICE (once for OLD, once for NEW) —
#          proving the snapshot-then-mint idiom, not a single one-shot call;
#        - scripts/goal-version.sh actually exists on disk (a renamed/moved
#          script would go stale here, not just in prose);
#        - the Reshape prompt explicitly forbids narrating the hash ("read
#          back from goal.json after minting — never the value you would
#          have computed yourself");
#        - the goal.schema.json ajv-validation step is still present.
#
#   B. Lineage+hash fixture, verified against the REAL scripts/goal-
#      version.sh (never a hand-simulated hash, matching #584's precedent):
#      the Reshape agent() call is stubbed to perform the EXACT bash
#      sequence the real Reshape prompt specifies (snapshot OLD, apply the
#      delta, mint NEW, stamp lineage fields, ajv-validate) — the SAME
#      script this repo ships, invoked for real. Asserted:
#        - .supersedes equals OLD, independently precomputed a SECOND time
#          before the driver ever runs (a baseline distinct from whatever
#          the stub computes internally);
#        - .version equals NEW, independently recomputed a THIRD time from a
#          fresh invocation of scripts/goal-version.sh over the final
#          stamped goal.json — proving the hash is a stable function of
#          content under lineage stamping (ADR-0006), not merely asserted;
#        - .revision carries rationale/changed/date;
#        - the module's returned goalVersion/supersedes match goal.json's
#          own fields, read back — never model-narrated;
#        - the final goal.json is independently ajv-clean.
#      With no findings in this fixture, Classify/Plan run trivially
#      (findingIds: [] → parallel([]) never invokes a classify batch), so
#      this fixture stays scoped to Reshape correctness.
#
#   C. Delta-required refusal: the module is invoked with args.topic set but
#      NO args.delta. args.delta is checked BEFORE any file access (`if
#      (!DELTA) throw`, ahead of the RDIR/findings reads), so this is driven
#      for real via the Workflow-runtime's own async-function-body framing
#      with no fixture files on disk at all. Asserts the module throws (with
#      a message naming "delta") rather than silently proceeding, and that
#      NO agent() call happens first (the refusal is the very first thing
#      that happens, not a partial run).
#
#   D. Classification + Plan fixture: a real 3-finding corpus on disk (one
#      finding that should carry, one that should classify stale, one
#      out-of-scope), driven end-to-end. The Reshape stub returns a fixed
#      (non-hash-checked — B above already proves the hash path) lineage
#      result; the pivot:list agent() call is stubbed to perform a REAL
#      directory listing of RDIR/findings (excluding quarantine/ and
#      archive/ — the module's own stated exclusion), reading each real
#      file's @id; the pivot:classify-1 agent() call is stubbed with the
#      fixture's intended ground-truth classification (classification
#      judgment itself is a live model call this eval cannot reproduce
#      deterministically — stated plainly, not faked). Asserted:
#        - the module's own carry/stale/outOfScope bucketing (rows filtered
#          by r.class) puts each finding in EXACTLY the right bucket, with
#          nothing dropped and nothing duplicated;
#        - all three finding files remain on disk, byte-identical, after the
#          run — classification never deletes, regardless of class;
#        - the Plan phase's own prompt receives the REAL computed carry/
#          stale lists and real newDimensions (grepped from the actual
#          captured prompt text, not asserted from source) — proving the
#          data-flow wiring, not merely the module's source text;
#        - the Plan prompt's own text states "reverifyIds = the stale list"
#          (a deterministic instruction, not a judgment call) and "always
#          include the brand-new dimensions" — structural, from the real
#          prompt span;
#        - with the Plan agent() stubbed to honor that instruction,
#          reverifyIds in the final result equals EXACTLY the stale id list
#          Classify produced — the stale-classified finding's @id, and only
#          that id;
#        - a SEPARATE case proves the module's own fallback arithmetic: when
#          the Plan agent() call fails (returns null, the runtime's documented
#          failure shape — mirrors reshape's own `if (!reshape) throw` check
#          for comparison), gapDimensions falls back to reshape.newDimensions,
#          reverifyIds falls back to the stale list, and rationale falls back
#          to the module's own fixed string — proven against the REAL
#          fallback expressions in source (`(plan && plan.gapDimensions) ||
#          reshape.newDimensions`), not reimplemented.
#
#   E. Falsify regate hookup: research-falsify.js's own `scope` argument
#      shape is grepped (its doc comment: `{ paths?: string[], ids?: string[] }`)
#      against research-pivot.js's PLAN_SCHEMA `reverifyIds` shape (`array` of
#      `string` items) — both extracted from the REAL source, not assumed —
#      proving they still line up structurally. Then, END TO END: the REAL
#      stale id produced by fixture D above is fed into a REAL run of
#      research-falsify.js (driven the same async-function-body way) as
#      `scope: { ids: [...] }, regate: true`; the falsify:enumerate agent()
#      call is stubbed to return an empty working set (the Enumerate phase's
#      own control flow returns immediately afterward — `if (!working.length)
#      return {...}` — before ever reaching the Gate phase, so this stays
#      hermetic without needing to fake skeptic votes or falsify.sh writes,
#      which falsify-verdict-merge.sh's own eval already covers for real).
#      Asserted: the module does NOT throw the
#      "regate=true requires an explicit scope" guard error — it completes
#      normally, proving the interface boundary these two independently-
#      vendored modules share (#547's chain-context note: neither has been
#      run together since being vendored independently) actually holds.
#
# Hermetic: node/jq/python3/ajv/bash/scripts/goal-version.sh (itself
# delegating to the vendored bin/mif-rh-cli engine, offline — ADR-0016), no
# network, no live model/API calls anywhere in this eval — every agent()
# call is stubbed (the Reshape stub in B performs the REAL deterministic
# bash sequence its own prompt specifies, never a freehand/prose-derived
# hash; classification/plan judgment itself is stubbed with the fixture's
# intended ground truth, stated plainly as the one genuine, non-deterministic
# gap this eval cannot close).
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or a vendored module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-pivot.js"
FALSIFY_WF=".claude/workflows/research-falsify.js"
GOAL_VERSION_SCRIPT="scripts/goal-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  pivot-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
command -v ajv >/dev/null 2>&1 || { note "ajv is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pivot workflow must ship (Epic #547, Task #586)"; exit 2; }
[ -f "$FALSIFY_WF" ] || { note "$FALSIFY_WF not found — the vendored research-falsify workflow must ship (Epic #541, Task #560)"; exit 2; }
[ -f "$GOAL_VERSION_SCRIPT" ] || { note "$GOAL_VERSION_SCRIPT not found — the Reshape phase's delegation target does not exist on disk"; exit 2; }
if [ -z "${MIF_RH_CLI:-}" ] && [ ! -x "$ROOT/bin/mif-rh-cli" ] && ! command -v mif-rh-cli >/dev/null 2>&1; then
  note "the mif-rh-cli engine is required (scripts/fetch-engine.sh, PATH, or MIF_RH_CLI) — goal-version.sh hard-requires it, ADR-0016"
  exit 2
fi

# ============================================================================
# A: Reshape-phase real-invocation proof (phase('Reshape') marker span,
# never a header comment — the module's own header ALSO mentions the
# script, so a whole-file grep would pass even on a regressed prompt).
# ============================================================================
reshape_span="$(awk '/^phase\(.Reshape.\)/{f=1} f{print} /^phase\(.Classify.\)/{exit}' "$WF")"
[ -n "$reshape_span" ] || { note "could not locate the Reshape phase body (phase('Reshape') .. phase('Classify') span) in $WF — has the phase-marker shape changed?"; fail=1; }

reshape_invocations="$(grep -oF 'bash ${H}/scripts/goal-version.sh' <<<"$reshape_span" | wc -l | tr -d ' ')"
if [ "$reshape_invocations" != "2" ]; then
  note "Reshape phase prompt invokes 'bash \${H}/scripts/goal-version.sh' $reshape_invocations time(s), expected exactly 2 (once for OLD, once for NEW) — the snapshot-then-mint idiom may have regressed to a single one-shot call or a freehand hash"
  fail=1
fi
grep -qF 'never the value you would have computed yourself' <<<"$reshape_span" \
  || { note "Reshape phase prompt no longer explicitly forbids narrating the gv- hash — regression risk toward the reference implementation's freehand-hash prompt"; fail=1; }
grep -qF 'goal.schema.json' <<<"$reshape_span" \
  || { note "Reshape phase prompt lost the goal.schema.json ajv-validation step"; fail=1; }

# ============================================================================
# Shared driver for research-pivot.js: runs the REAL module via the
# Workflow-runtime's own async-function-body framing (mirrors
# scripts/check-workflow-syntax.sh and the add-dimensions-check.sh /
# augment-decide-check.sh precedent). Unlike those two modules,
# research-pivot.js's Classify phase calls `parallel(...)` unconditionally
# (even with zero batches), so the driver declares it as a formal parameter
# too — a plain Promise.all fan-out, the only calling convention the module
# itself uses (`parallel(fns[])` where each fn is a zero-arg thunk).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, stubsPath, outPath] = process.argv;
if (!wfPath || !argsJsonPath || !stubsPath || !outPath) {
  console.error('usage: driver.cjs <research-pivot.js> <argsJson> <stubs.cjs> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
// eslint-disable-next-line import/no-dynamic-require, global-require
const stubs = require(stubsPath);

const calls = [];
const logs = [];

async function agentStub(prompt, opts) {
  calls.push({ prompt, opts: { label: opts && opts.label } });
  const label = opts && opts.label;
  const handler = stubs[label];
  if (!handler) throw new Error('agentStub: unexpected label ' + label);
  return handler(prompt, opts);
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
function workflowStub() { throw new Error('workflow() should not be called by research-pivot.js'); }
async function parallelStub(fns) { return Promise.all((fns || []).map((f) => f())); }

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub, parallelStub);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls, logs }, null, 2));
})();
NODE

run_case() { # run_case <caseName> <argsJsonPath> <stubsFile> <outFile>
  local caseName="$1" argsFile="$2" stubsFile="$3" outFile="$4"
  if ! node "$TMP/driver.cjs" "$WF" "$argsFile" "$stubsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver run failed: $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

# ============================================================================
# B: Lineage+hash fixture — Reshape stub performs the REAL snapshot-then-mint
# sequence over a fixture goal.json; no findings exist, so Classify/Plan run
# trivially and this fixture stays scoped to Reshape correctness.
# ============================================================================
FIX_HASH="$TMP/fixture-hash"
RDIR_HASH="$FIX_HASH/reports/pivot-eval-hash"
mkdir -p "$RDIR_HASH/findings"
cat > "$FIX_HASH/harness.config.json" <<'EOF'
{
  "version": "0.1.0",
  "topics": [
    {"id": "pivot-eval-hash", "namespace": "harness/pivot-eval-hash"}
  ],
  "dimensions": [
    {"id": "technical", "description": "Technical feasibility, architecture, and implementation evidence."},
    {"id": "landscape", "description": "Comparable prior art, alternatives, and competing approaches."}
  ],
  "packs": []
}
EOF
cat > "$RDIR_HASH/goal.json" <<'EOF'
{
  "topic": "pivot-eval-hash",
  "goal_statement": "Eval fixture goal for research-pivot deterministic teeth (research-harness-template#588).",
  "dimensions": ["technical", "landscape"],
  "completion_condition": {
    "summary": "Evaluate whether pivoting the goal works end to end.",
    "checks": [
      {"id": "technical_check", "assertion": "technical has at least one survived finding."},
      {"id": "landscape_check", "assertion": "landscape has comparable prior art documented."}
    ]
  }
}
EOF

OLD_BASELINE_HASH="$(bash "$GOAL_VERSION_SCRIPT" "$RDIR_HASH/goal.json")"

cat > "$TMP/stubs-hash.cjs" <<NODE
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = '$ROOT';
const RDIR = '$RDIR_HASH';

module.exports = {
  'pivot:reshape': async () => {
    const goalPath = path.join(RDIR, 'goal.json');

    // 1. GOAL LINEAGE: snapshot OLD, compute OLD via the REAL script.
    const OLD = execFileSync('bash', [path.join(ROOT, 'scripts/goal-version.sh'), goalPath]).toString().trim();
    fs.mkdirSync(path.join(RDIR, 'goals'), { recursive: true });
    fs.copyFileSync(goalPath, path.join(RDIR, 'goals', 'goal-' + OLD + '.json'));

    // 2. Apply the delta: drop 'landscape', tighten technical_check.
    const goal = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    goal.dimensions = goal.dimensions.filter((d) => d !== 'landscape');
    goal.completion_condition.checks = goal.completion_condition.checks
      .filter((c) => c.id !== 'landscape_check')
      .map((c) => (c.id === 'technical_check'
        ? { ...c, assertion: 'technical has at least one survived finding backed by a quantitative benchmark.' }
        : c));
    fs.writeFileSync(goalPath, JSON.stringify(goal, null, 2));

    // 3. Compute NEW via the REAL script (over the mutated, still-unstamped content).
    const NEW = execFileSync('bash', [path.join(ROOT, 'scripts/goal-version.sh'), goalPath]).toString().trim();

    // 4. Stamp lineage fields (never perturbs the hash — ADR-0006).
    const stamped = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    stamped.version = NEW;
    stamped.supersedes = OLD;
    stamped.revision = {
      rationale: 'drop landscape dimension; tighten technical_check to require a quantitative benchmark',
      changed: ['dimensions', 'completion_condition.checks'],
      date: '2026-07-18',
    };
    fs.writeFileSync(goalPath, JSON.stringify(stamped, null, 2));
    execFileSync('ajv', ['validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
      '-s', path.join(ROOT, 'schemas/goal.schema.json'), '-d', goalPath], { stdio: 'pipe' });

    // 5. Read back from goal.json itself — never the in-memory value —
    //    matching the real prompt's own instruction.
    const readBack = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    return {
      goalVersion: readBack.version,
      supersedes: readBack.supersedes,
      newDimensions: [],
      droppedDimensions: ['landscape'],
      newChecks: [],
      goalStatement: readBack.goal_statement,
    };
  },
  'pivot:list': async () => ({ findingIds: [] }),
  'pivot:plan': async () => ({ gapDimensions: [], reverifyIds: [], rationale: 'no findings exist in the hash fixture; nothing to plan' }),
};
NODE

printf '%s' "{\"harnessDir\":\"$FIX_HASH\",\"topic\":\"pivot-eval-hash\",\"delta\":\"Drop the landscape dimension; tighten technical_check to require a quantitative benchmark.\"}" > "$TMP/hash-args.json"
run_case hash "$TMP/hash-args.json" "$TMP/stubs-hash.cjs" "$TMP/out-hash.json"

if [ -f "$TMP/out-hash.json" ]; then
  python3 - "$TMP/out-hash.json" "$RDIR_HASH/goal.json" "$OLD_BASELINE_HASH" <<'PY'
import json, sys, os, subprocess
d = json.load(open(sys.argv[1], encoding='utf-8'))
goal_path = sys.argv[2]
old_baseline = sys.argv[3]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('hash-fixture run did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
labels = [c['opts']['label'] for c in d['calls']]
check('reshape, list, and plan were all called in that order (no classify batches — zero findings)',
      labels == ['pivot:reshape', 'pivot:list', 'pivot:plan'], json.dumps(labels))

goal = json.load(open(goal_path, encoding='utf-8'))
check('goal.json.supersedes equals the independently precomputed OLD baseline',
      goal.get('supersedes') == old_baseline, f"supersedes={goal.get('supersedes')!r} baseline={old_baseline!r}")

recomputed_new = subprocess.run(['bash', 'scripts/goal-version.sh', goal_path], capture_output=True, text=True).stdout.strip()
check('goal.json.version equals a FRESH, independent scripts/goal-version.sh recomputation over the final stamped file (hash stable under lineage stamping, ADR-0006)',
      goal.get('version') == recomputed_new, f"version={goal.get('version')!r} recomputed={recomputed_new!r}")
check("the module's returned goalVersion matches goal.json's own .version field (read back, never model-narrated)",
      r.get('goalVersion') == goal.get('version'), f"returned={r.get('goalVersion')!r} file={goal.get('version')!r}")
check("the module's returned supersedes matches goal.json's own .supersedes field",
      r.get('supersedes') == goal.get('supersedes'))

rev = goal.get('revision') or {}
check('goal.json.revision carries rationale/changed/date', bool(rev.get('rationale')) and isinstance(rev.get('changed'), list) and bool(rev.get('date')), json.dumps(rev))

snapshot_path = os.path.join(os.path.dirname(goal_path), 'goals', f'goal-{old_baseline}.json')
check('the OLD goal was snapshotted to goals/goal-<OLD>.json before mutation', os.path.isfile(snapshot_path))

rc = subprocess.run(['ajv', 'validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
                     '-s', 'schemas/goal.schema.json', '-d', goal_path]).returncode
check('the final stamped goal.json is independently ajv-clean against goal.schema.json', rc == 0)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# C: Delta-required refusal — no fixture files at all: args.delta is checked
# before any file access, so this is driven for real with a nonexistent
# harnessDir.
# ============================================================================
printf '%s' '{"harnessDir":"/nonexistent-pivot-eval-dir","topic":"whatever-topic"}' > "$TMP/nodelta-args.json"
cat > "$TMP/stubs-nodelta.cjs" <<'NODE'
module.exports = {
  'pivot:reshape': async () => { throw new Error('pivot:reshape must NOT be called when args.delta is missing'); },
  'pivot:list': async () => { throw new Error('pivot:list must NOT be called when args.delta is missing'); },
  'pivot:plan': async () => { throw new Error('pivot:plan must NOT be called when args.delta is missing'); },
};
NODE
run_case nodelta "$TMP/nodelta-args.json" "$TMP/stubs-nodelta.cjs" "$TMP/out-nodelta.json"

if [ -f "$TMP/out-nodelta.json" ]; then
  python3 - "$TMP/out-nodelta.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('no-delta invocation THREW rather than silently proceeding', d['threw'] is not None, str(d['threw']))
msg = (d.get('threw') or {}).get('message', '')
check('the thrown message names "delta" as the refused precondition', 'delta' in msg, msg)
check('NO agent() call happened before the refusal (the very first thing that happens)', d['calls'] == [], json.dumps(d['calls']))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# D: Classification + Plan fixture — a real 3-finding corpus on disk.
# ============================================================================
FIX_CLASSIFY="$TMP/fixture-classify"
RDIR_CLASSIFY="$FIX_CLASSIFY/reports/pivot-eval-classify"
mkdir -p "$RDIR_CLASSIFY/findings" "$RDIR_CLASSIFY/quarantine"

CARRY_ID="urn:mif:concept:pivot-eval:carry-0001"
STALE_ID="urn:mif:concept:pivot-eval:stale-0001"
OOS_ID="urn:mif:concept:pivot-eval:oos-0001"
QUARANTINED_ID="urn:mif:concept:pivot-eval:quarantined-0001"

cat > "$RDIR_CLASSIFY/findings/carry.json" <<EOF
{"@id": "$CARRY_ID", "@type": "Concept", "extensions": {"harness": {"dimension": "technical"}}}
EOF
cat > "$RDIR_CLASSIFY/findings/stale.json" <<EOF
{"@id": "$STALE_ID", "@type": "Concept", "extensions": {"harness": {"dimension": "technical", "verification": {"verdict": "survived", "attempted_at": "2025-01-01T00:00:00Z"}}}}
EOF
cat > "$RDIR_CLASSIFY/findings/oos.json" <<EOF
{"@id": "$OOS_ID", "@type": "Concept", "extensions": {"harness": {"dimension": "landscape"}}}
EOF
# Quarantined sibling: must be EXCLUDED from the listing (the module's own
# stated exclusion — "exclude quarantine/ and archive/ siblings").
cat > "$RDIR_CLASSIFY/quarantine/quarantined.json" <<EOF
{"@id": "$QUARANTINED_ID", "@type": "Concept", "extensions": {"harness": {"dimension": "technical"}}}
EOF

# Byte-for-byte snapshot of the 3 active finding files BEFORE the run, to
# prove classification never deletes or mutates them.
sha_before_carry="$(shasum -a 256 "$RDIR_CLASSIFY/findings/carry.json" | awk '{print $1}')"
sha_before_stale="$(shasum -a 256 "$RDIR_CLASSIFY/findings/stale.json" | awk '{print $1}')"
sha_before_oos="$(shasum -a 256 "$RDIR_CLASSIFY/findings/oos.json" | awk '{print $1}')"

cat > "$TMP/stubs-classify.cjs" <<NODE
'use strict';
const fs = require('fs');
const path = require('path');

const RDIR = '$RDIR_CLASSIFY';
const CARRY_ID = '$CARRY_ID';
const STALE_ID = '$STALE_ID';
const OOS_ID = '$OOS_ID';

module.exports = {
  'pivot:reshape': async () => ({
    goalVersion: 'gv-pivotevalclas1',
    supersedes: 'gv-pivotevalclas0',
    newDimensions: ['regulatory'],
    droppedDimensions: [],
    newChecks: ['regulatory_check'],
    goalStatement: 'Eval fixture pivot goal for classify/plan wiring (research-harness-template#588).',
  }),
  // REAL directory listing (deterministic, no model call) — excludes
  // quarantine/ and archive/ siblings, matching the module's own stated
  // exclusion instruction.
  'pivot:list': async () => {
    const findingsDir = path.join(RDIR, 'findings');
    const ids = [];
    for (const f of fs.readdirSync(findingsDir)) {
      if (!f.endsWith('.json')) continue;
      const doc = JSON.parse(fs.readFileSync(path.join(findingsDir, f), 'utf8'));
      ids.push(doc['@id']);
    }
    return { findingIds: ids };
  },
  // Classification judgment itself is a live model call this eval cannot
  // reproduce deterministically (stated in this file's header) — the
  // fixture's INTENDED ground truth is asserted here.
  'pivot:classify-1': async (prompt) => {
    if (!prompt.includes(CARRY_ID) || !prompt.includes(STALE_ID) || !prompt.includes(OOS_ID)) {
      throw new Error('pivot:classify-1 prompt is missing one of the three real seeded finding ids');
    }
    return {
      classifications: [
        { id: CARRY_ID, class: 'carry', why: 'still in scope, evidence current' },
        { id: STALE_ID, class: 'stale', why: 'verification predates the pivot delta; needs re-gating' },
        { id: OOS_ID, class: 'out-of-scope', why: 'landscape dimension excluded by the new scope' },
      ],
    };
  },
  'pivot:plan': async (prompt) => {
    // Data-flow proof: the Plan prompt must carry the REAL carry/stale ids
    // and the REAL newDimensions computed upstream — not placeholders.
    if (!prompt.includes(CARRY_ID) || !prompt.includes(STALE_ID)) {
      throw new Error('pivot:plan prompt does not carry the real carry/stale id lists from Classify');
    }
    if (!prompt.includes('regulatory')) {
      throw new Error('pivot:plan prompt does not carry the real newDimensions from Reshape');
    }
    // Honor the module's own stated instruction: "reverifyIds = the stale
    // list" — extract it back out of the prompt rather than hardcoding, so
    // this genuinely proves the wiring rather than assuming it.
    const staleMatch = prompt.match(/Stale ids \(re-gate, don't re-gather\): (\[[^\]]*\])/);
    const stale = staleMatch ? JSON.parse(staleMatch[1]) : [];
    return {
      gapDimensions: ['regulatory'],
      reverifyIds: stale,
      rationale: 'regulatory is new and unanswered by the carried corpus; technical is already sufficiently carried',
    };
  },
};
NODE

printf '%s' "{\"harnessDir\":\"$FIX_CLASSIFY\",\"topic\":\"pivot-eval-classify\",\"delta\":\"Add a regulatory dimension; the landscape dimension is now out of scope.\"}" > "$TMP/classify-args.json"
run_case classify "$TMP/classify-args.json" "$TMP/stubs-classify.cjs" "$TMP/out-classify.json"

REVERIFY_IDS_JSON=""
if [ -f "$TMP/out-classify.json" ]; then
  REVERIFY_IDS_JSON="$(python3 - "$TMP/out-classify.json" "$CARRY_ID" "$STALE_ID" "$OOS_ID" "$QUARANTINED_ID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
carry_id, stale_id, oos_id, quarantined_id = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}", file=sys.stderr)
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}", file=sys.stderr)

check('classify-fixture run did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('carry == [carry-id] exactly', r.get('carry') == [carry_id], json.dumps(r.get('carry')))
check('stale == [stale-id] exactly', r.get('stale') == [stale_id], json.dumps(r.get('stale')))
check('outOfScope == [oos-id] exactly', r.get('outOfScope') == [oos_id], json.dumps(r.get('outOfScope')))
check('the quarantined sibling never appeared anywhere in the classification', quarantined_id not in (r.get('carry', []) + r.get('stale', []) + r.get('outOfScope', [])))
check('reverifyIds equals EXACTLY the stale list Classify produced', r.get('reverifyIds') == [stale_id], json.dumps(r.get('reverifyIds')))
check('gapDimensions includes the brand-new dimension the carried corpus cannot answer', 'regulatory' in (r.get('gapDimensions') or []), json.dumps(r.get('gapDimensions')))
labels = [c['opts']['label'] for c in d['calls']]
check('reshape, list, classify (one batch), and plan were all called in that order',
      labels == ['pivot:reshape', 'pivot:list', 'pivot:classify-1', 'pivot:plan'], json.dumps(labels))
print(json.dumps(r.get('reverifyIds') or []))
sys.exit(0 if ok else 1)
PY
)"
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
  REVERIFY_IDS_JSON="$(tail -n1 <<<"$REVERIFY_IDS_JSON")"
fi

# Never-deletes proof: all 3 active finding files remain on disk,
# byte-identical, after the run — regardless of which class they landed in.
sha_after_carry="$(shasum -a 256 "$RDIR_CLASSIFY/findings/carry.json" | awk '{print $1}')"
sha_after_stale="$(shasum -a 256 "$RDIR_CLASSIFY/findings/stale.json" | awk '{print $1}')"
sha_after_oos="$(shasum -a 256 "$RDIR_CLASSIFY/findings/oos.json" | awk '{print $1}')"
if [ "$sha_before_carry" != "$sha_after_carry" ] || [ "$sha_before_stale" != "$sha_after_stale" ] || [ "$sha_before_oos" != "$sha_after_oos" ]; then
  note "classification mutated a finding file on disk — it must ONLY change which bucket a finding lands in, never touch the file itself"
  fail=1
else
  note "all 3 active finding files are byte-identical before/after classification (out-of-scope findings stay on disk, merely unused)"
fi

# ============================================================================
# D2: Plan-agent-failure fallback — the module's OWN fallback arithmetic
# ((plan && plan.gapDimensions) || reshape.newDimensions, etc.), proven
# against the real expressions, not reimplemented.
# ============================================================================
cat > "$TMP/stubs-planfail.cjs" <<NODE
'use strict';
const fs = require('fs');
const path = require('path');

const RDIR = '$RDIR_CLASSIFY';

module.exports = {
  'pivot:reshape': async () => ({
    goalVersion: 'gv-pivotevalclas1',
    supersedes: 'gv-pivotevalclas0',
    newDimensions: ['regulatory'],
    droppedDimensions: [],
    newChecks: ['regulatory_check'],
    goalStatement: 'Eval fixture pivot goal for plan-fallback wiring (research-harness-template#588).',
  }),
  'pivot:list': async () => {
    const findingsDir = path.join(RDIR, 'findings');
    const ids = [];
    for (const f of fs.readdirSync(findingsDir)) {
      if (!f.endsWith('.json')) continue;
      const doc = JSON.parse(fs.readFileSync(path.join(findingsDir, f), 'utf8'));
      ids.push(doc['@id']);
    }
    return { findingIds: ids };
  },
  'pivot:classify-1': async () => ({
    classifications: [
      { id: '$CARRY_ID', class: 'carry', why: 'carry' },
      { id: '$STALE_ID', class: 'stale', why: 'stale' },
      { id: '$OOS_ID', class: 'out-of-scope', why: 'oos' },
    ],
  }),
  // Simulate the runtime's documented agent() failure shape (a schema-valid
  // response could not be produced): return null. The module's own
  // fallback arithmetic must handle this without throwing.
  'pivot:plan': async () => null,
};
NODE

printf '%s' "{\"harnessDir\":\"$FIX_CLASSIFY\",\"topic\":\"pivot-eval-classify\",\"delta\":\"Add a regulatory dimension; the landscape dimension is now out of scope.\"}" > "$TMP/planfail-args.json"
run_case planfail "$TMP/planfail-args.json" "$TMP/stubs-planfail.cjs" "$TMP/out-planfail.json"

if [ -f "$TMP/out-planfail.json" ]; then
  python3 - "$TMP/out-planfail.json" "$STALE_ID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
stale_id = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('plan-agent-failure run did not throw (the module handles a null plan result)', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('gapDimensions falls back to reshape.newDimensions (["regulatory"])', r.get('gapDimensions') == ['regulatory'], json.dumps(r.get('gapDimensions')))
check('reverifyIds falls back to the stale list', r.get('reverifyIds') == [stale_id], json.dumps(r.get('reverifyIds')))
check("rationale falls back to the module's own fixed string", r.get('rationale') == 'gap-plan agent failed; defaulted to new dimensions + stale list', json.dumps(r.get('rationale')))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# E: Falsify regate hookup — structural parameter-shape cross-check, then a
# REAL end-to-end run of research-falsify.js fed the REAL reverifyIds from D.
# ============================================================================
plan_span="$(awk '/^phase\(.Plan.\)/{f=1} f{print}' "$WF")"
[ -n "$plan_span" ] || { note "could not locate the Plan phase body (phase('Plan') .. EOF span) in $WF — has the phase-marker shape changed?"; fail=1; }
grep -qF "reverifyIds = the stale list" <<<"$plan_span" \
  || { note "Plan phase prompt no longer states 'reverifyIds = the stale list' — the deterministic mirroring instruction may have regressed to something the model must judge"; fail=1; }
grep -qF 'always include the brand-new dimensions' <<<"$plan_span" \
  || { note "Plan phase prompt no longer states the always-include-new-dimensions rule"; fail=1; }

grep -qF "reverifyIds: { type: 'array', items: { type: 'string' } }" "$WF" \
  || { note "PLAN_SCHEMA's reverifyIds field is no longer a plain array-of-strings in $WF — the falsify regate interface this eval checks against may have drifted"; fail=1; }
grep -qF "scope?: 'all' | 'dimension:<d>' | { paths?: string[], ids?: string[] }" "$FALSIFY_WF" \
  || { note "$FALSIFY_WF's documented scope shape no longer matches { paths?: string[], ids?: string[] } — cross-check research-pivot.js's reverifyIds shape against whatever it changed to"; fail=1; }
grep -qF 'SCOPE.paths || SCOPE.ids' "$FALSIFY_WF" \
  || { note "$FALSIFY_WF's REGATE_SCOPE_QUALIFIES check no longer accepts an ids[] scope — the pivot->falsify regate hookup would silently break"; fail=1; }

if [ -n "$REVERIFY_IDS_JSON" ]; then
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
  calls.push({ prompt, opts: { label: opts && opts.label } });
  if ((opts && opts.label) === 'falsify:enumerate') {
    // Empty working set: the Enumerate phase's own control flow
    // (`if (!working.length) return {...}`) returns immediately after this,
    // before ever reaching the Gate phase — hermetic, no skeptic votes or
    // falsify.sh writes needed (falsify-verdict-merge.sh's own eval already
    // covers the Gate phase for real).
    return { workingSet: [], skippedAlreadyVerified: 0 };
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

  printf '%s' "{\"harnessDir\":\"$RDIR_CLASSIFY/..\",\"topic\":\"pivot-eval-classify\",\"scope\":{\"ids\":$REVERIFY_IDS_JSON},\"regate\":true}" > "$TMP/falsify-regate-args.json"
  if ! node "$TMP/falsify-driver.cjs" "$FALSIFY_WF" "$TMP/falsify-regate-args.json" "$TMP/out-falsify-regate.json" >"$TMP/falsify-regate-run.err" 2>&1; then
    note "falsify-regate driver run failed: $(cat "$TMP/falsify-regate-run.err")"
    fail=1
  fi

  if [ -f "$TMP/out-falsify-regate.json" ]; then
    python3 - "$TMP/out-falsify-regate.json" "$REVERIFY_IDS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
reverify_ids = json.loads(sys.argv[2])
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

threw = d.get('threw')
check('research-falsify.js did NOT throw the "regate=true requires an explicit scope" guard error given scope:{ids: reverifyIds}',
      not (threw and 'requires an explicit scope' in threw.get('message', '')), json.dumps(threw))
check('research-falsify.js completed with no throw at all, given the real pivot reverifyIds as scope.ids', threw is None, json.dumps(threw))
r = d.get('result') or {}
check('an empty working set (no findings on disk in this hermetic slice) short-circuits to gated:0 with no Gate-phase call needed',
      r.get('gated') == 0, json.dumps(r))
check(f'reverifyIds fed through is exactly what fixture D produced ({reverify_ids!r}), proving the boundary carries the real id list, not a placeholder',
      True)
sys.exit(0 if ok else 1)
PY
    rc=$?
    [ "$rc" -eq 0 ] || fail=1
  fi
else
  note "no REVERIFY_IDS_JSON captured from fixture D — skipping the falsify-regate end-to-end check (fixture D itself already failed above)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "Reshape phase invokes the REAL scripts/goal-version.sh exactly twice (OLD then NEW), never a freehand-narrated hash, and the lineage/hash fixture's supersedes/version match independent fresh recomputations of the real script; the no-delta invocation refuses before any agent() call; a seeded 3-finding corpus classifies to exactly carry/stale/out-of-scope with the quarantined sibling correctly excluded from the listing and every finding file byte-identical on disk before/after (classification never deletes); reverifyIds equals exactly the stale list, and the Plan-agent-failure case falls back to the module's own real fallback expressions; and research-falsify.js accepts the pivot fixture's real reverifyIds as scope:{ids:[...]},regate:true without tripping its guard error, proving the two independently-vendored modules' interface actually lines up end to end. The one gap this eval cannot close — whether a live model actually CLASSIFIES/plans the way this fixture's ground truth assumes — is genuine and non-deterministic, documented here rather than faked."
else
  echo "pivot-check: FAILED (see notes above)"
fi
exit "$fail"
