#!/usr/bin/env python3
"""Markdown lint anti-evasion hook for the research harness.

Invoked by Claude Code hooks as:  md_guard.py {pre|post|stop}
Reads the hook event JSON on stdin, emits hook JSON on stdout, and exits 0
(deny is expressed via JSON, not exit code, so the workflow is never broken by
an internal error) -- with ONE deliberate exception: if a `--fix` pass corrupts
a file's YAML frontmatter (issue #510), `post` restores the pre-fix content and
exits 2 so the corruption is loud, never a silent success.

Behavior:
  pre   Hard-deny (PreToolUse permissionDecision=deny) the cheap suppression
        shortcuts: a markdownlint/prettier directive added to a .md file as a
        LIVE comment (outside code spans/fences), or a Markdown glob added to a
        .markdownlintignore / .prettierignore file.
  post  Auto-run `markdownlint-cli2 --fix` on edited Markdown, then warn
        (non-blocking additionalContext) about residual debt. Also warns,
        forcefully, when an edit disables a rule in a markdownlint config file.
  stop  Final `--fix` sweep over the Markdown files touched this session plus a
        summary warning. Warn-only -- never blocks the stop.

Known blind spot (issue #85 Defect 3): pre/post/stop only see Markdown written
through the Write|Edit|MultiEdit tools, so Markdown appended via Bash redirection
(e.g. an orchestrator subagent appending research-progress.md) is never swept; and
MD025/MD024 are not `--fix`-able anyway. The backstop is the independent CI
`markdownlint` job (a separate workflow job, so an earlier failing gate cannot mask
it) plus emitting conformant Markdown at the source (orchestrator.md progress-log
template). This hook is intentionally not re-architected to sweep Bash-written files.
"""

import hashlib
import json
import os
import re
import shutil
import sys
import time

from md_lint_core import (
    MD_CONFIG_RE,
    is_markdown,
    resolve_binary,
    run_lint,
    strip_code,
    trim_diag,
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Overridable so the eval suite (evals/md-guard-fix-lock.sh) can isolate its
# lock/state writes from a real session's state directory.
STATE_DIR = os.environ.get("MD_GUARD_STATE_DIR") or os.path.join(SCRIPT_DIR, "state")

# A markdownlint/prettier suppression directive inside a LIVE HTML comment:
# markdownlint-disable / -disable-line / -disable-next-line / -disable-file /
# -capture / -restore / -configure / -configure-file, plus prettier-ignore.
# The `<!-- ... -->` anchor matters: markdownlint only honors these as HTML
# comments, so requiring the comment context avoids denying ordinary prose that
# merely mentions the word. `(?:(?!-->).)*?` keeps the match inside one comment
# (it cannot bridge a closed comment to a later prose mention).
SUPPRESS_RE = re.compile(
    r"<!--(?:(?!-->).)*?"
    r"(?:markdownlint-(?:disable|capture|restore|configure)|prettier-ignore)",
    re.DOTALL | re.IGNORECASE,
)
# A rule disabled in a markdownlint config: "MD013": false  /  MD013: false  /
# "default": false.
RULE_OFF_RE = re.compile(r"""["']?(MD\d{3}|default)["']?\s*:\s*false""")
# A Markdown linter invoked the wrong way in a Bash command: `npx markdownlint*`
# (network fetch of a different/older package that ignores project policy) or
# the old `markdownlint-cli` binary (not the installed markdownlint-cli2).
NPX_MD_RE = re.compile(r"\bnpx\b.*markdownlint", re.IGNORECASE)
OLD_CLI_RE = re.compile(r"\bmarkdownlint-cli\b(?!2)")


# --------------------------------------------------------------------------- #
# Input helpers
# --------------------------------------------------------------------------- #
def file_path_of(tool_input):
    return tool_input.get("file_path") or tool_input.get("filePath") or ""


def added_text(tool_input):
    """Concatenate the text being introduced by Write/Edit/MultiEdit."""
    parts = []
    if tool_input.get("content"):
        parts.append(tool_input["content"])
    if tool_input.get("new_string"):
        parts.append(tool_input["new_string"])
    for edit in tool_input.get("edits") or []:
        if isinstance(edit, dict) and edit.get("new_string"):
            parts.append(edit["new_string"])
    return "\n".join(parts)


def is_ignore_file(path):
    return os.path.basename(path) in (".markdownlintignore", ".prettierignore")


def is_md_config(path):
    return bool(MD_CONFIG_RE.search(path.replace("\\", "/")))


def ignore_adds_markdown(text):
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or s.startswith("!"):  # blank/comment/negation
            continue
        low = s.lower()  # match is_markdown(), which lowercases (catches README.MD)
        if (
            low.endswith(".md")
            or low.endswith(".markdown")
            or "*.md" in low
            or "*.markdown" in low
        ):
            return True
    return False


def disabled_rules(text):
    return sorted(set(m.group(1) for m in RULE_OFF_RE.finditer(text)))


# --------------------------------------------------------------------------- #
# Output helpers
# --------------------------------------------------------------------------- #
def emit(obj):
    sys.stdout.write(json.dumps(obj))


def deny(reason):
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
    )


