#!/usr/bin/env node
// mif-vendor-check.mjs — prove the vendored MIF schemas (schemas/mif/) are
// byte-identical to the MIF release pinned in schemas/mif/VENDOR.lock.
// Fail-closed. Node built-ins only.
//
//   node scripts/mif-vendor-check.mjs            # every file matches its pinned sha256
//   node scripts/mif-vendor-check.mjs --remote   # ...and the immutable mif-spec.dev
//                                                # mirror it was vendored from
//
// --remote keeps the pin from naming a MIF release that is not published (MIF
// docs/RELEASING.md §1f). It needs network access, so verify.sh runs the
// offline form (gate_mif_vendor) and CI's mif-vendor-check job runs --remote.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const lockPath = join(repoRoot, "schemas", "mif", "VENDOR.lock");
const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");

let lock;
try {
  lock = JSON.parse(readFileSync(lockPath, "utf8"));
} catch (e) {
  console.log(`::error::cannot read ${lockPath}: ${e.message}`);
  process.exit(1);
}
if (!Array.isArray(lock.files) || lock.files.length === 0 || !lock.source || !lock.mifSpecVersion) {
  console.log("::error::schemas/mif/VENDOR.lock is missing source, mifSpecVersion, or files[]");
  process.exit(1);
}
if (!lock.source.endsWith(`/${lock.mifSpecVersion}/`)) {
  console.log(`::error::VENDOR.lock source (${lock.source}) does not name mifSpecVersion ${lock.mifSpecVersion}`);
  process.exit(1);
}

let bad = 0;
for (const f of lock.files) {
  let got;
  try {
    got = sha256(readFileSync(join(repoRoot, f.path)));
  } catch (e) {
    bad++;
    console.log(`::error::vendored ${f.path} is unreadable (${e.code ?? e.message})`);
    continue;
  }
  if (got !== f.sha256) {
    bad++;
    console.log(`::error::vendored ${f.path} drifted from VENDOR.lock (got ${got.slice(0, 12)}…, want ${f.sha256.slice(0, 12)}…) — re-vendor from ${lock.source}, never hand-edit`);
  }
}

const remote = process.argv.includes("--remote");
if (remote) {
  for (const f of lock.files) {
    const url = new URL(f.upstream, lock.source).href;
    let got;
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      got = sha256(Buffer.from(await res.arrayBuffer()));
    } catch (e) {
      bad++;
      console.log(`::error::cannot fetch ${url} (${e.message}); is MIF ${lock.mifSpecVersion} published?`);
      continue;
    }
    if (got !== f.sha256) {
      bad++;
      console.log(`::error::${f.path} differs from ${url}`);
    }
  }
}

if (bad === 0) {
  console.log(`mif-vendor-check: ${lock.files.length} files match VENDOR.lock (MIF ${lock.mifSpecVersion}, ${lock.source})${remote ? " and the mirror" : ""}`);
}
process.exit(bad ? 1 : 0);
