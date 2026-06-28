---
title: "The Astro/Starlight site renders the full instance corpus"
description: "Make the rendered site build and navigate the whole research corpus in any instantiated clone, not just the template's example, by fixing the symlink-render, frontmatter, and exclusion gaps that only surface once real reports exist."
type: adr
category: architecture
tags: [site, astro, starlight, copier, content-collection, reports]
status: accepted
created: 2026-06-28
updated: 2026-06-28
author: zircote
project: research-harness-template
technologies: [Astro, Starlight, Copier]
audience: [developers, architects]
related: [0007-report-channel-canonical-blog-mif-exempt.md, 0005-packs-and-plugins-extension-model.md]
---

# ADR-0009: The Astro/Starlight site renders the full instance corpus

## Status

Accepted

## Context

### Background and Problem Statement

The Astro/Starlight site (`src/content.config.ts`, `astro.config.mjs`) projects the
Diátaxis `docs/` tree and the rendered `reports/` corpus into one Starlight `docs`
collection. The template ships only a single example topic, so the template's own
CI builds the site cleanly. Several gaps therefore stay invisible in the template
and only surface in a real instantiated clone with many topics, genre deliverables,
and falsification output:

1. **`harness-instance.md.jinja` carries no Starlight frontmatter.** It renders
   into the `docs` collection, whose `docsSchema()` requires `title`, so
   `astro build`/`astro dev` abort with `InvalidContentEntryDataError` in *every*
   clone before any report is even considered.
2. **Copier flattens symlinked directories on render.** The template ships
   `docs/reports -> ../reports` and `src/content/docs -> ../../docs`, but Copier
   materializes both as real directories in the clone. `gate_m23` checked only the
   first symlink, so the second silently regressed and the content collection
   resolved a stale copy — the site showed only the example, never the clone's
   corpus.
3. **The content-glob exclusions did not cover audit/continuity artifacts.** A real
   corpus emits `*-falsification-report.md`, `*-delta.md`, and `*-build-spec.md`
   logs that carry no Starlight frontmatter; the glob ingested them and aborted the
   build.
4. **The sidebar is unusable at corpus scale.** With dozens of topics every group
   expanded by default, the navigation is an unscannable wall.

### Decision Drivers

- The site must build and navigate the *clone's* corpus, not just the template's
  example — the corpus is the product.
- Fixes belong at the template source (`.jinja`, `copier.yml` tasks, gates,
  config), never as instance hand-patches, so `copier update` propagates them.
- No regression of the existing report channel: canonical L3 reports and genre
  deliverables stay pages; continuity logs and nav indexes stay out of the
  collection (ADR-0007).

## Decision

Close the four gaps at the source:

1. **`harness-instance.md.jinja` ships Starlight frontmatter** (`title`,
   `description`) and drops the duplicate H1 (Starlight renders the title).
2. **Copier re-establishes both symlinks** via `_tasks` (`ln -sfn ../reports
   docs/reports`, `ln -sfn ../../docs src/content/docs`), and **`gate_m23` now
   asserts both** symlinks, not just `docs/reports`.
3. **The content-glob excludes the audit/continuity artifacts**
   (`*-falsification-report.md`, `*-delta.md`, `*-build-spec.md`), and `gate_m23`
   enforces those exclusions. They are logs, not pages — consistent with the
   already-excluded `research-progress.md`, `findings/`, `_meta/`, and `README.md`.
4. **The sidebar groups collapse by default** (`collapsed: true`) so a large corpus
   is navigable.

Canonical L3 reports and genre deliverables continue to carry MIF frontmatter and
remain pages; the per-topic `README.md` stays the (frontmatter-less) build-topic
nav index and is intentionally not a page (it serves the `--check` gate). Surfacing
the per-topic README as a Starlight page would require the README generator to emit
Starlight frontmatter without breaking the `--check` gate or `markdownlint` MD025;
that is left to a follow-up.

## Consequences

### Positive

- The site builds and navigates the full corpus in any clone (verified: example +
  real corpora), closing the two filed defects (#164, #165).
- The fixes propagate through `copier update` because they live in the template
  source and are gate-enforced.

### Negative / Trade-offs

- The audit/continuity artifacts (falsification reports, deltas, build specs) are
  not browsable as site pages. They remain in `reports/` for the corpus and the
  gates; only the site projection omits them.
- The per-topic README is still not a navigable page (follow-up).
