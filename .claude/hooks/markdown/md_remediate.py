#!/usr/bin/env python3
"""Deterministic Markdown remediation for the research harness.

The md_guard.py hook runs `markdownlint-cli2 --fix` automatically, but `--fix`
cannot resolve several rule classes. This tool repairs those residual classes
plus broken intra-repo links and spell/typo false positives -- WITHOUT ever
suppressing a diagnostic. Judgment calls (genuine prose typos, ambiguous links
or heading levels) are reported under `escalate`, never auto-changed.

Passes (each idempotent):
  MD025  drop a frontmatter `title:` that duplicates the body H1
  MD060  normalize tables to padded pipes + spaced separators
  MD033  wrap bare <placeholder> tokens in backticks (or `{...}` in headings)
  MD036  convert a standalone **bold** line used as a heading into a heading
  MD029  re-indent a col-0 table/code block wedged between ordered-list items
  links  remap broken relative .md links to the canonical file (RB-NN / basename)
  spell  classify cspell/typos hits: allowlist proper nouns, escalate real typos

Usage:
  md_remediate.py [--check] [--dry-run] [--no-spell] [--apply-allowlist]
                  [--root DIR] <path-or-glob> ...

  --check            report only; write nothing (exit 1 if anything would change)
  --dry-run          print unified diffs; write nothing
  --no-spell         skip the cspell/typos pass
  --apply-allowlist  in write mode, add proper-noun hits to cspell.json/_typos.toml
  --root DIR         tree root for canonical link maps (default: git toplevel)

Exit: 0 = clean / all applied; 1 = changes needed under --check, or escalations.
"""

import argparse
import difflib
import glob as globmod
import json
import os
import re
import subprocess
import sys
import tempfile

import md_lint_core as core

HTML_ALLOW = {
    "br", "hr", "img", "a", "code", "pre", "kbd", "sub", "sup", "b", "i",
    "em", "strong", "span", "div", "details", "summary", "table", "thead",
    "tbody", "tr", "td", "th", "ul", "ol", "li", "p", "blockquote",
}


# --------------------------------------------------------------------------- #
# Frontmatter / fenced-region helpers
# --------------------------------------------------------------------------- #
def split_frontmatter(text):
    """Return (frontmatter_lines, body_text). frontmatter_lines is [] if none."""
    if not text.startswith("---\n") and text != "---":
        return [], text
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return [], text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[: i + 1], "\n".join(lines[i + 1 :])
    return [], text


def fence_mask(lines):
    """Boolean list: True where the line is inside a fenced code block (opener
    and closer lines included)."""
    mask = []
    fence = None  # (char, length) of the open fence
    for line in lines:
        s = line.lstrip()
        if fence:
            mask.append(True)
            char, length = fence
            close = re.match(r"(`{3,}|~{3,})\s*$", s)
            # CommonMark: closer is fence-chars only, same char, length >= opener.
            if close and close.group(1)[0] == char and len(close.group(1)) >= length:
                fence = None
        else:
            opener = re.match(r"(`{3,}|~{3,})", s)
            if opener:
                marker = opener.group(1)
                fence = (marker[0], len(marker))
                mask.append(True)
            else:
                mask.append(False)
    return mask


def _mask_inline_code(text):
    """Replace inline-code spans with placeholders so their contents (pipes,
    angle brackets, link syntax) are not parsed as Markdown. Returns
    (masked_text, spans); restore with _unmask_inline_code."""
    spans = []

    def _stash(m):
        spans.append(m.group(0))
        return "\x00%d\x00" % (len(spans) - 1)

    return re.sub(r"`+[^`]*`+", _stash, text), spans


def _unmask_inline_code(text, spans):
    return re.sub(r"\x00(\d+)\x00", lambda m: spans[int(m.group(1))], text)


