// research-coverage-audit.js — atomic action Z of the research pipeline
// (corpus audit: multi-modal sweep + completeness critic).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573/#578/#582/#586/#590
// precedent.
//
// Vendored from the workspace engine reference (Epic #549, Task #595). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569/#573/#578/#582/#586/#590 precedent) — the
// reference's own default (a workspace-relative
// 'repos/research-harness-template' path) does not apply inside the
// instance/template itself.
//
// CONFIRMED DELEGATION GAP — same class as #543-#548's findings, fixed
// here. The reference implementation's `thin-dimensions` and `staleness`
// auditor briefs re-derive their judgments FREEHAND: a bare agent probe
// reading raw finding files, instead of invoking the deterministic jq
// pipelines this repo's own `discover` skill (.claude/skills/discover/
// SKILL.md) already ships for exactly these two signals. The fix wires
// both briefs to those exact pipelines — adapted to this module's
// topic-scoped operation (goal.json's dimensions[], the same
// research-augment.js Assess-phase adaptation already established for the
// identical corpus-wide-vs-topic-scoped mismatch, #578/#580) rather than
// discover's own corpus-wide harness.config.json taxonomy:
//
//   thin-dimensions delegates to discover's `--gaps` pipeline (group_by
//   over research-index.json, cross-referenced against the topic's
//   goal.json dimensions[] instead of harness.config.json's corpus-wide
//   list) for the count portion; the auditor's own judgment layers on top
//   (weight relative to each dimension's share of the goal's completion
//   checks — a signal discover's own --gaps output does not carry).
//
//   staleness delegates to discover's TWO --stale pipelines verbatim: the
//   verdict-based `select(.verdict != "survived" and .verdict != null)`
//   filter over research-index.json, and the age-based
//   `[.["@id"], (.created // "n/a")] | @tsv` extraction over the raw
//   finding files (research-index.json carries no timestamp, exactly as
//   discover's own README states). The auditor's own judgment layers
//   recent-event awareness on top — a time-sensitive claim can be stale
//   even when young, which neither pipeline alone can see.
//
// The other four auditors (quarantine-review, graph-orphans,
// check-traceability, homeless-leads) have NO discover equivalent —
// confirmed by reading discover's SKILL.md in full — and are correctly
// left as novel blind probes; forcing a delegation onto them would be
// inventing a correspondence that does not exist.
//
// MODULE-REFERENCE CORRECTION (verified against the real vendored source
// on `main`, not assumed — planning's initial claim that the routed
// backlog's `target` field maps UNIFORMLY to all five downstream modules'
// args with no adapter was false and has been corrected):
//
//   research-augment.js      { harnessDir, topic, focusHint?, checkCoverage? }
//     — focusHint accepts "a dimension or unmet check ids"; a backlog
//       target string maps here reasonably directly.
//   research-add-dimensions.js { harnessDir, topic, hints?: string[], leads? }
//     — hints is an ARRAY; a single target string needs wrapping ([target]).
//   research-falsify.js      { harnessDir, topic, scope?: 'all' | 'dimension:<d>' | { paths?, ids? } }
//     — scope is a tagged union, none of which is a bare string; routing
//       requires constructing one of these shapes from what the backlog
//       item actually references.
//   research-import.js       { harnessDir, topic, containerDir: string }
//     — containerDir is REQUIRED and names a real exported MIF package
//       directory (as produced by /export). Nothing in an audit's corpus
//       scan can produce one from scratch — a backlog item routed to
//       `import` signals "go obtain an external export," not a ready target.
//   research-projection.js   { harnessDir, topic, synthesisPath, slug?, genre? }
//     — synthesisPath is a same-process-only ephemeral handle from a
//       preceding research-synthesis.js call (confirmed in that module's
//       own header: no cross-process survival guarantee). An audit run in
//       isolation has no live synthesisPath — routing to `projection` means
//       "re-run synthesis, then projection," not a direct call.
//
// Per the architecture doc's own flowchart, `research-pipeline.js`'s
// `mode: audit` returns a BACKLOG REPORT — it does not auto-dispatch. The
// routed backlog this module emits is therefore a human/orchestrator-
// readable ROUTING SIGNAL: it correctly names the next workflow, but
// translating a backlog item's generic `target` into that workflow's own
// args is a translation step this module deliberately does NOT build (see
// the Prioritize phase prompt and BACKLOG_SCHEMA below, where this
// distinction is restated for a future consumer — most likely #550, the
// not-yet-vendored orchestrator — so it is not silently assumed away).
export const meta = {
  name: 'research-coverage-audit',
  description: 'Atomic action Z (corpus audit): multi-modal sweep — six blind auditors each probe the corpus a different way (thin dimensions, staleness, quarantine, graph orphans, check-evidence traceability, homeless leads), a completeness critic asks what no auditor covered, and a prioritizer emits a typed backlog routing each item to the workflow that fixes it (augment / add-dimensions / falsify / import / projection) — target is a routing signal, not a directly-forwardable arg; the translation into each destination module\'s own args shape is left to the consumer',
  whenToUse: 'Between rounds when checks remain unmet, on a schedule against a long-lived corpus, or before trusting a corpus for a deliverable',
  phases: [
    { title: 'Sweep', detail: 'six parallel blind auditors, one probe modality each — thin-dimensions/staleness delegate their count/verdict/age computation to the discover skill\'s own jq pipelines' },
    { title: 'Critique', detail: 'completeness critic: what is missing that no auditor ran', model: 'sonnet' },
    { title: 'Prioritize', detail: 'deterministic merge + ranked, routed backlog', model: 'sonnet' },
  ],
}

