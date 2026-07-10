---
name: export
description: Build a MIF Container manifest (mif-package.json) plus resource files from a topic, for lossless transfer to another research-harness instance. Delegates to scripts/mif-container-export.sh. Never modifies reports/<topic>/.
argument-hint: "<topic> <output-dir> [--subset <in-scope-ids.json>] [--closure] [--source-instance <name>]"
allowed-tools:
  - Bash
  - Read
---

# Export

Builds a self-contained [MIF Container](../../docs/adr/0017-mif-container-instance-scoped-export-import-format.md)
(`mif-package.json` + resource files) from a registered topic, for lossless
transfer to another `research-harness-template` instance (ADR-0017). This
command is a thin delegator to `scripts/mif-container-export.sh` — it does not
implement export logic itself. Read-only against `reports/<topic>/`.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `<topic>` — required. Must already be registered in `harness.config.json`
  `topics[]` (see `/topics` to list them).
- `<output-dir>` — required. Must not already exist, or must be empty — the
  script refuses to write into a non-empty directory.
- `--subset <in-scope-ids.json>` — a path to a JSON array of `urn:mif:concept:...`
  ids to export (a **subset** export). Without this, every finding in the
  topic is exported (a **full** export).
- `--closure` — only meaningful with `--subset`: transitively expand the
  subset to every concept reachable via relationship edges, instead of
  marking an out-of-scope reference as a boundary. See
  `scripts/mif-container-resolve-scope.sh`'s own header for the closure-vs-
  marker precedence rule (ADR-0017 AD-4).
- `--source-instance <name>` — the `sourceInstance.namespace` to stamp on the
  manifest (used by the receiving instance's reconciliation policy, ADR-0017
  AD-6). Defaults to the topic's own namespace's first path segment (e.g.
  `harness` for `harness/<topic>`) if omitted — a reasonable default, but
  pass an explicit, stable value for a real cross-instance exchange.

## Behavior

```bash
bash scripts/mif-container-export.sh "$TOPIC" "$OUTPUT_DIR" \
  ${SUBSET:+--subset "$SUBSET"} ${CLOSURE:+--closure} ${SOURCE_INSTANCE:+--source-instance "$SOURCE_INSTANCE"}
```

The script fails closed (non-zero exit, named error on stderr, nothing written
under `<output-dir>`) on: an unregistered topic, a non-empty `<output-dir>`, a
missing/malformed `--subset` file, or any finding missing an
`ontology-map.json` entry (run `/ontology-review` first if so). A `--subset`
selector that resolves to **zero** findings is **not** a failure — it is a
valid, intentionally-supported export carrying just the (filtered)
`ontology-map.json` resource. On success it prints how many findings were
exported and under which scope (full/subset), and the finished
`<output-dir>/mif-package.json` has already been self-validated against
`schemas/mif-container.schema.json`.

## Next steps

After a successful export, point the user at:

```text
/import <output-dir> <destination-topic>              # apply it on the receiving instance
/import <output-dir> <destination-topic> --dry-run     # validate without writing, first
```

If the export command fails, surface the script's stderr message directly —
it already names the specific failure (unregistered topic, non-empty output
dir, missing ontology-map entry, etc.); do not paraphrase it away.