def context(event, message):
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": event,
                "additionalContext": message,
            }
        }
    )


# --------------------------------------------------------------------------- #
# State (touched-file tracking)
# --------------------------------------------------------------------------- #
def state_file(session_id):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "session")
    return os.path.join(STATE_DIR, safe + ".txt")


def record_touched(session_id, abspath):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(state_file(session_id), "a", encoding="utf-8") as fh:
            fh.write(abspath + "\n")
    except OSError:
        pass


# --------------------------------------------------------------------------- #
# Serialized, corruption-guarded `--fix` (issue #510)
#
# Parallel Edit batches fire concurrent PostToolUse hook chains against the SAME
# file; `markdownlint-cli2 --fix` is a read-modify-write, so two unserialized
# passes race and can corrupt the file (observed: YAML frontmatter wrapped in an
# HTML comment) while every hook reports success. Mirror of scripts/run-lock.sh:
# the lock is a DIRECTORY (mkdir is an atomic test-and-set across processes;
# touch is not), keyed on the sha256 of the absolute path; freshness is the
# directory's mtime; an `owner` file records a human-readable label; a stale
# lock (crashed holder) is stolen through the same atomic mkdir so two stealers
# cannot both win. The wait is BOUNDED: a holder runs `--fix` for at most
# run_lint's 30s subprocess timeout, and this hook's own PostToolUse timeout is
# 45s, so on timeout the fix is SKIPPED (never raced) -- the concurrent holder
# is fixing the very same file, and the Stop sweep re-fixes it anyway.
# --------------------------------------------------------------------------- #
def _lock_seconds(env_var, default):
    """Sanitize an env-tunable seconds value (run-lock.sh sanitize_minutes)."""
    raw = os.environ.get(env_var, "")
    try:
        val = float(raw)
    except (TypeError, ValueError):
        return default
    return val if val > 0 else default


LOCK_WAIT_SEC = _lock_seconds("MD_GUARD_LOCK_WAIT_SEC", 10)
LOCK_STALE_SEC = _lock_seconds("MD_GUARD_LOCK_STALE_SEC", 120)
LOCK_POLL_SEC = 0.1


def fix_lock_dir(abspath):
    digest = hashlib.sha256(abspath.encode("utf-8")).hexdigest()[:16]
    return os.path.join(STATE_DIR, "fix-lock-" + digest)


def acquire_fix_lock(abspath):
    """Acquire the per-file fix lock. Returns the lock path, or None on timeout.

    Fail SAFE like run-lock.sh: on an unexpected OS error, return None (the
    caller skips the fix) rather than proceed unlocked and risk racing.
    """
    lock = fix_lock_dir(abspath)
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
    except OSError:
        return None
    deadline = time.monotonic() + LOCK_WAIT_SEC
    while True:
        try:
            os.mkdir(lock)  # atomic: succeeds only if no holder existed
            try:
                with open(os.path.join(lock, "owner"), "w", encoding="utf-8") as fh:
                    fh.write("md_guard pid %d\n" % os.getpid())
            except OSError:
                pass
            return lock
        except FileExistsError:
            pass
        except OSError:
            return None
        try:
            age = time.time() - os.stat(lock).st_mtime
        except FileNotFoundError:
            # Holder released the lock between our mkdir attempt and this stat;
            # retry immediately (skip the poll sleep) -- the next mkdir likely wins.
            continue
        except OSError:
            age = 0  # unexpected stat error; fall through to the bounded wait
        if age > LOCK_STALE_SEC:
            # Stale marker from a crashed holder -- remove it and re-acquire
            # through the SAME atomic mkdir, so two stealers cannot both win.
            shutil.rmtree(lock, ignore_errors=True)
            continue
        if time.monotonic() >= deadline:
            return None
        time.sleep(LOCK_POLL_SEC)


def release_fix_lock(lock):
    shutil.rmtree(lock, ignore_errors=True)


