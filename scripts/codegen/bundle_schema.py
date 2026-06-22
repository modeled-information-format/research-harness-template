#!/usr/bin/env python3
"""Stdlib JSON-Schema bundler: inline external whole-file $refs into #/$defs with
ref-rebasing. Offline (no network); resolves placeholder URL $ids against vendored
local files. Cycle-safe (refs become local pointers, never materialized values)."""
import json, os, re, sys

def camel(name):
    stem = re.sub(r"\.schema\.json$", "", os.path.basename(name))
    return "".join(p.capitalize() for p in re.split(r"[-_./]", stem) if p)

def load(path):
    with open(path) as f:
        return json.load(f)

def build_registry(schema_root):
    by_id, by_path = {}, {}
    for dp, _, files in os.walk(schema_root):
        for fn in files:
            if fn.endswith(".schema.json"):
                p = os.path.abspath(os.path.join(dp, fn))
                s = load(p)
                by_path[p] = s
                if "$id" in s:
                    by_id[s["$id"]] = p
    return by_id, by_path

def resolve_ext(ref, cur_dir, by_id, by_path):
    """Map an external (non-#) ref to (absolute local file path, fragment).

    fragment is "" or a JSON pointer like "/$defs/Inner" (no leading #), preserved
    so a sub-path ref resolves into the inlined sub instead of collapsing to the
    whole file. Raises a clear error when the target cannot be resolved locally.
    """
    base, _, frag = ref.partition("#")
    if ref.startswith("http://") or ref.startswith("https://"):
        if base in by_id:
            return by_id[base], frag
        raise KeyError(f"unresolvable URL $ref (no vendored $id): {ref}")
    # relative file path
    path = os.path.abspath(os.path.join(cur_dir, base))
    if path not in by_path:
        raise KeyError(f"unresolvable file $ref (not found under schema root): {ref} -> {path}")
    return path, frag

def bundle(target_path, schema_root):
    by_id, by_path = build_registry(schema_root)
    target_path = os.path.abspath(target_path)
    root = json.loads(json.dumps(by_path[target_path]))  # deep copy
    defs = root.setdefault("$defs", {})
    # path -> defs key, for every external schema we pull in
    keyed = {}

    def ensure(path):
        if path in keyed:
            return keyed[path]
        key = camel(path)
        # de-dup key
        base, n = key, 2
        while key in defs or key in keyed.values():
            key = f"{base}{n}"; n += 1
        keyed[path] = key
        sub = json.loads(json.dumps(by_path[path]))
        sub_dir = os.path.dirname(path)
        # Strip $id/$schema so the inlined sub does NOT open a new resolution
        # scope — every #/$defs/<key>/... pointer then resolves against the root.
        sub.pop("$id", None); sub.pop("$schema", None)
        # rebase the sub-schema's OWN internal refs under #/$defs/<key>/...
        rewrite(sub, sub_dir, internal_prefix=f"#/$defs/{key}")
        defs[key] = sub
        return key

    def rewrite(node, cur_dir, internal_prefix="#"):
        if isinstance(node, dict):
            if "$ref" in node and isinstance(node["$ref"], str):
                ref = node["$ref"]
                if ref.startswith("#"):
                    # internal ref: rebase only when inside an inlined sub-schema
                    if internal_prefix != "#":
                        node["$ref"] = internal_prefix + ref[1:]
                else:
                    p, frag = resolve_ext(ref, cur_dir, by_id, by_path)
                    key = ensure(p)
                    # Re-append the fragment, rebased into the inlined sub at
                    # #/$defs/<key> (the sub's own defs were rebased the same way).
                    node["$ref"] = f"#/$defs/{key}" + frag
            # snapshot: ensure() inserts into root["$defs"] while we may be iterating
            # it — list() avoids "dictionary changed size during iteration".
            for v in list(node.values()):
                rewrite(v, cur_dir, internal_prefix)
        elif isinstance(node, list):
            for v in node:
                rewrite(v, cur_dir, internal_prefix)

    rewrite(root, os.path.dirname(target_path), internal_prefix="#")
    return root

if __name__ == "__main__":
    target, schema_root, out = sys.argv[1], sys.argv[2], sys.argv[3]
    b = bundle(target, schema_root)
    with open(out, "w") as f:
        json.dump(b, f, indent=2)
    print(f"bundled {os.path.basename(target)} -> {out} (defs: {len(b.get('$defs',{}))})")