// research-harness-template#654: normalize a top-level standalone Workflow-tool
// invocation. `args` arrives as a JSON-encoded STRING when this module is
// invoked directly at the top level (confirmed empirically -- issue #617),
// but as a real in-process object when composed as a nested child via
// research-pipeline.js's wf() helper. research-pipeline.js already guards
// its own external entry point for this; every atomic module is ALSO a
// valid direct entry point and needs the identical guard -- this was #654's
// actual root cause: `args` was a JSON string, so `args.topic` (or any
// other args.* property) silently read `undefined` (a string property
// access, never a thrown error) rather than the real value, and the very
// next `if (!TOPIC) throw` line fired even though the caller's `topic`
// argument was genuinely present in the call.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})

// args: { harnessDir, topic, leads?: [{from, lead}] (accumulated crossDimensionLeads),
//         checkCoverage?: [] (latest synthesis perCheck grades) }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
if (!TOPIC) throw new Error('research-coverage-audit: args.topic is required')
const RDIR = `${H}/reports/${TOPIC}`

const AUDIT_SCHEMA = {
  type: 'object',
  properties: {
    modality: { type: 'string' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          finding: { type: 'string', description: 'what is wrong/missing, concretely' },
          target: { type: 'string', description: 'dimension id, finding @id, check id, or file the item is about' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['finding', 'target', 'severity'],
      },
    },
  },
  required: ['modality', 'items'],
}
const CRITIC_SCHEMA = {
  type: 'object',
  properties: {
    uncoveredAngles: { type: 'array', items: { type: 'string' } },
    extraItems: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          finding: { type: 'string' },
          target: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['finding', 'target', 'severity'],
      },
    },
  },
  required: ['uncoveredAngles', 'extraItems'],
}
// `target` is a routing signal, NOT a directly-forwardable arg — see the
// MODULE-REFERENCE CORRECTION comment at the top of this file. In
// particular: `import` and `projection` items name the workflow that
// WOULD fix the item, but this module cannot supply that workflow's
// required args (a real containerDir; a live synthesisPath) from a corpus
// scan alone — a consumer must translate (or, for those two actions,
// obtain the missing input out-of-band) before calling the named workflow.
const BACKLOG_SCHEMA = {
  type: 'object',
  properties: {
    backlog: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          action: { type: 'string', enum: ['augment', 'add-dimensions', 'falsify', 'import', 'projection', 'manual'] },
          target: { type: 'string' },
          why: { type: 'string' },
          priority: { type: 'integer', minimum: 1 },
        },
        required: ['action', 'target', 'why', 'priority'],
      },
    },
    summary: { type: 'string' },
  },
  required: ['backlog', 'summary'],
}

