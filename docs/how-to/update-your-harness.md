---
diataxis_type: how-to
---

# How to update your harness safely

`scripts/update.sh` is the **only supported way** to pull later template
improvements into an already-instantiated clone. It verifies the provenance of
the target release **before** any template content is fetched and applied, and is
**fail-closed**: a verification miss aborts the update and nothing is applied.

Do **not** run `copier update` directly — that bypasses the provenance gate and
executes template `_tasks`/`_migrations` under `--trust` against an unverified
source.

## Prerequisites

- `git`, the GitHub CLI (`gh`) with `gh auth login` completed, `copier`, `gzip`,
  and `yq` on `PATH`.
- A **clean work tree** — commit or stash local changes first (`copier update`
  re-applies a diff and needs a clean tree).
- The upstream publishes an attested release (the template's `release.yml` does
  this automatically on every published release).

## Update

From the clone root:

```bash
bash scripts/update.sh
```

It will:

1. Resolve the latest release tag of the **pinned upstream template** and pin it to
   a concrete commit SHA. (The trust root — repository + release-workflow identity —
   is baked into `update.sh`, not taken from `.copier-answers.yml`; `_src_path` is
   read only to warn if your clone's recorded origin differs from it.)
2. Reproduce the release artifact from that tree and verify its SLSA
   build-provenance attestation, pinned to the repository **and** the release
   workflow identity (`gh attestation verify … --signer-workflow …`).
3. On success only, run `copier update --vcs-ref <verified-sha>` — so Copier
   applies exactly the bytes that were verified.

To update to a specific tag, or to pass extra Copier flags:

```bash
bash scripts/update.sh --target v1.2.3 -- --defaults
```

## When verification fails

A non-zero exit means **nothing was applied**. Either the target release is not
attested by the trusted release workflow (refuse to trust it), or — less
commonly — your local toolchain produced different archive bytes than the runner
did. The release artifact is a reproducible `git archive | gzip -n`, but tar
header format and the gzip OS byte can vary across git versions / platforms; if
the only signal is a digest mismatch on an otherwise-legitimate tag, that is a
reproducibility mismatch, not a provenance failure. See
[update-channel provenance model](../explanation/update-channel-provenance.md).

## Why this is the only supported path

The whole value of `copier update` over a snapshot engine is that it re-applies
template improvements to a live clone — but that channel runs template-supplied
code under `--trust`. The provenance gate is what *earns* that trust. Running it
in front of every update closes the one source-activity path the harness would
otherwise trust implicitly: its own update channel.
