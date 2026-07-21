#!/usr/bin/env bash
# check-output-conformance.sh — Stop-hook backstop for MIF output conformance
# (SPEC §10). The deterministic fail-closed enforcement is render-artifact.sh's
# write-then-validate (scripts/mif-project.sh) plus verify.sh gate_m10; this hook
# is a warn-only safety net that flags any git-dirty generic report which does not
# project to a valid MIF Level-3 finding before the session is reported complete.
#
# NON-BLOCKING: emits a systemMessage reminder only; never blocks Stop.
# Deterministic signal = git-dirty reports/<topic>/<slug>.md (clears on fix/commit).
# Exempt channels (blog, book, and channel-pack outputs — all nested under
# reports/<topic>/, never a top-level directory) are intentionally NOT checked
# here — their exemption is declared in the manifests, matched below by the
# trailing .blog.md suffix / nested book/ subdirectory that identifies them.

cat /dev/stdin >/dev/null 2>&1   # drain the event payload; content unused

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Generic reports changed this session (modified or new, staged or unstaged).
CHANGED=$(git status --porcelain --untracked-files=all -- 'reports/*/*.md' 2>/dev/null | sed 's/^...//')
[ -z "$CHANGED" ] && exit 0

BAD=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # reports/_meta is scaffolding; per-topic README.md is a navigation index; reports/_corpus
  # is the cross-topic atlas (corpus-synthesis.md); *-build-spec.md and the three
  # *-kiro-{requirements,design,tasks}.md suffixes are the ai-spec channel's agent-consumable
  # spec genres (mif.exempt, MIF Level-1, a synthesis across many findings, not a single
  # Level-3 graded finding — the same four-suffix exclusion list verify.sh's reports-binding
  # checks carry; the kiro genres were split out in research-harness-template#409/#414);
  # *.blog.md is the blog channel (MIF-exempt, nested under reports/<topic>/ per the trailing
  # suffix, never a top-level blog/ directory) — none of these are Level-3 reports of record.
  # (The book channel's own reports/<topic>/book/ nesting is one directory deeper than this
  # hook's flat 'reports/*/*.md' sweep reaches, so it never needs its own exemption case here.)
  case "$f" in reports/_meta/*|reports/_corpus/*|reports/*/README.md|reports/*/*-build-spec.md|reports/*/*-kiro-requirements.md|reports/*/*-kiro-design.md|reports/*/*-kiro-tasks.md|reports/*/*.blog.md) continue ;; esac
  scripts/mif-project.sh "$f" >/dev/null 2>&1 || BAD="${BAD}${f} "
done <<< "$CHANGED"
[ -z "$BAD" ] && exit 0

jq -n --arg files "$BAD" '{systemMessage: ("MIF output-conformance gate: generic report(s) do not project to a valid MIF Level-3 finding and must be fixed before this output is reported complete: " + $files + "— a report needs MIF frontmatter (citations, provenance, and extensions.harness.verification carrying a REAL, non-falsified verdict) over its body. Run a falsification pass over the synthesised claims and re-render via scripts/render-artifact.sh <artifact.json> report <out.md> <verification.json>.")}'
exit 0
