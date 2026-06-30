---
name: feature-spec
description: Genre template for a GitHub Spec Kit single-capability feature spec authored for an AI coding agent. Use when the deliverable is one capability written for an agent to implement, narrower than an architecture spec and lighter than a Kiro three-file decomposition.
version: 0.1.0
---

# Genre Template: Feature Spec (Spec Kit)

A deliverable-genre template (SPEC §6d). `report-synthesizer` binds surviving findings
(`schemas/findings.schema.json`, from `reports/<topic>/`); the `ai-spec` channel renders it.
Modelled on the GitHub Spec Kit single-feature spec.

## Selection rule

Use `feature-spec` for **one capability** authored for a coding agent. For a cross-cutting
**structure** use `architecture-spec`; for a feature needing an explicit task breakdown use
`kiro-spec`.

## Three mappings

- `artifact.finding_refs[]` → the **Context / rationale** grounding.
- goal `completion_condition.checks[]` → the **Acceptance criteria** (EARS).
- `artifact.sections[]` → the spec body.

## Frontmatter contract

`genre: feature-spec`, `audience: implementer`, `status`, `evidence_base`, optional `spec:`
block; MIF `Citation` objects.

## Section taxonomy (held fixed)

1. **Summary** — the capability in one paragraph.
2. **Motivation / context** — why, grounded in surviving findings (`finding_ref` per claim).
3. **Behaviour** — the capability's behaviour and interface.
4. **Acceptance criteria (EARS)** — one `WHEN … SHALL …` per goal check, with the verify command.
5. **Out of scope** — explicit non-goals.
6. **Sources** — named standards and works.

## EARS form

```text
AC-<n>  WHEN <trigger>, THE SYSTEM SHALL <behaviour>.  Verify: <goal-check verify command>.
```

## Authoring rules

Deterministic; markdownlint-clean; every claim grounded; acceptance criteria executable.
