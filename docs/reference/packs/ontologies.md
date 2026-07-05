---
id: reference-packs-ontologies
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-05T10:10:09-04:00'
namespace: docs/reference/packs
tags:
  - documentation
  - reference
title: "Ontology packs"
diataxis_type: reference
---

# Ontology packs

Ontology packs extend the MIF entity vocabulary for a specific domain. Each pack
supplies a `*.ontology.yaml` that declares namespaces, entity types, relationships,
and discovery patterns. Binding an ontology pack lets the research engine recognize,
classify, and relate domain entities found in sources.

Ontology packs have no external dependencies and no SKILL.md — they are data packs,
not skill packs.

The vocabulary is layered in three tiers: the domain-neutral **generic core**
(`mif-base` / `mif-generic` / `shared-traits`, the MIF-compliant always-on layer) →
[`engineering-base`](#engineering-base) (shared engineering supertypes — MIF-compliant,
opt-in via `extends`, never bound directly) → the bindable **domain packs** below.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

## Enabling and binding an ontology

Ontology packs use a **different control surface** from the skill/channel/genre
plugin packs. They are declared in `harness.config.json` `ontologies[]` (an `id`
plus an `enabled` flag), not in `packs[]`, so `scripts/pack-toggle.sh` does not
apply to them. Enabling an ontology is two steps:

1. Set its `enabled` flag to `true` in `ontologies[]` (the per-pack "Enable"
   command below does exactly this for that pack's `id`).
2. Bind the enabled ontology to a research topic with the `/ontology-review`
   command, whose deterministic engine is `scripts/ontology-review.sh`. Binding
   is what lets findings in that topic resolve to the ontology's entity types;
   per-finding classification is handled by `scripts/resolve-ontology.sh`.

`resolve-ontology.sh` is a thin wrapper (ADR-0016) that execs the `mif-rh-cli`
engine, hard-required (see [dependencies](../dependencies.md)).

---

## biology-research-lab

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/biology-research-lab/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/biology-research-lab)

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

### Constraints

- Opt-in only; cataloged `core=false` — topics must explicitly enable and bind; never auto-applied to non-biology-lab topics.
- Extends `mif-base v1.0.0` and `shared-traits v1.0.0`; binding is fail-closed — `resolve-ontology.sh` and `validate-concordance.sh` abort the entire corpus if either `extends` target is missing or mistyped.
- Scoped to academic biology research labs; entity types do not apply to engineering, legal, or market-research topics.
- Compliance sub-types (IRB / IACUC / IBC) are domain-specific and resolve only within bound biology-lab topics.

### Goals

- Supplies entity vocabulary covering the full biology-lab lifecycle: personnel (PI, postdoc, graduate-student, technician, lab-manager), grants, experiments, samples, reagents, equipment, publications, and compliance protocols.
- Enables recognition of NIH grant mechanism codes (R01, R21, K99, F31, T32, U01), ORCID identifiers, assay keywords, compliance identifiers (IRB, IACUC, IBC, BSL), and publication identifiers (DOI, PMID) in research sources.
- Typed findings validate fail-closed against the MIF schema on binding, providing provenance and completeness guarantees.
- Supports compliance lifecycle tracking and research data management (FAIR principles, CRediT contributor roles) within bound topics.

---

## cardiology

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/cardiology/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/cardiology)

### Purpose

