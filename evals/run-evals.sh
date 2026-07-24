#!/usr/bin/env bash
# run-evals.sh — the harness eval suite (SPEC §4a "Evals — KEEP → first-class";
# shipped and run in template CI). Each eval exercises a harness behaviour
# end-to-end against the sample corpus and asserts the expected outcome. Quality
# is a first-class concern, not optional.
#
#   bash evals/run-evals.sh
#
# Exit 0 iff every eval passes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
# Gate scripts never read stdin; detach it (research-harness-template#531)
# so no child can block on an inherited never-EOF pipe (backgrounded
# invocations hand exactly that to every descendant).
exec </dev/null


PASS=0; FAIL=0
GREEN=$'\033[32m'; RED=$'\033[31m'; RST=$'\033[0m'
run() { # run <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf '%s  PASS %s %s\n' "$GREEN" "$RST" "$name"
  else
    FAIL=$((FAIL+1)); printf '%s  FAIL %s %s\n' "$RED" "$RST" "$name"
  fi
}
# An eval that must FAIL the underlying command (negative case).
run_neg() { # run_neg <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); printf '%s  FAIL %s %s (expected failure)\n' "$RED" "$RST" "$name"
  else
    PASS=$((PASS+1)); printf '%s  PASS %s %s\n' "$GREEN" "$RST" "$name"
  fi
}

SF="reports/_meta/sample-session/findings"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. Engine pipeline smoke test (orchestrator → one falsification gate → MIF finding).
run "engine-smoke" bash evals/smoke-test.sh

# Gate scripts must never block on an inherited never-EOF stdin (#531):
# wrap-source forwards an explicit empty --content instead of falling
# through to the engine's stdin path, and the gate entrypoints detach
# stdin outright.
run "stdin-detach" bash evals/stdin-detach.sh

# verify.sh gate selector + profiling (#531): scoped runs are loudly
# marked, per-gate timings are built in, unmatched patterns fail fast.
run "verify-selector" bash evals/verify-selector.sh

# gate_m1's corpus-contamination scrub swallowed ANY git-grep failure (not
# just its "no match" exit-1 case) as a clean pass via `2>/dev/null || true`
# (#770): stubs git-grep to fail with a real error status and asserts the
# gate fails loudly instead of reporting a false-clean scan.
run "gate-m1-git-grep-failure-check" bash evals/gate-m1-git-grep-failure-check.sh

# gate_m28's 28h hang-regression check must degrade gracefully (skip, not
# hard-fail) when neither `timeout` nor `gtimeout` is on PATH (#774) -- a
# stock-macOS contributor with no Homebrew coreutils saw a real-looking FAIL
# from a CI-parity gate for a change that would actually pass CI.
run "gate-m28-timeout-path-check" bash evals/gate-m28-timeout-path-check.sh

# gate_m14's bypass_cmds loop variable must stay function-scoped (#780): a
# missing `local` here leaks into the caller once gate_m14 returns, since
# verify.sh calls every gate in-process ("$gate", never a subshell).
run "gate-m14-no-var-leak" bash evals/gate-m14-no-var-leak.sh

# gate_m23's 23d loop variable `d` must stay function-scoped (#781): it
# used to leak into the global scope once gate_m23 returned, which would
# silently corrupt any later gate reusing an unscoped `for d in ...`/
# `while read d` loop instead of starting from an unset variable.
run "gate-m23-loop-var-scope-check" bash evals/gate-m23-loop-var-scope-check.sh

# Workflow-runtime modules (.claude/workflows/*.js) use the runtime's
# async-function-body shape, so the CI parse-check must wrap before
# checking (#552): passes on the vendored research-goal.js, fails on a
# seeded syntax error, and runs inside verify.sh's gate_workflows.
run "workflow-parse-check" bash evals/workflow-parse-check.sh

# research-falsify.js's buildFixtureEntry() crashed on EVERY finding by
# calling new Date() from inside a Workflow-runtime script's own body,
# silently stalling the falsification gate on every real /research run
# (#618). Static, comment-aware gate over every vendored module for the
# three forbidden runtime globals (new Date(, Date.now(, Math.random():
# clean on the shipped tree, catches each forbidden call by file+line,
# never false-positives on the same strings appearing in a comment or
# template literal, and runs inside verify.sh's gate_workflows.
run "workflow-forbidden-globals-check" bash evals/workflow-forbidden-globals-check.sh

# The engine-workflows reference entry stays bidirectionally honest with
# the module set, cross-linked with commands.md, and keeps the /goal-writer
# positioning + supersession note (#553).
run "workflow-docs-check" bash evals/workflow-docs-check.sh

# ci.yml's verify/version-bump jobs (and, via their pack sources, monitor.yml/
# monitor-gate.yml) fed scripts/fetch-engine.sh's cross-repo read of mif-rs a
# GitHub App installation token restricted to this repo alone -- installation
# tokens 404 on any repo outside their scope, even a public one, so both jobs
# failed on every run (#662). Static gate over every .github/workflows/*.yml:
# every fetch-engine.sh step must use a minted App token whose mint step's
# repositories: input includes mif-rs (ADR-011 least-privilege identity),
# never the ambient default job token.
run "fetch-engine-gh-token-check" bash evals/fetch-engine-gh-token-check.sh

# /start's Error handling partial-findings check globs
# reports/<topic>/findings/*.json — where dimension-analyst output actually
# lands — never the flat reports/<topic>/*.json, which matches Phase 0
# bookkeeping (goal.json etc.) and misreported total failures as partial
# progress (#684). Also pins the path against the orchestrator's own
# live-progress signal so the two surfaces cannot silently diverge.
run "start-error-handling-glob-check" bash evals/start-error-handling-glob-check.sh

# /goal-writer's evidence-surface table and worked example model coverage
# verify commands over reports/<topic>/findings/*.json — where findings
# actually live — never the flat reports/<topic>/*.json glob, which only
# matches goal.json/state.json/ontology-map.json and made any authored
# coverage_per_dimension check permanently unsatisfiable (#676).
run "goal-writer-findings-path" bash evals/goal-writer-findings-path.sh

# research-goal.js's Context schema must require existingGoalSummary, not just
# type it as string|null (#766): the Draft prompt unconditionally interpolates
# it whenever existingGoalPath is truthy, so an omitted-but-schema-valid
# summary produced a literal "(undefined)" leak into the Draft agent's prompt.
run "goal-context-summary-required" bash evals/goal-context-summary-required.sh

# The research-goal draft→lint→repair contract has deterministic teeth
# (#554): scripts/lint-goal.sh FAILS the seeded-invalid fixture (step-shaped
# check assertion + off-config dimension) that ajv alone accepts, fails
# closed on a schema-invalid goal, passes the repaired form, and the
# workflow's bounded repair arithmetic (max 2 rounds) converges or fails
# closed when repair is exhausted.
run "goal-lint-repair" bash evals/goal-lint-repair.sh

# The research-fanout lane contract has deterministic teeth (#558): the ajv
# finding gate (findings.schema.json + vendored schemas/mif/ closure) FAILS
# the seeded-invalid fixture naming both issue classes, the lane's
# dimension-pin gate rejects an ajv-valid finding pinned outside its lane,
# relate/dedup annotation is provably additive (file count, older file, and
# claim content all preserved), and research-fanout.js keeps FINDING_CONTRACT
# in the analyst brief, crossDimensionLeads required, and the never-delete
# repair/relate constraints.
run "fanout-lane-contract" bash evals/fanout-lane-contract.sh

# research-harness-template#623: research-fanout.js's own validate/repair
# lane can mutate schema-invalid/citation-defective findings in place before
# the round loop's completion check ever runs. This eval proves the module
# now computes and returns the true pre-repair defect count, per dimension
# and as a round total, so a heavily-repaired corpus is never
# indistinguishable from one that was clean from the start.
run "fanout-repair-disclosure-check" bash evals/fanout-repair-disclosure-check.sh

# research-harness-template#751: the repair lane's revalidate `.then((rv) =>
# {...})` callback dereferenced `rv.invalid.length` with no null check, even
# though `agent()` can legitimately resolve to null on a terminal failure
# after retries. That uncaught TypeError propagated out of pipeline()'s
# per-item stage chain and crashed the ENTIRE fanout run for every
# dimension, discarding whatever other dimensions' work had already
# completed. This eval proves a null revalidate() result no longer throws,
# that unrelated dimensions' completed work survives, and that the failed
# dimension is dropped (consistent with this file's existing null-
# propagation convention) rather than silently reported as succeeded.
run "fanout-null-revalidate-crash" bash evals/fanout-null-revalidate-crash.sh

# The research-falsify verdict-merge table has deterministic teeth (#562):
# mergeVotes()'s arithmetic (unanimous, majority-falsified, minority-
# falsified-contested-escalates, mixed-non-falsified-takes-worst) and the
# over-budget claimBudget slicing (exact deferredIds remainder, nothing
# silently dropped) are extracted verbatim from research-falsify.js and run
# against the real functions; a seeded-false-finding fixture is graded
# through the real vendored engine and quarantined via the ported
# remediation logic end to end; the one-round rule (a normal re-run on an
# already-graded finding is excluded; a regate-scoped client-side reset
# genuinely re-processes it) is proven against that same real engine; and
# the module's fixture-write bridge / ported remediation contract are
# checked structurally. Lens identity is also proven to survive a failed
# lens (#682): pairLensResults() is extracted verbatim and run against the
# exact misattribution shape, and structural greps forbid a positional
# LENSES[i] lookup after filter(Boolean).
run "falsify-verdict-merge" bash evals/falsify-verdict-merge.sh

