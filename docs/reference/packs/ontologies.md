---
diataxis_type: reference
---

# Ontology packs

Ontology packs extend the MIF entity vocabulary for a specific domain. Each pack
supplies a `*.ontology.yaml` that declares namespaces, entity types, relationships,
and discovery patterns. Binding an ontology pack lets the research engine recognize,
classify, and relate domain entities found in sources.

Ontology packs have no external dependencies and no SKILL.md — they are data packs,
not skill packs.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

## Enabling and binding an ontology

Ontology packs use a **different control surface** from the skill/channel/genre
plugin packs. They are declared in `harness.config.json` `ontologies[]` (an `id`
plus an `enabled` flag), not in `packs[]`, so `scripts/pack-toggle.sh` does not
apply to them. Enabling an ontology is two steps:

1. Set its `enabled` flag to `true` in `ontologies[]` (the per-pack "Enable"
   command below does exactly this for that pack's `id`).
2. Bind the enabled ontology to a research topic with the `/ontology-review`
   command, whose deterministic engine is `scripts/resolve-ontology.sh`. Binding
   is what lets findings in that topic resolve to the ontology's entity types.

The `resolve-ontology.sh` engine requires `yq`, `jq`, and `ajv` (see
[dependencies](../dependencies.md)).

---

## backstage

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for the Backstage.io software catalog model. Modeled
from the Backstage System Model, Descriptor Format, Well-Known Annotations, and
Well-Known Relations specifications.

### Domain

Developer portals and internal service catalogs built on Backstage.io.

### Entities, relationships, and traits

**Entity types:** component (service / website / library / documentation / template),
api (openapi / asyncapi / graphql / grpc / trpc), resource (database / s3-bucket /
cluster / queue / cache / other), system, domain, group, user, location, template,
annotation, catalog-refresh, techdocs-build, scaffolder-task.

**Key relationships:** `owned_by`, `part_of`, `has_part`, `member_of`, `has_member`,
`parent_of`, `child_of`, `provides_api`, `consumes_api`, `depends_on`,
`dependency_of`.

**Traits applied:** `lifecycle`, `owned`, `tagged`, `documented`, `versioned`,
`contactable`.

**Discovery patterns:** recognizes catalog-info.yaml files, openapi.yaml, schema.graphql,
mkdocs.yml; detects component/api/resource/system/domain/group/template mentions
in content.

### When to bind

Bind `backstage` when researching developer portal adoption, internal platform
engineering, service catalog design, or Backstage plugin ecosystems.

### Enable

```sh
jq '(.ontologies[] | select(.id=="backstage") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## biology-research-lab

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary covering the full lifecycle of an academic biology
research lab: personnel, grants, experiments, samples, data, publications, and
compliance (IRB / IACUC / IBC). Sources include NIH, NSF, OHRP, OLAW, FAIR Data
Principles, and the CRediT Contributor Roles Taxonomy.

### Domain

Academic biology research labs and their operational, funding, and compliance contexts.

### Entities, relationships, and traits

**Entity types:** principal-investigator, lab-member (postdoc / graduate-student /
technician / lab-manager / other), collaborator, grant, grant-submission, grant-report,
project, protocol (cell-culture / molecular-biology / imaging / animal / computational /
other), experiment, sample (cell-line / tissue / dna / rna / protein / plasmid /
organism / other), reagent, equipment (microscope / centrifuge / sequencer /
flow-cytometer / other), dataset, publication, manuscript-submission, irb-protocol,
iacuc-protocol, ibc-protocol, training-record.

**Key relationships:** `leads`, `funded_by`, `uses_protocol`, `produces`, `covered_by`,
`collaborates_with`, `cites_grant`, `uses_sample`, `uses_equipment`.

**Traits applied:** `lifecycle`, `contactable`, `certified`, `renewable`, `auditable`,
`inventoried`, `maintainable`, `versioned`, `owned`, `reviewed`, `scheduled`,
`measured`, `budgeted`.

**Discovery patterns:** recognizes NIH grant mechanism codes (R01, R21, K99, F31,
T32, U01), ORCID identifiers, experimental keywords (PCR, qPCR, Western, assay),
compliance keywords (IRB, IACUC, IBC, BSL), and publication identifiers (DOI, PMID).

### When to bind

Bind `biology-research-lab` when researching academic research lab operations, life
sciences grant landscapes, laboratory compliance requirements, or research data
management.

### Enable

```sh
jq '(.ontologies[] | select(.id=="biology-research-lab") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## csi-5w1h

**Version:** 1.0.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for classifying customer technical support tickets using
the 5W1H framework (Who / What / When / Where / Why / How). Derived from data-driven
analysis of 78,405 HMH Customer Support (CSI) Jira tickets spanning January 2014
through February 2026, processed across 55 parallel analyst agents.

### Domain

Customer technical support ticket classification for K-12 EdTech platforms
(HMH Ed, ThinkCentral, my.hrw.com).

### Entities, relationships, and traits

**Namespaces (semantic):** tickets (symptom taxonomies, issue type hierarchies),
products (Core Curriculum / Intervention / Supplemental / Platform), platforms
(HMH Ed, ThinkCentral, my.hrw.com), organizations (teams, districts, schools).

**Analytical dimensions:** 11 dimensions covering symptom taxonomy, root cause
analysis, resolution pathways, platform mapping, team assignments, temporal patterns,
and impact assessment.

**Discovery patterns:** recognizes Jira ticket references, HMH product names, support
platform identifiers, and 5W1H classification markers.

### When to bind

Bind `csi-5w1h` when researching customer support operations, EdTech platform
reliability, support ticket taxonomy design, or historical support pattern analysis
in K-12 educational technology.

### Enable

```sh
jq '(.ontologies[] | select(.id=="csi-5w1h") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## data-engineering

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for the data engineering domain: data contracts, data
products, governance policies, data quality, storage architectures, and pipeline
patterns.

### Domain

Data engineering teams, data platform engineering, and modern data infrastructure.

### Entities, relationships, and traits

**Namespaces (semantic):** contracts (data contracts and product interface agreements),
governance (policies, controls, stewardship), storage (storage and scaling
architectures). **Namespaces (procedural):** pipelines (pipeline and data-movement
patterns).

**Entity types include:** data-contract (enforceable schema + semantics + SLA
agreements between producers and consumers).

**Traits applied:** `cited`.

**Discovery patterns:** recognizes data contract mentions, governance terminology,
pipeline and storage architecture patterns.

### When to bind

Bind `data-engineering` when researching data platform architecture, data contract
adoption, data governance frameworks, or modern data engineering tooling and practices.

### Enable

```sh
jq '(.ontologies[] | select(.id=="data-engineering") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## k12-educational-publishing

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for K-12 educational publishers covering curriculum,
textbooks, digital content, and state adoption processes. Modeled after legacy
publishers' operational structures (sources: EdReports.org, NASBE, California
Department of Education, Common Core State Standards Initiative, ISTE Standards,
Association of American Publishers).

