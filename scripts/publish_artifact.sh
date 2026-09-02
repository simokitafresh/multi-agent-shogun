#!/bin/bash
# scripts/publish_artifact.sh — 忍者 local commit 成果物(source_tree+patch)の複製(capture)と復元(restore)
# 設計書: docs/research/single_publisher_asis_tobe_5w1h_20260902.md §9.1 U2 / §2.4 C6 / §13 H7
# cmd_4446 AC1: このファイルの新規実装がAC1(capture/restore本体)
#
# 目的: worktree cleanup・pane 停止・respawn を経ても、忍者が local commit した成果物を
#       publisher が復元・公開できるようにする(H7: LGTM 時点では STAGE1 誤終端 respawn に間に合わない
#       → report_received 時点(このスクリプトの呼出し時点)へ前倒し)。
#
# Usage:
#   bash scripts/publish_artifact.sh capture <task_id> <worktree> <base> <source_sha>
#   bash scripts/publish_artifact.sh restore <task_id> <dest_tree>
#
# capture: <worktree>(忍者の task worktree)の <base>..<source_sha> 差分を
#          $STATE_DIR/publish_queue/artifacts/<task_id>/{patch.diff,manifest.yaml} へ複製する。
#          manifest.yaml = {source_sha, source_tree, patch_sha, base, paths[]}
#          worktree を削除・変更しない(読み取りのみ)。
# restore: <dest_tree>(base 相当の checkout 済み git worktree)へ patch を適用し、
#          変更 path を index へ stage する。write-tree の結果が manifest の source_tree と
#          一致しない場合は FAIL(rc=1)。root worktree への直接適用はしない(呼出し元の責務)。
#
# 停止条件: base..source_sha の差分が空(paths 0)の場合、capture は artifact を作らず
#           rc=3 で終了する(サイレントフォールバック禁止 — H9。空の複製を残さない)。
#
# Exit codes: 0=成功  1=restore tree mismatch  2=引数/前提エラー  3=capture空差分SKIP  4=lock timeout  5=git apply失敗
set -eu

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}"
ARTIFACTS_ROOT="$STATE_DIR/publish_queue/artifacts"

_pa_err() {
    echo "publish_artifact: $*" >&2
}

