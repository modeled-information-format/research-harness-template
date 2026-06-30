---
name: architecture-spec
description: Genre template for an AI-ready architecture specification (arc42/C4) — cross-cutting entity types, relationships, namespaces, decisions-with-alternatives, and EARS acceptance criteria a downstream AI coding agent can execute without re-deriving intent. Use when the deliverable defines a STRUCTURE (types, relationships, namespaces) rather than a single feature or behaviour.
version: 0.1.0
---

# Genre Template: AI-Ready Architecture Spec

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, frontmatter contract, and acceptance-criteria form. `report-synthesizer` consumes
this template, binds the surviving findings (MIF units validated by
`schemas/findings.schema.json`, drawn from `reports/<topic>/`), and the `ai-spec` channel
renders the result.

This genre is **self-demonstrating**: the canonical proof a spec genre is buildable is a spec
authored in it. The template's own §1–§12 taxonomy is itself an architecture spec.

## Target audience

An **implementer** — and specifically a downstream **AI coding agent** that will build the
work from the rendered spec. Quality goals, in priority order: (1) agent-executable — the agent
builds without re-deriving intent; (2) grounded — every design claim cites a surviving finding
or a named external standard; (3) deterministic — the same findings render the same spec;
(4) self-demonstrating.

## Selection rule

Use `architecture-spec` when the deliverable defines a **structure** (cross-cutting types,
relationships, namespaces). If it defines a single **feature** or a **behaviour**, use
`kiro-spec` or `feature-spec` instead.

## Three mappings (build on the existing artifact pipeline)

This genre is a shaping of the `artifact.json` → Markdown pipeline, not a new mechanism:

- `artifact.finding_refs[]` → the spec's **grounded evidence sections** (§9 and the per-section
  citations). No design claim is ungrounded.
- the goal's `completion_condition.checks[]` → the spec's **EARS acceptance criteria** (§8).
  Each check is already `{id, assertion, verify}`, mapping 1:1 to `WHEN … SHALL …` with the
  verify command as the executable test.
- `artifact.sections[]` → the **document structure** (the §1–§12 taxonomy below).

## Frontmatter contract

MIF Level-1+ frontmatter plus the genre markers: `genre: architecture-spec`,
`audience: implementer`, `status` (`proposed` for a greenfield build, or documenting an
existing one), `evidence_base` (a one-line account of the finding set), and an optional
`spec:` block (`id`, `goal`, `scope`, `version`). Citations are MIF `Citation` objects.

## Section taxonomy (hold fixed; fill the slots)

1. **Introduction and goals** — the build subject and quality goals.
2. **Constraints** — what is fixed and not up for negotiation in this build.
3. **Context and scope** (C4 system context) — what the build consumes and produces; in/out of scope.
4. **Solution strategy** — the approach, grounded in surviving findings.
5. **Building-block view** (C4 container view) — the independent units the build ships (entity catalog).
6. **Runtime view** — how the pieces interact; namespace and versioning conventions.
7. **Decisions and alternatives** (Path B) — each decision states the options, the selection rule, and the recommendation.
8. **Acceptance criteria (EARS)** — one `WHEN … SHALL …` statement per goal check, with the verify command.
9. **Evidence base** — the artifacts/findings that ground the design (the grounded evidence sections).
10. **Risks and caveats** — reported with the qualifications the falsification gate applied (weakened/inconclusive).
11. **How to reuse as template** — the parameterised slots a future build fills.
12. **Sources** — named external standards and works.

## EARS acceptance-criteria form

```text
AC-<n>  WHEN <trigger / condition>, THE SYSTEM SHALL <required behaviour>.
        Verify: <the goal check's verify command — the executable test>.
```

## Authoring rules

- Every §5/§9 evidence row carries its grounding (a `finding_ref` or a named source vocabulary).
- §7 keeps live forks visible: options + selection rule + recommendation, never a bare assertion.
- The rendered spec must be deterministic (same findings → byte-identical Markdown) and pass
  `markdownlint-cli2` with zero errors.
- Greenfield builds carry `status: proposed`; documenting an existing build carries the worked
  specimen's "these artifacts already exist" framing — same taxonomy, different `status`.

## Reuse as template

Hold the taxonomy fixed and fill: the **build subject** (§1, §3), the **genre selection** (§7.1
rule), the **building blocks** (§5), the **evidence base** (§9), and the **acceptance criteria**
(§8, one EARS statement per goal check). A document that fills these slots is one the `ai-spec`
channel could have emitted.
