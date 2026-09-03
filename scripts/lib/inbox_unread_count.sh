#!/usr/bin/env bash
# inbox_unread_count.sh — inbox YAML の未読件数をレコード境界で数える共通実装。
# 由来: cmd_karo_hotfix_inbox_unread_source_202609031435(prompt_state_inject.sh)。
# T3-S-43(2026-09-03 20:22): post-shogun-inbox-check.sh が素朴な awk '/read: false/' のまま
# 残り、bulletin_notify の content 内に現れた「read: false」文字列を未読 1 と誤カウント。
# 本文(単一行 content/ブロックスカラー)ではなくレコード直下の `read: false` フィールドのみ数える。
# 用法: inbox_unread_count <inbox_yaml>  → 数値を stdout(不在/不正時は 0)
inbox_unread_count() {
  local f="$1" n
  [[ -f "$f" ]] || { echo 0; return 0; }
  n="$(awk '
    BEGIN { in_block = 0; block_indent = -1; field_indent = -1 }
    {
      line = $0
      match(line, /^[ ]*/)
      ind = RLENGTH
      content = substr(line, ind + 1)
      is_new_record = (content ~ /^-([ ]|$)/)
      if (is_new_record) {
        sub(/^-[ ]*/, "", content)
        ind = ind + 2
        in_block = 0
        field_indent = ind
        if (content == "") next
      } else if (in_block) {
        if (ind > block_indent) { next }
        in_block = 0
      }
      if (!is_new_record && ind != field_indent) { next }
      if (content ~ /^read:[ ]*false[ ]*$/) { c++ }
      else if (content ~ /^[A-Za-z_][A-Za-z0-9_]*:[ ]*[|>][+-]?[ ]*$/) { in_block = 1; block_indent = ind }
    }
    END { print c + 0 }
  ' "$f" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  echo "$n"
}
