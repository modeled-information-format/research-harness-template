#!/usr/bin/env python3
"""Shared tokenizer for the Interest-Inference Engine and Recommendation
Engine's gap-detection mode (research-harness-template#419, #420):
lowercase, strip non-alphanumeric, drop short/stopword tokens. Dependency-
light by design (NFR4) — stdlib only, no NLP library.

Usage: mif_tokenize.py < text   -> one lowercased token per line
"""
import re
import sys

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for",
    "with", "as", "is", "are", "was", "were", "be", "been", "being", "this",
    "that", "these", "those", "it", "its", "at", "by", "from", "into",
    "we", "our", "their", "they", "you", "your", "not", "no", "can",
    "will", "would", "could", "should", "may", "might", "than", "then",
    "so", "such", "which", "what", "when", "where", "who", "how", "if",
}

TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokenize(text):
    return [
        t for t in TOKEN_RE.findall(text.lower())
        if len(t) > 2 and t not in STOPWORDS
    ]


def main():
    text = sys.stdin.read()
    for tok in tokenize(text):
        print(tok)


if __name__ == "__main__":
    main()
