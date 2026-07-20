// research-deliverables.js — atomic step 6 of the research pipeline
// (deliverable genres).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569 precedent.
//
// Vendored from the workspace engine reference (Epic #544, Task #573). This
// is a genuine ADAPTATION of the reference script, not a drop-in port.
// In-repo default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569 precedent).
//
// RESOLVED DESIGN DECISION — BOTH rendering mechanisms, not one (this
// EXPANDS the reference implementation's own "recommended scope" of
// artifact-based-only; the epic owner explicitly chose the larger scope).
// The real substrate is NOT a uniform genre×channel render matrix — it has
// TWO disjoint mechanisms, verified against the actual scripts/SKILL.md
// files (not guessed from the reference's prose):
//
//   MECHANISM 1 — ARTIFACT-BASED (channels: blog, book). A genre pack
//   (schemas/artifact.schema.json's `genre` field — academic, engineering,
//   exec-summary, … from harness.config.json packs[], `kind: "genre"`)
//   feeds `scripts/synthesize-artifact.sh <findings-dir> <genre> <out.json>`
//   (deterministic, delegates to the mif-rh-cli engine), whose output
//   `scripts/render-artifact.sh <artifact.json> <report|blog|book> <out>`
//   renders. This is exactly the publish-blog / book:book-author skills'
//   OWN pipeline (`.claude/skills/publish-blog/SKILL.md`,
//   `packs/channels/book/skills/book-author/SKILL.md`) — this module
//   delegates to the identical two scripts rather than reimplementing their
//   logic via free-form prompting, matching the #543/#569 precedent
//   (research-projection.js's own resolved script-delegation gap).
//   `channel="report"` is deliberately EXCLUDED from this module's own
//   servable set (see "report channel is out of scope" below) — this
//   module covers `blog`/`book` only.
//
//   MECHANISM 2 — SOURCE-DIRECT CHANNEL PACKS (pdf, jats, xbrl, ectd,
//   notebooklm, github-discuss, github-issues). Per
//   `docs/reference/packs/channels.md`'s own provenance/citation-grounding
//   audit and each pack's own `SKILL.md`/`plugin.json` (read individually,
//   not guessed): these are explicitly built "directly FROM THE SOURCES —
//   the findings corpus and its primary-source citations — NEVER from a
//   rendered report/artifact." There is no dedicated backing SCRIPT for
//   these the way mechanism 1 has synthesize-artifact.sh/render-artifact.sh
//   — each pack's real invocation mechanism is its own Claude Code Skill
//   (`Skill(<pack>:<pack>)`, e.g. `Skill(pdf:pdf)`), which itself reads the
//   findings dir directly and composes its own output per its own
//   argument-hint. There is no "genre" axis here at all (pdf's own
//   argument-hint takes `<findings-dir> [-o <output.pdf>] [<topic-name>]`,
//   no genre parameter) — a genre requested alongside one of these channels
//   does not apply and is reported as ignored, never silently honored.
//
// A THIRD (and arguably fourth) mechanism shape exists and is EXPLICITLY OUT
// OF SCOPE for this Task, not silently folded into either of the two named
// above: `diataxis` (per-finding Diátaxis page generation via its own
// `render-diataxis.sh`, an entirely different fan-out-per-finding shape) and
// `ai-spec` (a channel that itself consumes a DIFFERENT genre family —
// `ai-architecture-doc`/`kiro-requirements`/`kiro-design`/`kiro-tasks`/
// `feature-spec`, per `docs/reference/packs/genres.md`, none of which render
// through blog/book/report at all). Requesting either lands in
// `unavailable[]` naming this explicitly as a third mechanism this module
// does not cover — never silently mapped onto mechanism 1 or 2.
//
// SYNTHESIS-ONLY EVIDENCE RULE APPLIES TO MECHANISM 1 ONLY. The Task's own
// acceptance criteria state "rendered artifact carries only claims present
// in the synthesis... no fresh research or raw findings" — but
// synthesize-artifact.sh reads the FINDINGS DIR directly (never the
// synthesis file), exactly like research-projection.js's own Report phase.
// Mirroring that established precedent, `synthesisPath` is required and
// preflight-checked (same-process contract, verbatim from
// research-projection.js — see PREFLIGHT below) and used as a
// cross-check: after synthesize-artifact.sh produces the artifact, the
// Render phase agent verifies the artifact's claims trace to what the
// synthesis already established, never introducing content the synthesis
// excluded. Mechanism 2 is the OPPOSITE by explicit design of its own
// packs ("never a rendered report/artifact" is those packs' own
// non-negotiable) — applying the synthesis-only rule there would violate
// their own documented contract, so synthesisPath is deliberately UNUSED for
// source-direct rows; this is a real, load-bearing distinction, not an
// inconsistency.
//
// OUTPUT PATH COLLISIONS — an adaptation, not carried from the reference.
// Every artifact-mechanism render lands under reports/<topic>/, never a
// top-level blog/ or book/ directory (research-harness-instance decision:
// nothing this harness produces lives outside reports/<topic>/, full stop —
// blog/book remain real channel CONCEPTS, just never a separate top-level
// output tree). publish-blog's own convention is the single path
// `reports/<topic>/<topic>.blog.md`; book-author's is
// `reports/<topic>/book/chapters/<n>.md` (numeric chapter index, nested
// under the topic's own reports directory rather than a parallel top-level
// tree). Neither supports rendering MULTIPLE genres for the same topic
// without collision, which is this module's whole point (N genre×channel
// pairs in one run). Genre-suffix blog output exactly the way
// render-artifact.sh's own header comment already documents doing for the
// report channel ("<slug>.engineering.md"): `reports/<topic>/<topic>.blog.md`
// for the neutral/general genre (preserves the existing single-genre
// convention unchanged), `reports/<topic>/<topic>.<genre>.blog.md`
// otherwise — the trailing `.blog.md` (not a leading `blog.` prefix) keeps
// this collision-free against the report channel's own
// `reports/<topic>/<topic>.<genre>.md` genre files. book-author's numeric
// `<n>` chapter slot doesn't map cleanly onto "N independent genre-shaped
// chapters" — this module uses the genre string itself as the chapter slug
// instead of a numeric index: `reports/<topic>/book/chapters/<genre>.md`.
// The synthesize-artifact intermediate is likewise genre-suffixed
// (`artifact.<genre>.json`) so parallel rows for the same topic never race
// on one shared temp file.
//
// ENGINE REQUIREMENT: synthesize-artifact.sh / render-artifact.sh hard-
// require the mif-rh-cli engine (ADR-0016) — scripts/fetch-engine.sh,
// mif-rh-cli on PATH, or MIF_RH_CLI. Known open infra bug #567 (verify.sh's
// --gates ENGINE resolution runs before gate filtering) is orthogonal to
// this module's own runtime behavior — this module never calls verify.sh
// itself — and is out of scope for this Task; work around it locally with
// scripts/fetch-engine.sh, never silently.
//
// WITNESSED PROVENANCE — mechanism 1 only, never mechanism 2 (#632, same
// gap research-projection.js closed for the report channel). render-
// artifact.sh's own header states blog/book carry MIF Level-1 frontmatter
// (a real @context/@type/@id/conceptType/created concept), so mif-docs-
// plugin's mif-provenance skill can stamp them exactly like the report
// channel — added as a step in the artifact-mechanism Render prompt below.
// Mechanism 2 (source-direct channel packs: pdf, jats, xbrl, ectd,
// notebooklm, github-discuss, github-issues) is explicitly OUT OF SCOPE for
// this stamp: each pack owns its own output format and invocation
// (Skill(<pack>:<pack>)) with no dedicated backing script this module
// controls, several formats aren't even MIF-frontmatter-bearing markdown
// (PDF, XBRL), and stamping an output this module didn't itself render
// would be presumptuous about a contract only the pack's own SKILL.md can
// state. Every mechanism-2 render therefore reports
// provenanceOutcome="not-applicable" with that reason, matching this
// module's own established convention of naming scope explicitly rather
// than silently doing something inconsistent (see OUT_OF_SCOPE_CHANNELS
// above).
//
// GENRE SKILL INVOCATION GAP — closed, not carried forward
// (research-harness-template#640, same class as research-projection.js's
// #633). This module's mechanism-1 (artifact-based, blog/book) Render step
// previously passed the resolved genre straight through to
// synthesize-artifact.sh/render-artifact.sh as pass-through metadata and
// never invoked any genre's real Skill(<genre>:<genre>) template — every
// genre rendered the identical genre-neutral body with only the frontmatter
// `genre:` field differing, indistinguishable from a correctly-genred
// deliverable by inspection. Unlike research-projection.js, this module
// ALREADY has a dedicated Route phase that resolves genre×channel
// servability (pack enablement, methodology-vs-genre, out-of-scope
// third-mechanism/architectural-boundary channels) BEFORE Render ever runs
// — so, unlike #633's fix, no separate per-row enablement re-check is
// needed in Render: a genre reaching route.plan with mechanism="artifact"
// and genre!=="general" already has its own pack confirmed enabled by
// Route. The Render step therefore only needed a new step (see step 4 in
// the artifact-mechanism prompt below) that invokes
// Skill(<genre>:<genre>) on the rendered body — built from the same
// artifact claims steps 1-3 already established, never inventing new
// content, never touching the citation/References section render-
// artifact.sh already wrote — whenever genre!=="general", and reports the
// outcome via `genreApplied`/`genreSkillInvoked` instead of leaving it
// silently cosmetic. `genre="general"` (the default, or the Route-resolved
// fallback for a would-be-unavailable request) needs no skill invocation —
// it is definitionally the neutral render, `genreApplied=false`. Mechanism
// 2 (source-direct channel packs) has no genre axis at all (see
// MECHANISM 2 above) — those rows always report `genreApplied=false,
// genreSkillInvoked=""`, matching their existing "genre does not apply,
// ignore it" handling. A caller-supplied `p.genre` is validated against
// the same `^[a-z][a-z0-9-]*$` pack-name pattern
// harness.config.schema.json enforces (mirrors #633's own injection guard)
// before it is interpolated into either a shell command argument or a
// Skill() reference, below — never proceeding with an unvalidated string
// in either position.
export const meta = {
  name: 'research-deliverables',
  description: 'Atomic step 6 (deliverable genres): routing workflow covering BOTH real rendering mechanisms — artifact-based (synthesize-artifact.sh -> render-artifact.sh for blog/book, delegated never free-form-authored) and source-direct channel packs (pdf/jats/xbrl/ectd/notebooklm/github-discuss/github-issues, each invoked as its own Skill directly against findings, never through a rendered artifact); a requested pair whose backing pack/script is not enabled or whose mechanism this module does not cover reports via unavailable[] with a reason naming which mechanism and what is missing, never silently dropped',
  whenToUse: 'After projection — produces the optional deliverables (blog post, book chapter, exec-summary, engineering report, academic, briefing, PDF, JATS, …) from the same synthesis the report of record used',
  phases: [
    { title: 'Route', detail: 'requested genre×channel pairs vs harness.config.json packs[] + .claude/settings.local.json enabledPlugins ("<pack>@research-harness" key shape) → mechanism-tagged render plan; unavailable pairs get a reason naming the mechanism and what is missing', model: 'haiku' },
    { title: 'Render', detail: 'mechanism 1: synthesize-artifact.sh -> render-artifact.sh per genre×channel row, synthesis cross-checked, then Skill(<genre>:<genre>) applied to the body when genre!=="general" (#640; no separate re-check needed, Route already confirmed pack enablement), then Skill(mif-docs:mif-provenance) witnessed-provenance stamp (ADR-0018, #632; declines gracefully when capture is off); mechanism 2: Skill(<pack>:<pack>) invoked directly against findings, synthesis never consulted, no genre axis (genreApplied always false), provenance stamp explicitly not-applicable (each pack owns its own output/format)', model: 'sonnet' },
    { title: 'Check', detail: 'per-artifact lint (where markdown) + frontmatter/citation-leak conformance + ≥1 citation', model: 'haiku' },
  ],
}

