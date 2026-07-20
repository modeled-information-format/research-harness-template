---
name: publish-blog
description: "Render surviving research findings into a publishable blog post through the typed findings-to-artifact contract. A first-class harness output (not a pack). Use this skill when the user wants to turn research into a blog post, publish findings, draft an article from the corpus, or write up what the research found. Triggers on 'publish blog', 'blog post from research', 'write up these findings', 'draft an article', 'turn this into a post'."
version: 0.4.2
argument-hint: "[--topic <id>] [--genre <genre>] [--out <path.md>]"
allowed-tools: Read, Bash, Edit, Glob, Grep
---

# publish-blog — research → blog post

Blog is the **first-class** published harness output (SPEC §6d): it ships in the
core, always on, not as a pack (book and other channels arrive via optional channel
packs). It renders a published post from the surviving
findings of a session through the **typed findings→artifact contract**
(`schemas/artifact.schema.json`) — the same contract the book output uses, so the
citation-integrity and citation-leak gates run uniformly across both.

## Pipeline

1. **Resolve the finding set.** Default to the topic's findings dir
   (`reports/<topic>/findings/`). Only **surviving** findings (verdict ≠
   `falsified`) are eligible — quarantined and falsified findings never publish.

2. **Synthesize the artifact.** Run the report-synthesizer's substrate:

   ```bash
   scripts/synthesize-artifact.sh reports/<topic>/findings <genre> reports/<topic>/artifact.json
   ```

   The artifact is genre/channel-neutral and validates against
   `schemas/artifact.schema.json`. The `newsworthiness` field carries the
   engine's delta signal — the hook a publication needs.

3. **Render the post.** Every output lives under `reports/<topic>/`, never a
   top-level `blog/` directory — the trailing `.blog.md` suffix (not a leading
   `blog/` prefix) is what identifies the channel:

   ```bash
   scripts/render-artifact.sh reports/<topic>/artifact.json blog reports/<topic>/<topic>.blog.md
   ```

   Requesting a specific genre alongside the blog channel renders to
   `reports/<topic>/<topic>.<genre>.blog.md` instead (keeps it collision-free
   against the report channel's own `reports/<topic>/<topic>.<genre>.md`
   files).

4. **Gate the output.** The post must read as if written from public primary
   sources alone. The bundled `check-citation-leak.sh` hook fires on write; before
   reporting done, confirm the body has zero leaks (no finding/concept ids
   `urn:mif:concept:`/`urn:mif:report:`, no `reports/<slug>/` paths) and that every
   claim traces to a `## Sources` entry. The post's own `urn:mif:blog:` frontmatter
   id (its MIF Level-1 identity) is not a leak.

## Non-negotiables

- **Never publish a falsified or quarantined finding.** The synthesizer filters
  them; do not reintroduce them by hand.
- **Never leak internal research references** into the prose. Re-author from the
  primary source; do not just delete the token.
- The post is a projection of the artifact — to change the content, change the
  findings or the synthesis, not the rendered Markdown in place.
- **Rebuild the topic README after publishing.** The post renders to
  `reports/<topic>/<topic>.blog.md`, inside `reports/<topic>/` alongside the
  canonical report and any genre-suffixed report-channel files. The
  navigation README's Reports table is built from every `reports/<topic>/*.md`
  file (via `scripts/build-topic-readme.sh`), so a blog write now changes what
  that table should show — run `bash scripts/build-topic-readme.sh <topic>`
  (or the `readme` skill) before reporting this done, the same as
  `publish-report` already does.
- **`blog` is a MIF-exempt channel** (declared `mifExempt: true` in
  `harness.config.json` `outputs[]`): its public prose is orthogonal to MIF, so the
  MIF Level-3 source of truth lives in the generic `report` channel
  (`reports/<topic>/<slug>.md`), not the post. The MIF I/O conformance gate skips
  and logs the post; it does not require an L3 projection of it.
