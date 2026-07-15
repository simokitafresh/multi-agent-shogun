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

2026-07-15 karo RC2/RC3/RC4: two competing failure modes were both proven by
direct measurement:
  - RC2/RC3: enumerating known exec-wrapper program names (env, command,
    nohup, ...) is an unwinnable chase — a fixed set of untested wrapper
    names (time, ionice, taskset, chrt, xargs, ...) bypassed it.
  - RC3's fix (recursing on every token-list suffix to catch ANY unknown
    wrapper) proved to have the opposite, WORSE failure: `echo git stash`,
    `printf %s git stash`, `rg -n git stash scripts`, `python3 tool.py git
    stash`, `bash script.sh git stash`, and `inbox_write.sh karo git stash
    report` all falsely BLOCKed — "git"/"stash" as a data/search-term/
    positional-argument to an ordinary command is structurally
    indistinguishable from a real nested invocation without knowing what
    the leading program actually does with its trailing arguments.
Unknown-wrapper detection and zero false positives on arbitrary arguments
are provably NOT simultaneously achievable from argv shape alone (RC4
counter-examples). Per karo's RC4 direction, this module adopts the
explicit-SSOT / unknown-fails-open design: `_EXEC_WRAPPERS` is the single
enumerated table of known process launchers (env, command, nohup, nice,
timeout, setsid, exec, stdbuf, time, ionice, taskset, chrt, xargs) that
this classifier unwraps; a program NOT in this table is never treated as a
wrapper, so its trailing tokens are always its own data, never rechecked.
This table lives in exactly one place (this file), imported by both the
production hook and the legacy GA-239 path — no per-hook duplication.

`git -c alias.NAME=stash NAME` (and `-calias.NAME=stash`) is a separate,
unrelated bypass class: git's own alias mechanism, not a process launcher,
and precisely parseable from git's own `-c` option syntax without the
ambiguity above. `-c` config overrides are parsed for `alias.*` definitions
and an alias that expands to a stash (sub)command is treated exactly like a
literal `stash` subcommand.

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

_ALIAS_RE = re.compile(r"^alias\.([A-Za-z0-9_-]+)=(.*)$")

# env options that consume a following value token (GNU/POSIX subset
# relevant to reaching the wrapped command). Any other "-x" token before the
# wrapped command is treated as env's own no-value flag.
_ENV_VALUE_OPTS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}

_SHELL_DASH_C_PROGS = {"bash", "sh", "zsh", "dash", "ksh"}

# Single explicit SSOT of known process-launcher wrappers this classifier
# unwraps (karo RC4: enumerated table, not a per-hook duplicate; a program
# NOT listed here is never treated as a wrapper — its trailing tokens stay
# its own data and are never re-examined). Each entry:
#   value_opts  — this wrapper's own options that consume a following token
#   stop_tokens — no-value tokens/markers specific to this wrapper (e.g.
#                 "--" for the `command` builtin, "-c" for taskset's
#                 cpu-list-format flag)
#   positional_skip — non-option positional args this wrapper itself
#                 consumes AFTER its flags but BEFORE the wrapped command
#                 (e.g. `timeout 5 CMD...`, `taskset 0x1 CMD...`,
#                 `chrt 99 CMD...`).
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
    "time": {"value_opts": {"-o", "--output", "-f", "--format"}, "stop_tokens": set(), "positional_skip": 0},
    "ionice": {
        "value_opts": {"-c", "--class", "-n", "--classdata", "-p", "--pid"},
        "stop_tokens": {"-t", "--ignore"},
        "positional_skip": 0,
    },
    "taskset": {"value_opts": set(), "stop_tokens": {"-c", "--cpu-list", "-p", "--pid"}, "positional_skip": 1},
    "chrt": {
        "value_opts": set(),
        "stop_tokens": {"-f", "-r", "-o", "-i", "-b", "--fifo", "--rr", "--other", "--idle", "--batch"},
        "positional_skip": 1,
    },
    "xargs": {
        "value_opts": {
            "-I", "-L", "-n", "-P", "-s", "-a", "-d", "-E",
            "--replace", "--max-lines", "--max-args", "--max-procs",
            "--max-chars", "--arg-file", "--delimiter", "--eof-string",
        },
        "stop_tokens": {"-0", "-r", "-t", "-p", "-x", "-o", "--null", "--no-run-if-empty", "--interactive", "--verbose"},
        "positional_skip": 0,
    },
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


def _git_blocks(args):
    subcommand_index = _first_positional_index_after_git(args)
    if subcommand_index is None:
        return False
    subcommand = args[subcommand_index]
    if subcommand == "stash":
        stash_sub = _next_positional(args, subcommand_index)
        return stash_sub not in _READONLY_STASH_SUBCOMMANDS
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


def _unwrap_indirection(tokens):
    """Strip leading VAR=value assignments and known exec-wrapper programs.

    `env git stash`, `command git stash`, `nohup git stash`,
    `timeout 5 git stash`, `taskset -c 0 git stash`, and `FOO=bar git stash`
    all reach the real `git stash` invocation through a launcher the naive
    "is seg[0] literally 'git'" check never sees. Peel these layers (in any
    order, any number of times — e.g. `command env timeout 5 git stash`)
    until the remaining tokens start with the actual wrapped program. Only
    programs explicitly listed in `_EXEC_WRAPPERS` (or `env`) are unwrapped;
    everything else is left untouched (karo RC4: unknown programs fail
    open rather than being guessed at).
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

    if prog == "git":
        return _git_blocks(tokens[1:])

    # `bash -c '...'` (and sh/zsh/dash/ksh) hands an entire nested shell
    # command as a single string argument. The tokens inside are invisible
    # to token-position scanning of the OUTER command, so recurse into a
    # fresh parse of that string. Without an explicit "-c" flag, this is
    # `bash script.sh ...` — trailing tokens are the SCRIPT's own arguments
    # (opaque to us, never a nested invocation), so fail open rather than
    # guessing (karo RC4 counter-example: `bash script.sh git stash`).
    if prog in _SHELL_DASH_C_PROGS:
        args = tokens[1:]
        for index, arg in enumerate(args):
            if arg == "-c":
                nested = args[index + 1] if index + 1 < len(args) else None
                return nested is not None and classify(nested) == "block"
            if arg.startswith("-") and not arg.startswith("--") and "c" in arg[1:]:
                # combined short flags, e.g. "-lc" — value is the next token
                nested = args[index + 1] if index + 1 < len(args) else None
                return nested is not None and classify(nested) == "block"
        return False

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
