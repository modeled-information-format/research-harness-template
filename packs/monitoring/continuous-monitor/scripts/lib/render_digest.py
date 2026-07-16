#!/usr/bin/env python3
"""Per-run monitoring digest renderer (research-harness-template#524).

Renders a run's recommendations.json into the structured, human-reviewable
digest the Editorial Gate reviews -- modeled on the weekly-research
reference's Roundup Seed: per candidate a headline, domain, dated key
facts, momentum evidence (source count + engagement), source URLs, and
prior-coverage status. The SAME digest serves both runtimes (#525): the
Actions path puts it in the review PR's body, the in-session path renders
it as a markdown artifact the operator reads before invoking the gate.

The first line is a versioned format marker (like the reference's
`Seed format: v1`) so downstream consumers can detect format drift instead
of silently misparsing.

Usage: render_digest.py <recommendations.json> <subject> <run-id>
"""
import json
import sys

DIGEST_FORMAT = "v1"


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def render(recs, subject, run_id):
    lines = []
    lines.append(f"<!-- Digest format: {DIGEST_FORMAT} -->")
    lines.append(f"# Monitoring digest: {subject} ({run_id})")
    lines.append("")

    interest = [r for r in recs if r.get("mode") == "interest-match"]
    gaps = [r for r in recs if r.get("mode") == "gap-detect"]

    if not recs:
        lines.append("No candidate recommendations this run.")
        lines.append("")
        return "\n".join(lines)

    lines.append(
        f"{len(interest)} candidate recommendation(s), {len(gaps)} coverage-gap "
        "suggestion(s). Merging the review PR (or an explicit in-session gate "
        "accept) accepts every item below; closing without merge rejects the "
        "whole batch to the Continuity Log."
    )
    lines.append("")

    for i, rec in enumerate(interest, start=1):
        momentum = rec.get("momentum") or {}
        sources = momentum.get("sources") or ([rec.get("source")] if rec.get("source") else [])
        lines.append(f"## {i}. {rec.get('title') or '(untitled)'}")
        lines.append("")
        domain = rec.get("domain")
        if domain:
            weight = rec.get("weight")
            weight_note = f" (weight {weight})" if weight is not None else ""
            lines.append(f"- **Domain:** {domain}{weight_note}")
        if rec.get("published"):
            lines.append(f"- **Published:** {rec['published']}")
        lines.append(
            f"- **Momentum:** {momentum.get('source_count', 1)} source(s)"
            f" [{', '.join(sources)}], engagement {momentum.get('engagement', 0)}"
        )
        lines.append(
            f"- **Relevance:** {rec.get('score', 0)}"
            f" via {rec.get('inference_method', 'unknown')}"
        )
        # Prior-covered items never reach recommendations.json (suppressed at
        # ranking, #523) -- everything in a digest is new by construction.
        # The explicit line keeps that fact reviewable rather than implicit.
        lines.append("- **Prior coverage:** none (new this run)")
        urls = [c.get("url") for c in rec.get("citations") or [] if c.get("url")]
        if urls:
            lines.append("- **Sources:**")
            for url in urls:
                lines.append(f"  - <{url}>")
        lines.append("")

    if gaps:
        lines.append("## Coverage-gap suggestions")
        lines.append("")
        for gap in gaps:
            lines.append(
                f"- **{gap.get('dimension')}**: {gap.get('finding_count', 0)} finding(s)"
                f" vs corpus mean {gap.get('corpus_mean', 0)} -- {gap.get('description', '')}"
            )
        lines.append("")

    return "\n".join(lines)


def main():
    if len(sys.argv) != 4:
        print(
            "usage: render_digest.py <recommendations.json> <subject> <run-id>",
            file=sys.stderr,
        )
        return 2
    recs = load_json(sys.argv[1])
    sys.stdout.write(render(recs, sys.argv[2], sys.argv[3]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