Provides an entity vocabulary for cardiovascular disease classification, structured
cardiac diagnostic studies, and functional-status assessment. Covers the WHO ICD-11
Chapter 11 circulatory-disease blocks (hypertensive, ischemic, coronary, pulmonary,
pericardial, valve, myocardial, arrhythmia, arterial, venous, and lymphatic-vascular
disease), plus LOINC/ACC-AHA-ASE-grounded echocardiography and ECG study bundles,
invasive catheterization studies, standardized clinical-trial endpoint events, and
the NYHA functional-class scale. It `extends` [`clinical-health-base`](#clinical-health-base)
directly, inheriting the shared FHIR-shaped and ICD-11-shaped clinical primitives its
own types specialize.

### Domain

Cardiovascular disease classification, cardiac diagnostic studies, and cardiac
functional-status assessment.

### Entities, relationships, and traits

**Namespaces (semantic):** cardiology-disorders (circulatory disease classification,
ICD-11 Chapter 11), cardiology-functional-status (cardiac functional-status
classification scales). **Namespaces (episodic):** cardiology-studies (structured
cardiac diagnostic studies and clinical events).

**Entity types:** hypertensive-disease, ischemic-heart-disease, coronary-artery-disease,
pulmonary-heart-disease, pericardial-disease, endocarditis, heart-valve-disease,
cardiomyopathy, cardiac-arrhythmia, heart-failure, arterial-disease, venous-disease,
lymphatic-vascular-disorder (13 ICD-11 Chapter 11 circulatory-disease classification
entries), echocardiography-study, ecg-finding, cardiac-catheterization-study
(structured diagnostic study bundles), cardiovascular-endpoint-event (a standardized
clinical-trial endpoint event), nyha-functional-class (NYHA I-IV functional capacity),
cardiovascular-clinical-finding (a SNOMED CT point-in-time clinical finding).

**Key relationships:** `occurs_within` (a cardiac-catheterization-study occurs within
a clinical-encounter).

**Discovery patterns:** recognizes hypertension/ischemic-heart-disease/coronary-artery-
disease/arrhythmia/heart-failure/cardiomyopathy terminology, echocardiography and
ejection-fraction language, ECG/EKG terms (QRS, QT interval, PR interval), cardiac
catheterization and coronary angiography/PCI mentions, and NYHA functional-class
references.

### When to bind

Bind `cardiology` when researching cardiovascular disease classification, cardiac
diagnostic studies (echocardiography, ECG, catheterization), cardiovascular clinical-
trial endpoints, or cardiac functional-status assessment.

### Enable

```sh
jq '(.ontologies[] | select(.id=="cardiology") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-cardiology topics.
- Extends `clinical-health-base` directly, which itself extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Scoped to cardiovascular disease classification and cardiac studies; entity types do not apply to general health, fitness, or non-clinical engineering topics.

### Goals

- Provides vocabulary for cardiovascular disease classification: 13 WHO ICD-11 Chapter 11 circulatory-disease blocks from hypertensive disease through lymphatic-vascular disorders.
- Enables recognition of structured cardiac diagnostic studies (echocardiography, 12-lead ECG, cardiac catheterization) and standardized cardiovascular clinical-trial endpoint events.
- Resolves shared FHIR-shaped clinical primitives (clinical-observation, clinical-encounter, diagnostic-classification-entry) transitively via `clinical-health-base` without re-declaration.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## clinical-health-base

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/clinical-health-base/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/clinical-health-base)

### Purpose

A MIF-compliant intermediate layer between the domain-neutral generic core and the
clinical DOMAIN packs (cardiology, health, fitness). It owns the entity-type shapes
that recurred identically across all three packs' independent research passes: the
FHIR Patient/Encounter/Observation shapes and the ICD-11 stem/extension-code shape,
so the domains inherit them instead of each re-declaring its own copy. It `extends`
`research` rather than `mif-base`/`shared-traits` directly, since its descendants
need to subtype `research`'s own `research-procedure` and `observation` generic
shapes, which are not reachable through the generic core alone.

### Domain

Shared clinical vocabulary — patient/subject records, clinical encounters,
observations, and diagnostic classification entries.

### Entities, relationships, and traits

**Namespaces (semantic):** clinical-records (clinical record subjects and diagnostic
classification shapes). **Namespaces (episodic):** clinical-events (clinical
encounters and observations).

**Entity types:** clinical-record-subject (the FHIR Patient-shaped subject-of-record),
clinical-encounter (a FHIR Encounter-shaped time-bound clinical interaction),
clinical-observation (a FHIR Observation-shaped measurement-or-assertion primitive —
the strongest cross-pack convergence point in the clinical domain), diagnostic-
classification-entry (a WHO ICD-11 stem/extension-code classification entry).

**Discovery patterns:** disabled at this layer (`discovery.enabled: false`) — this is
a base layer, not directly instantiated by findings; the patterns declared here
(FHIR Patient/Encounter/Observation and ICD-11 diagnosis-code language) are inactive
and only its leaf-pack specializations (`cardiology`, `fitness`, `health`) discover
from source text.

### When to bind

Bind `clinical-health-base` directly only if a topic needs its FHIR-shaped subject,
encounter, and observation primitives, or its ICD-11 diagnostic-classification-entry
shape, without any leaf-pack specialization. In practice it is more often resolved
transitively by binding `cardiology`, `fitness`, or `health` instead, whose `extends`
chain reaches here.

### Enable

```sh
jq '(.ontologies[] | select(.id=="clinical-health-base") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-clinical topics.
- Extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Discovery is disabled at this layer; findings are typed at the `cardiology`/`fitness`/`health` leaf-pack level, not here.

### Goals

- Supplies the shared clinical entity-type shapes (FHIR Patient/Encounter/Observation, ICD-11 stem/extension-code) that `cardiology`, `fitness`, and `health` each independently converged on.
- Eliminates redundant supertype declarations across the three clinical leaf packs; each declares only its domain-specific types and resolves supertypes via the `extends` chain.
- Enables cross-pack subtype substitution: leaf-pack types (e.g. cardiology's `echocardiography-study`, fitness's Open mHealth types, health's `fhir-observation`) are all `subtype_of` `clinical-observation`.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## cosmology

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/cosmology/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/cosmology)

### Purpose

Provides an entity vocabulary for astronomical object and data-product classification
(IVOA vocabularies), IAU/CDS celestial-object nomenclature, and cosmological theory and
observation. Covers IVOA object-type, product-type, reference-frame, messenger, facility,
and processing-level vocabularies, IAU-designated quantities such as the Hubble-Lemaitre
expansion-rate relation, PACS-classified cosmological theory models, large-scale
structure, and galaxy-evolution processes, and background-radiation observations. It
`extends` [`physical-science-base`](#physical-science-base) directly, inheriting the
shared PACS-classification and physical-quantity primitives its own types specialize.

### Domain

Astronomical object/data classification, cosmological theory, and cosmological
observation.

### Entities, relationships, and traits

**Namespaces (semantic):** cosmology-objects (astronomical object and data-product
classification, IVOA), cosmology-theory (cosmological theory and process models),
cosmology-parameters (observational cosmology parameters), cosmology-structure
(large-scale structure and galaxy evolution classification). **Namespaces (episodic):**
cosmology-observations (background-radiation and other cosmological observations).

**Entity types:** astronomical-object-type, astronomical-data-product, cataloged-
object-designation, astronomical-reference-frame, astronomical-messenger-type,
astronomical-facility, data-processing-level (IVOA/IAU-CDS vocabulary entries),
hubble-lemaitre-parameter (the IAU-designated expansion-rate relation),
astrophysical-process-concept (a UAT top-level astrophysical-process concept),
cosmology-theory-model, large-scale-structure, galaxy-evolution-process (PACS-
classified theory and structure entries), observational-cosmology-parameter,
cosmic-background-radiation (named physical-quantity measurements).

**Discovery patterns:** recognizes dark-energy/dark-matter/cosmological-constant/
inflationary-universe language, Hubble constant/Hubble-Lemaitre/expansion-rate
terminology, cosmic microwave background/CMB/background-radiation mentions, galaxy
cluster/supercluster/large-scale-structure/cosmic-web terms, and quasar/AGN/blazar/
Seyfert-galaxy references.

### When to bind

Bind `cosmology` when researching astronomical object and data classification,
cosmological theory models, observational cosmology parameters, large-scale structure
and galaxy evolution, or cosmic background-radiation observations.

### Enable

```sh
jq '(.ontologies[] | select(.id=="cosmology") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-cosmology topics.
- Extends `physical-science-base` directly, which itself extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Scoped to astronomical/cosmological classification and observation; entity types do not apply to plasma-physics, clinical, or engineering topics.

### Goals

- Provides vocabulary for astronomical object/data classification: IVOA object-type, product-type, reference-frame, messenger, facility, and processing-level vocabularies, plus IAU/CDS celestial-object designations.
- Enables recognition of cosmological theory and structure language (dark energy, dark matter, inflationary universe, large-scale structure, galaxy evolution) and background-radiation observations.
- Resolves shared PACS-classification and physical-quantity supertypes transitively via `physical-science-base` without re-declaration.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## data-engineering

**Version:** 0.2.0 | **Kind:** ontology

**Source:** [`packs/ontologies/data-engineering/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/data-engineering)

### Purpose

Provides an entity vocabulary for the data engineering domain: data contracts, data
products, governance policies, data quality, storage architectures, and pipeline
patterns. It `extends` [`engineering-base`](#engineering-base), inheriting the shared
engineering supertypes and keeping only its data-specific types.

### Domain

Data engineering teams, data platform engineering, and modern data infrastructure.

### Entities, relationships, and traits

**Namespaces (semantic):** contracts (data contracts and product interface agreements),
governance (policies, controls, stewardship), storage (storage and scaling
architectures). **Namespaces (procedural):** pipelines (pipeline and data-movement
patterns).

**Entity types:** data-contract (enforceable schema + semantics + SLA agreements between
producers and consumers), data-product, data-governance-policy, data-quality-rule,
storage-architecture, pipeline-pattern, data-platform.

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

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-data-engineering topics.
- Extends `engineering-base`, which itself extends `mif-base` and `shared-traits`; `resolve-ontology.sh` walks the full chain fail-closed — a missing `engineering-base` target aborts corpus resolution.
- Scoped strictly to data-specific entity types; version 0.2.0 is a clean break with no back-compat aliases; `technology` is inherited from `mif-generic`, security types from `software-security`, and regulation from `regulatory-legal`.

### Goals

- Provides vocabulary for data engineering: data contracts, data products, governance policies, data quality rules, storage architectures, pipeline patterns, and data platforms.
- Resolves shared engineering supertypes (component, architectural-decision, design-pattern, delivery-metric, engineering-practice, process-discipline) transitively via `engineering-base` without re-declaration.
- Enables recognition of data contract definitions, governance terminology, and pipeline/storage architecture patterns in research sources.
- Typed findings validate fail-closed against MIF schema on binding.

---

## engineering-base

**Version:** 0.1.0 | **Kind:** ontology (shared layer — not directly bindable)

**Source:** [`schemas/ontologies/engineering-base/`](https://github.com/modeled-information-format/research-harness-template/tree/main/schemas/ontologies/engineering-base)

### Purpose

A MIF-compliant **intermediate layer** between the domain-neutral generic core
(`mif-base` / `mif-generic` / `shared-traits`) and the engineering DOMAIN packs. It
declares the supertypes that recur across every engineering domain so the domains
inherit them instead of each re-declaring its own copy. It is a layer, not a bindable
domain pack: topics do not bind `engineering-base` directly — they bind a descendant
(`software-engineering`, `data-engineering`, `software-security`), whose `extends` chain
reaches here.

### Domain

Shared engineering vocabulary — architecture, components, patterns, decisions, delivery
metrics, practices, and disciplines.

### Entities, relationships, and traits

**Entity types:** component, architectural-decision, design-pattern, delivery-metric,
engineering-practice, process-discipline, plus the cross-cutting universals control,
artifact, policy, provenance (recurring across security, data, and software — domain
packs specialize them via `subtype_of`, e.g. software-security
`security-control` is `subtype_of: [control]` — a subtype is substitutable for its
supertype at a relationship endpoint, enforced by the concordance validator and
`gate_m22`).

**Relationships:** `depends_on`, `implements`, `governs` (control/policy →
component/artifact), `attests` (provenance → artifact), `derived_from` (artifact lineage).

**Traits applied:** `versioned`, `documented`, `dated`, `cited`.

**Discovery patterns:** recognizes named design / architectural patterns (Factory,
Singleton, Observer, Repository, Strategy, Decorator, CQRS, Event Sourcing, Saga).

### Constraints

- Not directly bindable; cataloged `core=false` — topics bind a descendant pack (`software-engineering`, `data-engineering`, or `software-security`), never this layer directly.
- Resolved transitively only: `resolve-ontology.sh` walks the `extends` chain from a bound descendant; this layer is never itself the binding target.
- Extends `mif-base` and `shared-traits`; the full chain is fail-closed — a missing or mistyped `extends` target in any descendant pack aborts corpus resolution.

### Goals

- Provides the shared engineering supertypes inherited by all engineering domain packs: component, architectural-decision, design-pattern, delivery-metric, engineering-practice, process-discipline, and the cross-cutting universals control, artifact, policy, and provenance.
- Eliminates redundant supertype declarations across engineering domain packs; descendant packs declare only their domain-specific types and resolve supertypes via the `extends` chain.
- Enables cross-pack subtype substitution: domain subtypes (e.g. `security-control` in `software-security`) are `subtype_of` these supertypes and substitutable at relationship endpoints, enforced by the concordance validator and `gate_m22`.
- Recognizes named design and architectural patterns (Factory, Singleton, CQRS, Event Sourcing, Saga) in research sources via its discovery patterns.

### Resolution

`engineering-base` is cataloged present-but-NOT-core (`core=false`): it is never
always-on and never auto-applied to a non-engineering topic (biology, agriculture,
legal never resolve these types). Resolution is **transitive** — binding a descendant
pack resolves the supertypes this layer declares, because `resolve-ontology.sh` walks
the `extends` chain. There is no Enable command and no "When to bind" step for this
layer; enable and bind one of its descendant domain packs instead.

---

## fitness

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/fitness/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/fitness)

### Purpose

Provides an entity vocabulary for exercise physiology, physical-activity taxonomy, and
wearable-device fitness data. Covers the five ACSM health-related fitness components
(cardiorespiratory endurance, muscular strength, muscular endurance, flexibility, body
composition), FITT-VP-principle exercise prescriptions, the Compendium of Physical
Activities' MET-coded activity taxonomy, and four Open mHealth wearable-device reading
types (step count, heart rate, calories burned, body weight). It `extends`
[`clinical-health-base`](#clinical-health-base) directly, inheriting the shared FHIR-
Observation-shaped clinical primitive its wearable-data types specialize.

### Domain

Exercise physiology, physical-activity taxonomy, and wearable-device fitness data.

### Entities, relationships, and traits

**Namespaces (semantic):** fitness-components (ACSM health-related fitness
components). **Namespaces (episodic):** fitness-activity-log (MET-coded physical
activity and wearable-device readings). **Namespaces (procedural):**
fitness-prescription (structured exercise-prescription protocols).

**Entity types:** cardiorespiratory-fitness, muscular-strength, muscular-endurance,
flexibility-fitness, body-composition (the five ACSM fitness-component assessments),
exercise-prescription (a FITT-VP-principle exercise-prescription protocol),
physical-activity (a MET-coded Compendium activity-taxonomy entry), met-value (a
metabolic-equivalent-of-task energy-expenditure measurement), omh-step-count,
omh-heart-rate, omh-calories-burned, omh-body-weight (four Open mHealth wearable-
device reading types).

**Key relationships:** `occurs_within` (an exercise-prescription occurs within a
clinical-encounter).

**Discovery patterns:** recognizes cardiorespiratory-endurance/VO2-max/aerobic-fitness
language, FITT/FITT-VP/exercise-prescription terminology, MET-value/metabolic-
equivalent/Compendium references, step-count/pedometer mentions, and heart-rate-
monitor terminology.

### When to bind

Bind `fitness` when researching exercise physiology, physical-activity taxonomy,
exercise-prescription protocols, or wearable-device fitness data.

### Enable

```sh
jq '(.ontologies[] | select(.id=="fitness") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-fitness topics.
- Extends `clinical-health-base` directly, which itself extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- The four Open mHealth reuse types inherit a documented dependency-trajectory risk: Open mHealth is in legacy maintenance (last release 2017) and is explicitly superseded by IEEE 1752.1 per its own README.

### Goals

- Provides vocabulary for exercise physiology and physical-activity taxonomy: the five ACSM health-related fitness components, FITT-VP exercise prescriptions, and the Compendium of Physical Activities' MET-coded taxonomy.
- Enables recognition of wearable-device fitness data via four Open mHealth reading types (step count, heart rate, calories burned, body weight).
- Resolves the shared FHIR-Observation-shaped `clinical-observation` primitive transitively via `clinical-health-base` without re-declaration.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## health

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/health/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/health)

### Purpose

Provides an entity vocabulary for general clinical-record data (HL7 FHIR R5 core
resources) and functioning classification (WHO ICF). Covers FHIR's Patient, Condition,
Observation, Encounter, Procedure, AllergyIntolerance, and DiagnosticReport resources,
the general WHO ICD-11 stem-code diagnosis shape and its extension/cluster-code
qualifiers, and the four WHO ICF classification components (body functions, body
structures, activities/participation domains, environmental factors). It `extends`
[`clinical-health-base`](#clinical-health-base) directly, inheriting the shared FHIR-
shaped and ICD-11-shaped clinical primitives its own types specialize.

### Domain

General clinical-record data and functioning/disability/health classification.

### Entities, relationships, and traits

**Namespaces (semantic):** health-classification (ICD-11 diagnosis classification),
health-functioning (ICF functioning, disability, and health classification).
**Namespaces (episodic):** health-clinical-record (FHIR-shaped clinical record data).

**Entity types:** patient, condition, fhir-observation, encounter, procedure,
allergy-intolerance, diagnostic-report (seven FHIR R5 core-resource clones),
clinical-diagnosis (the general ICD-11 stem-code diagnosis shape),
diagnosis-extension-qualifier (an ICD-11 extension/cluster code qualifying a
diagnosis), body-function, body-structure, activity-participation-domain,
environmental-factor (four WHO ICF classification components).

**Discovery patterns:** recognizes ICD-11/diagnosis-code/diagnostic-classification
language, ICF body-function (b1-b8) and impairment terminology, activities-of-daily-
living/ICF (d1-d9)/participation-restriction terms, FHIR Patient/demographics
language, FHIR Observation/vital-sign/lab-result mentions, and clinical-encounter
terminology.

### When to bind

Bind `health` when researching general clinical-record data, HL7 FHIR resource
modeling, ICD-11 diagnosis classification, or WHO ICF functioning and disability
classification.

### Enable

```sh
jq '(.ontologies[] | select(.id=="health") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-health topics.
- Extends `clinical-health-base` directly, which itself extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- ICF's "Personal Factors" component is explicitly excluded; the standard itself declines to classify or code it.

### Goals

- Provides vocabulary for general clinical-record data: seven HL7 FHIR R5 core resources (Patient, Condition, Observation, Encounter, Procedure, AllergyIntolerance, DiagnosticReport).
- Enables recognition of WHO ICD-11 diagnosis classification (stem codes and extension/cluster-code qualifiers) and the four WHO ICF functioning/disability/health classification components.
- Resolves shared FHIR-shaped and ICD-11-shaped clinical primitives (clinical-record-subject, clinical-encounter, clinical-observation, diagnostic-classification-entry) transitively via `clinical-health-base` without re-declaration.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## market-research

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/market-research/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/market-research)

### Purpose

Provides an entity vocabulary for market and competitive research: market segments,
competitors and brands, buyer personas, market sizing (TAM/SAM/SOM), competitive forces,
service offerings and demand, value propositions, market-intelligence reports, data
sources, survey instruments, and win-loss analyses. Sources include schema.org /
GoodRelations, Umbrex market-mapping, HubSpot TAM/SAM/SOM, Porter Five Forces, and the
Strategyzer Value Proposition Canvas.

### Domain

Market analysis, competitive intelligence, and customer/segment research.

### Entities, relationships, and traits

**Entity types:** segment, competitor, brand, buyer-persona, respondent-segment,
sizing-estimate, competitive-force, service-offering, market-demand, value-proposition,
market-intelligence-report, market-data-source, survey-instrument, win-loss-analysis.

**Key relationships:** `analyzes-competitor`, `based-on-source`, `covers-segment`,
`item-offered`, `maintains-brand`, `operates-in`, `provides-service`, `targets-audience`,
`tracks-competitive-force`.

**Traits applied:** `auditable`, `bounded`, `categorized`, `contactable`, `located`,
`measured`, `owned`, `reviewed`, `scheduled`, `scored`, `seasonal`, `tagged`, `versioned`.

**Discovery patterns:** recognizes segment/vertical, competitor, buyer-persona/ICP,
TAM/SAM/SOM sizing, Porter five-forces, survey/conjoint/NPS, win-loss, and data-source
terminology.

### When to bind

Bind `market-research` when researching market landscapes, competitive intelligence,
customer segmentation, market sizing, or buyer / voice-of-customer analysis.

### Enable

```sh
jq '(.ontologies[] | select(.id=="market-research") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-market-research topics.
- Extends `mif-base v1.0.0` (compatible with `shared-traits v1.0.0`); binding is fail-closed — `resolve-ontology.sh` aborts the corpus if the `extends` target is missing or mistyped.
- Scoped to market and competitive research; entity types do not apply to scientific, legal, or engineering topics.

### Goals

- Provides vocabulary for market and competitive research: market segments, competitors, brands, buyer personas, market sizing (TAM/SAM/SOM), competitive forces, service offerings, value propositions, market-intelligence reports, survey instruments, and win-loss analyses.
- Enables recognition of segment/vertical, competitor, TAM/SAM/SOM, Porter five-forces, NPS/conjoint survey, win-loss, and data-source terminology in research sources.
- Grounded in schema.org/GoodRelations, Porter Five Forces, Strategyzer Value Proposition Canvas, and Umbrex market-mapping; every entity type traces to a named source class.
- Typed findings validate fail-closed against MIF schema on binding.

---

## mif-docs

**Version:** 1.0.0 | **Kind:** ontology

**Source:** [`packs/ontologies/mif-docs/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/mif-docs)

### Purpose

The discovery layer for the mif-docs documentation suite: it types every document
genre the suite's skills emit (ADRs, architecture documents and C4 views, design docs,
RFCs/PEPs, PRDs, feature specs, Kiro requirements/design/tasks, Diataxis reference/
explanation/tutorial/how-to guides, runbooks, playbooks, and changelogs) and declares
the typed relationships that connect them into a knowledge graph, so an agent can
traverse from one MIF document to related knowledge — the decision a spec realizes,
the runbook a playbook coordinates, the requirements a design derives from — rather
than re-reading prose. It `extends` `mif-base` directly.

