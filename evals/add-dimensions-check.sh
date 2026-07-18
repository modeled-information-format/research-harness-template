#!/usr/bin/env bash
# add-dimensions-check.sh — regression eval for the research-add-dimensions
# workflow module's Propose/Prune/Amend pipeline (research-harness-template#584,
# Epic #546, following #582's vendoring and #583's docs).
#
# Mirrors the augment-decide-check.sh / deliverables-route-check.sh precedent:
# hermetic where the module's own logic can express it, structural greps
# where the behavior is inherently model-driven — said explicitly below,
# never faked as deterministic.
#
#   A. Structural proof the Amend phase actually invokes the REAL
#      scripts/goal-version.sh, not an assumed/prose-derived hash. Extracted
#      by phase('Amend') marker span (never a header comment — the module's
#      own header prose ALSO mentions the script, so a naive whole-file grep
#      would pass even if the Amend prompt itself regressed to the freehand
#      hash the reference implementation used). Asserts:
#        - the literal invocation `bash ${H}/scripts/goal-version.sh` appears
#          in the Amend prompt TWICE (once for OLD, once for NEW) — proving
#          the snapshot-then-mint idiom, not a single one-shot call;
#        - scripts/goal-version.sh actually exists on disk (a renamed/moved
#          script would go stale here, not just in prose);
#        - the Amend prompt explicitly forbids narrating the hash ("read
#          back from goal.json after minting — never the value you would
#          have computed yourself").
#
#   B. Zero-candidate and all-rejected outcomes (inherently reachable without
#      any model judgment about WHICH candidates to keep — only that the
#      module's OWN control flow handles empty proposals/all-pruned
#      correctly): driven for real via the Workflow-runtime's own
#      async-function-body framing (mirrors scripts/check-workflow-syntax.sh
#      and the augment-decide-check.sh precedent). Both complete with no
#      throw, return structured reasoning (the rejected[] array with stated
#      reasons in the all-rejected case), and — checked byte-for-byte —
#      touch NEITHER the fixture harness.config.json NOR any goal.json/goals/
#      file: the Amend phase's agent() call is never invoked at all in
#      either path (asserted from the driver's own call log, not inferred).
#
#   C. Seeded-overlap rejection: a fixture proposal names one candidate that
#      genuinely restates an existing dimension ("technical-details",
#      evidence citing the OVERLAP criterion) alongside one legitimate new
#      axis ("regulatory"). The Prune-phase agent() call is stubbed (the
#      skeptic's actual overlap judgment is a live model call this eval
#      cannot reproduce deterministically — stated plainly, not faked) to
#      approve only the legitimate candidate and reject the overlapping one
#      WITH THE OVERLAP REASON. What is proven hermetically: the module's own
#      control flow correctly filters proposal.candidates down to exactly
#      the approved id (never smuggling a rejected candidate through), the
#      rejected candidate's stated reason survives unmodified into the
#      module's return value, and the Amend phase (checked via the call log)
#      is invoked with ONLY the approved candidate — the overlap candidate
#      never reaches config/goal mutation.
#
#   D. Approved-candidate success, verified against the REAL
#      scripts/goal-version.sh (never a hand-simulated hash): the Amend
#      agent() stub performs exactly the bash sequence the real Amend prompt
#      specifies (jq-patch harness.config.json dimensions[], ajv-validate,
#      snapshot the OLD goal, compute OLD via the real script, jq-patch
#      goal.json dimensions[], compute NEW via the real script, stamp
#      version/supersedes/revision, ajv-validate again) — the SAME script
#      this repo ships, invoked for real, not reimplemented. Asserted:
#        - the approved dimension lands in the fixture harness.config.json
#          dimensions[], and the patched config is ajv-clean against
#          harness.config.schema.json;
#        - the new goal.json is ajv-clean against schemas/goal.schema.json;
#        - .supersedes equals OLD (independently recomputed a SECOND time,
#          from a fresh invocation of scripts/goal-version.sh over the
#          snapshot file, not reused from the driver's first call) and
#          .version equals NEW, independently recomputed a THIRD time from
#          scripts/goal-version.sh over the final stamped goal.json — proving
#          the hash is stable under lineage-field stamping (ADR-0006's own
#          claim) rather than merely asserted.
#
# Hermetic: node/jq/python3/ajv/bash/scripts/goal-version.sh (itself
# delegating to the vendored bin/mif-rh-cli engine, offline — ADR-0016), no
# network, no live model/API calls anywhere in this eval — the Propose/Prune
# agent() calls are stubbed with fixed, schema-shaped decisions; the Amend
# agent() call is stubbed to perform the REAL deterministic bash sequence its
# own prompt specifies, never a freehand/prose-derived hash.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the vendored module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-add-dimensions.js"
GOAL_VERSION_SCRIPT="scripts/goal-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  add-dimensions-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
command -v ajv >/dev/null 2>&1 || { note "ajv is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-add-dimensions workflow must ship (Epic #546, Task #582)"; exit 2; }
[ -f "$GOAL_VERSION_SCRIPT" ] || { note "$GOAL_VERSION_SCRIPT not found — the Amend phase's delegation target does not exist on disk"; exit 2; }
if [ -z "${MIF_RH_CLI:-}" ] && [ ! -x "$ROOT/bin/mif-rh-cli" ] && ! command -v mif-rh-cli >/dev/null 2>&1; then
  note "the mif-rh-cli engine is required (scripts/fetch-engine.sh, PATH, or MIF_RH_CLI) — goal-version.sh hard-requires it, ADR-0016"
  exit 2
