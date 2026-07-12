#!/usr/bin/env python3
"""Interest-Inference Engine (research-harness-template#419).

Scores each candidate item (schemas/monitoring-candidate.schema.json) against
the harness's existing concordance (reports/concordance.json, AD-2) rather
than a separately maintained profile store: a candidate whose title/summary
overlaps a concordance node's label is "of interest" because the harness
already has a concept or entity about it. When a candidate has zero
concordance overlap (the topic isn't represented in the graph yet, NFR4),
falls back to a dependency-light TF-IDF score against the query terms that
seeded this run's connectors, computed over the candidate batch itself as
the reference corpus (no external corpus needed).

Usage:
  interest_inference.py <candidates.json> <concordance.json> <query-terms...>

<query-terms...> are the terms the run's Source Connectors searched for
(typically the topic's title/keywords) -- the TF-IDF fallback's query.

Prints the candidates array, each annotated with an "inference" object:
  { method: "concordance" | "tfidf-fallback", score: float,
    matched_nodes: [concordance node id, ...] }
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mif_tokenize import tokenize  # noqa: E402


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def candidate_text(candidate):
    return f"{candidate.get('title', '')} {candidate.get('summary', '')}"


def build_concordance_index(concordance):
    """One (token-set, node) pair per non-flagged node, for overlap scoring."""
    index = []
    for node in concordance.get("nodes", []):
        if node.get("flagged"):
            continue
        label_tokens = set(tokenize(node.get("label", "")))
        if label_tokens:
            index.append((node["id"], label_tokens))
    return index


MIN_LABEL_OVERLAP = 2  # a single shared common word (e.g. "data") is noise,
                        # not a real interest signal; require a real overlap.


def concordance_score(candidate_tokens, index):
    """Overlap ratio (Jaccard-lite: |intersection| / |candidate|) against
    every non-flagged concordance node whose label shares at least
    MIN_LABEL_OVERLAP tokens, plus the ids of every node that matched
    (citation backing, NFR5's downstream Recommendation Engine needs
    these). A one-token overlap on a generic word produces false-positive
    matches across nearly every candidate (verified empirically against
    live arXiv results); requiring at least two shared tokens keeps this a
    meaningful signal."""
    if not candidate_tokens:
        return 0.0, []
    cand_set = set(candidate_tokens)
    matched = []
    best_overlap = 0
    for node_id, label_tokens in index:
        overlap = len(cand_set & label_tokens)
        if overlap >= MIN_LABEL_OVERLAP:
            matched.append(node_id)
            best_overlap = max(best_overlap, overlap)
    score = best_overlap / len(cand_set) if cand_set else 0.0
    return score, matched


def tfidf_fallback_scores(candidates, query_terms):
    """Query-likelihood TF-IDF (NFR4: dependency-light, no external corpus):
    score(d) = sum over query terms t of tf(t, d) * log(N / df(t)), where N
    and df are computed over this run's own candidate batch. A legitimate
    vector-space relevance signal with zero external dependencies -- exactly
    what "TF-IDF/entity-overlap fallback" calls for when the concordance has
    no coverage yet."""
    n = len(candidates)
    if n == 0:
        return [0.0] * n
    query = [t.lower() for t in query_terms]
    doc_tokens = [tokenize(candidate_text(c)) for c in candidates]

    df = {t: 0 for t in query}
    for tokens in doc_tokens:
        token_set = set(tokens)
        for t in query:
            if t in token_set:
                df[t] += 1

    scores = []
    for tokens in doc_tokens:
        if not tokens:
            scores.append(0.0)
            continue
        tf_counts = {}
        for tok in tokens:
            tf_counts[tok] = tf_counts.get(tok, 0) + 1
        score = 0.0
        for t in query:
            tf = tf_counts.get(t, 0) / len(tokens)
            idf = math.log((n + 1) / (df[t] + 1)) + 1.0  # smoothed, always positive
            score += tf * idf
        scores.append(score)
    return scores


def main():
    if len(sys.argv) < 4:
        print(
            "usage: interest_inference.py <candidates.json> <concordance.json> "
            "<query-terms...>",
            file=sys.stderr,
        )
        return 2

    candidates_path, concordance_path = sys.argv[1], sys.argv[2]
    query_terms = sys.argv[3:]

    candidates = load_json(candidates_path)
    concordance = load_json(concordance_path)
    index = build_concordance_index(concordance)

    tfidf_scores = tfidf_fallback_scores(candidates, query_terms)

    annotated = []
    for candidate, tfidf_score in zip(candidates, tfidf_scores):
        tokens = tokenize(candidate_text(candidate))
        score, matched = concordance_score(tokens, index)
        if matched:
            inference = {
                "method": "concordance",
                "score": round(score, 4),
                "matched_nodes": matched,
            }
        else:
            inference = {
                "method": "tfidf-fallback",
                "score": round(tfidf_score, 4),
                "matched_nodes": [],
            }
        annotated.append({**candidate, "inference": inference})

    json.dump(annotated, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
