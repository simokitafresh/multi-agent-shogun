#!/usr/bin/env bash
# yaml_auto_archive.sh — bounded hot YAML lists with text-preserving archives.
#
# Config: config/yaml_auto_archive.tsv
# columns: path<TAB>keep<TAB>top_key<TAB>entry_regex<TAB>archive_path
#
# The implementation is intentionally line/block based. Do not replace this
# with yaml.dump/safe_dump; several operational YAML files contain long free
# text and mixed historical formatting.

set -euo pipefail

# WSL2最適化: $(cd)/$(dirname) subshell(~8ms) → string ops。
_yaa_self="${BASH_SOURCE[0]}"
[[ "$_yaa_self" != /* ]] && _yaa_self="$PWD/$_yaa_self"
_yaa_code_root="${_yaa_self%/scripts/yaml_auto_archive.sh}"
ROOT_DIR="${SHOGUN_ROOT:-$_yaa_code_root}"
source "$_yaa_code_root/scripts/lib/lock_path.sh"
unset _yaa_self
unset _yaa_code_root
CONFIG_FILE="${YAML_AUTO_ARCHIVE_CONFIG:-$ROOT_DIR/config/yaml_auto_archive.tsv}"
LOCK_FILE="/tmp/shogun_yaml_auto_archive.lock"

[ -f "$CONFIG_FILE" ] || exit 0

# WSL2最適化: flock subshell(~5-15ms) → exec fd。subshell fork排除。
exec 200>"$LOCK_FILE"
flock -w 10 200

# WSL2最適化: Python起動(~50ms) → grep+awk(~5ms)。
# アーカイブ不要の一般ケースでPython起動を完全排除。
# アーカイブ必要時はawk単一パスで全ブロック収集→archive追記→main上書き(atomic)。
_archive_one() {
    local path="$1" keep="$2" top_key="$3" entry_pattern="$4" archive_path="$5"
    local relpath="${path#$ROOT_DIR/}"
    local rel_archive="${archive_path#$ROOT_DIR/}"

    if [[ "$relpath" == "queue/insights.yaml" ]]; then
        echo "ALERT $relpath: lifecycle ledger requires status-aware reflux; generic count rotation forbidden" >&2
        return 1
    fi

    if [[ ! -f "$path" ]]; then
        echo "SKIP missing $relpath"
        return
    fi

    # grep -c: 1回のシーケンシャルスキャンでエントリ数を取得
    local count
    count=$(grep -cE "$entry_pattern" "$path" 2>/dev/null) || count=0

    # cmd_design_quality is consumed as a hot, recent-history log.  Its
    # configured retention must never be weakened into a small trimming value
    # (the 188 -> 5 incident); changing the limit requires an explicit code
    # change, not a mutable TSV edit.
    if [[ "$relpath" == "logs/cmd_design_quality.yaml" ]] && (( keep < ${CMD_QUALITY_MIN_HOT_ENTRIES:-200} )); then
        echo "ALERT $relpath: configured keep=$keep is below protected minimum ${CMD_QUALITY_MIN_HOT_ENTRIES:-200}; aborting without write" >&2
        return 1
    fi

    if (( count <= keep )); then
        echo "OK $relpath: entries=$count keep=$keep"
        return
    fi

    # アーカイブ必要 — awk単一パス
    local n_archive=$(( count - keep ))
    local archive_has_content=0 archive_before_count=0
    [[ -s "$archive_path" ]] && archive_has_content=1
    archive_before_count=$(grep -cE "$entry_pattern" "$archive_path" 2>/dev/null) || archive_before_count=0
    mkdir -p "$(dirname "$archive_path")"
    local tmp_path="${path}.tmp.$$"
    # NOTE: gawk dynamic regex(\s未サポート) → POSIX [[:space:]]に変換
    local awk_pattern="${entry_pattern//\\s/[[:space:]]}"

    awk \
        -v keep="$keep" \
        -v top_key="$top_key" \
        -v pattern="$awk_pattern" \
        -v archive_path="$archive_path" \
        -v tmp_path="$tmp_path" \
        -v archive_has_content="$archive_has_content" \
    'BEGIN {
        entry_count = 0
        in_entry = 0
        current_block = ""
    }
    $0 ~ pattern {
        if (in_entry) {
            entry_count++
            entries[entry_count] = current_block
        }
        in_entry = 1
        current_block = $0 "\n"
        next
    }
    in_entry { current_block = current_block $0 "\n"; next }
    END {
        if (in_entry) {
            entry_count++
            entries[entry_count] = current_block
        }
        n_keep  = int(keep)
        n_archive = entry_count - n_keep

        # archive追記 (新規作成時のみheader先出し)
        if (!archive_has_content && top_key != "-") {
            printf "%s:\n", top_key >> archive_path
        }
        for (i = 1; i <= n_archive; i++) {
            printf "%s", entries[i] >> archive_path
        }
        close(archive_path)

        # main上書き (atomic: tmp書込み→rename)
        if (top_key != "-") {
            printf "%s:\n", top_key > tmp_path
        }
        for (i = n_archive + 1; i <= entry_count; i++) {
            printf "%s", entries[i] >> tmp_path
        }
        close(tmp_path)
    }' "$path"

    # A rotation is allowed to reduce the hot-file count only when every
    # removed entry is present in the archive.  Verify before publishing the
    # replacement, so a parser/pattern regression becomes an ALERT rather
    # than destructive data loss.
    local kept_count archive_after_count expected_archive_count
    kept_count=$(grep -cE "$entry_pattern" "$tmp_path" 2>/dev/null) || kept_count=0
    archive_after_count=$(grep -cE "$entry_pattern" "$archive_path" 2>/dev/null) || archive_after_count=0
    expected_archive_count=$((archive_before_count + n_archive))
    if (( kept_count != keep || archive_after_count != expected_archive_count )); then
        rm -f "$tmp_path"
        echo "ALERT $relpath: rotation count mismatch before=$count keep=$kept_count expected_keep=$keep archive_before=$archive_before_count archive_after=$archive_after_count expected_archive=$expected_archive_count; aborting without replacing source" >&2
        return 1
    fi

    mv "$tmp_path" "$path"
    echo "ARCHIVED $relpath: $n_archive archived, $keep kept -> $rel_archive"
}

while IFS=$'\t' read -r rel_path keep_s top_key entry_pattern rel_archive; do
    [[ -z "$rel_path" || "$rel_path" == \#* ]] && continue
    if ! [[ "$keep_s" =~ ^[0-9]+$ ]] || (( keep_s < 1 )); then
        echo "invalid config line (keep must be integer >= 1): $rel_path" >&2
        exit 1
    fi
    [[ "$rel_path"    == /* ]] && fp="$rel_path"    || fp="$ROOT_DIR/$rel_path"
    [[ "$rel_archive" == /* ]] && fa="$rel_archive" || fa="$ROOT_DIR/$rel_archive"
    # cmd_quality_log.sh locks its own hot file while appending.  Take that
    # identical lock around a possible replacement to make append+archive
    # serializable; the global archive lock alone did not cover writers.
    if [[ "${fp#$ROOT_DIR/}" == "logs/cmd_design_quality.yaml" ]]; then
        exec 201>"$(lock_path "$fp")"
        flock -w 10 201 || { echo "ALERT ${fp#$ROOT_DIR/}: failed to acquire quality-log lock; aborting" >&2; exit 1; }
        _archive_one "$fp" "$keep_s" "$top_key" "$entry_pattern" "$fa"
        exec 201>&-
    else
        _archive_one "$fp" "$keep_s" "$top_key" "$entry_pattern" "$fa"
    fi
done < "$CONFIG_FILE"

exec 200>&-
