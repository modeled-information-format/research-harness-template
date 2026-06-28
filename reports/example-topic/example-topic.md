---
'@context': https://mif-spec.dev/schema/context.jsonld
'@type': Concept
'@id': urn:mif:report:harness/example-topic:example-topic
conceptType: semantic
namespace: harness/example-topic
title: 'Example research topic: template engines for a living harness'
created: "2026-06-28T06:30:12Z"
provenance:
  '@type': Provenance
  sourceType: system_generated
  confidence: 0.9
  trustLevel: moderate_confidence
citations:
  - '@type': Citation
    citationType: documentation
    citationRole: background
    title: Cookiecutter documentation
    url: https://cookiecutter.readthedocs.io/
  - '@type': Citation
    citationType: documentation
    citationRole: supports
    title: Copier — Updating a project
    url: https://copier.readthedocs.io/en/stable/updating/
extensions:
  harness:
    dimension: synthesis
    verification:
      verdict: survived
      verdict_basis: Demonstration report synthesized from the bundled sample-session findings, each of which carries a 'survived' verdict; no disconfirming evidence applies to this illustrative topic.
      attempted_at: "2026-06-28T00:00:00Z"
---

This general synthesis covers 3 surviving finding(s) across the research.

## Cookiecutter instantiation is a one-time snapshot with no upstream path

Cookiecutter and bare GitHub template repos generate a project once; there is no supported mechanism to re-apply later template changes. This contrasts with update-propagating engines.

```mermaid
graph TD
  n0["Cookiecutter instantiation is a one-time snapshot with no upstream path"]
  n1["kg-copier-0001"]
  n2["update propagation (Concept)"]
  n3["Cookiecutter (Technology)"]
  n0 -->|contradicts| n1
```

Key entities: Cookiecutter (Technology), update propagation (Concept).

_Dimension: landscape · verification: survived._

Evidence:

- [Cookiecutter documentation](<https://cookiecutter.readthedocs.io/>)

## Copier provides update propagation to instantiated projects

Copier's `copier update` re-applies later template changes to an already-instantiated project via a three-way merge. This is the capability a living template needs.

```mermaid
graph TD
  n0["Copier provides update propagation to instantiated projects"]
  n1["kg-distribution-0003"]
  n2["update propagation (Concept)"]
  n3["Copier (Technology)"]
  n0 -->|supports| n1
```

Key entities: Copier (Technology), update propagation (Concept).

_Dimension: technical · verification: survived._

Evidence:

- [Copier — Updating a project](<https://copier.readthedocs.io/en/stable/updating/>)

## A living template is mandatory for a harness that keeps gaining capability

Because the harness keeps gaining skills, gates, and schema versions, a one-time snapshot freezes every clone at its instantiation date. An update-propagating template engine is therefore the decisive distribution choice.

```mermaid
graph TD
  n0["kg-cookiecutter-0002"]
  n1["kg-copier-0001"]
  n2["A living template is mandatory for a harness that keeps gaining capability"]
  n3["living template (Concept)"]
  n4["update propagation (Concept)"]
  n2 -->|derived-from| n1
  n2 -->|derived-from| n0
```

Key entities: update propagation (Concept), living template (Concept).

_Dimension: trajectory · verification: survived._

Evidence:

- [Copier — Updating a project](<https://copier.readthedocs.io/en/stable/updating/>)

## Sources

- [Cookiecutter documentation](<https://cookiecutter.readthedocs.io/>)
- [Copier — Updating a project](<https://copier.readthedocs.io/en/stable/updating/>)
