#!/usr/bin/env bash
# shogun_commit_verdict.sh — 否定判定(不在/未到達/消失/偽CLEAR)を口にする前の一発検分。
#
# 背景: 2026-08-27〜28 に将軍が 5 回、1 つの文脈だけで検証して「不在」と断定し撤回した
#   T82 (fetch 失敗を 2>/dev/null で隠し local 比較で偽CLEAR) / T69 (worktree 消失=未commit 実装消失と推定、
#   実際は commit 実在) / T108 (control repo で rev-parse し rebalancer 正準 repo の commit を不在と断定)。
#   共通構造: 検証コマンドの文脈(repo/ref/fetch 成否)が違うだけで、正しい文脈では毎回「実在」だった。
# 原則: 反証の不在≠不在の証明(LS-A09(8))。本 script は「実在しうる全文脈」を機械的に総当たりし、
#   fetch の成否・各 repo での存否・HEAD/origin/main 祖先性・到達 ref を 1 画面で出す。
#   否定判定は本 script の verdict=ABSENT を見た後にのみ許される。
#
# Usage:
#   bash scripts/shogun_commit_verdict.sh <commit> [--context context/<file>.md] [--repo <path>]... [--no-fetch]
#   終了コード: 0=どこかで実在(PRESENT)、1=全文脈で不在(ABSENT)、2=引数エラー
set -u
CONTROL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_CONFIG="${SHOGUN_VERDICT_PROJECTS_CONFIG:-$CONTROL_ROOT/config/projects.yaml}"

commit=""; context_path=""; declare -a extra_repos=(); do_fetch=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --context) context_path="$2"; shift 2 ;;
        --repo) extra_repos+=("$2"); shift 2 ;;
        --no-fetch) do_fetch=0; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 2 ;;
        *) if [[ -z "$commit" ]]; then commit="$1"; shift; else echo "unknown arg: $1" >&2; exit 2; fi ;;
    esac
done
[[ -n "$commit" ]] || { echo "usage: $0 <commit> [--context context/x.md] [--repo path] [--no-fetch]" >&2; exit 2; }

project_path_from_config() {
    local target="$1"
    [[ -r "$PROJECTS_CONFIG" ]] || return 1
    awk -v target="$target" '
        function clean(v){ gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", v); return v }
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ { id=$0; sub(/.*id:[[:space:]]*/, "", id); id=clean(id); next }
        id == target && /^[[:space:]]+path:[[:space:]]*/ { p=$0; sub(/.*path:[[:space:]]*/, "", p); print clean(p); exit 0 }
    ' "$PROJECTS_CONFIG"
}

# 候補 repo の収集: control repo は常に含める。context 指定があれば正準 repo を config から解決。
declare -a repos=("$CONTROL_ROOT")
if [[ -n "$context_path" ]]; then
    project="infra"
    [[ "$context_path" == context/dm-signal*.md ]] && project="dm-signal"
    base="$(basename "$context_path" .md)"
    if [[ "$project" == infra ]]; then
        # context/<id>.md が config/projects.yaml の id と一致すれば、その PJ の正準 repo
        cand="$(project_path_from_config "$base" 2>/dev/null || true)"
        [[ -n "$cand" ]] && project="$base"
    fi
    if [[ "$project" != infra ]]; then
        p="$(project_path_from_config "$project" 2>/dev/null || true)"
        [[ -n "$p" && -d "$p" ]] && repos+=("$p") || echo "WARN: canonical repo for $context_path (project=$project) unresolved: '$p'" >&2
    fi
fi
for r in "${extra_repos[@]:-}"; do [[ -n "$r" && -d "$r" ]] && repos+=("$r"); done

present=0
printf 'commit=%s\n' "$commit"
for repo in "${repos[@]}"; do
    [[ -d "$repo/.git" || -f "$repo/.git" ]] || { printf 'repo=%s\tnot_a_git_repo\n' "$repo"; continue; }
    fetch_state="skipped"
    if (( do_fetch )); then
        if err="$(timeout 30 git -C "$repo" fetch -q origin 2>&1)"; then fetch_state="ok"; else fetch_state="FAILED($(printf '%s' "$err" | tail -1 | cut -c1-80))"; fi
    fi
    obj="$(git -C "$repo" cat-file -t "$commit" 2>/dev/null || echo "-")"
    if [[ "$obj" == "commit" ]]; then
        present=1
        anc_head="no"; git -C "$repo" merge-base --is-ancestor "$commit" HEAD 2>/dev/null && anc_head="yes"
        anc_origin="n/a"
        if git -C "$repo" rev-parse --verify -q origin/main >/dev/null 2>&1; then
            anc_origin="no"; git -C "$repo" merge-base --is-ancestor "$commit" origin/main 2>/dev/null && anc_origin="yes"
        fi
        refs="$(git -C "$repo" for-each-ref --format='%(refname:short)' --contains "$commit" 2>/dev/null | head -5 | paste -sd, -)"
        if [[ -z "$refs" ]]; then
            # T82 型: lane 書換で hash が変わっても内容(patch-id)が同じ commit が HEAD/origin/main に居るかを探す
            pid="$(git -C "$repo" show "$commit" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
            eq=""
            if [[ -n "$pid" ]]; then
                for ref in origin/main HEAD; do
                    git -C "$repo" rev-parse --verify -q "$ref" >/dev/null 2>&1 || continue
                    while read -r c; do
                        cp="$(git -C "$repo" show "$c" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
                        if [[ "$cp" == "$pid" ]]; then eq="$c@$ref"; break; fi
                    done < <(git -C "$repo" rev-list --max-count=300 "$ref" 2>/dev/null)
                    [[ -n "$eq" ]] && break
                done
            fi
            if [[ -n "$eq" ]]; then
                refs="(no ref contains it) EQUIVALENT patch-id → ${eq}  # lane 書換で hash 違い・内容同一=到達済(T82 型)"
            else
                refs="(no ref contains it = dangling/unreachable: 消失ではなく未接続)"
            fi
        fi
        subj="$(git -C "$repo" log -1 --format='%h %ci %s' "$commit" 2>/dev/null | cut -c1-90)"
        printf 'repo=%s\tfetch=%s\tobject=commit\tancestor_HEAD=%s\tancestor_origin/main=%s\trefs=%s\n\t%s\n' \
            "$repo" "$fetch_state" "$anc_head" "$anc_origin" "$refs" "$subj"
    else
        printf 'repo=%s\tfetch=%s\tobject=%s\n' "$repo" "$fetch_state" "$obj"
    fi
done
if (( present )); then
    echo "verdict=PRESENT  # 『不在/消失/未到達』と断定するな。上の repo/ref を根拠に肯定形で報告せよ"
    exit 0
fi
echo "verdict=ABSENT  # 全候補 repo で object 不在。fetch=FAILED の行があれば不在ではなく未確認=再試行せよ"
exit 1
