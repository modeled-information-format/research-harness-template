---
title: "Configurable site base path"
description: "Move the Astro/Starlight site's deploy base path out of a hardcoded literal in astro.config.mjs (the template's own GitHub Pages path) into harness.config.json .site.base, since every clone's real deploy target differs and the file is documented as byte-identical across instances."
type: adr
category: architecture
tags: [site, astro, config, base-path, copier]
status: accepted
created: 2026-07-01
updated: 2026-07-01
author: zircote
project: research-harness-template
technologies: [Astro, Starlight, Copier]
audience: [developers, architects]
related: [0009-site-renders-full-instance-corpus.md]
---

# ADR-0013: Configurable site base path

## Status

Accepted

## Context

### Background and Problem Statement

`astro.config.mjs` hardcoded `const BASE = "/research-harness-template"` — the
template's own GitHub Pages project-page path. This directly contradicts the
file's own header comment: "neither the template nor a clone hand-edits THIS
file — astro.config.mjs stays byte-identical across instances and `copier
update` never conflicts on it." Every other site-projection control
(`primarySurface`, the four plugin gates) is read from `harness.config.json
.site` at build time for exactly this reason; `base` was the one exception,
left as a literal.

Every instantiated clone deploys somewhere different: a GitHub Pages user/org
root site, a GitHub Pages project page under `/<repo>`, a custom domain at
root, or a custom sub-path behind a reverse proxy. A clone serving from
anywhere other than the template's own literal path had every internal link
in the rendered site 404 — the cross-link rewriter
(`astro-rehype-relative-markdown-links`) and the splash page both compute
final hrefs from `BASE`, so a wrong or absent base breaks navigation
site-wide, not just at one page.

`docs/index.mdx` (the splash/homepage) compounded the problem: every one of
its eight internal links duplicated the same `/research-harness-template`
literal as a static string, independent of any config value at all — the
only place in the entire `docs/` tree with this anomaly.

## Decision Drivers

### Primary Decision Drivers

1. PDD-1: The site must serve correctly from whatever real deploy target a
   clone actually uses (root, project-page sub-path, custom domain, or a
   reverse-proxy sub-path), not just the template's own literal path.
2. PDD-2: `astro.config.mjs` must remain genuinely byte-identical across
   instances (its own documented invariant) so `copier update` never
   conflicts on it — every other site-projection control already reads from
   `harness.config.json .site` at build time for exactly this reason.

### Secondary Decision Drivers

1. SDD-1: The splash page's internal links must not duplicate the base path
   as a separate hardcoded string, since that lets them drift independently
   of whatever the real config says.

## Considered Options

### Option 1: Leave BASE hardcoded, hand-patch astro.config.mjs per clone

Document that a clone hand-edits `astro.config.mjs`'s `BASE` literal after
instantiation to match its own real deploy target.

**Advantages:** No schema or config-plumbing change required; works for a
single one-off clone with no other tooling changes.

**Disadvantages:** Directly violates the file's own documented byte-identical
invariant; guarantees a merge conflict on every future `copier update` for any
clone that customizes it.

**Risk Assessment:** Technical — every hand-patched clone permanently diverges
from the template source; Schedule — fast for one clone, but recurring
`copier update` conflicts forever after; Ecosystem — every clone that deploys
anywhere but the template's own path must independently discover and repeat
this hand-patch.

### Option 2: Infer the base path automatically from the repo/project name

Derive `BASE` from `.copier-answers.yml`'s `project_name` or the git remote,
with no explicit config value at all.

**Advantages:** Zero configuration for the common case where the repo name
happens to match the deploy path.

**Disadvantages:** A repo name does not reliably determine the deploy path —
many instances deploy at a custom domain's root or a user/org root site, where
the repo name plays no part in the URL — and a wrong automatic guess breaks
every link identically to a missing one.

**Risk Assessment:** Technical — a silently wrong inference breaks navigation
site-wide with no indication why; Schedule — no explicit config to author, but
still needs the same override escape hatch once inference is wrong; Ecosystem
— every custom-domain or user/org-root clone hits the same silent breakage.

### Option 3: Explicit, documented config value in harness.config.json .site.base (chosen)

Add `site.base` to `harness.config.json` (schema-validated, defaulting to
`/`), read it in `astro.config.mjs` the same way every other site-projection
control already is, and strip the splash page's duplicated literal so it
inherits the configured base like every other internal link.

**Advantages:** `astro.config.mjs` stays genuinely byte-identical — the file
only reads the config, never hardcodes a path; a clone that needs a non-root
base sets one explicit, documented value; the safe default (`/`) covers the
common cases (local dev, a custom domain, a GitHub Pages user/org root site)
with zero configuration.