# The fanout->falsify HANDOFF SEAM has deterministic teeth (#652/#653):
# neither fanout-lane-contract.sh (structural-only: the FINDING_CONTRACT
# constant exists/is embedded) nor falsify-verdict-merge.sh (one-round rule
# in isolation, given a finding that ALREADY has attempted_at) proves a
# freshly-fanned finding, run through fanout's OWN validate-step strip
# command, actually survives into genuine grading. This eval extracts the
# mechanical jq del(attempted_at) filter verbatim from research-fanout.js,
# runs it for real against a fixture reproducing #652's exact incident
# shape, proves the UN-stripped fixture is skipped by the real engine
# (the negative control -- if this doesn't skip, the eval wouldn't have
# caught #652), and proves the SAME finding after the strip genuinely
# gates end to end through that same real engine.
run "fanout-falsify-handoff" bash evals/fanout-falsify-handoff.sh

# research-harness-template#656: the weakened-verdict remediation path in
# REMEDIATION_CONTRACT (prompt text, not deterministic code -- there is no
# pure function to extract and drive the way mergeVotes()/claimBudget
# above can) previously under-specified the required MIF Citation shape,
# which shipped 60 schema-invalid citations across 8 real findings (wrong
# citationType/citationRole enum values, missing title) plus one finding
# with its unrelated top-level temporal field nulled out by the same
# write step. This eval grep-checks REMEDIATION_CONTRACT's actual text for
# the fix's four required clauses (full citationType/citationRole enums,
# the exact wrong values #656 observed named explicitly, the required
# title field, strict field-scoping naming temporal, and a strengthened
# run-the-actual-ajv-command re-validate instruction), then proves against
# the REAL schemas (ajv, no model call) that all four of #656's named
# corruption patterns genuinely fail validation and that a citation/finding
# built by following the fixed contract's spec validates cleanly.
run "falsify-remediation-citation-shape" bash evals/falsify-remediation-citation-shape.sh

# The research-synthesis citation-integrity gate has deterministic teeth
# where the module's own logic can express it (#566): Select-phase
# structural exclusion (falsified/quarantined findings, and a verdict-clean
# archived finding, are excluded by DIRECTORY not verdict, proven against a
# seeded fixture corpus and cross-checked against the module's own prompt
# text) and the repair-round bound (a never-converging critique is proven
# BEHAVIORALLY -- by driving the module's own while-loop extracted verbatim
# -- to stop at exactly MAX_REPAIR=2 rounds, an early-converging critique
# stops sooner, an already-clean critique never loops at all). Citation-key
# integrity itself (does a synthesis cite an @id outside the closed
# survivor set) is delegated entirely to the opus Critique phase's model
# judgment -- no client-side validator exists for it anywhere in this repo
# -- so this eval proves the WIRING (closed survivorIds -> critique prompt)
# and the seeded out-of-set-citation fixture's own shape deterministically,
# and documents plainly (in the eval's own header) that grading the fixture
# through the real gate is a genuine, non-deterministic gap CI cannot close.
run "synthesis-citation-check" bash evals/synthesis-citation-check.sh

# The research-projection module has deterministic teeth where its own logic
# can express it (#571, Epic #543): structural grep of the module's ACTUAL
# AGENT PROMPT bodies (never a comment) proves the #569-resolved
# script-delegated composition is really wired in (Report:
# synthesize-artifact.sh->falsify.sh->render-artifact.sh->mif-project.sh;
# Index: build-topic-readme.sh+build-graph.sh+assert-graph-mif.sh); a REAL,
# hermetic, no-model fixture run through that same script pipeline (twice,
# same topic/slug, a genuinely different artifact in between) proves
# supersession @id identity (SAME @id, incremented version, changed content —
# never a fresh @id and never a stale no-op); the synthesisPath preflight
# guard is extracted VERBATIM and driven with a stubbed agent() to prove it
# fails closed with a clear, actionable message on a missing/unusable path;
# and a stale hand-typed README Findings count is proven caught by
# build-topic-readme.sh's real --check gate (the seed's own "never guessed"
# acceptance criterion, made a real regression trap).
run "projection-supersession-check" bash evals/projection-supersession-check.sh

# research-harness-template#720: the Index phase completed its real
# README/graph work in production, then never called StructuredOutput —
# and, when the harness's structured-output-enforce nudge fired, asserted
# in prose that it HAD already called the tool, which it never did.
# agent({schema}) surfaces that specific non-compliance class as a THROW,
# not the documented "returns null on death" contract, and the Index phase
# had no try/catch around its one agent() call, so the throw hard-failed a
# 304-agent-call, ~3.4-hour pipeline run one phase from the finish line.
# Structural proof that the call now runs on model: 'sonnet' (matching the
# Report phase's existing precedent for the identical mixed
# judgment-plus-script-pipeline task shape) rather than haiku, plus a
# behavioral proof that the module's own try/catch block (extracted
# VERBATIM, brace-matched, never re-typed) does not re-throw and degrades
# to a null index with a named warning when driven with a stubbed agent()
# that throws the exact observed failure signature, while leaving the
# documented null-return contract path and the happy path unaffected.
run "projection-index-resilience-check" bash evals/projection-index-resilience-check.sh

# research-harness-template#727: the Report and Verify phases of the same
# research-projection.js module share the identical unguarded agent()-throw
# exposure that #720 (above) fixed for Index. Report's fix is guard-and-
# RETHROW (its return shape isn't degradable — every downstream field is
# read unconditionally); Verify's fix is guard-and-DEGRADE (mirroring
# Index) while deliberately staying on `haiku` (an anti-regression trap in
# the opposite direction of Index's own model-escalation guard above). Both
# evals use the same brace-matched verbatim-extraction technique.
run "projection-report-resilience-check" bash evals/projection-report-resilience-check.sh
run "projection-verify-resilience-check" bash evals/projection-verify-resilience-check.sh

# research-harness-template#773: REPORT_SCHEMA unconditionally required
# frontmatterLevel/reportId even on the step-3 falsify early-exit path, where
# render-artifact.sh/mif-project.sh (the only place either value is ever
# actually determined) never runs -- forcing the subagent to fabricate a
# plausible-looking MIF level and @id for an artifact that was never
# rendered. frontmatterLevel now types as ['integer','null'] and the prompt
# instructs the honest null/"" sentinel on that path (mirroring the existing
# genreApplied/provenanceOutcome sentinel convention for the identical
# quarantine path). Proven via a REAL ajv schema validation: the
# falsify-quarantine payload is accepted by the current (fixed) schema,
# rejected by the historical pre-fix baseline, and the happy path is
# untouched.
run "projection-report-schema-falsify-exit-check" bash evals/projection-report-schema-falsify-exit-check.sh

# research-harness-template#775: scripts/mif-project.sh's `TMPD="$(mktemp -d)"`
# was unchecked, so a failing mktemp -d silently fell back to the root path
# /projection.json instead of failing closed with a named diagnostic.
run "mif-project-mktemp-check" bash evals/mif-project-mktemp-check.sh

# The research-deliverables module has deterministic teeth where its own
# logic can express it (#573, Epic #544): the module's static pack-taxonomy
# tables (which genres/methodology packs/source-direct channels/out-of-scope
# channels it knows about) are cross-checked against the REAL
# docs/reference/packs/index.md inventory table (parsed, not eyeballed) so a
# drift between the module and the real docs is a caught regression; a
# structural grep of the module's ACTUAL AGENT PROMPT BODIES proves the
# settings.local.json "<pack>@research-harness" key shape, the
# report-channel architectural-boundary reason, and the out-of-scope
# third-mechanism channels are all still named in the Route prompt, and that
# the Render prompt's two mechanism branches stay disjoint (artifact-based
# delegates to synthesize-artifact.sh -> render-artifact.sh, source-direct
# invokes Skill(<pack>:<pack>) directly and explicitly never touches either
# script or synthesisPath); and a REAL, hermetic, no-model fixture run
# through the actual synthesize-artifact.sh -> render-artifact.sh pipeline
# (offline, reports/_meta/sample-session's real findings, blog channel)
# proves the citation-leak gate holds by the REAL enforced pattern
# (extracted verbatim from .claude/hooks/check-citation-leak.sh), not merely
# asserted by the prompt text.
run "deliverables-route-check" bash evals/deliverables-route-check.sh

# research-harness-template#658: deliverables-route-check's part A can only
# catch a GENRE_PACKS entry disagreeing with docs/reference/packs/index.md —
# never a real mif-docs genre skill missing from GENRE_PACKS entirely, since
# both hand-maintained tables can (and did: 14 genres, arc42-arch-doc
# included) drift from the real plugin catalog together. This eval checks
# GENRE_PACKS against the actual vendored mif-docs-plugin skill directory
# (scripts/fetch-mif-docs-plugin.sh, ADR-0018) instead of another hand-typed
# table, so this class of drift can't recur silently again.
run "deliverables-genre-catalog-check" bash evals/deliverables-genre-catalog-check.sh

# research-harness-template#575 (Epic #544): a SEPARATE eval from the one
# above, scoped to what #573 actually wired — real, currently-enabled genre
# packs (exec-summary, engineering) are driven end-to-end through the real
# synthesize-artifact.sh -> render-artifact.sh pipeline and every Check-phase
# gate is asserted per rendered artifact (lint, MIF Level-1 frontmatter,
# citation-leak, >=1 citation); a genuinely-disabled real pack
# (sustainability-report) and a genuinely-nonexistent one are proven,
# structurally, to land in reason categories distinct from the out-of-scope
# source-direct/third-mechanism case (why full unavailable[] emission can't
# be driven end-to-end without a live model call is explained inline, along
# with a real proof that the substrate itself does not gate on pack
# enablement); and a seeded canary-claim fixture proves synthesize-artifact.sh
# reads the findings dir directly (never the synthesis) — the synthesis-only
# evidence rule for mechanism 1 is enforced only by the Render agent's own
# cross-check instruction, verified structurally.
run "deliverables-genre-channel-route" bash evals/deliverables-genre-channel-route.sh

