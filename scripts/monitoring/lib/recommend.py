#!/usr/bin/env python3
"""Recommendation Engine (research-harness-template#420).

Two modes, matching the architecture doc:

  interest-match  Rank Interest-Inference-scored candidates
                   (research-harness-template#419) above a threshold.
  gap-detect       Reuse .claude/skills/discover's own coverage-gap logic
                   (config-declared dimensions vs research-index.json counts)
                   rather than reimplementing knowledge-graph traversal, and
                   turn each real gap into a recommendation to research it.

NFR5 is a hard invariant, not a convention: every recommendation this module
produces carries at least one MIF citation traceable to a source finding,
concordance entity, or (for a TF-IDF-fallback match with no existing
corpus coverage) the candidate's own primary source. `_require_citations`
raises if that invariant is ever violated, so a citation-less recommendation
is not merely discouraged, it is structurally unable to leave this module.
"""
import json
import sys


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


def interest_match(scored_candidates, threshold=0.02):
    """Rank candidates already annotated by interest_inference.py."""
    recs = []
    for c in scored_candidates:
        inference = c.get("inference", {})
        score = inference.get("score", 0.0)
        if score < threshold:
            continue
        matched_nodes = inference.get("matched_nodes", [])
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
        url = c.get("url") or ""
        if url:
            citations.append({"type": "primary-source", "url": url})
        citations += [{"type": "concordance-node", "target": n} for n in matched_nodes]
        if not citations:
            # A connector's API contract doesn't always guarantee a
            # non-empty url (verified: semantic-scholar.sh's does not).
            # Skip this one candidate rather than let _require_citations
            # crash the entire interest-match run over it.
            continue
        rec = {
            "mode": "interest-match",
            "source": c.get("source"),
            "id": c.get("id"),
            "title": c.get("title"),
            "url": c.get("url"),
            "published": c.get("published"),
            "score": score,
            "inference_method": inference.get("method"),
            "citations": citations,
        }
        recs.append(_require_citations(rec))
    recs.sort(key=lambda r: -r["score"])
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


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("interest-match", "gap-detect"):
        print(
            "usage: recommend.py interest-match <scored-candidates.json> [threshold]\n"
            "       recommend.py gap-detect <harness.config.json> <research-index.json>",
            file=sys.stderr,
        )
        return 2

    mode = sys.argv[1]
    if mode == "interest-match":
        candidates = load_json(sys.argv[2])
        threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.02
        recs = interest_match(candidates, threshold)
    else:
        config = load_json(sys.argv[2])
        index = load_json(sys.argv[3])
        recs = gap_detect(config, index)

    json.dump(recs, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
