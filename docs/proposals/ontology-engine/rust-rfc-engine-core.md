---
id: rfc-harness-ontology-engine-rust
type: semantic
created: '2026-07-01T00:00:00Z'
modified: '2026-07-01T00:00:00Z'
namespace: rfc/ontology-engine
title: 'RFC: harness-ontology-engine — a Rust engine core for ontology-review/resolve-ontology'
tags:
  - rfc
  - rust
  - ontology
  - cli
  - mcp
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-01T00:00:00Z'
  recordedAt: '2026-07-01T00:00:00Z'
  ttl: P6M
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  trustLevel: high_confidence
citations:
  - '@type': Citation
    citationType: documentation
    citationRole: background
    title: 'ripgrep — single static binary, no runtime deps CLI pattern'
    url: https://github.com/BurntSushi/ripgrep
    accessed: '2026-07-01'
relationships:
  - type: relates-to
    target: /docs/proposals/ontology-engine/ai-architecture-doc.md
  - type: relates-to
    target: /docs/proposals/ontology-engine/feature-spec.md
  - type: relates-to
    target: /docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: 'harness-ontology-engine (Rust)'
  entity_type: rfc-document
---

# RFC: harness-ontology-engine — a Rust engine core for ontology-review/resolve-ontology

## Summary

Propose `harness-ontology-engine`: a Rust workspace implementing the
ontology-review/resolve-ontology pair's engine core, plus a CLI and an MCP
server as thin frontends over it, per the scope in
`docs/proposals/ontology-engine/feature-spec.md`. This RFC details one
concrete implementation path for the engine-core language `AD-1` in
`docs/proposals/ontology-engine/ai-architecture-doc.md` explicitly deferred —
it argues for evaluating Rust seriously with real design detail, not a
one-paragraph sketch, and does not itself settle AD-1.

## Motivation

`docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md` and
`docs/proposals/ontology-engine/prd.md` already establish the problem this
proposal responds to: a full-corpus `ontology-review.sh` run against a real
4296-finding, 36-topic corpus took over 20 minutes, a process-spawn cost from
invoking `yq`/`jq`/`ajv` per finding; and the harness has no live cross-topic
semantic recall today. This RFC does not re-derive that motivation — it
exists because AD-1 identified a specific, concrete reason Rust might be the
right implementation language (local on-device embedding inference,
avoiding a network dependency at gate time, per `ai-architecture-doc.md`'s
AD-1, echoing ADR-0014's SDD-2 requirement that no index be a required
external service at gate time), and that reason deserves a real design, not
a deferred one-liner, before the language choice is settled.

## Guide-level explanation

A contributor or instance operator installs `harness-ontology-engine` as a
single binary — either `cargo install harness-ontology-engine`, or a prebuilt,
checksum-verified static binary per platform, following this template's
existing pattern for pinned, verified external tool downloads
(`docs/adr/0008-attested-fail-closed-supply-chain.md`). The binary, `hoe`,
exposes three subcommands:

```bash
hoe review --topic ag-grants-research --strict --followup reports/_meta/ontology-followup.json
hoe resolve reports/ag-grants-research/findings/finding-x.json --topic ag-grants-research
hoe mcp-serve   # starts the MCP server (search, suggest_type, find_similar, corpus_stats)
```

