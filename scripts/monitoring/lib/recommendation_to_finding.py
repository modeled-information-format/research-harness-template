#!/usr/bin/env python3
"""Project an accepted, gate-stamped interest-match recommendation
(research-harness-template#420, #422) into a MIF finding
(schemas/findings.schema.json) for the Output Router
(research-harness-template#423) to hand to the harness's existing
publish-report/publish-blog skills -- no new output channel or schema.

Only interest-match recommendations are projected. gap-detect
recommendations are not: a coverage gap is a meta-observation about the
corpus itself, not a sourced claim, and has no real primary-source URL to
cite -- forcing one through the finding shape's citation-integrity gate
would mean fabricating a citation. Gap-detect recommendations are instead
surfaced separately (see output_router.py's write_gap_summary) as an
actionable suggestion, not committed to the findings corpus.

The projected finding's verification.verdict is "inconclusive" (a real,
valid value in schemas/findings.schema.json's enum) with a verdict_basis
explaining it has not yet been through a full adversarial /falsify pass --
Output Router materializes the finding and gates it on citation integrity,
it does not run (and cannot honestly claim to run unattended) the
LLM-driven falsification step publish-report's own pipeline performs.
"""
import json
import re
import sys


def slugify(text):
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:60] or "untitled"


def to_finding(rec, topic, namespace, now_iso):
    if rec.get("mode") != "interest-match":
        raise ValueError("only interest-match recommendations project to findings")

    slug = f"monitoring-{slugify(rec.get('title', rec.get('id', 'candidate')))}"
    # ONLY the primary-source citation becomes a MIF Citation. A
    # concordance-node reference is relevance-scoring metadata (why the
    # Interest-Inference Engine surfaced this candidate), not evidence for
    # the finding's own content -- putting an internal urn:mif: id into a
    # citation's `url` is neither a real http(s) URL nor (this repo's
    # harness.config.json ships features.internalCitations: false) an
    # accepted internal citation, and check-citation-integrity.sh correctly
    # rejects it (verified empirically: it failed all 11 real
    # recommendations from the first end-to-end run before this fix).
    # Matched concordance nodes are folded into `content` as descriptive
    # context instead.
    citations = [
        {
            "@type": "Citation",
            "url": c["url"],
            "title": rec.get("title", ""),
            "citationType": "article",
            "citationRole": "supports",
            "accessed": now_iso[:10],
        }
        for c in rec.get("citations", [])
        if c.get("type") == "primary-source" and c.get("url")
    ]
    matched_node_ids = [
        c["target"] for c in rec.get("citations", [])
        if c.get("type") == "concordance-node" and c.get("target")
    ]

    finding = {
        "@context": "https://mif-spec.dev/schema/context.jsonld",
        "@id": f"urn:mif:concept:{namespace}:{slug}",
        "@type": "Concept",
        "conceptType": "semantic",
        "title": rec.get("title", ""),
        "summary": rec.get("title", ""),
        "content": (
            f"Surfaced by continuous research monitoring (source: "
            f"{rec.get('source', 'unknown')}, published {rec.get('published', 'unknown')}). "
            f"Interest-Inference method: {rec.get('inference_method', 'unknown')}, "
            f"score {rec.get('score', 0)}. Primary source: {rec.get('url', '')}."
            + (
                f" Related to existing concordance concepts: {', '.join(matched_node_ids)}."
                if matched_node_ids
                else ""
            )
        ),
        "created": now_iso,
        "namespace": namespace,
        "tags": ["continuous-monitoring", rec.get("source", "unknown")],
        "citations": citations,
        "ontology": {"id": "mif-generic"},
        "entity": {"name": rec.get("title", "")[:80], "entity_type": "concept"},
        "extensions": {
            "harness": {
                "dimension": "landscape",
                "verification": {
                    "verdict": "inconclusive",
                    "verdict_basis": (
                        "Surfaced by continuous research monitoring "
                        "(research-harness-template#416); not yet run through "
                        "a full adversarial /falsify pass."
                    ),
                    "attempted_at": now_iso,
                },
            }
        },
    }
    return finding


def main():
    if len(sys.argv) < 5:
        print(
            "usage: recommendation_to_finding.py <recommendation.json> <topic> "
            "<namespace> <now-iso8601>",
            file=sys.stderr,
        )
        return 2
    with open(sys.argv[1], encoding="utf-8") as fh:
        rec = json.load(fh)
    topic, namespace, now_iso = sys.argv[2], sys.argv[3], sys.argv[4]
    json.dump(to_finding(rec, topic, namespace, now_iso), sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