// args: { harnessDir, topic, synthesisPath, genres?: string[] (e.g. ['exec-summary','engineering']),
//         channels?: string[] (default ['blog'] ONLY when the arg is absent/not an array; an
//         explicit [] is honored as "render zero channels", never coerced to the default — #626;
//         may mix artifact-based (blog/book) and source-direct
//         (pdf/jats/xbrl/ectd/notebooklm/github-discuss/github-issues) channels) }
const H = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
const SYN = args && args.synthesisPath
if (!TOPIC) throw new Error('research-deliverables: args.topic is required')
if (!SYN) throw new Error('research-deliverables: args.synthesisPath is required (mechanism-1 rows cross-check the synthesis-only evidence rule against it — see module header)')
const RDIR = `${H}/reports/${TOPIC}`
const GENRES = (args && args.genres) || []
// research-harness-template#626: Array.isArray, not truthiness. The prior
// `args.channels && args.channels.length` collapsed an explicit `channels:
// []` ("render nothing, on purpose") into the same branch as `channels`
// never being passed at all ("caller didn't ask, use the default") — both
// fell through to the ['blog'] default, silently overriding an explicit
// empty answer. An explicit array (even empty) must be honored verbatim;
// only an actually-absent/non-array `channels` gets the ['blog'] default.
const CHANNELS = (args && Array.isArray(args.channels)) ? args.channels : ['blog']