Every existing bash caller — `.claude/commands/`, `.claude/agents/`,
`scripts/verify.sh`, `evals/run-evals.sh` — changes exactly one thing: the
binary name it invokes. Every flag, exit code, and stdout shape is identical
to `scripts/ontology-review.sh`/`scripts/resolve-ontology.sh` today (see
`feature-spec.md`'s Design section for the exact flag list). A contributor
who has never touched Rust never needs to — they run `hoe` exactly like they
ran the bash scripts.

## Reference-level explanation

**Workspace layout** — a Cargo workspace with three crates, mirroring
`ai-architecture-doc.md`'s "thin wrapper over the same engine core"
requirement for both frontends:

- `crates/engine-core` — `resolve()` and `review()`, index build/query. No
  CLI or MCP concerns; this crate has zero dependency on `clap` or any MCP
  wire-protocol crate.
- `crates/cli` — a `clap`-based CLI frontend calling `engine-core` directly.
- `crates/mcp-server` — the MCP server frontend, also calling `engine-core`
  directly, with no write access to `reports/` (per `feature-spec.md`'s
  acceptance criterion that `suggest_type` never auto-stamps a finding).

**Parsing** — `serde` for the YAML ontology packs (the direct in-process
replacement for what `yq` does today, per finding, as a subprocess) and
`serde_json` for findings/config (replacing `jq`). Note: the obvious YAML
choice, `serde_yaml`, was archived by its maintainer in March 2024 and is no
longer maintained upstream; implementation should evaluate a maintained fork
(e.g. `serde_yaml_ng` or `serde_norway`) rather than depending on the
archived crate as-is. This is the single largest expected source of the
speedup: N subprocess spawns per finding become N in-process deserializations
in one long-lived process.

**Schema validation** — the `jsonschema` crate validates each finding's
`entity` block against its resolved type's schema in-process, replacing the
per-finding `ajv` subprocess call.

**Full-text index** — `rusqlite`'s `bundled` feature statically links the
SQLite C library into the `hoe` binary (no runtime dependency on a system
`libsqlite3`), matching `ai-architecture-doc.md`'s AD-2 decision. The FTS5
index itself is one embedded database file on disk (not linked — stored),
no separate database service, rebuilt by `hoe review` exactly like
`ontology-map.json` is rebuilt today.

**Embedding + similarity** — `candle-core`/`candle-transformers` for local
on-device embedding inference, loading a small sentence-embedding model
(a distilled/quantized model in the tens-of-MB range, not a full LLM). This
is the concrete reason AD-1 flagged as favoring Rust: candle's local-inference maturity
avoids a network dependency at gate time, unlike an API-based embedding
call. Cosine similarity over the resulting vectors runs over a flat
in-memory/on-disk store (matching AD-2's "no vector DB needed at this
scale" call) — a hand-rolled loop or `ndarray`, since the operation itself
is simple at ~4300 vectors.

**Concurrency/locking** — the `fs4` crate (or equivalent flock-wrapping
crate) implements the exclusive review-lock file from `ai-architecture-doc.md`'s
AD-3. Stale-lock detection: on acquiring the lock, `hoe` first checks whether
the PID recorded in an existing lock file is still alive (e.g. via
`sysinfo` or a raw `kill(pid, 0)` check); if the holding process is dead, the
stale lock is cleared and the new run proceeds — this is the concrete answer
AD-3's own "must detect and clear a stale lock" consequence asked for.

**MCP wire protocol** — the MCP server needs a JSON-RPC-over-stdio (or
equivalent) implementation. This RFC does not name a specific crate here
with confidence one exists and is well-maintained at the time of
implementation; see Unresolved Questions.

**Testing** — `proptest` property-based tests exercise `resolve()`/`review()`
against the *same* fixture corpus already used by `scripts/verify.sh` and
`evals/run-evals.sh` (`feature-spec.md`'s acceptance criterion 2 requires
identical outcomes against those exact suites). Rather than duplicating those
fixtures in Rust, the test harness shells out to the existing bash fixtures
(`evals/fixtures/ontology/*.json`, the `verify.sh` gate_m12/gate_m24
constructed fixtures) and asserts the Rust CLI's output matches the bash
scripts' output byte-for-byte on the same inputs — one source of truth for
expected behavior during the parity-proof phase, never two forks of what
"correct" means.

## Drawbacks

- **Steeper learning curve than the status quo.** This template's entire
  existing toolchain is bash plus common CLI tools (`jq`, `yq`, `ajv`) that
  any contributor can read line-by-line with no special setup. Rust is a
  materially larger ask — a contributor fixing a bug in this one subsystem
  now needs Rust literacy, where before they needed only shell literacy.
- **candle is a younger ML ecosystem** than e.g. Python's `transformers`, or
  even Go's growing bindings to established C inference libraries.
  Embedding-model support and quantization tooling may require more manual
  work in Rust than a Python-based alternative would, and less community
  prior art to draw on when something doesn't work.
- **A new supply-chain surface.** A Cargo workspace with a `crates.io`
  dependency tree is a category of risk this template's bash-only approach
  never had. It must be reconciled with `docs/adr/0008-attested-fail-closed-supply-chain.md`'s
  fail-closed stance — SCA/dependency scanning for a Rust workspace, not
  just the existing pinned-tool-download verification the bash approach
  relies on.

## Rationale and alternatives

`ai-architecture-doc.md`'s AD-1 named Go as the live alternative: for an
API-based embedding call (rather than local inference), Go and Rust are
roughly equivalent, and Go iterates faster for a team without deep Rust
experience. This RFC picks Rust to detail specifically because of the
local-inference argument, and that argument deserves more than a restated
conclusion: Go's local-inference options are real but materially thinner
than candle's. `onnxruntime_go` (cgo bindings to Microsoft's ONNX Runtime)
can run a pre-exported ONNX embedding model locally, but it depends on a
non-Rust, non-Go C library shipped and version-matched per platform — a
harder-to-vendor, harder-to-statically-link dependency than a pure-Rust
crate, working against this RFC's single-static-binary goal (see Prior
art). `gorgonia` is a pure-Go tensor/autodiff library, but it is not itself
a model-loading or embedding-inference framework — using it for embedding
inference would mean hand-porting a model's forward pass, not loading a
pretrained one, a materially larger implementation lift than candle's
`candle-transformers` model-loading support. Neither Go option is
disqualifying, but neither is a like-for-like match to what candle offers
today; this is the concrete basis for Rust being the more mature choice
for local inference specifically, not because Go was rejected. AD-1
remains formally undecided until this RFC (or a parallel Go-specific RFC,
not yet written) is reviewed against it. Doing nothing (status quo) is
Option 1 in `ADR-0014` and is already rejected there on its own terms;
this RFC does not re-argue that.