# research-harness-template#764: the module's existing GENRE STRING VALIDATION
# guard (#640) validated route.plan's genre field against the pack-name pattern
# before interpolating it into a shell-command argument / Skill() reference,
# but the identical channel field — interpolated into the same two positions
# — had no equivalent validation. This eval covers the new CHANNEL STRING
# validation guard this fix adds. Drives the real module (stubbed agent(),
# same technique as projection-slug-genre-args-check.sh) with a caller-
# controlled route.plan to prove an unknown channel and a mechanism/channel
# mismatch both fail closed before Render, while a genuinely valid channel
# still renders.
run "deliverables-channel-validation-check" bash evals/deliverables-channel-validation-check.sh

# research-harness-template#755: the Render pipeline's second stage produced
# `{ ...r, validation: null }` whenever the initial Check-phase agent() call
# itself resolved to null (user skip, or the subagent dying after retries) —
# that object is still truthy, so it survived `rendered.filter(Boolean)`,
# but the pre-fix `dirty` filter (`a.validation && !a.validation.clean`)
# treated a null validation as NOT dirty, silently excluding the artifact
# from the repair loop entirely: never fixed, never re-checked, never
# logged, unlike the symmetric post-fix re-check path which already logs a
# WARNING for the identical null case. This eval proves a null initial Check
# result now logs a WARNING, is treated as dirty, actually enters the repair
# (fix + re-check) loop, and ends up with a real clean verdict instead of
# the ambiguous `clean: null`.
run "deliverables-null-check-repair-check" bash evals/deliverables-null-check-repair-check.sh

# The research-augment module's Decide phase has deterministic teeth where its
# own logic can express it (#580, Epic #545, following #578's vendoring and
# #579's discover-delegation fix): the Assess phase's discover-skill
# delegation is proven to be the REAL, on-disk invocation (not an assumed
# name) via a structural cross-check against .claude/skills/discover/SKILL.md
# itself; the two jq pipelines the Assess prompt instructs are extracted
# VERBATIM from the module's ACTUAL runtime prompt text (driven for real via
# the Workflow-runtime's async-function-body framing) and executed for real
# against a thin/saturated fixture matrix; the Decide prompt's stated priority
# order (unmet-check-impact > attrition > thinness > staleness) plus the
# saturated-is-a-reject rule are checked structurally, in stated order; target
# checks named per deepening pick are proven to be real goal check ids, never
# invented; and DECISION_SCHEMA — captured verbatim from the real agent() call,
# never hand-retyped — is proven via ajv to require `reasoning` unconditionally
# (the empty-plan outcome is proven end-to-end to complete with no throw and a
# normal log line, never an error) and `targetChecks` per deepen[] entry. The
# Decide phase's actual dimension-selection judgment is a live model call this
# eval cannot reproduce deterministically — stated plainly, not faked.
run "augment-decide-check" bash evals/augment-decide-check.sh

# The research-add-dimensions module's Propose/Prune/Amend pipeline has
# deterministic teeth where its own logic can express it (#584, Epic #546,
# following #582's vendoring and #583's docs): the Amend phase is proven,
# structurally (phase('Amend') marker span, never a header comment), to
# invoke the REAL `bash ${H}/scripts/goal-version.sh` exactly twice (OLD then
# NEW) and to explicitly forbid narrating the hash — never the reference
# implementation's freehand-computed one; zero-candidate and all-rejected
# outcomes are driven for real via the Workflow-runtime's async-function-body
# framing and proven to complete with no throw, return structured reasoning,
# and leave the fixture harness.config.json/goal.json byte-for-byte untouched
# because the Amend agent() call is never invoked at all on either path; a
# seeded overlap candidate (a proposed dimension restating the existing
# "technical" dimension) is proven to be filtered out of added[] with its
# stated OVERLAP reason preserved, and to never reach the Amend phase; and the
# approved-candidate path is proven end-to-end against the REAL
# scripts/goal-version.sh (never a hand-simulated hash) — the new dimension
# lands in an independently ajv-clean harness.config.json, and the new goal
# version's supersedes/version fields are cross-checked against THREE
# separate fresh invocations of the real script (a baseline computed before
# the driver ever runs, plus two independent recomputations afterward),
# proving the gv- hash is a stable function of content under lineage
# stamping (ADR-0006), not merely asserted. The Prune phase's own live
# overlap/scope/decision-relevance judgment is a model call this eval cannot
# reproduce deterministically — stated plainly in the eval's own header, not
# faked.
run "add-dimensions-check" bash evals/add-dimensions-check.sh

# The research-pivot module's Reshape/Classify/Plan pipeline has deterministic
# teeth where its own logic can express it (#588, Epic #547, following #586's
# vendoring and #587's docs): the Reshape phase is proven, structurally
# (phase('Reshape') marker span, never a header comment), to invoke the REAL
# `bash ${H}/scripts/goal-version.sh` exactly twice (OLD then NEW) and to
# explicitly forbid narrating the hash; a dedicated lineage/hash fixture drives
# that exact snapshot-then-mint sequence against the REAL
# scripts/goal-version.sh and cross-checks supersedes/version against
# independent fresh recomputations of the real script, never a hand-simulated
# hash (#584's precedent); a no-delta invocation is proven to refuse before any
# agent() call is even made; a seeded 3-finding corpus (plus a quarantined
# sibling that must be excluded from the listing) is classified end-to-end into
# exactly carry/stale/out-of-scope, with every finding file proven
# byte-identical on disk before and after — classification never deletes —
# and reverifyIds proven to equal exactly the stale list, plus a separate case
# proving the module's own real fallback arithmetic when the Plan agent() call
# fails; and finally research-falsify.js is driven for real with the pivot
# fixture's actual reverifyIds as `scope:{ids:[...]},regate:true`, proving the
# two independently-vendored modules' interface boundary actually holds (never
# exercised together before, per #547's chain-context note) without tripping
# the regate-scope guard error. The one gap this eval cannot close — whether a
# live model actually classifies/plans the way the fixture's ground truth
# assumes — is genuine and non-deterministic, documented in the eval's own
# header rather than faked.
run "pivot-check" bash evals/pivot-check.sh

# The research-import module's DryRun/Review/Apply pipeline has deterministic
# teeth against the REAL fail-closed gate, not a mocked substitute (#592,
# Epic #548, following #590's vendoring and #591's docs): the DryRun and
# Apply phases are proven, structurally (phase() marker spans, never a
# header comment), to invoke the REAL bash scripts/mif-container-import.sh,
# with and without --dry-run; a REAL fixture container (exported from a
# fresh, synthetic, from-scratch source topic this eval registers and
# tears down itself, mif-generic-only so no vendored domain-pack
# dependency, avoiding deliverable-report corpus contamination) with one
# resource's bytes corrupted after its digest was declared is REJECTED by
# the real script's --dry-run path, with Review/Apply never called and
# nothing landing under the destination topic's findings/; the same real,
# uncorrupted container hits a Review NO-GO (a live sonnet
# scope-fit/collision/provenance judgment this eval cannot reproduce
# deterministically, stated plainly, not faked) with Apply never called
# and nothing written; a REAL container — exactly 2 hand-authored
# synthetic findings, one already carrying a genuine foreign verification
# block (attempted_at set) and one carrying the dimension-analyst.md
# pre-falsification placeholder (verdict: inconclusive, no attempted_at —
# genuinely unverified, still schema-valid) — imports for real through the
# non-dry-run gate, and the needsGating/trustedForeignVerdicts partition is
# proven correct for BOTH trustImportedVerdicts settings against the real
# on-disk written files (driven twice against the same real container/topic,
# the second invocation a real idempotent no-op upsert); and
# research-falsify.js is driven for real with the fixture's actual REAL
# needsGating as scope:{ids:[...]},regate:true, proving the two
# independently-vendored modules' interface boundary actually holds —
# mirroring #588's pivot->falsify interface fixture for this Epic's own
# action D -> falsify boundary. Real repo-root mutation (harness.config.json,
# reports/concordance.json) is guarded by the same mkdir-based
# $ROOT/.eval-corpus-mutation.lock + cp-based backup/restore idiom
# mif-container-nfr-verification.sh already uses for this exact shared
# real-corpus-mutation window.
run "import-check" bash evals/import-check.sh

# research-harness-template#746: a mistyped or unrecognized flag (e.g.
# --dryrun, -dry-run) fell through the arg-parsing loop's wildcard branch
# into POSITIONAL[] like an ordinary positional argument -- DRY_RUN silently
# stayed 0 (its default) and the old "at least 2" positional count check
# never caught it, so the script proceeded straight through step 4's real
# write with zero error or warning, contradicting its own documented
# --dry-run contract. Hermetic (every case exits during arg-parsing, before
# any directory/manifest resolution, so no real container/topic fixture is
# needed): a mistyped flag is now rejected with a message naming the bad
# option (never silently absorbed), an adjacent extra-bare-positional case
# is rejected too (exact count, not >=2), and the real --dry-run flag plus
# ordinary 2-arg usage are proven unaffected by the fix.
run "import-arg-parse-check" bash evals/import-arg-parse-check.sh