### Domain

K-12 educational content publishing, curriculum programs, and state adoption
processes.

### Entities, relationships, and traits

**Namespaces (semantic):** titles (published titles, editions, ISBNs), programs
(curriculum programs, series, bundles), content (learning objects, assessments,
standards alignments).

**Discovery patterns:** recognizes ISBN identifiers, grade-level and standards
references, curriculum program names, state adoption terminology.

### When to bind

Bind `k12-educational-publishing` when researching the K-12 educational publishing
market, curriculum adoption cycles, EdTech content strategy, or state standards
alignment processes.

### Enable

```sh
jq '(.ontologies[] | select(.id=="k12-educational-publishing") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## regenerative-agriculture

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for regenerative farm business operations: land, livestock,
supply chain, carbon markets, and certification bodies. Sources include the Rodale
Institute ROC Standards, Soil & Climate Initiative Verification Framework v3.0 (2025),
USDA NRCS Soil Health Principles, Rainforest Alliance Regenerative Agriculture Standard
(2025), and FAO Agroecology Knowledge Hub.

### Domain

Regenerative farm business operations — farm records, supply chain, carbon credit
activities, and certification tracking (not research observations).

### Entities, relationships, and traits

**Namespaces (semantic):** land (land parcels, fields, soil profiles), livestock
(animals, herds, breeding records). Additional namespaces cover supply chain, carbon
markets, certifications, and farm financials.

**Traits applied:** `lifecycle`, `owned`, `renewable`, `auditable`, `inventoried`.

**Discovery patterns:** recognizes farm operation terminology, soil health references,
certification body names (ROC, Rainforest Alliance), carbon market identifiers.

### When to bind

Bind `regenerative-agriculture` when researching farm business operations, regenerative
agriculture supply chains, carbon credit markets, or agricultural certification programs.
For research-oriented findings about farming practices rather than farm records, use
`regenerative-agriculture-research` instead.

### Enable

```sh
jq '(.ontologies[] | select(.id=="regenerative-agriculture") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## regenerative-agriculture-research

**Version:** 0.1.0 | **Kind:** ontology

### Purpose

Provides a research-oriented entity vocabulary for regenerative agriculture findings.
Covers research observations about farming practices, infrastructure, funding, and
technology — not farm records. Includes cross-cutting technology and security research
types so infrastructure- and security-flavored farm topics resolve correctly.

### Domain

Research findings about regenerative agriculture practices: husbandry, agronomy, farm
infrastructure, funding programs, and farm technology.

### Entities, relationships, and traits

**Namespaces (semantic):** husbandry (animal husbandry and livestock care knowledge),
agronomy (grazing, soil, crop, and pasture practices), infrastructure (fencing,
irrigation, IoT, networks), funding (grants, cost-share, and funding programs).

**Entity types include:** husbandry-practice (animal-husbandry or livestock-care
research observations such as lambing, newborn care, health management).

**Traits applied:** `cited`.

**Discovery patterns:** recognizes husbandry and agronomy terminology, farm
infrastructure keywords, grant and funding program identifiers, IoT and technology
references in a farm context.

### When to bind

Bind `regenerative-agriculture-research` when researching regenerative farming
practices, husbandry techniques, soil science, agronomy research, or agricultural
grant programs. For farm business records and supply chain tracking, use
`regenerative-agriculture` instead.

### Enable

```sh
jq '(.ontologies[] | select(.id=="regenerative-agriculture-research") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

---

## software-engineering

**Version:** 0.3.0 | **Kind:** ontology

### Purpose

Provides an entity vocabulary for software engineering teams: components, architecture,
dependencies, and deployment processes.

### Domain

Software development teams, software architecture research, and engineering process
analysis.

### Entities, relationships, and traits

**Namespaces (semantic):** architecture (system architecture and component designs),
components (software components, modules, services), dependencies (third-party libraries,
packages, integrations). **Namespaces (procedural):** deployments (deployment
procedures, release processes).

**Entity types include:** component (a software component, module, or service with
`name` and `responsibility` required fields).

**Traits applied:** `versioned`, `documented`.

**Discovery patterns:** recognizes component, service, module, architecture, and
dependency terminology in research sources.

### When to bind

Bind `software-engineering` when researching software architecture patterns,
engineering team practices, technology stack decisions, dependency management, or
software delivery processes.

### Enable

```sh
jq '(.ontologies[] | select(.id=="software-engineering") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```
