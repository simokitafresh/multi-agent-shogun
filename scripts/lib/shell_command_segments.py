#!/usr/bin/env python3
"""Quote-aware shell command segmentation shared by Bash hook classifiers."""
from __future__ import annotations

import re
import shlex

_HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_SEPARATORS = {"&&", ";", "||", "|", "&", "\n"}


def strip_heredocs(text: str) -> str:
    lines = text.split("\n")
    output: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        output.append(line)
        index += 1
        match = _HEREDOC_RE.search(line)
        if not match:
            continue
        strip_tabs = match.group(1) == "-"
        delimiter = match.group(3)
        while index < len(lines):
            body_line = lines[index]
            probe = body_line.lstrip("\t") if strip_tabs else body_line
            index += 1
            if probe == delimiter:
                break
    return "\n".join(output)


def segment_tokens(command: str) -> list[list[str]] | None:
    """Return argv tokens per shell segment; None means malformed quoting."""
    try:
        lexer = shlex.shlex(
            strip_heredocs(command), posix=True, punctuation_chars=";&|\n"
        )
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return None

    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in _SEPARATORS:
            if current:
                segments.append(current)
            current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    return segments