### Domain

MIF documentation genres and the cross-document relationships that connect them into
a traversable knowledge graph.

### Entities, relationships, and traits

**Namespaces (semantic):** decisions (architectural decision records), architecture
(architecture narratives, diagrams, and specs), specs (requirements, feature specs,
proposals), reference (information-oriented reference material). **Namespaces
(procedural):** operations (runbooks, playbooks, task plans), learning (tutorials and
how-to guides). **Namespaces (episodic):** history (changelogs and time-ordered
records).

**Entity types:** decision-record, architecture-document, architecture-view,
design-document, enhancement-proposal, product-requirements, feature-specification,
requirements-set, design-spec, task-plan, reference-document, explanation, tutorial,
how-to-guide, runbook, playbook, changelog — one per document genre the suite emits.

**Key relationships:** `realized-by` (a spec/decision is realized by a downstream
artifact), `derived-from` (an artifact is derived from an upstream one), `depends-on`
(an artifact depends on another), `supersedes` (a newer record supersedes an older
one), `relates-to` (a general, non-directional association between any two document
types).

**Discovery patterns:** no `content_pattern`-based discovery; instead this ontology
declares named traversal strategies (`decision-lineage`, `spec-chain`,
`kiro-traceability`, `ops-coordination`) that follow its typed relationships outward
from a starting document type (e.g. from a `decision-record`, follow `realized-by` to
the specs and architecture that implement it, and `supersedes` to its replacements).

