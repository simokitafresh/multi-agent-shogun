#!/usr/bin/env bash
# pre_push_guard.sh — GA-PUSH1 で止まる push を、止まらない範囲まで前進させるための境界計算。
#
# 背景(実測 2026-07-26):
#   共有worktreeで6忍者が同時に働くため、常に誰かが何かを編集している。
#   .githooks/pre-push の GA-PUSH1 は「push対象commitが触るpath」と「作業ツリーの
#   未commit path」が1つでも重なると push 全体を BLOCK する。judgement は正しいが
#   粒度が push 単位のため、無関係なcommitまで巻き添えで止まる。
#   16:39時点=未push14件・重複path=scripts/review_approval.sh。
#   16:47時点=未push10件・重複path=tests/unit/test_cmd_publish_preflight.bats。
#   ★8分で阻害pathの主が入れ替わった。恒常的に再発する。
#
# 本ライブラリがやること: 「重複pathを含む最初の未pushcommit」を git だけで機械判定し、
#                        その親(=安全に送れる先端)を返す。
# 本ライブラリがやらないこと: ★push しない。可否判断はしない(家老の領分)。
#                            ★.githooks/pre-push を変更しない(bypass脱出路も含め無改変)。
#
# 安全性の根拠(隔離環境で実測):
#   * <safe_tip>:main は origin/main の子孫かつ HEAD の祖先なので fast-forward。
#     履歴改変も強制pushも起きない。
#   * pre-push hook は remote_sha..local_sha で changed_files を再計算するため、
#     縮めた範囲に対して GA-PUSH1 も affected test も正しく再評価される。
#   * ∴「hookを騙して通す」のではなく「hookが通す範囲を求める」ものである。
#
# 効果は位置依存である(隠さない):
#   重複pathを最初に触るcommitが古いほど救われるcommitは少ない。
#   実測: 16:39状態=14件中4件しか進まない / 16:47状態=10件中8件進む。
#   ∴これは詰まりを完全に解く仕組みではなく、詰まりを部分的に流す仕組みである。

# --- exit経路(呼ぶ前に数えたもの / AC5) -------------------------------------
#   pre_push_guard_first_blocking_commit:
#     E1 未commit(tracked)が無い      -> 空を返す (=全量pushでよい)
#     E2 未pushcommitが無い            -> 空を返す (=送るものが無い)
#     E3 どのcommitも重複を含まない     -> 空を返す (=全量pushでよい)
#     E4 重複を含むcommitがある         -> その最初のsha を返す
#     ※ 返り値(exit status)は上記いずれも 0。異常時のみ非0。
#   pre_push_guard_safe_tip:
#     S1 first_blocking が空            -> 空を返す (=全量push)
#     S2 first_blocking が最古の未pushcommit -> 空を返す (=送れる前進が無い)
#     S3 それ以外                        -> first_blocking^ を返す
# ---------------------------------------------------------------------------

pre_push_guard_dirty_paths() {
    local repo="${1:-.}"
    git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null | cut -c4- | sort -u
}

# 重複pathを含む最初の未pushcommit(古い順)を返す。無ければ何も出力しない。
pre_push_guard_first_blocking_commit() {
    local repo="${1:-.}" remote_ref="${2:-origin/main}"
    local dirty_file sha overlap rc=0
    dirty_file=$(mktemp) || return 1
    pre_push_guard_dirty_paths "$repo" > "$dirty_file"
    if [ ! -s "$dirty_file" ]; then          # E1
        rm -f "$dirty_file"; return 0
    fi
    while read -r sha; do
        [ -n "$sha" ] || continue
        overlap=$(git -C "$repo" diff --name-only "${sha}^" "$sha" 2>/dev/null \
                  | sort -u | comm -12 - "$dirty_file")
        if [ -n "$overlap" ]; then           # E4
            printf '%s\n' "$sha"
            rm -f "$dirty_file"; return 0
        fi
    done < <(git -C "$repo" rev-list --reverse "${remote_ref}..HEAD" 2>/dev/null)
    rm -f "$dirty_file"                       # E2 / E3
    return "$rc"
}

# commit subject 先頭の cmd_id を返す(無ければ空)。
# 先頭に限るのは、本文中で他cmdに「言及しただけ」のものを拾わないためである
# (本日 inbox_write の auto-read が本文grepで別cmdを掴んだのと同じ失敗を避ける)。
pre_push_guard_cmd_id_of() {
    local repo="${1:-.}" sha="$2" subject
    subject=$(git -C "$repo" log -1 --format=%s "$sha" 2>/dev/null) || return 0
    case "$subject" in
        cmd_*) printf '%s\n' "${subject%%:*}" ;;
    esac
}

