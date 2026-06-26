---
name: xbrl
description: "Render surviving findings (typically a regulatory-disclosure artifact) into an inline XBRL (iXBRL) document directly from the SOURCES. Tags facts with xbrli:context / xbrli:unit and taxonomy concepts inside a human-readable XHTML shell, anchored to the current SEC inline-XBRL taxonomy. Never built from a rendered report."
version: 0.3.0
argument-hint: "<findings-dir> [-o <disclosure.xhtml>] [<topic-name>]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# XBRL Channel — inline XBRL from the sources

**Non-negotiable: this serialization is produced from the SOURCES alone.** The input
is the topic's surviving findings corpus (`reports/<topic>/findings/*.json`) — typically
mediated by a `regulatory-disclosure` artifact — and the primary materials those findings
cite. Never a rendered report, blog, or other channel's output. Building iXBRL from a
synthesized report would be a copy-of-a-copy (a simulacrum of the sources); it is
forbidden. Every tagged fact traces to a finding, and every figure to that finding's
primary-source citation.

Inline XBRL (iXBRL) embeds machine-readable XBRL facts inside a human-readable XHTML
document: a regulator's parser reads the tagged facts while a person reads the rendered
page. This channel is a render adapter — like `pdf` or `jats`, it is a serialization,
orthogonal to the MIF Level-3 report. The canonical L3 source of truth stays in the
`report` channel; this channel is `mif.exempt`.

This is an **optional** channel. It writes XHTML directly with stdlib tools (`jq` to read
findings); it shells out to no external render engine.

## Edition currency (verify live)

Inline XBRL facts reference a **taxonomy** (concept names like `us-gaap:NetIncomeLoss`).
Anchor concepts to the **current SEC inline-XBRL taxonomy edition** — do not assume a
taxonomy year from memory. Before tagging, confirm the live taxonomy/namespace at
<https://www.sec.gov/dera/data/financial-statement-and-notes-data-set> and the iXBRL
specification at <https://specifications.xbrl.org/work-product-index-inline-xbrl-inline-xbrl-1.1.html>.
When a finding's figure has no clean taxonomy concept, tag it as `ix:nonNumeric` under a
documented extension concept rather than forcing an ill-fitting standard concept.

## Phase 0: Load the sources

Resolve `<findings-dir>` to the topic's findings directory. Load **every surviving
finding** (verdict ≠ `falsified`):

```bash
jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
```

Each finding carries: `title` (the verified claim), `content`, `citations[]` (its
**primary sources** — title + url + type + role), `entities[]`, and
`extensions.harness.dimension`/`verification.verdict`. These are the sources. If a
`regulatory-disclosure` artifact is present, use it to order the disclosure sections, but
read the **findings** for the facts. Default output is
`<findings-dir>/../<topic>-disclosure.xhtml`.

## Phase 1: Plan contexts, units, and facts FROM the sources

From the surviving findings, derive:

1. **Contexts** — one `xbrli:context` per reporting period / entity dimension a finding
   reports against (an `id`, an `xbrli:entity`/`xbrli:identifier`, and an
   `xbrli:period` with `startDate`/`endDate` or `instant`).
2. **Units** — one `xbrli:unit` per measure (e.g. `USD` as
   `iso4217:USD`, `shares`, `pure` for ratios).
3. **Facts** — for each quantified claim in a finding, a tagged fact bound to a taxonomy
   concept, a `contextRef`, and (for numeric facts) a `unitRef` + `decimals`/`scale`.

Invent no figure not present in the findings. The visible XHTML body carries **no
internal-research identity** — emit finding claims + public citations only, never
finding/concept `@id`s, `urn:mif:` ids, `reports/<slug>/` paths, or `f_<dim>_<n>`
handles. The topic's MIF Level-1 identity rides in the XHTML `<head>` metadata
(Phase 3), not in the visible body.

## Phase 2: Author the inline XBRL document

