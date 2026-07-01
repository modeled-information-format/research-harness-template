---
title: "Change-driven component versioning"
description: "Version each component on change rather than stamping every SKILL.md, plugin.json, and pack doc with the release number every release; harness.config.json becomes the single always-bumps release pointer."
type: adr
category: architecture
tags: [versioning, release, packs, tooling, semver]
status: accepted
created: 2026-06-29
updated: 2026-07-01
author: zircote
project: research-harness-template
technologies: [Bash, jq, Semantic Versioning]
audience: [developers, architects]
related: [0005-packs-and-plugins-extension-model.md, 0008-attested-fail-closed-supply-chain.md]
---

# ADR-0010: Change-driven component versioning

## Status

Accepted

## Context

### Background and Problem Statement

The harness ships ~80 versioned artifacts: `harness.config.json`, the marketplace
catalog (`.claude-plugin/marketplace.json`), every core skill's `SKILL.md`
frontmatter, and — for each pack — a `plugin.json`, a `SKILL.md`, and a
`**Version:**` row in its family reference doc under `docs/reference/packs/`.

Until this decision, a release used **lockstep stamping**: every one of those
artifacts was rewritten to the new release number on every release, whether or
not the artifact had changed. The procedure was manual — `CLAUDE.md` instructed
the author to "mirror the previous bump commit" and change all of them together,
with no tool — and `CLAUDE.md` also asserted that a verify gate "fails if any
stamp drifts from `harness.config`." That gate did not exist: `scripts/verify.sh`
only checked that a `version:` field is *present* (gate 2c-fm), never that it
*equals* the release.

### Current Limitations

- **A patch release rewrites ~80 files to assert a change that did not happen.**
  A version number is supposed to mean "this component changed." Bumping 70
  unchanged packs from `0.4.2` to `0.4.3` makes the number lie and makes the diff
  unreviewable — the real change (e.g. a README image) drowns in stamp noise.
- **Every stamp edit is a corruption opportunity.** A hand-run sweep across 80
  files can truncate a JSON value, miss the marketplace stamp (which lives at
  `.metadata.version`, not the `null` top-level `.version`), or skip an
  independently-versioned file. Nothing caught it, because no gate enforced
  consistency and there was no script.
- **The documented safety net was fictional.** Relying on a drift gate that does
  not exist is worse than having none.

## Decision Drivers

### Primary Decision Drivers

