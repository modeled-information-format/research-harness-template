---
name: ectd
description: "Package a clinical-submission artifact into the FDA eCTD (electronic Common Technical Document) module structure directly FROM THE SOURCES — a research topic's surviving findings corpus and the primary materials its citations point to. Lays out the eCTD module tree (M1 regional administrative, M2 summaries, M3 quality, M4 nonclinical study reports, M5 clinical study reports) and writes the eCTD XML backbone that indexes the leaf files. NEVER built from a rendered report (that would be a copy-of-a-copy). Optional channel; pure mkdir + XML, no external toolchain. Verify-live eCTD v4.0. Use when the user says 'package as eCTD', 'build the eCTD submission', or 'render to eCTD'."
version: 0.3.0
argument-hint: "<findings-dir> [-o <output-dir>] [<topic-name>]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# eCTD Channel — source-grounded submission packaging

**Non-negotiable: this deliverable is packaged from the SOURCES alone.** The input
is the topic's surviving findings corpus (`reports/<topic>/findings/*.json`) and the
primary materials its citations reference — never a rendered report, blog, or other
channel's output. Packaging an eCTD from a synthesized report would be a
copy-of-a-copy (a simulacrum of the sources); it is forbidden. Every module leaf
traces to a finding, and every claim to that finding's primary-source citation.

This is an **optional** channel. eCTD is an electronic submission *packaging/transport*
format — it does not require an external toolchain; the module tree is `mkdir` and the
backbone is XML written directly. The MIF Level-3 source of truth stays in the generic
`report` channel; this channel is `mif.exempt` because the eCTD container format is
orthogonal to MIF markdown structure.

## Edition currency (verify-live)

Anchor to **FDA eCTD v4.0** (the HL7 RPS-based message format) as the illustrative
example only — never assert it as the current edition from memory. Before packaging,
resolve `ECTD_VERSION` with a best-effort live check, then stamp the resolved value
into the backbone:

```bash
# Best-effort live check against FDA's eCTD technical-specifications page:
# https://www.fda.gov/drugs/electronic-regulatory-submission-and-review/electronic-common-technical-document-ectd
# Read the current specification version there and set it explicitly, e.g.:
ECTD_VERSION="4.0"   # <- replace with the version resolved live; 4.0 is the anchor/fallback
# Offline or lookup unavailable: keep the 4.0 anchor and log that the live check
# could not be completed so the assumed version is auditable.
```

Do not hardcode the version as a settled fact; the `4.0` above is the fallback anchor,
not an assertion that it is current.

## eCTD module map

The eCTD organizes a submission into five modules. Each becomes a directory under the
submission sequence:

- **m1** — Regional administrative information (region-specific; FDA forms, cover letter, administrative metadata).
- **m2** — Common Technical Document summaries (quality overall summary, nonclinical and clinical overviews/summaries).
- **m3** — Quality (chemistry, manufacturing, and controls — CMC).
- **m4** — Nonclinical study reports (pharmacology, pharmacokinetics, toxicology).
- **m5** — Clinical study reports (clinical efficacy and safety).

## Phase 0: Load the sources

Resolve `<findings-dir>` to the topic's findings directory. Load **every surviving
finding** (verdict ≠ `falsified`):

```bash
jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
```

Each finding carries: `title` (the verified claim), `content`, `citations[]` (its
**primary sources** — title + url + type + role), `entities[]`, and
`extensions.harness.dimension`/`verification.verdict`. These are the sources. Read no
rendered report or artifact. Default output is `<findings-dir>/../ectd/`.

## Phase 1: Build the module tree FROM the sources

Create the eCTD submission sequence directory (a zero-padded sequence, e.g. `0000`)
and the five module folders under it:

```bash
OUT="<output-dir>"; SEQ="$OUT/0000"
mkdir -p "$SEQ/m1" "$SEQ/m2" "$SEQ/m3" "$SEQ/m4" "$SEQ/m5"
```

