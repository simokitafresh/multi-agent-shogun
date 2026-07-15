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

# Table-driven exec-wrapper unwrap (2026-07-15 karo RC2: command/nohup/nice/
# timeout/setsid all reach the wrapped program without being "git"
# themselves — an enumerate-as-you-find-them approach chases bypasses
# forever, so every transparent process launcher is declared once here:
#   value_opts  — this wrapper's own options that consume a following token
#   stop_tokens — no-value tokens/markers specific to this wrapper (e.g.
#                 "--" for the `command` builtin)
#   positional_skip — non-option positional args this wrapper itself
#                 consumes AFTER its flags but BEFORE the wrapped command
#                 (e.g. `timeout 5 CMD...` — the duration).
# Any other "-x" token encountered before the wrapped command is treated as
# a no-value flag of the wrapper (safe default: still unwraps to the real
# command instead of misreading it as the program).
_EXEC_WRAPPERS = {
    "command": {"value_opts": set(), "stop_tokens": {"--"}, "positional_skip": 0},
    "nohup": {"value_opts": set(), "stop_tokens": set(), "positional_skip": 0},
    "nice": {"value_opts": {"-n", "--adjustment"}, "stop_tokens": set(), "positional_skip": 0},
    "setsid": {"value_opts": set(), "stop_tokens": set(), "positional_skip": 0},
    "timeout": {
        "value_opts": {"-k", "--kill-after", "-s", "--signal"},
        "stop_tokens": {"--foreground", "--preserve-status", "--"},
        "positional_skip": 1,
    },
    "exec": {"value_opts": {"-a"}, "stop_tokens": {"-c", "-l"}, "positional_skip": 0},
    "stdbuf": {"value_opts": {"-i", "-o", "-e"}, "stop_tokens": set(), "positional_skip": 0},
}


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
    """Strip leading VAR=value assignments and known exec-wrapper programs.

    `env git stash`, `command git stash`, `nohup git stash`,
    `timeout 5 git stash`, and `FOO=bar git stash` all reach the real
    `git stash` invocation through a launcher the naive "is seg[0] literally
    'git'" check never sees. Peel these layers (in any order, any number of
    times — e.g. `command env timeout 5 git stash`) until the remaining
    tokens start with the actual wrapped program.
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
        elif prog in _EXEC_WRAPPERS:
            spec = _EXEC_WRAPPERS[prog]
            tokens.pop(0)
            changed = True
            while tokens:
                if tokens[0] in spec["value_opts"]:
                    tokens.pop(0)
                    if tokens:
                        tokens.pop(0)
                    continue
                if tokens[0] in spec["stop_tokens"]:
                    tokens.pop(0)
                    continue
                if tokens[0].startswith("-"):
                    tokens.pop(0)
                    continue
                break
            for _ in range(spec["positional_skip"]):
                if tokens and not tokens[0].startswith("-"):
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
