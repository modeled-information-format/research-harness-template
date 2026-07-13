---
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-topic:sample-report
conceptType: semantic
namespace: harness/example-topic
title: "Sample synthesis report"
created: "2026-06-19T12:00:00Z"
modified: '2026-07-13T14:11:01.729Z'
temporal:
  "@type": TemporalMetadata
  validFrom: "2026-06-19T12:00:00Z"
provenance:
  '@type': Provenance
  sourceType: system_generated
  confidence: 0.9
  trustLevel: user_stated
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:878c53f7-09b4-4f64-bb13-e210d7c2f073
    '@type': prov:Activity
  agentVersion: 2.1.207
citations:
  - "@type": Citation
    citationType: documentation
    citationRole: supports
    title: "Copier — Updating a project"
    url: https://copier.readthedocs.io/en/stable/updating/
    accessed: "2026-06-19"
extensions:
  harness:
    dimension: synthesis
    verification:
      verdict: survived
      verdict_basis: "Disconfirming search over the report's synthesised claims found no credible refutation of the surviving findings."
      attempted_at: "2026-06-19T12:30:00Z"
---
This is the canonical MIF Level-3 markdown report sample: authoritative YAML
frontmatter (the MIF concept) over a clean Markdown body. The title lives in the
frontmatter, so the body carries no top-level heading. The frontmatter projects to
a JSON-LD finding that validates against `schemas/findings.schema.json`, and the
body becomes the MIF `content`.

## Sources

- [Copier — Updating a project](https://copier.readthedocs.io/en/stable/updating/)
