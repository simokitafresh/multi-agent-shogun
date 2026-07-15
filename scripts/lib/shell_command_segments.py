#!/usr/bin/env python3
"""Quote-aware shell command segmentation shared by Bash hook classifiers."""
from __future__ import annotations

import re
import shlex

_HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_SEPARATORS = {"&&", ";", "||", "|", "&", "\n"}
_REDIRECT_RE = re.compile(r"^[0-9]*[><]")
_BARE_REDIRECT_RE = re.compile(r"^[0-9]*(>>?|<)$")


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

    # Claude Code appends "2>&1" to bash commands. shlex with
    # punctuation_chars=";&|\n" has no concept of shell redirection, so a
    # redirect operator (2>, >, <, ...) and its target are ordinary tokens
    # to it, and "&" inside "2>&1" is indistinguishable from the "&"
    # background/separator operator. Consume redirect operators and their
    # targets here — including the "&"+word fd-duplication form (2>&1) and
    # the plain "> file" form — so neither leaks into a segment as a fake
    # command token nor its target survives as an orphan segment
    # (2026-07-15 shogun root cause; same operator pattern as
    # guard14_db_trust_classify._strip_shell_redirects).
    segments: list[list[str]] = []
    current: list[str] = []
    index = 0
    total = len(tokens)
    while index < total:
        token = tokens[index]
        if _REDIRECT_RE.match(token):
            index += 1
            # A bare operator (">", "2>", ...) has its target as a separate
            # token — either "&"+word (fd-dup, e.g. "2>" "&" "1") or a plain
            # following word (e.g. "cmd" ">" "out"). An attached-target
            # token (e.g. ">out", "2>/tmp/x" — no space before the target)
            # already contains its target; consuming the *next* token too
            # would eat an unrelated positional argument that follows it.
            if _BARE_REDIRECT_RE.match(token):
                if index < total and tokens[index] == "&":
                    index += 1
                    if index < total and tokens[index] not in _SEPARATORS:
                        index += 1
                elif index < total and tokens[index] not in _SEPARATORS:
                    index += 1
            continue
        if token in _SEPARATORS:
            if current:
                segments.append(current)
            current = []
            index += 1
            continue
        current.append(token)
        index += 1
    if current:
        segments.append(current)
    return segments