// Static pack taxonomy, cross-checked by evals/deliverables-route-check.sh
// against the real docs/reference/packs/index.md "Pack inventory" table
// (kind column) so a drift between this table and the real docs is a caught
// regression, never a silent guess.
const ARTIFACT_CHANNELS = ['blog', 'book'] // channel="report" is research-projection's job, not this module's — see header
const SOURCE_DIRECT_CHANNELS = ['pdf', 'jats', 'xbrl', 'ectd', 'notebooklm', 'github-discuss', 'github-issues']
const OUT_OF_SCOPE_CHANNELS = ['diataxis', 'ai-spec'] // real third-mechanism channels, deliberately not covered — see header
// Genre packs (kind:"genre") that render through blog/book via mechanism 1.
// consumingChannel:'ai-spec' entries are genre packs whose SOLE real
// consuming channel is ai-spec (docs/reference/packs/genres.md) — requesting
// one against blog/book gets a precise reason, never a generic "unknown
// genre" miss.
const GENRE_PACKS = {
  academic: {}, briefing: {}, 'computing-paper': {}, engineering: {}, 'exec-summary': {}, 'trend-analysis': {},
  'clinical-submission': {}, 'legal-memo': {}, 'regulatory-disclosure': {}, 'sustainability-report': {},
  'humanities-chicago': {}, 'humanities-mla': {}, 'security-pentest': {}, 'market-research-report': {},
  'systematic-review': {}, 'compliance-audit': {}, 'competitive-quadrant': {}, 'nist-sp': {},
  'ai-architecture-doc': { consumingChannel: 'ai-spec' },
  'kiro-requirements': { consumingChannel: 'ai-spec' },
  'kiro-design': { consumingChannel: 'ai-spec' },
  'kiro-tasks': { consumingChannel: 'ai-spec' },
  'feature-spec': { consumingChannel: 'ai-spec' },
}
// Methodology packs (kind:"methodology") — dimension/analyst skills, NEVER a
// deliverable genre template, even though harness.config.json enables three
// of them (competitive-analysis, market-sizing, trend-modeling) alongside
// the real genre packs in the same packs[] array with no distinguishing
// field of their own.
const METHODOLOGY_PACKS = ['competitive-analysis', 'customer-research', 'financial-analysis', 'market-sizing', 'regulatory-review', 'trend-modeling', 'continuous-monitor']

