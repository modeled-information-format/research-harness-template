---
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:614d6b22-4f8c-5442-9ca4-ae946335bf5f
conceptType: semantic
namespace: harness/example-topic
title: "Falsified report (must not ship)"
created: "2026-06-19T12:00:00Z"
provenance:
  "@type": Provenance
  sourceType: system_generated
citations:
  - "@type": Citation
    citationType: documentation
    citationRole: supports
    title: "Copier — Updating a project"
    url: https://copier.readthedocs.io/en/stable/updating/
extensions:
  harness:
    dimension: synthesis
    verification:
      verdict: falsified
      verdict_basis: "Disconfirming search refuted the report's central claim."
      attempted_at: "2026-06-19T12:30:00Z"
---
This report carries a `falsified` verdict. It is schema-valid but the
citation-integrity gate (via `mif-project.sh`) must reject it: a falsified report
must never ship.
