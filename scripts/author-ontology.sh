#!/usr/bin/env bash
# author-ontology.sh — when on-demand resolution finds no ontology for a domain,
# scaffold one FROM THE RESEARCH and concierge a PR to the canonical registry.
#
# The harness is a producer, not just a consumer: the entity types a topic's
# findings actually used (reports/<topic>/ontology-map.json) — especially the
# ones that fell back to the generic core — are the raw material for a new
# domain ontology. This drafts that ontology and prepares its contribution.
#
# Usage:
#   author-ontology.sh <new-id> <topic> [--out <file>] [--open-pr]
#   author-ontology.sh <new-id> --from-clusters <clusters.json> [--out <file>] [--open-pr]
#     <new-id>   id for the new ontology (e.g. clinical-trials)
#     <topic>    topic dir under reports/ to mine observed types from
#     --from-clusters  alternate input: instead of mining a topic's
#                ontology-map.json, read `mif-rh-cli expansion-candidates`
#                output (recurring tier-3 misses clustered by similarity; see
#                docs/adr/0015) and scaffold one draft candidate type per
#                cluster, quoting member excerpts and finding ids
#     --out      write the draft here (default: a temp file, path printed)
#     --open-pr  concierge: branch the ontologies repo, drop the draft, open a draft PR
#
# Grounding fields are stubbed TODO on purpose — a human (or a follow-up research
# pass) supplies the cited source vocabulary before the upstream PR merges.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"
command -v jq >/dev/null || { echo "author-ontology: jq required" >&2; exit 2; }

NEWID=""; TOPIC=""; OUT=""; OPEN_PR=0; CLUSTERS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --open-pr) OPEN_PR=1; shift;;
    --from-clusters) CLUSTERS="$2"; shift 2;;
    -*) echo "author-ontology: unknown flag $1" >&2; exit 2;;
    *) if [ -z "$NEWID" ]; then NEWID="$1"; elif [ -z "$TOPIC" ]; then TOPIC="$1"; fi; shift;;
  esac
done
[ -n "$NEWID" ] && { [ -n "$TOPIC" ] || [ -n "$CLUSTERS" ]; } \
  || { echo "usage: author-ontology.sh <new-id> <topic> [--out f] [--open-pr]" >&2
       echo "       author-ontology.sh <new-id> --from-clusters <clusters.json> [--out f] [--open-pr]" >&2; exit 2; }
# The two input modes are mutually exclusive: silently preferring one would
# leave the other argument doing nothing without any signal.
[ -n "$TOPIC" ] && [ -n "$CLUSTERS" ] \
  && { echo "author-ontology: give either a <topic> or --from-clusters, not both" >&2; exit 2; }

if [ -n "$CLUSTERS" ]; then
  # Alternate input: `mif-rh-cli expansion-candidates` output — recorded tier-3
  # misses clustered by mutual similarity (ADR-0015). Each cluster becomes one
  # draft candidate type for a human to name, define, and ground.
  [ -f "$CLUSTERS" ] || { echo "author-ontology: no such clusters file: $CLUSTERS" >&2; exit 1; }
  jq -e '.clusters | type == "array"' "$CLUSTERS" >/dev/null 2>&1 \
    || { echo "author-ontology: $CLUSTERS is not expansion-candidates output (no .clusters array)" >&2; exit 1; }
  jq -e '.clusters | all(type == "object" and (.members | type == "array"))' "$CLUSTERS" >/dev/null 2>&1 \
    || { echo "author-ontology: $CLUSTERS has malformed cluster entries (each needs an object with a members array)" >&2; exit 1; }
  ntypes=$(jq '.clusters | length' "$CLUSTERS")
  [ "$ntypes" -gt 0 ] || { echo "author-ontology: no clusters in $CLUSTERS" >&2; exit 1; }
  # basename only: ORIGIN lands in commit messages and PR bodies via
  # --open-pr, and a local temp path is provenance noise in a public artifact.
  ORIGIN="tier-3 expansion clusters ($(basename "$CLUSTERS"))"