const ROUTE_SCHEMA = {
  type: 'object',
  properties: {
    plan: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          genre: { type: 'string', description: "'general' for a neutral artifact-based render, '-' for a source-direct channel (no genre axis applies)" },
          channel: { type: 'string' },
          mechanism: { type: 'string', enum: ['artifact', 'source-direct'] },
          templateSource: { type: 'string', description: 'the enabled pack providing the genre template (mechanism 1) or the channel pack skill (mechanism 2)' },
          outputHint: { type: 'string' },
        },
        required: ['genre', 'channel', 'mechanism', 'templateSource', 'outputHint'],
      },
    },
    unavailable: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          requested: { type: 'string' },
          reason: { type: 'string', description: 'must name which mechanism (artifact-based / source-direct / out-of-scope third-mechanism / architectural-boundary) and exactly what is missing or unsupported' },
        },
        required: ['requested', 'reason'],
      },
    },
  },
  required: ['plan', 'unavailable'],
}
const RENDER_SCHEMA = {
  type: 'object',
  properties: {
    outputPath: { type: 'string' },
    genre: { type: 'string' },
    channel: { type: 'string' },
    mechanism: { type: 'string', enum: ['artifact', 'source-direct'] },
    citationsCount: { type: 'integer', description: 'distinct citations the rendered output carries (finding-traced for mechanism 1, primary-source for mechanism 2)' },
    genreApplied: { type: 'boolean', description: '(#640) true only if the Render step actually invoked Skill(<genre>:<genre>) and restructured the body per that genre\'s template; false when genre="general" (mechanism 1) or for every mechanism-2 row (no genre axis) — never true for a genre whose template was not actually applied' },
    genreSkillInvoked: { type: 'string', description: '(#640) the "<genre>:<genre>" Skill reference actually invoked, or "" when genreApplied is false' },
    provenanceOutcome: { type: 'string', enum: ['stamped', 'declined', 'error', 'not-applicable'], description: 'result of the Skill(mif-docs:mif-provenance) stamp attempt (#632) for mechanism 1 rows; "not-applicable" for mechanism 2 rows (each pack owns its own output/format, see module header) — "declined" is expected/healthy when capture is off or the session ledger never witnessed this file, never a render failure' },
    provenanceReason: { type: 'string', description: 'why declined/error/not-applicable, or "witnessed" when stamped' },
  },
  required: ['outputPath', 'genre', 'channel', 'mechanism', 'citationsCount', 'genreApplied', 'genreSkillInvoked', 'provenanceOutcome', 'provenanceReason'],
}
const CHECK_SCHEMA = {
  type: 'object',
  properties: {
    clean: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'string' } },
  },
  required: ['clean', 'problems'],
}
const PREFLIGHT_SCHEMA = {
  type: 'object',
  properties: {
    exists: { type: 'boolean' },
    reason: { type: 'string', description: 'why exists=false, or a one-word "ok" when true' },
  },
  required: ['exists', 'reason'],
}

// Shared Check-phase prompt — used both for the initial post-render
// validation and for the re-validation that follows an attempted fix, so
// both passes apply the identical criteria (write-validate atomicity).
const checkPrompt = (outputPath, mechanism, genre, channel) =>
  `Validate the deliverable ${outputPath} (harness ${H}, mechanism="${mechanism}"). If the output is Markdown, run ` +
  `markdownlint-cli2 with the repo config. Confirm the citation-leak gate holds regardless of format (no ${mechanism === 'artifact' ? 'urn:mif: ids, finding handles, or reports/<slug>/ paths — public citations only' : 'internal research identity leaking into a channel whose contract says it renders from public sources'}). ` +
  `Confirm it cites at least one primary source (a deliverable citing zero sources is a defect for "${genre}"×"${channel}"). ` +
  `Report problems verbatim; fix nothing.`