# The research-coverage-audit module's Sweep/Critique/Prioritize pipeline has
# deterministic teeth where its own logic can express it (#597, Epic #549,
# following #595's vendoring and #596's docs): BACKLOG_SCHEMA's action enum
# names the real five downstream modules (augment/add-dimensions/falsify/
# import/projection, plus manual), cross-checked against those five modules
# actually existing on disk, and the Prioritize prompt's own
# "target is a routing signal, not a directly-forwardable arg" disclaimer is
# proven intact; the thin-dimensions and staleness auditors' jq pipelines,
# extracted VERBATIM from the real, already-interpolated runtime prompt text,
# are EXECUTED FOR REAL against a fixture corpus, proving a genuinely-ungated
# (verdict: null) finding is invisible to the real verdict-based staleness
# pipeline (excluded by its own .verdict != null clause) but visible to the
# real age-based one; a hand-corrupted README Findings count is proven
# objectively stale via build-topic-readme.sh's real --check gate in an
# isolated instance (the same mechanism projection-supersession-check.sh's own
# Part D established); the full module, driven end to end, routes the real
# ungated finding to falsify and the real stale README to projection, ranked
# above two lower-impact items by the priority FIELD despite a deliberately
# scrambled stub insertion order (proving the ranking is field-driven, not an
# insertion-order illusion); CRITIC_SCHEMA (captured verbatim from the real
# audit:critic call, never hand-retyped) mechanically rejects a hypothetical
# no-target extraItems entry while accepting a concrete one, making the
# seed's own "concrete facts, not hypotheticals" acceptance criterion a real
# ajv-enforced regression trap; and AUDIT_SCHEMA (also captured verbatim) is
# proven to have no dedicated absence-justification field, so this eval
# enforces "no bare empty array" itself, checked per-auditor against all six
# real captured prompts. The one gap this eval cannot close -- whether a live
# model actually performs the staleness/critic/prioritize JUDGMENT the way
# this fixture's stubs assume -- is genuine and non-deterministic, documented
# in the eval's own header rather than faked.
run "coverage-audit-check" bash evals/coverage-audit-check.sh

# The research-pipeline module's MODE 'full' bounded autonomous round loop has
# deterministic teeth where its own orchestration logic can express it (#602,
# Epic #550, following #599's vendoring and #601's docs): CHECK_SCHEMA
# (captured verbatim from the real completionCheck() agent() call) is
# ajv-proven to require `evidence` on every met[] entry and `why` on every
# unmet[] entry; `done = true` is proven, by exact count, to be set in
# exactly one place in the whole file -- the independent evaluator's own
# unmet.length===0 check -- never by narrative or activity, proven both
# structurally and behaviorally (a round whose fanout/falsify/synthesis all
# succeed does NOT stop the loop while a check stays unmet); the
# research-harness-template#611 regression (evidence silently dropped from
# met[] in the final run report) is fixed and driven end-to-end against the
# real module; maxRounds is proven to genuinely bound the loop even when the
# evaluator would never naturally finish; the honest-termination path (the
# augment judge's plan.deepen comes back empty) is proven to stop the loop
# immediately -- never a further round, never looping forever -- with the
# judge's own real reasoning visible in the captured log, mirroring
# research-augment's empty-plan-is-valid precedent (#545/#580); the goal's
# own declared boundHit is proven to stop the loop without ever reaching the
# adaptation phase, distinct from the maxRounds stop; and the budget-floor
# guard is proven to stop the loop before round 1 even begins, still
# producing a well-formed run report. The one gap this eval cannot close --
# whether a live sonnet completionCheck()/coverage-audit/augment call would
# really grade/decide the way these fixtures' stubs assume -- is genuine and
# non-deterministic, documented in the eval's own header rather than faked;
# each of those judgments is already covered by its own dedicated eval.
run "research-pipeline-full-mode-check" bash evals/research-pipeline-full-mode-check.sh

# research-harness-template#623: the independent completion evaluator's
# prompt now discloses research-fanout's real per-round repair count (so a
# finding_valid/citation_integrity-shaped check can never be graded 'met'
# from post-repair corpus state without disclosing that repair happened),
# and the run's own final report surfaces the accumulated repair total —
# proven both structurally (against the real module source) and
# behaviorally (driving the real module with a heavily-repaired round 1
# followed by a clean round 2).
run "pipeline-repair-disclosure-check" bash evals/pipeline-repair-disclosure-check.sh

# The research-pipeline module's five standalone-mode branches --
# audit/import/pivot/augment/deliverables -- each have deterministic teeth of their own
# (#603, Epic #550, companion to #602's full-mode eval above), proving each
# mode dispatches to, and correctly composes, EXACTLY the atomic-workflow
# sequence the architecture doc's mode-routing table documents for it (never
# a step the table doesn't show), both structurally (grepping the real,
# unmodified mode-router branch) and behaviorally (driving the real
# research-pipeline.js source with every workflow() child stubbed to a
# canned, schema-shaped result matching that child's own real return shape).
# One fixture per mode, one explicit run line per mode (not globbed, matching
# the explicit-line pattern held without exception across all eleven prior
# epics):
#   - audit: research-coverage-audit ALONE -> the routed backlog is returned
#     verbatim via a plain spread; NONE of the five downstream modules a
#     backlog item can route to (augment/add-dimensions/falsify/import/
#     projection) is ever itself auto-invoked by this branch -- the positive
#     proof of research-harness-template#595's own documented finding (cited
#     by this Task's acceptance criteria) that a backlog item's `target` is
#     a human/orchestrator-readable routing signal, never something audit
#     mode auto-dispatches on the caller's behalf.
#   - import: research-import -> a falsify drain gated literally on
#     `needsGating.length` (proven conditional in BOTH directions) ->
#     synthesis -> projection gated on `synthesis.ok`; an import-gate failure
#     short-circuits before any gating runs.
#   - pivot: research-pivot -> a regate falsify call scoped to
#     `{ ids: reverifyIds }` with `regate: true` (behaviorally distinct from
#     the separate `scope: 'all'` falsifyAll() drain call that follows the
#     gap-fill fanout) -> a gap-fill fanout gated on a REAL two-condition
#     guard (`gapDimensions.length && !budgetLow()`, proven to block on
#     EITHER condition independently) -> synthesis -> projection.
#   - augment: research-augment -> an empty `deepen[]` is a real
#     honest-termination code path (mirrors research-augment's own
#     empty-plan-is-valid precedent, #545/#580) -> otherwise fanout over
#     EXACTLY the deepen plan's own dimensions at a depth that escalates to
#     'deep' the moment ANY ONE entry requests it -> a falsify drain ->
#     synthesis -> projection.
#   - deliverables (research-harness-template#624): research-synthesis ALONE
#     (no fan-out, no falsify -- reuses the survivor corpus already on disk)
#     -> research-deliverables fed that fresh synthesisPath plus
#     genres/channels. A missing genres AND channels throws before either
#     child runs; a synthesis.ok===false result short-circuits to
#     deliverables:null before research-deliverables is ever invoked; this
#     mode deliberately never calls research-projection (the report of
#     record is untouched). Also proves the adjacent KNOWN_MODES guard
#     (closing the mode router's previously-missing unrecognized-mode
#     rejection) fires before ANY child dispatches, for every mode, not just
#     this one.
# What none of these five evals can close (genuine, non-deterministic,
# stated in each eval's own header rather than faked): whether a live child
# workflow's own judgment (coverage-audit's Sweep/Critique/Prioritize,
# import's Dry-Run/Review/Apply, pivot's Reshape/Classify/Plan, augment's
# Decide, or a live synthesis/deliverables render) actually produces the
# shapes these fixtures hand-author -- each of those judgments is already
# covered by that child's own dedicated eval (coverage-audit-check.sh,
# import-check.sh, pivot-check.sh, augment-decide-check.sh, synthesis/
# deliverables suites). These five evals' job is only the mode-router
# orchestration code around those calls, not the calls' own judgment.
run "research-pipeline-audit-check" bash evals/research-pipeline-audit-check.sh
run "research-pipeline-import-check" bash evals/research-pipeline-import-check.sh
run "research-pipeline-pivot-check" bash evals/research-pipeline-pivot-check.sh
run "research-pipeline-augment-check" bash evals/research-pipeline-augment-check.sh
run "research-pipeline-deliverables-check" bash evals/research-pipeline-deliverables-check.sh

# research-pipeline.js is ONE vendored module invoked externally through the
# real Workflow-tool boundary (D-9: composition exactly two levels deep) --
# its own top-level `args` can arrive as a JSON-encoded STRING rather than an
# already-parsed object (#617). This eval drives the real, unmodified module
# source with args handed through BOTH ways (raw string, matching the real
# runtime; already-parsed object, matching every sibling eval's existing
# assumption and every internal workflow() call this script itself makes)
# and proves both shapes resolve identically, across the
# topic/harnessDir/workflowsDir guard and the mode-specific
# containerDir/delta guards.
run "research-pipeline-args-parse-check" bash evals/research-pipeline-args-parse-check.sh

# research-harness-template#654: research-pipeline.js's OWN header comment
# (right above) used to claim it was the ONLY module reachable this way --
# "every other vendored module is only ever invoked internally via this
# script's own workflow() calls, which pass real in-process JS objects" --
# and #654 disproved that assumption empirically (research-goal.js's own
# whenToUse already documents standalone use; research-falsify.js and
# research-synthesis.js reproduced the identical instant "args.topic is
# required" failure). This eval is the #617-pattern eval's sibling, covering
# the remaining eleven atomic modules: each now carries the identical
# `typeof args === 'string' ? JSON.parse(args) : (args || {})` guard.
run "atomic-workflows-args-parse-check" bash evals/atomic-workflows-args-parse-check.sh

# research-harness-template#675: the #654 eval above proves only `topic`
# threads through JSON-string args — research-projection.js's OPTIONAL
# slug/genre fields briefly kept reading from the raw `args` after the guard
# landed, silently falling back to TOPIC/'general' on every string-args
# invocation (a property access on a string primitive is `undefined`, never
# an error) and defeating the #633 genre-resolution mechanism. This eval
# pins that defect class: slug AND genre must demonstrably thread from
# string args into the module's real calls, and an invalid genre arriving
# via string args must still hit the fail-closed pack-name-pattern throw.
run "projection-slug-genre-args-check" bash evals/projection-slug-genre-args-check.sh

# release.yml never uploads to an already-published (immutable) release
# (#537): tag-push trigger, no post-publish `gh release upload`, artifact
# attached in the same `gh release create` call.
run "release-workflow-immutable-safe" bash evals/release-workflow-immutable-safe.sh

