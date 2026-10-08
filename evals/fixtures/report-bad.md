---
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:5c433064-3be8-5232-9f82-17d30df7d4dd
conceptType: semantic
namespace: harness/example-topic
title: "Non-conformant report (no verification verdict)"
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
---
This report carries no `extensions.harness.verification` verdict, so it has not
passed the falsification gate and must NOT project to a valid MIF Level-3 finding.
`mif-project.sh` rejects it.