# --------------------------------------------------------------------------- #
# MD025 -- frontmatter title duplicating the body H1
# --------------------------------------------------------------------------- #
def fix_frontmatter_title(text, rep):
    fm, body = split_frontmatter(text)
    if not fm:
        return text
    body_lines = body.split("\n")
    has_h1 = any(re.match(r"#\s+\S", ln) for ln in body_lines)
    if not has_h1:
        return text
    new_fm = [ln for ln in fm if not re.match(r"\s*title\s*:", ln)]
    if len(new_fm) == len(fm):
        return text
    rep["fixed"].add("MD025")
    return "\n".join(new_fm) + "\n" + body


# --------------------------------------------------------------------------- #
# MD060 -- table column style (pad pipes + separators)
# --------------------------------------------------------------------------- #
def _split_cells(row):
    s = row.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    # A pipe inside an inline-code span is literal (GFM), not a column break --
    # mask spans before splitting so `` `a|b` `` stays one cell.
    masked, spans = _mask_inline_code(s)
    return [_unmask_inline_code(c, spans).strip() for c in re.split(r"(?<!\\)\|", masked)]


def _is_table_row(line):
    s = line.strip()
    return s.startswith("|") and s.endswith("|") and len(s) > 1


def _is_sep_cells(cells):
    return bool(cells) and all(re.fullmatch(r":?-{1,}:?", c) for c in cells)


def _fmt_sep(c):
    left, right = c.startswith(":"), c.endswith(":")
    if left and right:
        return ":---:"
    if left:
        return ":---"
    if right:
        return "---:"
    return "---"


def fix_tables(text, rep):
    lines = text.split("\n")
    mask = fence_mask(lines)
    changed = False
    out = []
    for i, line in enumerate(lines):
        if not mask[i] and _is_table_row(line):
            indent = line[: len(line) - len(line.lstrip(" \t"))]  # preserve nesting
            cells = _split_cells(line)
            if _is_sep_cells(cells):
                new = indent + "| " + " | ".join(_fmt_sep(c) for c in cells) + " |"
            else:
                new = indent + "| " + " | ".join(cells) + " |"
            if new != line:
                changed = True
            out.append(new)
        else:
            out.append(line)
    if changed:
        rep["fixed"].add("MD060")
    return "\n".join(out)


# --------------------------------------------------------------------------- #
# MD033 -- bare <placeholder> tokens
# --------------------------------------------------------------------------- #
TAG_RE = re.compile(r"<([^<>]+)>")


def _is_real_html(inner):
    inner = inner.strip()
    if inner.startswith(("!", "/")):
        return True  # comment / closing / doctype
    if re.match(r"https?://|mailto:", inner):
        return True  # autolink
    if "@" in inner and " " not in inner:
        return True  # email autolink
    name = re.match(r"\s*([A-Za-z][A-Za-z0-9]*)", inner)
    if name and name.group(1).lower() in HTML_ALLOW:
        return True
    return False


def fix_placeholders(text, rep):
    lines = text.split("\n")
    mask = fence_mask(lines)
    changed = False
    for i, line in enumerate(lines):
        if mask[i] or "<" not in line:
            continue
        # mask inline code spans so we don't touch <...> inside backticks
        spans = []

        def _stash(m):
            spans.append(m.group(0))
            return "\x00%d\x00" % (len(spans) - 1)

        masked = re.sub(r"`+[^`]*`+", _stash, line)
        is_heading = bool(re.match(r"#{1,6}\s", masked.lstrip()))

        def _repl(m):
            inner = m.group(1)
            if _is_real_html(inner):
                return m.group(0)
            nonlocal changed
            changed = True
            if is_heading:
                return "{" + inner + "}"
            return "`<" + inner + ">`"

        masked = TAG_RE.sub(_repl, masked)
        # restore code spans
        masked = re.sub(r"\x00(\d+)\x00", lambda m: spans[int(m.group(1))], masked)
        lines[i] = masked
    if changed:
        rep["fixed"].add("MD033")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# MD036 -- standalone bold line used as a heading
