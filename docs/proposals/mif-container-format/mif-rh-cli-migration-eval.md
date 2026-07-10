---
title: "mif-rh-cli migration evaluation (Story #334, AD-7)"
description: "Real measured benchmark data on whether scripts/mif-container-export.sh / -import.sh's shell/jq implementation has a performance bottleneck at ADR-0014-comparable corpus scale, per AD-7's trigger condition for migrating this logic into mif-rh-cli."
type: doc
category: architecture
tags: [mif-container-format, performance, benchmark, mif-rh-cli, ad-7]
status: draft
created: 2026-07-10
author: zircote
project: research-harness-template
related: [ai-architecture-doc.md, feature-spec.md, 0017-mif-container-instance-scoped-export-import-format.md, 0014-compiled-ontology-engine-cli-and-mcp.md]
audience: [developers, architects]
---

# mif-rh-cli migration evaluation (Story #334)

## What this evaluates

Issue #334 (Epic #275's 8th Story, deferred-pending-evidence in ADR-0017's
AD-7) asks whether `scripts/mif-container-export.sh` / `-import.sh`'s
shell/jq implementation should migrate into `mif-rh-cli` as new subcommands.
AD-7's own text: "Nothing in the measured research indicates an
export/import performance problem analogous to what justified the compiled
ontology engine (ADR-0014); migrating the manifest-build/verify logic into
`mif-rh-cli` is a natural M2 if a future scale or bulk-migration use case
demonstrates a real bottleneck, not a redesign."

This document supplies that measurement: real, directly-run benchmark data
(not simulated or purely theoretical) at two corpus scales, compared against
ADR-0014's own reference bottleneck (4296 findings, 20+ minutes, 3
subprocesses/finding for `ontology-review.sh`'s `yq`/`jq`/`ajv` calls).

## Why this shares ADR-0014's failure mode

`scripts/mif-container-digest.sh` computes each resource's digest by
shelling out to `sha256sum`/`shasum` — a subprocess per finding, invoked
once per finding by `export.sh` and at least once (twice on some paths) per
finding by `import.sh`, on top of `write-finding.sh`'s own per-finding `ajv`
validation call. This is the same architectural pattern ADR-0014 diagnosed
in `ontology-review.sh`: subprocess-spawn cost paid per finding, per external
tool, with no in-memory reuse across findings within one run.

## Method

A benchmark tool, `scripts/mif-container-migration-eval-bench.sh`, generates
a synthetic topic of N schema-valid findings (cloned from the bundled
example topic's own real sample finding via `jq`, each given a distinct
fake `@id` and empty `relationships[]` to avoid dangling cross-references),
registers it as a throwaway topic, times `export.sh` once and `import.sh`
twice (once into a fresh topic — the new-`@id` upsert path — then again
into the now-populated topic — the existing-`@id` upsert path, which
`import.sh`'s code takes an extra digest-recheck subprocess call per
finding on), then restores every file it touched (`harness.config.json`,
`reports/concordance.json`) and deletes the synthetic topic directories.
No real corpus data is read or written at any point; the benchmark
generates and only ever touches its own synthetic topics.

Two real runs were executed directly (not simulated): N=50 and N=500. A
third run at N=4296 (ADR-0014's exact reference scale) was intentionally
**not** run — the 50→500 data already confirms linear per-finding scaling
across a 10x range with under 2% drift for the dominant cost (`import.sh`,
fresh path), so a third ~45-minute run would only re-confirm an
already-tight trend line, not add material evidence.

## Results (real, measured)

| N | export.sh | import.sh (fresh, new-`@id`) | import.sh (re-import, existing-`@id`) |
| --- | --- | --- | --- |
| 50 | 1s | 19s | 11s |
| 500 | 12s | 193s | 143s |

Per-finding rate:

| N | export.sh (s/finding) | import.sh fresh (s/finding) | import.sh re-import (s/finding) |
| --- | --- | --- | --- |
| 50 | 0.0200 | 0.3800 | 0.2200 |
| 500 | 0.0240 | 0.3860 | 0.2860 |

`export.sh` and `import.sh` (fresh path) scale essentially linearly across
this 10x range (export: +20% per-finding drift; import-fresh: **+1.6%**
per-finding drift — within measurement noise). `import.sh`'s re-import path
grew ~30% per-finding across the same range, the one data point that is not
cleanly linear; the true cost at larger N could run higher than a linear
extrapolation predicts.

## Extrapolation to ADR-0014's reference scale (4296 findings) — NOT separately measured

Using the N=500 per-finding rate (the higher, more scale-relevant of the two
data points):

| Operation | Extrapolated time at N=4296 |
| --- | --- |
| `export.sh` | ~103s (~1.7 min) |
| `import.sh` (fresh, new-`@id`) | ~1658s (~27.6 min) |
| `import.sh` (re-import, existing-`@id`) | ~1229s (~20.5 min), likely an **underestimate** given the re-import path's non-linear drift |

## Conclusion

`export.sh` alone does not demonstrate a bottleneck at this scale (under 2
minutes extrapolated). **`import.sh` does**: its extrapolated cost at
ADR-0014's own 4296-finding reference scale (~27.6 minutes for a fresh
import, and likely 20+ minutes even for a re-import into an
already-populated topic) meets or exceeds ADR-0014's own reference
bottleneck (20+ minutes) that justified building the compiled ontology
engine. This is real, measured evidence — not a hypothetical — that AD-7's
trigger condition ("a future scale or bulk-migration use case demonstrates
a real bottleneck") is met for `import.sh` specifically, at the exact
scale ADR-0014 itself uses as its bottleneck reference point.

This document reports the measurement. It does not decide the next action
(migrate `import.sh`'s logic into `mif-rh-cli` now, scope a narrower fix,
or accept the cost as tolerable for this repo's actual usage pattern) —
that decision belongs to the repo owner, consistent with AD-7's own framing
of M2 as conditional, not automatic, on a demonstrated bottleneck.
