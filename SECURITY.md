# Security Policy

## Verifying Release Artifacts

Every release artifact is published with a [SLSA](https://slsa.dev/) build-provenance
attestation, generated in `.github/workflows/release.yml` with
[`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance).
The attestation is signed through Sigstore; its signer identity is this
repository's own release workflow. The release pipeline re-verifies the
attestation before publishing, so a tag never publishes an unverified artifact.

To verify a downloaded release artifact yourself, pin verification to the
signing workflow:

```sh
gh attestation verify research-harness-template-<version>.tar.gz \
  --repo modeled-information-format/research-harness-template \
  --signer-workflow modeled-information-format/research-harness-template/.github/workflows/release.yml
```

`--repo` scopes trust to this repository; `--signer-workflow` additionally pins
trust to the specific workflow that produced the attestation — the certificate
identity is `.../.github/workflows/release.yml@refs/tags/<tag>` (the
`gh attestation verify` output shows this full ref-suffixed identity).
Verifying with both is the strict check; `--repo` alone would accept an
attestation from any workflow in the repository. A non-zero exit status means
verification failed — do not trust the artifact.

## Reporting a Vulnerability

Report security issues privately via
[GitHub Security Advisories](https://github.com/modeled-information-format/research-harness-template/security/advisories/new).
Please do not open a public issue for an undisclosed vulnerability.