def run_fix_serialized(abspath):
    """Run `markdownlint-cli2 --fix` on one file, serialized and sanity-checked.

    Returns (rc, diag, err) where err is None on the normal path, or a dict
    {"kind": "lock"|"corrupt", "msg": ...}:
      lock     the per-file lock could not be acquired within the bounded wait;
               the fix was SKIPPED (never run concurrently).
      corrupt  the file started with "---" (YAML frontmatter) before the fix
               and no longer did after it; the pre-fix content was RESTORED and
               the corrupted output kept aside under state/ for forensics.
    """
    lock = acquire_fix_lock(abspath)
    if lock is None:
        return None, "", {
            "kind": "lock",
            "msg": "md_guard: skipped `markdownlint-cli2 --fix` on "
            + os.path.basename(abspath)
            + " -- another hook holds its fix lock (concurrent edit batch) and "
            "it stayed held past the bounded wait. Not raced; the holder is "
            "fixing this same file, and the session-end sweep re-fixes it.",
        }
    try:
        try:
            with open(abspath, "rb") as fh:
                before = fh.read()
        except OSError:
            before = None
        rc, diag = run_lint(abspath, fix=True)
        if before is not None and before.startswith(b"---"):
            try:
                with open(abspath, "rb") as fh:
                    after = fh.read()
            except OSError:
                after = None
            if after is None or not after.startswith(b"---"):
                kept = os.path.join(
                    STATE_DIR,
                    "corrupt-%s-%d.md"
                    % (
                        hashlib.sha256(abspath.encode("utf-8")).hexdigest()[:16],
                        int(time.time()),
                    ),
                )
                try:
                    with open(kept, "wb") as fh:
                        fh.write(after or b"")
                except OSError:
                    kept = "(could not be saved)"
                restored = True
                try:
                    with open(abspath, "wb") as fh:
                        fh.write(before)
                except OSError:
                    restored = False
                return rc, diag, {
                    "kind": "corrupt",
                    "msg": "md_guard: `markdownlint-cli2 --fix` CORRUPTED "
                    + abspath
                    + " -- the file started with YAML frontmatter (\"---\") "
                    "before the fix and no longer did after it (issue #510). "
                    + (
                        "The pre-fix content has been RESTORED."
                        if restored
                        else "RESTORING the pre-fix content FAILED -- the file "
                        "on disk is the corrupted output; recover it by hand."
                    )
                    + " Corrupted output kept at: "
                    + kept
                    + ". Do NOT treat this edit as successfully linted -- "
                    "inspect the file before continuing.",
                }
        return rc, diag, None
    finally:
        release_fix_lock(lock)


# --------------------------------------------------------------------------- #
# Events
# --------------------------------------------------------------------------- #
def do_pre(path, tool_input):
    text = added_text(tool_input)
    if is_markdown(path) and SUPPRESS_RE.search(strip_code(text)):
        deny(
            "Suppression directives (markdownlint-disable / prettier-ignore) are "
            "not allowed in Markdown here. Do not silence the diagnostic -- fix it. "
            "Run `markdownlint-cli2 --fix \"" + os.path.basename(path) + "\"` to "
            "auto-resolve fixable issues, then correct the rest by hand."
        )
        return
    if is_ignore_file(path) and ignore_adds_markdown(text):
        deny(
            "Adding Markdown paths to " + os.path.basename(path) + " to hide them "
            "from the linter is not allowed. Fix the underlying issues instead "
            "(`markdownlint-cli2 --fix`)."
        )
        return


def do_post(path, tool_input, session_id):
    if is_md_config(path):
        text = added_text(tool_input)
        rules = disabled_rules(text)
        # An `ignores` entry that excludes Markdown is the config-channel
        # equivalent of a .markdownlintignore glob -- it hides files from the
        # linter without disabling a named rule.
        hides = bool(re.search(r'"?ignores"?\s*[:=]', text)) and ignore_adds_markdown(text)
        if rules or hides:
            what = []
            if rules:
                what.append("disabled rule(s) " + ", ".join(rules))
            if hides:
                what.append("added Markdown path(s) to `ignores`")
            context(
                "PostToolUse",
                "You "
                + " and ".join(what)
                + " in "
                + os.path.basename(path)
                + ". Weakening lint policy is only acceptable as a deliberate, "
                "justified choice. If you did this to make a diagnostic go away, "
                "REVERT it and fix the underlying Markdown instead "
                "(`markdownlint-cli2 --fix` first).",
            )
        return

    if not is_markdown(path):
        return
    abspath = os.path.abspath(path)
    if not os.path.exists(abspath):
        return

    if not resolve_binary():
        context(
            "PostToolUse",
            "markdownlint-cli2 not found on PATH -- cannot auto-fix or lint "
            "Markdown. Install it (`brew install markdownlint-cli2`).",
        )
        return

    # One pass: `--fix` auto-corrects fixable issues AND reports the residual
    # (un-fixable) violations it leaves behind, so a second lint is redundant.
    # Serialized per file + frontmatter-corruption guard (issue #510).
    rc, diag, err = run_fix_serialized(abspath)
    record_touched(session_id, abspath)
    if err is not None and err["kind"] == "corrupt":
        # Loud, blocking failure: exit 2 feeds stderr back to the agent. The
        # hook must never silently succeed on a file it may have corrupted.
        sys.stderr.write(err["msg"] + "\n")
        return 2
    if err is not None:  # lock timeout: fix skipped, warn non-blocking
        context("PostToolUse", err["msg"])
        return 0
    if rc not in (0, None) and diag.strip():
        context(
            "PostToolUse",
            "Auto-fix (`markdownlint-cli2 --fix`) ran on "
            + os.path.basename(path)
            + ". These issues remain and must be CORRECTED, not suppressed:\n"
            + trim_diag(diag),
        )
    return 0


