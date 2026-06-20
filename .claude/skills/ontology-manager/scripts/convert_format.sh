#!/usr/bin/env bash
# convert_format.sh - Convert MIF ontology between formats
#
# Usage:
#   convert_format.sh yaml2json <input.yaml> [output.json]
#   convert_format.sh json2yaml <input.json> [output.yaml]
#   convert_format.sh yaml2jsonld <input.yaml> [output.jsonld]
#
# Requires: yq, jq (no PyPI; yaml2jsonld emits a minimal @context via yq/jq)
set -euo pipefail

MODE="${1:?Usage: convert_format.sh <yaml2json|json2yaml|yaml2jsonld> <input> [output]}"
INPUT="${2:?Usage: convert_format.sh <mode> <input> [output]}"
OUTPUT="${3:-}"

if [[ ! -f "$INPUT" ]]; then
	echo "Error: File not found: $INPUT" >&2
	exit 1
fi

case "$MODE" in
yaml2json)
	# Default output: replace .yaml with .json
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${INPUT%.ontology.yaml}.ontology.json"
		[[ "$OUTPUT" == "$INPUT" ]] && OUTPUT="${INPUT%.yaml}.json"
	fi
	yq -o=json '.' "$INPUT" | jq '.' >"$OUTPUT"
	echo "Converted: $INPUT -> $OUTPUT"
	;;

json2yaml)
	# Default output: replace .json with .yaml
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${INPUT%.ontology.json}.ontology.yaml"
		[[ "$OUTPUT" == "$INPUT" ]] && OUTPUT="${INPUT%.json}.yaml"
	fi
	yq -P '.' "$INPUT" >"$OUTPUT"
	echo "Converted: $INPUT -> $OUTPUT"
	;;

yaml2jsonld)
	# Default output: replace .yaml with .jsonld
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${INPUT%.ontology.yaml}.ontology.jsonld"
		[[ "$OUTPUT" == "$INPUT" ]] && OUTPUT="${INPUT%.yaml}.jsonld"
	fi
	# yq/jq projection with a minimal JSON-LD envelope (no PyPI). The vendored
	# schemas/mif/ontology.context.jsonld carries the full @context for tooling.
	yq -o=json '.' "$INPUT" | jq '{
        "@context": "https://mif-spec.dev/schema/ontology/ontology.context.jsonld",
        "@type": "mif:Ontology"
      } + .' >"$OUTPUT"
	echo "Converted: $INPUT -> $OUTPUT"
	;;

*)
	echo "Error: Unknown mode '$MODE'" >&2
	echo "Modes: yaml2json, json2yaml, yaml2jsonld" >&2
	exit 1
	;;
esac
