# Changelog

All notable changes to the research-harness template are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.16.26] - 2026-07-21

### Added

- **`research-pipeline.js` gained a gate-only `falsify` mode in its mode
  router** (#655): drains and gates pending falsification verdicts for an
  existing topic without re-running fanout or synthesis.

### Changed

- **`research-projection.js` slug/genre string-args threading is pinned by a
  dedicated regression eval** (#709).

### Fixed

- **CLI `--genres` is routed into the Project phase, and Deliver is gated on
  channels** (#650, #651): a genres-only invocation no longer silently
  skipped projection or triggered channel delivery with nothing to deliver.
- **Falsification remediation specifies the Citation shape and scopes its
  mutations** (#656, #660): remediation can no longer rewrite finding fields
  outside the remediation contract.
- **`research-fanout.js`'s `FINDING_CONTRACT` closes the `attempted_at`
  one-round-rule trap** (#653): a finding could previously satisfy the
  one-round rule without a genuine falsification attempt timestamp.
- **JSON-string args are normalized at every atomic workflow's entry point**
  (#654, #661): a stringified array/object arriving as `args` no longer
  breaks `args.filter`/`args.map` inside the workflow scripts.
- **`research-deliverables.js`'s `GENRE_PACKS` covers all 37 real mif-docs
  genre skills** (#663): previously unmapped genres fell through the pack
  router.
- **`start.md`'s partial-findings check globs
  `reports/<topic>/findings/*.json`** (#693): it was still looking at the
  pre-findings-subdirectory layout and never detected partial runs.
- **`ai-spec`'s kiro genre outputs are exempt from the Stop-hook conformance
  sweep** (#695): kiro `requirements.md`/`design.md`/`tasks.md` are their own
  genre contract, not MIF-frontmatter documents.
- **`backfill-report-slugs.sh` topic auto-discovery excludes every
  `_`-prefixed `reports/` scaffolding directory** (#694).
- **The engineering-base/agriculture/research ontology namespaces are re-keyed
  under the underscore-prefixed triad roots** (#701).
- **Voice-gate line numbers are reported from the real file, not the
  `strip_links`-filtered stream** (#698): findings now point at the actual
  offending line.
- **Each falsify lens result is paired with its lens identity before failed
  lenses are dropped** (#699): a failed lens could previously shift the
  attribution of every lens after it.
- **Augment mode's fanout dispatch is guarded behind the budget floor**
  (#685, #700): augment no longer dispatches new fanout work the budget can't
  cover.
- **The conformance sweep pathspec is qualified with `:(glob)`** (#696): the
  unqualified pathspec could reach nested channel files it must not sweep.
- **The book-channel clause is ordered before the `reports/*/*.md` catch-all
  in `is_authored_surface`** (#672, #704): book chapter files were being
  misclassified by the catch-all.
- **Import mode's falsify drain is scoped to `needsGating` with regate**
  (#713): foreign verdicts imported from another container are re-gated
  instead of trusted as-is.
- **Blog/book channels render temp-then-move with an explicit engine
  exit-status check** (#711): a failed render can no longer leave a partial
  deliverable at the final path.
- **The `--open-pr` draft copy is guarded and the concierge commit is scoped
  to the draft + index** (#710): unrelated working-tree state can no longer
  ride along in a concierge commit.
- **`attempted_at` is asserted present after a genuine `falsify.sh` write**
  (#659, #665).
- **`report-synthesizer`'s Step 1/Step 4 finding globs point at the
  `findings/` subdirectory** (#671, #703): synthesis was reading an empty
  glob after the findings-layout move.
- **`goal-writer`'s finding paths point at `reports/<topic>/findings/` where
  findings actually live** (#676, #707): the evidence-surface table's
  coverage row, both worked-example verify commands, and every
  finding-location prose statement globbed `reports/<topic>/*.json`
  directly, which only matches `goal.json`/`state.json`/`ontology-map.json`
  — none of which carry `extensions.harness.dimension` — so any coverage
  check authored from the manual was permanently unsatisfiable.
- **`write-finding.sh`'s generic ln-failure branch removes the staged file
  before `rmdir`** (#683, #705): the non-empty staging directory made the
  cleanup itself fail, leaking staged state.
- **`update.sh`'s pass-through guard rejects `--defaults`/`-l`/`-f`, and the
  docs stop recommending them** (#706): those copier flags can silently
  discard instance answers or overwrite instance files.
- **`check-workflow-forbidden-globals.sh` recognizes regex literals** (#708):
  a `\/*` inside a regex literal could previously open a phantom block
  comment and blind the check to everything after it.
- **Native `enabledPlugins` fails closed for unresolved marketplace-ref
  packs** (#714): an unresolvable pack reference now blocks instead of
  silently enabling nothing.
- **Empty review-bypass allowances are enforced on `main` after removing the
  retired org CI app** (#715).
- **The container import lookup matches existing findings by parsed `@id`,
  never jq-pretty-printed bytes** (#716): byte-level formatting differences
  no longer defeat the duplicate check.
- **`container-dir`/`output-dir` are resolved caller-relative against the
  invoking cwd, not the repo root** (#717).
- **Step 4's committed writes are rolled back when a later resource's import
  fails** (#718): a failed multi-resource import no longer leaves a
  half-imported container.

## [0.16.25] - 2026-07-21

### Fixed

- **`ci.yml`'s `verify`/`version-bump` jobs (and the `continuous-monitor`
  pack's `monitor.yml`/`monitor-gate.yml`, plus a pre-existing instance of
  the same bug in `release.yml`'s `changelog-links-check` job) no longer
  404 on `scripts/fetch-engine.sh`'s cross-repo read of `mif-rs`** (#662).
  The minted CI App token's `repositories:` input was restricted to the
  current repo alone; an installation token scoped that way 404s on any
  repo outside its list, even a public one in the same org — an
  installation-scoping boundary, not a permissions gap. The `mif-ci` App
  is already installed org-wide, so the fix widens each mint step's
  `repositories:` to include `mif-rs` (or, for the portable
  `continuous-monitor` pack workflows, mints a second, separate
  read-only App token scoped to exactly `mif-rs`) — the same
  purpose-built, least-privilege App identity this org's ADR-011
  architecture requires, correctly scoped, not a substitution for it.
  Adds `scripts/check-fetch-engine-gh-token.sh` as a static regression
  gate proving every `fetch-engine.sh` step resolves to a minted token
  actually scoped to `mif-rs`.

- **`scripts/fetch-mif-docs-plugin.sh`'s cache-reuse check treated "checked
  out at the pinned ref" as "provisioned"** (#677): the clone/checkout lands
  the pinned ref before `npm ci` / `npm run hydrate-schema` ever run, so a
  failed install left the cache at the correct ref with no `node_modules` and
  no hydrated schema — and the next run's ref-only check then printed
  `already at pinned ref` and exited 0, a false success the downstream
  `verify.sh` `gate_m32` consumer failed on with an unrelated-looking
  `Cannot find module 'ajv'` error. The script now writes a
  `.provisioned-ref` completion sentinel into the cache only after both
  post-checkout steps succeed; cache reuse requires the ref AND the sentinel
  to agree, and a partially-provisioned cache at the correct ref re-runs
  install/hydration (without re-cloning) instead of short-circuiting. New
  eval `fetch-mif-docs-plugin-provision` pins the contract with a stubbed
  npm: failed install writes no sentinel, the next run re-provisions, and a
  fully-provisioned cache is reused without invoking npm.

## [0.16.24] - 2026-07-21

### Fixed

- **`cron_match.py` step semantics in the continuous-monitor pack** (#689).
  `parse_field()` aligned `a-b/step` offsets to the field's absolute lower
  bound instead of the range's own start (`9-17/4` over hours returned
  `{12, 16}` instead of the vixie-cron `{9, 13, 17}`), and a bare `N/step`
  collapsed to the single value `{N}` — the step was silently ignored —
  instead of expanding open-ended to the field's upper bound (`10/5` over
  minutes now yields `{10, 15, ..., 55}`). Topics with such schedules were
  silently gated at the wrong times by `monitor.yml`. Regression eval:
  `evals/cron-match-step-alignment.sh`.

## [0.16.23] - 2026-07-20

### Fixed

- **Every blog/book write path now lands under `reports/<topic>/`, never a
  top-level `blog/`/`book/` directory** (research-harness-instance decision:
  nothing this harness produces lives outside `reports/<topic>/`). `blog` and
  `book` remain real channel concepts — the `publish-blog` skill, the `book`
  channel pack, ADR-0007, and every schema are untouched, only where their
  rendered output lands changes: `publish-blog` renders to
  `reports/<topic>/<topic>.blog.md` (or `.<genre>.blog.md`), replacing
  `blog/<topic>.md`; `book-author` renders to
  `reports/<topic>/book/chapters/<genre>.md`, replacing
  `book/<topic>/chapters/<n>.md`. `research-deliverables.js`'s Route-phase
  `outputHint` prompt, `build-topic-readme.sh`'s genre classifiers, and the
  `check-citation-leak.sh`/`check-voice.sh`/`check-output-conformance.sh`
  hooks are all repointed to match.

## [0.16.22] - 2026-07-19

### Fixed

- **`.githooks/pre-push`'s version-bump check didn't distinguish tag pushes
  from branch pushes, self-blocking every release** (#648): the hook ran
  `scripts/check-version-bump.sh` unconditionally, with no awareness of the
  standard git pre-push stdin protocol (`local_ref local_sha remote_ref
  remote_sha` lines) that distinguishes what kind of ref is being pushed.
  Pushing a release tag at the exact commit where the release pointer was
  just bumped failed the check, because "the last actual git tag release"
  it resolves against is the about-to-be-pushed tag itself — a paradox
  inherent to the act of releasing, not a real versioning violation
  (reproduced live during the v0.16.21 release, forcing a `--no-verify`
  bypass). The hook now reads its stdin per the standard protocol and skips
  the check entirely when every ref being pushed is a tag ref
  (`refs/tags/*`, including a tag deletion); a branch push — including one
  that mixes branch and tag refs in the same invocation — still runs the
  check exactly as before.

## [0.16.21] - 2026-07-19

### Added

- **`research-pipeline.js` gained a `deliverables` mode** (#624): renders
  genre/channel deliverables from a topic's EXISTING, already-gated corpus
  without re-running `research-fanout`/`research-falsify`. Previously the
  only way to render a deliverable genre after a completed run was to bypass
  `/research` entirely and hand-invoke `research-deliverables.js` directly
  through the Workflow tool with a prior run's own scratch `synthesisPath`,
  which is not guaranteed to still exist by the time a later invocation
  runs (`research-synthesis.js`'s ephemeral-output contract is same-
  process-only). `deliverables` mode instead re-drafts a fresh synthesis
  from the survivor findings already on disk (cheap relative to a full
  round — no fan-out, no falsification gate) and feeds that fresh
  `synthesisPath` straight into `research-deliverables` in the same
  process. Requires at least one of `genres`/`channels`. Deliberately never
  calls `research-projection` — the report of record
  (`reports/<topic>/<slug>.md`) is left untouched by this mode (a
  considered design choice, not a silent omission). `/research --mode
  deliverables --genres <g1,g2>` (or `--channels`) is the new entry point;
  see [engine-workflows.md](docs/reference/engine-workflows.md#research-pipeline)
  and [commands.md](docs/reference/commands.md#research) for the full
  reference.

### Fixed

- **`research-pipeline.js`'s mode router silently fell through to `full`
  mode on an unrecognized `mode` string** (#624, adjacent fix): every mode
  branch was an independent early-return `if` with no terminal `else`/
  default guard, so a typo (e.g. `deliverabels`) triggered a full
  autonomous round loop instead of a clear error. A `KNOWN_MODES` guard now
  throws `unknown mode '<mode>'` before any branch dispatches.

- **Concurrent `research-projection.js` invocations against the same topic
  silently corrupted each other via a shared `artifact.json` path** (#628):
  the Report phase's intermediates (`reports/<topic>/artifact.json`,
  `report-finding.json`, `report-finding.falsified.json`,
  `report.verification.json`) are fixed, per-topic paths — not
  genre/slug-parameterized — so two concurrent invocations rendering
  different genres for the same topic (e.g. "engineering" and
  "exec-summary") raced on them with no error surfaced: every invocation
  reported `ok: true` while one invocation's `synthesize-artifact.sh`
  clobbered another's `artifact.json` mid-flight, corrupting or overwriting
  reports. `research-projection.js` now acquires a topic-scoped
  `reports/<topic>/.projection-lock` (via the same shared
  `scripts/lib/container-lock.sh` primitive `mif-container-export.sh`/
  `mif-container-import.sh` already use for `.container.lock`) around the
  whole `synthesize-artifact.sh` -> `render-artifact.sh` pipeline, so a
  second concurrent projection run on the same topic refuses to start
  rather than racing — released on every exit path (success, a falsified
  verdict, or an earlier failure). This is a deliberately independent third
  lock namespace, mirroring the existing separation between
  `reports/<topic>/.run-lock` and `reports/<topic>/.container.lock`, so it
  never contends with the orchestrator's findings-mutation lock or a
  concurrent `/export`/`/import`. `artifact.json` itself keeps its fixed,
  well-known name (unlike `research-deliverables.js`'s own genre-suffixed
  blog/book intermediates) because `mif-container-export.sh`/
  `mif-container-import.sh`/`verify.sh` all expect it at that exact path.
- **`research-projection.js` and `research-deliverables.js` never invoked the
  harness's own witnessed-provenance mechanism, so every rendered report/blog/
  book carried identical, model-asserted `provenance` boilerplate regardless of
  what actually happened during generation** (#632): `research-projection.js`'s
  Report phase now stamps the rendered report via `Skill(mif-docs:mif-provenance)`
  (ADR-0018) after its existing `mif-project.sh` re-confirmation, and
  `research-deliverables.js` does the same for mechanism-1 (artifact-based
  blog/book) rows after `render-artifact.sh` — both decline gracefully (never
  hand-authoring a workaround) when capture is off or the session ledger never
  witnessed the file, and both surface the stamp outcome
  (`provenanceOutcome`/`provenanceReason`) through their schemas and final
  return rather than discarding it. Mechanism-2 source-direct channel packs
  (pdf, jats, xbrl, ectd, notebooklm, github-discuss, github-issues) are
  explicitly out of scope (`provenanceOutcome: "not-applicable"`) — each owns
  its own output format/invocation with no dedicated backing script this module
  controls.
- **`research-pipeline.js`'s completion check could grade `finding_valid`/
  `citation_integrity` as cleanly met without disclosing that
  `research-fanout.js`'s own repair lane had just mutated the graded
  findings in place** (#623): `research-fanout.js` now computes and returns
  the round's true repair count — per dimension (`perDimension[].repaired`)
  and as a total (`repaired`) — the number of findings that arrived
  schema-invalid or citation-defective and needed the Repair phase before
  they validated. `research-pipeline.js`'s independent completion
  evaluator now receives that count every round and is instructed that a
  schema/citation-validity check may never be graded `met` from the
  post-repair corpus state without disclosing it; the run's own final
  report also surfaces the accumulated repair total (`repaired`),
  deterministically, independent of what the evaluator does with the
  disclosure.
- **`research-falsify.js` crashed on every finding needing gating** (#618):
  `buildFixtureEntry()` called `new Date()` from inside its own body — the
  Workflow runtime disallows `new Date()`/`Date.now()`/`Math.random()` inside
  a script's own body (deterministic resume) — so every real `/research`
  full-mode run (or any mode reaching the falsify gate) crashed the write
  step for every finding needing gating, leaving them all stuck at the
  un-gated `inconclusive` placeholder with no way to clear it. The timestamp
  is now threaded through `args.runDate`, computed once by the `/research`
  command (outside the Workflow runtime, before its single `Workflow` tool
  call) and forwarded through `research-pipeline.js`'s `wf()` helper to
  every `research-falsify` call. `research-falsify.js` fails loudly if a
  finding needs gating and no `runDate` was supplied, rather than silently
  computing one in-script.
- Added `scripts/check-workflow-forbidden-globals.sh` (wired into
  `verify.sh`'s `gate_workflows`, alongside `check-workflow-syntax.sh`): a
  comment-aware static gate that greps every `.claude/workflows/*.js` module
  for `new Date(`, `Date.now(`, and `Math.random(` calls, so a future
  regression of this class is caught in CI, not discovered live against a
  real corpus.
- **`research-falsify.js`'s `scope: 'all'` silently skipped one pre-existing
  finding across two gate attempts** (#625): the Enumerate step's
  `workingSet`/`skippedAlreadyVerified` were both the same agent turn's own
  classification of the findings it decided to look at, so nothing
  independently proved it looked at ALL of them — a real 19-finding run
  enumerated only 18, with only an aggregate skip count and no itemized
  on-disk listing to reconcile against. Enumerate now also returns
  `allFindingIds` (every on-disk `@id`, derived mechanically via
  `find … | sort`, never re-derived from the same reasoning that produced
  `workingSet`) and itemizes `skippedAlreadyVerifiedIds`; a deterministic
  `reconcileEnumeration()` set-difference check in code confirms every
  on-disk id is covered by `workingSet ∪ skippedAlreadyVerifiedIds`,
  triggers one named retry on a gap, and throws loudly (naming the missing
  id(s)) if the gap survives the retry, rather than silently gating a
  partial working set. The reconciliation only applies to `scope: 'all'` —
  under a narrower scope (`dimension:*`, or an explicit `paths`/`ids` set,
  including regate) the working set is a deliberate subset, so out-of-scope
  on-disk findings sit in neither list legitimately and would otherwise be
  falsely flagged missing. RE-GATE mode also gained its own deterministic
  guard: since regate exists specifically to re-open verification even for
  findings already carrying `extensions.harness.verification.attempted_at`,
  the module now fails loudly (naming the offending id(s)) if enumeration
  nonetheless populates `skippedAlreadyVerifiedIds` during a regate run,
  rather than trusting the enumeration agent's own compliance with that
  prompt contract.

## 0.16.20 - 2026-07-19

## 0.16.19 - 2026-07-18

## [0.16.18] - 2026-07-18

### Added

- **Vendor the research-pipeline workflow (the workflow-of-workflows
  orchestrator)** (#599, Epic #550): `.claude/workflows/research-pipeline.js`,
  the twelfth and last workflow module and the sole composer of the eleven
  atomic ones (D-9, one-level `workflow()` nesting). Implements the
  deterministic mode router (`full | augment | pivot | import | audit`) and
  the bounded autonomous round loop for `full` runs — `goal` -> [`fanout` ->
  `falsify` (bounded drain) -> `synthesis` -> an independent sonnet
  completion check that runs each goal check's own verify command and
  grades adversarially]\* -> audit-driven adaptation (routes to
  `add-dimensions` or `augment`) -> `projection` -> optional `deliverables`.
  Loop-exit, round bounds (`maxRounds`), and the token-budget floor (60 000
  remaining) are code comparisons on typed agent output, never prompt
  instructions; when the augment judge finds nothing left to deepen while
  checks remain unmet, the loop stops with the judge's own stated reasoning
  logged (NFR-10, a real code path). `harnessDir` defaults to `.`, matching
  every prior vendored module; `workflowsDir` keeps the reference's own
  `.claude/workflows` default unchanged. The old agent engine
  (`.claude/agents/orchestrator.md`, `/start`) remains untouched.
- `scripts/verify.sh`'s `gate_workflows` gained its twelfth hand-added
  per-file existence assert for `.claude/workflows/research-pipeline.js`,
  alongside the eleven already there; `check-workflow-syntax.sh`'s own
  nullglob parse-check required no manual wiring for the new file.

## 0.16.17 - 2026-07-18

### Added

- **Vendor the research-coverage-audit workflow (atomic action Z — corpus
  audit)** (#595, Epic #549): `.claude/workflows/research-coverage-audit.js`,
  the fifth and last of the steering-action modules. Six blind auditors each
  probe the corpus a different way — `thin-dimensions` (haiku),
  `staleness` (haiku), `quarantine-review` (haiku), `graph-orphans` (haiku),
  `check-traceability` (sonnet), `homeless-leads` (sonnet); a sonnet
  completeness critic asks what no auditor covered and spot-checks its own
  top suspicions against the real corpus; a sonnet prioritizer emits a
  routed backlog (`augment | add-dimensions | falsify | import | projection
  | manual`), ranked by unmet-check impact, then severity, then cheapness.
  `harnessDir` defaults to `.`, matching every prior vendored module.
- **Confirmed delegation gap, fixed here** (same class as #543-#548): the
  reference implementation's `thin-dimensions` and `staleness` auditor
  briefs re-derived their signal freehand instead of invoking the
  deterministic jq pipelines the harness's own `discover` skill already
  ships for exactly these two probes. Both briefs now delegate to
  `discover`'s `--gaps`/`--stale` pipelines verbatim (adapted to this
  module's topic scope: goal.json's `dimensions[]`, not
  `harness.config.json`'s corpus-wide taxonomy — the same adaptation
  `research-augment.js`'s Assess phase already established, #578/#580).
  The other four auditors have no `discover` equivalent and are correctly
  left as novel probes.
- **Module-reference correction, documented in code**: the routed
  backlog's `target` field does NOT map uniformly to all five downstream
  modules' args with no adapter, verified against the real vendored source
  on `main` — `research-add-dimensions.js`'s `hints` is an array (needs
  wrapping), `research-falsify.js`'s `scope` is a tagged union (needs
  construction), `research-import.js`'s `containerDir` and
  `research-projection.js`'s `synthesisPath` are both required values an
  audit's corpus scan cannot itself produce. `target` is documented as a
  routing signal, not a directly-forwardable arg, in the Prioritize prompt
  and next to `BACKLOG_SCHEMA` for the not-yet-vendored orchestrator (#550).
  `scripts/verify.sh`'s `gate_workflows` gains an eleventh hand-added
  per-file existence assert. Docs (`## research-coverage-audit` in
  `docs/reference/engine-workflows.md`, with a per-auditor `discover`-skill
  cross-reference rather than one blanket subsumption claim, #596) and a
  deterministic eval (`evals/coverage-audit-check.sh`, #597) ship in this
  same release. Version bumped via `scripts/bump-version.sh` patch
  (0.16.16 -> 0.16.17, ADR-0010).

## 0.16.16 - 2026-07-18

### Added

- **Deterministic eval for the research-import DryRun/Review/Apply pipeline**
  (#592, Epic #548): `evals/import-check.sh`, wired as a tenth explicit run
  line in `evals/run-evals.sh`. Every DryRun and Apply agent() call is
  stubbed to invoke the REAL `scripts/mif-container-import.sh` — never a
  mocked/fabricated verdict — proving: (A) structurally, via phase() marker
  spans, that the DryRun phase invokes the script WITH `--dry-run` and the
  Apply phase invokes it WITHOUT; (B) a REAL fixture container with one
  resource's bytes corrupted after its digest was declared is rejected by
  the real script's `--dry-run` path, with Review/Apply never called and
  nothing written; (C) a real, uncorrupted container hits a Review NO-GO (a
  live sonnet scope-fit judgment stubbed since it cannot be reproduced
  deterministically) with Apply never called and nothing written; (D) a
  real container — exactly 2 hand-authored synthetic findings, one
  already carrying a genuine foreign verification block (`attempted_at`
  set) and one carrying `scripts/falsify.sh`'s own documented PLACEHOLDER
  `inconclusive`/no-`attempted_at` shape — imports for real through the
  non-dry-run gate, and the `needsGating`/`trustedForeignVerdicts`
  partition is correct for BOTH
  `trustImportedVerdicts` settings against the real on-disk written files;
  (E) `research-falsify.js` accepts the real `needsGating` output as
  `scope:{ids:[...]},regate:true` without tripping its guard error,
  mirroring #588's pivot->falsify interface fixture. Real repo-root
  mutation (`harness.config.json`, `reports/concordance.json`) is guarded by
  the same `$ROOT/.eval-corpus-mutation.lock` + cp-based backup/restore
  idiom `mif-container-nfr-verification.sh` already uses.

## 0.16.15 - 2026-07-18

### Added

- **Vendored research-import workflow** (#590, Epic #548):
  `.claude/workflows/research-import.js` — atomic action D (include
  pre-existing findings, for when findings from another harness instance,
  an earlier campaign, or an `/export` container should join the corpus), a
  three-phase chain: a haiku DryRun phase runs
  `scripts/mif-container-import.sh <container> <topic> --dry-run` (manifest
  schema, per-resource + manifest-level digests, ontology-binding
  compatibility) — any failure rejects with nothing written; a sonnet
  Review phase checks what the mechanical gate cannot see (same-`@id`-
  different-content collisions, provenance coherence, scope fit vs the
  goal) — a genuine NO-GO is possible even after DryRun passes; a haiku
  Apply phase runs the real import (fail-closed, no partial writes) and
  enumerates imported/foreign-verdict/unverified findings. Unlike every
  prior module in this chain (#543 projection, #544 deliverables, #545
  augment, #546 add-dimensions, #547 pivot — each of which found and fixed
  a freehand-reimplementation gap in its vendor Task), this module's
  DryRun and Apply phases were confirmed, read line by line against the
  actual reference source, to delegate ENTIRELY to the real
  `scripts/mif-container-import.sh` (ADR-0017,
  `docs/adr/0017-mif-container-instance-scoped-export-import-format.md`,
  status: accepted) — no freehand manifest/digest/ontology-binding logic
  in either prompt. The delegation bar matters especially here: this is
  the one workflow in the chain that ingests untrusted EXTERNAL input, so
  the fail-closed gate's integrity depends entirely on zero freehand
  duplication of its checks. `needsGating` (`unverified` plus, unless
  `trustImportedVerdicts` is set, `withForeignVerdicts`) feeds directly
  into `research-falsify.js`'s `scope: { ids: [...] }, regate: true` with
  no adapter needed — documented at the return site so the interface
  contract, including the foreign-verdict regate nuance, is visible at the
  call site. `harnessDir` defaults to `.`, matching the
  research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js/research-projection.js/research-deliverables.js/
  research-augment.js/research-add-dimensions.js/research-pivot.js
  precedent. `scripts/verify.sh`'s `gate_workflows` gains a tenth
  hand-added per-file existence assert for the new module.

## 0.16.14 - 2026-07-18

### Added

- **Vendored research-pivot workflow** (#586, Epic #547):
  `.claude/workflows/research-pivot.js` — atomic action C (pivot research
  focus, for when the question itself changes), a three-phase chain ending
  in a lineage event: a sonnet Reshape phase mints a NEW version of the
  goal's append-only lineage from a required delta argument (a pivot with
  no stated delta throws and refuses to run); parallel haiku Classify
  batches (default 15) grade every existing finding against the NEW goal
  as carry / stale / out-of-scope — findings are gathered once and reused
  across goal versions, classification never deletes, out-of-scope
  findings stay on disk simply unused; a sonnet Plan phase computes
  `gapDimensions` (which dimensions the carried corpus cannot answer the
  new checks from) and `reverifyIds` (the stale list). Fixes the same
  class of delegate-vs-reimplement gap #543/#544/#545/#546 already named:
  the reference implementation's Reshape phase computes the `gv-`
  content-hash freehand (a prose description of the sha256-first-12-hex
  algorithm) rather than invoking `scripts/goal-version.sh`, which already
  delegates to the canonical `mif-rh-cli harness goal-version` mechanism
  (Category-B cutover, research-harness-template#276/Story #298). This
  module instead follows the same snapshot-then-mint idiom
  `.claude/commands/goal-writer.md`'s `--reshape` flow and
  `research-add-dimensions.js`'s Amend phase already establish: snapshot
  the live goal to `reports/<topic>/goals/goal-<gv>.json` before editing,
  apply the delta, then mint the new version by actually running
  `scripts/goal-version.sh` (ADR-0006, content-hashed append-only lineage —
  the goal is immutable per version, a pivot is an append, never an
  in-place edit). `reverifyIds` feeds directly into `research-falsify.js`'s
  `scope: { ids: [...] }, regate: true` with no adapter needed — documented
  at the return site so the interface contract is visible at the call site.
  `harnessDir` defaults to `.`, matching the
  research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js/research-projection.js/research-deliverables.js/
  research-augment.js/research-add-dimensions.js precedent.
  `scripts/verify.sh`'s `gate_workflows` gains a ninth hand-added per-file
  existence assert for the new module.

## 0.16.13 - 2026-07-18

### Added

- **Vendored research-add-dimensions workflow** (#582, Epic #546):
  `.claude/workflows/research-add-dimensions.js` — atomic action B (widen
  the dimension set), a generator-critic chain ending in a lineage event: a
  sonnet Propose phase derives candidate new dimensions from homeless
  evidence leads (`crossDimensionLeads`) and user hints, justified only
  when existing dimensions genuinely cannot house the evidence; a sonnet
  Prune phase attacks each candidate on overlap, scope, and
  decision-relevance; an Amend phase wires approved survivors into
  `harness.config.json` `dimensions[]` (ajv-clean) and mints a new `gv-`
  goal version with correct `supersedes` lineage. Fixes the same class of
  delegate-vs-reimplement gap #543/#544/#545 already named: the reference
  implementation's Amend phase computes the `gv-` content-hash freehand
  (a prose description of the sha256-first-12-hex algorithm) rather than
  invoking `scripts/goal-version.sh`, which already delegates to the
  canonical `mif-rh-cli harness goal-version` mechanism (Category-B
  cutover, research-harness-template#276/Story #298). This module instead
  follows the same snapshot-then-mint idiom `.claude/commands/goal-writer.md`'s
  update flow and `research-goal.js`'s re-authoring branch already
  establish: snapshot the live goal to `reports/<topic>/goals/goal-<gv>.json`
  before editing, apply the dimension-widening delta, then mint the new
  version by actually running `scripts/goal-version.sh` (ADR-0006,
  content-hashed append-only lineage — the goal is immutable per version,
  widening is an append, never an in-place edit). `harnessDir` defaults to
  `.`, matching the research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js/research-projection.js/research-deliverables.js/
  research-augment.js precedent. `scripts/verify.sh`'s `gate_workflows`
  gains an eighth hand-added per-file existence assert for the new module.

## 0.16.12 - 2026-07-18

### Added

- **Vendored research-augment workflow** (#578, Epic #545):
  `.claude/workflows/research-augment.js` — atomic action A (augment), a
  pure DECIDE workflow: a haiku Assess phase computes the per-dimension
  coverage/verdict/staleness matrix and a sonnet Decide phase judges which
  dimensions to deepen with stated reasoning, rejected alternatives, and
  named target checks (or an explicit, valid "nothing warrants deepening").
  Fixes the same class of delegate-vs-reimplement gap #543/#544 already
  named: the reference implementation's Assess phase re-derives per-dimension
  finding/verdict counts via a free-form haiku prompt over raw finding
  files; here it instead composes the two jq idioms the `discover` skill
  (`.claude/skills/discover/SKILL.md`) already documents — grouping by
  dimension (its coverage-gaps pipeline) and filtering by verdict (its
  stale-findings pipeline) — into one deterministic pipeline over the same
  `research-index.json`. Only `oldestFindingDate` (the index carries no
  timestamp, same gap discover's own README notes for its age-based
  staleness signal) is genuinely incremental logic layered on top, read
  from the raw finding files. `harnessDir` defaults to `.`, matching the
  research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js/research-projection.js/research-deliverables.js
  precedent; the module runs standalone with no live-orchestrator-context
  dependency (the orchestrator, #550, is not yet vendored). Decide-phase
  priority is unmet-check-impact > attrition > thinness > staleness, with
  attrition treated as a distinct sourcing-strategy signal rather than
  folded into thinness. `scripts/verify.sh`'s `gate_workflows` gains a
  seventh hand-added per-file existence assert for the new module.

## 0.16.11 - 2026-07-18

### Added

- **Vendored research-deliverables workflow** (#573, Epic #544):
  `.claude/workflows/research-deliverables.js` — atomic step 6 (deliverable
  genres), covering BOTH real rendering mechanisms the substrate has (an
  expansion of the reference implementation's own artifact-only
  recommendation, an explicit epic-owner scope decision): artifact-based
  renders (`blog`/`book` channels via the same `synthesize-artifact.sh` ->
  `render-artifact.sh` pipeline the `publish-blog`/`book:book-author`
  skills use, never free-form-authored) and source-direct channel packs
  (`pdf`, `jats`, `xbrl`, `ectd`, `notebooklm`, `github-discuss`,
  `github-issues`, each invoked as its own `Skill(<pack>:<pack>)` directly
  against the findings dir, never through a rendered artifact or the
  synthesis). `channel="report"` is explicitly excluded as
  research-projection's own job, and `diataxis`/`ai-spec` are named as a
  genuine third mechanism this module does not cover — every unavailable
  request reports a reason naming which mechanism and what is missing,
  never silently dropped. The Route phase reads `harness.config.json`
  `packs[]` and `.claude/settings.local.json`'s native `enabledPlugins`
  under its real `"<pack>@research-harness"` key shape, cross-checking
  against a static genre/methodology/channel pack taxonomy so a methodology
  pack (competitive-analysis, market-sizing, trend-modeling) is never
  mistaken for a deliverable genre template. `harnessDir` defaults to `.`,
  matching the research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js/research-projection.js precedent.
  `scripts/verify.sh`'s `gate_workflows` gains a sixth hand-added per-file
  existence assert for the new module, and
  `evals/deliverables-route-check.sh` proves the module's static pack
  tables against the real `docs/reference/packs/index.md` table and the
  artifact-based pipeline's citation-leak-clean claim against a real,
  hermetic fixture run.

## 0.16.10 - 2026-07-18

### Added

- **Vendored research-projection workflow** (#569, Epic #543):
  `.claude/workflows/research-projection.js` — atomic step 5 (projection),
  materializing the typed synthesis onto the durable corpus surfaces. The
  Report phase delegates to the `publish-report` skill's real script
  pipeline (`synthesize-artifact.sh` -> `falsify.sh` -> `render-artifact.sh`
  -> `mif-project.sh`) instead of hand-authoring MIF frontmatter/citations —
  in particular, the `extensions.harness.verification` verdict always comes
  from a genuine falsification pass over the report's own central claims,
  never asserted; a `falsified` verdict quarantines the report and stops
  before rendering. The Index phase delegates to the `readme` skill's
  `build-topic-readme.sh` for the deterministic structural backbone (haiku
  authors only the synthesis-grade Key Findings/Purpose the script cannot
  compute) and the `graph` skill's `build-graph.sh` +
  `assert-graph-mif.sh` for the knowledge-graph refresh — a correctness fix
  over the reference implementation's free-form-prompt reimplementation of
  all three skills. Guards the same-process-only `synthesisPath` hand-off
  from `research-synthesis.js` (#542) with an explicit existence/non-empty/
  valid-JSON preflight check that fails closed with a clear error, rather
  than trusting a required arg with no guard. Report supersession preserves
  the report's `@id` across a re-render structurally (the engine derives it
  from namespace+slug), verified against a real fixture run rather than
  assumed. `harnessDir` defaults to `.`, matching the
  research-goal.js/research-fanout.js/research-falsify.js/
  research-synthesis.js precedent. `scripts/verify.sh`'s `gate_workflows`
  gains a fifth hand-added per-file existence assert for the new module.

## 0.16.9 - 2026-07-18

### Added

- **Vendored research-synthesis workflow** (#564, Epic #542):
  `.claude/workflows/research-synthesis.js` — atomic step 4 (synthesis), the
  evaluator-optimizer loop: a haiku Select phase builds the survivor set
  (`survived`/`weakened`/`inconclusive` verdicts; `falsified` findings are
  structurally excluded via the `quarantine/`/`archive/` directories
  `research-falsify.js` already moved them to, never re-derived from the
  verdict field; findings with no verification block are counted separately
  as `unverified`/ungated, never silently promoted into the survivor set), a
  sonnet Draft phase writes a typed, `@id`-keyed synthesis organized around
  `schemas/goal.schema.json`'s `completion_condition.checks[]`, and an opus Critique
  phase grades it per-check plus citation-key integrity, fidelity, and
  tension-burial, with a bounded `<=2`-round repair loop that reports an
  explicit unresolved-check list rather than looping forever. Invents and
  documents (in the module's own header comments) the ephemeral-output
  contract this repo had no prior canonical convention for: the synthesis
  document is written to a single `mktemp` file OUTSIDE the repo tree, and
  its absolute path travels back to the caller in the top-level
  `synthesisPath` field of the module's return value — the handoff shape the
  not-yet-started research-projection workflow (#543) will consume. In-repo
  default: `harnessDir` defaults to `.`, matching the established
  `research-goal.js`/`research-fanout.js`/`research-falsify.js` precedent.
  `scripts/verify.sh`'s `gate_workflows` gained a fourth hand-added
  per-file existence assert for the new module.

## 0.16.8 - 2026-07-18

### Added

- **Vendored research-falsify workflow** (#560, Epic #541):
  `.claude/workflows/research-falsify.js` — atomic step 3 (falsification), the
  single adversarial gate decomposed into haiku claim decomposition,
  perspective-diverse sonnet skeptic voting (counter-evidence, source-integrity,
  temporal-validity, scope-integrity — web-only), deterministic verdict-merge
  arithmetic in code (`mergeVotes()`), and opus adjudication only on contested
  minority-`falsified` patterns. Adapted from the workspace reference against
  the CURRENT substrate rather than carried forward as-is: (1) a fixture-write
  bridge — `scripts/falsify.sh`'s real signature takes no bare verdict/basis
  CLI args, so the module materializes a small `{verdict, basis, disconfirming}`
  evidence fixture in code (`buildFixtureEntry()`) from its own verdict
  arithmetic and mktemps it outside the repo tree before invoking
  `falsify.sh <finding> <fixture>`; (2) `regate` is a client-side reset —
  `falsify.sh`'s one-round check has no engine override, so the module clears
  a stale finding's `extensions.harness.verification` block itself before
  re-invoking `falsify.sh`, keeping the write itself exclusively routed
  through the substrate; (3) remediation (falsified → quarantine, weakened →
  downgrade one `provenance.trustLevel` rung with a bounded summary qualifier,
  survived/inconclusive → annotate only) is ported directly into the module
  from `.claude/agents/falsification-analyst.md` Step 7, since neither
  `falsify.sh` nor `mif-rh-cli` implement it. `verify.sh` `gate_workflows`
  gains the third per-file existence assert; the `check-workflow-syntax.sh`
  glob parse-check covers it automatically.

## 0.16.7 - 2026-07-18

### Added

- **Vendored research-fanout workflow** (#556, Epic #540):
  `.claude/workflows/research-fanout.js` — atomic step 2 (research fan-out)
  of the workflow-of-workflows engine, adapted from the workspace reference
  with in-repo defaults (`harnessDir` defaults to the instance root `.`, the
  #552 precedent). Analyst briefs are self-contained: the inlined
  `FINDING_CONTRACT` constant carries the findings-schema rules, with no
  dependence on `.claude/agents/dimension-analyst.md` prose. Per-dimension
  Research→Validate→Repair lanes run with no cross-dimension barrier (repair
  annotates/repairs, never deletes), a single cross-corpus Relate pass
  annotates duplicates with typed MIF relationships, and the
  `crossDimensionLeads` side-channel surfaces homeless evidence in the return
  payload. `verify.sh` `gate_workflows` gains the per-file existence assert
  for the module; the `check-workflow-syntax.sh` glob parse-check covers it
  automatically.

## 0.16.6 - 2026-07-18

### Added

- **Deterministic goal verifiability lint + draft→lint→repair eval** (#554,
  Epic #539): `scripts/lint-goal.sh` is the machine-checkable floor under the
  research-goal workflow's Gate-phase lint — a fail-closed `ajv` schema gate
  against `schemas/goal.schema.json`, step-shaped
  `completion_condition.checks[]` assertion detection (leading imperative
  research verb — a step, not an end-state fact), and off-config
  `dimensions[]` detection. The vendored
  `.claude/workflows/research-goal.js` Gate/repair prompts now route through
  it. `evals/goal-lint-repair.sh` (registered in `evals/run-evals.sh`, so
  CI's required `verify` context covers it) proves the contract on the
  seeded-invalid fixture set under `evals/fixtures/goal-lint/`: the
  seeded-invalid goal is ajv-valid yet fails the lint (both issue classes
  named), a schema-invalid goal fails closed before the content lint, the
  repaired goal is green, and the workflow's bounded repair arithmetic
  (max 2 rounds) converges or fails closed when repair is exhausted.

## 0.16.5 - 2026-07-18

### Added

- **Vendored `research-goal` workflow module** (#552, Epic #539):
  `.claude/workflows/research-goal.js` — atomic step 1 of the research
  pipeline (goal-writing: Context probe → Draft → Gate with a bounded
  2-round repair loop) — now ships as first-class engine content. In-repo
  arg defaults (`harnessDir` defaults to the instance root `.`), and
  re-authoring an existing goal routes through ADR-0006's content-hashed
  append-only lineage (`scripts/goal-version.sh`, `gv-*` versions,
  `goals/goal-<gv>.json` snapshots) instead of an ad hoc
  `goal.prior.json` copy. `.claude/workflows/` is not copier-excluded, so
  the module travels byte-identical template-and-instance.
- **Workflow-module parse-check on the `verify` surface** (#552):
  `scripts/check-workflow-syntax.sh` compiles each
  `.claude/workflows/*.js` as a Workflow-runtime async function body
  (top-level `return`/`await` are legal there, so a bare `node --check`
  rejects a valid module), wired into `verify.sh` as `gate_workflows` —
  covered by the already-required `verify` CI context, no new required
  check. Regression eval `evals/workflow-parse-check.sh` proves the wrap
  is load-bearing: the vendored file passes, bare `node --check` rejects
  it, and a seeded syntax error fails loudly.
- **Engine-workflows reference entry** (#553, Epic #539):
  `docs/reference/engine-workflows.md` documents the Workflow-runtime
  module surface — the async-body module shape and parse-check, the
  governing architecture's typed-hand-off and `jq`+`ajv` write-validate
  rules, and the `research-goal` module (phases, args with in-repo
  defaults, bounded repair loop, typed return). The `/goal-writer`
  positioning is stated where commands are described
  (`docs/reference/commands.md`, `.claude/commands/goal-writer.md`): the
  command stays the interactive, user-facing path; the workflow is the
  engine path a pipeline composes — and for engine-composed goal
  authoring, deterministic chaining with `ajv` + verifiability gates
  supersedes prompt-discipline gating. Regression eval
  `evals/workflow-docs-check.sh` keeps the page bidirectionally honest
  with the module set and keeps the positioning/supersession note from
  silently regressing.

## 0.16.4 - 2026-07-17

### Fixed

- **`release.yml` no longer uploads to a release after it is published**
  (#537): the workflow now triggers on the `vX.Y.Z` tag push itself, builds
  and attests the tarball, fail-closed re-verifies the attestation, and
  creates the GitHub Release with the attested tarball attached in the same
  `gh release create` call — never a separate post-publish upload, which
  GitHub immutable releases reject outright (HTTP 422) and which previously
  burned a release tag (v0.8.0 → v0.8.1). Added
  `evals/release-workflow-immutable-safe.sh` as a permanent regression test.

## [0.16.3] - 2026-07-16

### Added

- **verify.sh gate selector and built-in profiling** (#531): `--gates <ERE>`
  runs only gate functions whose name matches the pattern, with the summary
  line loudly marked `[SCOPED RUN: ... matched N/M gates]` so a scoped run
  can never masquerade as the full suite; `VERIFY_PROFILE=1` prints
  per-gate wall seconds as gates finish plus the slowest five at the end.
  Regression eval `evals/verify-selector.sh` covers the scoped-and-loud
  contract, the profiling output, and the fail-fast unmatched pattern.
  Together with 0.16.2's stdin-hang and eval-dedup fixes this closes #531
  (full suite 5m53s -> ~1m25s; scoped iteration is seconds).

## 0.16.2 - 2026-07-16

### Fixed

- **Gate suite no longer hangs on inherited stdin** (#531): an explicit
  `--content ""` to `wrap-source.sh` was treated as "content not provided"
  (both by the wrapper's `[ -n ]` test and by the engine's own
  empty-means-absent fallback), silently switching to the engine's stdin
  path — which blocks forever in `read()` whenever stdin is an open,
  never-EOF pipe, exactly what backgrounded invocations of
  `verify.sh`/`run-evals.sh` hand every descendant via the smoke test's
  empty-content refusal case. The wrapper now forwards an explicit
  `--content` (even empty) and detaches the engine's stdin on every
  explicit-content path; `verify.sh`, `run-evals.sh`, and `smoke-test.sh`
  detach stdin outright (no gate path reads it); a regression eval
  (`evals/stdin-detach.sh`) runs both paths under a deliberately
  never-EOF stdin.

## 0.16.1 - 2026-07-16

### Fixed

- **TF-IDF fallback noise floor** (Epic #518 live-acceptance finding): a
  candidate sharing exactly one common token with the query terms (e.g.
  "notes" in a release-notes tool against a git-notes domain) could clear
  the default recommendation threshold through the tfidf-fallback path.
  The fallback now requires at least two distinct query tokens in the
  candidate (the same rationale as the concordance MIN_LABEL_OVERLAP rule)
  -- a candidate that fully matches any term or concordance node never
  reaches the fallback, so no genuinely matching candidate is demoted. A
  single-token sentinel fixture (I6-fieldnotes) joins the golden-set
  relevance eval, verified to fail without the fix.

## 0.16.0 - 2026-07-16

### Added

- **First-class monitoring domains** (#521, #522): a top-level
  `monitoringDomains[]` block in harness.config.json -- current-events
  domains of interest at the operator's discretion (name, weight,
  queryTerms, curated sources, schedule, optional `projectToTopic`
  binding), decoupled from topics[]. `run-monitoring.sh` and the gate
  resolve their subject argument domain-first with the topic-bound
  `continuousMonitoring` block as the fully supported special case; a
  domain's runs live under `reports/_monitoring/<id>/`.
- **Momentum ranking with a prior-coverage memory** (#523):
  `interest-match` merges candidates surfacing the same item across
  sources and ranks by independent source count, engagement evidence (HN
  points+comments), relevance, then recency -- every factor recorded on
  the recommendation (`momentum`, `domain`, `weight`). Items accepted by
  the Editorial Gate in earlier runs are suppressed via
  `reports/_monitoring/prior-coverage.jsonl`, written ONLY by the
  gate-accept path (`recommend.py coverage-append`, single-writer
  discipline).
- **Versioned per-run digest** (#524): `render-digest.sh` emits the
  Editorial Gate's human review surface (`Digest format: v1` marker;
  per candidate a headline, domain/weight, momentum evidence, relevance,
  prior-coverage status, and source URLs). `monitor.yml` uses it as the
  review PR's body; the SKILL.md documents the identical in-session
  review.
- **Dual-runtime parity documented and evaled** (#525): one command per
  path (Actions `workflow_dispatch` vs in-session script invocation) side
  by side in the how-to, both calling the same scripts; the
  `monitoring-domains` eval asserts identical fixture inputs produce
  byte-identical recommendations across runs, plus schema/resolution,
  momentum/memory, digest, and gate round-trip coverage.

## 0.15.4 - 2026-07-16

### Fixed

- **continuous-monitor's workflows are deliverable to copier instances**
  (#517): `copier.yml` excludes `.github/workflows/*` wholesale, so no
  instantiated clone could ever receive `monitor.yml`/`monitor-gate.yml` —
  the pack's documented unattended production callers — and the how-to
  documented commands that cannot work in an instance. The canonical
  workflow sources now ship inside the pack
  (`packs/monitoring/continuous-monitor/workflows/`, which copier delivers),
  and the new `scripts/install-monitoring-workflows.sh` materializes them
  into a clone's `.github/workflows/` as a documented, idempotent,
  drift-aware opt-in (`--check` reports without writing; a disabled pack is
  noted loudly, not silently). The how-to now walks instance owners through
  the install step instead of asserting the workflows are already there.

### Added

- **`gate_monitoring_workflow_sync` in `verify.sh`**: every installed
  monitoring workflow must be byte-identical to its pack source (the
  template must always carry live copies; an instance without them simply
  hasn't opted in), so a `copier update` that changes a pack workflow source
  can't leave a stale installed copy behind silently.
- **Workflow-install eval** (`evals/monitoring-workflow-install.sh`):
  regression coverage for #517 against a throwaway fake-instance tree —
  pack ships both sources; install is byte-identical, idempotent, and
  drift-aware; the disabled-pack advisory is emitted.

## 0.15.3 - 2026-07-16

### Fixed

- **continuous-monitor connectors dispatch `queryTerms[]` as atomic
  terms/phrases per each API's own query grammar** (#513): `run-monitoring.sh`
  previously space-joined every term into one blob that arXiv exploded into
  OR-of-single-words (151,074 results in the live comparison — the newest N
  arbitrary papers on the archive) and HN Algolia treated as AND-of-all-words
  (0 results). Connectors now take a JSON array of terms and build
  phrase-quoted boolean OR in one request (arXiv, PubMed, GDELT) or dispatch
  one request per term with merge/dedup by id (HN, OpenAlex, Crossref,
  Semantic Scholar).
- **Interest-Inference scores against the monitored topic, not the whole
  corpus** (#514): concordance matching is scoped to nodes tagged with the
  run's topic (`--topic`), and the topic's `queryTerms` are a first-class
  scoring signal (`inference_method: "query-terms"`) instead of a fallback
  that corpus-scale matching never allowed to fire. Previously any candidate
  sharing two tokens with any label anywhere in a 55-topic corpus cleared the
  recommendation threshold — a pure-mathematics paper "matched" a git-notes
  topic via an agriculture-technology node.
- **GDELT connector reports rate limiting as rate limiting** (#515): GDELT
  enforces its request spacing by returning HTTP 200 with a plaintext notice,
  which previously surfaced as a misleading `jq parse error`. The connector
  now detects the notice (`connector_guard_json`), retries once after
  `GDELT_RETRY_DELAY_SECONDS` (default 6), and fails closed with the true
  cause in the Continuity Log.

### Added

- **Relevance eval for continuous monitoring** (#516): a golden-query-set
  eval (`evals/monitoring-relevance.sh`) over recorded fixtures asserts, at
  the production default threshold, that zero known-irrelevant candidates and
  at least 80% of known-relevant candidates are recommended — the guardrail
  whose absence let #513/#514 ship green — plus a topic-scoping regression
  sentinel that corpus-global scoring would recommend.
- **Connector query-construction eval** (`evals/monitoring-query-construction.sh`):
  offline regression coverage for per-API query dispatch (#513) and the GDELT
  HTTP-200 rate-limit notice handling (#515), via a recorded-fixture
  `connector_fetch` override seam in `connector-common.sh`.

## 0.15.2 - 2026-07-15

### Added

- **`verify.sh` structurally checks that every `gate_*` function reading a
  copier-excluded doc file carries an `IS_TEMPLATE` guard** (#507): two
  separate gates (`gate_changelog_links` #401, `gate_milestone_docs` #505)
  each unconditionally failed in every instantiated clone because they read
  a file `copier.yml`'s `_exclude` list deliberately keeps out of instances,
  with no guard — caught only by a human/agent noticing after the fact, both
  times. The new `gate_is_template_guard_hygiene` extracts the literal doc
  filenames from `copier.yml`'s `_exclude` list and flags any `gate_*`
  function referencing one with no `IS_TEMPLATE` guard anywhere in its body,
  so a third gate can't reintroduce the same defect silently.

## [0.15.1] - 2026-07-14

### Fixed

- **`falsification-analyst`'s weakened-remediation could push a finding's
  `summary` past the MIF schema's 500-char cap** (research-harness-template#503):
  the agent's Step 7 remediation appended a "Falsification note" qualifier to
  `summary` with no length bound, so a verbose qualifier could push the field
  over `maxLength` — observed up to 723 chars, 5 of 19 weakened findings in
  one gate run, discovered only after the fact by `reconcile-session.sh`
  rather than at write time. Step 7 now truncates in two stages: the
  qualifier itself is capped first (trimming the verdict-basis text it
  wraps, not the fixed template around it), then the original summary is
  truncated to whatever budget remains under the cap, which is inherited
  from the vendored MIF schema and is never raised here. Step 6's
  re-validation `ajv` command was also missing the
  `entity-reference.schema.json` ref that `write-finding.sh` and
  `dimension-analyst.md` both include, so some ref-dependent violations could
  slip past the analyst's own check.

## [0.15.0] - 2026-07-14

Release-pointer advance only (ADR-0010) — no new component changes of its
own. Cuts a release bundling everything merged since `v0.13.0`, each already
documented in its own dated section below (most recently the bash 3.2
array-expansion fixes in #498/#500 and the milestone-docs backfill in #501).

## [0.14.1] - 2026-07-14

### Added

- **Backfilled `COMPLETION-CRITERIA.md` and `IMPLEMENTATION-PLAN.md` through
  Milestone/Phase 32** (research-harness-template#443): both docs had been
  dramatically stale — `COMPLETION-CRITERIA.md`'s last documented milestone
  was 13 and `IMPLEMENTATION-PLAN.md`'s last phase was 8, while
  `scripts/verify.sh` had already grown through `gate_m32`. Reconstructed
  Milestone 9 and Milestones 14 through 32 in `COMPLETION-CRITERIA.md`, and
  Phases 9 through 32 in `IMPLEMENTATION-PLAN.md` (MIF I/O conformance, session-recovery
  durability, ontology conformance, the falsification phase-gate, goal
  evolution, the Diátaxis channel, README freshness, the ADR-0011 fail-closed
  ontology-completeness gate, the cross-topic corpus atlas, the full
  ADR-0017 MIF Container export/import format, and the ADR-0018 mif-docs
  conformance floor) directly from each `gate_mN` function body and its
  originating issue/PR references — a full historical backfill, not a
  fresh-start convention, since the reconstruction data was traceable. Added
  a new `gate_milestone_docs` drift-prevention gate to `scripts/verify.sh`
  comparing the highest `gate_mN` in `GATES=(...)` against the highest
  documented milestone/phase in both files, so this cannot silently drift
  again.

### Fixed

- **Guarded remaining unbound-variable-risk `"${arr[@]}"` expansions for bash
  3.2** (research-harness-template#499): stock, unpatched macOS bash treats
  `"${array[@]}"` on a zero-element array as unbound under `set -u`, even when
  the array was declared with `array=()`. Applies the same
  `"${arr[@]+"${arr[@]}"}"` guard used to fix #496 (PR #498) to every other
  occurrence found by re-auditing the current tree: `scripts/resolve-ontology.sh`,
  `scripts/wrap-source.sh`, `scripts/fetch-ontology.sh`,
  `scripts/render-artifact.sh`, `scripts/backfill-report-slugs.sh`,
  `scripts/codegen/gen-models.sh`, `scripts/verify.sh`,
  `scripts/build-topic-readme.sh`,
  `packs/monitoring/continuous-monitor/scripts/run-monitoring.sh`,
  `packs/channels/diataxis/scripts/render-diataxis.sh`,
  `evals/mif-container-nfr-verification.sh`, and
  `.claude/skills/ontology-manager/scripts/scaffold_ontology.sh`.

### Changed

- **Continuous monitoring repackaged as a pack** (`packs/monitoring/continuous-monitor`,
  research-harness-template#483): Epic #416's `scripts/monitoring/**` moved to
  `packs/monitoring/continuous-monitor/scripts/**` with its own `plugin.json`
  and `SKILL.md`, wired through `harness.config.json` `packs[]` like every
  other pack. `harness.config.json` `packs[]` now needs
  `{"name": "continuous-monitor", "enabled": true}` in addition to a topic's
  own `continuousMonitoring.enabled: true` — both gates are required, checked
  by `run-monitoring.sh` and `monitor.yml` before anything runs. `monitor.yml`
  and `monitor-gate.yml` are updated to call the new script paths; docs
  (`pack-structure.md`, `packs-and-plugins.md`, `packs/monitoring.md`,
  `coverage.md`, `dependencies.md`, `scripts.md`,
  `enable-continuous-monitoring.md`) are reconciled to match. Fixed a
  pre-existing latent bug found during the move: an apostrophe inside a
  bash single-quoted jq filter in `semantic-scholar.sh`'s connector broke
  the script's own syntax.

## [0.14.0] - 2026-07-12

Epic #416: Continuous Research-Monitoring Capability. A periodically-triggered
scan of weekly news, academic/preprint papers, and current-events signals,
scored against the harness's existing knowledge, with every candidate
recommendation gated through human PR review before anything publishes.

### Added

- **ADR-0019** settles the scheduling/trigger primitive: GitHub Actions cron,
  not a cloud Routine, with write-back via a review PR that doubles as the
  Editorial Gate (research-harness-template#417).
- **Eight Source Connectors** (`scripts/monitoring/connectors/`): arXiv,
  OpenAlex, Crossref, Semantic Scholar, PubMed, bioRxiv/medRxiv, GDELT DOC 2.0,
  Hacker News — each a free, keyless `curl`+`jq` client, no SDK, opt-in
  enhancement env vars default off (research-harness-template#418).
- **Interest-Inference Engine** (`scripts/monitoring/interest-inference.sh`)
  scores candidates against `reports/concordance.json` with a dependency-light
  TF-IDF fallback for uncovered topics; refuses to score against a stale
  concordance (research-harness-template#419).
- **Recommendation Engine** (`scripts/monitoring/recommend.sh`): interest-match
  and gap-detect modes, every recommendation carrying at least one MIF
  citation enforced in code (research-harness-template#420).
- **Continuity Log + fail-closed budget** (`scripts/monitoring/lib/continuity-log.sh`,
  `run-with-budget.sh`): every ingestion failure or budget breach is recorded,
  never silent (research-harness-template#421).
- **Editorial Gate** (`scripts/monitoring/editorial-gate.sh`): structural
  human-review checkpoint, fail-safe default (no decision = rejected), with a
  no-bypass invariant enforced before publish (research-harness-template#422).
- **Output Router** (`scripts/monitoring/output-router.sh`) hands accepted
  recommendations to the existing `publish-report`/`publish-blog` skills
  unmodified — no new output channel (research-harness-template#423).
- **`.github/workflows/monitor.yml` + `monitor-gate.yml`** implement ADR-0019
  end to end: a scheduled run opens one review PR per topic; merging or
  closing it drives accept/reject (research-harness-template#424).
- **`harness.config.json`'s per-topic `continuousMonitoring` block** (schedule,
  queryTerms, sources, budgetSeconds, maxResultsPerSource,
  recommendationThreshold), shipped disabled on the bundled example topic.
- **`evals/monitoring-pipeline.sh`** dry-run eval covering the fail-closed,
  Editorial Gate no-bypass, and full accept-to-publish paths
  (research-harness-template#425).
- **`docs/how-to/enable-continuous-monitoring.md`** operator how-to.

### Fixed

- `reports/concordance.json` had drifted stale since #229 (PR #253's
  retro-classification never triggered a rebuild) — caught by the new
  Interest-Inference freshness guard, rebuilt.
- ADR-0019 initially used this repo's `docs/adr/template.md` shape, which
  cannot be provenance-stamped or pass real `structured-madr` validation
  (missing `## Links`, invalid Audit status). Authored via the `mif-docs:adr`
  skill instead; now passes `smadr` strict mode and MIF conformance levels
  1-3 against the real Action. The same gap affects every other ADR in this
  repo (already tracked, research-harness-template#435).

## [0.13.1] - 2026-07-12

### Fixed

- Added the `[0.13.0]` footer compare-link now that the `v0.13.0` tag exists,
  per #393's convention — it could not be added in the same PR that stripped
  `0.12.3`'s heading brackets, since the tag didn't exist yet at that point.
- **`scripts/build-topic-readme.sh` trims a truncated title's trailing
  whitespace.** The `mif-rh-cli` engine's `harness topic-metadata` cuts a
  long `goal_statement` to build `TITLE` at a fixed character count with no
  word-boundary awareness (modeled-information-format/mif-rs#86); when the
  cut lands right after a space, the generated README's H1 kept the
  trailing space and failed markdownlint's MD009. The script now trims
  `TITLE` defensively after the engine `eval`, independent of when the
  upstream engine bug itself is fixed.

## [0.13.0] - 2026-07-12

Epic #405: `mif-docs-plugin` adopted as the single document-tooling and
provenance substrate for every document-shaped deliverable this harness
produces — closing the gap #228's genre-consolidation left open (schema
conformance via the harness's own vendored `ajv` closure, ADR-0002, but no
witnessed, hook-observed provenance and no wiring for `docs/` at all).

### Added

- **`mif-docs-plugin` wired as a declared, pinned dependency.** `.mcp.json`
  gains the `mif-mcp` server; `.claude/settings.json` gains a top-level
  `mifProvenance: {capture: true, stamp: "auto"}` key read directly by the
  plugin's own `provenance-config.mjs` (research-harness-template#406).
- **ADR-0018** documents `mif-docs-plugin` as the document-tooling and
  provenance substrate, and the deprecation policy every retirement in this
  Epic follows: a document type duplicating an existing `mif-docs` genre gets
  retired outright, not kept in parallel (research-harness-template#407).
- **The canonical report channel now stamps `mif-docs`-witnessed provenance**
  on every rendered `reports/<topic>/<slug>.md` — `report-synthesizer.md`'s
  new Step 4d invokes `Skill(mif-docs:mif-provenance)` after rendering
  (research-harness-template#408).
- **`verify.sh`'s new `gate_m32`** structurally enforces the mif-docs
  conformance floor on every tracked document deliverable: `mif-validate
  --level 1` on every checked file, and `--level 3` (unconditionally, no
  exemptions) on every file that declares a `provenance:` block — proving
  the block is structurally well-formed, not merely present. A fresh CI
  runner has no session ledger, so this can only ever prove structural
  well-formedness, never witnessed authorship — that remains a live-session
  question. New `scripts/fetch-mif-docs-plugin.sh` clones the plugin at its
  pinned SHA into a fail-closed, gitignored cache so CI (and any contributor)
  can run `mif-validate` without a separate sibling checkout
  (research-harness-template#413).

### Changed

- **`architecture-spec`, `feature-spec`, and `kiro-spec` bundled genre packs
  are retired**, in favor of direct `marketplace-ref` consumption of five
  `mif-docs-plugin` genres: `ai-architecture-doc`, `feature-spec`,
  `kiro-requirements`, `kiro-design`, `kiro-tasks`. The `kiro-spec` genre had
  no 1:1 successor — it is replaced by three independently selectable
  genres, each rendered by a separate invocation of the `ai-spec` channel
  (research-harness-template#409, #414).
- **`docs/` (ADRs, Diátaxis explanation/how-to/reference/tutorials, proposals)
  audited against `mif-docs` conformance.** ADRs stay exempt (structured-madr,
  not `mif-validate`, per `mif-docs-plugin`'s own ADR-0001); every other
  tracked doc confirmed or brought to MIF Level 1, with a documented
  authoring convention added to `docs/README.md`
  (research-harness-template#410).
- **`packs/market-research/*` and `packs/trend-modeling/*` audited for
  `mif-docs` duplication** — confirmed no overlap (they are findings-
  methodology skills, not rendered-document genres) and given explicit
  non-duplication disposition notes (research-harness-template#411).
- **All ten channel packs audited for provenance/citation-grounding
  compliance** against Epic #405 / ADR-0018 — confirmed no channel drops
  citation grounding between its sources and its rendered output; `diataxis`
  flagged as a candidate for a future L3/witnessed-provenance upgrade, not
  silently left unconsidered (research-harness-template#412).

### Fixed

- Two files declared `provenance:` without the separately required
  `temporal:` block (`docs/reference/dependencies.md`,
  `docs/reference/mcp-server.md`, among 22 total across `docs/` and the
  example-corpus fixtures) — real gaps `gate_m32`'s uniform, no-exemption
  L3 check caught, not waved through with a carve-out
  (research-harness-template#413).
- Post-migration deprecation sweep (research-harness-template#414): two
  fixture files declared retired genre names with no valid successor
  reference (`architecture-spec` → renamed to its 1:1 successor
  `ai-architecture-doc`; `kiro-spec` → split into the three fixture files
  matching its three genre successors, since no 1:1 successor exists); an
  orphaned worktree lock tied to a three-day-dead process was removed after
  verifying it held zero unmerged commits; four files from unrelated
  concurrent PRs were missing the same required `temporal:` block `gate_m32`
  enforces.

## 0.12.3 - 2026-07-12

### Fixed

- `gate_changelog_links` (#397) no longer runs in an instantiated clone, where
  it always failed: an instance's own git remote never carries the template's
  `v*` release tags, so the gate had no real tag history to check footer
  compare-links against. Guarded with the existing `IS_TEMPLATE` flag
  (`scripts/verify.sh:31`), the same template-only-skip pattern `gate_m7`
  already uses (#401).
- `reports/example-okf-mif-knowledge-spine/synthesis-okf-mif-knowledge-spine.md`
  (part of the shipped, AS-IS example corpus) had an invalid
  `conceptType: synthesis` (not one of `semantic`/`episodic`/`procedural`) and
  a bare `created: 2026-06-28` date instead of a `date-time` string, failing
  external MIF tooling (`mif-rs`/`mif-mcp`) schema validation on every
  instance. Changed to `conceptType: semantic` and
  `created: "2026-06-28T00:00:00Z"` (#402).

## [0.12.2] - 2026-07-11

### Added

- CI now enforces that every `CHANGELOG.md` footer compare-link resolves to a
  real git tag (`scripts/verify.sh`'s new `gate_changelog_links`,
  deliberately narrow so it never fails on the normal bumped-but-not-yet-tagged
  resting state between releases) (#397).
- `release.yml` runs `mif-rh-cli harness reconcile-changelog-links --check`
  after a release publishes and posts a warning annotation if the CHANGELOG
  needs heading-bracket/footer-link reconciliation, without gating the
  release or any other PR (#397).

### Changed

- Pinned `mif-rh-cli` engine version bumped `0.6.1` -> `0.7.0`
  (`scripts/fetch-engine.sh`, `scripts/lib/engine.sh`) to pick up
  `reconcile_changelog_links`/`harness reconcile-changelog-links`
  (research-harness-template#397, mif-rs#82).

### Fixed

- `CLAUDE.md` no longer claims markdownlint's MD052 enforces the CHANGELOG
  bracket/footer invariant — verified empirically false (0 errors on a
  bracketed heading with no matching footer link); `gate_changelog_links`
  enforces it instead.

## [0.12.1] - 2026-07-11

### Fixed

- `scripts/run-lock.sh steal` now refuses (exit 3, unless `FORCE=1`) when a
  topic's `findings/` or `research-progress.md` shows write activity within
  the guard window (`RUN_LOCK_STEAL_GUARD_MIN`, default 10 minutes), closing
  the race where a misread agent-liveness signal
  (e.g. `TaskOutput` reporting `completed` for a still-working orchestrator)
  could force a lock steal against a genuinely-alive writer (#392).
- `start.md`/`resume.md`'s "Monitoring a running session" guidance now
  explicitly warns that `TaskOutput`'s `completed` status on the
  orchestrator's own `Agent` call is not sufficient evidence a session died —
  only the disk-state signals (static finding count and no new progress-log
  entry) are authoritative (#392).
- `orchestrator.md`'s Phase 1/Phase 2 background-spawn poll loops are worded
  more forcefully, with an explicit self-check, so the model can't substitute
  a "wait for completion notification" narration for the required synchronous
  `Bash` poll loop (#392).
- `CHANGELOG.md`'s footer compare-links now only reference tags that were
  actually cut, comparing each release against the previous *real* tag
  instead of the adjacent dated section's version string; backfill-corrected
  the ~9 dated sections that were folded into a later release without ever
  getting their own tag (#393).

## [0.12.0] - 2026-07-11

### Added

- **`reports/_corpus/README.md`**: `scripts/build-topic-readme.sh` gained a
  `_corpus` mode, delegated to from `scripts/synthesize-corpus.sh`, that
  renders a navigable corpus-atlas README alongside `corpus-map.json`/
  `corpus-synthesis.md` — a topic table, verdict/entity/contradiction
  counts, and a Purpose section preserved across rebuilds (#352).

### Changed

- **`scripts/lib/engine.sh` / `scripts/fetch-engine.sh`**: bumped the pinned
  `mif-rh-cli` engine from `0.6.0` to `0.6.1`, picking up the upstream fix
  for `attempted_at` recording as epoch-0 (closes #363, #389).
- **Dependencies**: patch-bumped `astro` (`7.0.3` -> `7.0.7`), `@astrojs/starlight`
  (`0.41.1` -> `0.41.3`), `starlight-links-validator` (`0.25.1` -> `0.25.2`),
  `starlight-llms-txt` (`0.10.0` -> `0.11.0`). Astro's newer default Markdown
  processor ("Sätteri") requires `remarkPlugins`/`rehypePlugins` users to
  install `@astrojs/markdown-remark` explicitly, now added as a direct
  dependency.
- **`scripts/codegen/gen-models.sh`**: bumped the pinned dev-time
  `datamodel-code-generator` from `0.65.0` to `0.68.1` — generated
  `lib/harness_models/*.py` output is byte-identical, no regeneration diff.
- **CI**: bumped the Python runtime pin from `3.12` to `3.14` (`3.12` exited
  upstream bugfix support in 2025-04; `3.14` is in active bugfix support
  until 2027-10). `actions/setup-python` bumped `v6.2.0` -> `v6.3.0`,
  `actions/attest-build-provenance` bumped `v4.1.0` -> `v4.1.1`. Node stays
  pinned at `24` (Active LTS until 2028) — `26` doesn't reach LTS until
  2026-10-28, so it was evaluated and deliberately held back.
  `docs/reference/dependencies.md`'s runtime table is corrected to match the
  actual CI pins (it previously described `node` as floating `lts/*` and
  `python3` as declared `3.12`, neither of which matched `ci.yml`).

### Fixed

- **`.claude/commands/start.md`**: Phase 2 topic-title derivation now strips
  known goal-statement boilerplate phrasing and enforces a word-boundary-safe
  80-char truncation, and always asks the user to confirm the derived title
  (not only when truncation fired) before registering the topic (#353, #391).

### Security

- Evaluated bumping the `js-yaml` npm override (pinned to `4.2.0` to
  remediate CVE-2026-53550 / GHSA-h67p-54hq-rp68, #149) to the latest
  `5.2.1`. Reverted: `@astrojs/starlight` still does a default import of
  `js-yaml` (`import yaml from 'js-yaml'`), which `5.x` no longer exports,
  breaking `npm run build` outright. The `4.2.0` pin already remediates the
  CVE; staying on it is not a security regression.

## 0.11.2 - 2026-07-09

### Fixed

- **`harness.config.schema.json`**: added the missing `"complete"` value to
  `topics[].status`'s enum. The orchestrator's Phase 4 ("Update the topic
  status") and `/topics`' own documented `--filter` example both already
  used `"complete"`, but the schema only declared `active`/`paused`/`archived`,
  so every full research session's Phase 4 step failed `ajv validate` and
  left `harness.config.json` in an invalid state after a successful run.

## 0.11.1 - 2026-07-07

### Added

- **`docs/how-to/negative-examples-curation-workflow.md`**: the reusable,
  multi-agent confusion-driven curation workflow for scaling
  `negative_examples` curation (MIF ADR-020) across many confusion pairs at
  once (#271).
- **`ontology-manager` skill** (`0.4.3` -> `0.5.0`): a new
  `references/negative-examples-curation.md` and decision-tree entry
  codifying the corpus-regen/baseline/partition/draft steps as executable
  guidance for spinning up parallel drafting agents (#271).
- **Local `pre-push` git hook**: enforces the ADR-0010 change-driven
  versioning gate (`scripts/check-version-bump.sh`) before a push leaves
  your machine, not just in CI. Installed automatically via
  `git config core.hooksPath .githooks`, wired through `npm install`'s
  `postinstall`.

## [0.11.0] - 2026-07-07

### Added

- **`mif-rh-cli` powers 30 scripts previously implemented in bash+jq** (#276):
  ontology vendoring/cataloging/authoring (`fetch-ontology.sh`,
  `sync-packs.sh`, `check-ontology-lock.sh`, `sync-registry-ontologies.sh`,
  `author-ontology.sh`), corpus/concordance synthesis (`synthesize-corpus.sh`,
  `import-corpus.sh`, `build-concordance.sh`, `reconcile-session.sh`,
  `synthesize-artifact.sh`, `build-topic-readme.sh`), validation gates
  (`assert-graph-mif.sh`, `check-citation-integrity.sh`,
  `check-shippable-typing.sh`, `falsify.sh`, `check-relationship-targets.sh`,
  `validate-concordance.sh`, plus `verify.sh`'s two whole-registry ontology
  scans), graph/index/membership/rendering (`build-graph.sh`,
  `build-graph-viz.sh`, `build-index.sh`, `resolve-membership.sh`,
  `render-artifact.sh`), versioning/release orchestration
  (`bump-version.sh`, `goal-version.sh`, `check-version-bump.sh`,
  `mif-project.sh`), and feature toggles/packaging (`site-toggle.sh`,
  `pack-toggle.sh`, `wrap-source.sh`). Requires mif-rh-cli >= 0.5.0.

### Fixed

- **CI**: `verify.sh`'s cross-pack relationship-reference and subtype_of
  gates now surface the engine's actual error instead of a misleading
  "orphans found" verdict when the engine call itself fails.
- **CI**: the standalone `copier-update` eval and the version-bump job now
  provision the engine correctly (a fresh copier-generated instance has no
  engine of its own to resolve).
- **CI**: workflow steps that read public release artifacts now mint a
  short-lived App token instead of relying on the ambient `GITHUB_TOKEN`.

## 0.10.1 - 2026-07-06

### Added

- Documented `negative_examples` scoring and the `calibrate --confusions`
  confusion-matrix export, both shipped in mif-rh engine v0.4.0: a new
  curation-workflow section in the engine-cli reference, a new step in
  the classification-engine-loop how-to, a real explanation of the
  non-reordering demotion gate in the classification-engine explanation
  page, and the `negative_demoted`/`negatives_active` fields in the
  mcp-server reference. Bumps the pinned engine version to 0.4.0 in
  `scripts/fetch-engine.sh` and `docs/reference/dependencies.md`.
  Closes #268.

## [0.10.0] - 2026-07-06

### Added

- Registered two new domain ontologies published to the canonical registry
  since the last sync: `heliophysics` and `non-ionizing-radiation` (both
  enabled by default, per `sync-registry-ontologies.sh`'s discovery pass).

### Changed

- Re-vendored every enabled domain ontology pack against the current
  `mif-spec.dev/ontologies` registry index (a fresh `ontologies.lock.json`
  is instance-derived and gitignored in the template, so nothing else here
  is tracked).

## [0.9.0] - 2026-07-05

### Added

- **MCP server wiring** — `scripts/fetch-engine.sh` installs
  `mif-rh-mcp` beside the CLI (same attested, fail-closed download),
  a repo-root `.mcp.json` registers the stdio server for agent
  sessions, and the classification-loop runbook documents the four
  read-only tools and the `--build-index` prerequisite. The template's
  own automation adopts the tools as optional accelerators with lexical
  fallback: the search skill's `--sem` backend is now the engine index,
  dimension-analyst runs a `find_similar` prior-art check before
  emitting findings, corpus-synthesizer can lean on `corpus_stats` and
  semantic lookup during synthesis, and the orchestrator documents the
  ADR-0015 suggest/calibrate cadence after classification passes.

### Changed

- **Engine-only classification (ADR-0016)** — `resolve-ontology.sh` and
  `ontology-review.sh` are now thin wrappers over the `mif-rh` engine
  (`mif-rh-cli` v0.3.1+, hard required; byte-parity with the retired bash
  implementations is enforced fail-closed in mif-rs CI). Provisioning:
  `scripts/fetch-engine.sh` installs an attestation-verified release binary
  to `bin/`; a PATH install or an explicit `MIF_RH_CLI` override also work.
  A missing or too-old engine fails loudly with the remedy; there is no
  silent fallback.

## 0.8.4 - 2026-07-02

### Fixed

- **`render-artifact.sh` stamped an absolute filesystem path into `slug:` when
  `$OUT` was passed as an absolute path** (`report-synthesizer.md`'s own
  documented usage passes an absolute `$REPORTS_DIR`). `SLUGPATH` was derived
  from a bare `dirname "$OUT"`, so an absolute `$OUT` leaked the caller's full
  filesystem path into the rendered frontmatter's `slug:` key -- a route the
  site's cross-link rewriter cannot resolve. `$OUT` is now normalized to
  absolute and stripped of the repo root before deriving `SLUGPATH`, so
  `slug:` is always repo-root-relative regardless of how the caller passed
  `$OUT`. `REPO_ROOT` resolves `pwd` logically, not physically (`pwd -P`):
  callers build `$OUT` with plain `$(pwd)`, so a physical `REPO_ROOT` would
  diverge from that prefix on a checkout reached through a symlink, silently
  reproducing the same leak (caught in review).

## [0.8.3] - 2026-07-02

### Fixed

- **`ontology-review.sh` silently folded discovery-basis guesses into "typed", hiding
  corpus-wide ontology gaps.** `resolve-ontology.sh`'s content-pattern discovery
  fallback (for a finding with no `entity` block) records its guess with
  `basis: "discovery"` and `valid: true`, but never writes that guess back to the
  finding — nothing durable exists on disk. The review script counted any
  `valid: true` record as typed regardless of `basis`, so a topic could read as 100%
  classified while zero of its findings carried a real ontology stamp. The
  ADR-0011 fail-closed shippable-typing gate (`check-shippable-typing.sh`) and its
  `reconcile-session.sh` mirror had the same gap: both checked `basis` against only
  `untyped`/`unresolved`, so a discovery-only shippable finding could ship with no
  durable classification despite the gate's stated fail-closed contract.
- `ontology-review.sh`'s coverage table and summary line now report STAMPED
  (declared/resolved — a real `entity_type` on disk) separately from DISCOVERY
  (guessed, unpersisted); `--strict` is unchanged (still fails only on
  invalid/unresolved, not on discovery-only or untyped — those are backlog, not
  corruption).
- Added `ontology-review.sh --followup <path>`: writes a deterministic JSON backlog
  of every finding that is not durably stamped (discovery-only, untyped, or
  invalid/unresolved), grouped by topic, for tracking and retro-classification.
- `check-shippable-typing.sh` and `reconcile-session.sh` now also block/count a
  shippable finding whose ontology-map record is `basis: "discovery"`, matching
  their existing treatment of `untyped`/`unresolved`.
- Retro-classified the 15 findings in the bundled `example-okf-mif-knowledge-spine`
  topic that the discovery-basis fix above surfaced as never durably stamped.
  Each finding's `entity` block now carries a real `entity_type` chosen from its
  actual content, not the original regex discovery guess (which had put all 15
  under a W3C PROV-O provenance-record type that didn't fit). The topic now
  reads 36/36 stamped, 0 discovery-only.
- **The site's deploy base path was a hardcoded literal (`/research-harness-template`)
  in `astro.config.mjs`, contradicting that file's own stated design** ("neither the
  template nor a clone hand-edits THIS file"). Every clone actually deploys somewhere
  different (site root, a GitHub Pages project page, a custom sub-path), so a clone
  serving from `/` had every internal link 404 unless it hand-patched the supposedly
  byte-identical engine file.
- Added `harness.config.json` `.site.base` (schema + `astro.config.mjs` now reads
  `siteCfg.base ?? "/"`). Default is site root (`/`); the template's own
  `harness.config.json` sets it explicitly to `/research-harness-template` to
  preserve its real GitHub Pages deployment.
- `docs/index.mdx` (the splash page) had every internal link hardcoded with the
  template's own `/research-harness-template` prefix, a literal string independent
  of any config — the only place in the docs tree with this anomaly. Links are now
  base-relative (`/reports/`, `/tutorials/getting-started/`, ...), letting Starlight
  inject the configured base like every other internal link already does.
- `scripts/verify.sh` gate_m23's reports-landing check updated to match (asserts
  the base-relative `link: /reports/`, not the old hardcoded literal).

## 0.8.2 - 2026-07-01

> This entry collapses five version-bump commits (0.9.0, 0.10.0, 0.11.0,
> 0.11.1, 0.11.2) that landed on `main` without ever being cut as a GitHub
> Release. The actual last published release is v0.8.1; this is the next real
> release point, carrying all of that work as a single patch step.

### Fixed

- **Genre-suffixed report filenames (`<slug>.<genre>.md`) no longer 404 on the
  served site.** `astro-rehype-relative-markdown-links` slugifies each link's
  path segment with `github-slugger` — a heading-anchor algorithm that strips
  embedded `.` without inserting a separator, producing a mismatched href
  (`fooengineering` instead of `foo.engineering`) even though Astro's own
  content-collection route (which keeps the dot) resolves fine. `render-
  artifact.sh` now stamps an explicit `slug:` frontmatter field — the route the
  content collection already resolves to — which the plugin honors over its own
  computation.
- Added `scripts/backfill-report-slugs.sh`: idempotent, `--dry-run`-capable
  remediation for reports rendered before this fix, across every topic.
- The Reports table's Genre column showed `—` for every canonically-named
  `report-<genre>.md` deliverable (10 of 15 in the example corpus) because
  `render-artifact.sh` never stamped the artifact's own `genre` field into the
  rendered frontmatter, and `build-topic-readme.sh`'s filename fallback only
  recognized the dotted `<slug>.<genre>.md` convention, not `report-<genre>.md`.
  `render-artifact.sh`'s report channel now stamps `genre:` directly (schema-
  required by `artifact.schema.json`); `file_genre()` also gained a
  `report-<genre>.md` filename fallback for reports rendered before the stamp
  existed.
- **The release-pointer version gate required every PR to move
  `harness.config.json`'s `.version` relative to its own merge-base**, so two
  PRs opened against the same `main` commit collided even though neither
  author did anything wrong — whichever merged first bumped the pointer, and
  the second PR's own diff then showed it unchanged against a now-stale base.
  `scripts/check-version-bump.sh`'s release-pointer rule now compares against
  the last actual git tag release instead of a PR's own base, and only fails
  on a real regression (the pointer at or below that tag). A PR that changes
  files without touching the pointer passes as long as the pointer is already
  ahead of the last release. `[skip-version-check]` is retired along with the
  per-PR pointer obligation it used to waive. Per-pack/per-skill bump-on-change
  is unchanged. See ADR-0010's 2026-07-01 amendment.

### Changed

- The `engineering` report genre is now consumed externally from
  [`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
  (SHA-pinned via `harness.config.json` `packs[]`) instead of the bundled
  `packs/reports/engineering` pack, which is retired. This is the pilot genre
  for the genre-consolidation migration onto `mif-docs` as the single genre
  and conformance authority
  (research-harness-template#228). The genre's capability, including the
  optional Mermaid architecture-diagram figure, is unchanged; its MIF
  frontmatter authoring and conformance now go through `mif-docs`' shared
  `mif-frontmatter` / `mif-validate` substrate.
- The 17 remaining bundled report-genre packs are retired in favor of
  external consumption from `mif-docs-plugin`, completing the
  genre-consolidation migration piloted by `engineering`
  (research-harness-template#228): `academic`, `briefing`, `computing-paper`,
  `humanities-mla`, `humanities-chicago`, `clinical-submission`, `nist-sp`,
  `regulatory-disclosure`, `compliance-audit`, `security-pentest`,
  `legal-memo`, `market-research-report`, `sustainability-report`,
  `trend-analysis`, `competitive-quadrant`, `systematic-review`,
  `exec-summary`. There
  is no longer a `packs/reports/` directory — all 18 report genres now
  resolve via `harness.config.json` `packs[].source` `marketplace-ref`
  entries against the shared `mif-docs` marketplace declaration. Genre
  capability is unchanged; each genre's MIF frontmatter authoring and
  conformance now go through `mif-docs`' shared substrate.
- `scripts/check-pack-docs.py`'s external-pack resolution now tracks which
  family each external name actually resolved into, fixing a name-collision
  bug where a report genre and an unrelated ontology sharing the same name
  (`trend-analysis`) could cross-contaminate each other's outbound-link and
  README-exemption checks.

### Added

- **`harness.config.json` `marketplaces[]`** — declare an external Claude Code
  plugin source once (`name`, `url`, a pinned `ref`); any number of `packs[]`
  entries reference it via `source: {type: "marketplace-ref", marketplace:
  <name>}` instead of each repeating an identical `{type, url, ref}` object. A
  pack's own `ref` overrides the marketplace's for that pack only.
  `scripts/sync-packs.sh` and `scripts/check-pack-docs.py` resolve it; a new
  `verify.sh` gate (5d2) proves the sharing and the per-pack override.
- The `engineering` pack's source is migrated from an inline external object
  to a `mif-docs` marketplace reference, ahead of migrating the harness's
  remaining report genres onto it.
- `render-artifact.sh` now stamps a `version:` frontmatter field on every
  rendered report/blog/book, auto-incremented from the file's own prior value
  when a genre is re-rendered for the same topic (previously silently
  overwritten with no on-disk indicator of revision).
- `build-topic-readme.sh`'s Reports table gained a **Genre** column (`Type |
  Genre | Title`), extracted from the deliverable's own `genre:` frontmatter
  (falling back to a dotted-filename convention), with the `version:` field
  appended as `(vN)` when present. Previously every non-canonically-named
  deliverable fell into the generic "Document" `Type` bucket with no way to
  tell genres apart.

## [0.8.1] - 2026-06-30

### Changed

- Re-cut of 0.8.0 (the v0.8.0 tag was bound to a deleted release); no functional changes. See 0.8.0 notes below.

## [0.8.0] - 2026-06-30

### Changed

- **Domain ontology packs are now vendored on demand, not bundled** (#224,
  completing ADR-0012). The 12 domain packs under `packs/ontologies/*` are
  `git rm`'d and the directory is gitignored; only base layers under
  `schemas/ontologies/` ship committed. Clones/CI vendor the enabled packs from
  the canonical registry (`scripts/fetch-ontology.sh --all-enabled`,
  sha256-verified, pinned in `ontologies.lock.json`) before the catalog is built
  — wired into copier `_tasks` and the CI `verify` job ahead of `verify.sh`. The
  `ontologies.lock.json` pin ships committed and `check-ontology-lock.sh` proves
  no drift (#222 follow-through: lock present + gate-clean). `gate_m22` vendors
  its `software-security` subtype_of exemplar on demand. Override the registry
  source for dev/CI/offline with `$MIF_ONTOLOGY_SOURCE`.

### Added

- **README "not a chatbot deep-research" notice** — clarifies the harness is a
  falsified deep-exploration + knowledge-graph engine (adversarial falsification,
  depth, reusable accreting results), and that AI *will* make mistakes, which is
  why the schema/ontology/MIF/falsification rigor exists.

### Fixed

- `evals/copier-update.sh` now treats copier's post-apply temp-clone cleanup
  race (Python 3.14 `rmtree` "Directory not empty" on `copier._main.new_copy*`)
  as success — the render already landed; the script's assertions verify it — and
  still retries the pre-apply local-clone hardlink race.

## 0.7.1 - 2026-06-30

### Added

- **Ship the cross-topic concordance** `reports/concordance.json` (#218). The
  ontological spine is now rebuilt over the shipped example corpus
  (`scripts/build-concordance.sh`: 36 nodes / 46 edges) and committed, reflecting the
  domain-pack entity types the corpus resolves to (`trend`, `segment`,
  `sizing-estimate`, `value-proposition`, `market-intelligence-report`,
  `critical-uncertainty`, `emerging-issue`, `data-provenance`, …). `verify.sh`'s
  template corpus-shape gate (8c) now allows this deterministic, allowlisted artifact
  alongside `_meta/` and the archived example topic.

### Removed

- **Retired the seed-time `schemas/mif/VENDOR.lock` provenance file** (#223). It is
  moot under on-demand vendoring (ADR-0012, #221): the registry-pinned
  `ontologies.lock.json` + `scripts/check-ontology-lock.sh` now carry vendored-pack
  provenance, and the MIF contract is first-class and editable in-repo. `gate_m12`
  drops its verbatim-set assertion (subsection 12d); it still validates the contract
  and every registry ontology, asserts `id@version` uniqueness, and exercises the
  resolver/pack-enable matrix. Docs reconciled (ADR-0002 audit, ontology-conformance,
  contracts reference, COMPLETION-CRITERIA, `ontology-manager` skill).

## 0.7.0 - 2026-06-30

### Added

- **On-demand ontology vendoring** (ADR-0012). Domain ontologies are fetched from
  the canonical registry (the `ontologies` repo → `mif-spec.dev/ontologies/`) and
  verified fail-closed against a pinned `sha256` index, instead of every clone
  bundling every ontology. New `scripts/fetch-ontology.sh` (resolve the `extends`
  closure, fetch, sha256-verify, materialize `packs/ontologies/<id>/`, pin
  `ontologies.lock.json`); `scripts/check-ontology-lock.sh` (drift gate — a
  vendored copy must match its pinned hash, so fixes go upstream, not in place);
  and `scripts/author-ontology.sh` (when no ontology covers a domain, scaffold one
  from the topic's observed entity types and concierge a draft PR upstream). Base
  layers stay committed. Covered by `evals/ontology-vendoring.sh`. Flipping the
  bundled domain packs to a gitignored on-demand cache (with corpus re-enrichment)
  is a staged follow-up once the registry is served.

## 0.6.1 - 2026-06-30

### Fixed

- **Project hooks skip cleanly when their script is absent.** Each `.claude/settings.json`
  PreToolUse, PostToolUse, and Stop hook command now guards on the script's presence
  (`[ -f "$CLAUDE_PROJECT_DIR/.claude/hooks/…" ] || exit 0`) before invoking it, so a
  partial checkout or any context without the harness hook scripts no-ops the hook
  instead of failing the tool call.

## 0.6.0 - 2026-06-29

### Added

- **`ai-spec` channel + spec-genre packs.** A new `ai-spec` channel pack renders a
  topic's surviving findings into an AI-ready, agent-executable architecture spec — a
  genre-shaping of the `artifact.json` → Markdown pipeline (`finding_refs[]` → grounded
  evidence sections, the goal's `completion_condition.checks[]` → EARS acceptance
  criteria, `artifact.sections[]` → structure). It pairs with a new `packs/genres/`
  family carrying one pack per spec genre: `architecture-spec` (arc42/C4 §1–§12 +
  EARS), `kiro-spec` (requirements → design → tasks), and `feature-spec` (Spec Kit
  single capability). All optional and toggle-ready (`enabled:false`), registered in
  `harness.config.json` and the marketplace.
- **Cognitive-triad explanation** (`docs/explanation/cognitive-triad.md`). Codifies why
  an entity type's `base` is the closed set `_semantic`/`_procedural`/`_episodic`
  (Tulving's memory systems, cited as MIF `Citation` objects), the base-vs-namespace
  distinction, and why a derivation method such as "analytical" is never a base — its
  outputs (`forecast`/`scenario`/`adoption-curve`) are `_semantic`.
- **Worked specimens.** One worked example per genre in the bundled
  `example-okf-mif-knowledge-spine` topic (`*-build-spec.md`), each a MIF Level-1
  deliverable grounded in surviving findings with EARS criteria drawn from the goal checks.

### Changed

- **Five domain ontology packs conformed to the build-spec.** `software-security`,
  `regulatory-legal`, `scientific`, `market-research`, and `trend-analysis` now carry
  prior-art grounding (`source_vocab`/`source_class`/`prior_art`/`disposition`) on every
  entity type and provenance traits resolved from `shared-traits` (seven generic
  provenance traits promoted there). All shipped types preserved; `regulatory-legal`
  gains the missing `compliance-regulation`; `analytical`-rooted types conformed to
  `_semantic`. Packs validate and resolve fail-closed through the catalog.
- The output-conformance hook exempts `*-build-spec.md` (the `ai-spec` channel's
  Level-1 agent-consumable spec) from the Level-3 write-time check.

### Fixed

- `build-topic-readme.sh`: list `*-build-spec.md` deliverables in the topic README
  Reports table (only `*-delta.md` build logs stay excluded), and force `LC_ALL=C`
  on the Reports-table sort so the generated README is byte-identical across build
  hosts (a locale-sensitive `sort -k2` made the README-freshness gate flap between
  macOS and the Linux CI runner).

## [0.5.0] - 2026-06-29

### Added

- **Fail-closed ontology-completeness gate + auto-reconciled spine** (Epic 1). The
  research loop now reconciles the cross-topic concordance as a first-class
  pre-synthesis stage. `scripts/check-shippable-typing.sh` blocks synthesis until
  every shippable (`survived`/`weakened`) finding resolves to a valid ontology type,
  and the orchestrator builds + validates `reports/concordance.json` before spawning
  the report-synthesizer. Falsified, quarantined, and inconclusive findings never
  block; `/ontology-review --enrich` then `/resume` is the unblock path. New
  ADR-0011 records the decision and `gate_m24` enforces it.
- **Ontology-aware synthesis** (Epic 2). `scripts/synthesize-artifact.sh` joins each
  report section to its finding's resolved type (`entityType`/`ontology`/`basis`)
  from `ontology-map.json`, and the `report` channel renders the resolved type in
  its provenance line. The no-map path stays byte-identical, so existing renders are
  unaffected.
- **Cross-topic corpus atlas** (Epic 2). New `scripts/synthesize-corpus.sh`,
  `corpus-synthesizer` agent, and `/synthesize-corpus` command project the spine
  (`reports/concordance.json`) into `reports/_corpus/corpus-synthesis.md` — the whole
  research record across every topic, **including what was falsified or weakened**
  (which the survivors-only report-synthesizer omits). `gate_m25` covers it.
- **Concordance scale-query verbs** in the `graph` skill: `--reuse`,
  `--contradictions`, and `--disproven` over `reports/concordance.json` (graph skill
  bumped to `0.5.0`).
- **Org governance reference** (`docs/reference/org-governance.md`) cross-linking the
  org release, branch-protection, Dependabot auto-merge, and labels runbooks plus the
  reusable-workflow CI architecture, reachable from `SECURITY.md` and `README.md`.

### Fixed

- `copier update` now re-runs `sync-packs.sh` (added to copier `_tasks`), so the
  derived ontology catalog (`.claude/enabled-packs.json`) never goes stale after an
  update — a stale catalog missing an `extends` target would otherwise make the
  fail-closed resolver mark the whole bound corpus invalid.
- `evals/copier-update.sh` now surfaces copier's stderr instead of swallowing it and
  retries the transient local-clone hardlink race, so a genuine failure is
  diagnosable rather than an undiagnosable "flake."

## [0.4.3] - 2026-06-29

### Added

- A MIF-branded **social-preview card** (`.github/social-preview.svg` / `.png`)
  and a README hero banner. The card frames the harness as a MIF-native engine
  across three pillars — MIF substrate, ontological spine, and a living knowledge
  graph that grows each session — the last shown as a typed cyan spine accreting
  amber findings.
- `scripts/bump-version.sh` — a change-driven version-bump tool. It moves the
  template release pointer (`harness.config.json`), the marketplace catalog
  (`.metadata.version`), and inserts the CHANGELOG section, and bumps a pack's
  stamps (`plugin.json`, its `SKILL.md`, and its family-doc row) only when that
  pack is named with `--pack`. It self-verifies and supports `--check` (dry run).
- A **version-consistency gate** in `scripts/verify.sh`: the marketplace catalog
  version equals the template version, and every skill/plugin stamp is well-formed
  semver. It does not force uniformity (independent versions stay legal), replacing
  the previously-claimed (but unenforced) lockstep gate.
- A **bump-on-change CI gate** (`scripts/check-version-bump.sh`, wired as the
  PR-only `version-bump` job): a changed pack or core skill must move its own
  version, and any change must move the `harness.config.json` release pointer, or
  CI fails naming the un-bumped component. `[skip-version-check]` on its own line
  in a commit waives the pointer rule for a change that warrants no release.

### Changed

- **Versioning is now change-driven, not lockstep** (ADR-0010). A pack or skill
  version bumps only when its own files change; `harness.config.json` is the sole
  always-bumps release pointer. A release that touches no pack now changes three
  files instead of ~80, removing the per-release stamp churn and the corruption
  risk it carried. `CLAUDE.md` is updated to document the new model and tool.

## [0.4.2] - 2026-06-28

### Added

- The bundled **archived example research corpus** (`reports/example-okf-mif-knowledge-spine`)
  ships to every clone as its inherited seed fixture — keeping the same name in the template
  and in clones — so a fresh clone shows the engine's worked output immediately. The
  `copier-update` eval asserts it ships archived on copy and survives `copier update` without
  duplication or conflict. (It is served straight out of `reports/`; the prior `example-`-prefix
  rename was dropped — renaming the corpus directory inside copier's update render destabilized
  copier's temp-dir cleanup.)

### Changed

- The bundled example is now a single **archived** research topic served straight out of
  `reports/` — `example-okf-mif-knowledge-spine`, a worked OKF + MIF knowledge-spine corpus
  (36 findings, knowledge graph, falsification report, and a full set of genre reports:
  exec-summary, briefing, market-research-report, market-sizing, competitive-analysis,
  competitive-quadrant, trend-analysis, trend-modeling, academic, engineering, and
  computing-paper). The distribution gate (`verify.sh` 8c) now permits this one served
  example under `reports/` alongside `reports/_meta/`.
- **The site now serves the full topic deliverable tree** — the README (as the topic
  index at `/reports/<topic>/`), the neutral synthesis, the falsification report, the
  research-progress log, and every genre report all render, instead of being excluded
  (these are critical consumer-facing deliverables). `src/content.config.ts` wraps `glob()`
  to DERIVE the Starlight `title` from each file's body `# H1` (so the generated artifacts
  are never mutated and clones get the same behaviour) and re-slugs the README to the topic
  index; a `remarkStripReportH1` plugin drops the duplicate body heading at render. The
  reports **sidebar lists one link per topic** (its README index), not a per-report tree, and
  a `Sidebar` component override adds a client-side **topic filter**. ADR-0009 is amended to
  record this (superseding its README/falsification exclusions).
- The **readme channel** is upgraded toward the `zircote/research` per-topic exemplars:
  a falsification audit-trail line in the header, dimensions rendered with their
  descriptions, a richer Artifacts table (type + size), backtick-quoted tags, an optional
  hero image, and a **Reports table listing the topic's constituents as Type → Title** in a
  deterministic reader-consumption order (executive summary → briefing → synthesis → genre
  reports → falsification report → research progress).
- Site sidebar groups collapse by default so a large corpus stays navigable.

### Removed

- The legacy `example-topic` placeholder and the `topic_id` / `topic_title` copier
  prompts. The inherited archived seed is the clone's starting topic; run `/start` to
  research new topics.

### Fixed

- The rendered site now builds and navigates the full instance corpus, not just
  the example. `harness-instance.md.jinja` ships Starlight frontmatter (it was
  frontmatter-less and aborted `astro build`/`dev` in every clone); Copier
  re-establishes the `docs/reports` and `src/content/docs` symlinks it flattens
  on render, and `gate_m23` now asserts both; and the content glob excludes
  audit/continuity artifacts (`*-falsification-report.md`, `*-delta.md`,
  `*-build-spec.md`) that carry no Starlight frontmatter. (#164, #165)
- `scripts/render-artifact.sh` derived the report intro's "covers N surviving finding(s)"
  from the section count, which undercounts once a genre reshapes sections; it now counts
  `finding_refs` (the true surviving-finding total), accurate for every genre.
- Findings now carry a top-level `namespace` field. The example corpus's 36 findings
  omitted it (it lived only inside the `@id` URN), so `build-index.sh` projected
  `namespace: null` for every finding and namespace-scoped `/search` + the `/topics`
  rollup silently broke (and report synthesis fell back to a `harness/report` namespace).
  The corpus is backfilled, the `dimension-analyst` now emits the field, and a new
  fail-closed gate (`verify.sh` 8e) requires every finding under `reports/**/findings`
  to carry a non-empty top-level `namespace` so the omission can never ship silently.
  The `topics` and `discover` skill evals are realigned to the new manifest (sole
  archived example topic; four research dimensions).

## [0.4.1] - 2026-06-28

### Added

- The Reports surface now has a stable `/reports/` index page
  (`src/pages/reports.astro`) that lists this harness's report topics from the docs
  collection: empty-safe before the first report, the example topic in the template,
  a clone's own reports in an instance. The splash landing gains a "Read the reports"
  hero action and a Reports card, and the Reports sidebar group gains an "Overview"
  link, all pointing at it.
- Auto-redeploy: `docs.yml` fires the `source-updated` `repository_dispatch` the org
  Pages `deploy.yml` listens for after a green build on a push to `main`
  (authenticating as the org GitHub App, scoped to the org Pages repo), so a merge
  republishes the live site automatically. Previously the live site only updated on a
  manual deploy dispatch. `gate_m23` gains 23e (landing surfaced) and 23f (dispatch
  wired; template-only).

## [0.4.0] - 2026-06-28

### Added

- The Astro/Starlight site now renders `reports/` as a first-class surface for
  human reading: each `reports/<topic>/<slug>.md` becomes a page in a **Reports**
  sidebar group (mermaid + relative links resolved), covered by `llms.txt`. The
  template hosts a rendered **example-topic** report so the docs site demonstrates
  the reports surface; a clone is activated reports-primary at instantiation.
- `harness.config.json` gains an optional `site` block (validated by the schema):
  `primarySurface` (`reports|docs|auto`) and `plugins` gates for `llmsTxt`,
  `mermaid`, `imageZoom`, `linksValidator`. `astro.config.mjs` reads it at build
  time, so neither the template nor a clone hand-edits `astro.config.mjs`.
- `scripts/site-toggle.sh` — flip the site surface or an optional plugin from the
  manifest. Two optional Starlight plugins are bundled (default off):
  `starlight-image-zoom` and `starlight-links-validator`.
- `/configure` command + `harness-configurator` agent — a configuration concierge
  that toggles packs and site features, manages ontologies and topics, and re-runs
  the gates.
- Copier post-copy `_tasks` hook (with `_message_after_copy`) activates a clone's
  reports surface on `copier copy --trust`; the bundled example report is excluded
  from clones so `copier update` stays conflict-free.
- `gate_m23` (site projection) and the `site-toggle` eval.

### Changed

- Upgraded the docs site to **Astro 7 / Starlight 0.41** (from Astro 6 / Starlight
  0.40), mirroring the sibling MIF repo. `astro-rehype-relative-markdown-links` is
  retained via a `package.json` `overrides` peer relaxation (it still resolves the
  docs' relative `.md` links on Astro 7); the `gray-matter` patch is retained (the
  relative-links plugin reads link targets through `gray-matter`, which calls the
  `safeLoad` removed in js-yaml 4). The Astro-6-pinned `esbuild` override is dropped.

### Fixed

- `scripts/update.sh` now handles cross-platform reproducibility misses
  (macOS/BSD vs Linux `git archive | gzip -n` bytes) with a sanctioned fail-closed
  fallback: verify the downloaded release asset's attestation, then require
  extracted-content equality with the pinned commit SHA before applying
  `copier update --vcs-ref <sha>` (issue #151).

## [0.3.0] - 2026-06-26

### Added

- MIT `LICENSE` at the repo root (the template is now explicitly MIT-licensed).

### Security

- Remediated GHSA-h67p-54hq-rp68 / CVE-2026-53550 (quadratic-complexity DoS in
  `js-yaml` YAML merge-key handling). `js-yaml` is forced to `>= 4.2.0` via an npm
  `overrides` entry, and `gray-matter` — which hard-pins the unmaintained 3.x line
  and pulled it transitively into the docs build — is patched with `patch-package`
  (`yaml.safeLoad`/`safeDump` → `yaml.load`/`dump`, a faithful rename since those
  are 4.x's safe variants). No upstream fix exists, so the committed lockfile is
  pinned forward to keep instantiated harnesses clean.

## [0.2.0] - 2026-06-25

### Added

- Fail-closed provenance gate before `copier update` (issue #94). `scripts/update.sh`
  is the only supported update path: it resolves the target release tag, pins it to a
  commit SHA, reproduces the release artifact, and verifies its SLSA build-provenance
  attestation with the same primitive as `release.yml`/CI/`SECURITY.md`
  (`gh attestation verify --repo … --signer-workflow …/release.yml`). Any miss exits
  non-zero and never invokes Copier; on success it runs `copier update --vcs-ref
  <verified-sha>` (TOCTOU-closed). The trust root is the signer-workflow identity baked
  into the wrapper, established once at clone and verify-before-apply protected.
  `evals/update-provenance.sh` (run in CI via `run-evals.sh`) asserts the gate fails
  closed; docs: a how-to ("update your harness safely") and an explanation
  ("update-channel provenance model").
- A layered ontology spine. New MIF-compliant intermediate layer
  `engineering-base` (`schemas/ontologies/engineering-base/0.1.0.yaml`, cataloged
  `core=false`) declares the engineering supertypes shared across domains —
  `component`, `architectural-decision`, `design-pattern`, `delivery-metric`,
  `engineering-practice`, `process-discipline` — plus `depends_on`/`implements`.
  The engineering domain packs `extends: engineering-base`, so resolution is
  transitive: binding a domain pack resolves the supertypes its ancestor layers
  declare. The layer is present-but-not-core, so non-engineering topics never
  resolve these types — keeping the upstream-submittable generic core
  domain-neutral. `gate_m21` proves the positive (descendant resolves an
  ancestor-layer type) and the negative (a non-engineering topic does not).
- Cross-cutting universals in `engineering-base` — `control`, `artifact`,
  `policy`, `provenance` — with edges `governs` (control/policy →
  component/artifact), `attests` (provenance → artifact), and `derived_from`
  (artifact lineage). `data-engineering` adds `governed_by` (data-product/storage
  → control/policy), realizing the data/security governance cross-cut.
- Entity-type subsumption: a new first-class `subtype_of` field on entity types
  (declared in `ontology.schema.json`). A subtype is substitutable for its
  supertype at a relationship endpoint, enforced by `validate-concordance.sh` and
  `gate_m22`. `software-security.security-control` is `subtype_of: [control]`, so it
  satisfies the cross-cutting `governs` edge; a non-subtype is rejected.
- A root `CLAUDE.md` orienting Claude Code to the harness (gates, contracts, the
  goal-driven engine, pack control plane, and the conventions that bite). It is
  template-managed and re-applied on update; the new
  `docs/how-to/instantiate-the-harness.md` section recommends instance owners put
  their own clone-specific guidance in a `CLAUDE.local.md` (loaded automatically,
  never touched by `copier update`).

### Changed

- `resolve-ontology.sh` and `validate-concordance.sh` now walk the `extends`
  chain when building a topic's allowed ontology set (fail-closed if an
  `extends` target is not cataloged). `sync-packs.sh` catalogs non-core layers
  under `schemas/ontologies/` as `core=false` (only `mif-base`, `mif-generic`,
  `shared-traits` are core).
- Renamed the `security` ontology pack to `software-security` (extends
  `engineering-base`); moved the SDLC-facing `security-threat`,
  `security-framework`, and `security-incident` supertypes into it from
  `software-engineering`, where the finer STIX/ATT&CK/CWE types refine them.
  Renamed its `control` type to `security-control` (the security specialization of
  the new generic `engineering-base` `control`).
- Deduplicated the engineering domain packs: `software-engineering` (0.5.0) now
  carries only SDLC-operational types (`incident-report`, `runbook`,
  `deployment-procedure`, `migration-guide`); `data-engineering` (0.2.0) carries
  only data-specific types. Both inherit the shared supertypes and the generic
  `technology` (which is a MIF built-in in `mif-generic`) instead of copying them.
- Nothing is vendor-locked. `VENDOR.lock` no longer marks any file `verbatim:true`
  (the MIF contract `ontology.schema.json` + context are unlocked); `gate_m12` now
  asserts the verbatim set is empty. `VENDOR.lock` is retained for provenance
  (source/commit + seed checksums). The contract is first-class and evolves in-repo
  on its way back to MIF — conformance stays fail-closed by validation, not by
  freezing files.
- The graph visualization is now a real interactive force-directed node-link
  diagram (issue #91). `build-graph-viz.sh` replaces the two `<ul>` lists with a
  deterministic SVG layout (seeded circle + fixed-iteration Fruchterman-Reingold,
  no RNG), concept/entity nodes colored and sized by degree, typed edges
  (`supports`/`contradicts`/`derived-from`/`mentions`) with distinct color, dash,
  and arrowheads, edge-type labels, hover tooltips, a legend, and draggable nodes
  — still self-contained vanilla SVG + JS (no CDN, no network). The embedded graph
  JSON escapes `</` so a label containing `</script>` cannot break out of the tag.
- Ephemeral viz HTML no longer dirties the working tree (issue #91).
  `build-graph-viz.sh` defaults its output to a `mktemp` path **outside** the
  project tree (an explicit second argument still writes in-repo); the `verify.sh`
  M-graph gate renders its probe into a temp dir and removes it. Only tracked data
  artifacts (findings, `knowledge-graph.json`, `concordance.json`, maps) belong in
  `reports/` — documented in `docs/reference/scripts.md`.

### Removed

- `compliance-regulation` (modeled in `regulatory-legal` as `legal-act`/
  `obligation`) and the deprecated `adoption-trend` (superseded by
  `trend-analysis`'s `trend`) are dropped from the engineering packs. Pre-stable
  clean break — no back-compat aliases.

## [0.1.2] - 2026-06-24

### Added

- `SECURITY.md` with a "Verifying Release Artifacts" section documenting the
  strict `gh attestation verify` command (pinned to the release workflow via
  `--signer-workflow`) and how to report vulnerabilities.

### Changed

- The release workflow re-verifies the SLSA build-provenance attestation
  before publishing (fail-closed) and pins trust to the release workflow with
  `--signer-workflow`, so a tag never publishes an unverified artifact and an
  attestation from any other workflow in the repository is rejected.

## [0.1.1] - 2026-06-23

First release of the domain-general research harness template.

### Added

- **Four-layer architecture** in one repository — engine (`.claude/agents` and
  `.claude/commands`), contracts (`schemas/`), harness services (topic registry,
  knowledge graph, search, discovery), and outputs (`reports/`, channels, packs)
  — all shipping on clone. See
  [ADR 0001](docs/adr/0001-four-layer-single-repository-architecture.md).
- **MIF Level-3 I/O conformance**: findings are individual MIF memory units
  validated against the vendored `schemas/mif/` closure.
- **Goal-driven sessions**: a content-hashed, append-only goal
  (`schemas/goal.schema.json`) initiates, steers, and gates each run.
- **Config-declared dimensions** read from `harness.config.json` (`technical`,
  `landscape`, `trajectory`) — not a fixed taxonomy.
- **Single adversarial falsification gate** assigning ordinal verdicts
  (`falsified` / `weakened` / `survived` / `inconclusive`) with one-round
  remediation.
- **Packs and plugins**: one plugin per skill, toggled via the
  `harness.config.json` `packs[]` control plane and the
  `.claude-plugin/marketplace.json` marketplace. Channel packs (book, Diátaxis,
  PDF, NotebookLM, GitHub Discussions, GitHub Issues), report genres,
  methodologies, and ontologies.
- **Output channels**: blog (first-class, always on) and the canonical MIF
  Level-3 report channel as the source of truth.
- **Diátaxis documentation set** under `docs/` (tutorials, how-to, reference,
  explanation) plus Architectural Decision Records under `docs/adr/`.
- **Attested delivery**: SHA-pinned GitHub Actions enforced by a `pin-check`
  CI gate, and a release workflow that attests a reproducible source tarball
  with SLSA build provenance via `actions/attest-build-provenance`.
- **Distribution** as a Copier living template and a Claude Code plugin
  marketplace.

[Unreleased]: https://github.com/modeled-information-format/research-harness-template/compare/v0.16.21...HEAD
[0.16.21]: https://github.com/modeled-information-format/research-harness-template/compare/v0.16.18...v0.16.21
[0.16.18]: https://github.com/modeled-information-format/research-harness-template/compare/v0.16.3...v0.16.18
[0.16.3]: https://github.com/modeled-information-format/research-harness-template/compare/v0.15.1...v0.16.3
[0.15.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.15.0...v0.15.1
[0.15.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.14.1...v0.15.0
[0.14.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.2...v0.13.0
[0.12.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.1...v0.12.2
[0.12.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.1...v0.8.3
[0.8.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.5.0...v0.8.0
[0.5.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/modeled-information-format/research-harness-template/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/modeled-information-format/research-harness-template/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/modeled-information-format/research-harness-template/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/modeled-information-format/research-harness-template/releases/tag/v0.1.1

<!--
Dated sections above with no bracketed heading (0.6.0, 0.6.1, 0.7.0, 0.7.1,
0.8.2, 0.8.4, 0.10.1, 0.11.1, 0.11.2, 0.12.3, 0.15.2, 0.15.3, 0.15.4, 0.16.0,
0.16.1, 0.16.2, 0.16.4, 0.16.5, 0.16.6, 0.16.7, 0.16.8, 0.16.9, 0.16.10,
0.16.11, 0.16.12, 0.16.13, 0.16.14, 0.16.15, 0.16.16, 0.16.17, 0.16.19,
0.16.20) moved the
`harness.config.json` version
pointer per ADR-0010's change-driven model but were folded into a later
release before a GitHub Release/tag was ever published for them, so they omit
a footer compare-link — nothing real exists to compare against. Convention
(#393): a footer compare-link is only emitted once a real Release/tag exists
for a dated section, and it compares against the previous *actual* tag, not
the adjacent dated section's version string. If a future dated section's
version pointer gets folded into a later release without its own tag, strip
its brackets and omit its footer link the same way when that becomes known.
-->