### When to bind

Bind `mif-docs` when a topic's corpus is itself MIF documentation and findings need to
resolve to a specific document genre and traverse the relationships between documents,
rather than to the content those documents describe.

### Enable

```sh
jq '(.ontologies[] | select(.id=="mif-docs") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-documentation topics.
- Extends `mif-base` directly; `resolve-ontology.sh` resolves this single-hop chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Traversal is strategy-driven, not pattern-driven: there is no `discovery.patterns` list to classify untyped findings; the four named strategies instead follow the declared relationship types from a given starting genre.

### Goals

- Types every document genre the mif-docs suite emits, so a document instance in the graph resolves to the specific genre that produced it.
- Declares the typed relationships (`realized-by`, `derived-from`, `depends-on`, `supersedes`, `relates-to`) that connect documents into a knowledge graph instead of leaving cross-document links implicit in prose.
- Supplies four named traversal strategies (decision lineage, spec chain, Kiro traceability, ops coordination) an agent can follow to find related knowledge from a starting document.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## observability

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/observability/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/observability)

### Purpose

Provides an entity vocabulary for observability-platform research: observability
services and the telemetry signals they emit, service-ownership registries,
capability comparisons against a baseline, market positioning, time-stamped roadmap
signals, and platform migration patterns. Types form an explicit IS-A tree rooted in
the inherited generic and engineering supertypes. It `extends` both
[`engineering-base`](#engineering-base) (for `delivery-metric` and `design-pattern`)
and `mif-generic` (for `technology` and `concept`).

### Domain

Observability platforms, telemetry, and platform migration analysis (for example
AWS-native observability versus Datadog).

### Entities, relationships, and traits

**Namespaces (semantic):** services (observability services and the signals and
registries they provide), analysis (capability comparisons and market positioning).
**Namespaces (episodic):** roadmap (GA dates, launches, deprecations, predictions).
**Namespaces (procedural):** migrations (platform migration patterns and case studies).

**Entity types:** observability-service, service-ownership-registry, telemetry-signal,
capability-comparison, market-position, roadmap-signal, migration-pattern. Two abstract
intermediate supertypes (observability-resource, observability-assessment) organize the
IS-A tree and are not stamped on findings.

**Key relationships:** `emits`, `compares`, `positions`, `advances`, `catalogs`.

**Discovery patterns:** recognizes observability service names (CloudWatch, X-Ray, ADOT,
OpenTelemetry, Managed Prometheus, Managed Grafana, Application Signals), service-catalog
and developer-portal terminology, capability parity and gap language, migration case
studies, market-position language (Gartner, Magic Quadrant), and roadmap signals (GA,
re:Invent, end-of-support).

### When to bind

Bind `observability` when researching observability platforms, telemetry signals,
service-ownership and catalog tooling, capability gaps between observability vendors, or
platform migration patterns.

### Enable

```sh
jq '(.ontologies[] | select(.id=="observability") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-observability topics.
- Extends `engineering-base` and `mif-generic`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Scoped to observability platforms and migration analysis; the two abstract supertypes are not directly stampable on findings.

### Goals

