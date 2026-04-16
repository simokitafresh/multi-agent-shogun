#!/usr/bin/env bash
set -euo pipefail

# SCRIPT_DIR unused but kept for reference
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_CMD="${GH_CMD:-gh}"
GIST_OWNER="${GIST_OWNER:-simokitafresh}"
GIST_INDEX_ID="${GIST_INDEX_ID:-83a17157247174e9faefc3962968fe1b}"
GIST_INDEX_FILENAME="${GIST_INDEX_FILENAME:-gist-index.md}"
GIST_INDEX_TITLE="${GIST_INDEX_TITLE:-DM-Signal Gist Index}"
GIST_INDEX_DATE="${GIST_INDEX_DATE:-$(date '+%Y-%m-%d')}"

declare -a CATEGORY_ORDER=(
    "note記事"
    "週報"
    "研究データ・分析レポート"
    "deepdive・将軍記録"
    "ユーザー向け"
    "インフラ・確定申告・比較分析"
    "前処理研究"
)

log() {
    echo "[gist_index_update] $*"
}

title_key() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_ipynb_title() {
    local title_key_value
    title_key_value="$(title_key "$1")"
    [[ "$title_key_value" == *".ipynb"* || "$title_key_value" == *"ipynb"* ]]
}

classify_gist() {
    local title="$1"
    local key
    key="$(title_key "$title")"

    case "$key" in
        *"note記事"*|*"記事下書き"*|*"解説"*|*"検証"*|*"信じていい"*|*"選べ"*|*"使えない"*|*"p平均"*|*"p-average"*|*"p̄"*|*"戦国ai列伝"*|*"列伝"*)
            printf '%s\n' "note記事"
            ;;
        *"weekly"*)
            printf '%s\n' "週報"
            ;;
        *"研究日誌"*|*"前処理研究"*)
            printf '%s\n' "前処理研究"
            ;;
        *"deepdive"*|*"why深掘り"*|*"因果探索"*|*"why chain"*|*"deep dive"*|*"将軍必読"*)
            printf '%s\n' "deepdive・将軍記録"
            ;;
        *"user manual"*|*"マニュアル"*)
            printf '%s\n' "ユーザー向け"
            ;;
        *"確定申告"*|*"経費管理"*|*"gstack"*|*"dashboard"*|*"ダッシュボード"*|*"mcas"*|*"システム比較"*|*"対比"*|*"比較ドキュメント"*)
            printf '%s\n' "インフラ・確定申告・比較分析"
            ;;
        *)
            printf '%s\n' "研究データ・分析レポート"
            ;;
    esac
}

