#!/usr/bin/env python3
"""Shared Markdown lint engine for the research harness.

Extracted from md_guard.py so both the anti-evasion hook (md_guard.py) and the
active remediation tool (md_remediate.py) use one implementation of:

  - markdownlint-cli2 binary resolution
  - upward project-config discovery with a shipped fallback ruleset
  - `markdownlint-cli2 [--fix]` invocation on a single file
  - diagnostic trimming to rule lines
  - code-fence/inline-code stripping (markdownlint's live-text semantics)

No behavior change versus the original md_guard.py definitions.
"""

import json
import os
import re
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(SCRIPT_DIR, "default.markdownlint.jsonc")
BIN_FALLBACK = "/opt/homebrew/bin/markdownlint-cli2"

MD_CONFIG_RE = re.compile(
    r"(?:^|/)\.markdownlint(?:-cli2)?\.(?:json|jsonc|yaml|yml|toml|cjs|mjs)$"
)
CONFIG_NAMES = [
    ".markdownlint.json",
    ".markdownlint.jsonc",
    ".markdownlint.yaml",
    ".markdownlint.yml",
    ".markdownlint.toml",
    ".markdownlint.cjs",
    ".markdownlint.mjs",
    ".markdownlint-cli2.jsonc",
    ".markdownlint-cli2.yaml",
    ".markdownlint-cli2.toml",
    ".markdownlint-cli2.cjs",
    ".markdownlint-cli2.mjs",
]


def is_markdown(path):
    return path.lower().endswith((".md", ".markdown"))


def strip_code(text):
    """Remove fenced code blocks and inline code spans so only live text remains.

    Mirrors markdownlint's own semantics: a `markdownlint-disable` directive is
    only honored as a live HTML comment, never inside code. For Edit fragments
    the fence context is necessarily local to the added text -- a conservative,
    documented limitation.
    """
    out = []
    fence = None  # (char, length) of the open fence, else None
    for line in text.splitlines():
        stripped = line.lstrip()
        if fence:
            char, length = fence
            close = re.match(r"(`{3,}|~{3,})\s*$", stripped)
            # CommonMark: a closer is fence-chars only (no info string), same
            # char, length >= the opener's. A shorter/other-char run does not
            # close, so a nested example fence no longer truncates the block.
            if close and close.group(1)[0] == char and len(close.group(1)) >= length:
                fence = None
            continue
        opener = re.match(r"(`{3,}|~{3,})", stripped)
        if opener:
            marker = opener.group(1)
            fence = (marker[0], len(marker))
            continue
        out.append(re.sub(r"`+[^`]*`+", "", line))
    return "\n".join(out)


def resolve_binary():
    from shutil import which

    return which("markdownlint-cli2") or (
        BIN_FALLBACK if os.path.exists(BIN_FALLBACK) else None
    )


def config_args(file_dir):
    """Resolve the markdownlint config to apply for a file.

    Returns explicit `["--config", <path>]` to the nearest project config found
    walking upward from file_dir, otherwise the shipped default ruleset. We pass
    `--config` explicitly rather than relying on markdownlint-cli2's own
    discovery: cli2 resolves config relative to its working directory, so when
    run with cwd=<file dir> + a bare basename it does NOT walk up to a repo-root
    config -- which would silently apply cli2's built-in defaults (MD013 on)
    instead of the project policy.
    """
    d = os.path.abspath(file_dir)
    while True:
        for name in CONFIG_NAMES:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return ["--config", p]
        pkg = os.path.join(d, "package.json")
        if os.path.exists(pkg):
            try:
                with open(pkg, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
                # Only a real top-level `markdownlint` key counts -- a substring
                # match would fire on a devDependency named "markdownlint-cli2"
                # and silently apply cli2's built-in defaults (MD013 on).
                if isinstance(data, dict) and "markdownlint" in data:
                    # cli2 reads the package.json `markdownlint` key itself;
                    # --config does not accept package.json, so defer to its
                    # discovery from this directory.
                    return []
            except (OSError, ValueError):
                pass
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return ["--config", DEFAULT_CONFIG]


def run_lint(path, fix):
    """Run markdownlint-cli2 on a single file. Returns (returncode, diagnostics).
    cli2 prints diagnostics to stderr; returncode 0=clean, 1=violations."""
    binary = resolve_binary()
    if not binary:
        return None, ""
    d = os.path.dirname(os.path.abspath(path)) or "."
    base = os.path.basename(path)
    cmd = [binary]
    if fix:
        cmd.append("--fix")
    cmd += config_args(d)
    cmd.append(base)
    try:
        proc = subprocess.run(
            cmd, cwd=d, capture_output=True, text=True, timeout=30
        )
    except (subprocess.SubprocessError, OSError):
        return None, ""
    return proc.returncode, (proc.stderr or proc.stdout or "")


def trim_diag(diag, limit=2500):
    rule_lines = [ln for ln in diag.splitlines() if re.search(r"MD\d{3}", ln)]
    out = "\n".join(rule_lines) if rule_lines else diag.strip()
    return out[:limit]