Write a well-formed XHTML5 document whose root declares the inline-XBRL namespaces, with
the hidden/resources header carrying contexts and units, and the visible body carrying
the tagged facts:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- Illustrative values below (edition, namespace, slug, CIK, dates, entity name,
     and citation) are placeholders to be substituted from the sources; the snippet
     is shown as well-formed XML so it can be validated as-is. -->
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:ix="http://www.xbrl.org/2013/inlineXBRL"
      xmlns:xbrli="http://www.xbrl.org/2003/instance"
      xmlns:iso4217="http://www.xbrl.org/2003/iso4217"
      xmlns:dei="http://xbrl.sec.gov/dei/2024"
      xmlns:us-gaap="http://fasb.org/us-gaap/2024">
  <head>
    <meta name="dc.identifier" content="urn:mif:xbrl:acme-financials:fy2024-disclosure"/>
    <title>ACME Corp FY2024 Disclosure</title>
  </head>
  <body>
    <ix:header>
      <ix:references/>
      <ix:resources>
        <xbrli:context id="FY">
          <xbrli:entity><xbrli:identifier scheme="http://www.sec.gov/CIK">0000123456</xbrli:identifier></xbrli:entity>
          <xbrli:period><xbrli:startDate>2024-01-01</xbrli:startDate><xbrli:endDate>2024-12-31</xbrli:endDate></xbrli:period>
        </xbrli:context>
        <xbrli:unit id="USD"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit>
      </ix:resources>
    </ix:header>

    <h1>ACME Corp FY2024 Disclosure</h1>

    <!-- one disclosure section per surviving finding; each quantified claim is a tagged fact -->
    <p>Net income for the period was
      <ix:nonFraction name="us-gaap:NetIncomeLoss" contextRef="FY" unitRef="USD" decimals="0">5200000</ix:nonFraction>.
    </p>
    <p>Reporting entity:
      <ix:nonNumeric name="dei:EntityRegistrantName" contextRef="FY">ACME Corporation</ix:nonNumeric>.
    </p>

    <!-- References: every unique primary source the disclosure rests on -->
    <h2>References</h2>
    <ol>
      <li><a href="https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&amp;CIK=0000123456">ACME Corp FY2024 Form 10-K</a></li>
    </ol>
  </body>
</html>
```

- Numeric facts use `ix:nonFraction` with `name`, `contextRef`, `unitRef`, and
  `decimals` (or `scale` when the displayed value is scaled).
- Textual facts use `ix:nonNumeric` with `name` and `contextRef`.
- Every `contextRef`/`unitRef` must resolve to a declared `xbrli:context`/`xbrli:unit`.
- The MIF L1 identity lives only in `<head>` metadata (`urn:mif:xbrl:…`), never in a
  visible `ix:nonNumeric`/text node.

Write the document to the resolved output path (default `<topic>-disclosure.xhtml`).

## Phase 3: Verify and report

1. Confirm the output exists and is non-empty (`ls -lh <output>`); report its size and path.
2. Confirm well-formedness — every opened tag closes, the `ix:`/`xbrli:` namespaces are
   declared on the root, and every `contextRef`/`unitRef` resolves.
3. Confirm completeness — every quantified claim across the surviving findings is tagged,
   and the References list has an entry for every unique primary source.
4. Confirm no internal identity leaked into the visible body
   (`grep -E 'urn:mif:(concept|report):|\bf_[a-z]+_[0-9]+\b'` should match nothing in the
   body; the `urn:mif:xbrl:` head identifier is the only permitted MIF id).

## Non-negotiables

- **Sources only.** Build from the findings corpus + primary citations (and a
  `regulatory-disclosure` artifact for ordering, if present). Never from a rendered
  report/blog/book — that is a copy-of-a-copy and is forbidden.
- **Well-formed iXBRL.** Namespaces on the root; contexts and units declared before they
  are referenced; every fact bound to a current-taxonomy concept.
- **No internal identity in the body.** Finding/concept ids, `urn:mif:concept|report:`,
  corpus paths, and `f_<dim>_<n>` handles never render into the visible document; the
  source's MIF identity rides in the XHTML `<head>` metadata.

## Error Handling

- Missing taxonomy concept for a figure: tag as `ix:nonNumeric` under a documented
  extension concept and note it; do not force an ill-fitting standard concept.
- A finding with no quantified figure: render its claim as narrative `ix:nonNumeric`
  (or plain prose if it is not a disclosed fact), never as a fabricated number.
- Output fails well-formedness: surface the exact unbalanced tag or unresolved ref for
  diagnosis.
