"""Editorial Gate (research-harness-template#422): the mandatory human-review
checkpoint between the Recommendation Engine and the Output Router (AD-4 --
pure algorithmic curation underperforms human-edited digests). Per ADR-0019,
the actual human review is a GitHub PR (merge = accept, close = reject); this
module is what turns that decision into pipeline state once it's known.

Structurally in the path, not a bypassable flag: a recommendation is
"gate.passed": true only if this module's gate() function stamped it after
finding an explicit "accept" decision. FAIL-SAFE DEFAULT: any recommendation
with no decision recorded at all is treated as rejected, not accepted -- an
unreviewed candidate must never reach Output Router by omission.
"""
import json
import sys


def gate_key(rec):
    """Stable key a decisions map is keyed by: a candidate's own id for
    interest-match recommendations, or a dimension-scoped key for
    gap-detect recommendations (which have no candidate id). A candidate
    whose connector defaulted its id to "" (every connector does on a
    missing upstream id) falls back to its url, then title -- WITHOUT this,
    an empty-id item could never match any decision and would silently fall
    to the fail-safe reject even on an accepted batch. MUST stay in
    lockstep with the jq decisions-map builder in run-gate-and-publish.sh,
    which produces exactly these keys."""
    if rec.get("id"):
        return rec["id"]
    if rec.get("mode") == "gap-detect":
        return f"gap:{rec.get('dimension', '')}"
    if rec.get("url"):
        return f"url:{rec['url']}"
    if rec.get("title"):
        return f"title:{rec['title']}"
    return None


def gate(recommendations, decisions, decided_by, decided_at):
    """Split recommendations into (accepted, rejected) per `decisions`
    (a dict: gate_key -> "accept" | "reject"). Anything not present in
    `decisions` is rejected by default (fail-safe: no decision means no
    publish). Returns (accepted, rejected) where each rejected entry also
    carries a `reason` for the Continuity Log."""
    accepted = []
    rejected = []
    for rec in recommendations:
        key = gate_key(rec)
        decision = decisions.get(key) if key else None
        if decision == "accept":
            stamped = {
                **rec,
                "gate": {
                    "passed": True,
                    "decided_by": decided_by,
                    "decided_at": decided_at,
                },
            }
            accepted.append(stamped)
        elif decision == "reject":
            rejected.append({**rec, "reason": "reviewer rejected"})
        else:
            rejected.append(
                {**rec, "reason": "no explicit accept decision recorded (fail-safe default)"}
            )
    return accepted, rejected


def assert_all_gated(recommendations):
    """The structural no-bypass check: raise if ANY recommendation lacks a
    valid gate.passed=true stamp. The Output Router (research-harness-
    template#423) calls this before publishing anything -- it is the one
    place NFR6 ("no fully automated publish path") is actually enforced in
    code, not merely documented. A recommendation fabricated directly
    (skipping gate()) fails this check and is refused."""
    for rec in recommendations:
        gate_info = rec.get("gate")
        if not isinstance(gate_info, dict) or gate_info.get("passed") is not True:
            raise AssertionError(
                "recommendation without a valid Editorial Gate stamp reached "
                f"the publish boundary: {rec!r}"
            )


def main():
    if len(sys.argv) < 5:
        print(
            "usage: editorial_gate.py <recommendations.json> <decisions.json> "
            "<decided-by> <decided-at-iso8601>",
            file=sys.stderr,
        )
        return 2

    with open(sys.argv[1], encoding="utf-8") as fh:
        recommendations = json.load(fh)
    with open(sys.argv[2], encoding="utf-8") as fh:
        decisions = json.load(fh)
    decided_by, decided_at = sys.argv[3], sys.argv[4]

    accepted, rejected = gate(recommendations, decisions, decided_by, decided_at)
    json.dump({"accepted": accepted, "rejected": rejected}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