# --------------------------------------------------------------------------- #
BOLD_LINE_RE = re.compile(r"^\s*(\*\*|__)(.+?)\1\s*$")


def _is_heading_like(inner):
    """A standalone bold line is safe to promote to a heading only if it reads
    like a label, not prose. Conservative: a sentence, a formula, or a long
    phrase is left as emphasis (and escalated as residual MD036) rather than
    promoted into a broken heading-fragment."""
    t = inner.strip()
    if not t or "=" in t:
        return False
    if t.endswith(":"):
        return True
    if t[-1] in ".!?":
        return False  # a sentence, not a heading
    return len(t.split()) <= 6


def fix_bold_as_heading(text, rep):
    lines = text.split("\n")
    mask = fence_mask(lines)
    level = 2  # default if no prior heading
    changed = False
    for i, line in enumerate(lines):
        if mask[i]:
            continue
        h = re.match(r"(#{1,6})\s", line)
        if h:
            level = len(h.group(1))
            continue
        m = BOLD_LINE_RE.match(line)
        if not m:
            continue
        prev_blank = i == 0 or lines[i - 1].strip() == ""
        next_blank = i + 1 >= len(lines) or lines[i + 1].strip() == ""
        # a heading-like emphasis paragraph: its own line, blank-separated,
        # and the emphasized text has no inner markup that implies real prose
        if prev_blank and next_blank and "`" not in m.group(2) and _is_heading_like(m.group(2)):
            new_level = min(level + 1, 6)
            lines[i] = "#" * new_level + " " + m.group(2).strip()
            changed = True
    if changed:
        rep["fixed"].add("MD036")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# MD040 -- fenced code block with no language
# --------------------------------------------------------------------------- #
_SHELL_RE = re.compile(
    r"^(\$ |#!|git |gh |npx |npm |kubectl |cosign |syft |grype |aws |docker |"
    r"export |curl |cd |make |terraform |helm |oras |crane |cat |sed |grep |"
    r"python3? |pip |cargo |brew |node |go |jq |yq )"
)


def classify_fence(body):
    """Best-effort language for an unlabeled fence. Conservative: only emit a
    real language on a strong signal; default to `text` (always correct -- it
    just means no syntax highlighting -- so this never mislabels)."""
    nonempty = [ln.strip() for ln in body if ln.strip()]
    if not nonempty:
        return "text"
    first = nonempty[0]
    if first[0] in "{[":
        return "json"
    if any(_SHELL_RE.match(ln) for ln in nonempty[:6]):
        return "bash"
    return "text"


def fix_unlabeled_fences(text, rep):
    lines = text.split("\n")
    out = []
    i, n = 0, len(lines)
    changed = False
    while i < n:
        line = lines[i]
        s = line.lstrip()
        m = re.match(r"(`{3,}|~{3,})(.*)$", s)
        if m:
            fence, info = m.group(1), m.group(2).strip()
            fchar = fence[0]
            indent = line[: len(line) - len(s)]
            j = i + 1
            body = []
            while j < n:
                sj = lines[j].lstrip()
                cm = re.match(r"(`{3,}|~{3,})\s*$", sj)
                # closer: same char, length >= opener (a shorter run is body).
                if cm and cm.group(1)[0] == fchar and len(cm.group(1)) >= len(fence):
                    break
                body.append(lines[j])
                j += 1
            if not info:
                out.append(indent + fence + classify_fence(body))
                changed = True
            else:
                out.append(line)
            out.extend(body)
            if j < n:
                out.append(lines[j])  # closing fence
            i = j + 1
            continue
        out.append(line)
        i += 1
    if changed:
        rep["fixed"].add("MD040")
    return "\n".join(out)


# --------------------------------------------------------------------------- #
# MD029 -- col-0 table/code wedged inside an ordered list
# --------------------------------------------------------------------------- #
OL_ITEM_RE = re.compile(r"^(\d+)\.\s")


