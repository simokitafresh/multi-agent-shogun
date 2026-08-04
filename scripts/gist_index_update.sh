#!/usr/bin/env bash
set -euo pipefail

GH_CMD="${GH_CMD:-gh}"
GIST_OWNER="${GIST_OWNER:-simokitafresh}"
GIST_INDEX_ID="${GIST_INDEX_ID:-83a17157247174e9faefc3962968fe1b}"
GIST_INDEX_FILENAME="${GIST_INDEX_FILENAME:-gist-index.md}"
GIST_INDEX_TITLE="${GIST_INDEX_TITLE:-DM-Signal Gist Index}"
GIST_INDEX_DATE="${GIST_INDEX_DATE:-$(date '+%Y-%m-%d')}"

declare -a CATEGORY_ORDER=(
    "設計書・稼働中"
    "設計書・CLOSED"
    "調査書・監査・レポート"
    "正本・カタログ・パターン"
    "記事・対外発信"
    "その他・運用"
)

log() {
    echo "[gist_index_update] $*"
}

title_key() {
    LC_ALL=C printf '%s' "${1,,}"
}

is_ipynb_title() {
    local title_key_value
    title_key_value="$(title_key "$1 ${2:-}")"
    [[ "$title_key_value" == *".ipynb"* || "$title_key_value" == *"ipynb"* ]]
}

classify_gist() {
    local title="$1"
    local key
    key="$(title_key "$title")"

    # Output: category<TAB>status<TAB>fallback.  Precedence is explicit
    # exclusion (caller) -> status tag -> title key -> fallback.
    if [[ "$key" =~ 【[^】]*(closed|完了|後継)[^】]*】 ]]; then
        printf '%s\t%s\t%s\n' "設計書・CLOSED" "closed" "false"
    elif [[ "$key" =~ 【[^】]*(稼働中|設計済|実装進行中|レビュー反映済)[^】]*】 ]]; then
        printf '%s\t%s\t%s\n' "設計書・稼働中" "active" "false"
    elif [[ "$key" == *"asis/tobe"* || "$key" == *"as-is/to-be"* || "$key" == *"5w1h"* ]]; then
        printf '%s\t%s\t%s\n' "設計書・稼働中" "unknown_status" "false"
    elif [[ "$key" == *"調査書"* || "$key" == *"監査"* || "$key" == *"レポート"* || "$key" == *"進化量"* ]]; then
        printf '%s\t%s\t%s\n' "調査書・監査・レポート" "not_applicable" "false"
    elif [[ "$key" == *"mece"* || "$key" == *"カタログ"* || "$key" == *"パターン"* || "$key" == *"正本"* || "$key" == *"チェックリスト"* ]]; then
        printf '%s\t%s\t%s\n' "正本・カタログ・パターン" "not_applicable" "false"
    elif [[ "$key" == *"note記事"* || "$key" == *"週報"* || "$key" == *"weekly"* || "$key" == *"投資知識辞書"* || "$key" == *"ユーザー向け"* ]]; then
        printf '%s\t%s\t%s\n' "記事・対外発信" "not_applicable" "false"
    else
        printf '%s\t%s\t%s\n' "その他・運用" "not_applicable" "true"
    fi
}

fetch_gists() {
    if command -v "$GH_CMD" >/dev/null 2>&1; then
        "$GH_CMD" api --paginate gists --jq '.[] | [.id, (.description // ""), ((.files | keys) | join(",")), .public, .updated_at] | @tsv'
    else
        bash "$GH_CMD" api --paginate gists --jq '.[] | [.id, (.description // ""), ((.files | keys) | join(",")), .public, .updated_at] | @tsv'
    fi
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
    raw_list="$(fetch_gists)"

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
    local unknown_status_count=0
    local fallback_count=0
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

        if is_ipynb_title "$title" "$_files"; then
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

        local category status is_fallback
        IFS=$'\t' read -r category status is_fallback <<< "$(classify_gist "$title")"
        if [ "$status" = "unknown_status" ]; then
            unknown_status_count=$((unknown_status_count + 1))
        fi
        if [ "$is_fallback" = "true" ]; then
            fallback_count=$((fallback_count + 1))
        fi
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

    local excluded_total completeness_sum fallback_ratio
    excluded_total=$((excluded_counts[self_index] + excluded_counts[duplicate_title] + excluded_counts[ipynb]))
    completeness_sum=$((kept_count + excluded_total))
    fallback_ratio="$(awk -v fallback="$fallback_count" -v kept="$kept_count" 'BEGIN { printf "%.2f", kept ? (fallback * 100 / kept) : 0 }')"
    log "category_counts: 設計書・稼働中=${category_counts["設計書・稼働中"]:-0} 設計書・CLOSED=${category_counts["設計書・CLOSED"]:-0} 調査書・監査・レポート=${category_counts["調査書・監査・レポート"]:-0} 正本・カタログ・パターン=${category_counts["正本・カタログ・パターン"]:-0} 記事・対外発信=${category_counts["記事・対外発信"]:-0} その他・運用=${category_counts["その他・運用"]:-0}"
    log "completeness: fetched=${total_count} classified=${kept_count} excluded=${excluded_total} sum=${completeness_sum} match=$([ "$total_count" -eq "$completeness_sum" ] && printf true || printf false)"
    log "classification_quality: unknown_status=${unknown_status_count} fallback=${fallback_count} fallback_ratio_pct=${fallback_ratio}"
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

    GH_CMD="$GH_CMD" bash "$(dirname "${BASH_SOURCE[0]}")/gist_verified_write.sh" \
        "$GIST_INDEX_ID" "$GIST_INDEX_FILENAME" "$tmpfile"
    log "updated and verified gist ${GIST_INDEX_ID} (${GIST_INDEX_FILENAME})"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
