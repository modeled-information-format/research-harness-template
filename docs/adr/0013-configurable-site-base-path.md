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

Two other approaches were considered and rejected. Leaving `BASE` hardcoded
and documenting that a clone hand-patches `astro.config.mjs` after
instantiation was rejected: it directly violates the file's own documented
byte-identical invariant, and guarantees a merge conflict on every future
`copier update` for any clone that customizes it. Inferring the base path
automatically from the repo/project name (`.copier-answers.yml`
`project_name` or the git remote) was also rejected: a repo name does not
reliably determine the deploy path — many instances deploy at a custom
domain's root or a user/org root site, where the repo name plays no part in
the URL — and a wrong automatic guess breaks every link identically to a
missing one, so an explicit, documented default is safer than an inference
that still needs the same override escape hatch.

## Decision

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
