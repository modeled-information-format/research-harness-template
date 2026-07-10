---
name: import
description: Apply a MIF Container manifest (mif-package.json) into a registered topic through the fail-closed import gate. Delegates to scripts/mif-container-import.sh. A failure at any step rejects the entire import, never a partial write.
argument-hint: "<container-dir> <topic> [--dry-run]"
allowed-tools:
  - Bash
  - Read
---

# Import

Applies a [MIF Container](../../docs/adr/0017-mif-container-instance-scoped-export-import-format.md)
(produced by `/export`, on this or another `research-harness-template`
instance) into a registered topic. This command is a thin delegator to
`scripts/mif-container-import.sh` — it does not implement import logic
itself.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `<container-dir>` — required. A directory containing `mif-package.json`
  plus every resource file it names (as produced by `/export`).
- `<topic>` — required. Must already be registered in `harness.config.json`
  `topics[]` — this gate imports **into** an existing topic, it does not
  create one (see `/topics` to list what's registered, or `/configure topics`
  to register a new one first).
- `--dry-run` — run the manifest/digest/ontology-binding validation steps and
  report the outcome without writing anything to `reports/`.

## Behavior

```bash
bash scripts/mif-container-import.sh "$CONTAINER_DIR" "$TOPIC" ${DRY_RUN:+--dry-run}
```

The gate runs a strict, ordered sequence (ADR-0017) — manifest schema
validation, per-resource + manifest-level digest verification, ontology-
binding compatibility against this instance's cataloged packs, an idempotent
upsert-by-`@id` write applying the per-field reconciliation policy (ADR-0017
AD-6 — falsification verdicts, session lineage, and each finding's own
provenance stay origin-scoped to THIS instance; tags union; everything else
takes the incoming value; the ontology-map resource itself is written
verbatim only for a full-scope export, since a subset export's ontology-map
only covers the exported ids and would otherwise delete typing for every
other finding already at the destination), then the deterministic
`knowledge-graph.json`/README/concordance rebuilders plus a candidate
cross-`@id` sameAs scan. **A failure at any step rejects the entire import —
never a partial write.**

A second import already running against the same topic fails closed on a
held lock (`reports/<topic>/.container.lock`) rather than racing. This lock
is import-side only — `/export` does not currently take it, so a concurrent
`/export` against a topic mid-import can read an inconsistent in-flight
snapshot (tracked as a follow-up, not yet fixed).

## Next steps

- If the import printed a candidate sameAs proposal
  (`reports/concordance-sameas-proposals.json` was written), tell the user
  it is a **reviewable proposal only** — nothing was merged automatically;
  they decide whether any of the flagged pairs are genuinely the same
  concept.
- If `--dry-run` succeeded, the next step is the same command without
  `--dry-run` to actually write.
- If the import failed, surface the script's stderr message directly — it
  already names the specific failure (digest mismatch, ontology-binding
  incompatibility, schema-invalid finding, held lock, etc.); do not
  paraphrase it away.
