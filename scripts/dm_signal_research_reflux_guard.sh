#!/usr/bin/env bash
# DM-Signal docs/research commit -> 本陣 research context reflux fingerprint guard.
set -euo pipefail

ROOT_DIR="${SHOGUN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONTEXT_FILE="${DM_SIGNAL_REFLUX_CONTEXT_FILE:-$ROOT_DIR/context/dm-signal-research.md}"
DM_SIGNAL_REPO="${DM_SIGNAL_REPO:-/mnt/c/Python_app/DM-signal}"

usage() {
    echo "Usage: $0 prepare --repo PATH --mode synced|non-target --evidence TEXT" >&2
    echo "       $0 check --repo PATH" >&2
    echo "       $0 check-command COMMAND" >&2
    echo "       $0 sync-split --repo PATH --commit HASH --cmd CMD --context PATH [--context PATH ...]" >&2
}

sync_split() {
    local repo="" commit="" cmd=""
    local -a contexts=()
    while (($#)); do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            --commit) commit="${2:-}"; shift 2 ;;
            --cmd) cmd="${2:-}"; shift 2 ;;
            --context) contexts+=("${2:-}"); shift 2 ;;
            *) usage; return 2 ;;
        esac
    done
    [[ -n "$repo" && "$commit" =~ ^[0-9a-f]{7,40}$ && "$cmd" =~ ^cmd_[A-Za-z0-9_-]+$ && ${#contexts[@]} -gt 0 ]] || { usage; return 2; }
    git -C "$repo" cat-file -e "${commit}^{commit}" 2>/dev/null || { echo "BLOCK(GA-249): commit不存在: $commit" >&2; return 2; }
    git -C "$repo" merge-base --is-ancestor "$commit" HEAD || { echo "BLOCK(GA-249): commitはmain/HEAD未統合: $commit" >&2; return 2; }

    # 内容反映を先に証明できたcontextだけを、一回のtransactionでmarker同期する。
    # 1件でも未反映/欠落なら全ファイルbyte不変で停止する。
    local context_list
    context_list=$(printf '%s\n' "${contexts[@]}")
    CONTEXT_LIST="$context_list" python3 - "$ROOT_DIR" "$commit" "$cmd" <<'PY'
import os, re, sys, tempfile
root, commit, cmd = sys.argv[1:]
rels = [p for p in os.environ.get("CONTEXT_LIST", "").splitlines() if p]
if len(rels) != len(set(rels)):
    raise SystemExit("BLOCK(GA-249): duplicate context path")
prepared = []
today = __import__('datetime').date.today().isoformat()
for rel in rels:
    if not re.fullmatch(r"context/[A-Za-z0-9._-]+\.md", rel):
        raise SystemExit(f"BLOCK(GA-249): invalid context path: {rel}")
    path = os.path.join(root, rel)
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        raise SystemExit(f"BLOCK(GA-249): context missing: {rel}")
    if cmd not in text:
        raise SystemExit(f"BLOCK(GA-249): content未反映のためmarker同期禁止: {rel} token={cmd}")
    text, n1 = re.subn(r"<!--\s*last_updated:\s*[^>]*-->", f"<!-- last_updated: {today} {cmd} -->", text, count=1)
    source = f"<!-- source_commit:{commit} reason:{cmd}_main_integration evidence:{cmd}_content_present -->"
    text, n2 = re.subn(r"<!--\s*source_commit:[0-9a-f]{7,40}[^\n]*?-->", source, text, count=1)
    if n1 != 1 or n2 != 1:
        raise SystemExit(f"BLOCK(GA-249): marker missing/ambiguous: {rel} last_updated={n1} source_commit={n2}")
    prepared.append((path, text, open(path, "rb").read()))

temps = []
try:
    for path, text, _original in prepared:
        fd, tmp = tempfile.mkstemp(prefix=".split-sync.", dir=os.path.dirname(path))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text); f.flush(); os.fsync(f.fileno())
        temps.append((tmp, path))
    replaced = []
    try:
        for tmp, path in temps:
            os.replace(tmp, path); replaced.append(path)
    except BaseException:
        originals = {path: original for path, _text, original in prepared}
        for path in replaced:
            fd, rollback = tempfile.mkstemp(prefix=".split-rollback.", dir=os.path.dirname(path))
            with os.fdopen(fd, "wb") as f:
                f.write(originals[path]); f.flush(); os.fsync(f.fileno())
            os.replace(rollback, path)
        raise
    temps.clear()
finally:
    for tmp, _ in temps:
        try: os.unlink(tmp)
        except FileNotFoundError: pass
print(f"SPLIT_SYNCED count={len(prepared)} commit={commit} cmd={cmd}")
PY
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

# GA-236: check-commandはPreToolUseフックとして「commandがまだ実行される前」に
# 呼ばれる。`git add ... && git commit ...`のようにaddとcommitが同一command文字列
# に連結されている場合、この時点ではindexへのadd未実行のためhas_staged_research()
# は常にfalseを返し、docs/research変更が無検証のままcommitされてしまう(TOCTOU)。
# staged/未staged tracked/untrackedのいずれかにdocs/research変更が実在するかを
# working tree全体で判定し、chained-add検出時のBLOCK要否判断に使う。
has_worktree_research_changes() {
    local repo="$1"
    git -C "$repo" diff --cached --quiet -- docs/research || return 0
    git -C "$repo" diff --quiet -- docs/research || return 0
    [[ -n "$(git -C "$repo" ls-files --others --exclude-standard -- docs/research 2>/dev/null)" ]] && return 0
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

OPERATORS = {";", "&&", "||", "&", "|"}


def segment_args(tokens, start):
    """start以降、次のshell演算子または末尾までのtoken列を返す(startは含まない)"""
    args = []
    k = start
    n = len(tokens)
    while k < n and tokens[k] not in OPERATORS:
        args.append(tokens[k])
        k += 1
    return args, k


def add_targets_research(args):
    """`git add <args>`がdocs/research配下を巻き込み得るpathspecかを判定する。
    fail-closed: 引数なし/`-A`/`--all`/`-u`/`.`等の広域指定は無条件で対象とみなす。
    """
    if not args:
        return True
    for a in args:
        if a in (".", "-A", "--all", "-u", "--update", ":/"):
            return True
        if not a.startswith("-"):
            norm = a.lstrip("./")
            if norm == "docs" or norm == "docs/research" or norm.startswith("docs/research/"):
                return True
    return False


def commit_stages_tracked(args):
    """`git commit -a/--all/-am`等、commit自身がtracked変更をstageするかを判定する"""
    for a in args:
        if a == "--all":
            return True
        if a.startswith("-") and not a.startswith("--") and "a" in a[1:]:
            return True
    return False


i = 0
n = len(tokens)
add_repos_broad = set()
results = []
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
        if j < n and tokens[j] == "add":
            args, k = segment_args(tokens, j + 1)
            if add_targets_research(args):
                add_repos_broad.add(repo)
            i = k
            continue
        if j < n and tokens[j] == "commit":
            args, k = segment_args(tokens, j + 1)
            chained = repo in add_repos_broad or commit_stages_tracked(args)
            results.append((repo, chained))
            i = k
            continue
    i += 1

for repo, chained in results:
    print(f"{repo}\t{'CHAINED_ADD' if chained else 'PLAIN'}")
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
    local repo tag
    while IFS=$'\t' read -r repo tag; do
        [[ -n "$repo" ]] || continue
        if [[ "$tag" == "CHAINED_ADD" ]]; then
            local _rag_rc=0
            is_dm_signal_repo "$repo" || _rag_rc=$?
            if ((_rag_rc == 0)) && has_worktree_research_changes "$repo"; then
                echo "BLOCK(GA-220/GA-236): git addとgit commitが同一command文字列に連結されており、docs/research変更が未staged状態でreflux検証をすり抜けます(TOCTOU)。git add(別のtool call)を先に完了させてからgit commitを実行してください" >&2
                return 2
            fi
        fi
        check_repo "$repo" || return $?
    done <<< "$py_output"
}

case "${1:-}" in
    prepare) shift; prepare "$@" ;;
    check) [[ "${2:-}" == "--repo" && -n "${3:-}" ]] || { usage; exit 2; }; check_repo "$3" ;;
    check-command) (($# == 2)) || { usage; exit 2; }; check_command "$2" ;;
    sync-split) shift; sync_split "$@" ;;
    *) usage; exit 2 ;;
esac
