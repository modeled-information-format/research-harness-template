---
title: "Attested delivery and fail-closed supply-chain verification"
description: "Verify every downloaded artifact with an attestation-preferred waterfall over a pinned-checksum floor, refusing to install on a miss."
type: adr
category: security
tags: [supply-chain, slsa, provenance, attestation, fail-closed]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [GitHub Actions, SLSA, sigstore, cosign]
audience: [developers, architects]
related: [0001-four-layer-single-repository-architecture.md, 0005-packs-and-plugins-extension-model.md]
---

# ADR-0008: Attested delivery and fail-closed supply-chain verification

## Status

Accepted

## Context

### Background and Problem Statement

The harness downloads tools and dependencies in CI
(`.github/workflows/ci.yml`), and the template is itself distributed as releases.
The harness needs every downloaded artifact cryptographically verified, and it
must refuse to proceed when verification cannot be established — not warn and
continue (`README.md` "Supply-chain verification").

### Current Limitations

An unverified binary is a supply-chain hole: a tampered `yq` or a swapped release
artifact would execute inside the build with no challenge.

## Decision Drivers

### Primary Decision Drivers

1. Every raw binary the build downloads must be cryptographically verified.
2. A verification miss must fail the build — fail closed, never
   warn-and-continue.

### Secondary Decision Drivers

1. Prefer the strongest available proof (build provenance) but degrade to a
   defined floor when upstream publishes none.
2. Pin actions and tool versions so digests are stable and reproducible.

## Considered Options

### Option 1: Trust the download

**Description:** Fetch each tool by URL and run it without verification.

- **Advantages:** Zero ceremony.
- **Disadvantages:** Any upstream compromise or MITM executes unverified code in CI.
- **Risk Assessment:** technical high; schedule low; ecosystem high.

### Option 2: Checksum-only

**Description:** Pin a SHA-256 for every artifact and verify the bytes, with no provenance.

- **Advantages:** A pinned digest catches tampering of that exact artifact.
- **Disadvantages:** A checksum proves what the bytes are, not who built them or how — it carries no build provenance, so it cannot attest the artifact came from the expected, untampered pipeline.
- **Risk Assessment:** technical medium; schedule low; ecosystem medium.

### Option 3: Attestation-preferred waterfall with a pinned-checksum floor

**Description:** Prefer a GitHub build-provenance attestation; fall back to a pinned SHA-256 cross-checked against the upstream signed checksums; otherwise refuse to install.

- **Advantages:** Prefers a GitHub build-provenance attestation (`gh attestation verify`) — SLSA provenance backed by sigstore/cosign signing under the hood, the strongest proof of origin and build integrity; relaxes to a pinned SHA-256 only when upstream publishes no attestation (e.g. `mikefarah/yq`), and refuses to install if neither passes; package-manager installs (`npm`, `pip`/`pipx`) are registry-integrity-verified and actions are SHA-pinned.
- **Disadvantages:** The checksum floor is genuinely weaker than provenance; the waterfall documents this trade rather than hiding it.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 3: an attestation-preferred waterfall with a pinned-checksum
floor.** The build prefers a GitHub build-provenance attestation (SLSA provenance
via sigstore/cosign); when none exists it falls back to a pinned-SHA-256 checksum
cross-checked against the upstream signed checksums; if neither passes, it refuses
to install. The same posture governs release artifacts. Verification is
fail-closed: a miss fails the build, and nothing installs unverified. In
`ci.yml`, `yq` is pinned (not "latest") and lands on the checksum floor because
upstream publishes no attestation.

## Consequences

### Positive

1. No unverified binary ever runs in the build, and the strongest available proof
   is always used.
2. The floor keeps the policy enforceable even for upstreams that publish no
   provenance.

### Negative

1. Pinned versions and digests must be bumped deliberately as tools release.

### Neutral

1. The checksum floor's weaker guarantee is stated explicitly rather than implied
   away, so consumers know exactly what each artifact's verification proves.

## Decision Outcome

An attestation-preferred, fail-closed waterfall gives every downloaded artifact
the strongest available proof — SLSA build-provenance via sigstore/cosign when
present — and a pinned-checksum floor otherwise, refusing to install when neither
passes. The deliberate-bump maintenance cost is the price of a stable, verifiable
supply chain.

## Related Decisions

- [ADR-0001: Four-layer single-repository architecture](../0001-four-layer-single-repository-architecture/)
- [ADR-0005: Packs and plugins extension model](../0005-packs-and-plugins-extension-model/)

## Links

- `.github/workflows/ci.yml`
- `README.md` ("Supply-chain verification")

## More Information

- **Date:** 2026-06-23
- **Source:** `.github/workflows/ci.yml`, `README.md` ("Supply-chain verification")

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Attestation-preferred waterfall in CI | `.github/workflows/ci.yml` (yq verify step) | compliant |
| Fail-closed on verification miss | `.github/workflows/ci.yml` (`exit 1` branch) | compliant |
| SHA-pinned actions | `.github/workflows/ci.yml` | compliant |
| Policy documented for users | `README.md` ("Supply-chain verification") | compliant |

**Summary:** `ci.yml` implements the attestation-to-checksum waterfall with a fail-closed `exit 1` on a verification miss, pins the `yq` version and digest, and the policy is documented in `README.md`.

**Action Required:** None
