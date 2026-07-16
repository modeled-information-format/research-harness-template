# fetch-stub.sh — offline connector_fetch replacement for
# evals/monitoring-query-construction.sh, sourced by connector-common.sh via
# the CONNECTOR_FETCH_OVERRIDE eval seam. Records every requested URL to
# FETCH_URL_LOG (the eval asserts on the constructed queries, #513), then
# serves the matching recorded fixture instead of touching the network.
connector_fetch() {
  local url="$1"
  printf '%s\n' "$url" >> "${FETCH_URL_LOG:?fetch-stub needs FETCH_URL_LOG}"
  case "$url" in
    *export.arxiv.org*)
      cat "${EVAL_FIXTURE_DIR:?}/arxiv.atom.xml"
      ;;
    *hn.algolia.com*query=git%20notes*)
      cat "${EVAL_FIXTURE_DIR:?}/hn-git-notes.json"
      ;;
    *hn.algolia.com*)
      cat "${EVAL_FIXTURE_DIR:?}/hn-ai-provenance.json"
      ;;
    *gdeltproject.org*)
      cat "${EVAL_FIXTURE_DIR:?}/gdelt-rate-limit-notice.txt"
      ;;
    *)
      echo "fetch-stub: no recorded fixture for $url" >&2
      return 1
      ;;
  esac
}