phase('Route')

// Same-process contract guard, verbatim from research-projection.js (#571,
// Epic #543): research-synthesis.js's synthesisPath hand-off is SAME-
// PROCESS-ONLY (no cleanup trap, no cross-process survival guarantee). Only
// mechanism-1 rows consult SYN (see header), but the preflight itself runs
// unconditionally before Route, since Route's own plan can't yet know which
// rows will be mechanism 1 — failing closed here is cheaper than failing
// mid-Render on a row that turns out to need it.
const preflight = await agent(
  `SAME-PROCESS CONTRACT CHECK. research-synthesis.js's synthesisPath hand-off is explicitly SAME-PROCESS-ONLY (no cleanup trap installed, but also no cross-process survival guarantee — its own header states a consumer must read the file before that process exits). Before this module trusts ${SYN}, verify all three: (1) the file exists (test -f), (2) it is non-empty (test -s), (3) it parses as valid JSON (jq empty). Return exists=true ONLY if all three hold; otherwise exists=false with a one-sentence reason naming which check failed (e.g. "file missing", "empty file", "invalid JSON").`,
  { label: 'deliverables:preflight', model: 'haiku', effort: 'low', schema: PREFLIGHT_SCHEMA },
)
if (!preflight || !preflight.exists) {
  throw new Error(
    `research-deliverables: synthesisPath "${SYN}" is not usable (${preflight ? preflight.reason : 'preflight check itself failed'}). ` +
      `The ephemeral-output contract is SAME-PROCESS-ONLY — this module must be composed in the SAME process as the research-synthesis ` +
      `call that produced it. Re-run research-synthesis and consume its synthesisPath in the same pipeline run — do not retry this ` +
      `module standalone against a stale path.`,
  )
}

