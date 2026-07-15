#!/usr/bin/env python3
"""git stash mutation guard — single SSOT for shared-worktree stash safety.

cmd_karo_ci_red_remaining_unit_202607151950: this task family runs multiple
ninjas directly on the shared main working tree (no per-ninja isolated
worktree). A top-level `git stash` mutates the ONE shared index/working tree
for everyone at once — 2026-07-15 20:27 an agent ran a bare `git stash` and
silently swept 23 tracked files (spanning multiple agents' in-progress diffs
and operational state) away, requiring a manual `stash@{0} apply` recovery.

Classification is argv-position-based (not substring/regex on raw command
text, matching the Guard 5→17 lesson from the same task): a segment blocks
only when a real `git` invocation's first `stash` (or stash-aliased)
positional subcommand is anything other than a read-only one.

2026-07-15 karo RC2/RC3: enumerating known exec-wrapper program names
(env, command, nohup, nice, timeout, setsid, ..., then time, ionice,
taskset, chrt, xargs, ...) is an unwinnable chase — any current or future
launcher this doesn't yet name is a bypass. Every one of those wrappers
shares one structural property: the wrapped command's argv tokens appear
later in the SAME shell segment (same exec argv), verbatim. So instead of
parsing each wrapper's own option grammar, recursively re-evaluate every
suffix of the segment's token list — this generalizes to any launcher
without a maintained table. A quoted multi-word explanation (a single
token, e.g. an inbox_write.sh message) never collapses to a bare "git"
token, so it is never mistaken for an invocation.

`git -c alias.NAME=stash NAME` (and `-calias.NAME=stash`) is a second,
unrelated bypass class: git's own alias mechanism, not a process launcher.
`-c` config overrides are parsed for `alias.*` definitions and an alias
that expands to a stash (sub)command is treated exactly like a literal
`stash` subcommand.

Output: "block" or "allow" on stdout.
"""

import os
import re
import sys

from shell_command_segments import segment_tokens

_READONLY_STASH_SUBCOMMANDS = {"list", "show"}

# git global options that consume a following value token, so the real
# "stash" subcommand token isn't mistaken for an option's value (or vice
# versa). Mirrors the subset relevant to reaching a subcommand.
_GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "--git-dir", "--work-tree", "-c"}

_SHELL_DASH_C_PROGS = {"bash", "sh", "zsh", "dash", "ksh"}

_ALIAS_RE = re.compile(r"^alias\.([A-Za-z0-9_-]+)=(.*)$")


def _first_positional_index_after_git(args):
    """Return the index of the first non-option positional token in args, or None."""
    skip_value = False
    for index, arg in enumerate(args):
        if skip_value:
            skip_value = False
            continue
        if arg in _GIT_GLOBAL_OPTS_WITH_VALUE:
            skip_value = True
            continue
        if arg.startswith("--git-dir=") or arg.startswith("--work-tree=") or arg.startswith("-c"):
            continue
        if arg.startswith("-"):
            continue
        return index
    return None


def _next_positional(args, after_index):
    """Return the first non-option token strictly after after_index, or None (bare)."""
    for token in args[after_index + 1 :]:
        if token.startswith("-"):
            continue
        return token
    return None


def _collect_git_aliases(args):
    """Return {alias_name: expansion} from -c/-cVALUE alias.NAME=EXPANSION overrides."""
    aliases = {}
    index = 0
    while index < len(args):
        token = args[index]
        if token == "-c":
            if index + 1 < len(args):
                match = _ALIAS_RE.match(args[index + 1])
                if match:
                    aliases[match.group(1)] = match.group(2)
            index += 2
            continue
        if token.startswith("-c") and not token.startswith("--"):
            match = _ALIAS_RE.match(token[2:])
            if match:
                aliases[match.group(1)] = match.group(2)
        index += 1
    return aliases


def _stash_subcommand_blocks(args, subcommand_index):
    """args[subcommand_index] is the literal "stash" token; check what follows it."""
    stash_sub = _next_positional(args, subcommand_index)
    return stash_sub not in _READONLY_STASH_SUBCOMMANDS


def _segment_blocks(tokens):
    if not tokens:
        return False
    prog = os.path.basename(tokens[0])

    if prog == "git":
        args = tokens[1:]
        subcommand_index = _first_positional_index_after_git(args)
        if subcommand_index is None:
            return False
        subcommand = args[subcommand_index]
        if subcommand == "stash":
            return _stash_subcommand_blocks(args, subcommand_index)
        alias_value = _collect_git_aliases(args).get(subcommand)
        if alias_value is None:
            return False
        alias_tokens = alias_value.split()
        if not alias_tokens or alias_tokens[0] != "stash":
            return False
        if len(alias_tokens) > 1:
            return alias_tokens[1] not in _READONLY_STASH_SUBCOMMANDS
        stash_sub = _next_positional(args, subcommand_index)
        return stash_sub not in _READONLY_STASH_SUBCOMMANDS

    # `bash -c '...'` (and sh/zsh/dash/ksh) hands an entire nested shell
    # command as a single string argument. The tokens inside are invisible
    # to token-position scanning of the OUTER command, so recurse into a
    # fresh parse of that string instead of scanning it as ordinary tokens.
    if prog in _SHELL_DASH_C_PROGS:
        args = tokens[1:]
        for index, arg in enumerate(args):
            if arg == "-c":
                nested = args[index + 1] if index + 1 < len(args) else None
                if nested is not None:
                    return classify(nested) == "block"
                break
            if arg.startswith("-") and not arg.startswith("--") and "c" in arg[1:]:
                # combined short flags, e.g. "-lc" — value is the next token
                nested = args[index + 1] if index + 1 < len(args) else None
                if nested is not None:
                    return classify(nested) == "block"
                break
        # No -c found (e.g. `bash script.sh ...`): fall through to the
        # generic launcher fallback below rather than declaring this safe.

    # Generic launcher fallback: env, command, VAR=val prefixes, nohup,
    # nice, timeout, setsid, time, /usr/bin/time, ionice, taskset, chrt,
    # xargs, and any future exec-launcher not named above all place the
    # wrapped command's tokens later in this same list. Recurse on every
    # suffix rather than parsing each wrapper's own option grammar.
    for index in range(1, len(tokens)):
        if _segment_blocks(tokens[index:]):
            return True
    return False


def classify(command):
    segs = segment_tokens(command)
    if segs is None:
        return "block"
    for seg in segs:
        if not seg:
            continue
        if _segment_blocks(seg):
            return "block"
    return "allow"


def main():
    command = os.environ.get("GIT_STASH_GUARD_COMMAND")
    if command is None:
        if len(sys.argv) > 1:
            command = sys.argv[1]
        else:
            command = sys.stdin.read()
    print(classify(command))


if __name__ == "__main__":
    main()
