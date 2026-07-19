#!/usr/bin/env bash
# pipeline-repair-disclosure-check.sh — regression eval for
# research-harness-template#623 (research-pipeline.js side): a live full-mode
# run reported finding_valid/citation_integrity as cleanly 'met' with no
# indication that research-fanout.js's own repair lane had just mutated a
# large fraction of the round's findings in place before grading — the
# independent completion evaluator graded only "does the corpus currently
# validate", never "did it arrive that way". This eval proves the
# orchestrator now (a) tells the independent evaluator's prompt exactly how
# many findings this round's fanout repaired, so it can no longer grade a
# validity check as cleanly met without disclosing that, and (b) surfaces
# the running repair total in the run's own final report, deterministically,
# independent of what the model does with the disclosure.
#
# Drives the REAL research-pipeline.js source via the same
# Workflow-runtime async-function-body driver technique as
# research-pipeline-full-mode-check.sh (every workflow() child and the
# completionCheck() agent() call stubbed to canned, schema-shaped results;
# no live model/API calls anywhere). This eval does not re-prove the round
# loop's own bounding/termination behavior (research-pipeline-full-mode-check.sh
# already does, exhaustively) — it proves ONLY the repair-disclosure wiring
# #623 asked for.
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly):
# whether a live sonnet completionCheck() call actually heeds the disclosure
# text and states the repair count in its evidence, rather than ignoring the
# instruction. That is a live-model judgment call no CI eval can prove
# deterministically — the same class of documented gap
# synthesis-citation-check.sh already names for the analogous citation-
# integrity judgment. What IS proven deterministically: the disclosure text,
# carrying the REAL per-round repair count, actually reaches the prompt the
# model would see, and the run report's own repaired total is correct
# regardless of what the model does with it.
#
# Hermetic: node/python3, no network, no model/API calls, no fixture files
# on disk (research-pipeline.js's round loop never touches real files
# itself — every filesystem interaction is delegated to stubbed children).
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-pipeline.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  pipeline-repair-disclosure-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

# ============================================================================
# Structural: the completionCheck() prompt embeds a per-round repairedCount
# parameter and the disclosure instruction naming #623, and the round loop
# reads fan.repaired and accumulates it — checked against the real,
# unmodified module source before the behavioral drive below.
# ============================================================================
grep -qF 'async function completionCheck(roundNo, roundRepaired)' "$WF" \
  || { note "completionCheck() no longer accepts a roundRepaired parameter -- the independent evaluator has no way to learn this round's repair count"; fail=1; }
grep -qF 'DISCLOSURE (research-harness-template#623)' "$WF" \
  || { note "completionCheck()'s prompt lost the #623 repair-disclosure instruction"; fail=1; }
grep -qF 'const roundRepaired = (fan && fan.repaired) || 0' "$WF" \
  || { note "the round loop no longer reads fan.repaired from research-fanout's return value"; fail=1; }
grep -qF 'totalRepaired += roundRepaired' "$WF" \
  || { note "the round loop no longer accumulates totalRepaired across rounds"; fail=1; }
grep -qF 'repaired: totalRepaired,' "$WF" \
  || { note "the final full-mode return no longer surfaces the accumulated repair total"; fail=1; }

# ============================================================================
# Behavioral: same driver technique as research-pipeline-full-mode-check.sh.
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, stubsPath, outPath] = process.argv;
const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'budget', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
// eslint-disable-next-line import/no-dynamic-require, global-require
const stubs = require(stubsPath);

const wfCalls = [];
const agentCalls = [];
const logs = [];

async function workflowStub(spec, wfArgs) {
  const scriptPath = (spec && spec.scriptPath) || '';
  const m = /research-([a-zA-Z-]+)\.js$/.exec(scriptPath);
  const name = m && m[1];
  wfCalls.push({ name, args: wfArgs });
  const handler = stubs.wf && stubs.wf[name];
  if (!handler) throw new Error('workflowStub: unexpected/unstubbed scriptPath ' + JSON.stringify({ scriptPath, name }));
  return handler(wfArgs);
}

async function agentStub(prompt, opts) {
  const label = opts && opts.label;
  agentCalls.push({ label, prompt });
  const m = /^check:round-(\d+)$/.exec(label || '');
  if (!m) throw new Error('agentStub: unexpected label ' + label);
  return stubs.completionCheck(Number(m[1]));
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
async function parallelStub(fns) { return Promise.all((fns || []).map((f) => f())); }
const budgetObj = stubs.budget || { total: 0, remaining: () => 0 };

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub, parallelStub, budgetObj);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, wfCalls, agentCalls, logs }, null, 2));
})();
NODE