_pa_capture() {
    local task_id="${1:-}" worktree="${2:-}" base="${3:-}" source_sha="${4:-}"
    if [ -z "$task_id" ] || [ -z "$worktree" ] || [ -z "$base" ] || [ -z "$source_sha" ]; then
        _pa_err "capture: task_id/worktree/base/source_sha はすべて必須"
        return 2
    fi
    git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1 || {
        _pa_err "capture: not a git worktree: $worktree"
        return 2
    }

    local source_tree
    source_tree="$(git -C "$worktree" rev-parse "${source_sha}^{tree}" 2>/dev/null)" || {
        _pa_err "capture: cannot resolve source_sha tree: $source_sha"
        return 2
    }

    local paths
    paths="$(git -C "$worktree" diff --no-renames --name-only "$base" "$source_sha" -- 2>/dev/null || true)"
    if [ -z "$paths" ]; then
        _pa_err "capture: SKIP(empty diff, 0 paths) task_id=$task_id base=$base source_sha=$source_sha"
        return 3
    fi

    local artifact_dir="$ARTIFACTS_ROOT/$task_id"
    mkdir -p "$artifact_dir"
    local lock="$artifact_dir/.capture.lock"
    (
        flock -w 30 9 || { _pa_err "capture: lock timeout task_id=$task_id"; exit 4; }
        local patch_tmp patch_sha
        patch_tmp="$(mktemp "$artifact_dir/.patch.XXXXXX")"
        git -C "$worktree" diff --no-renames --binary "$base" "$source_sha" -- > "$patch_tmp"
        patch_sha="$(git hash-object "$patch_tmp")"
        # patch.diff は manifest.yaml より先に確定させる。manifest.yaml の存在を
        # 「artifact 完成」の合図として読む側(restore・gate)がいるため、
        # 逆順だと manifest はあるのに patch が古い/未整合という窓ができる。
        mv -f "$patch_tmp" "$artifact_dir/patch.diff"
        python3 - "$REPO_ROOT" "$artifact_dir/manifest.yaml" "$source_sha" "$source_tree" "$patch_sha" "$base" "$paths" <<'PY'
import sys

repo_root, manifest_path, source_sha, source_tree, patch_sha, base, paths_raw = sys.argv[1:8]
paths = [p for p in paths_raw.splitlines() if p]

sys.path.insert(0, repo_root)
from scripts.lib.yaml_atomic import atomic_yaml_write  # noqa: E402


class _Sha(str):
    """Marks a scalar that must always round-trip as a YAML string, even when
    every character happens to be a decimal digit (PyYAML's implicit resolver
    would otherwise coerce an all-digit scalar to int)."""


def _represent_sha(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", str(data), style="'")


import yaml  # noqa: E402

yaml.add_representer(_Sha, _represent_sha, Dumper=yaml.Dumper)

data = {
    "source_sha": _Sha(source_sha),
    "source_tree": _Sha(source_tree),
    "patch_sha": _Sha(patch_sha),
    "base": _Sha(base),
    "paths": paths,
}
atomic_yaml_write(manifest_path, data)
PY
    ) 9>"$lock"
    _pa_err "capture: OK task_id=$task_id source_sha=$source_sha source_tree=$source_tree paths=$(printf '%s\n' "$paths" | wc -l)"
}

_pa_restore() {
    local task_id="${1:-}" dest_tree="${2:-}"
    if [ -z "$task_id" ] || [ -z "$dest_tree" ]; then
        _pa_err "restore: task_id/dest_tree はすべて必須"
        return 2
    fi
    local artifact_dir="$ARTIFACTS_ROOT/$task_id"
    local manifest_path="$artifact_dir/manifest.yaml"
    local patch_path="$artifact_dir/patch.diff"
    if [ ! -f "$manifest_path" ] || [ ! -f "$patch_path" ]; then
        _pa_err "restore: artifact not found for task_id=$task_id ($artifact_dir)"
        return 2
    fi
    git -C "$dest_tree" rev-parse --git-dir >/dev/null 2>&1 || {
        _pa_err "restore: not a git worktree: $dest_tree"
        return 2
    }

    local expected_tree
    expected_tree="$(python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
v = d.get('source_tree')
print(str(v) if v is not None else '')
" "$manifest_path")"
    if [ -z "$expected_tree" ]; then
        _pa_err "restore: manifest missing source_tree: $manifest_path"
        return 2
    fi

    local paths
    paths="$(python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
for p in (d.get('paths') or []):
    print(p)
" "$manifest_path")"

    if ! git -C "$dest_tree" apply --binary --whitespace=nowarn "$patch_path"; then
        _pa_err "restore: git apply failed task_id=$task_id patch=$patch_path"
        return 5
    fi

    if [ -n "$paths" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            git -C "$dest_tree" add -- "$p"
        done <<< "$paths"
    fi

    local actual_tree
    actual_tree="$(git -C "$dest_tree" write-tree)"

    if [ "$actual_tree" != "$expected_tree" ]; then
        _pa_err "restore: FAIL tree mismatch expected=$expected_tree actual=$actual_tree task_id=$task_id"
        return 1
    fi

    echo "$actual_tree"
    _pa_err "restore: OK task_id=$task_id tree=$actual_tree"
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        capture)
            shift
            _pa_capture "$@"
            ;;
        restore)
            shift
            _pa_restore "$@"
            ;;
        *)
            _pa_err "usage: publish_artifact.sh {capture <task_id> <worktree> <base> <source_sha> | restore <task_id> <dest_tree>}"
            return 2
            ;;
    esac
}

main "$@"
