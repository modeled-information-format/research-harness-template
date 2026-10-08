#!/usr/bin/env bash
# mif-ids-check.sh — regression eval for the MIF 1.4 id tooling:
# scripts/mif-id.sh (scripts/lib/mif_id.py), scripts/migrate-mif-ids.py and the
# reconcile-session.sh legacy-corpus guard.
#
# Proves, against hermetic temp files (never the real reports/ tree):
#   1. mif-id.sh mints the org-wide id (uuid5 in the mif-spec.dev namespace of
#      the legacy remainder), is idempotent, and passes reserved/bare-UUID input
#      through unhashed
#   2. migrate-mif-ids.py rewrites ids in prose, inline HTML and autolinks,
#      appends the old id to EXISTING aliases (JSON + YAML block/flow lists)
#      instead of dropping it, names every templated/constructed id it cannot
#      rewrite, and is a no-op on a second run (aliases are never rewritten)
#   3. reconcile-session.sh refuses a pre-1.4 corpus (exit 4, no state.json)
#      instead of counting every finding as not done
#
# Run: bash evals/mif-ids-check.sh   (exit 0 = all assertions hold)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/mif-ids-eval.XXXXXX"); trap 'rm -rf "$T"' EXIT

# 1. The id rule.
want="$(python3 -c 'import uuid; print("urn:mif:" + str(uuid.uuid5(uuid.uuid5(uuid.NAMESPACE_URL, "https://mif-spec.dev"), "concept:harness/t:s")))')"
got1="$(scripts/mif-id.sh concept:harness/t:s)"
got2="$(scripts/mif-id.sh urn:mif:concept:harness/t:s)"
got3="$(scripts/mif-id.sh "$got1")"
if [ "$got1" = "$want" ] && [ "$got2" = "$want" ] && [ "$got3" = "$want" ]; then
  ok "mif-id.sh mints uuid5(NS, remainder) for remainder and legacy-URN input, idempotently"
else
  no "mif-id.sh rule wrong: '$got1' / '$got2' / '$got3' (want $want)"
fi
if [ "$(scripts/mif-id.sh entity:org:acme)" = "urn:mif:entity:org:acme" ] \
   && [ "$(scripts/mif-id.sh urn:mif:entity:org:acme)" = "urn:mif:entity:org:acme" ] \
   && [ "$(scripts/mif-id.sh 7614bd9f-a688-586e-9a11-a4acbd543100)" = "urn:mif:7614bd9f-a688-586e-9a11-a4acbd543100" ]; then
  ok "reserved (with or without urn:mif:) and bare-UUID input pass through unhashed"
else
  no "reserved or bare-UUID input was hashed into a new id"
fi

# 2. The migration tool.
A="$(scripts/mif-id.sh concept:ns:a)"; B="$(scripts/mif-id.sh concept:ns:b)"; R="$(scripts/mif-id.sh report:ns/t:r)"
cat > "$T/doc.md" <<'EOF'
---
'@id': urn:mif:report:ns/t:r
aliases:
  - first-alias
---

See <code>urn:mif:concept:ns:a</code> and <urn:mif:concept:ns:b>.
Placeholder urn:mif:concept:<ns>:<slug>; built 'urn:mif:concept:' + ns.
EOF
printf -- '---\n"@id": urn:mif:report:ns/t:q\naliases: [one, two]\n---\nbody\n' > "$T/flow.md"
printf '{"@id":"urn:mif:concept:ns:a","aliases":["a-old"],"x":1}\n' > "$T/f.json"
python3 scripts/migrate-mif-ids.py --write --aliases "$T/doc.md" "$T/flow.md" "$T/f.json" >/dev/null 2>"$T/err1"
if grep -qF "<code>$A</code>" "$T/doc.md" && grep -qF "<$B>" "$T/doc.md" && grep -qF "'@id': $R" "$T/doc.md"; then
  ok "ids inside inline HTML and autolinks are rewritten"
else
  no "an id in inline HTML/autolink was not rewritten: $(sed -n '7p' "$T/doc.md")"
fi
if grep -qxF '  - first-alias' "$T/doc.md" && grep -qxF '  - urn:mif:report:ns/t:r' "$T/doc.md" \
   && grep -qxF 'aliases: [one, two, urn:mif:report:ns/t:q]' "$T/flow.md" \
   && [ "$(jq -c '.aliases' "$T/f.json")" = '["a-old","urn:mif:concept:ns:a"]' ]; then
  ok "the old id is appended, in order, to existing aliases (YAML block, YAML flow, JSON)"
else
  no "existing aliases lost or reordered the old id"
fi
if grep -q 'NOT migrated.*urn:mif:concept:<' "$T/err1" && grep -q "NOT migrated.*urn:mif:concept:'" "$T/err1"; then
  ok "templated and constructed ids are named on stderr, never skipped silently"
else
  no "skipped ids were not reported: $(cat "$T/err1")"
fi
cp -R "$T" "$T.before"
python3 scripts/migrate-mif-ids.py --write --aliases "$T/doc.md" "$T/flow.md" "$T/f.json" >/dev/null 2>&1
if python3 scripts/migrate-mif-ids.py "$T/doc.md" "$T/flow.md" "$T/f.json" >/dev/null 2>&1 \
   && diff -r "$T.before" "$T" >/dev/null 2>&1; then
  ok "a second run is a no-op (legacy ids recorded in aliases are never rewritten)"
else
  no "a second run changed already-migrated files"
fi
rm -rf "$T.before"

# 3. The reconcile guard.
mkdir -p "$T/topic/findings"
jq '."@id" = "urn:mif:concept:harness/topic:legacy"' schemas/samples/finding.sample.json > "$T/topic/findings/a.json"
scripts/reconcile-session.sh "$T/topic" >/dev/null 2>"$T/err2"
rc=$?
if [ "$rc" -eq 4 ] && [ ! -e "$T/topic/state.json" ] && grep -q 'migrate-mif-ids.py' "$T/err2"; then
  ok "reconcile-session refuses a pre-1.4 corpus (exit 4, nothing written, names the migration)"
else
  no "reconcile-session did not refuse a legacy corpus (rc=$rc)"
fi

echo "mif-ids eval: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
