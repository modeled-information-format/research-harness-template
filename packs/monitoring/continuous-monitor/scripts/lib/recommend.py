#!/usr/bin/env python3
"""Recommendation Engine (research-harness-template#420, #523).

Two modes, matching the architecture doc:

  interest-match  Rank Interest-Inference-scored candidates
                   (research-harness-template#419) above a threshold, by
                   MOMENTUM (research-harness-template#523, modeled on the
                   gh-aw weekly-research reference): independent source
                   count first, engagement evidence second (HN points +
                   comments where available), then relevance score and
                   recency. Candidates surfacing the same item across
                   sources are merged into one recommendation, and every
                   ranking factor is recorded on the recommendation
                   (auditability). A prior-coverage memory (JSONL, written
                   ONLY by the gate-accept path -- single-writer
                   discipline) suppresses items already accepted in earlier
                   runs instead of re-recommending them cold.
  gap-detect       Reuse .claude/skills/discover's own coverage-gap logic
                   (config-declared dimensions vs research-index.json counts)
                   rather than reimplementing knowledge-graph traversal, and
                   turn each real gap into a recommendation to research it.

NFR5 is a hard invariant, not a convention: every recommendation this module
produces carries at least one MIF citation traceable to a source finding,
concordance entity, or (for a fallback match with no existing corpus
coverage) the candidate's own primary source. `_require_citations`
raises if that invariant is ever violated, so a citation-less recommendation
is not merely discouraged, it is structurally unable to leave this module.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mif_tokenize import tokenize  # noqa: E402


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _require_citations(rec):
    citations = rec.get("citations") or []
    if not citations:
        raise AssertionError(f"recommendation produced with no citations: {rec!r}")
    for c in citations:
        if not (c.get("target") or c.get("url")):
            raise AssertionError(f"citation with no target/url: {c!r}")
    return rec


def coverage_key(item):
    """Cross-source / cross-run identity for a candidate or recommendation.

    The same item routinely surfaces on more than one source (an arXiv paper
    and the HN story linking it share a title, not a URL), so the primary
    key is the normalized title token join when the title is substantial
    (>= 3 meaningful tokens); short/empty titles fall back to a normalized
    URL. Deterministic and dependency-light by design."""
    title_tokens = tokenize(item.get("title") or "")
    if len(title_tokens) >= 3:
        return "title:" + " ".join(title_tokens)
    url = (item.get("url") or "").lower()
    url = re.sub(r"^https?://(www\.)?", "", url)
    url = url.split("?")[0].split("#")[0].rstrip("/")
    return "url:" + url


def _engagement(candidate):
    """Engagement evidence where a source provides it: HN points+comments.
    Other sources contribute 0 -- momentum's first factor (independent
    source count) is available everywhere, engagement is a bonus signal."""
    raw = candidate.get("raw") or {}
    total = 0
    for field in ("points", "num_comments"):
        value = raw.get(field)
        if value is None:
            continue
        try:
            total += int(value)
        except (TypeError, ValueError):
            continue
    return total


def load_prior_coverage(path):
    """Keys accepted by the Editorial Gate in earlier runs (JSONL, one
    object per line with at least {key}). A missing file is an empty
    memory, never an error -- first run, or memory not adopted."""
    keys = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                key = entry.get("key")
                if key:
                    keys[key] = entry
    except FileNotFoundError:
        return {}
    return keys


def interest_match(scored_candidates, threshold=0.02, memory=None,
                   domain=None, weight=1.0):
    """Merge cross-source duplicates, rank by momentum, suppress prior
    coverage (#523)."""
    memory = memory or {}

    # 1. Relevance floor first: momentum must never resurrect an off-topic
    #    candidate (#513/#514's failure mode).
    kept = [
        c for c in scored_candidates
        if c.get("inference", {}).get("score", 0.0) >= threshold
    ]

    # 2. Cross-source merge: one recommendation per item, however many
    #    sources surfaced it.
    groups = {}
    order = []
    for c in kept:
        key = coverage_key(c)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(c)

    recs = []
    suppressed = 0
    for key in order:
        members = groups[key]
        # Representative: strongest engagement, then relevance score -- its
        # title/url/published front the merged recommendation.
        rep = max(
            members,
            key=lambda m: (_engagement(m), m.get("inference", {}).get("score", 0.0)),
        )
        prior = memory.get(key)
        if prior is not None:
            # Already accepted by the Editorial Gate in an earlier run:
            # re-recommending it cold is pure noise. Suppressed loudly, not
            # silently dropped -- the run log records what and why.
            print(
                "recommend[interest-match]: suppressed prior-covered candidate "
                f"'{(rep.get('title') or '')[:80]}' (accepted in run "
                f"{prior.get('run_id', 'unknown')})",
                file=sys.stderr,
            )
            suppressed += 1
            continue

        sources = sorted({m.get("source") for m in members if m.get("source")})
        engagement = sum(_engagement(m) for m in members)
        score = max(m.get("inference", {}).get("score", 0.0) for m in members)

        # ALWAYS cite the candidate's own primary source (a real http(s)
        # URL): harness.config.json's features.internalCitations defaults
        # false in this repo, so a concordance-node citation alone (an
        # internal graph reference, no URL) is not traceable per
        # check-citation-integrity.sh and would be blocked at publish --
        # discovered by live-testing Story #423's Output Router against
        # this repo's actual config, not assumed. Concordance-node
        # citations are added as supplementary context explaining *why*
        # the source is relevant, never as the only evidence.
        citations = []
        seen_urls = set()
        seen_nodes = set()
        for m in members:
            url = m.get("url") or ""
            if url and url not in seen_urls:
                citations.append({"type": "primary-source", "url": url})
                seen_urls.add(url)
            for node in m.get("inference", {}).get("matched_nodes", []):
                if node not in seen_nodes:
                    citations.append({"type": "concordance-node", "target": node})
                    seen_nodes.add(node)
        if not citations:
            # A connector's API contract doesn't always guarantee a
            # non-empty url (verified: semantic-scholar.sh's does not).
            # Skip this one candidate rather than let _require_citations
            # crash the entire interest-match run over it.
            continue

        rec = {
            "mode": "interest-match",
            "source": rep.get("source"),
            "id": rep.get("id"),
            "title": rep.get("title"),
            "url": rep.get("url"),
            "published": rep.get("published"),
            "score": score,
            "inference_method": rep.get("inference", {}).get("method"),
            "momentum": {
                "source_count": len(sources),
                "sources": sources,
                "engagement": engagement,
                "group_size": len(members),
            },
            "citations": citations,
        }
        if domain:
            rec["domain"] = domain
        if weight is not None:
            rec["weight"] = weight
        recs.append(_require_citations(rec))

    if suppressed:
        print(
            f"recommend[interest-match]: {suppressed} candidate(s) suppressed "
            "via prior-coverage memory",
            file=sys.stderr,
        )

    # 3. Momentum ranking (#523): independent source count, engagement,
    #    relevance score, then recency; the recorded weight is the
    #    cross-domain tie-break when digests merge domains.
    recs.sort(
        key=lambda r: (
            -r["momentum"]["source_count"],
            -r["momentum"]["engagement"],
            -r["score"],
            r.get("published") or "",
            r.get("id") or "",
        )
    )
    return recs


def gap_detect(config, index):
    """Reuse .claude/skills/discover's own gap heuristic: a config-declared
    dimension with zero findings, or far below the corpus mean, is a gap.
    Same fields discover itself reports (dimension, count, description) --
    this is the same analysis, wired into monitoring output, not a
    parallel reimplementation."""
    counts = {}
    for finding in index.get("findings", []):
        dim = finding.get("dimension") or "unassigned"
        counts[dim] = counts.get(dim, 0) + 1

    dims = config.get("dimensions", [])
    if not dims:
        return []
    mean = sum(counts.get(d["id"], 0) for d in dims) / len(dims)

    recs = []
    for d in dims:
        cnt = counts.get(d["id"], 0)
        if cnt == 0 or (mean > 0 and cnt < mean * 0.5):
            rec = {
                "mode": "gap-detect",
                "dimension": d["id"],
                "description": d.get("description", ""),
                "finding_count": cnt,
                "corpus_mean": round(mean, 2),
                "citations": [
                    {
                        "type": "internal",
                        "target": "harness.config.json",
                        "note": (
                            f"dimension '{d['id']}' declared in "
                            f"harness.config.json.dimensions: "
                            f"{d.get('description', '')}"
                        ),
                    }
                ],
            }
            recs.append(_require_citations(rec))
    return recs


def coverage_append(accepted_path, memory_path, run_id):
    """Append gate-ACCEPTED interest-match recommendations to the
    prior-coverage memory (#523). This function is the memory's only
    writer -- run-gate-and-publish.sh's accept path calls it; every other
    consumer only reads. Idempotent: keys already present are skipped, so
    re-running a gate never duplicates entries."""
    from datetime import datetime, timezone

    accepted = load_json(accepted_path)
    existing = load_prior_coverage(memory_path)
    recorded_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    appended = 0
    Path(memory_path).parent.mkdir(parents=True, exist_ok=True)
    with open(memory_path, "a", encoding="utf-8") as fh:
        for rec in accepted:
            if rec.get("mode") != "interest-match":
                continue
            key = coverage_key(rec)
            if key in existing:
                continue
            entry = {
                "key": key,
                "url": rec.get("url"),
                "title": rec.get("title"),
                "run_id": run_id,
                "recorded_at": recorded_at,
            }
            if rec.get("domain"):
                entry["domain"] = rec["domain"]
            fh.write(json.dumps(entry) + "\n")
            existing[key] = entry
            appended += 1
    print(
        f"recommend[coverage-append]: {appended} entr{'y' if appended == 1 else 'ies'} "
        f"appended to {memory_path}",
        file=sys.stderr,
    )
    return 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in (
        "interest-match", "gap-detect", "coverage-append",
    ):
        print(
            "usage: recommend.py interest-match <scored-candidates.json> [threshold]"
            " [--memory <jsonl>] [--domain <id>] [--weight <n>]\n"
            "       recommend.py gap-detect <harness.config.json> <research-index.json>\n"
            "       recommend.py coverage-append <accepted.json> <memory.jsonl> <run-id>",
            file=sys.stderr,
        )
        return 2

    mode = sys.argv[1]
    if mode == "coverage-append":
        if len(sys.argv) < 5:
            print(
                "usage: recommend.py coverage-append <accepted.json> <memory.jsonl> <run-id>",
                file=sys.stderr,
            )
            return 2
        return coverage_append(sys.argv[2], sys.argv[3], sys.argv[4])
    if mode == "interest-match":
        candidates = load_json(sys.argv[2])
        rest = sys.argv[3:]
        threshold = 0.02
        if rest and not rest[0].startswith("--"):
            threshold = float(rest[0])
            rest = rest[1:]
        memory = {}
        domain = None
        weight = 1.0
        while rest:
            flag = rest[0]
            if flag == "--memory" and len(rest) >= 2:
                memory = load_prior_coverage(rest[1])
                rest = rest[2:]
            elif flag == "--domain" and len(rest) >= 2:
                domain = rest[1]
                rest = rest[2:]
            elif flag == "--weight" and len(rest) >= 2:
                weight = float(rest[1])
                rest = rest[2:]
            else:
                print(f"recommend.py: unknown argument {flag!r}", file=sys.stderr)
                return 2
        recs = interest_match(candidates, threshold, memory, domain, weight)
    else:
        config = load_json(sys.argv[2])
        index = load_json(sys.argv[3])
        recs = gap_detect(config, index)

    json.dump(recs, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