def fix_ordered_list_blocks(text, rep):
    """Re-indent ONLY a table block wedged directly between two ordered-list
    items (the MD029-breaking case). Headings, prose, and code are never moved --
    a heading between two lists means they are *separate* lists, not a wedge.
    """
    lines = text.split("\n")
    mask = fence_mask(lines)  # True inside fenced code (skip example tables)
    n = len(lines)
    out = list(lines)
    changed = False

    def prev_nb(idx):
        j = idx - 1
        while j >= 0 and out[j].strip() == "":
            j -= 1
        return j

    def next_nb(idx):
        j = idx
        while j < n and out[j].strip() == "":
            j += 1
        return j if j < n else -1

    i = 0
    while i < n:
        if (not mask[i]) and _is_table_row(out[i]) and out[i][:1] not in (" ", "\t"):
            start = i
            while i < n and (not mask[i]) and _is_table_row(out[i]) and out[i][:1] not in (" ", "\t"):
                i += 1
            end = i  # exclusive
            p, nx = prev_nb(start), next_nb(end)
            pre_ok = p >= 0 and (bool(OL_ITEM_RE.match(out[p])) or out[p][:1] in (" ", "\t"))
            post_ok = nx >= 0 and bool(OL_ITEM_RE.match(out[nx]))
            if pre_ok and post_ok:
                for k in range(start, end):
                    if out[k].strip():
                        out[k] = "   " + out[k]
                changed = True
        else:
            i += 1
    if changed:
        rep["fixed"].add("MD029")
    return "\n".join(out)


# --------------------------------------------------------------------------- #
# Broken intra-repo .md links
# --------------------------------------------------------------------------- #
LINK_RE = re.compile(r"\]\(([^)]+)\)")
RB_RE = re.compile(r"(RB-(\d{2,3}))-[A-Za-z0-9-]+\.md")


def build_canonical_maps(root):
    by_rb = {}
    by_base = {}
    for p in globmod.glob(os.path.join(root, "**", "*.md"), recursive=True):
        base = os.path.basename(p)
        by_base.setdefault(base, []).append(p)
        m = re.match(r"RB-(\d{2,3})-", base)
        if m:
            by_rb.setdefault(m.group(1), []).append(p)
    return by_rb, by_base


def fix_links(text, path, maps, rep):
    by_rb, by_base = maps
    d = os.path.dirname(os.path.abspath(path))
    changed = False

    def _repl(m):
        nonlocal changed
        target = m.group(1).strip()
        if target.startswith(("http://", "https://", "#", "mailto:")):
            return m.group(0)
        pathpart = target.split("#")[0]
        anchor = target[len(pathpart):]
        if not pathpart or not pathpart.endswith(".md"):
            return m.group(0)
        resolved = os.path.normpath(os.path.join(d, pathpart))
        if os.path.exists(resolved):
            return m.group(0)
        # try RB-number remap
        cand = None
        rbm = RB_RE.search(os.path.basename(pathpart))
        if rbm and rbm.group(2) in by_rb and len(by_rb[rbm.group(2)]) == 1:
            cand = by_rb[rbm.group(2)][0]
        else:
            base = os.path.basename(pathpart)
            if base in by_base and len(by_base[base]) == 1:
                cand = by_base[base][0]
        if not cand:
            rep["escalate"].append(
                {"class": "link", "detail": "unresolved link %r in %s" % (target, os.path.basename(path))}
            )
            return m.group(0)
        rel = os.path.relpath(cand, d)
        changed = True
        rep["links_repaired"].append("%s -> %s" % (pathpart, rel))
        return "](" + rel + anchor + ")"

    lines = text.split("\n")
    mask = fence_mask(lines)
    for i, line in enumerate(lines):
        if mask[i]:
            continue  # never rewrite a link shown inside a fenced code example
        masked, spans = _mask_inline_code(line)
        masked = LINK_RE.sub(_repl, masked)
        lines[i] = _unmask_inline_code(masked, spans)
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Spell / typos
# --------------------------------------------------------------------------- #
def _looks_like_identifier(tok):
    """High-precision test for a code identifier that is safe to auto-allowlist.

    Deliberately conservative: only structural identifiers qualify (a digit, a
    `- . _ /` separator, or genuine mixed case with BOTH a lowercase letter and
    an INTERNAL uppercase letter, e.g. `consecutiveSuccessLimit`). A merely
    capitalized word -- proper noun OR a sentence-start typo like `Coverge` --
    does NOT qualify, nor does an all-caps token (`PARCER`, `BASF`): those are
    escalated for a human/agent to confirm. Never auto-allowlist on capitalization
    alone -- allowlisting a misspelling silently suppresses a real defect.
    """
    if any(ch.isdigit() for ch in tok):
        return True
    if any(c in tok for c in "-._/"):
        return True
    has_lower = any(c.islower() for c in tok)
    has_inner_upper = any(c.isupper() for c in tok[1:])
    return has_lower and has_inner_upper


