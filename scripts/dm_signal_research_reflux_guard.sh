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

# GA-220: repo identityはgit-common-dir(絶対正規化)で比較する。show-toplevelは
# linked worktreeごとに別pathを返すため、main/linked worktreeを誤って別repoと
# 判定してしまう(worktreeはtoplevelが異なってもcommon-dirは共有する)。
repo_common_dir() {
    local repo="$1" common resolved
    common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
    if [[ -z "$common" ]]; then
        # 旧git(--path-format未対応)向けfallback: common-dirは-C適用後のcwd基準の相対pathで返る
        common="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 1
        [[ -n "$common" ]] || return 1
        if [[ "$common" != /* ]]; then
            common="$(cd "$repo" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P)" || return 1
        fi
    fi
    resolved="$(realpath "$common" 2>/dev/null)" && [[ -n "$resolved" ]] && common="$resolved"
    [[ -n "$common" ]] || return 1
    printf '%s\n' "$common"
}

# 戻り値: 0=同一repo, 1=別repo(安全にスキップ), 2=DM_SIGNAL_REPO側が解決不能(設定不正。fail-closed)
is_dm_signal_repo() {
    local actual expected
    expected="$(repo_common_dir "$DM_SIGNAL_REPO")" || return 2
    actual="$(repo_common_dir "$1")" || return 1
    [[ "$actual" == "$expected" ]]
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
    local repo="$1" fingerprint recorded rc
    rc=0; is_dm_signal_repo "$repo" || rc=$?
    if ((rc == 2)); then
        echo "BLOCK(GA-220): DM_SIGNAL_REPO repo identityを解決できない(設定不正の疑い): $DM_SIGNAL_REPO" >&2
        return 2
    fi
    ((rc == 0)) || return 0
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
    local repo="" mode="" evidence="" fingerprint encoded marker tmp rc
    while (($#)); do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            --mode) mode="${2:-}"; shift 2 ;;
            --evidence) evidence="${2:-}"; shift 2 ;;
            *) usage; return 2 ;;
        esac
    done
    [[ -n "$repo" && "$mode" =~ ^(synced|non-target)$ && -n "$evidence" ]] || { usage; return 2; }
    rc=0; is_dm_signal_repo "$repo" || rc=$?
    if ((rc == 2)); then
        echo "BLOCK(GA-220): DM_SIGNAL_REPO repo identityを解決できない(設定不正の疑い): $DM_SIGNAL_REPO" >&2
        return 2
    fi
    ((rc == 0)) || { echo "BLOCK(GA-220): prepare対象はDM-Signal repoのみ" >&2; return 2; }
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
    local py_output py_status
    py_status=0
    # GA-220 multiline: shlex.split() has no concept of heredocs. Quote characters
    # inside a heredoc BODY are commit-message data, not shell quoting, but shlex
    # treats the raw multi-line command as flat shell text and desyncs its quote
    # state on them (crash on odd embedded-quote count, silent mis-tokenization on
    # even count). The embedded python strips heredoc body+terminator lines before
    # tokenizing so commit-message content can never affect repo detection.
    # `|| py_status=$?` (not a bare assignment) is required: under set -e, a plain
    # `py_output="$(...)"` aborts the function immediately on non-zero exit before
    # this line's own status can be inspected.
    py_output="$(COMMAND="$command" START_DIR="$PWD" python3 - <<'PY'
import os
import re
import shlex
import sys

command = os.environ["COMMAND"]
cwd = os.environ["START_DIR"]

HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def strip_heredocs(text):
    lines = text.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        i += 1
        m = HEREDOC_RE.search(line)
        if not m:
            continue
        strip_tabs = m.group(1) == "-"
        delim = m.group(3)
        while i < n:
            body_line = lines[i]
            probe = body_line.lstrip("\t") if strip_tabs else body_line
            i += 1
            if probe == delim:
                break
    return "\n".join(out)


try:
    tokens = shlex.split(strip_heredocs(command))
except ValueError as exc:
    print(f"PARSE_ERROR: {exc}", file=sys.stderr)
    sys.exit(3)

i = 0
n = len(tokens)
while i < n:
    tok = tokens[i]
    if tok == "cd" and i + 1 < n:
        target = os.path.expanduser(tokens[i + 1])
        cwd = os.path.realpath(target if os.path.isabs(target) else os.path.join(cwd, target))
        i += 2
        continue
    if os.path.basename(tok) == "git":
        repo = cwd
        j = i + 1
        if j + 1 < n and tokens[j] == "-C":
            target = os.path.expanduser(tokens[j + 1])
            repo = os.path.realpath(target if os.path.isabs(target) else os.path.join(cwd, target))
            j += 2
        if j < n and tokens[j] == "commit":
            print(repo)
    i += 1
PY
)" || py_status=$?
    if ((py_status == 3)); then
        echo "BLOCK(GA-220): commit commandのshell構文を解析できない(heredoc除去後も無効。fail-closed)" >&2
        return 2
    elif ((py_status != 0)); then
        echo "BLOCK(GA-220): commit commandパーサが予期しないエラーで終了した(exit=$py_status)" >&2
        return 2
    fi
    [[ -n "$py_output" ]] || return 0
    local repo
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        check_repo "$repo" || return $?
    done <<< "$py_output"
}

case "${1:-}" in
    prepare) shift; prepare "$@" ;;
    check) [[ "${2:-}" == "--repo" && -n "${3:-}" ]] || { usage; exit 2; }; check_repo "$3" ;;
    check-command) (($# == 2)) || { usage; exit 2; }; check_command "$2" ;;
    *) usage; exit 2 ;;
esac