- Provides vocabulary for observability-platform research: services, telemetry signals, service-ownership registries, capability comparisons, market positions, roadmap signals, and migration patterns.
- Resolves shared engineering supertypes (delivery-metric, design-pattern) transitively via `engineering-base` and the generic `technology` and `concept` via `mif-generic` without re-declaration.
- Enables recognition of observability service names, telemetry and pillar terminology, capability-parity language, market-position and roadmap signals, and migration case studies in research sources.
- Typed findings validate fail-closed against MIF schema on binding.

---

## physical-science-base

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/physical-science-base/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/physical-science-base)

### Purpose

A MIF-compliant intermediate layer beneath the physical-science DOMAIN packs
(`plasma-physics`, `cosmology`). It owns the two shapes both packs independently
mined from unrelated PACS sections (52.xx vs 98.xx): a PACS-code-tagged
classification-scheme entry, and a named physical quantity with a value and unit
produced by a measurement or observation. It `extends` `research` rather than
`mif-base`/`shared-traits` directly, since `physical-quantity` needs to subtype
`research`'s own generic `observation` shape, which is not reachable through the
generic core alone.

### Domain

Shared physics/astrophysics vocabulary — classification-scheme entries and named
physical quantities.

### Entities, relationships, and traits

**Namespaces (semantic):** physical-science (physics/astrophysics classification and
quantity shapes).

**Entity types:** classification-scheme-entry (a named, coded entry in a physics or
astrophysics classification scheme — the shape plasma-physics's and cosmology's
PACS-grounded classification mints both independently converged on),
physical-quantity (a named physical quantity with a value and unit — the shape
plasma-physics's fundamental plasma-parameter quantities and cosmology's
observational-cosmology and background-radiation parameters both independently
converged on).

**Discovery patterns:** disabled at this layer (`discovery.enabled: false`) — this is
a base layer, not directly instantiated by findings; the patterns declared here (PACS-
code/classification-scheme language and physical-quantity/named-quantity language) are
inactive and only its leaf-pack specializations (`plasma-physics`, `cosmology`)
discover from source text.

### When to bind

Bind `physical-science-base` directly only if a topic needs its bare classification-
scheme-entry or physical-quantity shapes without any leaf-pack specialization. In
practice it is more often resolved transitively by binding `plasma-physics` or
`cosmology` instead, whose `extends` chain reaches here.

### Enable

```sh
jq '(.ontologies[] | select(.id=="physical-science-base") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-physical-science topics.
- Extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Discovery is disabled at this layer; findings are typed at the `plasma-physics`/`cosmology` leaf-pack level, not here.

### Goals

- Supplies the two shared physics/astrophysics entity-type shapes (`classification-scheme-entry`, `physical-quantity`) that `plasma-physics` and `cosmology` each independently converged on.
- Eliminates redundant supertype declarations across the two physical-science leaf packs; each declares only its domain-specific types and resolves supertypes via the `extends` chain.
- Enables cross-pack subtype substitution: leaf-pack types (e.g. plasma-physics's `plasma-parameter`, cosmology's `observational-cosmology-parameter`) are all `subtype_of` `physical-quantity`.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## plasma-physics

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/plasma-physics/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/plasma-physics)

### Purpose

Provides an entity vocabulary for plasma phenomena, confinement devices, diagnostic
and simulation techniques, and fundamental plasma quantities. Covers all 19 PACS
section-52 top-level subsections (elementary processes, plasma properties, dynamics
and flow, wave instabilities, laser and nonlaser interactions, heating methods,
intense particle beams, applications, and electric discharges), magnetic- and
inertial-confinement and pinch fusion devices, plasma simulation and diagnostic
techniques, and named plasma parameters (Debye length, plasma frequency, Larmor
radius). It `extends` [`physical-science-base`](#physical-science-base) directly,
inheriting the shared PACS-classification and physical-quantity primitives its own
types specialize.

### Domain

Plasma physics, fusion-confinement devices, and plasma diagnostics.

### Entities, relationships, and traits

**Namespaces (semantic):** plasma-phenomena (plasma physical phenomena
classification, PACS 52.xx), plasma-devices (plasma confinement and generation
apparatus), plasma-parameters (fundamental plasma physical quantities).
**Namespaces (procedural):** plasma-diagnostics (plasma diagnostic and simulation
techniques).

**Entity types:** elementary-plasma-process, plasma-property, plasma-dynamics-flow,
plasma-wave-instability, laser-plasma-interaction, plasma-interaction-nonlaser,
intense-particle-beam-source, plasma-application, electric-discharge (PACS-classified
phenomena entries), plasma-heating-method (a PACS-classified, procedural heating-
method entry), magnetic-confinement-configuration, laser-inertial-confinement-device,
pinch-device, plasma-device (confinement and generation apparatus), plasma-simulation-
method, plasma-diagnostic-technique (research procedures), plasma-parameter (a named
fundamental plasma quantity).

**Discovery patterns:** recognizes plasma-instability/plasma-wave/Langmuir-wave/
Alfven-wave language, tokamak/stellarator/magnetic-confinement/reversed-field-pinch
terminology, inertial-confinement-fusion/ICF/laser-driven-fusion mentions, Debye-
length/plasma-frequency/Larmor-radius references, and Langmuir-probe/plasma-
diagnostic/Thomson-scattering terms.

### When to bind

Bind `plasma-physics` when researching plasma phenomena, fusion confinement-device
technology, plasma diagnostic or simulation techniques, or fundamental plasma
quantities.

### Enable

```sh
jq '(.ontologies[] | select(.id=="plasma-physics") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-plasma-physics topics.
- Extends `physical-science-base` directly, which itself extends `research`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Grounded in the frozen 2010 PACS edition, superseded by APS's actively-maintained PhySH; the classification-scheme-entry mints keyed to PACS 52.xx inherit this documented dependency-trajectory risk.

### Goals

- Provides vocabulary for plasma physics: all 19 PACS section-52 top-level subsections covering plasma phenomena, properties, dynamics, waves, interactions, heating, and applications.
- Enables recognition of magnetic- and inertial-confinement fusion devices (tokamaks, stellarators, pinch devices, laser ICF) and plasma diagnostic/simulation techniques.
- Resolves shared PACS-classification and physical-quantity supertypes transitively via `physical-science-base` without re-declaration.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## platform-engineering

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/platform-engineering/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/platform-engineering)

### Purpose