# .githooks/pre-push must not self-block every release (#648): a tag-only
# (or tag-deletion) push skips the version-bump check entirely per git's
# standard pre-push stdin protocol, while a branch push -- including one
# that mixes branch and tag refs -- still runs it exactly as before.
run "pre-push-tag-skip" bash evals/pre-push-tag-skip.sh

# scripts/fetch-mif-docs-plugin.sh's cache-reuse check must require the
# post-checkout provisioning (npm ci + hydrate-schema) to have completed, not
# just the pinned ref to match (#677): a run whose install fails must not be
# reported as a reusable cache by the next run.
run "fetch-mif-docs-plugin-provision" bash evals/fetch-mif-docs-plugin-provision-check.sh

# 1b. Topic run lock: two concurrent runs on one topic are mutually exclusive
#     (prevents the shared-findings/ corruption vector).
run "run-lock-mutual-exclusion" bash evals/run-lock-test.sh

# 1b2. Finding publish is collision-safe: two dimension-analysts converging on
#      the same slug must not silently clobber one another (issue #357).
run "finding-publish-collision" bash evals/finding-publish-collision.sh

# 1b3. write-finding.sh never leaks its .wf-staging-* directory on any exit
#      path — including the generic ln-failure branch, which used to rmdir the
#      staging dir without removing the staged file first (issue #683).
run "write-finding-stage-cleanup" bash evals/write-finding-stage-cleanup.sh

# 1c. Update-channel provenance gate: scripts/update.sh refuses to invoke copier on a
#     verification miss (fail-closed), pins copier to the verified SHA on a pass, and
#     refuses a dirty tree (issue #94).
run "update-provenance-gate" bash evals/update-provenance.sh

# 1d. guard-falsify-gate.sh's path-extraction regex must not be corrupted by
#     a shell-assignment prefix on the same line (issue #356).
run "guard-falsify-gate" bash evals/guard-falsify-gate.sh

# 1d2. check-output-conformance.sh's Stop-hook exemption case must exempt the
#      ai-spec channel's three kiro genre outputs (*-kiro-requirements.md,
#      *-kiro-design.md, *-kiro-tasks.md) exactly like verify.sh's own
#      four-suffix exclusion list, without defeating the backstop for
#      generic reports (issue #691).
run "output-conformance-exemptions" bash evals/output-conformance-exemptions.sh

# 1e. md_guard.py's PostToolUse `--fix` must be serialized per file (mkdir
#     lock, bounded wait, stale-steal) and must restore + exit non-zero when a
#     fix pass destroys a file's YAML frontmatter (issue #510).
run "md-guard-fix-lock" bash evals/md-guard-fix-lock.sh

# 1f. falsification-analyst.md's documented bounded-summary-qualifier algorithm
#     (#503/#504) must actually hold the 500-char schemas/mif/mif.schema.json
#     summary cap across a range of summary/verdict_basis lengths, and never
#     silently drop the qualifier to make room.
run "bounded-summary-qualifier" bash evals/bounded-summary-qualifier.sh

# 1g. research-projection.js's documented bounded summary CONSTRUCTION algorithm
#     (#629) must hold the same 500-char schemas/mif/mif.schema.json summary cap
#     when report-finding.json's summary is authored from scratch off an
#     artifact's title/sections/sources, across a range of summary lengths
#     including the real observed overrun (3937 chars), and must never alter a
#     summary that is already under the cap.
run "report-finding-summary-cap" bash evals/report-finding-summary-cap.sh

# 1h. check-output-conformance.sh's sweep pathspec must keep its :(glob)
#     qualifier: a bare git pathspec `*` crosses `/`, sweeping exempt nested
#     channel files (reports/<topic>/book/...) into the gate and emitting a
#     spurious conformance systemMessage (issue #687).
run "conformance-sweep-depth" bash evals/conformance-sweep-depth.sh

# 1h2. check-voice.sh's mech_hits/buzz_hits line numbers must match the real
#     file on disk: strip_links blanks exempt citation/URL lines instead of
#     deleting them, so `grep -n` never renumbers the stream (issue #688).
run "voice-gate-line-numbers" bash evals/voice-gate-line-numbers.sh

# 1h3. check-voice.sh's is_authored_surface must classify book-channel prose
#     (reports/<slug>/book/{chapters,appendices,front-matter}/*.md) as an
#     authored surface: the dedicated book clause must precede the generic
#     reports/*/*.md clause, which otherwise shadows it because case `*`
#     crosses `/` (issue #672).
run "voice-gate-book-surfaces" bash evals/voice-gate-book-surfaces.sh

# 2. Citation-integrity: a clean finding passes; a bad one is flagged.
run     "citation-integrity-good" scripts/check-citation-integrity.sh schemas/samples/citation-good.sample.json
run_neg "citation-integrity-bad"  scripts/check-citation-integrity.sh schemas/samples/citation-bad.sample.json

# 3. Knowledge graph derives from MIF ids, not tags.
run "kg-from-mif" bash -c 'scripts/build-graph.sh "'"$SF"'" "'"$TMP"'/kg.json" && scripts/assert-graph-mif.sh "'"$TMP"'/kg.json"'

# 4. Output contract: findings render to both blog and book via one artifact.
run "outputs-blog-and-book" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/a.json" &&
  scripts/render-artifact.sh "'"$TMP"'/a.json" blog "'"$TMP"'/post.md" &&
  scripts/render-artifact.sh "'"$TMP"'/a.json" book "'"$TMP"'/chapter.md" &&
  [ -s "'"$TMP"'/post.md" ] && [ -s "'"$TMP"'/chapter.md" ]'

# 4b. Diagram policy: a Mermaid figure in a section body survives rendering intact
#     (the render pass leaves fenced code blocks verbatim) and validates.
run "mermaid-render-preserves-fences" bash evals/mermaid-render.sh

# 5. MIF I/O conformance (SPEC §10).
# 5a. A compliant report projects to a valid MIF L3 finding; bad ones are rejected.
run     "report-mif-good"           scripts/mif-project.sh schemas/samples/report.sample.md
run_neg "report-mif-bad"            scripts/mif-project.sh evals/fixtures/report-bad.md
run_neg "report-falsified-rejected" scripts/mif-project.sh evals/fixtures/report-falsified.md

# 5a-2. research-harness-template#762: mif-project.sh's directory
#       re-resolution checks the cd subshell's exit status instead of
#       silently continuing with a bogus root-level path when the report's
#       directory vanishes (removed/renamed/unmounted) between the earlier
#       existence check and this re-resolution (a TOCTOU race).
run "mif-project-cd-resolve-check" bash evals/mif-project-cd-resolve-check.sh

# 5a-2b. A mistyped --json-out flag (research-harness-template#765) is a hard
#       error, not a silently-ignored no-op: the caller must be told the flag
#       wasn't recognized instead of having the projection quietly skip
#       writing its output file while still exiting 0.
run_neg "report-mif-json-out-typo-rejected" \
  scripts/mif-project.sh schemas/samples/report.sample.md --json_out "$TMP/typo-out.json"

# 5a-3. The correctly-spelled flag still honors --json-out end to end.
run "report-mif-json-out-honored" bash -c '
  scripts/mif-project.sh schemas/samples/report.sample.md --json-out "'"$TMP"'/good-out.json" &&
  [ -s "'"$TMP"'/good-out.json" ]'

# 5a-4. --json-out with a missing/empty path is a controlled exit-2 usage error
#       (prefixed "mif-project: ..."), not bash's own unprefixed exit-1 message
#       from an unset-parameter expansion (PR #799 Copilot review).
run_neg "report-mif-json-out-missing-path-rejected" \
  scripts/mif-project.sh schemas/samples/report.sample.md --json-out

# 5a-5. A trailing argument after a valid --json-out <path> is rejected instead
#       of being silently ignored (PR #799 Copilot review).
run_neg "report-mif-trailing-arg-rejected" \
  scripts/mif-project.sh schemas/samples/report.sample.md --json-out "$TMP/trailing-out.json" --typo

# 5b. The report channel emits a valid L3 report end-to-end (write-then-validate).
run "report-channel-e2e" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/r.json" &&
  scripts/render-artifact.sh "'"$TMP"'/r.json" report "'"$TMP"'/report.md" evals/fixtures/report-verification.json &&
  scripts/mif-project.sh "'"$TMP"'/report.md"'

# 5b-2. The documented verdict path is real: a verdict PRODUCED by falsify.sh (not
#       hand-authored) flows through extraction into a valid L3 report. Proves the
#       falsify.sh -> verification-block -> report channel seam the agent doc uses.
run "report-verdict-from-falsify" bash -c '
  scripts/falsify.sh evals/fixtures/raw-finding.json evals/fixtures/evidence.json > "'"$TMP"'/ff.json" &&
  jq ".extensions.harness.verification" "'"$TMP"'/ff.json" > "'"$TMP"'/vf.json" &&
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/ra.json" &&
  scripts/render-artifact.sh "'"$TMP"'/ra.json" report "'"$TMP"'/rr.md" "'"$TMP"'/vf.json" &&
  scripts/mif-project.sh "'"$TMP"'/rr.md"'

# 5b-3. render-artifact.sh's report channel stamps the artifact's own `genre:`
#       directly into the rendered frontmatter (schema-required by
#       artifact.schema.json), so a genre survives even for a canonically-named
#       report-<genre>.md deliverable that carries no dot-delimited slug.
run "render-artifact-stamps-genre" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" engineering "'"$TMP"'/g.json" &&
  scripts/render-artifact.sh "'"$TMP"'/g.json" report "'"$TMP"'/report-engineering.md" \
    evals/fixtures/report-verification.json &&
  grep -qx "genre: engineering" "'"$TMP"'/report-engineering.md"'