# 境界候補が「同一cmdを2つに割っていないか」を検査し、割っていれば手前へ下げる。
# 理由(軍師の実測 2026-07-26): path基準だけで #4 を境界にすると、
#   cmd_karo_impl_watcher_log_series_kind = db3a1e724(#3) と 92bef71db(#9)
#   cmd_karo_impl_approval_log_atomic     = 6d8412dfd(#5) と 2e2dcb0c2(#10)
# のうち前者(=レビュー指摘を受けた版)だけが公開され、★是正commitが置き去りになる。
# 「部分的な状態を完全であるかのように公開する」ことになるため、境界はcmdを割らない。
pre_push_guard_unsplit_tip() {
    local repo="${1:-.}" remote_ref="${2:-origin/main}" tip="$3"
    local sha cid inside_first outside changed
    [ -n "$tip" ] || return 0
    while :; do
        changed=0
        outside=$(git -C "$repo" rev-list "${tip}..HEAD" 2>/dev/null)
        while read -r sha; do
            [ -n "$sha" ] || continue
            cid=$(pre_push_guard_cmd_id_of "$repo" "$sha")
            [ -n "$cid" ] || continue
            # 同じcmd_idが境界の外側にも居るなら、この境界はcmdを割っている
            inside_first=""
            while read -r osha; do
                [ -n "$osha" ] || continue
                if [ "$(pre_push_guard_cmd_id_of "$repo" "$osha")" = "$cid" ]; then
                    inside_first="$sha"; break
                fi
            done <<< "$outside"
            if [ -n "$inside_first" ]; then
                tip=$(git -C "$repo" rev-parse "${inside_first}^" 2>/dev/null) || return 1
                changed=1
                break
            fi
        done < <(git -C "$repo" rev-list --reverse "${remote_ref}..${tip}" 2>/dev/null)
        [ "$changed" -eq 1 ] || break
        # 境界が remote まで下がったら送れるものは無い
        if [ "$tip" = "$(git -C "$repo" rev-parse "$remote_ref" 2>/dev/null)" ]; then
            return 0
        fi
    done
    printf '%s\n' "$tip"
}

# 安全に送れる先端を返す。全量pushでよい場合・進める余地が無い場合は何も出力しない。
# 基準は2つだけである(軍師の注意: 基準を増やすほど境界は手前へ下がり、
# 極端には常に0件となって停滞解消という目的自体を失う。増やすなら効果を実測してから):
#   1. path重複  — 未commit pathと重なるcommitを含めない
#   2. cmd分割   — 境界より後に同一cmd_idのcommitがあるなら、その境界を採らない
pre_push_guard_safe_tip() {
    local repo="${1:-.}" remote_ref="${2:-origin/main}"
    local first parent oldest
    first=$(pre_push_guard_first_blocking_commit "$repo" "$remote_ref") || return 1
    [ -n "$first" ] || return 0               # S1: 全量pushでよい(分割は起きない)
    oldest=$(git -C "$repo" rev-list --reverse "${remote_ref}..HEAD" 2>/dev/null | head -1)
    [ "$first" != "$oldest" ] || return 0     # S2
    parent=$(git -C "$repo" rev-parse "${first}^" 2>/dev/null) || return 1
    pre_push_guard_unsplit_tip "$repo" "$remote_ref" "$parent"   # S3 (+S4: 分割なら手前へ)
}

# 人が読むための要約。★push コマンドは提案するだけで実行しない。
pre_push_guard_report() {
    local repo="${1:-.}" remote_ref="${2:-origin/main}"
    local first safe total ahead
    total=$(git -C "$repo" rev-list --count "${remote_ref}..HEAD" 2>/dev/null || echo 0)
    first=$(pre_push_guard_first_blocking_commit "$repo" "$remote_ref")
    if [ -z "$first" ]; then
        printf 'pending=%s blocking=none action=full-push\n' "$total"
        return 0
    fi
    safe=$(pre_push_guard_safe_tip "$repo" "$remote_ref")
    if [ -z "$safe" ]; then
        printf 'pending=%s blocking=%s action=none reason=oldest-pending-commit-is-blocking\n' \
            "$total" "$first"
        return 0
    fi
    ahead=$(git -C "$repo" rev-list --count "${remote_ref}..${safe}" 2>/dev/null || echo 0)
    printf 'pending=%s blocking=%s safe_tip=%s advances=%s suggested=git push origin %s:main\n' \
        "$total" "$first" "$safe" "$ahead" "$safe"
}

# 直接実行された場合のみCLIとして振る舞う(source時は関数定義のみ)。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-report}" in
        first-blocking) pre_push_guard_first_blocking_commit "${2:-.}" "${3:-origin/main}" ;;
        safe-tip)       pre_push_guard_safe_tip "${2:-.}" "${3:-origin/main}" ;;
        report|"")      pre_push_guard_report "${2:-.}" "${3:-origin/main}" ;;
        *) echo "usage: pre_push_guard.sh [first-blocking|safe-tip|report] [repo] [remote_ref]" >&2; exit 2 ;;
    esac
fi
