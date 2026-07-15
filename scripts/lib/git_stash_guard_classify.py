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
only when its actual program is "git" (optionally via `git -C <path> ...`)
and its first `stash` positional subcommand is anything other than a
read-only one.

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

_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# env options that consume a following value token (GNU/POSIX subset
# relevant to reaching the wrapped command). All other "-x" tokens before
# the wrapped command are treated as env's own no-value flags.
_ENV_VALUE_OPTS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}

_SHELL_DASH_C_PROGS = {"bash", "sh", "zsh", "dash", "ksh"}


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


def _unwrap_indirection(tokens):
    """Strip leading VAR=value assignments and env/command wrappers.

    `env git stash`, `command git stash`, and `FOO=bar git stash` all reach
    the real `git stash` invocation through a launcher the naive "is seg[0]
    literally 'git'" check never sees. Peel these layers (in any order, any
    number of times — e.g. `command env git stash`) until the remaining
    tokens start with the actual program.
    """
    tokens = list(tokens)
    changed = True
    while changed and tokens:
        changed = False
        while tokens and _ASSIGNMENT_RE.match(tokens[0]):
            tokens.pop(0)
            changed = True
        if not tokens:
            break
        prog = os.path.basename(tokens[0])
        if prog == "env":
            tokens.pop(0)
            changed = True
            while tokens:
                if _ASSIGNMENT_RE.match(tokens[0]):
                    tokens.pop(0)
                    continue
                if tokens[0] in _ENV_VALUE_OPTS:
                    tokens.pop(0)
                    if tokens:
                        tokens.pop(0)
                    continue
                if tokens[0].startswith("-"):
                    tokens.pop(0)
                    continue
                break
        elif prog == "command":
            tokens.pop(0)
            changed = True
            while tokens and tokens[0] in ("-p", "-v", "-V"):
                tokens.pop(0)
    return tokens


def _segment_blocks(seg):
    tokens = _unwrap_indirection(seg)
    if not tokens:
        return False
    prog = os.path.basename(tokens[0])
    args = tokens[1:]

    # `bash -c '...'` (and sh/zsh/dash/ksh) hands an entire nested shell
    # command as a single string argument. The tokens inside are invisible
    # to segment-level parsing of the OUTER command, so recurse into them.
    if prog in _SHELL_DASH_C_PROGS:
        for index, arg in enumerate(args):
            if arg == "-c":
                nested = args[index + 1] if index + 1 < len(args) else None
                if nested is not None:
                    return classify(nested) == "block"
                break
            if arg.startswith("-") and "c" in arg[1:] and not arg.startswith("--"):
                # combined short flags, e.g. "-lc" — value is the next token
                nested = args[index + 1] if index + 1 < len(args) else None
                if nested is not None:
                    return classify(nested) == "block"
                break
        return False

    if prog != "git":
        return False
    subcommand_index = _first_positional_index_after_git(args)
    if subcommand_index is None or args[subcommand_index] != "stash":
        return False
    stash_sub = _next_positional(args, subcommand_index)
    return stash_sub not in _READONLY_STASH_SUBCOMMANDS


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
