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
import sys

from shell_command_segments import segment_tokens

_READONLY_STASH_SUBCOMMANDS = {"list", "show"}

# git global options that consume a following value token, so the real
# "stash" subcommand token isn't mistaken for an option's value (or vice
# versa). Mirrors the subset relevant to reaching a subcommand.
_GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "--git-dir", "--work-tree", "-c"}


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


def classify(command):
    segs = segment_tokens(command)
    if segs is None:
        return "block"
    for seg in segs:
        if not seg:
            continue
        prog = os.path.basename(seg[0])
        if prog != "git":
            continue
        args = seg[1:]
        subcommand_index = _first_positional_index_after_git(args)
        if subcommand_index is None or args[subcommand_index] != "stash":
            continue
        stash_sub = _next_positional(args, subcommand_index)
        if stash_sub not in _READONLY_STASH_SUBCOMMANDS:
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
