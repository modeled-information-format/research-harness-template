#!/usr/bin/env python3
"""Markdown lint anti-evasion hook for the research harness.

Invoked by Claude Code hooks as:  md_guard.py {pre|post|stop}
Reads the hook event JSON on stdin, emits hook JSON on stdout, always exits 0
(deny is expressed via JSON, not exit code, so the workflow is never broken by
an internal error).

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
"""

import json
import os
import re
import sys

from md_lint_core import (
    MD_CONFIG_RE,
    is_markdown,
    resolve_binary,
    run_lint,
    strip_code,
    trim_diag,
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(SCRIPT_DIR, "state")

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
    rc, diag = run_lint(abspath, fix=True)
    record_touched(session_id, abspath)
    if rc not in (0, None) and diag.strip():
        context(
            "PostToolUse",
            "Auto-fix (`markdownlint-cli2 --fix`) ran on "
            + os.path.basename(path)
            + ". These issues remain and must be CORRECTED, not suppressed:\n"
            + trim_diag(diag),
        )


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
        rc, diag = run_lint(f, fix=True)
        if rc not in (0, None) and diag.strip():
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
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    tool_input = data.get("tool_input") or {}
    path = file_path_of(tool_input)
    session_id = data.get("session_id") or "session"

    if event == "pre":
        do_pre(path, tool_input)
    elif event == "post":
        do_post(path, tool_input, session_id)
    elif event == "stop":
        do_stop(session_id)
    elif event == "bash":
        do_bash(tool_input.get("command", ""))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never break the workflow
        sys.stderr.write("md_guard: internal error: %r\n" % (exc,))
    sys.exit(0)