const route = await agent(
  `Build the deliverables render plan for topic ${TOPIC}, harness ${H}. Requested channels: ${JSON.stringify(CHANNELS)}; requested genres: ${JSON.stringify(GENRES)} (empty = neutral artifact-based renders only, genre="general").\n\n` +
    `THIS MODULE COVERS EXACTLY TWO REAL RENDER MECHANISMS — classify every requested channel into one before considering genre:\n` +
    `1. ARTIFACT-BASED (channels ${JSON.stringify(ARTIFACT_CHANNELS)} only — "report" is EXCLUDED, see below): a genre pack feeds ` +
    `scripts/synthesize-artifact.sh -> scripts/render-artifact.sh. "blog" is core/always-on (no pack gates the CHANNEL itself, only ` +
    `an explicitly requested genre needs its own pack enabled). "book" is itself an optional CHANNEL PACK — check that the "book" pack ` +
    `is enabled (harness.config.json packs[] + .claude/settings.local.json) exactly like a genre pack, in addition to any genre pack ` +
    `check.\n` +
    `2. SOURCE-DIRECT CHANNEL PACKS (channels ${JSON.stringify(SOURCE_DIRECT_CHANNELS)}): each is its own Claude Code Skill invoked ` +
    `directly against the findings dir (Skill(<pack>:<pack>)) — built "directly FROM THE SOURCES... NEVER from a rendered report" per ` +
    `their own SKILL.md/plugin.json (docs/reference/packs/channels.md's provenance audit confirms this for every one of the seven). ` +
    `There is NO genre axis for these — a genre requested alongside one is ignored (report it, do not silently apply it and do not drop ` +
    `the channel because a genre was also asked).\n` +
    `EXPLICITLY OUT OF SCOPE (a real third mechanism, never folded into 1 or 2): channels ${JSON.stringify(OUT_OF_SCOPE_CHANNELS)} — ` +
    `"diataxis" (per-finding page generation via its own render-diataxis.sh) and "ai-spec" (consumes an entirely different genre family: ` +
    `ai-architecture-doc/kiro-requirements/kiro-design/kiro-tasks/feature-spec, none of which render through blog/book). Report these in ` +
    `unavailable[] naming the third-mechanism reason explicitly.\n` +
    `"report" as a requested channel is an ARCHITECTURAL BOUNDARY, not unavailable-for-lack-of-a-pack: the canonical L3 report is ` +
    `research-projection.js's job (Epic #543/#569), not this module's. Report it in unavailable[] with that reason.\n\n` +
    `PACK CLASSIFICATION (do not guess — read harness.config.json packs[] AND cross-check against this reference; a pack's own ` +
    `plugin.json "kind" is authoritative when readable, this table covers marketplace-ref packs that have no local plugin.json to read):\n` +
    `- GENRE packs (mechanism 1 templateSource): ${JSON.stringify(Object.keys(GENRE_PACKS))}. Of these, ` +
    `${JSON.stringify(Object.keys(GENRE_PACKS).filter((g) => GENRE_PACKS[g].consumingChannel))} consume ONLY the ai-spec channel — ` +
    `requesting one of these against blog/book is unavailable with that exact reason (not "genre pack not enabled").\n` +
    `- METHODOLOGY packs (${JSON.stringify(METHODOLOGY_PACKS)}) are dimension/analyst skills, NEVER a deliverable genre template — ` +
    `harness.config.json currently enables three of them (competitive-analysis, market-sizing, trend-modeling) alongside real genre ` +
    `packs in the same packs[] array with no distinguishing field of their own in that file; a genre request matching one of these must ` +
    `be reported unavailable with the reason "this pack provides a research methodology/dimension skill, not a deliverable genre ` +
    `template" — never silently treated as an unknown/disabled genre.\n\n` +
    `ENABLEMENT CHECK — read BOTH ${H}/harness.config.json packs[] (the control-plane intent) AND ${H}/.claude/settings.local.json ` +
    `(gitignored, instance-local, written by scripts/sync-packs.sh) if it exists. The native enabledPlugins key shape there is ` +
    `"<pack-name>@research-harness": true (the marketplace name from .claude-plugin/marketplace.json, NOT a bare pack name) — match ` +
    `this exact shape, never a bare-name lookup. settings.json (no ".local") NEVER carries enabledPlugins (gate_m5) and must not be ` +
    `read for this. Treat a pack as enabled only if harness.config.json packs[] marks it enabled:true (settings.local.json, if present, ` +
    `should agree — if it's stale or absent, harness.config.json's own enabled:true is still authoritative for THIS module's routing ` +
    `decision, since a clone may not have run sync-packs.sh yet).\n\n` +
    `For every requested (genre × channel) or bare-channel combination that cannot be served, emit unavailable[] with a reason that ` +
    `NAMES the mechanism (artifact-based / source-direct / out-of-scope-third-mechanism / architectural-boundary) and exactly what is ` +
    `missing (pack disabled, wrong pack kind, wrong consuming channel, unrecognized channel) — never silently dropped. For every ` +
    `servable combination emit one plan[] row with the resolved mechanism, templateSource (the pack name that will actually render it), ` +
    `and outputHint following these conventions — every artifact-mechanism path lives under reports/${TOPIC}/, never a top-level ` +
    `blog/ or book/ directory (this harness's own standing rule: nothing renders outside reports/<topic>/): artifact-based blog -> ` +
    `"${H}/reports/${TOPIC}/${TOPIC}.blog.md" for genre="general", "${H}/reports/${TOPIC}/${TOPIC}.<genre>.blog.md" otherwise (the ` +
    `trailing .blog.md, not a leading blog/ prefix, is what keeps this collision-free against the report channel's own ` +
    `<topic>.<genre>.md files); artifact-based book -> "${H}/reports/${TOPIC}/book/chapters/<genre>.md" (genre as the chapter ` +
    `slug, since this module renders one chapter per requested genre rather than a numeric sequence); source-direct channels -> follow ` +
    `that pack's own SKILL.md-documented default location — every one of them (pdf/jats/xbrl/ectd/notebooklm) already resolves relative ` +
    `to <findings-dir>/.., i.e. reports/${TOPIC}/ itself, so no adaptation is needed there; do not invent any harness-wide convention ` +
    `beyond the blog/book paths named above.`,
  { label: 'deliverables:route', model: 'haiku', schema: ROUTE_SCHEMA },
)
if (!route) throw new Error('research-deliverables: routing failed')
for (const u of route.unavailable) log(`UNAVAILABLE: ${u.requested} — ${u.reason}`)
if (!route.plan.length) {
  log('No servable genre×channel routes — nothing to render')
  return { ok: false, artifacts: [], unavailable: route.unavailable }
}
log(`Rendering ${route.plan.length} deliverable(s): ${route.plan.map((p) => `${p.genre}×${p.channel} (${p.mechanism})`).join(', ')}`)

// GENRE STRING VALIDATION (research-harness-template#640, mirrors #633's own
// guard in research-projection.js): every non-general/non-'-' genre below is
// interpolated into a shell command argument (synthesize-artifact.sh/
// render-artifact.sh's genreArg) AND, for artifact rows, into a Skill()
// reference (genreSkillRef = `${genre}:${genre}`). Pack names are
// constrained by harness.config.schema.json's packs[].name pattern
// (^[a-z][a-z0-9-]*$) — Route is a model call, not code, so its plan[]
// cannot be trusted to have enforced this itself. Validate BEFORE any use
// and fail closed rather than silently coercing or proceeding.
for (const p of route.plan) {
  if (p.genre !== 'general' && p.genre !== '-' && !/^[a-z][a-z0-9-]*$/.test(p.genre)) {
    throw new Error(
      `research-deliverables: route.plan genre "${p.genre}" (channel "${p.channel}") does not match the pack-name pattern ` +
        `harness.config.schema.json enforces (^[a-z][a-z0-9-]*$) — refusing to interpolate an unvalidated genre string into a shell ` +
        `command or Skill() reference.`,
    )
  }
}