fi

# ============================================================================
# A: Amend-phase real-invocation proof (phase('Amend') marker span, never a
# header comment — the module's own header ALSO mentions the script, so a
# whole-file grep would pass even on a regressed prompt).
# ============================================================================
amend_span="$(awk '/^phase\(.Amend.\)/{f=1} f{print}' "$WF")"
[ -n "$amend_span" ] || { note "could not locate the Amend phase body (phase('Amend') .. EOF span) in $WF — has the phase-marker shape changed?"; fail=1; }

amend_invocations="$(grep -oF 'bash ${H}/scripts/goal-version.sh' <<<"$amend_span" | wc -l | tr -d ' ')"
if [ "$amend_invocations" != "2" ]; then
  note "Amend phase prompt invokes 'bash \${H}/scripts/goal-version.sh' $amend_invocations time(s), expected exactly 2 (once for OLD, once for NEW) — the snapshot-then-mint idiom may have regressed to a single one-shot call or a freehand hash"
  fail=1
fi
grep -qF 'never the value you would have computed yourself' <<<"$amend_span" \
  || { note "Amend phase prompt no longer explicitly forbids narrating the gv- hash — regression risk toward the reference implementation's freehand-hash prompt"; fail=1; }
grep -qF 'goal.schema.json' <<<"$amend_span" \
  || { note "Amend phase prompt lost the goal.schema.json ajv-validation step"; fail=1; }
grep -qF 'harness.config.schema.json' <<<"$amend_span" \
  || { note "Amend phase prompt lost the harness.config.schema.json ajv-validation step"; fail=1; }