def run_typos(paths):
    """Return list of (token, suggestion). Empty if typos unavailable."""
    from shutil import which

    binary = which("typos") or os.path.expanduser("~/.cargo/bin/typos")
    if not os.path.exists(binary) and not which("typos"):
        return None
    try:
        proc = subprocess.run(
            [binary, *paths], capture_output=True, text=True, timeout=60
        )
    except (subprocess.SubprocessError, OSError):
        return None
    hits = []
    for m in re.finditer(r"`([^`]+)` should be `([^`]+)`", proc.stdout + proc.stderr):
        hits.append((m.group(1), m.group(2)))
    return hits


def spell_pass(paths, rep, allowlist):
    hits = run_typos(paths)
    if hits is None:
        rep["escalate"].append({"class": "spell", "detail": "typos binary unavailable -- run manually"})
        return
    seen = set()
    for tok, sug in hits:
        if tok in seen:
            continue
        seen.add(tok)
        if _looks_like_identifier(tok):
            allowlist.add(tok)
            rep["allowlist_candidates"].add(tok)
        else:
            rep["escalate"].append(
                {"class": "typo", "detail": "%r -> %r (reword; not auto-changed)" % (tok, sug)}
            )


def apply_allowlist(repo_root, words):
    """Add proper-noun tokens to _typos.toml [default.extend-words]."""
    if not words:
        return []
    toml = os.path.join(repo_root, "_typos.toml")
    existing = ""
    if os.path.exists(toml):
        existing = open(toml, encoding="utf-8").read()
    added = []
    new_lines = []
    for w in sorted(words):
        if re.search(r'^\s*%s\s*=' % re.escape(w), existing, re.M):
            continue
        new_lines.append('%s = "%s"' % (w, w))
        added.append(w)
    if not added:
        return []
    if "[default.extend-words]" in existing:
        existing = existing.replace(
            "[default.extend-words]",
            "[default.extend-words]\n" + "\n".join(new_lines),
            1,
        )
    else:
        if existing and not existing.endswith("\n"):
            existing += "\n"
        existing += "\n[default.extend-words]\n" + "\n".join(new_lines) + "\n"
    open(toml, "w", encoding="utf-8").write(existing)
    return added


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def apply_text_passes(text, path, maps, rep):
    # MD025 needs the whole document (frontmatter + body).
    text = fix_frontmatter_title(text, rep)
    # All other passes operate on the BODY only -- YAML frontmatter is not
    # Markdown; its pipes, angle brackets, and emphasis must be left untouched.
    fm, body = split_frontmatter(text)
    body = fix_tables(body, rep)
    body = fix_placeholders(body, rep)
    body = fix_bold_as_heading(body, rep)
    body = fix_ordered_list_blocks(body, rep)
    body = fix_unlabeled_fences(body, rep)
    body = fix_links(body, path, maps, rep)
    return ("\n".join(fm) + "\n" + body) if fm else body


