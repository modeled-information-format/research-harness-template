---
title: "The cognitive triad: why an entity type's base is a closed set"
diataxis_type: explanation
citations:
  - "@type": Citation
    citationType: book
    citationRole: background
    title: "Tulving, E. (1972). Episodic and semantic memory. In E. Tulving & W. Donaldson (Eds.), Organization of Memory (pp. 381-403). Academic Press."
    url: "https://search.worldcat.org/title/313204"
  - "@type": Citation
    citationType: article
    citationRole: background
    title: "Tulving, E. (1985). How many memory systems are there? American Psychologist, 40(4), 385-398."
    url: "https://doi.org/10.1037/0003-066X.40.4.385"
  - "@type": Citation
    citationType: book
    citationRole: background
    title: "Tulving, E. (1983). Elements of Episodic Memory. Oxford University Press."
    url: "https://global.oup.com/academic/product/9780198521259"
  - "@type": Citation
    citationType: article
    citationRole: background
    title: "Tulving, E. (2002). Episodic memory: From mind to brain. Annual Review of Psychology, 53, 1-25."
    url: "https://doi.org/10.1146/annurev.psych.53.100901.135114"
---

# The cognitive triad: why an entity type's base is a closed set

Every MIF entity type declares a **base**: one of `_semantic`, `_procedural`, or
`_episodic`. Those three are not a convenient bucketing the harness invented. They are
the memory systems established in Endel Tulving's cognitive psychology, and the harness
treats them as a principled, **closed** taxonomy. This page explains what the three
are, why nothing is added to them, and the base-versus-namespace distinction the rule
turns on.

## The three systems

- **`_semantic`** — decontextualised facts and concepts: knowledge *that* something is
  so, independent of where or when it was learned (Tulving, 1972).
- **`_episodic`** — specific, time-and-place-stamped experiences: a record of *what
  happened*, bound to its context (Tulving, 1972; 1983).
- **`_procedural`** — skills and operations: knowing *how* to do something, expressed
  in performance rather than recollection. Tulving sets procedural, semantic, and
  episodic memory in a single hierarchy (Tulving, 1985).

The partition is an empirical claim about how memory is organised, argued and defended
across decades of work, most directly in "How many memory systems are there?"
(Tulving, 1985).

## The triad is closed

Because the three are a research-backed account of the memory systems, the harness does
not add a fourth. Introducing a new base — say `_analytical` — would assert a memory
system the science does not recognise, and every consumer of the base (ontology
resolution, the cognitive-namespace roots, and interoperability with anything else
MIF-typed) would inherit that unfounded claim. How many systems there are is precisely
the question Tulving (1985) answers; the harness adopts that answer rather than
re-opening it.

## Base versus namespace

The rule turns on a distinction:

- A **base** is the cognitive commitment. It is a closed set of exactly three, and it
  is *not* a hierarchy you can hang children off. Introducing `analytical` as a "child"
  of one of the three would still be using `analytical` as a base value, only nested —
  and that is the category error. "Analytical" describes *how a thing was derived* (a
  method, a kind of provenance); a base records *which memory system the thing is*.
  Derivation method and memory system are different axes, and making one a sub-node of
  the other corrupts the taxonomy.
- A **namespace** can be anything, because it is organisational labelling *under* a
  root. Grouping foresight types at `_semantic/foresight/...` is fine: the grouping is
  descriptive and the base stays `_semantic`.

New domain vocabulary is therefore expressed as namespaces under a root, never as a new
base.

## Worked case: analytical outputs are semantic

The trend-analysis pack's `forecast`, `adoption-curve`, and `scenario` arrived from
research carrying a base of `analytical`. Conformed to the triad, all three are
`_semantic`:

- a **forecast** ("adoption reaches 50% by 2030") is a decontextualised declarative
  claim about the world;
- a **scenario** is a constructed possible-future, a knowledge artifact rather than a
  lived event;
- an **adoption-curve** is a model of a trajectory.

None is a lived, time-stamped experience (episodic) or a skill (procedural). That an
analysis produced them is provenance metadata; it does not change which memory system
the artifact belongs to. The `analytical` base was an error to conform, and the correct
base is `_semantic`.

## Why it matters here

The base is load-bearing: ontology resolution is fail-closed on it, the cognitive
namespace roots derive from it, and any other MIF-typed system reads it. A taxonomy
that grew a fourth or fifth base whenever a domain felt under-served would lose the very
property that makes it worth committing to — that every typed memory in the corpus
answers the same small, principled question about its own nature. The triad is fixed so
that commitment holds.