Provides an entity vocabulary for internal developer platforms and portals: the
developer portal itself, the plugins that extend it, the software templates and
golden paths it paves, and the typed integrations that bind it to external systems
(identity, source control, cloud, observability, incident, security, CI/CD,
infrastructure, ticketing). Motivated by research on a Backstage-based internal
developer portal, where every distinct portal concern (Okta auth, GitHub integration,
the scaffolder, PagerDuty/Snyk/Orca plugins, the AWS resource catalog) collapsed into
a single undifferentiated "service catalog / developer portal" type before this pack
existed. It `extends` [`engineering-base`](#engineering-base) directly.

### Domain

Internal developer platforms and portals, platform-engineering tooling, and portal
integrations with external systems.

### Entities, relationships, and traits

**Namespaces (semantic):** portals (internal developer portals and the plugins that
extend them), integrations (typed bindings from a portal to external systems), paths
(software templates and golden paths).

**Entity types:** developer-portal (an internal developer portal/platform, a
`component` subtype), portal-plugin (a plugin/extension that adds capability to a
portal, a `component` subtype), software-template (a scaffolder/golden-path template
that instantiates a ready-to-run project), golden-path (a paved-road workflow with
guardrails), portal-integration (a typed binding from a portal to an external system,
differentiated by `integration_category`).

**Key relationships:** `integrates` (a developer portal exposes a typed integration to
an external system), `extends_portal` (a plugin extends a developer portal),
`provides` (a developer portal provides golden paths and software templates),
`scaffolds` (a software template scaffolds a component), `bound_to` (a portal
integration binds the portal to an external technology).

**Discovery patterns:** recognizes internal-developer-portal/platform/Backstage/IDP
language, Backstage-plugin/portal-plugin/frontend-backend-module terminology,
software-template/scaffolder-template/golden-path-template/cookiecutter mentions,
golden-path/paved-road terminology, and named external-system integration language
(Okta, OIDC, SAML, SSO, GitHub, PagerDuty, Snyk, Orca, Chronosphere, Grafana, AWS)
paired with integration/provider/plugin/auth/catalog-discovery terms.

### When to bind

Bind `platform-engineering` when researching internal developer platforms/portals,
platform-engineering tooling, software templates and golden paths, or a portal's
typed integrations with external systems.

### Enable

```sh
jq '(.ontologies[] | select(.id=="platform-engineering") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — bound to a topic only when it concerns an internal developer platform/portal.
- Extends `engineering-base`, which itself extends `mif-base` and `shared-traits`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- `portal-integration.integration_category` is the differentiator for the many external bindings a portal exposes; a finding whose integration type does not resolve to a named `integration_category` value is not substitutable for a different one.

### Goals

- Provides vocabulary for internal developer platforms: the portal itself, its plugins, software templates, golden paths, and typed external-system integrations.
- Gives previously-undifferentiated portal concerns (auth providers, SCM integration, the scaffolder, observability/incident/security plugins) distinct, queryable types instead of one generic catalog type.
- Resolves shared engineering supertypes (`component`) transitively via `engineering-base` without re-declaration; `developer-portal` and `portal-plugin` are both `subtype_of: [component]`.
- Typed findings validate fail-closed against the MIF schema on binding.

---

## psycholinguistics

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/psycholinguistics/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/psycholinguistics)

### Purpose

Provides an entity vocabulary for psycholinguistics and computational stylometry research:
psycholinguistic constructs, stylometric features, psychometric indices, elicitation
protocols, research instruments, linguistic frameworks, and references to existing
frameworks. Supports voice-elicitation, personality-language mapping, and
authorship/readability research. Sources include the Big Five/OCEAN model, LIWC, Flesch
readability, MATTR/MTLD lexical-diversity measures, Burrows's Delta (stylo), and the
Cognitive Interview.

### Domain

Psycholinguistics, computational stylometry, and voice-elicitation research.

### Entities, relationships, and traits

**Namespaces (semantic):** constructs (psycholinguistic and psychological constructs),
features (stylometric and linguistic features), indices (psychometric indices and derived
scores), instruments (research instruments, tools, and platforms), frameworks (linguistic
and psycholinguistic frameworks), protocols (elicitation and interview protocols).

**Entity types:** psycholinguistic-construct, stylometric-feature, psychometric-index,
elicitation-protocol, research-instrument, linguistic-framework, existing-framework-reference.

**Key relationships:** `measures`, `operationalizes`, `grounds`.

**Traits applied:** `cited`.

**Discovery patterns:** recognizes Big Five/OCEAN and HEXACO trait terminology, LIWC,
readability and lexical-diversity measures (TTR, MATTR, MTLD, Flesch, Kincaid), stylometry
and authorship-attribution terms (stylo, Burrows's Delta), and elicitation-protocol
language (cognitive interview, think-aloud, voice interview).

### When to bind

Bind `psycholinguistics` when researching personality-language mapping, voice elicitation,
stylometry and authorship attribution, readability and lexical diversity, or the research
instruments and frameworks used in those studies.

### Enable

```sh
jq '(.ontologies[] | select(.id=="psycholinguistics") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-psycholinguistics topics.
- Extends `engineering-base` and `mif-generic`; `resolve-ontology.sh` walks the full chain fail-closed — a missing or mistyped `extends` target aborts corpus resolution.
- Scoped to psycholinguistics and stylometry research; entity types do not apply to engineering operational, legal, or market-research topics.

### Goals

- Provides vocabulary for psycholinguistics and stylometry research: constructs, stylometric features, psychometric indices, elicitation protocols, research instruments, linguistic frameworks, and existing-framework references.
- Resolves the generic `concept` and `technology` supertypes via `mif-generic` and `delivery-metric` and `design-pattern` via `engineering-base` without re-declaration.
- Enables recognition of Big Five/OCEAN and LIWC terminology, readability and lexical-diversity measures, stylometry and authorship-attribution terms, and elicitation-protocol language in research sources.
- Grounded in the Big Five/OCEAN model, LIWC, Flesch readability, MATTR/MTLD, Burrows's Delta, and the Cognitive Interview; relationships are RO/IAO grounded.
- Typed findings validate fail-closed against MIF schema on binding.

---

## regenerative-agriculture

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/regenerative-agriculture/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/regenerative-agriculture)

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

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-agriculture topics.
- Extends `mif-base v1.0.0` and `shared-traits v1.0.0`; binding is fail-closed — `resolve-ontology.sh` and `validate-concordance.sh` abort the corpus if either `extends` target is missing or mistyped.
- Scoped strictly to farm business records, supply chain, carbon credits, and certification tracking — not research observations; for research-oriented findings use `regenerative-agriculture-research` instead.

### Goals

- Provides vocabulary for regenerative farm business operations: land parcels and soil profiles, livestock, supply chain, carbon market activities, certifications, and farm financials.
- Enables recognition of farm operation terminology, soil health references, certification body names (ROC, Rainforest Alliance), and carbon market identifiers in research sources.
- Grounded in Rodale Institute ROC Standards, Soil & Climate Initiative Verification Framework v3.0 (2025), USDA NRCS Soil Health Principles, and FAO Agroecology Knowledge Hub.
- Typed findings validate fail-closed against MIF schema on binding.

---

## regenerative-agriculture-research

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/regenerative-agriculture-research/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/regenerative-agriculture-research)

### Purpose

Provides a research-oriented entity vocabulary for regenerative agriculture findings.
Covers research observations about farming practices, infrastructure, funding, and
technology — not farm records. Types form an IS-A tree rooted in the inherited generic
and engineering supertypes. It `extends` both [`engineering-base`](#engineering-base)
(for `engineering-practice`, `component`, and `policy`) and `mif-generic` (for
`technology` and `concept`).

### Domain

Research findings about regenerative agriculture practices: husbandry, agronomy, farm
infrastructure, funding programs, and farm technology.

### Entities, relationships, and traits

**Namespaces (semantic):** husbandry (animal husbandry and livestock care knowledge),
agronomy (grazing, soil, crop, and pasture practices), infrastructure (fencing,
irrigation, IoT, networks), funding (grants, cost-share, and funding programs).

**Entity types (21):** husbandry-practice, agronomic-practice, farm-infrastructure,
grant-program, equipment-or-input, plus the husbandry leaves parturition-protocol,
neonatal-care, periparturient-nutrition, livestock-health-condition, and
breed-characteristic; the farm-infrastructure leaves fencing-system, irrigation-system,
connectivity-link, sensor-or-edge-node, power-system, and network-segment; the
equipment leaves iot-device and fencing-component; the grant-program leaf
conservation-cost-share; and the cross-cutting adoption-trend and compliance-regulation.

**Key relationships:** `relates_to`, `supports`, `has_part`, `connects`.

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

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-agriculture topics.
- Extends `mif-base v1.0.0`; binding is fail-closed — `resolve-ontology.sh` aborts the corpus if the `extends` target is missing or mistyped.
- Scoped to research observations about farming practices — not farm business records or supply chain tracking; for farm records use `regenerative-agriculture` instead.

### Goals

- Provides research-oriented vocabulary for regenerative agriculture findings: husbandry practices, agronomy (grazing, soil, crop, pasture), farm infrastructure (fencing, irrigation, IoT), funding programs, and cross-cutting technology and security research types.
- Enables recognition of husbandry and agronomy terminology, farm infrastructure keywords, grant and funding program identifiers, and IoT/technology references in a farm research context.
- Cross-cutting technology and security research types are included so topics spanning farm technology and infrastructure resolve without a separate pack.
- Typed findings validate fail-closed against MIF schema on binding.

---

## regulatory-legal

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/regulatory-legal/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/regulatory-legal)

