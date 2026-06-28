---
title: "How to configure the reports site"
diataxis_type: how-to
---

# How to configure the reports site

The harness ships an Astro/Starlight site that renders your `reports/` (and the
Diátaxis `docs/`) for local human reading. In the template it is the published
docs site and demonstrates the bundled example report; in an instantiated harness
it is your primary local mode of reading research. This guide shows how to choose
which surface leads, toggle the optional site plugins, and read your reports
locally. For the underlying control plane, see the `site` block in the
[configuration reference](../reference/configuration.md) and
[`site-toggle.sh`](../reference/scripts.md).

## Before you begin

- Have the [core runtime](../reference/dependencies.md) installed (`jq` for the
  toggles) plus `node` to build the site (`npm install` once).
- The one file you edit is `harness.config.json`; the toggles write its `.site`
  block. You never hand-edit `astro.config.mjs` — it reads `.site` at build time.

## Read your reports locally

```sh
npm install
npm run dev          # serve with live reload; or: npm run build && npm run preview
```

`npm run reports` is an alias for the local reader. A clone is activated
reports-primary at instantiation (see below), so your reports lead the sidebar. For
the full step-by-step (the local URL and base path, production preview, and
troubleshooting), see [How to run and browse the local site](run-the-local-site.md).

## Choose the leading surface

```sh
bash scripts/site-toggle.sh primary reports   # Reports lead the sidebar
bash scripts/site-toggle.sh primary docs      # docs lead; Reports come after
bash scripts/site-toggle.sh primary auto      # reports when any report exists, else docs
```

The site landing (`/`) stays the docs index in every case; `primary` only orders
the sidebar groups. Rebuild (`npm run build`) to apply.

## Toggle an optional plugin

```sh
bash scripts/site-toggle.sh plugin imageZoom on        # click-to-zoom images
bash scripts/site-toggle.sh plugin linksValidator on   # fail the build on broken links
bash scripts/site-toggle.sh plugin llmsTxt off         # stop emitting llms.txt
bash scripts/site-toggle.sh plugin mermaid off         # stop rendering mermaid fences
```

`llmsTxt` and `mermaid` are installed and on by default; `imageZoom` and
`linksValidator` are installed and off by default. Note `linksValidator` fails the
build on any broken internal link, including links to non-page report siblings —
enable it only once your reports' links resolve.

## Activation in a clone

When you instantiate the harness with `copier copy --trust`, a post-copy task runs
`site-toggle.sh primary reports` so the clone boots reports-primary. The `--trust`
flag is required for copier to run the task; without it the clone stays
docs-primary and you can run the toggle yourself. The bundled example report is
deliberately not copied into clones — your first `/start` populates your own topic.

## Do it conversationally

The [`/configure`](../reference/commands.md) command is a concierge over all of
this: it toggles packs and site features, manages ontologies and topics, and
re-runs the gates. For example, ask it to "make reports the primary surface and
turn on image zoom" and it drives the same scripts and validates the result.