phase('Render')
const rendered = await pipeline(
  route.plan,
  (p) => {
    const genreArg = p.genre === '-' ? 'general' : p.genre
    // GENRE SKILL APPLICATION (#640): every artifact-based row reaching this
    // point already had its genre's pack enablement confirmed by the Route
    // phase (see module header) — no separate re-check needed here, unlike
    // #633's fix in research-projection.js which had no prior routing phase
    // to lean on. genre="general" needs no skill invocation (neutral render
    // stands as-is); anything else gets Skill(<genre>:<genre>) applied.
    const genreStepText =
      genreArg !== 'general'
        ? `4. GENRE SKILL APPLICATION (research-harness-template#640): genre "${genreArg}"'s pack was already confirmed enabled by the ` +
          `Route phase (templateSource: ${p.templateSource}) — invoke Skill(${genreArg}:${genreArg}) to restructure ONLY ` +
          `${p.outputHint}'s BODY content into that genre's actual documented section structure (its own template's required ` +
          `sections — e.g. engineering's mandatory Problem/Context/Options/Trade-offs-table/Decision/Implementation-Notes/` +
          `Consequences, briefing's Headline/What's-New/Why-It-Matters/What's-Next), built from the SAME artifact claims steps 1-3 ` +
          `already established — invent no new claims, never touch the citation/References/Sources section step 3 already wrote ` +
          `(public-citation-only; restructuring the body must not introduce a citation leak). Set genreApplied=true, ` +
          `genreSkillInvoked="${genreArg}:${genreArg}".\n`
        : `4. GENRE SKILL APPLICATION (research-harness-template#640): genre="general" — no genre template applies, the neutral ` +
          `artifact-rendered body from step 3 stands unchanged. Set genreApplied=false, genreSkillInvoked="".\n`
    return p.mechanism === 'artifact'
      ? agent(
          `Render ONE artifact-based deliverable for topic ${TOPIC}, harness ${H}: genre="${p.genre}", channel="${p.channel}", ` +
            `template source: ${p.templateSource}. Follow the publish-blog/book-author skills' own SCRIPT PIPELINE exactly — never ` +
            `free-form-author the content:\n` +
            `1. bash ${H}/scripts/synthesize-artifact.sh ${RDIR}/findings ${genreArg} ${RDIR}/artifact.${genreArg}.json — ` +
            `deterministic, delegates to the mif-rh-cli engine; produces the typed Artifact (schemas/artifact.schema.json).\n` +
            `2. SYNTHESIS-ONLY EVIDENCE RULE (cross-check, since the script above reads findings directly and never consults the ` +
            `synthesis): read the typed synthesis at ${SYN} and confirm every claim the artifact carries traces to what that synthesis ` +
            `already established — the deliverable must never introduce a claim present in raw findings but excluded or contradicted ` +
            `by the synthesis.\n` +
            `3. bash ${H}/scripts/render-artifact.sh ${RDIR}/artifact.${genreArg}.json ${p.channel} ${p.outputHint} — write-then-` +
            `validated; produces public-citation-only prose (the citation-leak gate is enforced by this script's own engine delegation ` +
            `for blog/book, per scripts/render-artifact.sh's own header — do not hand-craft finding-@id citation keys into the output, ` +
            `that would BE a citation leak, not a feature).\n` +
            genreStepText +
            `5. Stamp WITNESSED provenance (mif-docs-plugin's mif-provenance skill, ADR-0018, #632) on top of — never instead of — the ` +
            `MIF Level-1 frontmatter step 3 already wrote (render-artifact.sh's own header: blog/book carry a real ` +
            `@context/@type/@id/conceptType/created concept), and on top of step 4's restructuring if genreApplied=true. Invoke it via ` +
            `the Skill tool, namespaced pack:skill, never a hand-rolled script path into the plugin's install cache:\n` +
            `   Skill(mif-docs:mif-provenance) — "stamp ${p.outputHint}"\n` +
            `If capture is disabled (mifProvenance.capture unset or false at every settings scope) or the session ledger has no ` +
            `witnessed touch of this file, stamp DECLINES (exit 3) — this is expected and healthy, not a render failure to surface as ` +
            `broken; the deliverable's provenance block stays whatever step 3 (and step 4, if applied) already asserted (model-` +
            `asserted). Do NOT hand-author a provenance block to work around a decline. On success the block carries hook-observed ` +
            `agent/agentVersion/wasGeneratedBy fields instead of only model-asserted ones; trustLevel stays user_stated (a local, ` +
            `unsigned witness) — never overstate it as anything higher when reporting the outcome.\n` +
            `Return the output path, genre, channel, mechanism="artifact", how many distinct primary-source citations the rendered ` +
            `output's References/Sources section lists, the genre outcome from step 4 (genreApplied/genreSkillInvoked, per step 4's ` +
            `own instruction above), and the provenance stamp outcome from step 5 (provenanceOutcome: "stamped"/"declined"/"error", ` +
            `plus provenanceReason naming why, or "witnessed" when stamped).`,
          { label: `render:${p.genre}x${p.channel}`, phase: 'Render', model: 'sonnet', schema: RENDER_SCHEMA },
        )
      : agent(
          `Render ONE source-direct deliverable for topic ${TOPIC}, harness ${H}: channel="${p.channel}" (mechanism 2 — built DIRECTLY ` +
            `from findings/citations, NEVER from a rendered artifact or report). Invoke Skill(${p.channel}:${p.channel}) directly ` +
            `against ${RDIR}/findings, following that skill's own documented pipeline and default output location (see its own ` +
            `SKILL.md argument-hint) — do NOT run synthesize-artifact.sh or render-artifact.sh for this row; that pipeline belongs to ` +
            `mechanism 1 only, and using it here would violate this channel's own "never a rendered report" non-negotiable. Do NOT ` +
            `read or reference the synthesis at ${SYN} for this row — the synthesis-only evidence rule does not apply to source-direct ` +
            `channels by design.${p.genre !== '-' ? ` A genre ("${p.genre}") was requested alongside this channel but does not apply — ` +
            `there is no genre axis here; ignore it.` : ''}\n` +
            `There is no genre axis for this mechanism (#640) — always return genreApplied=false, genreSkillInvoked="" regardless of ` +
            `whether a genre was requested alongside this channel.\n` +
            `Do NOT attempt a Skill(mif-docs:mif-provenance) stamp for this row — mechanism 2 is explicitly out of scope for it (each ` +
            `pack owns its own output format/invocation with no dedicated backing script this module controls, and several formats ` +
            `aren't even MIF-frontmatter-bearing markdown; see module header). Return provenanceOutcome="not-applicable" with that ` +
            `reason verbatim.\n` +
            `Return the output path, genre="-", channel, mechanism="source-direct", how many distinct primary-source citations the ` +
            `output carries, genreApplied=false/genreSkillInvoked="", and the provenance fields (provenanceOutcome="not-applicable", ` +
            `provenanceReason naming why).`,
          { label: `render:${p.channel}`, phase: 'Render', model: 'sonnet', schema: RENDER_SCHEMA },
        )
  },
  (r, p) =>
    r
      ? agent(
          checkPrompt(r.outputPath, r.mechanism, p.genre, p.channel),
          { label: `check:${p.genre}x${p.channel}`, phase: 'Check', model: 'haiku', effort: 'low', schema: CHECK_SCHEMA },
        ).then((v) => ({ ...r, validation: v }))
      : null,
)

