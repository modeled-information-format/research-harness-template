---
title: "How to verify a release artifact"
diataxis_type: how-to
---

# How to verify a release artifact

This guide shows an adopter how to confirm that a downloaded release artifact
genuinely came from this repository's release workflow and was not tampered
with. It is the consumer side of the harness's attested-delivery policy. The
authoritative policy is [`SECURITY.md`](https://github.com/modeled-information-format/research-harness-template/blob/main/SECURITY.md); this guide does not
restate it, it walks the procedure.

## What guarantees the artifact

Every release artifact is a reproducible source tarball published with a
[SLSA](https://slsa.dev/) build-provenance attestation, signed through Sigstore.
The release pipeline **re-verifies the attestation before publishing**, so a tag
never publishes an unverified artifact. From `.github/workflows/release.yml`:

```yaml
- name: Verify attestation (fail-closed, before publish)
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    set -euo pipefail
    gh attestation verify "${{ steps.build.outputs.artifact }}" \
      --repo "${GITHUB_REPOSITORY}" \
      --signer-workflow "${GITHUB_REPOSITORY}/.github/workflows/release.yml"
```

That step's failure fails the job, so the upload step that follows never runs on
an unverified artifact. This is the "fail-closed" property: the producer applies
the same check you are about to run.

The actions in that workflow are SHA-pinned (for example
`actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`), so
the trusted build step cannot be swapped by a moved tag.

## Prerequisites

- `gh` (GitHub CLI) 2.x or newer, including the `attestation` subcommand —
  confirm with `gh --version` (see [dependencies](../reference/dependencies.md)).
- The downloaded artifact file, named
  `research-harness-template-<version>.tar.gz`.

## Steps

1. Download the release artifact from the GitHub release page.

2. Run the strict verification, pinning trust to both the repository **and** the
   signing workflow. This is the exact command from
   [`SECURITY.md`](https://github.com/modeled-information-format/research-harness-template/blob/main/SECURITY.md):

   ```sh
   gh attestation verify research-harness-template-<version>.tar.gz \
     --repo modeled-information-format/research-harness-template \
     --signer-workflow modeled-information-format/research-harness-template/.github/workflows/release.yml
   ```

3. Read the result:

   - **Exit status `0`** — verification passed. `gh attestation verify` prints
     the certificate identity, which ends in
     `.../.github/workflows/release.yml@refs/tags/<tag>`.
   - **Non-zero exit status** — verification failed. **Do not trust the
     artifact.** Per `SECURITY.md`: "A non-zero exit status means verification
     failed — do not trust the artifact."

## Why both flags

`--repo` scopes trust to this repository. `--signer-workflow` additionally pins
trust to the specific workflow that produced the attestation. Verifying with
both is the strict check; `--repo` alone would accept an attestation from any
workflow in the repository. Always pass both flags.

## Reporting a vulnerability

Report security issues privately via
[GitHub Security Advisories](https://github.com/modeled-information-format/research-harness-template/security/advisories/new),
as stated in [`SECURITY.md`](https://github.com/modeled-information-format/research-harness-template/blob/main/SECURITY.md). Do not open a public issue for
an undisclosed vulnerability.