const COMMON = `Corpus: harness ${H}, topic ${TOPIC} — findings under ${RDIR}/findings/ (quarantine/, archive/ siblings), goal at ${RDIR}/goal.json, graph at ${RDIR}/knowledge-graph.json if present. You are ONE blind auditor in a panel; probe ONLY your modality, concretely (real ids/paths/counts), and return items even when small — an empty list means you verified there is genuinely nothing, and you say how you verified it.`

const AUDITORS = [
  {
    key: 'thin-dimensions',
    model: 'haiku',
    brief:
      'Coverage thinness. DELEGATE the count portion to the same deterministic jq pipeline the harness\'s own discover skill ' +
      '(.claude/skills/discover/SKILL.md) uses for its --gaps signal, adapted to this topic\'s own goal.json dimensions[] ' +
      '(not harness.config.json\'s corpus-wide taxonomy — this audit is scoped to one topic) — never re-derive these counts ' +
      'by reading and eyeballing raw finding files:\n' +
      `  jq -n --slurpfile goal ${RDIR}/goal.json --slurpfile idx ${RDIR}/research-index.json '\n` +
      '    ($idx[0].findings | group_by(.dimension) | map({(.[0].dimension // "unassigned"): length}) | add) as $counts\n' +
      "    | $goal[0].dimensions | map({dimension: ., findings: ($counts[.] // 0)})'\n" +
      'Run this exactly (adjust only for jq availability). Then judge, per dimension: is the surviving evidence thin in ' +
      'absolute terms, or relative to how much of the goal\'s completion_condition.checks[] that dimension is supposed to ' +
      'carry (read goal.json\'s checks — a dimension backing 3 checks with 2 findings is thinner than one backing 1 check ' +
      'with 2 findings, even though the raw counts match)? Flag any dimension whose surviving evidence cannot plausibly ' +
      'support the checks it is meant to.',
  },
  {
    key: 'staleness',
    model: 'haiku',
    brief:
      'Staleness. DELEGATE both signals to the same jq pipelines the harness\'s own discover skill ' +
      '(.claude/skills/discover/SKILL.md) uses for its --stale output — never guess at age or verdict by eyeballing files:\n' +
      '  1. Verdict-based (epistemically stale regardless of age):\n' +
      `     jq '[ .findings[] | select(.verdict != "survived" and .verdict != null) ]' ${RDIR}/research-index.json\n` +
      '  2. Age-based (research-index.json carries no timestamp, so read the raw finding files):\n' +
      `     jq -r '[ .["@id"], (.created // "n/a") ] | @tsv' ${RDIR}/findings/*.json | sort -k2\n` +
      'Run both exactly (adjust only for jq availability). Then layer your own judgment on top of those two deterministic ' +
      'lists: findings whose evidence or verification is old relative to how fast their subject moves, and time-sensitive ' +
      'claims verified before recent events that could have superseded them — a signal neither pipeline alone can see. ' +
      'Use created/attempted_at fields, not guesses.',
  },
  { key: 'quarantine-review', model: 'haiku', brief: 'Quarantine ledger: what sits in quarantine/, why, and whether any falsification basis has plausibly expired (the disconfirming source itself superseded). Quarantined items are candidates for re-examination, never for silent restoration.' },
  { key: 'graph-orphans', model: 'haiku', brief: 'Graph connectivity: findings mentioned by no relationship edge, concepts/entities with a single edge, and relationship types that are suspiciously absent (a corpus of N findings with near-zero contradicts/refines edges is unlinked, not harmonious).' },
  { key: 'check-traceability', model: 'sonnet', brief: 'Check-evidence traceability: for each goal completion check, walk the corpus and list which surviving finding @ids actually bear on it. Flag checks resting on zero or one finding, and checks whose supporting evidence is all weakened/inconclusive.' },
  { key: 'homeless-leads', model: 'sonnet', brief: 'Homeless evidence: leads recorded by analysts that fit no declared dimension (provided below if any), plus any finding whose dimension pin looks like a force-fit. These are the raw signal for add-dimensions.' },
]

