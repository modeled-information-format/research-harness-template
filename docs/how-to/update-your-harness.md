---
id: how-to-update-your-harness
type: semantic
created: '2026-06-25T07:30:10-04:00'
modified: '2026-07-21T11:12:43.391Z'
namespace: docs/how-to
tags:
  - documentation
  - how-to
title: "How to update your harness safely"
diataxis_type: how-to
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-25T00:00:00Z'
  recordedAt: '2026-07-21T00:00:00Z'
  ttl: P6M
provenance:
  '@type': Provenance
  agent: claude-code/claude-fable-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:6cffe5d9-0ff6-4850-a402-01fd4a85a0d9
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.216
---

# How to update your harness safely

`scripts/update.sh` is the **only supported way** to pull later template
improvements into an already-instantiated clone. It verifies the provenance of
the target release **before any template content is applied to your clone**, and is
**fail-closed**: a verification miss aborts the update and nothing is applied.
(The target tag is fetched into a throwaway temp repo to reproduce and verify the
release artifact; your clone is never touched — `copier update` is not invoked —
unless verification passes.)

Do **not** run `copier update` directly — that bypasses the provenance gate and
executes template `_tasks`/`_migrations` under `--trust` against an unverified
source.

## Prerequisites

- `git`, the GitHub CLI (`gh`) with `gh auth login` completed, `copier`, `gzip`,
  and `yq` on `PATH`.
- A **clean work tree** — commit or stash local changes first (`copier update`
  re-applies a diff and needs a clean tree).
- The upstream publishes an attested release (the template's `release.yml` does
  this automatically on every version-tag push).

## Update

From the clone root:

```bash
bash scripts/update.sh
```

It will:

1. Resolve the latest release tag of the **pinned upstream template** and pin it to
   a concrete commit SHA. (The trust root — repository + release-workflow identity —
   is baked into `update.sh`, not taken from `.copier-answers.yml`.)
2. Reproduce the release artifact from that tree and verify its SLSA
   build-provenance attestation, pinned to the repository **and** the release
   workflow identity (`gh attestation verify … --signer-workflow …`). If the
   local reproduction misses verification, it falls back to the signed release
   asset and verifies that the extracted content matches the pinned commit.
3. On success only: run `copier update --vcs-ref <verified-sha>` — so Copier applies
   exactly the bytes that were verified (a git SHA is content-addressed, so the applied
   content is the verified content regardless of which path `_src_path` names). Then, if
   your clone's recorded `_src_path` lags an org move, **heal it** to the pinned upstream
   in `.copier-answers.yml` so future runs target it directly rather than relying on the
   redirect — that one-line rewrite lands in the same update diff you review and commit.
   (The heal must run *after* `copier update`, which refuses a dirty work tree.)

To update to a specific tag, or to pass extra Copier flags:

```bash
bash scripts/update.sh --target v1.2.3 -- --skip-answered
```

`--skip-answered` (`-A`) makes the update non-interactive while keeping the
answers recorded in `.copier-answers.yml`; Copier only prompts for questions
that are new in the target version. Two flag families are rejected by
`update.sh` rather than forwarded:

- `--vcs-ref`/`-r` — would defeat the verify-then-pin guarantee above.
- `--defaults` (`-l`/`-f`) — on `copier update` it resolves every question to
  its schema-declared default instead of your recorded answer, silently
  resetting the instance's customizations (topics, packs, voice profile) to
  template stock.

## After updating

A successful `scripts/update.sh` run applies the verified template content, but
three things do not happen automatically.

- **Confirm the update applied cleanly.** Run `bash scripts/verify.sh` and
  confirm it exits `0`. This re-checks every contract, including the merged
  manifest, against the version you just pulled in.
- **Re-fetch the engine binary if its pinned version moved.** An update can
  bring in a newer `scripts/fetch-engine.sh` with a higher pinned
  `ENGINE_VERSION`, but it does not install the binary itself. Run
  `scripts/fetch-engine.sh` again after every update; it is a no-op if the
  pinned version has not changed. See
  [Run the classification engine loop](../run-the-classification-engine-loop/).
- **Expect a "registry index sha256 changed" refusal on the first re-vendor
  after an upstream registry change.** If the update landed newer ontology
  core or domain pack versions, `scripts/fetch-ontology.sh` treats the
  registry index as a pinned trust root and refuses to fetch once that index
  moves, naming the fix directly in its own error. This is expected after a
  registry change, not a sign of tampering: clear the `index_sha256` field in
  `ontologies.lock.json`, then re-run the fetch to deliberately re-pin. See
  [Vendor ontologies on demand](../vendor-ontologies-on-demand/).

## When verification fails

A non-zero exit means **nothing was applied**. `update.sh` already handles the
reproducibility-mismatch case by verifying the downloaded signed release asset
and content-checking it against the pinned commit. So if it still exits non-zero,
the release either is not attested by the trusted release workflow, the expected
asset was missing, or the release asset's extracted content did not match the
pinned commit. See
[update-channel provenance model](../../explanation/update-channel-provenance/).

## Why this is the only supported path

The whole value of `copier update` over a snapshot engine is that it re-applies
template improvements to a live clone — but that channel runs template-supplied
code under `--trust`. The provenance gate is what *earns* that trust. Running it
in front of every update closes the one source-activity path the harness would
otherwise trust implicitly: its own update channel.