For each module, author a module summary leaf grounded in the surviving findings —
each summary maps the findings (and their primary-source citations) relevant to that
module's content, with each claim linked to its public source (`[title](url)`). A
finding's `extensions.harness.dimension` is a hint for which module it informs; when
unclear, place quality/CMC-style claims in m3, nonclinical in m4, clinical in m5, and
cross-cutting summaries in m2. m1 carries the regional administrative metadata (topic,
namespace, date, resolved eCTD version).

Write one summary per module, e.g. `$SEQ/m2/m2-summary.md`, `$SEQ/m3/m3-quality.md`,
`$SEQ/m4/m4-nonclinical.md`, `$SEQ/m5/m5-clinical.md`, and `$SEQ/m1/m1-admin.md`.

Constraints: every leaf traces to a finding and its primary source; invent nothing not
in the findings. The leaves carry **no internal-research identity** — emit finding
claims + public citations only, never finding/concept `@id`s, `urn:mif:` ids,
`reports/<slug>/` paths, or `f_<dim>_<n>` handles. The submission's MIF identity rides
in the backbone metadata (Phase 2), not in the leaf bodies.

## Phase 2: Write the eCTD XML backbone

Write the eCTD backbone (`ectd-backbone.xml`) at the sequence root. The backbone is
the index that references every module leaf, declares the eCTD version, and carries the
submission's MIF Level-1 identity as a metadata attribute. Reference each `m1`–`m5`
leaf with its relative path and a module/section label:

```bash
cat > "$SEQ/ectd-backbone.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<ectd:backbone xmlns:ectd="urn:hl7-org:v3" ectd-version="${ECTD_VERSION}"
               mif-identity="urn:mif:ectd:<namespace>:<slug>">
  <module id="m1" title="Regional Administrative Information">
    <leaf href="m1/m1-admin.md"/>
  </module>
  <module id="m2" title="CTD Summaries">
    <leaf href="m2/m2-summary.md"/>
  </module>
  <module id="m3" title="Quality">
    <leaf href="m3/m3-quality.md"/>
  </module>
  <module id="m4" title="Nonclinical Study Reports">
    <leaf href="m4/m4-nonclinical.md"/>
  </module>
  <module id="m5" title="Clinical Study Reports">
    <leaf href="m5/m5-clinical.md"/>
  </module>
</ectd:backbone>
XML
```

The `ectd-version` attribute records the resolved (verify-live) eCTD version; the
`mif-identity` attribute gives the package a traceable MIF Level-1 identity. The eCTD
container format itself is exempt from the L3 I/O conformance gate.

## Phase 3: Verify and report

1. Confirm the five module folders exist (`ls "$SEQ"`) and each holds its summary leaf.
2. Confirm `ectd-backbone.xml` exists, is non-empty, references all five module leaves,
   and declares the resolved eCTD version.
3. Confirm completeness: every surviving finding is reflected in at least one module
   summary, and every primary source is cited.
4. Report the submission path, the sequence number, and the resolved eCTD version.

## Non-negotiables

- **Sources only.** Package from the findings corpus + primary citations. Never from a
  rendered report/blog/book/artifact — that is a copy-of-a-copy and is forbidden.
- **Complete module tree.** All five modules (m1–m5) plus the XML backbone are written;
  no module silently omitted.
- **No internal identity in the leaves.** Finding/concept ids, `urn:mif:`, corpus
  paths, and `f_<dim>_<n>` handles never render into the module leaves; the package's
  MIF identity rides in the backbone metadata.
- **Verify-live edition.** Resolve the current eCTD version (anchor: v4.0) before
  packaging; never assume it from memory.

## Error Handling

- Empty findings set: warn that there are no surviving findings to package and stop.
- A module with no relevant findings: write a stub summary noting the module is empty
  for this submission rather than omitting the folder — the eCTD tree stays complete.
- Backbone write failure: surface the full error for diagnosis.
