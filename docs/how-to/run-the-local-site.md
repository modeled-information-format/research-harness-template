---
title: "How to run and browse the local site"
diataxis_type: how-to
---

# How to run and browse the local site

A runbook for serving the harness's Astro/Starlight site on your machine and
reading your reports in a browser. This is the primary local mode of consuming
research in an instantiated harness. To choose which surface leads or to toggle
site plugins, see [How to configure the reports site](configure-the-site.md).

## Before you begin

- Install Node `>=22.12.0` (the floor declared in `package.json` `engines`; it is
  what Astro 7 requires) and npm.
- Install the site dependencies once, from the repo root:

  ```sh
  npm install
  ```

## Run the dev server (live reload)

1. Start the dev server:

   ```sh
   npm run dev          # `npm run reports` is an alias for the same thing
   ```

2. The terminal prints a local URL. The site is served under whatever base path
   `harness.config.json` `.site.base` is set to (default `/`, the site root; see
   [Reference: configuration](../reference/configuration.md) and
   [ADR-0013](../adr/0013-configurable-site-base-path.md)) — in this template it
   is pinned to `/research-harness-template`, so the address to open is:

   ```text
   http://localhost:4321/research-harness-template/
   ```

   A clone with the default `base: "/"` opens the bare `http://localhost:4321/`
   instead. The port is `4321` unless it is taken, in which case Astro picks the
   next free port and prints it. Opening the bare `http://localhost:4321/` when
   your base is a non-root sub-path returns a **404**, not a redirect — open the
   base-pathed URL directly.

3. Open that URL. The left sidebar carries the **Reports** group (its position
   depends on `site.primarySurface`); expand it and click a topic's report to read
   it. Mermaid diagrams render in place, and links between reports resolve to their
   pages.

4. Leave the server running. Editing a report under `reports/` or a doc under
   `docs/` reloads the open page automatically.

5. Stop the server with `Ctrl-C`.

## Preview the production build

To browse exactly what CI builds and the org Pages shell deploys:

```sh
npm run build        # writes the static site to dist/
npm run preview      # serves dist/ locally
```

`npm run preview` prints the same base-pathed URL as the dev server. Use this to
confirm `llms.txt`, the search index, and the rendered routes before pushing.

## See a new report appear

Reports render from `reports/<topic>/<slug>.md`. After a research session writes a
new report (for example via `/start`), the dev server picks it up on the next
reload; a production preview needs a fresh `npm run build`. With
`site.primarySurface: auto`, the first report in a clone also flips the site to
reports-primary.

## Troubleshooting

- **A change is not showing up:** Astro caches content. Clear the cache and rebuild:

  ```sh
  rm -rf .astro dist
  npm run build
  ```

- **A report page shows only its title, no body:** confirm `npm install` applied the
  `patches/` patch (the relative-links plugin needs it on js-yaml 4); re-run
  `npm install` and rebuild.

- **The build fails on a broken link:** the `linksValidator` plugin is off by
  default. If you enabled it, point report links only at pages, not at non-page
  siblings (`findings/*.json`, `knowledge-graph.html`).
