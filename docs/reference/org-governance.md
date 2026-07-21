---
id: reference-org-governance
type: semantic
created: '2026-06-29T13:48:43-04:00'
modified: '2026-07-21T11:25:19.747Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: org governance & release runbooks"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-29T13:48:43-04:00'
  ttl: P6M
  recordedAt: '2026-06-29T13:48:43-04:00'
provenance:
  '@type': Provenance
  agent: claude-code/claude-fable-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:6cffe5d9-0ff6-4850-a402-01fd4a85a0d9
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.216
---

# Reference: org governance & release runbooks

This repository follows the shared governance, CI, and release process of the
[`modeled-information-format`](https://github.com/modeled-information-format) organization. Those
processes are maintained once, centrally, in the org
[`.github`](https://github.com/modeled-information-format/.github) repository and apply to every
repo that adopts the attested-delivery backbone — including this one. The runbooks below are the
authoritative, governing process; this page makes them reachable from here.

## Runbooks

| Runbook | What it governs |
| --- | --- |
| [Release runbook](https://github.com/modeled-information-format/.github/blob/main/docs/runbooks/release-runbook.md) | The required, audit-gated **attested release process**: punch-list audit, epics + sub-issues, a decision log, a release workplan issue, one PR per epic under GitHub Flow, and the attested cutover. |
| [Branch-protection runbook](https://github.com/modeled-information-format/.github/blob/main/docs/runbooks/branch-protection-runbook.md) | The required-checks, single-review, and linear-history rules applied to protected branches. |
| [Dependabot auto-merge runbook](https://github.com/modeled-information-format/.github/blob/main/docs/runbooks/dependabot-automerge-runbook.md) | The policy and rollout for auto-merging **patch** Dependabot updates, approved by the org `automerge` App — minor/major and non-semver bumps stay manual for review. |
| [Labels runbook](https://github.com/modeled-information-format/.github/blob/main/docs/runbooks/labels-runbook.md) | The org-wide label taxonomy and the reusable label-sync that keeps every repo consistent. |

## Branch-protection review-bypass policy

`main`'s required-review rule grants **no** `bypass_pull_request_allowances`: no user, team, or
App may merge past the one-review requirement. Dependabot auto-merge does not need one — the org
`automerge` App **approves** patch Dependabot PRs, satisfying the review requirement rather than
bypassing it (see the Dependabot auto-merge runbook above). The retired
`modeled-information-format-ci` App (id `4139655`), superseded by the org's six least-privilege
Apps, was removed from the allowance list under
[#667](https://github.com/modeled-information-format/research-harness-template/issues/667). The
`branch-protection-governance` job in
[`ci.yml`](https://github.com/modeled-information-format/research-harness-template/blob/main/.github/workflows/ci.yml)
fails if any review-bypass allowance reappears.

## Reusable CI/release workflows

This repo's CI and release gates are **thin SHA-pinned callers** of the org's reusable workflows
in [`.github/.github/workflows/`](https://github.com/modeled-information-format/.github/tree/main/.github/workflows)
— SAST (CodeQL/Semgrep), SCA (OSV-Scanner), Trivy, Checkov, Scorecard, secrets, VEX, actionlint,
shellcheck, sign-and-attest, and verify-gates. The architecture is recorded in the org
[ADR-002: reusable quality-gate architecture](https://github.com/modeled-information-format/.github/blob/main/docs/adr/ADR-002-reusable-quality-gate-architecture.md).

The consumer side of the release policy — verifying a downloaded artifact's attestation — is in
[How to verify a release artifact](../how-to/verify-a-release.md); the repo's release security
policy is
[`SECURITY.md`](https://github.com/modeled-information-format/research-harness-template/blob/main/SECURITY.md).