# 5b-4. build-topic-readme.sh's file_genre() recognizes the canonical
#       report-<genre>.md filename (report_type()'s OWN pattern family) as a
#       fallback, not just the dotted <slug>.<genre>.md convention — a
#       pre-genre-stamp deliverable with no genre: field still shows its real
#       genre in the Reports table, not the generic "Document" bucket. Uses the
#       bundled example topic (the only registered one) with a throwaway
#       report-<genre>.md fixture and a disposable --out, so the real README
#       is never touched.
run "build-topic-readme-genre-fallback-report-dash" bash -c '
  d=reports/example-okf-mif-knowledge-spine &&
  trap "rm -f $d/report-_evaltmpgenre.md" EXIT &&
  printf -- "---\ntitle: t\n---\nbody\n" > "$d/report-_evaltmpgenre.md" &&
  scripts/build-topic-readme.sh example-okf-mif-knowledge-spine \
    --out "'"$TMP"'/readme-genretest.md" >/dev/null &&
  grep -qE "\| _evaltmpgenre \|" "'"$TMP"'/readme-genretest.md"'

# 5b-4b. build-topic-readme.sh's ".tmp.$$" atomic-write staging file must never
#        accumulate forever when a prior invocation was killed before its mv()
#        ran (research-harness-template#772): a leftover "<out>.tmp.<stale-pid>"
#        is swept (sweep_stale_tmp) the next time the script writes to that
#        same $OUT, and the real README still writes correctly. Uses the
#        engine-free _corpus path against a throwaway scratch dir, so this
#        needs no mif-rh-cli install and never touches a real topic.
run "build-topic-readme-sweeps-stale-tmp" bash -c '
  d="'"$TMP"'/sweep-corpus"; mkdir -p "$d/reports/_corpus"
  printf "%s" "{\"topics\":[],\"verdict_distribution\":{},\"entity_reuse\":[],\"contradictions\":[],\"disproven\":[]}" \
    > "$d/reports/_corpus/corpus-map.json"
  : > "$d/reports/_corpus/README.md.tmp.999999" &&
  CLAUDE_PROJECT_DIR="$d" bash scripts/build-topic-readme.sh _corpus >/dev/null &&
  [ ! -e "$d/reports/_corpus/README.md.tmp.999999" ] &&
  [ -f "$d/reports/_corpus/README.md" ]
'

# 5b-4c. build-topic-readme.sh must not leave its ".tmp.$$" staging file behind
#        when killed mid-write by SIGTERM (research-harness-template#772's other
#        half — the PostToolUse rebuild hook hitting its timeout): the
#        top-of-file trap removes the in-flight temp file and re-raises the
#        signal so the process still terminates rather than resuming. Forces a
#        wide write window with a synthetic 1,000,000-topic corpus-map.json —
#        the group-command redirect creates "$OUT.tmp.$$" the instant the
#        write starts, and jq keeps it open for over a second processing that
#        many rows — so the poll-then-kill below lands reliably mid-write
#        instead of racing a write that is already done.
run "build-topic-readme-sigterm-cleanup" bash -c '
  d="'"$TMP"'/sigterm-corpus"; mkdir -p "$d/reports/_corpus"
  python3 -c "