short_date() {
    local iso_date="${1:-}"
    if [[ "$iso_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        printf '%s\n' "${iso_date:5:5}"
    else
        printf '%s\n' "$iso_date"
    fi
}

gist_url() {
    local gist_id="$1"
    printf 'https://gist.github.com/%s/%s\n' "$GIST_OWNER" "$gist_id"
}

render_header() {
    cat <<EOF
# ${GIST_INDEX_TITLE}
<!-- last_updated: ${GIST_INDEX_DATE} -->

> 全gistの一覧。タップでブラウザで開く。

EOF
}

append_category_section() {
    local category="$1"
    local content="$2"
    if [ -z "$content" ]; then
        return
    fi

    printf '## %s\n\n' "$category"
    printf '| 日付 | タイトル |\n'
    printf '|------|---------|\n'
    printf '%s\n\n' "$content"
}

main() {
    local dry_run=false
    if [ "${1:-}" = "--dry-run" ]; then
        dry_run=true
    fi

    local raw_list
    raw_list="$("$GH_CMD" gist list --limit 100)"

    declare -A seen_titles=()
    declare -A category_rows=()
    declare -A category_counts=()
    declare -A excluded_counts=(
        [self_index]=0
        [duplicate_title]=0
        [ipynb]=0
    )
    local total_count=0
    local kept_count=0
    local excluded_lines=""

    local gist_id title _files _visibility updated_at
    while IFS=$'\t' read -r gist_id title _files _visibility updated_at; do
        [ -n "${gist_id:-}" ] || continue
        total_count=$((total_count + 1))

        if [ "$gist_id" = "$GIST_INDEX_ID" ]; then
            excluded_counts[self_index]=$((excluded_counts[self_index] + 1))
            excluded_lines+=$'self_index\t'"$gist_id"$'\t'"$title"$'\n'
            continue
        fi

        if is_ipynb_title "$title"; then
            excluded_counts[ipynb]=$((excluded_counts[ipynb] + 1))
            excluded_lines+=$'ipynb\t'"$gist_id"$'\t'"$title"$'\n'
            continue
        fi

        local seen_key
        seen_key="$(title_key "$title")"
        if [ -n "${seen_titles[$seen_key]:-}" ]; then
            excluded_counts[duplicate_title]=$((excluded_counts[duplicate_title] + 1))
            excluded_lines+=$'duplicate_title\t'"$gist_id"$'\t'"$title"$'\n'
            continue
        fi
        seen_titles[$seen_key]="$gist_id"

        local category
        category="$(classify_gist "$title")"
        local row
        row="| $(short_date "$updated_at") | [$title]($(gist_url "$gist_id")) |"
        if [ -n "${category_rows[$category]:-}" ]; then
            category_rows[$category]+=$'\n'
        fi
        category_rows[$category]+="$row"
        category_counts[$category]=$(( ${category_counts[$category]:-0} + 1 ))
        kept_count=$((kept_count + 1))
    done <<< "$raw_list"

    local tmpfile
    tmpfile="$(mktemp)"
    # shellcheck disable=SC2064  # tmpfile is local; expand at definition time is intentional
    trap "rm -f '$tmpfile'" EXIT

    render_header > "$tmpfile"
    local category
    for category in "${CATEGORY_ORDER[@]}"; do
        append_category_section "$category" "${category_rows[$category]:-}" >> "$tmpfile"
    done

    {
        printf -- '---\n'
        printf '*%d件中%d件を掲載（インデックスgist自身=%d、重複gist=%d、ipynb系gist=%d を除外）*\n' \
            "$total_count" \
            "$kept_count" \
            "${excluded_counts[self_index]}" \
            "${excluded_counts[duplicate_title]}" \
            "${excluded_counts[ipynb]}"
    } >> "$tmpfile"

    log "category_counts: note記事=${category_counts["note記事"]:-0} 週報=${category_counts["週報"]:-0} 研究データ・分析レポート=${category_counts["研究データ・分析レポート"]:-0} deepdive・将軍記録=${category_counts["deepdive・将軍記録"]:-0} ユーザー向け=${category_counts["ユーザー向け"]:-0} インフラ・確定申告・比較分析=${category_counts["インフラ・確定申告・比較分析"]:-0} 前処理研究=${category_counts["前処理研究"]:-0}"
    log "excluded_counts: self_index=${excluded_counts[self_index]} duplicate_title=${excluded_counts[duplicate_title]} ipynb=${excluded_counts[ipynb]}"
    if [ -n "$excluded_lines" ]; then
        log "excluded_entries_begin"
        while IFS=$'\t' read -r reason excluded_id excluded_title; do
            [ -n "${reason:-}" ] || continue
            log "excluded reason=${reason} id=${excluded_id} title=${excluded_title}"
        done <<< "$excluded_lines"
        log "excluded_entries_end"
    fi

    if [ "$dry_run" = true ]; then
        cat "$tmpfile"
        return 0
    fi

    "$GH_CMD" gist edit "$GIST_INDEX_ID" --filename "$GIST_INDEX_FILENAME" "$tmpfile"
    log "updated gist ${GIST_INDEX_ID} (${GIST_INDEX_FILENAME})"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