### Purpose

Provides an entity vocabulary for regulatory and legal research: legislative acts and
treaties, obligations and rights, jurisdictions and authorities, contracts, licenses,
court decisions, regulatory sanctions, compliance reporting, and control mappings.
Grounded in LKIF-Core, FIBO (FBC / FND), ELI v1.5, Akoma Ntoso, and NIST OSCAL.

### Domain

Law, regulation, compliance, and governance contexts.

### Entities, relationships, and traits

**Entity types:** legal-act, treaty, obligation, legal-right, legal-capacity,
jurisdiction, authority, legal-person, legal-role, contract, license-permit,
control-mapping, court-decision, regulatory-sanction, legal-procedure, assessment,
compliance-report.

**Key relationships:** `amends`, `applies_in`, `cites`, `confers`, `governed_by`,
`has_jurisdiction_in`, `imposes`, `regulates`, `satisfies`, `transposes`.

**Traits applied:** `auditable`, `bounded`, `categorized`, `contactable`, `lifecycle`,
`located`, `owned`, `regulated`, `renewable`, `reviewed`, `scheduled`, `scored`, `tagged`.

**Discovery patterns:** recognizes regulation citations (Regulation (EU), U.S.C., GDPR,
HIPAA), deontic language (shall / must / prohibited), jurisdictions, regulators, control
crosswalks (OLIR), ELI / Akoma Ntoso URIs, case citations (ECLI), and contract / legal-role
terminology. `control-mapping.control_ref` bridges to the software-security pack's `security-control` type.

### When to bind

Bind `regulatory-legal` when researching laws and regulations, compliance obligations,
legal instruments and case law, or control-to-obligation mappings.

### Enable

```sh
jq '(.ontologies[] | select(.id=="regulatory-legal") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-legal topics.
- Extends `mif-base v1.0.0` and `shared-traits v1.0.0`; binding is fail-closed — `resolve-ontology.sh` and `validate-concordance.sh` abort the corpus if either `extends` target is missing or mistyped.
- Scoped to law, regulation, compliance, and governance; `control-mapping.control_ref` bridges cross-pack to `software-security`'s `security-control` type but the types are not interchangeable across packs.

### Goals

- Provides vocabulary for regulatory and legal research: legislative acts, treaties, obligations, rights, jurisdictions, authorities, contracts, licenses, court decisions, sanctions, compliance reports, and control mappings.
- Enables recognition of regulation citations (Regulation (EU), U.S.C., GDPR, HIPAA), deontic language (shall / must / prohibited), ELI/Akoma Ntoso URIs, ECLI case citations, and OLIR control crosswalks in research sources.
- Grounded in LKIF-Core, FIBO (FBC/FND), ELI v1.5, Akoma Ntoso, and NIST OSCAL; every entity type traces to a named source vocabulary class.
- Typed findings validate fail-closed against MIF schema on binding; `control-mapping.control_ref` provides a cross-pack bridge to `software-security`'s `security-control` type.

---

## scientific

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/scientific/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/scientific)

### Purpose

Provides an entity vocabulary for scientific research: studies and investigations,
methods and protocol applications, samples and measurements, hypotheses, instruments,
publications and funding, and datasets with their catalogs, distributions, services, and
provenance. Grounded in OBO Foundry / OBI, IAO, COB, W3C DCAT 3, W3C PROV-O, and
schema.org (OBO IRIs are OLS4/Ontobee-confirmed).

### Domain

Scientific studies, research data management, and data provenance.

### Entities, relationships, and traits

**Entity types:** study, research-investigation, cohort, method, protocol-application,
sample-organism, measurement, hypothesis, research-instrument, research-publication,
research-funding, dataset, data-distribution, data-service, dataset-series, data-catalog,
data-provenance.

**Key relationships:** `applies`, `catalogs`, `enrolls`, `funded_by`, `has_sample`,
`measured_on`, `produces`, `reports_in`, `tests`, `uses_instrument`, `uses_method`.

**Traits applied:** `auditable`, `bounded`, `budgeted`, `categorized`, `inventoried`,
`lifecycle`, `located`, `maintainable`, `measured`, `owned`, `quality_controlled`,
`renewable`, `reviewed`, `scheduled`, `tagged`.

**Discovery patterns:** recognizes study / trial / cohort, assay / protocol / method,
sample / organism / tissue, measurement, hypothesis, instrument, DOI / preprint, grant,
DCAT dataset, and PROV-O provenance terminology.

### When to bind

Bind `scientific` when researching scientific studies, experimental methods, research
data and catalogs, or data provenance and lineage.

### Enable

```sh
jq '(.ontologies[] | select(.id=="scientific") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-scientific topics.
- Extends `mif-base v1.0.0` and `shared-traits v1.0.0`; binding is fail-closed — `resolve-ontology.sh` and `validate-concordance.sh` abort the corpus if either `extends` target is missing or mistyped.
- Scoped to scientific studies, research data management, and data provenance; entity types do not apply to engineering operational, legal, or market-research topics.
- OBO IRIs are OLS4/Ontobee-confirmed gate-corrected values; a finding whose `ontology.id` and resolved type do not align is a hard fail, not a fallback.

### Goals

- Provides vocabulary for scientific research: studies, investigations, cohorts, methods, protocol applications, samples, measurements, hypotheses, instruments, publications, funding, datasets, data distributions, data services, dataset series, catalogs, and data provenance.
- Enables recognition of study/trial/cohort, assay/protocol/method, sample/organism/tissue, measurement, hypothesis, instrument, DOI/preprint, grant, DCAT dataset, and PROV-O provenance terminology in research sources.
- Grounded in OBO Foundry/OBI, IAO, COB, W3C DCAT 3, W3C PROV-O, and schema.org; every entity type traces to a named source vocabulary.
- Typed findings validate fail-closed against MIF schema on binding.

---

## software-engineering

**Version:** 0.5.0 | **Kind:** ontology

