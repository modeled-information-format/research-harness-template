---
title: "The update-channel provenance model"
diataxis_type: explanation
---

# The update-channel provenance model

The harness's differentiator over a snapshot engine is that `copier update`
re-applies later template improvements to an already-instantiated clone. That
update channel executes template-supplied code (`_tasks`/`_migrations`) under
`copier --trust`. Left unauthenticated, it is the one source-activity path the
harness would trust implicitly — so it gets the same fail-closed, cryptographically
verified treatment as every other input. `scripts/update.sh` (copied verbatim into
every clone, like `scripts/verify.sh`) is that gate.

## Why the gate cannot live inside Copier

Copier's update sequence clones the target template, regenerates the old version,
computes the user diff, runs **pre-migrations**, then applies. There is **no
pre-fetch verification hook**: the earliest author-controlled code is
pre-migrations, which run *after* the target is already checked out — and which
are supplied by the as-yet-unverified template, so using them to verify that
template is circular. The gate must therefore be a wrapper that runs **before**
Copier, and the update must be **pinned** to exactly the ref the wrapper verified.

## One verification primitive, everywhere

`update.sh` does not invent a trust mechanism. It reuses the **exact** primitive
already used by `release.yml`, CI, and `SECURITY.md`:

- `release.yml` builds a **reproducible source tarball** — `git archive --format=tar
  --prefix=<name>-<tag>/ <sha> | gzip -n` — from the tagged tree and attests it with
  SLSA build provenance (`actions/attest-build-provenance`, Sigstore/cosign under
  the hood; the signer identity is the release workflow).
- `update.sh` reproduces that same artifact locally from the target tree and runs
  `gh attestation verify <artifact> --repo <owner/repo> --signer-workflow
  <owner/repo>/.github/workflows/release.yml`. `--repo` scopes trust to the
  repository; `--signer-workflow` pins it to the certificate identity of the
  release workflow, so an attestation from any other workflow is rejected.

A miss exits non-zero and Copier is never invoked.

## Pinning closes the TOCTOU gap

The gate verifies a concrete commit SHA, then forces Copier to that SHA via
`--vcs-ref <sha>`. It never verifies "latest tag" and lets Copier independently
re-resolve "latest." Because a git SHA **is** the content hash of the tree, the
checkout Copier applies is the verified bytes by construction.

## Bootstrap trust (the self-update problem)

`update.sh` is itself template-managed, so a hostile update could try to rewrite
it (and its pinned `--signer-workflow` identity) to neuter the next check. This
holds because the **current**, trusted `update.sh` verifies the *incoming* release
against the current pinned identity **before** applying it — so an update not
signed by the release workflow is rejected before it can replace the verifier. The
trust root is the signer-workflow identity baked into the file and established once
at clone (TOFU); an update cannot silently weaken it without first passing a check
it cannot pass. For fleets, additionally run the same gate in org-controlled CI so
a locally tampered `update.sh` cannot bypass org policy.

## The one trade-off: reproducibility

Verifying by reproducing `git archive | gzip -n` requires the consumer's git/tar/
gzip to produce the same bytes as the runner. `release.yml` documents the same
caveat (tar header format, gzip OS byte). The upside is parity: the updater, CI,
and a human all run the identical `gh attestation verify` command. The failure mode
is benign and detectable — a legitimate tag fails *closed* on a byte mismatch
rather than passing something unverified.
