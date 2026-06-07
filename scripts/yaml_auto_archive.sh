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
ROOT_DIR="${SHOGUN_ROOT:-${_yaa_self%/scripts/yaml_auto_archive.sh}}"
unset _yaa_self
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

    if [[ ! -f "$path" ]]; then
        echo "SKIP missing $relpath"
        return
    fi

    # grep -c: 1回のシーケンシャルスキャンでエントリ数を取得
    local count
    count=$(grep -cE "$entry_pattern" "$path" 2>/dev/null) || count=0

    if (( count <= keep )); then
        echo "OK $relpath: entries=$count keep=$keep"
        return
    fi

    # アーカイブ必要 — awk単一パス
    local n_archive=$(( count - keep ))
    local archive_has_content=0
    [[ -s "$archive_path" ]] && archive_has_content=1
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
    _archive_one "$fp" "$keep_s" "$top_key" "$entry_pattern" "$fa"
done < "$CONFIG_FILE"

exec 200>&-