else
  MAP="reports/$TOPIC/ontology-map.json"
  [ -f "$MAP" ] || { echo "author-ontology: no $MAP — run /ontology-review on '$TOPIC' first" >&2; exit 1; }

  # Mine distinct entity types the topic actually used; surface generic-fallback
  # ones first (they most want a domain home of their own).
  types_json=$(jq '[.[]? | {t: .entity_type, generic: ((.resolved_ontology // "") | startswith("mif-generic"))}]
                   | group_by(.t) | map({type: .[0].t, generic: (any(.[]; .generic))})
                   | sort_by(.generic | not)' "$MAP")
  ntypes=$(jq 'length' <<<"$types_json")
  [ "$ntypes" -gt 0 ] || { echo "author-ontology: no entity types found in $MAP" >&2; exit 1; }
  ORIGIN="research topic '$TOPIC'"
fi

# Portable temp: `mktemp -t <template>` is interpreted differently across
# implementations (BSD/BusyBox treat a non-trailing-X template inconsistently).
# `mktemp -d` is portable everywhere; we control the filename inside it.
[ -n "$OUT" ] || { tmpd="$(mktemp -d)" && OUT="$tmpd/$NEWID.ontology.yaml"; } \
  || { echo "author-ontology: mktemp failed" >&2; exit 1; }
{
  echo "---"
  if [ -n "$CLUSTERS" ]; then
    echo "# ${NEWID} ontology — DRAFT scaffolded from recurring tier-3 misses."
    echo "# Authored by scripts/author-ontology.sh --from-clusters ${CLUSTERS}"
    echo "# (mif-rh-cli expansion-candidates output; see docs/adr/0015)."
    echo "# TODO before contributing upstream: NAME each todo-cluster-N candidate for"
    echo "#   the concept its excerpts share, define it, fill its grounding"
    echo "#   (source_vocab / source_class / prior_art) with a cited authority, and"
    echo "#   refine base/traits/schema. disposition stays 'mint' for newly-minted types."
  else
    echo "# ${NEWID} ontology — DRAFT scaffolded from research topic '${TOPIC}'."
    echo "# Authored by scripts/author-ontology.sh from reports/${TOPIC}/ontology-map.json."
    echo "# TODO before contributing upstream: fill each entity type's grounding"
    echo "#   (source_vocab / source_class / prior_art) with a cited authority, and"
    echo "#   refine base/traits/schema. disposition stays 'mint' for newly-minted types."
  fi
  echo "ontology:"
  echo "  id: ${NEWID}"
  echo "  version: \"0.1.0\""
  echo "  description: \"DRAFT ${NEWID} domain ontology scaffolded from ${ORIGIN}\""
  echo "  extends:"
  echo "    - mif-base"
  echo "    - shared-traits"
  echo "entity_types:"
  if [ -n "$CLUSTERS" ]; then
    n=0
    jq -c '.clusters[]' "$CLUSTERS" | while IFS= read -r cl; do
      n=$((n+1))
      size=$(jq -r '.size // (.members | length)' <<<"$cl")
      runs=$(jq -r '.runs // 0' <<<"$cl")
      echo "  - name: todo-cluster-${n}"
      echo "    description: |-"
      echo "      TODO: name and define this candidate type — ${size} recurring tier-3 miss(es) across ${runs} run(s)."
      echo "      Member excerpts:"
      jq -r '[.members[]? | .content // ""] | .[0:3][] | gsub("[\r\n\t]"; " ") | .[0:140]' <<<"$cl" \
        | while IFS= read -r ex; do
        echo "      - \"${ex}\""
      done
      echo "      Member findings: $(jq -r '[.members[]?.finding_id] | unique | join(", ")' <<<"$cl")"
      echo "    base: semantic"
      echo "    traits:"
      echo "      - cited"
      echo "    schema:"
      echo "      required: []"
      echo "      properties: {}"
      echo "    source_vocab: TODO"
      echo "    source_class: TODO"
      echo "    prior_art: TODO"
      echo "    disposition: mint"
    done
  else
    jq -r '.[] | .type' <<<"$types_json" | while IFS= read -r t; do
      [ -n "$t" ] || continue
      echo "  - name: ${t}"
      echo "    description: \"TODO: define ${t} (observed in topic ${TOPIC})\""
      echo "    base: semantic"
      echo "    traits:"
      echo "      - cited"
      echo "    schema:"
      echo "      required: []"
      echo "      properties: {}"
      echo "    source_vocab: TODO"
      echo "    source_class: TODO"
      echo "    prior_art: TODO"
      echo "    disposition: mint"
    done
  fi
} > "$OUT"

if [ -n "$CLUSTERS" ]; then
  echo "author-ontology: drafted '$NEWID' with $ntypes candidate type(s) from clusters -> $OUT"
  echo "  (one todo-cluster-N per recurring tier-3 miss cluster — name, define, and ground each before contributing)"
else
  echo "author-ontology: drafted '$NEWID' with $ntypes entity type(s) -> $OUT"
  echo "  (generic-fallback types listed first — those most need a domain home)"
fi

if [ "$OPEN_PR" != 1 ]; then
  cat >&2 <<EOF

Next — contribute it upstream (concierge):
  1. Review/fill the TODO grounding in $OUT
  2. Re-run with --open-pr to branch the ontologies repo, drop the draft, regenerate
     the index, and open a draft PR — or do it by hand:
       cp "$OUT" <ontologies-repo>/ontologies/${NEWID}.ontology.yaml
       (cd <ontologies-repo> && scripts/gen-ontology-index.sh && \\
        git checkout -b feat/ontology-${NEWID} && git add -A && \\
        git commit -m "feat(ontology): add ${NEWID} (drafted from harness ${ORIGIN})" && \\
        gh pr create --draft --title "feat(ontology): ${NEWID}" --body "Drafted from harness ${ORIGIN}.")
EOF
  exit 0
fi

# --- concierge: open the PR (opt-in) ---------------------------------------
ONT_REPO="${MIF_ONTOLOGIES_REPO:-}"
[ -z "$ONT_REPO" ] && [ -d "$ROOT/../ontologies" ] && ONT_REPO="$ROOT/../ontologies"
[ -n "$ONT_REPO" ] && [ -d "$ONT_REPO/ontologies" ] || { echo "author-ontology: set MIF_ONTOLOGIES_REPO to the ontologies repo to --open-pr" >&2; exit 1; }
command -v gh >/dev/null || { echo "author-ontology: gh CLI required for --open-pr" >&2; exit 1; }

branch="feat/ontology-${NEWID}"
cp "$OUT" "$ONT_REPO/ontologies/${NEWID}.ontology.yaml"
( cd "$ONT_REPO" || exit 1
  if [ -x scripts/gen-ontology-index.sh ]; then bash scripts/gen-ontology-index.sh || exit 1; fi
  git checkout -b "$branch" \
  && git add -A \
  && git commit -q -m "feat(ontology): add ${NEWID} (drafted from harness ${ORIGIN})

Scaffolded by the research harness from ${ORIGIN}.
Grounding fields are TODO and must be filled with cited authorities before merge." \
  && git push -u origin "$branch" \
  && gh pr create --draft --title "feat(ontology): ${NEWID} (drafted from research)" \
       --body "Drafted by the research harness from ${ORIGIN}. $([ -n "$CLUSTERS" ] && echo 'Candidate types are recurring tier-3 classification misses clustered by similarity — each needs a real name, definition, and grounding before merge.' || echo "Entity types are the ones the topic's findings actually used (generic-fallback first).") Grounding (source_vocab/source_class/prior_art) is stubbed TODO and needs a cited authority before merge." ) \
  && echo "author-ontology: opened a draft PR for '$NEWID' in $ONT_REPO" \
  || { echo "author-ontology: concierge PR step failed (see output above)" >&2; exit 1; }
