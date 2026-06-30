---
name: kiro-spec
description: Genre template for a Kiro three-file spec — requirements -> design -> tasks — a single-feature, task-decomposed build spec an AI coding agent executes. Use when the deliverable is one feature with a clear task decomposition (a behaviour to build), not a cross-cutting structure.
version: 0.1.0
---

# Genre Template: Kiro Three-File Spec

A deliverable-genre template (SPEC §6d). `report-synthesizer` binds the surviving findings
(`schemas/findings.schema.json`, from `reports/<topic>/`); the `ai-spec` channel renders the
result. Modelled on Amazon Kiro's requirements -> design -> tasks decomposition.

## Selection rule

Use `kiro-spec` when the deliverable is a **single feature** with a clear task decomposition.
For a cross-cutting **structure** use `architecture-spec`; for a one-capability agent spec use
`feature-spec`.

## Three mappings

- `artifact.finding_refs[]` → grounded evidence in **Design**.
- goal `completion_condition.checks[]` → **EARS** acceptance criteria in **Requirements**.
- `artifact.sections[]` → the three-file body.

## Frontmatter contract

`genre: kiro-spec`, `audience: implementer`, `status`, `evidence_base`, optional `spec:` block;
MIF `Citation` objects.

## Section taxonomy (three files, held fixed)

1. **Requirements** — user stories + **EARS** acceptance criteria (one `WHEN … SHALL …` per goal
   check, with the verify command). Grounded in surviving findings.
2. **Design** — the technical approach: components, data flow, interfaces, and the grounded
   evidence (`finding_ref` or named standard per claim).
3. **Tasks** — an ordered, checkboxed build sequence; each task names its acceptance criterion
   and the files it touches, so an agent executes it without re-deriving intent.

## EARS form

```text
AC-<n>  WHEN <trigger>, THE SYSTEM SHALL <behaviour>.  Verify: <goal-check verify command>.
```

## Authoring rules

Deterministic (same findings → byte-identical Markdown); markdownlint-clean; every Design claim
grounded; every Task traces to a Requirement.
