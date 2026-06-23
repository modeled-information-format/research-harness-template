---
name: publish-report
description: "Render surviving research findings into the canonical MIF Level-3 markdown report — the harness's source of truth (reports/<topic>/<slug>.md), held to the same bar as a finding and graded by the falsification gate. A first-class harness output (not a pack), never exempt. Use this skill when the user wants the authoritative MIF report, the L3 report of record, or to emit the canonical report from the corpus. Triggers on 'publish report', 'generate the MIF report', 'render the report of record', 'emit the canonical report', 'L3 report from findings'."
version: 0.1.1
argument-hint: "[--topic <id>] [--genre <genre>] [--out <path.md>]"
allowed-tools: Read, Bash, Edit, Glob, Grep
---

# publish-report — research → canonical MIF Level-3 report

The generic `report` channel is the **canonical MIF Level-3 source of truth**
(SPEC §10): a basic markdown report (`reports/<topic>/<slug>.md`) with authoritative
YAML frontmatter (the MIF concept) over a Markdown body. Unlike the `blog` and
`book` projections — which are MIF-exempt published prose — the report is **never
exempt**: it is held to the **same L3 bar as a finding** and must carry a real,
non-falsified `extensions.harness.verification` verdict before it ships.

## Pipeline

1. **Resolve the finding set.** Default to the topic's findings dir
   (`reports/<topic>/findings/`). Only **surviving** findings (verdict ≠
   `falsified`) are eligible.

2. **Synthesize the artifact** (full MIF citations carried through):

   ```bash
   scripts/synthesize-artifact.sh reports/<topic>/findings <genre> reports/<topic>/artifact.json
   ```

3. **Obtain a REAL verdict — never author it by hand.** Run the same adversarial
   falsification gate a finding goes through over the synthesised report's claims,
   and extract the verdict block it writes:

   ```bash
   # report-finding.json = a finding-shaped projection of the report's central
   # claims (its citations, no verification block yet).
   scripts/falsify.sh reports/<topic>/report-finding.json <evidence> \
     > reports/<topic>/report-finding.falsified.json
   jq '.extensions.harness.verification' reports/<topic>/report-finding.falsified.json \
     > reports/<topic>/report.verification.json
   ```

   A `falsified` verdict means the report is quarantined and NOT shipped.

4. **Render the report** (write-then-validated; fails closed if it does not project
   to a valid L3 finding):

   ```bash
   scripts/render-artifact.sh reports/<topic>/artifact.json report \
     reports/<topic>/<slug>.md reports/<topic>/report.verification.json
   ```

5. **Confirm L3.** `scripts/render-artifact.sh` already validates via
   `scripts/mif-project.sh`; before reporting done, re-run it to be sure:

   ```bash
   scripts/mif-project.sh reports/<topic>/<slug>.md
   ```

## Non-negotiables

- **Never hand-author the verification verdict.** It must come from a real
  falsification pass, exactly as for a finding. The gate enforces that a
  well-formed, non-`falsified` verdict is *present*; that it was honestly earned
  rests on you.
- **Never ship a falsified or quarantined report.** `mif-project.sh` and the
  citation-integrity gate reject a `falsified` verdict.
- **The report is the MIF source of truth, not exempt.** The title lives in the
  frontmatter; the body carries no top-level heading (it would trip MD025 and
  duplicate the title). To change content, change the findings or the synthesis,
  not the rendered Markdown in place.
- **Genres are L3 here.** A genre shapes the report's content; the report is still
  rendered through this channel and held to L3.
