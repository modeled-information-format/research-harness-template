#!/usr/bin/env python3
"""Minimal 5-field cron matcher (stdlib only, no croniter dependency) for
research-harness-template#424: does a topic's own continuousMonitoring.schedule
match the current UTC time? monitor.yml's own schedule: trigger fires more
often than any single topic's configured cron (GitHub Actions supports only
one schedule per workflow), so each topic must independently check whether
THIS particular firing is actually its turn.

Usage: cron_match.py "<5-field cron>" [now-iso8601-utc]
Exit 0 = matches (run this topic now). Exit 1 = does not match (skip).
`now` defaults to the current UTC time; pass it explicitly for testing.
"""
import sys
from datetime import datetime, timezone


def parse_field(field, lo, hi):
    """Expand one cron field ('*', '5', '1-5', '*/15', '1,15,30') to the set
    of values it matches within [lo, hi]."""
    values = set()
    for part in field.split(","):
        if part == "*":
            values.update(range(lo, hi + 1))
            continue
        step = 1
        has_step = "/" in part
        if has_step:
            part, step_s = part.split("/", 1)
            step = int(step_s)
        if part == "*":
            rng = range(lo, hi + 1)
        elif "-" in part:
            a, b = part.split("-", 1)
            rng = range(int(a), int(b) + 1)
        elif has_step:
            # Bare 'N/step' (vixie-cron shorthand for 'N-hi/step'): open-ended
            # from N to the field's upper bound, not the single value N.
            rng = range(int(part), hi + 1)
        else:
            rng = range(int(part), int(part) + 1)
        # Step offsets align to the range's own start (vixie-cron 'a-b/step'
        # fires at a, a+step, ...), never to the field's absolute lower bound.
        values.update(v for v in rng if (v - rng.start) % step == 0)
    return values


def matches(cron_expr, now):
    fields = cron_expr.split()
    if len(fields) != 5:
        raise ValueError(f"expected 5 cron fields, got {len(fields)}: {cron_expr!r}")
    minute, hour, dom, month, dow = fields

    minutes = parse_field(minute, 0, 59)
    hours = parse_field(hour, 0, 23)
    doms = parse_field(dom, 1, 31)
    months = parse_field(month, 1, 12)
    # cron day-of-week: 0 or 7 = Sunday ... 6 = Saturday; Python's
    # weekday(): 0 = Monday ... 6 = Sunday. Normalize both to 0=Sunday.
    dows = {0 if d == 7 else d for d in parse_field(dow, 0, 7)}
    py_dow_to_cron_dow = (now.weekday() + 1) % 7  # Python Mon=0 -> cron Sun=0

    if now.minute not in minutes or now.hour not in hours or now.month not in months:
        return False

    # Standard vixie-cron semantics: when BOTH dom and dow are restricted
    # (not "*"), a match on EITHER is sufficient; if either is "*", only the
    # other constrains.
    dom_restricted = dom != "*"
    dow_restricted = dow != "*"
    dom_match = now.day in doms
    dow_match = py_dow_to_cron_dow in dows
    if dom_restricted and dow_restricted:
        return dom_match or dow_match
    if dom_restricted:
        return dom_match
    if dow_restricted:
        return dow_match
    return True


def main():
    if len(sys.argv) < 2:
        print("usage: cron_match.py '<5-field cron>' [now-iso8601-utc]", file=sys.stderr)
        return 2
    cron_expr = sys.argv[1]
    if len(sys.argv) > 2:
        now = datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00"))
    else:
        now = datetime.now(timezone.utc)
    return 0 if matches(cron_expr, now) else 1


if __name__ == "__main__":
    sys.exit(main())
