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
remain pages.

> **Superseded in part — see the [2026-06-28 amendment](#amendment-2026-06-28-serve-the-full-deliverable-tree) below.**
> Point 3's exclusion of `*-falsification-report.md` and the README, and the deferral
> of "the per-topic README as a page", are reversed: every deliverable now renders.

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
  *(Falsification reports are now served — see the amendment.)*
- The per-topic README is still not a navigable page (follow-up).
  *(Now served as the topic index — see the amendment.)*

## Amendment (2026-06-28): serve the full deliverable tree

The original decision hid the README, the falsification report, the neutral synthesis,
and the research-progress log from the site because each lacks Starlight frontmatter.
That was wrong for the product: **these are critical, consumer-facing research
deliverables — excluding them obfuscates the work and costs credibility.** Every
deliverable under `reports/<topic>/` now renders. This supersedes Decision point 3's
README/falsification exclusion and the deferred "README as a page" follow-up.

How, without mutating the generated artifacts:

1. **Derived titles in the content loader.** `src/content.config.ts` wraps `glob()`
   (`reportsLoader`/`deriveTitleFromH1`): a reports/ entry with no Starlight `title`
   gets one derived from its body `# H1` (then a humanized filename). The files are
   never edited, so clones' future artifacts render the same way — no generator change.
2. **README is the topic index.** A custom `generateId` re-slugs `reports/<topic>/README.md`
   to `reports/<topic>/`, making it the topic's landing page.
3. **No double heading.** A remark plugin (`remarkStripReportH1`) strips the leading body
   H1 of a derived-title page at render, since Starlight already renders the derived title.
4. **Uncluttered nav.** The sidebar lists ONE link per topic (its README index), not a
   per-report autogenerate tree; a `Sidebar` component override adds a client-side topic
   filter. A topic's constituents are navigated from the README index's **Type → Title**
   Reports table (ordered by a single canonical map in `scripts/build-topic-readme.sh`:
   executive summary → briefing → synthesis → genre reports → falsification report →
   research progress).

Only `reports/_meta/`, `findings/*.json`, and the `*-delta.md` / `*-build-spec.md` build
logs remain excluded (data/logs with no stable page shape). `gate_m23` is updated to assert
the loader markers, that the README/falsification/research-progress negations are gone, and
that the example topic's deliverables each carry a derivable H1.