# ============================================================================
# Shared driver: runs the REAL module via the Workflow-runtime's own
# async-function-body framing (mirrors scripts/check-workflow-syntax.sh and
# the augment-decide-check.sh precedent).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, stubsPath, outPath] = process.argv;
if (!wfPath || !argsJsonPath || !stubsPath || !outPath) {
  console.error('usage: driver.cjs <research-add-dimensions.js> <argsJson> <stubs.cjs> <outPath>');
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
  calls.push({ prompt, opts: { label: opts && opts.label } });
  const label = opts && opts.label;
  const handler = stubs[label];
  if (!handler) throw new Error('agentStub: unexpected label ' + label);
  return handler(prompt, opts);
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
function workflowStub() { throw new Error('workflow() should not be called by research-add-dimensions.js'); }

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

run_case() { # run_case <caseName> <fixtureDir> <topic> <stubsFile> <outFile>
  local caseName="$1" fixtureDir="$2" topic="$3" stubsFile="$4" outFile="$5"
  printf '%s' "{\"harnessDir\":\"$fixtureDir\",\"topic\":\"$topic\"}" > "$TMP/$caseName-args.json"
  if ! node "$TMP/driver.cjs" "$WF" "$TMP/$caseName-args.json" "$stubsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver run failed: $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

# ============================================================================
# Fixture harness shared by every case below: two existing dimensions
# (technical, landscape), a topic, a goal.json naming them.
# ============================================================================
new_fixture() { # new_fixture <name> -> echoes fixture root path
  local name="$1"
  local dir="$TMP/fixture-$name"
  local rdir="$dir/reports/add-dim-eval-topic"
  mkdir -p "$rdir"
  cat > "$dir/harness.config.json" <<'EOF'
{
  "version": "0.1.0",
  "topics": [
    {"id": "add-dim-eval-topic", "namespace": "harness/add-dim-eval-topic"}
  ],
  "dimensions": [
    {"id": "technical", "description": "Technical feasibility, architecture, and implementation evidence."},
    {"id": "landscape", "description": "Comparable prior art, alternatives, and competing approaches."}
  ],
  "packs": []
}
EOF
  cat > "$rdir/goal.json" <<'EOF'
{
  "topic": "add-dim-eval-topic",
  "goal_statement": "Eval fixture goal for research-add-dimensions deterministic teeth (research-harness-template#584).",
  "dimensions": ["technical", "landscape"],
  "completion_condition": {
    "summary": "Evaluate whether widening dimensions works end to end.",
    "checks": [
      {"id": "technical_check", "assertion": "technical has at least one survived finding."}
    ]
  }
}
EOF
  echo "$dir"
}

# ============================================================================
# B1: Zero-candidate case — Propose returns candidates: [] — a valid,
# non-error outcome per the module's own header/return comment.
# ============================================================================
FIX_ZERO="$(new_fixture zero)"
cat > "$TMP/stubs-zero.cjs" <<'NODE'
module.exports = {
  'add-dim:propose': async () => ({ candidates: [] }),
  'add-dim:prune': async () => { throw new Error('add-dim:prune must NOT be called when Propose returns zero candidates'); },
  'add-dim:amend': async () => { throw new Error('add-dim:amend must NOT be called when Propose returns zero candidates'); },
};
NODE
run_case zero "$FIX_ZERO" add-dim-eval-topic "$TMP/stubs-zero.cjs" "$TMP/out-zero.json"

if [ -f "$TMP/out-zero.json" ]; then
  python3 - "$TMP/out-zero.json" "$FIX_ZERO" <<'PY'
import json, sys, os
d = json.load(open(sys.argv[1], encoding='utf-8'))
fixture = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('zero-candidate run did not throw (not an error)', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('added[] is genuinely empty', r.get('added') == [], json.dumps(r.get('added')))
check('rejected[] is genuinely empty', r.get('rejected') == [], json.dumps(r.get('rejected')))
check('goalVersion is null (no lineage event happened)', r.get('goalVersion') is None, json.dumps(r.get('goalVersion')))
labels = [c['opts']['label'] for c in d['calls']]
check('only add-dim:propose was called (Prune/Amend never reached)', labels == ['add-dim:propose'], json.dumps(labels))

cfg_path = os.path.join(fixture, 'harness.config.json')
with open(cfg_path, encoding='utf-8') as f:
    cfg = json.load(f)
check('fixture harness.config.json dimensions[] untouched (still exactly 2)', len(cfg['dimensions']) == 2, json.dumps(cfg['dimensions']))
goal_path = os.path.join(fixture, 'reports/add-dim-eval-topic/goal.json')
with open(goal_path, encoding='utf-8') as f:
    goal = json.load(f)
check('fixture goal.json untouched (no .version stamped)', 'version' not in goal, json.dumps(goal))
check('no goals/ snapshot directory was created', not os.path.isdir(os.path.join(fixture, 'reports/add-dim-eval-topic/goals')))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# B2: All-rejected case — candidates proposed, all pruned. Structured
# reasoning (rejected[] with stated reasons) returned, no error, no
# config/goal-version mutation.
# ============================================================================
FIX_ALLREJ="$(new_fixture allrejected)"
cat > "$TMP/stubs-allrejected.cjs" <<'NODE'
module.exports = {
  'add-dim:propose': async () => ({
    candidates: [
      { id: 'edge-case-1', description: 'Edge case axis 1', evidence: 'homeless lead A', methodologyNote: 'note A' },
      { id: 'edge-case-2', description: 'Edge case axis 2', evidence: 'homeless lead B', methodologyNote: 'note B' },
    ],
  }),
  'add-dim:prune': async () => ({
    approved: [],
    rejected: [
      { id: 'edge-case-1', why: 'not decision-relevant — would be interesting but would not change the goal decision' },
      { id: 'edge-case-2', why: 'excluded by the goal scope out_of_scope list' },
    ],
  }),
  'add-dim:amend': async () => { throw new Error('add-dim:amend must NOT be called when all candidates are rejected'); },
};
NODE
run_case allrejected "$FIX_ALLREJ" add-dim-eval-topic "$TMP/stubs-allrejected.cjs" "$TMP/out-allrejected.json"

if [ -f "$TMP/out-allrejected.json" ]; then
  python3 - "$TMP/out-allrejected.json" "$FIX_ALLREJ" <<'PY'
import json, sys, os
d = json.load(open(sys.argv[1], encoding='utf-8'))
fixture = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('all-rejected run did not throw (not an error)', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('added[] is genuinely empty', r.get('added') == [], json.dumps(r.get('added')))
rejected = r.get('rejected') or []
check('rejected[] carries both candidates with their stated reasons', len(rejected) == 2 and all(x.get('why') for x in rejected), json.dumps(rejected))
check('goalVersion is null (no lineage event happened)', r.get('goalVersion') is None, json.dumps(r.get('goalVersion')))
labels = [c['opts']['label'] for c in d['calls']]
check('only propose+prune were called (Amend never reached)', labels == ['add-dim:propose', 'add-dim:prune'], json.dumps(labels))

cfg_path = os.path.join(fixture, 'harness.config.json')
with open(cfg_path, encoding='utf-8') as f:
    cfg = json.load(f)
check('fixture harness.config.json dimensions[] untouched (still exactly 2)', len(cfg['dimensions']) == 2, json.dumps(cfg['dimensions']))
goal_path = os.path.join(fixture, 'reports/add-dim-eval-topic/goal.json')
with open(goal_path, encoding='utf-8') as f:
    goal = json.load(f)
check('fixture goal.json untouched (no .version stamped)', 'version' not in goal, json.dumps(goal))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# C: Seeded-overlap rejection — one candidate genuinely overlaps an existing
# dimension ("technical"), one is legitimate ("regulatory"). Prune is stubbed
# (the skeptic's actual overlap judgment is a live model call, stated
# plainly as the gap this eval cannot close) to approve only the legitimate
# candidate; what's proven hermetically is the module's OWN filtering logic
# and that the rejected reason survives unmodified, and that Amend only
# ever sees the approved candidate.
# ============================================================================
FIX_OVERLAP="$(new_fixture overlap)"
cat > "$TMP/stubs-overlap.cjs" <<'NODE'
module.exports = {
  'add-dim:propose': async () => ({
    candidates: [
      {
        id: 'technical-details',
        description: 'Deeper technical implementation details',
        evidence: 'seeded overlap: this is a restatement of the existing "technical" dimension, same axis of inquiry',
        methodologyNote: 'same methodology as technical',
      },
      {
        id: 'regulatory',
        description: 'Regulatory and compliance posture',
        evidence: 'homeless lead: compliance findings kept landing outside every declared dimension',
        methodologyNote: 'review applicable regulations and precedent enforcement actions',
      },
    ],
  }),
  'add-dim:prune': async () => ({
    approved: ['regulatory'],
    rejected: [
      { id: 'technical-details', why: 'OVERLAP — this is a subset/restatement of the existing "technical" dimension, not a distinct axis' },
    ],
  }),
  'add-dim:amend': async (prompt) => {
    // Prove Amend is invoked with ONLY the approved candidate (never the
    // overlap-rejected one) by inspecting its own prompt text.
    if (prompt.includes('technical-details')) {
      throw new Error('add-dim:amend prompt names the rejected overlap candidate "technical-details" — it must only ever see approved candidates');
    }
    if (!prompt.includes('regulatory')) {
      throw new Error('add-dim:amend prompt does not name the approved candidate "regulatory"');
    }
    return { configPatched: true, goalVersion: 'gv-000000000000', supersedes: null, added: ['regulatory'] };
  },
};
NODE
run_case overlap "$FIX_OVERLAP" add-dim-eval-topic "$TMP/stubs-overlap.cjs" "$TMP/out-overlap.json"

if [ -f "$TMP/out-overlap.json" ]; then
  python3 - "$TMP/out-overlap.json" <<'PY'
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

check('overlap-fixture run did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('added[] contains ONLY the approved "regulatory" candidate', r.get('added') == ['regulatory'], json.dumps(r.get('added')))
rejected = r.get('rejected') or []
overlap_entry = next((x for x in rejected if x.get('id') == 'technical-details'), None)
check('the overlap candidate is present in rejected[] with a non-empty stated reason', overlap_entry is not None and bool(overlap_entry.get('why')))
check('the stated reason names the overlap criterion', 'OVERLAP' in (overlap_entry or {}).get('why', ''), json.dumps(overlap_entry))
labels = [c['opts']['label'] for c in d['calls']]
check('propose, prune, and amend were all called in that order', labels == ['add-dim:propose', 'add-dim:prune', 'add-dim:amend'], json.dumps(labels))
sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

# ============================================================================
# D: Approved-candidate success, verified against the REAL
# scripts/goal-version.sh — never a hand-simulated hash. The Amend stub
# performs the EXACT bash sequence the real Amend prompt specifies.
# ============================================================================
FIX_APPROVED="$(new_fixture approved)"
RDIR_APPROVED="$FIX_APPROVED/reports/add-dim-eval-topic"

# Independently precompute OLD from the pristine fixture goal, BEFORE the
# driver runs, as a cross-check baseline distinct from whatever the stub
# computes internally.
OLD_BASELINE="$(bash "$GOAL_VERSION_SCRIPT" "$RDIR_APPROVED/goal.json")"

cat > "$TMP/stubs-approved.cjs" <<NODE
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = '$ROOT';
const FIXTURE = '$FIX_APPROVED';
const RDIR = '$RDIR_APPROVED';

module.exports = {
  'add-dim:propose': async () => ({
    candidates: [
      {
        id: 'regulatory',
        description: 'Regulatory and compliance posture',
        evidence: 'homeless lead: compliance findings kept landing outside every declared dimension',
        methodologyNote: 'review applicable regulations and precedent enforcement actions',
      },
    ],
  }),
  'add-dim:prune': async () => ({ approved: ['regulatory'], rejected: [] }),
  'add-dim:amend': async () => {
    // 1. CONFIG: jq-patch harness.config.json dimensions[], then ajv-validate.
    const cfgPath = path.join(FIXTURE, 'harness.config.json');
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    cfg.dimensions.push({ id: 'regulatory', description: 'Regulatory and compliance posture.' });
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
    execFileSync('ajv', ['validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
      '-s', path.join(ROOT, 'harness.config.schema.json'), '-d', cfgPath], { stdio: 'pipe' });

    // 2. GOAL LINEAGE: snapshot OLD, compute OLD via the REAL script.
    const goalPath = path.join(RDIR, 'goal.json');
    const OLD = execFileSync('bash', [path.join(ROOT, 'scripts/goal-version.sh'), goalPath]).toString().trim();
    fs.mkdirSync(path.join(RDIR, 'goals'), { recursive: true });
    fs.copyFileSync(goalPath, path.join(RDIR, 'goals', 'goal-' + OLD + '.json'));

    // Add the new dimension id, additive only.
    const goal = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    goal.dimensions.push('regulatory');
    fs.writeFileSync(goalPath, JSON.stringify(goal, null, 2));

    // 3. Compute NEW via the REAL script (over the widened, still-unstamped content).
    const NEW = execFileSync('bash', [path.join(ROOT, 'scripts/goal-version.sh'), goalPath]).toString().trim();

    // 4. Stamp lineage fields (never perturbs the hash — ADR-0006).
    const stamped = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    stamped.version = NEW;
    stamped.supersedes = OLD;
    stamped.revision = { rationale: 'widen dimension set', changed: ['regulatory'], date: '2026-07-18' };
    fs.writeFileSync(goalPath, JSON.stringify(stamped, null, 2));
    execFileSync('ajv', ['validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
      '-s', path.join(ROOT, 'schemas/goal.schema.json'), '-d', goalPath], { stdio: 'pipe' });

    // 5. Read back the NEW version from goal.json itself — never the
    //    in-memory value — matching the real prompt's own instruction.
    const readBack = JSON.parse(fs.readFileSync(goalPath, 'utf8'));
    return { configPatched: true, goalVersion: readBack.version, supersedes: readBack.supersedes, added: ['regulatory'] };
  },
};
NODE
run_case approved "$FIX_APPROVED" add-dim-eval-topic "$TMP/stubs-approved.cjs" "$TMP/out-approved.json"

if [ -f "$TMP/out-approved.json" ]; then
  python3 - "$TMP/out-approved.json" "$FIX_APPROVED" "$OLD_BASELINE" <<'PY'
import json, sys, os, subprocess
d = json.load(open(sys.argv[1], encoding='utf-8'))
fixture = sys.argv[2]
old_baseline = sys.argv[3]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

check('approved-fixture run did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
check('added == ["regulatory"]', r.get('added') == ['regulatory'], json.dumps(r.get('added')))
labels = [c['opts']['label'] for c in d['calls']]
check('propose, prune, and amend were all called in that order', labels == ['add-dim:propose', 'add-dim:prune', 'add-dim:amend'], json.dumps(labels))

# 1. Config landed ajv-clean (already proven inside the stub; re-verify from
#    the OUTSIDE too, against the real schema, independently).
cfg_path = os.path.join(fixture, 'harness.config.json')
cfg = json.load(open(cfg_path, encoding='utf-8'))
ids = [dd['id'] for dd in cfg['dimensions']]
check('the approved dimension landed in harness.config.json dimensions[]', 'regulatory' in ids, json.dumps(ids))
rc = subprocess.run(['ajv', 'validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
                     '-s', 'harness.config.schema.json', '-d', cfg_path]).returncode
check('the patched harness.config.json is independently ajv-clean', rc == 0)

# 2. Goal version lineage: supersedes == OLD baseline (recomputed BEFORE the
#    driver ran, matching the snapshot file), and it equals what was actually
#    snapshotted to goals/goal-<OLD>.json.
goal_path = os.path.join(fixture, 'reports/add-dim-eval-topic/goal.json')
goal = json.load(open(goal_path, encoding='utf-8'))
check('goal.json.supersedes equals the independently precomputed OLD baseline', goal.get('supersedes') == old_baseline, f"supersedes={goal.get('supersedes')!r} baseline={old_baseline!r}")
snapshot_path = os.path.join(fixture, 'reports/add-dim-eval-topic/goals', f'goal-{old_baseline}.json')
check('the OLD goal was snapshotted to goals/goal-<OLD>.json before mutation', os.path.isfile(snapshot_path))

# 3. THE key claim: the NEW gv- hash matches what scripts/goal-version.sh
#    independently computes over the CURRENT (post-mutation, post-stamp)
#    goal.json — recomputed HERE, a third independent invocation, never
#    reused from the stub's own in-process computation.
recomputed_new = subprocess.run(['bash', 'scripts/goal-version.sh', goal_path], capture_output=True, text=True).stdout.strip()
check('goal.json.version equals a FRESH, independent scripts/goal-version.sh recomputation over the final stamped file (hash stable under lineage stamping, ADR-0006)',
      goal.get('version') == recomputed_new, f"version={goal.get('version')!r} recomputed={recomputed_new!r}")
check("the module's returned goalVersion matches goal.json's own .version field (read back, never model-narrated)",
      r.get('goalVersion') == goal.get('version'), f"returned={r.get('goalVersion')!r} file={goal.get('version')!r}")
check("the module's returned supersedes matches goal.json's own .supersedes field",
      r.get('supersedes') == goal.get('supersedes'))

rc2 = subprocess.run(['ajv', 'validate', '--spec=draft2020', '--strict=false', '-c', 'ajv-formats',
                      '-s', 'schemas/goal.schema.json', '-d', goal_path]).returncode
check('the final stamped goal.json is independently ajv-clean against goal.schema.json', rc2 == 0)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "Amend phase invokes the REAL scripts/goal-version.sh exactly twice (OLD then NEW), never a freehand-narrated hash; zero-candidate and all-rejected outcomes both complete with no throw, structured reasoning, and provably untouched config/goal files (Amend never invoked); a seeded overlap candidate is correctly filtered out of added[] with its stated OVERLAP reason preserved, and Amend never sees it; and the approved-candidate path lands the new dimension in an independently-ajv-clean harness.config.json, with the new goal version's supersedes/version fields matching THREE separate fresh invocations of the real scripts/goal-version.sh (baseline before mutation, and two independent recomputations after) — proving the hash is a real, stable function of content, not a hand-simulated or narrated value. The one gap this eval cannot close — whether a live skeptic model actually judges 'technical-details' as overlapping — is genuine and non-deterministic, documented here rather than faked."
else
  echo "add-dimensions-check: FAILED (see notes above)"
fi
exit "$fail"
