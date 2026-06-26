---
name: book-author
description: "Render surviving research findings into a book chapter through the typed findings-to-artifact contract. An OPTIONAL channel pack (enable the `book` pack to use it), supporting the full genre range. Use this skill when the user wants to author a book, write a chapter from the research, turn the corpus into long-form, or build a manuscript. Triggers on 'write a book', 'author a chapter', 'book from research', 'turn this into a chapter', 'long-form from the corpus', 'manuscript'."
version: 0.3.0
argument-hint: "[--topic <id>] [--genre <genre>] [--chapter <n>] [--out <path.md>]"
allowed-tools: Read, Bash, Edit, Glob, Grep
---

# book-author — research → book chapter

Book is an **optional channel pack** (SPEC §6d): enable the bundled `book` channel
pack to author long-form — it is not an always-on core output (blog is the
first-class published channel). It renders a chapter from the surviving findings
through the **same typed findings→artifact contract** (`schemas/artifact.schema.json`)
the blog output uses — so a research corpus drives both a post and a book from one
synthesis, and
the citation gates run uniformly across both.

The book pipeline supports its full genre range (technical / children's / fiction
/ history / non-fiction) via the genre passed to the synthesizer, and the chapter
carries front/endnote matter. The citation-leak gate is the manuscript invariant:
a chapter must read as if written from public primary sources alone.

## Pipeline

1. **Resolve the finding set** for the chapter — the topic's surviving findings
   (verdict ≠ `falsified`).

2. **Synthesize the artifact** (the report-synthesizer substrate):

   ```bash
   scripts/synthesize-artifact.sh reports/<topic>/findings <genre> reports/<topic>/artifact.json
   ```

3. **Render the chapter** from the same artifact the blog uses:

   ```bash
   scripts/render-artifact.sh reports/<topic>/artifact.json book book/<topic>/chapters/<n>.md
   ```

4. **Gate the manuscript.** The bundled `check-citation-leak.sh` hook guards
   `book/*/chapters/*.md`: no finding ids, `urn:mif:` ids, or `reports/<slug>/`
   paths may appear. Re-author any flagged passage from the primary source.

## Non-negotiables

- **Never include a falsified or quarantined finding** — the synthesizer filters
  them.
- **Manuscript prose carries no internal-research references.** The chapter cites
  only the public sources in its endnotes.
- The chapter is a projection of the artifact; change the findings or synthesis,
  not the rendered Markdown in place.
- **`book` is a MIF-exempt channel** (declared `mifExempt: true` in
  `harness.config.json` `outputs[]`): its public prose is orthogonal to MIF, so the
  MIF Level-3 source of truth lives in the generic `report` channel
  (`reports/<topic>/<slug>.md`), not the chapter. The MIF I/O conformance gate skips
  and logs the chapter; it does not require an L3 projection of it.
