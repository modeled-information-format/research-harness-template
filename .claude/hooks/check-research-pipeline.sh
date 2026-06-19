#!/usr/bin/env bash
# Stop hook (bundled enforcement, SPEC §7a). When a session has touched findings,
# surface the research-lifecycle completion checklist so the
# falsify -> remediate -> reconcile -> reindex -> lint steps are not skipped.
#
# NON-BLOCKING: emits a systemMessage reminder only; never blocks Stop.
# Deterministic signal = git-dirty findings files (clears once committed).

cat /dev/stdin >/dev/null 2>&1   # drain the event payload; content unused

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Findings files changed this session (modified or new, staged or unstaged).
CHANGED=$(git status --porcelain -- 'reports/*/findings_*.json' 'reports/*/*.finding.json' 2>/dev/null | sed 's/^...//')
[ -z "$CHANGED" ] && exit 0   # no findings touched -> nothing to remind

# Distinct topics touched this session.
TOPIC_LIST=$(echo "$CHANGED" | sed -E 's#reports/([^/]+)/.*#\1#' | sort -u)
TOPICS=$(echo "$TOPIC_LIST" | tr '\n' ' ')

# Unambiguous defect: citations listed dead — scoped to the touched topics only.
DEAD=""
for t in $TOPIC_LIST; do
  hits=$(grep -rl 'deadUrls' "reports/$t" 2>/dev/null | tr '\n' ' ')
  [ -n "$hits" ] && DEAD="${DEAD}${hits}"
done

MSG="Research-lifecycle reminder: findings changed this session in topic(s): ${TOPICS}. Before reporting complete, confirm the pipeline ran — (1) NEW findings falsified (extensions.harness.verification dated today + falsification report); (2) remediated (falsified -> quarantine, weakened -> confidence down one level, re-ground any dead citation); (3) state + harness.config.json + READMEs reconciled; (4) reindex run; (5) markdownlint-cli2 = 0 errors; (6) scripts/check-citation-integrity.sh passes."
if [ -n "$DEAD" ]; then
  MSG="${MSG} DEAD CITATIONS still listed in: ${DEAD}— re-ground from the live primary source before done."
fi

jq -n --arg m "$MSG" '{systemMessage: $m}'
exit 0