const artifacts = rendered.filter(Boolean)
const dirty = artifacts.filter((a) => a.validation && !a.validation.clean)
if (dirty.length) {
  phase('Check')
  const refixed = await parallel(
    dirty.map((a) => async () => {
      await agent(
        `Fix these validation problems in ${a.outputPath} (harness ${H}) without changing any claim content or citations:\n` +
          a.validation.problems.map((p) => `- ${p}`).join('\n'),
        { label: `fix:${a.genre}x${a.channel}`, phase: 'Check', model: 'haiku' },
      )
      // Re-validate after the fix — a fix is not done until it proves out
      // against the same check that failed it (write-validate atomicity,
      // fail-closed; mirrors research-fanout.js's repair -> revalidate
      // precedent). Without this, `clean` in the returned artifacts[] would
      // permanently reflect the PRE-fix state even when the fix succeeded.
      const rv = await agent(
        checkPrompt(a.outputPath, a.mechanism, a.genre, a.channel),
        { label: `recheck:${a.genre}x${a.channel}`, phase: 'Check', model: 'haiku', effort: 'low', schema: CHECK_SCHEMA },
      )
      return { a, rv }
    }),
  )
  for (const { a, rv } of refixed) {
    if (rv) a.validation = rv
    else log(`WARNING: re-validation after fix produced no result for ${a.outputPath} — leaving prior (failing) validation recorded`)
  }
}

return {
  ok: artifacts.length > 0,
  artifacts: artifacts.map((a) => ({ path: a.outputPath, genre: a.genre, channel: a.channel, mechanism: a.mechanism, citations: a.citationsCount, clean: a.validation ? a.validation.clean : null, genreApplied: a.genreApplied, genreSkillInvoked: a.genreSkillInvoked, provenanceOutcome: a.provenanceOutcome, provenanceReason: a.provenanceReason })),
  unavailable: route.unavailable,
}
