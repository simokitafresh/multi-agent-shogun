#!/usr/bin/env bash
# PreToolUse hook: block destructive Bash commands (D001-D008).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

emit_deny() {
    local reason="$1"
    jq -cn --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
}

payload="$(cat)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "$tool_name" != "Bash" ]; then
    exit 0
fi

command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [ -z "$command" ]; then
    exit 0
fi

reason="$(
    COMMAND="$command" PROJECT_ROOT="$PROJECT_ROOT" python3 - <<'PY'
import os
import re
import shlex

command = os.environ.get("COMMAND", "")
project_root = os.path.realpath(os.environ.get("PROJECT_ROOT", "."))
cwd = os.path.realpath(os.getcwd())


def split_segments(cmd: str):
    return [seg.strip() for seg in re.split(r"(?:&&|\|\||;|\|)", cmd) if seg.strip()]


def outside_project(path: str):
    expanded = os.path.expanduser(path)
    prefix = re.split(r"[\*\?\[]", expanded, maxsplit=1)[0]
    if prefix == "":
        prefix = expanded or "."
    candidate = prefix if os.path.isabs(prefix) else os.path.join(cwd, prefix)
    resolved = os.path.realpath(candidate)
    in_project = resolved == project_root or resolved.startswith(project_root + os.sep)
    return (not in_project), resolved


def is_system_path(resolved: str):
    if resolved == "/":
        return True
    prefixes = (
        "/etc",
        "/usr",
        "/var",
        "/bin",
        "/sbin",
        "/lib",
        "/lib64",
        "/opt",
        "/home",
        "/mnt/c",
        "/mnt/d",
    )
    return any(resolved == p or resolved.startswith(p + "/") for p in prefixes)


def check_pipe_to_shell(cmd: str):
    patterns = (
        r"(^|[ \t;&|])curl\b[^\n|]*\|[ \t]*(bash|sh)\b",
        r"(^|[ \t;&|])wget\b[^\n|]*-O-[^\n|]*\|[ \t]*sh\b",
    )
    for pattern in patterns:
        if re.search(pattern, cmd):
            return "D008: pipe-to-shell pattern is forbidden (curl/wget -> sh/bash)"
    return ""


def check_rm(tokens):
    has_r = False
    has_f = False
    paths = []
    after_double_dash = False

    for tok in tokens[1:]:
        if tok == "--":
            after_double_dash = True
            continue
        if not after_double_dash and tok.startswith("-"):
            if tok == "--recursive":
                has_r = True
                continue
            if tok == "--force":
                has_f = True
                continue
            flags = tok[1:].lower()
            if "r" in flags:
                has_r = True
            if "f" in flags:
                has_f = True
            continue
        paths.append(tok)

    if not (has_r and has_f):
        return ""

    for raw in paths:
        if raw in ("/", "~") or raw.startswith("/mnt/*") or raw.startswith("/home/*"):
            return "D001: rm -rf on root/system wildcard path is forbidden"
        outside, resolved = outside_project(raw)
        if outside:
            return f"D002: rm -rf outside project tree is forbidden ({resolved})"
    return ""


def check_git(tokens):
    if len(tokens) < 2:
        return ""

    sub = tokens[1]
    args = tokens[2:]

    if sub == "push":
        if "--force-with-lease" not in args and ("--force" in args or "-f" in args):
            return "D003: git push --force/-f is forbidden (use --force-with-lease)"
        return ""

    if sub == "reset" and "--hard" in args:
        return "D004: git reset --hard is forbidden"

    if sub == "checkout" and "--" in args:
        idx = args.index("--")
        if idx + 1 < len(args) and args[idx + 1] == ".":
            return "D004: git checkout -- . is forbidden"

    if sub == "restore" and "." in args:
        return "D004: git restore . is forbidden"

    if sub == "clean":
        for tok in args:
            if tok == "--force":
                return "D004: git clean -f/--force is forbidden"
            if tok.startswith("-") and "f" in tok[1:] and tok != "-n":
                return "D004: git clean -f/--force is forbidden"
    return ""


def check_recursive_system_chmod_chown(tokens, cmd0):
    recursive = False
    for tok in tokens[1:]:
        if tok == "--recursive":
            recursive = True
            break
        if tok.startswith("-") and "R" in tok[1:]:
            recursive = True
            break
    if not recursive:
        return ""

    non_options = [t for t in tokens[1:] if not t.startswith("-")]
    if not non_options:
        return ""

    # chmod/chown both have one non-path token before paths (mode or owner)
    paths = non_options[1:] if len(non_options) >= 2 else non_options
    for raw in paths:
        outside, resolved = outside_project(raw)
        if outside and is_system_path(resolved):
            return f"D005: {cmd0} -R on system path is forbidden ({resolved})"
    return ""


reason = check_pipe_to_shell(command)
if reason:
    print(reason)
    raise SystemExit(0)

for segment in split_segments(command):
    try:
        tokens = shlex.split(segment, posix=True)
    except ValueError:
        continue

    if not tokens:
        continue

    cmd0 = os.path.basename(tokens[0])

    if cmd0 in {"sudo", "su"}:
        print("D005: sudo/su is forbidden")
        raise SystemExit(0)

    if cmd0 in {"kill", "killall", "pkill"}:
        print("D006: kill/killall/pkill is forbidden")
        raise SystemExit(0)

    if cmd0 == "tmux" and len(tokens) >= 2 and tokens[1] in {"kill-server", "kill-session"}:
        print("D006: tmux kill-server/kill-session is forbidden")
        raise SystemExit(0)

    if cmd0 == "rm":
        reason = check_rm(tokens)
        if reason:
            print(reason)
            raise SystemExit(0)

    if cmd0 == "git":
        reason = check_git(tokens)
        if reason:
            print(reason)
            raise SystemExit(0)

    if cmd0 in {"chmod", "chown"}:
        reason = check_recursive_system_chmod_chown(tokens, cmd0)
        if reason:
            print(reason)
            raise SystemExit(0)

    if cmd0.startswith("mkfs") or cmd0 in {"fdisk", "mount", "umount"}:
        print(f"D007: {cmd0} is forbidden")
        raise SystemExit(0)

    if cmd0 == "dd" and any(tok.startswith("if=") for tok in tokens[1:]):
        print("D007: dd with if= is forbidden")
        raise SystemExit(0)
PY
)"

if [ -n "$reason" ]; then
    emit_deny "$reason"
fi

exit 0