phase('Sweep')
const sweeps = await parallel(
  AUDITORS.map((a) => () =>
    agent(
      `${COMMON}\nMODALITY: ${a.key}. ${a.brief}` +
        (a.key === 'homeless-leads' && A && A.leads && A.leads.length ? `\nRecorded leads: ${JSON.stringify(A.leads)}` : '') +
        (a.key === 'check-traceability' && A && A.checkCoverage ? `\nLatest synthesis check grades: ${JSON.stringify(A.checkCoverage)}` : ''),
      { label: `audit:${a.key}`, phase: 'Sweep', model: a.model, schema: AUDIT_SCHEMA },
    ),
  ),
)
const found = sweeps.filter(Boolean)
const allItems = found.flatMap((s) => s.items.map((i) => ({ ...i, modality: s.modality })))
log(`Sweep: ${allItems.length} item(s) across ${found.length}/${AUDITORS.length} auditors`)

phase('Critique')
const critic = await agent(
  `Completeness critic for a corpus audit (harness ${H}, topic ${TOPIC}). The panel ran these modalities: ${AUDITORS.map((a) => a.key).join(', ')} and produced: ${JSON.stringify(allItems.slice(0, 60))}${allItems.length > 60 ? ` (+${allItems.length - 60} more)` : ''}.\n` +
    `Ask: what is missing that NO auditor probed — a modality not run (citation rot? contradiction density? ontology-pin drift? concordance drift across topics?), a claim every auditor implicitly trusted, a corpus surface nobody opened? Spot-check the corpus for your top 2 suspicions and return concrete extraItems for what you actually find (not hypotheticals).`,
  { label: 'audit:critic', model: 'sonnet', schema: CRITIC_SCHEMA },
)
const merged = allItems.concat(((critic && critic.extraItems) || []).map((i) => ({ ...i, modality: 'critic' })))

phase('Prioritize')
const prioritized = await agent(
  `Turn audit items into a ROUTED backlog (harness ${H}, topic ${TOPIC}). Items: ${JSON.stringify(merged)}\n` +
    `Route each to the workflow that fixes it: augment (thin/weak evidence on an existing dimension) | add-dimensions (homeless leads, force-fit pins) | falsify (ungated or expired-basis findings needing [re-]gating) | import (evidence known to exist elsewhere) | projection (stale derived surfaces: README counts, graph, report of record) | manual (needs a human decision — say what decision). Merge duplicates that route to the same action+target. Rank by priority (1 = first): unmet-check impact first, then severity, then cheapness. ` +
    `NOTE for the caller: target is a routing signal naming what the item is about (a dimension id, finding @id, check id, or file) — it is NOT a ready arg value for the destination workflow. In particular, import needs a real containerDir (an actual export directory, which this audit cannot produce) and projection needs a live synthesisPath from a just-run synthesis (which this audit does not have) — route these two as "go obtain/produce X, then call Y," never as a directly-callable target. Return the backlog and a 3-sentence summary.`,
  { label: 'audit:prioritize', model: 'sonnet', schema: BACKLOG_SCHEMA },
)

return {
  backlog: (prioritized && prioritized.backlog) || [],
  summary: prioritized ? prioritized.summary : 'prioritizer failed; raw items returned',
  rawItems: merged,
  uncoveredAngles: (critic && critic.uncoveredAngles) || [],
}