def process_file(path, maps, write):
    orig = open(path, encoding="utf-8").read()
    rep = {
        "file": path,
        "fixed": set(),
        "links_repaired": [],
        "allowlist_candidates": set(),
        "escalate": [],
        "residual": "",
        "changed": False,
    }
    text = apply_text_passes(orig, path, maps, rep)

    d = os.path.dirname(os.path.abspath(path)) or "."
    if write:
        if text != orig:
            open(path, "w", encoding="utf-8").write(text)
        # `--fix` corrects and reports residual in one pass (no second lint).
        rc, diag = core.run_lint(path, fix=True)
        final = open(path, encoding="utf-8").read()
    else:
        fd, tmp = tempfile.mkstemp(suffix=".md", dir=d)
        os.close(fd)
        try:
            open(tmp, "w", encoding="utf-8").write(text)
            rc, diag = core.run_lint(tmp, fix=True)
            final = open(tmp, encoding="utf-8").read()
            rep["residual"] = core.trim_diag(diag) if rc not in (0, None) else ""
        finally:
            os.remove(tmp)
        rep["changed"] = final != orig
        if rep["changed"]:
            rep["_diff"] = "".join(
                difflib.unified_diff(
                    orig.splitlines(keepends=True),
                    final.splitlines(keepends=True),
                    fromfile=path, tofile=path + " (remediated)",
                )
            )
        return rep, final

    rep["residual"] = core.trim_diag(diag) if rc not in (0, None) else ""
    rep["changed"] = final != orig
    return rep, final


def expand_targets(args_paths):
    out = []
    for a in args_paths:
        if any(ch in a for ch in "*?["):
            out.extend(globmod.glob(a, recursive=True))
        else:
            out.append(a)
    return [p for p in out if core.is_markdown(p) and os.path.isfile(p)]


def git_root(start):
    try:
        proc = subprocess.run(
            ["git", "-C", start, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass
    return start


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-spell", action="store_true")
    ap.add_argument("--apply-allowlist", action="store_true")
    ap.add_argument("--root", default=None)
    a = ap.parse_args(argv)

    targets = expand_targets(a.paths)
    if not targets:
        print(json.dumps({"error": "no markdown files matched", "paths": a.paths}))
        return 2

    write = not (a.check or a.dry_run)
    root = a.root or git_root(os.path.dirname(os.path.abspath(targets[0])) or ".")
    maps = build_canonical_maps(root)

    allowlist = set()
    reports = []
    for path in sorted(set(targets)):
        rep, _ = process_file(path, maps, write)
        reports.append(rep)

    if not a.no_spell:
        srep = {"file": "<spell>", "fixed": set(), "links_repaired": [],
                "allowlist_candidates": set(), "escalate": [], "residual": "",
                "changed": False}
        spell_pass(sorted(set(targets)), srep, allowlist)
        reports.append(srep)
        if write and a.apply_allowlist and allowlist:
            added = apply_allowlist(root, allowlist)
            srep["allowlist_added"] = added

    # serialize (sets -> sorted lists)
    out = []
    any_change = False
    any_escalate = False
    for r in reports:
        any_change = any_change or r.get("changed")
        any_escalate = any_escalate or bool(r.get("escalate"))
        item = {
            "file": os.path.relpath(r["file"]) if r["file"] != "<spell>" else "<spell>",
            "changed": r.get("changed", False),
            "fixed": sorted(r["fixed"]),
            "links_repaired": r["links_repaired"],
            "allowlist_candidates": sorted(r["allowlist_candidates"]),
            "escalate": r["escalate"],
            "residual": r["residual"],
        }
        if "allowlist_added" in r:
            item["allowlist_added"] = r["allowlist_added"]
        if a.dry_run and r.get("_diff"):
            item["diff"] = r["_diff"]
        out.append(item)

    print(json.dumps({"mode": "check" if a.check else "dry-run" if a.dry_run else "write",
                      "root": root, "results": out}, indent=2))
    if a.check and (any_change or any_escalate):
        return 1
    return 1 if any_escalate else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
