# Reference: contracts

The typed substrate every layer exchanges. All contracts live under `schemas/`.

## Findings — `schemas/findings.schema.json`

A finding **is** a MIF v1.0 memory unit (design spec §6c). The schema
`allOf`-extends the real vendored MIF schema (`schemas/mif/mif.schema.json`) with
two harness-local requirements (§8b):

- `citations` — a non-empty array of MIF Level 3 citations (citation-integrity).
- `extensions.harness` — `dimension` (the config-declared dimension) and
  `verification` (the adversarial-falsification verdict: one of `falsified`,
  `weakened`, `survived`, `inconclusive`, with a `verdict_basis`).

Validate with the vendored MIF closure registered:

```bash
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/findings.schema.json \
  -r schemas/mif/mif.schema.json \
  -r schemas/mif/definitions/entity-reference.schema.json \
  -d <finding>.json
```

## Manifest — `harness.config.schema.json`

The deploy contract. Required: `version`, `topics`, `dimensions`, `packs`.
`packs[].source` is either the `"bundled"` constant or an external/private
plugin object (`{type, url, ref}`). See `harness.config.json` for a sample.

## Pack — `schemas/pack.schema.json`

A pack is a Claude Code plugin. Required: `name`, `version`, `kind` (one of
`methodology`, `genre`, `channel`, `ontology`). `provides.skills` lists the
plugin's skills. The bundled plugins are listed in
`.claude-plugin/marketplace.json`.

**One plugin per skill** (see [pack-structure](../explanation/pack-structure.md)):
each skill is its own plugin under `packs/<pack>/<skill>/`, so a clone enables
exactly the skills it wants without adopting a whole pack. The pack directory
(`packs/reports/`, `packs/market-research/`, …) is a *family container*, not a
plugin; the plugins are its `<skill>/` subdirectories.

## Structured Data Protocol

See [STRUCTURED-DATA.md](../../schemas/STRUCTURED-DATA.md): write JSON with `jq`,
then validate immediately. A write is not complete until the artifact validates.

## Citation-integrity gate

`scripts/check-citation-integrity.sh <findings.json>` asserts every finding has
at least one well-formed, live citation and no `falsified` verdict. Exit 0 =
pass, exit 1 = violation (one diagnostic line per violation).

## Generic report — `reports/<topic>/<slug>.md` (MIF Level-3 markdown)

The canonical MIF Level-3 output and source of truth (SPEC §10). A report **is** a
MIF concept serialized as markdown: authoritative YAML frontmatter (the MIF fields
— `@id`, `conceptType`, `created`, `citations`, `provenance`,
`extensions.harness.{dimension,verification}`) over a Markdown body that becomes the
MIF `content`. `scripts/mif-project.sh <report.md>` projects frontmatter+body to
JSON and validates it against `findings.schema.json` (the **same bar as a finding**)
plus the citation-integrity gate — so a report carries a real, non-falsified
falsification verdict, exactly like a finding. `scripts/render-artifact.sh
<artifact.json> report <out.md> <verification.json>` emits it write-then-validated
(fails closed on a non-conformant report).

## Source envelope — `schemas/mif/source-envelope.schema.json`

The inbound boundary contract. A raw ingested source normalized into a MIF memory
unit: `allOf`-extends the vendored MIF schema with required `provenance.sourceType`
and `extensions.harness.source` (`url`, `fetchedAt`, `contentType`).
`scripts/wrap-source.sh` composes and validates one, refusing (non-zero) any source
that does not validate at L3 before an analyst consumes it.

## Exemption

A report is exempt from L3 only when its format is orthogonal to the result, and
only when **declared**: first-class channels in `harness.config.json`
`outputs[].mifExempt: true`, channel packs in `plugin.json` `mif.exempt: true`.
Genres are L3 by default; exemption is for orthogonal formats, never genres.
`verify.sh` `gate_m10` enforces all of the above and logs every exempt surface.