import json
n = 1000000
json.dump({\"topics\": [f\"t{i}\" for i in range(n)], \"verdict_distribution\": {},
            \"entity_reuse\": [], \"contradictions\": [], \"disproven\": []},
           open(\"$d/reports/_corpus/corpus-map.json\", \"w\"))
"
  CLAUDE_PROJECT_DIR="$d" bash scripts/build-topic-readme.sh _corpus >/dev/null 2>&1 &
  pid=$!
  tmp="$d/reports/_corpus/README.md.tmp.$pid"
  waited=0
  while [ ! -e "$tmp" ]; do
    sleep 0.05
    waited=$((waited+1))
    if [ "$waited" -gt 100 ]; then
      echo "tmp staging file never appeared" >&2
      kill -9 "$pid" 2>/dev/null
      exit 1
    fi
  done
  kill -TERM "$pid"
  wait "$pid" 2>/dev/null
  [ ! -e "$tmp" ] &&
  [ ! -e "$d/reports/_corpus/README.md" ]
'

# 5b-5. render-artifact.sh stamps `slug:` as a clean repo-root-relative route
#       even when $OUT is given as an ABSOLUTE path under the repo checkout
#       (report-synthesizer.md documents this usage via an absolute
#       $REPORTS_DIR). A bare dirname-based SLUGPATH would stamp an absolute
#       filesystem path into `slug:` here -- that was the reviewed bug.
run "render-artifact-slugpath-absolute-out" bash -c '
  trap "rm -rf reports/_evaltmp_absout" EXIT &&
  mkdir -p reports/_evaltmp_absout &&
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/abs.json" &&
  scripts/render-artifact.sh "'"$TMP"'/abs.json" report \
    "$(pwd)/reports/_evaltmp_absout/x.engineering.md" evals/fixtures/report-verification.json &&
  grep -qx "slug: reports/_evaltmp_absout/x.engineering" reports/_evaltmp_absout/x.engineering.md'

# 5b-5b. render-artifact.sh's REPO_ROOT must resolve $(pwd) logically, not
#        physically: callers build $OUT with plain $(pwd) (5b-5 above), so on a
#        checkout reached through a symlink a physical REPO_ROOT would diverge
#        from that logical $OUT prefix, the strip would silently no-op, and
#        `slug:` would leak an absolute path -- the same bug 5b-5 fixes,
#        reached through a different door. Reviewed in PR #255.
run "render-artifact-slugpath-symlinked-checkout" bash -c '
  trap "rm -rf reports/_evaltmp_symlink" EXIT &&
  mkdir -p reports/_evaltmp_symlink &&
  LINK="'"$TMP"'/symlinked-checkout" &&
  ln -s "$(pwd)" "$LINK" &&
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/symlink.json" &&
  ( cd "$LINK" &&
    scripts/render-artifact.sh "'"$TMP"'/symlink.json" report \
      "$(pwd)/reports/_evaltmp_symlink/y.engineering.md" evals/fixtures/report-verification.json ) &&
  grep -qx "slug: reports/_evaltmp_symlink/y.engineering" reports/_evaltmp_symlink/y.engineering.md'

# 5b-6. version: increments on each re-render of the same $OUT (the harness keeps
#       no automatic history, so the frontmatter counter is the only revision
#       record).
run "render-artifact-version-increments" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/v.json" &&
  scripts/render-artifact.sh "'"$TMP"'/v.json" report "'"$TMP"'/vtest.md" evals/fixtures/report-verification.json &&
  grep -qx "version: 1" "'"$TMP"'/vtest.md" &&
  scripts/render-artifact.sh "'"$TMP"'/v.json" report "'"$TMP"'/vtest.md" evals/fixtures/report-verification.json &&
  grep -qx "version: 2" "'"$TMP"'/vtest.md"'

# 5b-6b. The blog/book published channels are atomic-to-valid like the report
#        channel (issue #681): a failing engine must exit the script non-zero,
#        never leave a partial file at $OUT, never corrupt a prior good render
#        at $OUT, and always print a diagnostic — temp-then-move, exit-status
#        checked (set -e is not in effect in render-artifact.sh).
run "render-artifact-atomic-write" bash evals/render-artifact-atomic-write.sh

# 5b-6c. Two concurrent render-artifact.sh invocations targeting the SAME
#        $OUT must never both silently succeed with a DUPLICATE version stamp
#        (issue #776): the whole read-prior-version -> render -> mv critical
#        section is now serialized per-$OUT via a container-lock-style mkdir
#        lock, so a losing racer is denied loudly (clear stderr diagnostic,
#        non-zero exit) rather than corrupting the version counter silently.
run "render-artifact-concurrent-version-race" bash evals/render-artifact-concurrent-version-race.sh

# 5b-7. backfill-report-slugs.sh only stamps the key actually missing (a file
#       with slug but no version gets ONLY version added, never a duplicate
#       slug line), --dry-run reports ONLY the missing key (not both,
#       unconditionally -- the reviewed misleading-output bug), and a second
#       run is a true no-op (idempotent).
run "backfill-slugs-partial-state-and-idempotent" bash -c '
  trap "rm -rf reports/_evaltmp_backfill" EXIT &&
  mkdir -p reports/_evaltmp_backfill &&
  printf -- "---\nslug: reports/_evaltmp_backfill/foo\ntitle: t\n---\nbody\n" \
    > reports/_evaltmp_backfill/foo.md &&
  dryout=$(scripts/backfill-report-slugs.sh --dry-run _evaltmp_backfill) &&
  printf "%s" "$dryout" | grep -q "version: 1" &&
  ! printf "%s" "$dryout" | grep -q "slug:" &&
  scripts/backfill-report-slugs.sh _evaltmp_backfill >/dev/null &&
  grep -qx "version: 1" reports/_evaltmp_backfill/foo.md &&
  [ "$(grep -c "^slug:" reports/_evaltmp_backfill/foo.md)" = "1" ] &&
  out=$(scripts/backfill-report-slugs.sh _evaltmp_backfill) &&
  printf "%s" "$out" | grep -q "0 fixed, 1 already OK"'

# 5b-8. backfill-report-slugs.sh topic auto-discovery (no <topic> args) must
#       exclude EVERY "_"-prefixed non-topic scaffolding dir under reports/
#       (_meta, _corpus, _monitoring, ...), not just the literal _meta (#692)
#       -- a frontmatter-bearing file in such a dir must never be enumerated
#       for stamping. Naming an "_" dir explicitly still processes it (5b-7
#       relies on exactly that).
run "backfill-slugs-autodiscovery-skips-underscore-dirs" bash -c '
  trap "rm -rf reports/_evaltmp_scaffold" EXIT &&
  mkdir -p reports/_evaltmp_scaffold &&
  printf -- "---\ntitle: t\n---\nbody\n" > reports/_evaltmp_scaffold/nav.md &&
  out=$(scripts/backfill-report-slugs.sh --dry-run) &&
  ! printf "%s" "$out" | grep -q "_evaltmp_scaffold" &&
  expout=$(scripts/backfill-report-slugs.sh --dry-run _evaltmp_scaffold) &&
  printf "%s" "$expout" | grep -q "_evaltmp_scaffold/nav.md"'

# 5c. Inbound source-envelope: a valid envelope passes; an invalid one is refused.
run     "source-envelope-good" ajv validate --spec=draft2020 --strict=false -c ajv-formats \
          -s schemas/mif/source-envelope.schema.json -r schemas/mif/mif.schema.json \
          -r schemas/mif/definitions/entity-reference.schema.json -d schemas/samples/source-envelope.sample.json
run_neg "source-envelope-bad"  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
          -s schemas/mif/source-envelope.schema.json -r schemas/mif/mif.schema.json \
          -r schemas/mif/definitions/entity-reference.schema.json -d evals/fixtures/source-envelope-bad.json

# 5d. Exemptions are declared (blog is the always-on exempt output; book/pdf channel packs
#     declare mif.exempt in their plugin.json).
run "exempt-channels-declared" bash -c '
  jq -e "[.outputs[]|select(.channel==\"blog\")|select(.mifExempt==true)]|length==1" harness.config.json >/dev/null &&
  jq -e ".mif.exempt==true" packs/channels/book/.claude-plugin/plugin.json >/dev/null &&
  jq -e ".mif.exempt==true" packs/channels/pdf/.claude-plugin/plugin.json >/dev/null'

# 5d. Ontology resolution (SPEC §8c): a finding's entity_type resolves to exactly one
#     of its topic's bound ontologies and its entity validates (additive); undeclared,
#     missing-required, and unbound-for-topic fail; untyped and generic-core pass.
OC="--catalog evals/fixtures/ontology/catalog.json --config evals/fixtures/ontology/config.json"
run     "ontology-resolve-good"     bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/good.json    --topic edu  $OC --map \"$TMP/o1.json\""
run     "ontology-extra-field-ok"   bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/extra.json   --topic edu  $OC --map \"$TMP/o2.json\""
run     "ontology-generic-core"     bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/generic.json --topic bare $OC --map \"$TMP/o3.json\""
run     "ontology-untyped-ok"       bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/untyped.json --topic edu  $OC --map \"$TMP/o4.json\""
run_neg "ontology-undeclared-type"  bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/undecl.json  --topic edu  $OC --map \"$TMP/o5.json\""
run_neg "ontology-missing-required" bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/missing.json --topic edu  $OC --map \"$TMP/o6.json\""
run_neg "ontology-unbound-for-topic" bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/good.json   --topic bare $OC --map \"$TMP/o7.json\""
run_neg "ontology-ambiguous"        bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/ambiguous.json --topic eng $OC --map \"$TMP/o8.json\""
run     "ontology-disambiguated"    bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/disambig.json  --topic eng $OC --map \"$TMP/o9.json\""
run     "ontology-review-coverage"  bash -c "mkdir -p \"$TMP/rep/edu/findings\" && cp evals/fixtures/ontology/good.json \"$TMP/rep/edu/findings/\" && scripts/ontology-review.sh --topic edu --strict --reports-dir \"$TMP/rep\" $OC"

# 5d-ii. Discovery-basis findings (no entity block; classified only by resolve-ontology.sh's
#        content-pattern fallback) must NOT be counted as stamped/typed, and --followup must
#        list them by finding_id — the exact gap that let a topic read as "fully typed" while
#        no finding on disk carried a real ontology stamp.
run     "ontology-review-discovery-not-stamped" bash -c "
  rm -rf \"$TMP/rep2\"; mkdir -p \"$TMP/rep2/edu/findings\"
  cp evals/fixtures/ontology/good.json evals/fixtures/ontology/discovery.json \"$TMP/rep2/edu/findings/\"
  scripts/ontology-review.sh --topic edu --reports-dir \"$TMP/rep2\" $OC --followup \"$TMP/rep2/followup.json\" > \"$TMP/rep2/out.txt\" 2>&1
  grep -q '1 stamped, 1 discovery-only, 0 untyped, 0 invalid' \"$TMP/rep2/out.txt\" &&
  [ \"\$(jq -r '.total_needs_followup' \"$TMP/rep2/followup.json\")\" = 1 ] &&
  [ \"\$(jq -r '.topics.edu[0].finding_id' \"$TMP/rep2/followup.json\")\" = f-discovery-only ] &&
  [ \"\$(jq -r '.topics.edu[0].basis' \"$TMP/rep2/followup.json\")\" = discovery ]"
# ADR-0016: classification hard-requires the engine; a bad override must fail
# loudly (exit 5, message naming the remedy), never fall back to a different
# code path. Positive eval: the loud failure IS the expected behavior.
run     "engine-missing-fails-loud"  bash -c "
  out=\$(MIF_RH_CLI=/nonexistent/mif-rh-cli scripts/resolve-ontology.sh evals/fixtures/raw-finding.json 2>&1); rc=\$?;
  [ \$rc -eq 5 ] && printf %s \"\$out\" | grep -q 'install it with scripts/fetch-engine.sh'"

# research-harness-template#767: a version-mismatch failure (candidate found,
# but too old) must name WHICH of engine_bin's three resolution paths
# ($MIF_RH_CLI override, PATH, <root>/bin/mif-rh-cli) actually supplied the
# stale candidate, and give that source's real remedy -- "re-run
# scripts/fetch-engine.sh" is only correct for the repo-local case; telling a
# user with a stale override or a stale PATH binary to do that is a
# guaranteed no-op, since fetch-engine.sh only ever writes the repo-local path.
run "engine-version-mismatch-source-check" bash evals/engine-version-mismatch-source-check.sh

# #779: a pre-release binary's suffix (-rc1, -alpha, ...) must not be
# silently discarded by the version-extraction regex — it has to rank BELOW
# the release of the same X.Y.Z it names, not compare as equal to it.
run     "engine-version-precedence" bash evals/engine-version-precedence-check.sh
run     "ontology-vendoring"        bash evals/ontology-vendoring.sh
run     "sync-registry-ontologies"  bash evals/sync-registry-ontologies.sh

# 5d-iii. author-ontology.sh --from-clusters (ADR-0015): expansion-candidates
#         cluster JSON scaffolds one todo-cluster-N draft candidate type per
#         cluster — quoting member excerpts and listing member finding ids —
#         and the draft validates against the vendored ontology contract.
run     "author-ontology-from-clusters" bash -c "
  scripts/author-ontology.sh evaltmp-clusters --from-clusters evals/fixtures/expansion-clusters.json --out \"$TMP/clusters-draft.yaml\" >/dev/null 2>&1 &&
  grep -q 'name: todo-cluster-2' \"$TMP/clusters-draft.yaml\" &&
  awk '/name: todo-cluster-1/,/disposition:/' \"$TMP/clusters-draft.yaml\" > \"$TMP/cluster1-block.txt\" &&
  awk '/name: todo-cluster-2/,/disposition:/' \"$TMP/clusters-draft.yaml\" > \"$TMP/cluster2-block.txt\" &&
  grep -q 'Member findings: f-alpha, f-beta' \"$TMP/cluster1-block.txt\" &&
  grep -q 'Spaced-repetition scheduling policies' \"$TMP/cluster1-block.txt\" &&
  grep -q 'Member findings: f-delta, f-gamma' \"$TMP/cluster2-block.txt\" &&
  bash .claude/skills/ontology-manager/scripts/validate_ontology.sh \"$TMP/clusters-draft.yaml\""

# 5d-iv. author-ontology.sh --open-pr concierge (#670): the copy into the
#        reused sibling ontologies clone is exit-checked (a failed cp aborts
#        before branch/commit/push/PR), and the commit stages only the new
#        draft + regenerated index — never the rest of the clone's tree.
run     "author-ontology-open-pr-scoped" bash evals/author-ontology-open-pr-scoped.sh

# 5e. Ontological spine (concordance, SPEC §8d): build over a topic corpus and validate
#     ontology conformance; an undeclared entityType or a from/to domain violation fails.
WC="--config evals/fixtures/concordance/config.json --catalog evals/fixtures/concordance/catalog.json"
run     "concordance-build-and-validate" bash -c "scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w.json\" >/dev/null && scripts/validate-concordance.sh \"$TMP/w.json\" $WC"
run     "concordance-conformant"         scripts/validate-concordance.sh evals/fixtures/concordance/good.concordance.json $WC
run_neg "concordance-undeclared-type"    scripts/validate-concordance.sh evals/fixtures/concordance/undeclared-type.concordance.json $WC
run_neg "concordance-domain-violation"   scripts/validate-concordance.sh evals/fixtures/concordance/domain-violation.concordance.json $WC
run     "concordance-idempotent"         bash -c "scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w1.json\" >/dev/null && scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w2.json\" >/dev/null && diff -q \"$TMP/w1.json\" \"$TMP/w2.json\""

# 5f. reports/_corpus/README.md (research-harness-template#352): synthesize-corpus.sh's
#     _corpus mode builds a site landing page straight from corpus-map.json, joined against
#     harness.config.json for each topic's title/status; a topic present in corpus-map but
#     absent from the config falls back to "—" rather than crashing; a hand-edited Purpose
#     section survives a rebuild.
run "synthesize-corpus-readme" bash -c '
  d="'"$TMP"'/corpus-readme"; mkdir -p "$d/reports"
  cp evals/fixtures/concordance/good.concordance.json "$d/reports/concordance.json"
  printf "%s" "{\"version\":\"0.1.0\",\"topics\":[{\"id\":\"edu\",\"title\":\"Education Fixture\",\"namespace\":\"harness/edu\",\"status\":\"active\"}]}" > "$d/harness.config.json"
  CLAUDE_PROJECT_DIR="$d" bash scripts/synthesize-corpus.sh "$d/reports" >/dev/null &&
  grep -qF "| edu | Education Fixture | active |" "$d/reports/_corpus/README.md" &&
  grep -qF "**Topics:** 1" "$d/reports/_corpus/README.md" &&
  CLAUDE_PROJECT_DIR="$d" bash scripts/build-topic-readme.sh _corpus --check >/dev/null &&
  sed -i.bak "s/A cross-topic view.*/CUSTOM PURPOSE./" "$d/reports/_corpus/README.md" &&
  CLAUDE_PROJECT_DIR="$d" bash scripts/build-topic-readme.sh _corpus >/dev/null &&
  grep -qF "CUSTOM PURPOSE." "$d/reports/_corpus/README.md"
'
run "synthesize-corpus-readme-unmatched-topic" bash -c '
  d="'"$TMP"'/corpus-readme-unmatched"; mkdir -p "$d/reports"
  cp evals/fixtures/concordance/good.concordance.json "$d/reports/concordance.json"
  printf "%s" "{\"version\":\"0.1.0\",\"topics\":[]}" > "$d/harness.config.json"
  CLAUDE_PROJECT_DIR="$d" bash scripts/synthesize-corpus.sh "$d/reports" >/dev/null &&
  grep -qF "| edu | — | — |" "$d/reports/_corpus/README.md"
'

# 6. Model-authoring layer (lib/harness_models): every authored schema emits
#    deterministic, schema-valid contract JSON from a typed dict — replacing the
#    hand-composed shell JSON (`jq -n`) that broke under the Bash `eval` wrapper.
run "models-authoring" python3 evals/test_models.py

# Site-projection control plane: site-toggle.sh round-trips + astro/content config
# gating + copier reports-activation (the reports-as-primary-delivery surface).
run "site-toggle" bash evals/site-toggle.sh

# Relationship-graph integrity (2026-07): every relationships[].target must
# resolve to a real, active finding @id. See scripts/check-relationship-targets.sh
# for the two root causes (bare/guessed target slugs; quarantine never cascaded
# to inbound references) that let orphaned targets land in the corpus unnoticed.
run "relationship-targets" bash evals/relationship-targets.sh

# MIF Container NFR verification (Story #331, Epic #275, ADR-0017): proves all
# 8 EARS-notation non-functional requirements from the architecture doc's
# "Non-Functional Requirements" section against the REAL bundled sample topic
# (36 real findings, real relationship edges, 3 real ontology bindings) --
# not just gate_m26-m31's synthetic/small fixtures -- plus the
# feature-spec's own headline claim: export -> import into a fresh instance
# -> export again reproduces a byte-identical manifest digest.
run "mif-container-nfr-verification" bash evals/mif-container-nfr-verification.sh

# gate_m27's 27f "unreadable file fails closed" check root-safety
# (research-harness-template#777): chmod 000 doesn't deny root/DAC-override
# processes read access, so the check's premise can silently not hold. Proves
# the classification helper (scripts/lib/unreadable-probe.sh) treats a
# bypassed read as SKIP rather than a false FAIL, while still catching the
# original swallow-bug defect class, and that the real gate still passes
# end-to-end for a normal (non-root) run.
run "gate-m27-root-safe-unreadable-check" bash evals/gate-m27-root-safe-unreadable-check.sh

# Continuous research monitoring (Epic #416, Story #425): dry-run over
# fixture source data (no live network calls), real pipeline logic --
# covers the fail-closed budget path, the Editorial Gate's no-bypass and
# fail-safe-default paths, and a full accept-to-publish run producing a
# real schema+citation-integrity-valid MIF finding.
run "monitoring-pipeline" bash evals/monitoring-pipeline.sh

# Continuous monitoring relevance (Story #519): the golden-query-set eval
# #516 called for -- fixture candidates with known-relevant/known-irrelevant
# labels scored at the production default threshold; zero irrelevant and
# >= 80% relevant must be recommended, with #514's topic scoping proven by
# a sentinel that cross-topic corpus-global scoring would have matched.
run "monitoring-relevance" bash evals/monitoring-relevance.sh

# Connector query semantics (#513) + GDELT rate-limit handling (#515):
# recorded-fixture regression evals over the per-API query construction
# (phrase-quoted OR vs one-request-per-term) and the HTTP-200 plaintext
# rate-limit notice detection.
run "monitoring-query-construction" bash evals/monitoring-query-construction.sh

# Monitoring workflow delivery (#517): the pack ships monitor.yml/
# monitor-gate.yml as pack sources and install-monitoring-workflows.sh
# materializes them into .github/workflows/ — idempotent, drift-aware
# (--check fails on a changed source), loud when the pack is disabled.
run "monitoring-workflow-install" bash evals/monitoring-workflow-install.sh

# Domain-based monitoring model (Story #521): monitoringDomains[] schema +
# domain-first subject resolution (#522), cross-source momentum ranking and
# the accept-only prior-coverage memory (#523), the versioned digest and a
# standalone domain's gate round-trip (#524), and byte-identical
# recommendations across runs from identical fixture inputs (#525).
run "monitoring-domains" bash evals/monitoring-domains.sh

# Per-topic cron gate step semantics (#689): 'a-b/step' aligns offsets to the
# range's own start (vixie-cron), never the field's absolute lower bound, and
# a bare 'N/step' expands open-ended to the field's upper bound instead of
# collapsing to the single value N.
run "cron-match-step-alignment" bash evals/cron-match-step-alignment.sh

# 7. Progress-log markdownlint conformance (issue #85 Defect 2): a multi-session
#    research-progress.md built per orchestrator.md's template — one H1 (file
#    creation only) + date-qualified per-session H2s — lints clean, while each old
#    buggy form fails on its SPECIFIC rule: a re-emitted top-level H1 trips MD025,
#    and a repeated fixed `## Findings Summary` sub-heading (single H1) trips MD024
#    and not MD025. Proves the lint config has teeth for both defect forms.
#    markdownlint-cli2 is always present in CI (installed in this job); a local run
#    without it shows a visible SKIP rather than a silent pass.
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  run "progress-log-multisession-lint" bash -c '
    d=$(mktemp -d); trap '\''rm -rf "$d"'\'' EXIT
    cat > "$d/good.md" <<EOF
# Research Progress: demo

## 2026-06-01 — Session Initialized

- Goal: x

## 2026-06-01 — Session Summary

- **Status:** complete

## 2026-06-02 — Session Initialized

- Goal: x

## 2026-06-02 — Session Summary

- **Status:** complete
EOF
    # D2 form (a): the H1 re-emitted each session -> MD025 (multiple top-level headings).
    cat > "$d/bad_h1.md" <<EOF
# Research Progress: demo

## 2026-06-01 — Session Initialized

- Goal: x

# Research Progress: demo

## 2026-06-02 — Session Initialized

- Goal: y
EOF
    # D2 form (b): a fixed sub-heading repeated across sessions under a single H1 ->
    #             MD024 (duplicate sibling heading), and specifically NOT MD025.
    cat > "$d/bad_sub.md" <<EOF
# Research Progress: demo

## Findings Summary

- a

## Findings Summary

- b
EOF
    markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/good.md" >/dev/null 2>&1 || { echo "conformant log not clean"; exit 1; }
    h1=$(markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/bad_h1.md" 2>&1); [ $? -ne 0 ] || { echo "bad_h1 unexpectedly clean"; exit 1; }
    echo "$h1" | grep -q MD025 || { echo "re-emitted H1 did not trip MD025"; exit 1; }
    sub=$(markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/bad_sub.md" 2>&1); [ $? -ne 0 ] || { echo "bad_sub unexpectedly clean"; exit 1; }
    echo "$sub" | grep -q MD024 || { echo "repeated sub-heading did not trip MD024"; exit 1; }
    echo "$sub" | grep -q MD025 && { echo "bad_sub tripped MD025 (must isolate MD024)"; exit 1; }
    exit 0'
else
  printf '  SKIP  progress-log-multisession-lint (markdownlint-cli2 not installed)\n'
fi

# 8. Anti-narration guard (issue #490): /start and /resume must instruct the
#    assistant to output only a bare factual acknowledgment after backgrounding
#    the orchestrator -- no speculative time estimates, no reassurance framing,
#    no restating the obvious. A silent regression here (the instruction text
#    quietly dropped in a future edit) can't be caught by markdownlint or any
#    schema gate, since it's prose the assistant reads, not data it validates --
#    this eval is the only thing that would catch it.
run "anti-narration-guard-start"  bash -c 'grep -q "Issue #490" .claude/commands/start.md && grep -q "output ONLY a bare factual" .claude/commands/start.md'
run "anti-narration-guard-resume" bash -c 'grep -q "Issue #490" .claude/commands/resume.md && grep -q "output ONLY a bare factual" .claude/commands/resume.md'

# research-harness-template#733: copier.yml's _tasks ran site-toggle.sh (hard-
# requires the mif-rh-cli engine since #276) BEFORE fetch-engine.sh, so a
# fresh instance with no cached engine failed the very first _tasks entry on
# every copier copy/update. Static analysis so it can't be masked by CI
# already having the engine cached before any real _tasks run.
run "copier-tasks-engine-order-check" bash evals/copier-tasks-engine-order-check.sh

# research-harness-template#778: gate_m5's mktemp -d calls (5c/5d/5d2/5d3/5d4)
# had no failure guard, so a failed mktemp silently collapsed every "$T/..."
# path to filesystem root. Shadows mktemp with a stub that always fails and
# asserts gate_m5 fails closed with an explicit scratch-directory message
# instead of limping through with a misattributed pack-toggle failure.
run "gate-m5-mktemp-guard" bash evals/gate-m5-mktemp-guard.sh

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%srun-evals: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%srun-evals: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
