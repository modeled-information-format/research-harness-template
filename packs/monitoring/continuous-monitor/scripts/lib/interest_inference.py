#!/usr/bin/env python3
"""Interest-Inference Engine (research-harness-template#419, #514).

Scores each candidate item (schemas/monitoring-candidate.schema.json) with
two first-class, topic-anchored signals:

1. Topic-scoped concordance overlap: candidates are matched against the
   labels of the monitored topic's OWN concordance nodes (nodes whose
   `topics` array contains the --topic id), never the whole corpus. The
   corpus-global matching this replaced made any candidate sharing two
   tokens with any label anywhere in a mature multi-topic corpus score as
   an "interest match" (#514) -- a pure-mathematics paper "matched" a
   git-notes topic via an agriculture-technology node.
2. Query-term matching: the topic's own queryTerms (the same terms that
   seeded this run's connectors) are matched as atomic phrases against the
   candidate's title/summary. This is a primary signal, not a fallback --
   under the pre-#514 design queryTerms were consulted only when the
   concordance produced zero matches, which at corpus scale never happened.

The final score is the stronger of the two. Only when neither signal
matches does the dependency-light TF-IDF fallback fire (NFR4: the topic
isn't represented in the graph yet), computed over the candidate batch
itself as the reference corpus (no external corpus needed).

Usage:
  interest_inference.py <candidates.json> <concordance.json> \
      [--topic <topic-id>] [--] <query-terms...>

<query-terms...> are the terms the run's Source Connectors searched for
(typically the topic's continuousMonitoring.queryTerms). --topic scopes
concordance matching to that topic's nodes; omit it only when the passed
concordance is already scoped to a single topic (e.g. an eval fixture).

Prints the candidates array, each annotated with an "inference" object:
  { method: "concordance" | "query-terms" | "tfidf-fallback", score: float,
    matched_nodes: [concordance node id, ...],
    matched_terms: [query term, ...] }
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


def build_concordance_index(concordance, topic=None):
    """One (token-set, node) pair per non-flagged node, for overlap scoring.

    When `topic` is given, only nodes whose `topics` array contains it are
    indexed (#514): interest scoring for topic T must reflect T, not
    whatever else the corpus happens to know about."""
    index = []
    for node in concordance.get("nodes", []):
        if node.get("flagged"):
            continue
        if topic is not None and topic not in (node.get("topics") or []):
            continue
        label_tokens = set(tokenize(node.get("label", "")))
        if label_tokens:
            index.append((node["id"], label_tokens))
    return index


MIN_LABEL_OVERLAP = 2  # a single shared common word (e.g. "data") is noise,
                        # not a real interest signal; require a real overlap.


def concordance_score(candidate_tokens, index):
    """Overlap ratio (Jaccard-lite: |intersection| / |candidate|) against
    every indexed (topic-scoped) concordance node whose label shares at
    least MIN_LABEL_OVERLAP tokens, plus the ids of every node that matched
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


def query_term_score(candidate_tokens, query_terms):
    """Fraction of query terms the candidate matches, plus the matched
    terms. A term matches when every one of its tokens appears in the
    candidate's tokens -- token-subset rather than raw substring, so
    punctuation/case/word-order variants of a phrase still count, while a
    term contributing no tokens (all stopwords/too short) never matches."""
    if not query_terms:
        return 0.0, []
    cand_set = set(candidate_tokens)
    matched = []
    scorable = 0
    for term in query_terms:
        term_tokens = set(tokenize(term))
        if not term_tokens:
            continue
        scorable += 1
        if term_tokens <= cand_set:
            matched.append(term)
    if scorable == 0:
        return 0.0, []
    return len(matched) / scorable, matched


def tfidf_fallback_scores(candidates, query_terms):
    """Query-likelihood TF-IDF (NFR4: dependency-light, no external corpus):
    score(d) = sum over query TOKENS t of tf(t, d) * log(N / df(t)), where N
    and df are computed over this run's own candidate batch. Terms are
    tokenized the same way candidates are -- a raw multi-word phrase would
    never equal any single token and would contribute nothing (part of how
    queryTerms ended up dead weight pre-#514)."""
    n = len(candidates)
    if n == 0:
        return []
    query = sorted({tok for term in query_terms for tok in tokenize(term)})
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


def parse_args(argv):
    if len(argv) < 3:
        return None
    candidates_path, concordance_path = argv[1], argv[2]
    rest = argv[3:]
    topic = None
    if rest[:1] == ["--topic"]:
        if len(rest) < 2:
            return None
        topic = rest[1]
        rest = rest[2:]
    if rest[:1] == ["--"]:
        rest = rest[1:]
    return candidates_path, concordance_path, topic, rest


def main():
    parsed = parse_args(sys.argv)
    if parsed is None:
        print(
            "usage: interest_inference.py <candidates.json> <concordance.json> "
            "[--topic <topic-id>] [--] <query-terms...>",
            file=sys.stderr,
        )
        return 2
    candidates_path, concordance_path, topic, query_terms = parsed

    candidates = load_json(candidates_path)
    concordance = load_json(concordance_path)
    index = build_concordance_index(concordance, topic)

    tfidf_scores = tfidf_fallback_scores(candidates, query_terms)

    annotated = []
    for candidate, tfidf_score in zip(candidates, tfidf_scores):
        tokens = tokenize(candidate_text(candidate))
        c_score, matched_nodes = concordance_score(tokens, index)
        q_score, matched_terms = query_term_score(tokens, query_terms)
        if matched_nodes or matched_terms:
            if matched_nodes and c_score >= q_score:
                method, score = "concordance", c_score
            else:
                method, score = "query-terms", q_score
            inference = {
                "method": method,
                "score": round(score, 4),
                "matched_nodes": matched_nodes,
                "matched_terms": matched_terms,
            }
        else:
            inference = {
                "method": "tfidf-fallback",
                "score": round(tfidf_score, 4),
                "matched_nodes": [],
                "matched_terms": [],
            }
        annotated.append({**candidate, "inference": inference})

    json.dump(annotated, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