# Two rounds: round 1's fanout repairs 3 findings (heavily defective round);
# round 2's fanout repairs 0 (clean round) and the evaluator finally reports
# zero unmet, ending the run.
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"repair-disclosure-eval-topic\",\"maxRounds\":3}" > "$TMP/args.json"
cat > "$TMP/stubs.cjs" <<'NODE'
'use strict';
let fanoutCalls = 0;
let synthCalls = 0;
module.exports = {
  wf: {
    goal: async () => ({ ok: true, goalFile: 'reports/repair-disclosure-eval-topic/goal.json', goalProse: 'eval goal', dimensions: ['technical'], checks: [{ id: 'finding_valid' }], lintIssues: [] }),
    fanout: async (a) => {
      fanoutCalls += 1;
      return {
        dimensions: a.dimensions,
        findings: [],
        perDimension: (a.dimensions || []).map((d) => ({ dimension: d, written: 3, valid: 3, repaired: fanoutCalls === 1 ? 3 : 0, searches: 2, saturation: 'not saturated' })),
        crossDimensionLeads: [],
        related: 0,
        repaired: fanoutCalls === 1 ? 3 : 0,
      };
    },
    falsify: async () => ({ gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    synthesis: async () => { synthCalls += 1; return { ok: true, synthesisPath: 'reports/repair-disclosure-eval-topic/synthesis-' + synthCalls + '.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }; },
    'coverage-audit': async () => ({ backlog: [{ action: 'augment', target: 'finding_valid', why: 'still unmet', priority: 1 }], summary: 'keep going', rawItems: [], uncoveredAngles: [] }),
    augment: async () => ({ deepen: [{ dimension: 'technical', depth: 'standard', rationale: 'one more pass' }], rejected: [], reasoning: 'more evidence needed', matrix: [] }),
    'add-dimensions': async () => { throw new Error('add-dimensions must NOT be called in this fixture'); },
    projection: async (a) => ({ ok: true, reportPath: 'reports/repair-disclosure-eval-topic/report.md', reportId: 'urn:mif:concept:repair-disclosure-eval-topic:report', mifLevel: 3, checksAddressed: ['finding_valid'], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
  completionCheck: (roundNo) => {
    if (roundNo === 1) return { met: [{ id: 'finding_valid', evidence: 'ajv passes now; 3 finding(s) were repaired this round before grading' }], unmet: [{ id: 'other_check', why: 'not yet satisfied' }], boundHit: false };
    return { met: [
      { id: 'finding_valid', evidence: 'ajv passes; 0 findings needed repair this round' },
      { id: 'other_check', evidence: 'now satisfied' },
    ], unmet: [], boundHit: false };
  },
};
NODE

if ! node "$TMP/driver.cjs" "$WF" "$TMP/args.json" "$TMP/stubs.cjs" "$TMP/out.json" >"$TMP/run.err" 2>&1; then
  note "driver run failed: $(cat "$TMP/run.err")"
  fail=1
fi

if [ -f "$TMP/out.json" ]; then
  python3 - "$TMP/out.json" <<'PY'
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

check('module did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}

round1 = next((c for c in d['agentCalls'] if c['label'] == 'check:round-1'), None)
round2 = next((c for c in d['agentCalls'] if c['label'] == 'check:round-2'), None)
check('round 1 completion-check prompt exists', round1 is not None)
check('round 2 completion-check prompt exists', round2 is not None)

if round1:
    check("round 1's prompt discloses the TRUE repair count (3) to the independent evaluator",
          'repaired 3 schema-invalid' in round1['prompt'], round1['prompt'][:400])
    check("round 1's prompt names #623 explicitly (not a generic unexplained instruction)",
          'research-harness-template#623' in round1['prompt'])
if round2:
    check("round 2's prompt discloses 0 repairs (a clean round is never misreported as repaired)",
          'repaired 0 schema-invalid' in round2['prompt'], round2['prompt'][:400])

check('run report surfaces the accumulated repair total across both rounds (3 + 0 = 3), independent of what the model did with the disclosure',
      r.get('repaired') == 3, str(r.get('repaired')))
check('result.done is true (round 2 finally reported zero unmet)', r.get('done') is True, str(r.get('done')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "no out.json produced"
  fail=1
fi

[ "$fail" -eq 0 ] && note "the independent completion evaluator's prompt now discloses the REAL per-round repair count computed by research-fanout.js (never a generic or omitted figure), names #623 so the instruction is traceable, and the run's own final report exposes the accumulated repair total deterministically -- so a corpus that arrived heavily defective can no longer be mistaken for one that was clean from the start, whether or not the live model heeds the disclosure text itself (a genuine, documented, non-deterministic gap this eval cannot close)"
exit "$fail"