**Source:** [`packs/ontologies/software-engineering/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/software-engineering)

### Purpose

Provides an entity vocabulary for the SDLC-operational slice of software engineering:
production incidents and operational procedures. It `extends`
[`engineering-base`](#engineering-base), from which it inherits the shared engineering
supertypes (component, architectural-decision, design-pattern, delivery-metric,
engineering-practice, process-discipline); the generic `technology` comes from
`mif-generic`. Security types (`security-threat`, `security-framework`,
`security-incident`) live in the [`software-security`](#software-security) pack, and
regulation is modeled in [`regulatory-legal`](#regulatory-legal) (subsumed by its
`legal-act` / `obligation`). The former `adoption-trend` is gone — the
[`trend-analysis`](#trend-analysis) pack's `trend` is canonical.

### Domain

Software development teams, software architecture research, and engineering process
analysis.

### Entities, relationships, and traits

**Namespaces (procedural):** deployments (deployment procedures, release processes).

**Entity types:** incident-report, runbook, deployment-procedure, migration-guide (the
shared supertypes are inherited from `engineering-base`, not re-declared here).

**Traits applied:** `versioned`, `dated`, `timeline`, `stakeholders`.

**Discovery patterns:** recognizes incident / outage / postmortem / RCA, runbook /
playbook / SOP, deployment / release, and migration / upgrade terminology in research
sources.

### When to bind

Bind `software-engineering` when researching production incidents and postmortems,
operational runbooks, deployment and release procedures, or system migration plans. For
the shared engineering supertypes (components, architecture, decisions, patterns), bind
this or any sibling engineering pack — they are inherited from `engineering-base`.

### Enable

```sh
jq '(.ontologies[] | select(.id=="software-engineering") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-software-engineering topics.
- Extends `engineering-base`, which extends `mif-base` and `shared-traits`; `resolve-ontology.sh` walks the full chain fail-closed — a missing target in the chain aborts corpus resolution.
- Scoped strictly to SDLC-operational types; version 0.5.0 is a clean break with no back-compat aliases; security types belong to `software-security`, regulation to `regulatory-legal`, and trend to `trend-analysis`.

### Goals

- Provides vocabulary for software engineering operations: incident reports, runbooks, deployment procedures, and migration guides.
- Resolves shared engineering supertypes (component, architectural-decision, design-pattern, delivery-metric, engineering-practice, process-discipline) transitively via `engineering-base` without re-declaration.
- Enables recognition of incident/outage/postmortem/RCA, runbook/playbook/SOP, deployment/release, and migration/upgrade terminology in research sources.
- Typed findings validate fail-closed against MIF schema on binding.

---

## software-security

**Version:** 0.2.0 | **Kind:** ontology

**Source:** [`packs/ontologies/software-security/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/software-security)

### Purpose

Provides an entity vocabulary for the software-facing slice of security research:
vulnerabilities and weaknesses, controls, threat actors, campaigns and tactics,
indicators of compromise, malware, tools and infrastructure, threat-intelligence
reports, supply-chain risk, policies, assessments, and POA&Ms. It `extends`
[`engineering-base`](#engineering-base). Grounded in MITRE ATT&CK / CAPEC, CVE / CWE /
NVD, NIST SP 800-53 / OSCAL / 800-161r1, STIX 2.1, OWASP, and VERIS. The
`security-threat`, `security-framework`, and `security-incident` types live **here**, as
SDLC-facing supertypes that the finer STIX / ATT&CK / CWE types (attack-tactic, weakness,
vulnerability) refine.

### Domain

Cybersecurity threat intelligence, vulnerability management, and security compliance.

### Entities, relationships, and traits

**Entity types:** attack-tactic, attack-mitigation, malware, vulnerability, weakness,
security-control, threat-actor, attack-campaign, indicator-of-compromise, security-infrastructure,
security-tool, threat-intelligence-report, supply-chain-risk, security-policy,
security-assessment, poam, security-threat, security-framework, security-incident.

**Key relationships:** `attributed_to`, `categorizes`, `defines`, `documents`, `exploits`,
`hosts`, `indicates`, `mitigates`, `mitigates_threat`, `realizes`, `tracks`, `uses`.

**Traits applied:** `auditable`, `categorized`, `certified`, `inventoried`, `located`,
`measured`, `owned`, `quality_controlled`, `regulated`, `reviewed`, `scheduled`, `scored`,
`tagged`, `versioned`.

**Discovery patterns:** recognizes ATT&CK technique / CAPEC IDs, CVE / CWE ids, NIST
control ids, framework names, breach / ransomware terms, threat-actor and campaign names,
IOC / YARA / STIX / TLP markers, supply-chain / SBOM, pen-test / red-team, and malware
family names.

### When to bind

Bind `software-security` when researching threat intelligence, vulnerability and weakness
analysis, security controls and frameworks, or security compliance and assessment.

### Enable

```sh
jq '(.ontologies[] | select(.id=="software-security") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-security topics.
- Extends `engineering-base` (which extends `mif-base` and `shared-traits`); `resolve-ontology.sh` walks the full chain fail-closed — a missing target in the chain aborts corpus resolution.
- `security-threat`, `security-framework`, and `security-incident` are defined here as SDLC-facing supertypes; finer ATT&CK/CWE types refine them. A finding whose resolved type belongs to a different ontology than its pin names is a hard fail.

### Goals

- Provides vocabulary for cybersecurity research: attack tactics, mitigations, malware, vulnerabilities, weaknesses, security controls, threat actors, attack campaigns, indicators of compromise, security infrastructure, tools, threat-intelligence reports, supply-chain risk, policies, assessments, and POA&Ms.
- Resolves shared engineering supertypes transitively via `engineering-base`; `security-control` is `subtype_of: [control]` and substitutable at relationship endpoints, enforced by the concordance validator and `gate_m22`.
- Enables recognition of ATT&CK technique/CAPEC IDs, CVE/CWE IDs, NIST control IDs, breach/ransomware terms, IOC/YARA/STIX/TLP markers, and SBOM/supply-chain terminology in research sources.
- Typed findings validate fail-closed; `control-mapping.control_ref` in `regulatory-legal` bridges to this pack's `security-control` type.

---

## trend-analysis

**Version:** 0.1.0 | **Kind:** ontology

**Source:** [`packs/ontologies/trend-analysis/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/ontologies/trend-analysis)

### Purpose

Provides an entity vocabulary for strategic foresight and trend analysis: weak signals,
drivers, trends and megatrends, emerging issues, wild cards, critical uncertainties,
adoption curves, forecasts, scenarios, horizons, implications, visions, and roadmaps.
Grounded in IFTF foresight, EU JRC / K4P, Sitra, Shell / GBN scenario planning, Rogers
Diffusion of Innovations, Gartner Hype Cycle, Three Horizons, the Futures Wheel, and
OECD-OPSI. (Six types the inventory based on `analytical` are remapped to the `semantic`
root, since the mif-base cognitive triad has no `_analytical` root.) This pack's `trend`
is canonical, replacing the former `adoption-trend` (which has been removed).

### Domain

Strategic foresight, futures studies, and technology / market trend analysis.

### Entities, relationships, and traits

**Entity types:** signal, driver, trend, megatrend, emerging-issue, wild-card,
critical-uncertainty, adoption-curve, forecast, scenario, horizon, implication, vision,
roadmap.

**Key relationships:** `constrains`, `generates`, `grounds`, `indicates`, `informs`,
`intensifies`, `matures_into`, `operationalizes`, `placed_on`, `produces`, `specializes`.

**Traits applied:** `auditable`, `bounded`, `categorized`, `measured`, `owned`,
`reviewed`, `scheduled`, `scored`, `tagged`, `versioned`.

**Discovery patterns:** recognizes weak-signal, driver-of-change / STEEP, trend, hype-cycle
/ S-curve, forecast, megatrend, scenario, and wild-card / black-swan terminology.

### When to bind

Bind `trend-analysis` when researching strategic foresight, emerging signals and
megatrends, technology adoption and hype cycles, or scenario and roadmap planning.

### Enable

```sh
jq '(.ontologies[] | select(.id=="trend-analysis") | .enabled) |= true' \
  harness.config.json > harness.config.tmp && mv harness.config.tmp harness.config.json
```

### Constraints

- Opt-in only; cataloged `core=false` — never auto-applied to non-foresight topics.
- Extends `mif-base v1.0.0` (compatible with `shared-traits v1.0.0`); binding is fail-closed — `resolve-ontology.sh` aborts the corpus if the `extends` target is missing or mistyped.
- `trend` is the canonical generic trend type here; the former `adoption-trend` from `software-engineering` is removed and replaced by this pack's `trend` (no back-compat alias).
- Six entity types (adoption-curve, forecast, horizon, implication, scenario, vision) are remapped to the `semantic` base under the `_semantic/foresight` namespace tree; the mif-base cognitive triad has no `_analytical` root.

### Goals

- Provides vocabulary for strategic foresight and trend analysis: signals, drivers, trends, megatrends, emerging issues, wild cards, critical uncertainties, adoption curves, forecasts, scenarios, horizons, implications, visions, and roadmaps.
- Enables recognition of weak-signal, STEEP driver-of-change, trend, hype-cycle/S-curve, forecast, megatrend, scenario, and wild-card/black-swan terminology in research sources.
- Grounded in IFTF, EU JRC/K4P, Sitra, Shell/GBN scenario planning, Rogers Diffusion of Innovations, Gartner Hype Cycle, Three Horizons, Futures Wheel, and OECD-OPSI.
- Typed findings validate fail-closed against MIF schema on binding.
