---
name: publish-blog
description: "Render surviving research findings into a publishable blog post through the typed findings-to-artifact contract. A first-class harness output (not a pack). Use this skill when the user wants to turn research into a blog post, publish findings, draft an article from the corpus, or write up what the research found. Triggers on 'publish blog', 'blog post from research', 'write up these findings', 'draft an article', 'turn this into a post'."
version: 1.0.0
argument-hint: "[--topic <id>] [--genre <genre>] [--out <path.md>]"
allowed-tools: Read, Bash, Edit, Glob, Grep
---

# publish-blog — research → blog post

Blog is one of the two **first-class** harness outputs (SPEC §6d): it ships in the
core, always on, not as a pack. It renders a published post from the surviving
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

3. **Render the post.**

   ```bash
   scripts/render-artifact.sh reports/<topic>/artifact.json blog blog/<topic>.md
   ```

4. **Gate the output.** The post must read as if written from public primary
   sources alone. The bundled `check-citation-leak.sh` hook fires on write; before
   reporting done, confirm zero leaks (no finding ids, `urn:mif:` ids, or
   `reports/<slug>/` paths) and that every claim traces to a `## Sources` entry.

## Non-negotiables

- **Never publish a falsified or quarantined finding.** The synthesizer filters
  them; do not reintroduce them by hand.
- **Never leak internal research references** into the prose. Re-author from the
  primary source; do not just delete the token.
- The post is a projection of the artifact — to change the content, change the
  findings or the synthesis, not the rendered Markdown in place.
