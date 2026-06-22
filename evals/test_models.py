#!/usr/bin/env python3
"""Model-authoring evals: prove the harness_models layer emits deterministic,
schema-valid contract JSON for every authored schema.

For each schema with a fixture: load it, round-trip through harness_models.emit,
and validate the emitted bytes against the real schema with ajv (the validity
gate). Plus determinism (shuffled input -> identical bytes) and None-dropping.

Pure stdlib + ajv (already a CI/build dependency). Run from the repo root:
    python3 evals/test_models.py
Exit 0 iff all checks pass.
"""
from __future__ import annotations

import glob
import json
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "lib"))
from harness_models import emit  # noqa: E402

# schema (relative to schemas/) -> sample fixture (relative to repo root)
CASES = {
    "findings.schema.json": "schemas/samples/finding.sample.json",
    "concordance.schema.json": "schemas/samples/concordance.sample.json",
    "pack.schema.json": "schemas/samples/pack.sample.json",
    "session-state.schema.json": "schemas/samples/session-state.sample.json",
    "mif/ontology.schema.json": "schemas/samples/ontology-definition.sample.json",
    "mif/source-envelope.schema.json": "schemas/samples/source-envelope.sample.json",
    # goal/artifact ship no upstream sample; minimal fixtures live alongside this test.
    "goal.schema.json": "evals/fixtures/models/goal.sample.json",
    "artifact.schema.json": "evals/fixtures/models/artifact.sample.json",
}

MIF_REFS = glob.glob(os.path.join(ROOT, "schemas/mif/**/*.schema.json"), recursive=True)
passed = failed = 0


def report(ok: bool, name: str, detail: str = "") -> None:
    global passed, failed
    g, r, x = "\033[32m", "\033[31m", "\033[0m"
    if ok:
        passed += 1
        print(f"{g}  PASS {x} {name}")
    else:
        failed += 1
        print(f"{r}  FAIL {x} {name}  {detail}")


def ajv_valid(schema_rel: str, data_path: str) -> tuple[bool, str]:
    schema_abs = os.path.join(ROOT, "schemas", schema_rel)
    refs = [r for r in MIF_REFS if os.path.abspath(r) != os.path.abspath(schema_abs)]
    cmd = ["ajv", "validate", "--spec=draft2020", "--strict=false", "-c", "ajv-formats",
           "-s", schema_abs]
    for r in refs:
        cmd += ["-r", r]
    cmd += ["-d", data_path]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode == 0:
        return True, ""
    lines = (p.stderr or p.stdout).strip().splitlines()
    return False, lines[-1] if lines else f"ajv exited {p.returncode} with no output"


def main() -> int:
    tmp = tempfile.mkdtemp()
    for schema_rel, sample_rel in CASES.items():
        sample_path = os.path.join(ROOT, sample_rel)
        if not os.path.exists(sample_path):
            report(False, f"fixture-present:{schema_rel}", f"missing {sample_rel}")
            continue
        sample = json.load(open(sample_path))

        # 1. emitted output validates against the real schema
        out = os.path.join(tmp, schema_rel.replace("/", "_") + ".json")
        emit.write(sample, out)
        ok, detail = ajv_valid(schema_rel, out)
        report(ok, f"emit-validates:{schema_rel}", detail)

        # 2. determinism: shuffled top-level key order -> identical bytes
        items = list(sample.items())
        random.seed(1)
        random.shuffle(items)
        report(emit.dump_json(sample) == emit.dump_json(dict(items)),
               f"deterministic:{schema_rel}")

    # 3. a present null is preserved (required-nullable fields must keep their null,
    #    e.g. session-state attempted_at) — emit must not drop it
    report('"b": null' in emit.dump_json({"a": 1, "b": None}), "null-preserved")

    # 4. canonical form: single trailing newline
    s = emit.dump_json({"x": 1})
    report(s.endswith("\n") and not s.endswith("\n\n"), "trailing-newline")

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