## Prior art

`ripgrep` demonstrates the single-static-binary, zero-runtime-dependency
pattern this RFC follows: one Rust binary, trivially distributable, no
interpreter or VM required at the install site — the same shape
`harness-ontology-engine` proposes for `hoe`.

## Unresolved questions

- Which crate (or hand-rolled JSON-RPC-over-stdio implementation) backs the
  MCP server's wire protocol — this RFC deliberately does not name one with
  confidence, since the ecosystem here is new enough that naming a specific
  crate risks naming one that doesn't exist or isn't maintained by the time
  this is implemented.
- Which specific small embedding model to bundle or load — a concrete model
  choice (size, license, quantization) is out of scope for this RFC and
  needs its own evaluation once M1 (the parity-proof milestone, which needs
  no embeddings at all) is complete.
- Whether the binary vendors the embedding model weights (larger binary/
  download, no first-run network dependency) or fetches them on first use.
  `docs/adr/0012-on-demand-ontology-vendoring.md` already establishes a
  precedent worth following for exactly this kind of question — on-demand
  fetch, fail-closed sha256-verified against a pinned index — and this RFC
  flags it as the model to imitate for embedding weights, without deciding
  it here.

## Future possibilities

If the proof-of-concept succeeds and generalization is later authorized (a
decision `ADR-0014` explicitly defers and this RFC does not re-litigate),
the same `engine-core`/`cli`/`mcp-server` workspace shape could absorb the
five scripts `ADR-0014`'s Option 2 names as generalization candidates —
`check-shippable-typing.sh`, `build-concordance.sh`, `validate-concordance.sh`,
`reconcile-session.sh`, `synthesize-corpus.sh` — as additional `engine-core`
modules behind the same two frontends, rather than a second, separate
rewrite effort.