def do_stop(session_id):
    sf = state_file(session_id)
    if not os.path.exists(sf):
        return
    if not resolve_binary():
        # Can't lint without the binary. Leave the state file so a later session
        # (with the binary present) still sweeps these files -- do not silently
        # discard the touched-file record and report a false "no debt".
        return
    try:
        with open(sf, "r", encoding="utf-8") as fh:
            files = [ln.strip() for ln in fh if ln.strip()]
    except OSError:
        files = []

    residuals = []
    for f in dict.fromkeys(files):  # dedupe, preserve order
        if not os.path.exists(f):
            continue
        # One pass: `--fix` corrects and reports the residual (see do_post).
        # Same per-file lock + corruption guard as do_post (issue #510); the
        # stop sweep stays warn-only, so a guard trip is reported via the
        # systemMessage below rather than a non-zero exit.
        rc, diag, err = run_fix_serialized(f)
        if err is not None:
            residuals.append((f, err["msg"]))
        elif rc not in (0, None) and diag.strip():
            residuals.append((f, trim_diag(diag)))

    if residuals:
        msg = [
            "Session end: `markdownlint-cli2 --fix` swept the Markdown files you "
            "touched. The following lint debt remains -- correct it, do not "
            "suppress it:"
        ]
        for f, d in residuals:
            try:
                rel = os.path.relpath(f)
            except ValueError:
                rel = f
            msg.append("\n# " + rel + "\n" + d)
        # Stop does NOT honor hookSpecificOutput.additionalContext; its only
        # non-blocking channel is the universal top-level systemMessage.
        emit({"systemMessage": "\n".join(msg)})

    try:
        os.remove(sf)
    except OSError:
        pass


def do_bash(command):
    # Warn-only (never block): nudge ad-hoc / npx markdownlint invocations toward
    # the project tooling, which applies the repo ruleset and the remediation
    # passes a raw linter skips. A direct `markdownlint-cli2` call is fine.
    if not command or not (NPX_MD_RE.search(command) or OLD_CLI_RE.search(command)):
        return
    context(
        "PreToolUse",
        "Use the project's Markdown tooling, not an ad-hoc linter. To CHECK: "
        "`markdownlint-cli2` (installed; applies the repo .markdownlint.jsonc). "
        "To REPAIR: `python3 .claude/hooks/markdown/md_remediate.py <paths>` "
        "(runs --fix PLUS the residual classes it cannot auto-fix: tables, "
        "placeholders, links, spell triage). Avoid `npx markdownlint*` and the "
        "old `markdownlint-cli` -- they fetch a different package over the "
        "network and ignore project policy.",
    )


# --------------------------------------------------------------------------- #
def main():
    """Dispatch the event. Returns the process exit code (0 unless `post`
    detected --fix corruption, the one loud non-zero path -- see module doc)."""
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    tool_input = data.get("tool_input") or {}
    path = file_path_of(tool_input)
    session_id = data.get("session_id") or "session"

    if event == "pre":
        do_pre(path, tool_input)
    elif event == "post":
        return do_post(path, tool_input, session_id) or 0
    elif event == "stop":
        do_stop(session_id)
    elif event == "bash":
        do_bash(tool_input.get("command", ""))
    return 0


if __name__ == "__main__":
    rc = 0
    try:
        rc = main() or 0
    except Exception as exc:  # internal errors never break the workflow
        sys.stderr.write("md_guard: internal error: %r\n" % (exc,))
        rc = 0
    sys.exit(rc)