**Disadvantages:** Requires a one-time schema addition and a reordering of
`astro.config.mjs`'s existing manifest read so the config value is available
before `BASE` is computed.

**Risk Assessment:** Technical — low, reuses the same config-read pattern
every other site-projection control already follows; Schedule — one
coordinated change across schema, config, and the splash page; Ecosystem —
every `copier`-instantiated clone gets a working, explicit override with no
inference risk.

## Decision

Option 3.

1. **`harness.config.schema.json`**: add `site.properties.base` — `string`,
   pattern anchored to a leading `/`, `default: "/"`.
2. **`astro.config.mjs`**: reorder the existing manifest read so `siteCfg` is
   available before `BASE` is computed, then
   `const BASE = siteCfg.base ?? "/";` replaces the literal. The header
   comment now states the fallback and the invariant explicitly.
3. **The template's own `harness.config.json`** sets `.site.base` to
   `/research-harness-template` — its real, already-live GitHub Pages
   project-page path — so its own deployment is unaffected.
4. **`docs/index.mdx`**: every internal link (`hero.actions[].link`, every
   `LinkCard href`) had its hardcoded `/research-harness-template/` prefix
   stripped to a bare `/`, making all eight links base-relative and letting
   Starlight inject the configured base like every other internal link in
   the docs tree already does.
5. **`scripts/verify.sh` gate_m23**: the "reports landing surfaced" check
   updated to assert `docs/index.mdx` contains the base-relative
   `link: /reports/`, not the old hardcoded literal.

Verified: full eval suite (35/35) and `verify.sh` (142/142) pass;
markdownlint clean; manually confirmed on a live dev server that
`.site.base = "/"` serves the site correctly at root with base-relative
links (previously the site root always 404'd), and reverting to
`.site.base = "/research-harness-template"` resolves exactly as before.

## Consequences

### Positive

- Every clone can now serve its site correctly from its own real deploy
  target by setting one config value, with zero risk of a `copier update`
  conflict on `astro.config.mjs` — the file stays genuinely byte-identical.
- The splash page's internal links can never drift from the configured base
  again, since they no longer duplicate it.
- The default (`/`, site root) is the safe choice for the common cases
  (local dev, a custom domain, a GitHub Pages user/org root site) without
  requiring any clone to configure anything.

### Negative

- A clone that already had this bug and worked around it by hand-patching
  `astro.config.mjs` must now instead set `.site.base` in
  `harness.config.json` and revert its hand-patch, or its next
  `copier update` will conflict on the file the patch touched.
- A custom-domain deployment still needs `base: "/"` even though it is not
  literally the GitHub Pages account's own root — the schema documents this
  but does not separately validate it.

### Neutral

- The template's own deployment sets `.site.base` explicitly to its real live
  path (`/research-harness-template`) rather than relying on the default —
  every other clone chooses its own value the same way, based on its actual
  deploy target.

## Decision Outcome

An explicit, schema-validated `site.base` config value lets every clone serve
its site correctly from its own real deploy target while keeping
`astro.config.mjs` genuinely byte-identical, avoiding both the merge-conflict
risk of hand-patching (Option 1) and the silent-breakage risk of inferring the
path from the repo name (Option 2).

## Related Decisions

- ADR-0009: the site-projection decision this config value extends — every
  other site-projection control it introduced already reads from
  `harness.config.json .site` the same way `base` now does.

## Links

- `harness.config.schema.json` — the `site.base` schema addition.
- `astro.config.mjs` — where `BASE` is now read from config instead of hardcoded.
- `docs/index.mdx` — the splash page whose 8 links were made base-relative.
- `scripts/verify.sh` (`gate_m23`) — the updated reports-landing-link assertion.

## More Information

- **Date:** 2026-07-01
- **Source:** `harness.config.schema.json`, `astro.config.mjs`, `docs/index.mdx`, `scripts/verify.sh` (`gate_m23`).

## Audit

### 2026-07-01

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Full eval suite (35/35) and verify.sh (142/142) pass | `evals/run-evals.sh`, `scripts/verify.sh` | compliant |
| `.site.base = "/"` serves the site correctly at root with base-relative links; reverting to the template's own path resolves exactly as before | manually confirmed on a live dev server | compliant |
| Splash page's 8 internal links made base-relative | `docs/index.mdx` | compliant |

**Summary:** All five decision points verified: schema addition, config-driven `BASE`, template's own explicit config value, base-relative splash links, and the updated gate assertion.

**Action Required:** None.