1. A version number must reflect an actual change to its component (semantic
   versioning's core promise).
2. A release must be safe to perform and reviewable — small, intentional diffs,
   not an 80-file sweep with no machine check.

### Secondary Decision Drivers

1. Components already version independently in practice (e.g.
   `.claude/skills/readme/SKILL.md` is at `2.0.0`; ontology packs carry their own
   `version` in `ontology.pack.json`), so the lockstep invariant was already
   untrue.
2. Nothing in the distribution *requires* uniform versions — `marketplace.json`
   lists plugins by `source` path and carries no per-plugin version field.

## Considered Options

### Option 1: Keep lockstep, add a script and an equality gate

**Description:** Keep stamping every artifact to the release version, but make it
safe with a `bump-version.sh` that rewrites all ~80 stamps and a verify gate that
fails unless every stamp equals `harness.config.json`.

- **Advantages:** One number to reason about ("everything here is 0.4.3"); the
  script + gate remove the corruption risk.
- **Disadvantages:** The diff stays ~80 files per release; version numbers still
  assert changes that did not happen; the equality gate is impossible to satisfy
  without first *down-* or *up-*versioning the already-independent files
  (`readme@2.0.0`, ontology packs), i.e. it fights reality.
- **Risk Assessment:** technical low; schedule low; ecosystem medium (perpetuates
  meaningless version churn).

### Option 2: Change-driven versioning with a pointer, a tool, and a consistency gate

**Description:** A component's version bumps only when its own files change.
`harness.config.json` is the single always-bumps release pointer; the marketplace
catalog tracks it. `scripts/bump-version.sh` moves the pointer, the catalog, and
the CHANGELOG by default, and bumps a pack's three stamps only when that pack is
named with `--pack`. A new `gate_versions` in `verify.sh` enforces the invariants
that actually hold.

- **Advantages:** A release touches only what changed (this release: three files,
  not eighty); version numbers regain meaning; the tool self-verifies and offers a
  `--check` dry run; the gate is satisfiable because it does not assume uniformity.
- **Disadvantages:** Component versions become heterogeneous, so "what version is
  pack X" must be read from pack X, not inferred from the release; `CLAUDE.md` and
  the bump procedure must be rewritten.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 2: change-driven component versioning.** A component's version
moves only when its files change. `harness.config.json` `.version` is the single
release pointer that always bumps; `.claude-plugin/marketplace.json`
`.metadata.version` tracks it.

This is realized by:

- **`scripts/bump-version.sh`** — reads the current version from
  `harness.config.json`, resolves the new one (`patch`/`minor`/`major` or an
  explicit semver), and rewrites the template pointer, the marketplace catalog,
  and a new dated `CHANGELOG.md` section. Per-pack stamps move only when a pack is
  passed with `--pack <component>` (then its `plugin.json`, its `SKILL.md`, and its
  `**Version:**` doc row, anchored to the component's section, are bumped). It only
  touches structural JSON fields and section-anchored lines, self-verifies its
  writes, and supports `--check` for a dry run.
- **`gate_versions` in `scripts/verify.sh`** — asserts the template version is
  well-formed semver, the marketplace catalog equals it, and every `SKILL.md` /
  `plugin.json` stamp is well-formed semver (catching a botched bump). It does
  **not** require uniformity, because independent versions (`readme@2.0.0`,
  ontology packs) are legitimate under this model.
- **`scripts/check-version-bump.sh` + the `version-bump` CI job** — enforces
  *bump-on-change* (the binding half of the requirement). On every pull request it
  diffs against the base and fails when a changed pack or core skill did not move
  its own version, or when any change left the `harness.config.json` release
  pointer unmoved — naming the offending component and the fix. A change that
  warrants no release uses `[skip-version-check]` on its own line in a commit
  (waiving the pointer rule only; a changed pack or skill must always bump).
  Ontology packs are
  exempt. `gate_versions` checks versions are *consistent*; this gate checks they
  were *moved when required* — together they close the gap the old, fictional
  drift gate only pretended to.
  > **Superseded in part — see the [2026-07-01 amendment](#amendment-2026-07-01-the-release-pointer-is-not-a-per-pr-obligation)
  > below.** The release-pointer half of this rule (comparing against a PR's own
  > base) is replaced: the pointer must stay ahead of the last actual release, not
  > move on every individual PR. Rule A (per-pack/skill bump-on-change) is
  > unchanged.
- **Completeness proof** — after a bump, `git grep <old-version>` returns only the
  CHANGELOG history line; `git diff --name-only` is the exact, enumerable change
  set. This independent check is what makes any bump — including the first run of a
  new tool on a live release — provably complete.

## Consequences

### Positive

1. A release diff is proportional to the actual change. The `0.4.3` release that
   introduced this model touches three version files, not eighty.
2. Version numbers carry information again: a pack at `0.4.2` in a `0.4.3` harness
   genuinely has not changed since `0.4.2`.
3. The safety net is real and satisfiable: a self-verifying bump tool, a
   consistency gate (`gate_versions`), and a PR-only bump-on-change gate
   (`scripts/check-version-bump.sh`) that fails a change which forgot to move its
   version — the binding enforcement the old drift gate only claimed to provide.

### Negative

1. Component versions are heterogeneous; there is no single number that describes
   "everything in this clone." Mitigated by `harness.config.json` remaining the
   one release pointer and the marketplace catalog tracking it.

### Neutral

1. `docs/reference/packs/*.md` version rows are now per-pack and only change when
   that pack changes, so a family doc may show several different versions — correct
   under this model, but different from the old uniform appearance.

## Decision Outcome

The harness now versions by change. The churn and corruption risk of lockstep
stamping are gone, replaced by a single release pointer, a self-verifying tool,
a consistency gate, and a CI bump-on-change gate. The one cost — heterogeneous
component versions — is the considered consequence of letting version numbers mean
what they are supposed to mean.

## Related Decisions

- 0005-packs-and-plugins-extension-model.md
- 0008-attested-fail-closed-supply-chain.md

## More Information

- **Date:** 2026-06-29
- **Source:** `scripts/bump-version.sh`, `scripts/check-version-bump.sh`, `scripts/verify.sh` (`gate_versions`), `.github/workflows/ci.yml` (`version-bump` job), `CLAUDE.md`

## Audit

### 2026-06-29

**Status:** Compliant

| Finding | Files | Assessment |
| --- | --- | --- |
| Single release pointer bumped, catalog tracks it | `harness.config.json`, `.claude-plugin/marketplace.json` | compliant |
| No unchanged pack stamp moved in the 0.4.3 bump | `packs/**`, `.claude/skills/**` | compliant |
| Consistency gate enforces the real invariants | `scripts/verify.sh` | compliant |
| Bump tool self-verifies and supports dry run | `scripts/bump-version.sh` | compliant |
| Bump-on-change enforced on PRs (changed component must move its version) | `scripts/check-version-bump.sh`, `.github/workflows/ci.yml` | compliant |

**Summary:** The 0.4.3 release was performed change-driven and verified by `git grep` completeness, `gate_versions`, and the `version-bump` CI gate (tested: a changed pack without a bump fails).

**Action Required:** None

## Amendment (2026-07-01): the release pointer is not a per-PR obligation

The original Rule B required *every* pull request to move `harness.config.json`
`.version` relative to its own merge-base, or carry `[skip-version-check]`. In
practice this meant two PRs opened against the same `main` commit — a routine
situation, not a mistake by either author — collided: whichever merged first
bumped the pointer; the second's own diff then showed the pointer "unchanged"
against its stale base and failed CI, even though `main` itself was already
ahead. This happened twice on 2026-07-01 (PRs #241/#242, then #243), each
requiring a manual rebase and re-bump to unblock, and does not scale: a project
with parallel work in flight should not force N PRs to fight over the same
version number.

**The requirement was never actually "every PR bumps the pointer."** The real
requirement — the one semantic versioning and a release process both actually
need — is *the pointer must have moved since the last release by the time the
next release is cut*, not that any specific PR be the one to move it. Rule B is
changed accordingly: `check-version-bump.sh` now compares `harness.config.json`
`.version` against the **last git tag release** (`git tag --list 'v*'`, highest
semver), not the PR's own base, and fails only if the pointer has regressed to
or below that tag. A PR that changes files without touching the pointer now
passes as long as *something* — this PR, an earlier one, or a later one before
the next release — keeps the pointer ahead of the last release. `[skip-version-check]`
is removed: there is no longer a per-PR pointer obligation to waive.

Rule A (a changed pack or core skill must move its own version) is **unchanged**
— that is a real per-component omission, not a race condition, and stays
per-PR.

This does not weaken the release-pointer invariant; it makes it match what was
actually true: the pointer is a release-time property of the repository, not a
per-commit property of any one PR.

### 2026-07-01

**Status:** Compliant

| Finding | Files | Assessment |
| --- | --- | --- |
| Rule B compares against the last release tag, not a PR's own base | `scripts/check-version-bump.sh` | compliant |
| Two PRs racing off the same base no longer collide on the pointer | tested: a file change with no version bump, base at v0.11.1 vs last tag v0.8.1, passes | compliant |
| A real regression (pointer at or below the last tag) still fails | tested: pointer forced to the last tag's value fails with a named message | compliant |
| Rule A (per-pack/skill bump-on-change) unchanged and still enforced | tested: a changed pack with no version bump still fails | compliant |
| Portable semver compare (no `sort -V`) | `scripts/check-version-bump.sh` | compliant — this session already hit one GNU-only-flag portability break (`realpath -m`) on this same template; `sort -V` is BSD-absent the same way |

**Summary:** The release-pointer rule was relaxed from a per-PR obligation to a per-release invariant, closing the exact collision this repository hit twice in one day. Verified locally against three scenarios (unbumped-but-ahead passes, regression fails, per-component rule unaffected) before landing.

**Action Required:** None
