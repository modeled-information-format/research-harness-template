---
name: jats
description: "Render a research topic's surviving findings into well-formed JATS (NISO Z39.96) XML directly FROM THE SOURCES — the findings corpus and the primary materials its citations point to. Composes a scholarly article (article metadata in <front>/<article-meta>, a <body> of one section per finding, and a <back>/<ref-list> reference list) and serializes it as JATS XML. NEVER built from a rendered report (that would be a copy-of-a-copy). Optional channel; verify the current NISO Z39.96 version live before tagging. Use when the user says 'render to JATS', 'export as JATS XML', or 'make a JATS article'."
version: 0.4.0
argument-hint: "<findings-dir> [-o <article.xml>] [<topic-name>]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# JATS Channel — source-grounded

**Non-negotiable: this deliverable is produced from the SOURCES alone.** The input
is the topic's surviving findings corpus (`reports/<topic>/findings/*.json`) and the
primary materials its citations reference — never a rendered report, blog, or other
channel's output. Building JATS from a synthesized report would be a copy-of-a-copy
(a simulacrum of the sources); it is forbidden. Every body section traces to a
finding, and every reference to that finding's primary-source citation.

JATS (Journal Article Tag Suite, **NISO Z39.96**) is a machine-readable XML
*serialization* of a scholarly article — a render target, the orthogonal analog of
the `pdf` channel, not a `reports/` genre. This is an **optional** channel.

## Phase 0: Verify the JATS version (run first)

Anchor to the **current** NISO Z39.96 edition. As of this writing the active
version is **JATS v1.4 (ANSI/NISO Z39.96-2024, October 2024)** — verify live before
tagging:

```bash
# Confirm the current edition; do not trust a cached version string.
echo "Verify current NISO Z39.96 version at https://www.niso.org/publications/z3996-2024-jats"
```

Pick a tag set at implementation: Archiving/Blue (`archivearticle`), Publishing/Green
(`articlemeta`), or Authoring/Pumpkin. Default to the **Archiving and Interchange**
(Blue) DTD for maximum interchange fidelity, and record the chosen
`@dtd-version="1.4"` on the root `<article>`.

## Phase 1: Load the sources

Resolve `<findings-dir>` to the topic's findings directory. Load **every surviving
finding** (verdict ≠ `falsified`):

```bash
jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
```

Each finding carries: `title` (the verified claim), `content`, `citations[]` (its
**primary sources** — title + url + type + role), `entities[]`, and
`extensions.harness.dimension`/`verification.verdict`. These are the sources. Read
no rendered report or artifact. Default output is `<findings-dir>/../<topic>.xml`.

## Phase 2: Compose the JATS article FROM the sources

Serialize a well-formed JATS XML article grounded in the findings — **exhaustive,
one body section per finding**, never a thinned summary. The required skeleton:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<article xmlns:xlink="http://www.w3.org/1999/xlink"
         dtd-version="1.4" article-type="research-article" xml:lang="en">
  <front>
    <article-meta>
      <title-group><article-title>TOPIC TITLE</article-title></title-group>
      <pub-date date-type="pub"><year>YYYY</year></pub-date>
      <abstract><p>One-paragraph synthesis of the surviving findings.</p></abstract>
    </article-meta>
  </front>
  <body>
    <!-- one <sec> per surviving finding -->
    <sec>
      <title>FINDING CLAIM</title>
      <p>FINDING CONTENT. Cited primary source <xref ref-type="bibr" rid="r1">[1]</xref>.</p>
    </sec>
  </body>
  <back>
    <ref-list>
      <!-- one <ref> per unique primary-source citation -->
      <ref id="r1">
        <element-citation publication-type="webpage">
          <article-title>CITATION TITLE</article-title>
          <ext-link ext-link-type="uri" xlink:href="https://...">https://...</ext-link>
        </element-citation>
      </ref>
    </ref-list>
  </back>
</article>
```

Rules:

1. **`<front>`/`<article-meta>`** — the topic title (`<article-title>`), publication
   date (from today / the corpus namespace), and an `<abstract>` synthesizing the
   surviving findings.
2. **`<body>`** — for every surviving finding, a `<sec>` with a `<title>` (the claim)
   and `<p>` content, linking each claim to its citation via `<xref ref-type="bibr">`.
   Group by dimension with nested `<sec>` if that aids the reader.
3. **`<back>`/`<ref-list>`** — one `<ref>`/`<element-citation>` per **unique** primary
   source across all findings, each with `<article-title>` and an `<ext-link>` to the
   url. This is the point — the reader can follow each claim back to its primary source.

Constraints: every claim traces to a finding and its primary source; invent nothing
not in the findings. **XML-escape** all text content (`&amp; &lt; &gt;`). Write the
serialized JATS XML to the output path.

## Phase 3: Identity and the citation-leak gate

The rendered JATS XML carries **no internal-research identity** — emit finding
claims + public citations only, never finding/concept `@id`s, `urn:mif:` ids,
`reports/<slug>/` paths, or `f_<dim>_<n>` handles. The rendered file is exempt from
the L3 I/O conformance gate (it is a format orthogonal to MIF L3, declared via the
pack's `mif.exempt`), but the citation-leak gate still applies to the full
serialization: **no `urn:mif:` string anywhere in `article.xml`**.

The topic's MIF Level-1 identity rides in the article's *public* metadata only — the
journal/namespace label and date — not the internal URN scheme:

```xml
<journal-meta><journal-id journal-id-type="publisher">NAMESPACE</journal-id></journal-meta>
```

If a JATS consumer requires an `<article-id>`, mint a public, scheme-free identifier
(e.g. a slug or DOI), never the internal `urn:mif:` URI.

## Phase 4: Verify and clean up

1. Confirm the XML file exists and is non-empty; report its path.
2. Well-formedness check (`xmllint --noout <article.xml>` if available; else a basic
   tag-balance scan). Surface any parse error for diagnosis.
3. Confirm completeness: one `<sec>` for **every** surviving finding and one `<ref>`
   for every unique primary source — spot-check the count.

## Non-negotiables

- **Sources only.** Build from the findings corpus + primary citations. Never from a
  rendered report/blog/book/pdf/artifact — that is a copy-of-a-copy and is forbidden.
- **Exhaustive.** Every surviving finding gets a `<sec>`; every primary source a
  `<ref>`. No truncation.
- **No internal identity in the body.** Finding/concept ids, `urn:mif:`, corpus paths,
  and `f_<dim>_<n>` handles never render into the JATS body — nor anywhere in the XML; the
  source's identity rides only in a **public, scheme-free** `<article-id>` (never the
  `urn:mif:` URN itself).
- **Verify the version live.** Anchor to the current NISO Z39.96 edition (JATS v1.4,
  Oct 2024 at this writing); never trust a cached version string.

## Error Handling

- Malformed XML: surface the `xmllint` error for diagnosis; do not emit a partial file.
- Missing citation url on a finding: emit the `<ref>` with `<article-title>` only and warn.
- No surviving findings: warn and emit an empty-body article rather than crashing.
