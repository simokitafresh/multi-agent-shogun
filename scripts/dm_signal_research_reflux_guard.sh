#!/usr/bin/env bash
# DM-Signal docs/research commit -> 本陣 research context reflux fingerprint guard.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_FILE="${DM_SIGNAL_REFLUX_CONTEXT_FILE:-$ROOT_DIR/context/dm-signal-research.md}"
DM_SIGNAL_REPO="${DM_SIGNAL_REPO:-/mnt/c/Python_app/DM-signal}"

usage() {
    echo "Usage: $0 prepare --repo PATH --mode synced|non-target --evidence TEXT" >&2
    echo "       $0 check --repo PATH" >&2
    echo "       $0 check-command COMMAND" >&2
}

repo_root() {
    git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

is_dm_signal_repo() {
    local actual expected
    actual="$(repo_root "$1")" || return 1
    expected="$(repo_root "$DM_SIGNAL_REPO")" || return 1
    [[ "$(realpath "$actual")" == "$(realpath "$expected")" ]]
}

staged_fingerprint() {
    local repo="$1"
    python3 - "$repo" <<'PY'
import hashlib
import subprocess
import sys

repo = sys.argv[1]
names = subprocess.run(
    ["git", "-C", repo, "diff", "--cached", "--name-only", "--diff-filter=ACMRD", "-z", "--", "docs/research"],
    check=True, capture_output=True,
).stdout.decode("utf-8", "surrogateescape").split("\0")
entries = []
for path in sorted(p for p in names if p):
    status = subprocess.run(
        ["git", "-C", repo, "diff", "--cached", "--name-status", "--", path],
        check=True, capture_output=True, text=True,
    ).stdout.split("\t", 1)[0].strip() or "?"
    blob_result = subprocess.run(
        ["git", "-C", repo, "rev-parse", f":{path}"],
        capture_output=True, text=True,
    )
    blob = blob_result.stdout.strip() if blob_result.returncode == 0 else "DELETED"
    entries.append(f"{status}\t{path}\t{blob}")
if not entries:
    raise SystemExit(3)
canonical = "\n".join(entries) + "\n"
print(hashlib.sha256(canonical.encode("utf-8", "surrogateescape")).hexdigest())
PY
}

has_staged_research() {
    git -C "$1" diff --cached --quiet -- docs/research || return 0
    return 1
}

check_repo() {
    local repo="$1" fingerprint recorded
    is_dm_signal_repo "$repo" || return 0
    has_staged_research "$repo" || return 0
    fingerprint="$(staged_fingerprint "$repo")" || {
        echo "BLOCK(GA-220): staged docs/research fingerprintを生成できない" >&2
        return 2
    }
    [[ -f "$CONTEXT_FILE" ]] || {
        echo "BLOCK(GA-220): reflux context欠落: $CONTEXT_FILE" >&2
        return 2
    }
    recorded="$(sed -n 's/.*dm_signal_research_reflux: fingerprint=\([0-9a-f]\{64\}\);.*/\1/p' "$CONTEXT_FILE" | head -1)"
    if [[ "$recorded" != "$fingerprint" ]]; then
        echo "BLOCK(GA-220): DM-Signal staged docs/researchとcontext reflux証跡が不一致" >&2
        echo "  staged_fingerprint=$fingerprint" >&2
        echo "  recorded_fingerprint=${recorded:-MISSING}" >&2
        echo "  action: bash scripts/dm_signal_research_reflux_guard.sh prepare --repo '$repo' --mode synced --evidence '<context節/同期根拠>'" >&2
        echo "  非対象なら --mode non-target --evidence '<明示的非対象根拠>'" >&2
        return 2
    fi
}

prepare() {
    local repo="" mode="" evidence="" fingerprint encoded marker tmp
    while (($#)); do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            --mode) mode="${2:-}"; shift 2 ;;
            --evidence) evidence="${2:-}"; shift 2 ;;
            *) usage; return 2 ;;
        esac
    done
    [[ -n "$repo" && "$mode" =~ ^(synced|non-target)$ && -n "$evidence" ]] || { usage; return 2; }
    is_dm_signal_repo "$repo" || { echo "BLOCK(GA-220): prepare対象はDM-Signal repoのみ" >&2; return 2; }
    has_staged_research "$repo" || { echo "BLOCK(GA-220): staged docs/research変更がない" >&2; return 2; }
    fingerprint="$(staged_fingerprint "$repo")"
    encoded="$(printf '%s' "$evidence" | base64 -w0)"
    marker="<!-- dm_signal_research_reflux: fingerprint=$fingerprint; mode=$mode; evidence_b64=$encoded -->"
    tmp="$(mktemp "${CONTEXT_FILE}.tmp.XXXXXX")"
    awk -v marker="$marker" '
        /dm_signal_research_reflux: fingerprint=/ { if (!done) { print marker; done=1 }; next }
        { print }
        /^<!-- last_updated:/ && !done { print marker; done=1 }
        END { if (!done) print marker }
    ' "$CONTEXT_FILE" > "$tmp"
    mv "$tmp" "$CONTEXT_FILE"
    echo "REFLUX_PREPARED fingerprint=$fingerprint mode=$mode"
}

check_command() {
    local command="$1"
    COMMAND="$command" START_DIR="$PWD" python3 - <<'PY' | while IFS= read -r repo; do
import os
import shlex

tokens = shlex.split(os.environ["COMMAND"])
cwd = os.environ["START_DIR"]
seps = {"&&", ";", "||", "|"}
i = 0
while i < len(tokens):
    if tokens[i] == "cd" and i + 1 < len(tokens):
        cwd = os.path.realpath(os.path.join(cwd, os.path.expanduser(tokens[i + 1]))) if not os.path.isabs(os.path.expanduser(tokens[i + 1])) else os.path.realpath(os.path.expanduser(tokens[i + 1]))
        i += 2
        continue
    if os.path.basename(tokens[i]) == "git":
        repo = cwd
        j = i + 1
        if j + 1 < len(tokens) and tokens[j] == "-C":
            target = os.path.expanduser(tokens[j + 1])
            repo = os.path.realpath(os.path.join(cwd, target)) if not os.path.isabs(target) else os.path.realpath(target)
            j += 2
        if j < len(tokens) and tokens[j] == "commit":
            print(repo)
    i += 1
PY
        check_repo "$repo" || exit $?
    done
}

case "${1:-}" in
    prepare) shift; prepare "$@" ;;
    check) [[ "${2:-}" == "--repo" && -n "${3:-}" ]] || { usage; exit 2; }; check_repo "$3" ;;
    check-command) (($# == 2)) || { usage; exit 2; }; check_command "$2" ;;
    *) usage; exit 2 ;;
esac
