#!/usr/bin/env python3
"""Normalize an Atom/RSS XML document (read from stdin) to JSON (written to
stdout), for research-harness-template#418's feed-based Source Connectors.
Kept as its own file rather than an inline heredoc: a heredoc would consume
the shell's stdin as the script source, leaving nothing for the real feed
document to be piped through.
"""
import sys
import json
import xml.etree.ElementTree as ET


def strip_ns(tag):
    return tag.split("}", 1)[-1] if "}" in tag else tag


def elem_to_dict(el):
    d = {"_tag": strip_ns(el.tag)}
    text = (el.text or "").strip()
    if text:
        d["_text"] = text
    for k, v in el.attrib.items():
        d[f"@{strip_ns(k)}"] = v
    children = {}
    for child in el:
        ctag = strip_ns(child.tag)
        cval = elem_to_dict(child)
        if ctag in children:
            if not isinstance(children[ctag], list):
                children[ctag] = [children[ctag]]
            children[ctag].append(cval)
        else:
            children[ctag] = cval
    d.update(children)
    return d


def main():
    data = sys.stdin.read()
    root = ET.fromstring(data)

    entries = []
    for tag in ("entry", "item"):
        found = root.findall(f".//{{*}}{tag}")
        if found:
            entries = [elem_to_dict(e) for e in found]
            break

    json.dump({"entries": entries}, sys.stdout)


if __name__ == "__main__":
    main()