## Session state — `schemas/session-state.schema.json`

The crash-safe resume checkpoint (SPEC §6b). `scripts/reconcile-session.sh <reports-dir>`
derives `reports/<topic>/state.json` **purely from disk** — per
finding `{id, dimension, valid, attempted_at, verdict}`, per-dimension
`{total, done}`, and per completion-check `{check, passed}` — then prints the
remaining-work plan. A finding is **done** when it is schema-valid — validity
*requires* `extensions.harness.verification` with a verdict, so a valid finding has
already been through the falsification gate — and not `falsified` (a falsified
finding's dimension still needs a replacement). Invalid findings and `*.tmp`/hidden
partial writes are excluded from done-counts, so `/resume` never reworks completed
findings. Reconcile is byte-deterministic and idempotent (no
wall-clock field; sorted records) — two runs over the same disk produce identical
output. `scripts/write-finding.sh <src> <findings-dir> <name>` is the atomic-to-valid
primitive for placing an **already-valid** finding (e.g. an import): it lands in
`findings/` only after full-schema validation (stage + ajv + atomic rename). The
dimension-analyst stages its own *raw, pre-gate* findings into `findings/` the same
atomic way (stage + validate the fields it owns + rename) — those are not
full-schema-valid until the falsification gate stamps a verdict, so they go through
the analyst's inline atomic write, not `write-finding.sh`. Reconcile **fails safe**:
if ajv cannot validate a known-good sample it aborts non-zero and writes no
checkpoint, so a broken toolchain never produces a "re-run everything" plan; callers
treat a non-zero reconcile as "stop", never "everything remaining". `verify.sh`
`gate_m11` asserts all of this — including against the real shipped sample session
and under a broken ajv.

## Ontology — `schemas/mif/ontology.schema.json`

The ontology definition contract (`schemas/mif/ontology.schema.json`), vendored
verbatim from MIF and checksum-locked in `schemas/mif/VENDOR.lock` (the trust root;
ontology *definitions* are unlocked/editable — only the contract is locked). An
ontology declares `entity_types` (each `{name, base,
schema:{required, properties}}`) and `relationships`. The **registry** is the set of
vendored ontology YAMLs — core under `schemas/ontologies/` (`mif-generic` built-in
generic types + `mif-base` scaffolding, always enabled for every topic) and the six
example **data packs** under `packs/ontologies/<id>/` (disabled by default). JSON is
projected from the yaml on the fly (`yq -o=json | ajv`); none is committed, so there
is no drift. `scripts/sync-packs.sh` writes the **catalog** (`.claude/enabled-packs.json`
`ontologies[]`) = core (always) + the ontologies enabled in `harness.config.json`
`ontologies[]`. A topic binds ontologies via `topics[].ontologies[]`; only an enabled
(cataloged) ontology may be bound, and an extended ontology applies **only** to topics
that bind it.

`scripts/resolve-ontology.sh <finding> [--topic <id>]` is the topical resolver:
untyped findings pass (recorded `untyped`); a typed finding's `entity_type` must
resolve to exactly one of the topic's bound ontologies (0 → fail; >1 → needs an
explicit `ontology.id`), and its `entity` must satisfy that type's schema (additive —
required fields and declared field constraints enforced, extra fields allowed). The
mapping is recorded to `reports/<topic>/ontology-map.json`. It fails closed (a missing
catalog aborts) and is bash-3.2 portable. Classification — stamping a finding's
`entity_type` — is an upstream agent step (`dimension-analyst`, topic onboarding in
`/start`); the resolver and `gate_m12` are the deterministic floor. `gate_m12` asserts:
the contract validates its sample; every registry ontology validates; id@version is
unique; VENDOR.lock checksum-locks the contract only (ontology definitions unlocked);
the `ontology-manager` skill scaffolds a new valid ontology (registry extensible);
the resolver pass/fail matrix; fail-safe; binding
→ catalog → registry integrity; and the pack-enable path end to end.
