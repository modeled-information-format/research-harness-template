---
title: "How to author finding JSON with the model layer"
diataxis_type: how-to
---

# How to author finding JSON with the model layer

Agents that produce schema-bound JSON — findings (`dimension-analyst`,
`source-chunker`), verdicts and remediations (`falsification-analyst`) — author it
through the **model layer** in `lib/harness_models/`, never by composing JSON in the
shell. The emitted JSON is the contract; this path makes it deterministic and valid.

## Why not `jq -n` or heredocs

The Bash tool wraps every command in `eval`. A multi-line `jq -n '{ … }'` or a
`cat <<'EOF'` carrying real finding `content` breaks under that wrapper the moment
the text contains an unescaped parenthesis, quote, or colon — the command fails with
`syntax error near unexpected token '('`, or worse, emits malformed JSON. Authoring
in Python sidesteps the shell entirely: the content lives in Python strings, and
`json.dump` always produces syntactically valid output.

## The layer

- `lib/harness_models/<schema>.py` — `typing.TypedDict` shapes **generated** from
  `schemas/*.schema.json` by `scripts/codegen/gen-models.sh` (pure stdlib; do not
  hand-edit — change the schema and regenerate).
- `lib/harness_models/emit.py` — `dump_json` / `write`, the deterministic emitter:
  keys sorted, two-space indent, UTF-8 preserved, one trailing newline. Values are
  emitted faithfully (a present `null` is kept — some fields are required-and-nullable;
  to omit an optional field, leave its key out of the dict).

## Author a finding

Write a short script with the **Write tool** (its body is Python, so no shell
quoting applies), then run it:

Write the script to a **unique temp path** (e.g. `mktemp -t author-finding.XXXXXX.py`)
— analysts run concurrently from a shared cwd, so a fixed name would race — then
`python3 <that path> <staging-path>` and remove it.

```python
import sys
sys.path.insert(0, "lib")  # run from the repo root
from harness_models import emit
# from harness_models.findings import Mif  # the TypedDict shape (editor/type-check aid)

finding = {
    "@context": "https://mif-spec.dev/schema/context.jsonld",
    "@type": "Concept",
    "@id": "urn:mif:concept:<topic>:<slug>",
    "conceptType": "...",
    "content": "...",          # arbitrary prose — a Python string, never shell-quoted
    "created": "...",
    # Citation is a closed object: no @id; cite by live http(s) url (see finding.sample.json).
    "citations": [{"@type": "Citation", "citationType": "documentation",
                   "citationRole": "supports", "title": "...", "url": "https://..."}],
    "extensions": {"harness": {"dimension": "<dim>"}},
}
emit.write(finding, sys.argv[1])
```

Then validate and publish exactly as before — the analyst emits only its half of the
contract (no `extensions.harness.verification`; the falsification gate stamps that),
so it validates the fields it owns and atomically renames the staging file into
`reports/<topic>/findings/`.

## Mutate an existing finding (remediation)

Read it into Python, mutate the dict, and re-emit — do not `jq`-compose the change:

```python
import json, sys
sys.path.insert(0, "lib")
from harness_models import emit
f = json.load(open(sys.argv[1]))
f["provenance"]["trustLevel"] = "moderate_confidence"   # e.g. weakened downgrade
f.setdefault("citations", []).append({...})
emit.write(f, sys.argv[1])
```

## Regenerating models

When a schema changes, regenerate and commit:

```bash
bash scripts/codegen/gen-models.sh         # rewrites lib/harness_models/*.py
CHECK=1 bash scripts/codegen/gen-models.sh # CI uses this to fail on drift
```

The validity + determinism of every authored schema is asserted by the
`models-authoring` eval (`evals/test_models.py`, run from `evals/run-evals.sh`).
