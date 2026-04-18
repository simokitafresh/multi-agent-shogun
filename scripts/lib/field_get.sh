#!/usr/bin/env bash
# field_get.sh — YAML/JSON共通フィールド取得ライブラリ
# 教訓L070の根本解決: grep -E "^\s+フィールド名:" で任意インデント対応（2sp固定禁止）
#
# 使い方:
#   source方式: . scripts/lib/field_get.sh
#   単体テスト: bash scripts/lib/field_get.sh --test
#
# 関数:
#   field_get <file> <field> [default]  — フィールド値を取得
#
# 教訓L071: SCRIPT_DIR はリポルート基準 (多数派方式)
# 教訓L073: scripts/lib/ は ../.. でリポルートに到達

# SCRIPT_DIR: string ops instead of $(cd) subshell (~5ms savings on WSL2)
_fg_self="${BASH_SOURCE[0]}"
[[ "$_fg_self" != /* ]] && _fg_self="$PWD/$_fg_self"
_FIELD_GET_SCRIPT_DIR="${_fg_self%/scripts/lib/field_get.sh}"
unset _fg_self
# field_deps.tsv はホワイトリスト外 → 自動的にgit-ignored
_FIELD_DEPS_TSV="${_FIELD_GET_SCRIPT_DIR}/scripts/lib/field_deps.tsv"

# ──────────────────────────────────────────────────────
# field_get <file> <field> [default]
#   ファイル拡張子で自動判別: .yaml/.yml → grep/sed, .json → jq
#   結果が空 & defaultなし → WARNをstderrに出力して空文字を返す
#   結果が空 & defaultあり → defaultを返す
#   環境変数 FIELD_GET_NO_LOG=1 で依存記録を抑制
# ──────────────────────────────────────────────────────
field_get() {
  local file="$1"
  local field="$2"
  local _has_default=0
  local default=""
  if [[ $# -ge 3 ]]; then
    _has_default=1
    default="$3"
  fi
  local caller="${BASH_SOURCE[1]:-unknown}:${BASH_LINENO[0]:-0}"

  if [[ -z "$file" || -z "$field" ]]; then
    echo "[field_get] ERROR: usage: field_get <file> <field> [default]" >&2
    return 1
  fi

  local result=""
  local ext="${file##*.}"

  if [[ "$ext" == "json" ]]; then
    # JSON: jq で取得
    if command -v jq &>/dev/null; then
      result=$(jq -r ".${field} // empty" "$file" 2>/dev/null)
    else
      echo "[field_get] WARN: jq not found, cannot parse JSON: $file (caller: $caller)" >&2
    fi
  else
    # YAML: L070対策 — ^\s+ で任意インデント対応（2sp固定禁止）
    # cmd_1355修正: トップレベル(^field:)を先に検索。なければインデント付きにフォールバック
    local field_line=""

    # 1. トップレベル(インデントなし)を優先検索 (grep -m1 + bash str ops, sed不使用)
    field_line=$(grep -m1 -E "^${field}:" "$file" 2>/dev/null)
    if [[ -n "$field_line" ]]; then
      result="${field_line#*:}"
      result="${result#"${result%%[![:space:]]*}"}"   # ltrim whitespace
      result="${result#\'}" ; result="${result%\'}"   # strip single quotes
      result="${result#\"}" ; result="${result%\"}"   # strip double quotes
    fi

    # 2. トップレベルになければインデント付き(最浅マッチ)にフォールバック
    if [[ -z "$result" && -z "$field_line" ]]; then
      field_line=$(grep -E "^\s+${field}:" "$file" 2>/dev/null | awk '{
        match($0, /[^ \t]/)
        indent = RSTART - 1
        if (NR == 1 || indent < min_indent) {
          min_indent = indent
          best = $0
        }
      } END { if (NR > 0) print best }')
      if [[ -n "$field_line" ]]; then
        # 最初のコロンでのみ分割（フィールド名にregex特殊文字があっても安全）
        result="${field_line#*:}"
        result="${result#"${result%%[![:space:]]*}"}"   # ltrim whitespace
        result="${result#\'}" ; result="${result%\'}"   # strip single quotes
        result="${result#\"}" ; result="${result%\"}"   # strip double quotes
      fi
    fi

    # ブロック配列形式:
    # field:
    #   - a
    #   - b
    # を "a, b" に変換して返す
    if [[ -z "$result" && -n "$field_line" && "$field_line" =~ ^[[:space:]]*${field}:[[:space:]]*$ ]]; then
      result=$(awk -v field="$field" '
        function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
        function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
        BEGIN { capture = 0; base = -1; count = 0; out = "" }
        {
          line = $0
          if (match(line, /[^ ]/)) {
            indent = RSTART - 1
          } else {
            indent = length(line)
          }
          if (capture == 0) {
            if (line ~ "^[[:space:]]*" field ":[[:space:]]*$") {
              capture = 1
              base = indent
            }
            next
          }
          if (indent <= base && line !~ /^[[:space:]]*$/) {
            exit
          }
          if (line ~ /^[[:space:]]*-[[:space:]]+/) {
            item = line
            sub(/^[[:space:]]*-[[:space:]]*/, "", item)
            item = rtrim(ltrim(item))
            if (count == 0) {
              out = item
            } else {
              out = out ", " item
            }
            count++
          }
        }
        END { print out }
      ' "$file")
    fi
  fi

  # 依存マップ記録
  if [[ "${FIELD_GET_NO_LOG:-0}" != "1" ]]; then
    _field_get_log "$caller" "$file" "$field"
  fi

  if [[ -z "$result" ]]; then
    if [[ "$_has_default" == "1" ]]; then
      echo "$default"
    else
      echo "[field_get] WARN: empty result for '$field' in '$file' (caller: $caller)" >&2
      echo ""
    fi
    return 0
  fi

  echo "$result"
}

# ──────────────────────────────────────────────────────
# _field_get_log <caller> <file> <field>
#   field_deps.tsv に {caller, file, field, timestamp} をアトミック追記
#   flock取得失敗時はスキップ（本体処理は止めない）
# ──────────────────────────────────────────────────────
_field_get_log() {
  local caller="$1"
  local file="$2"
  local field="$3"
  local ts
  # printf -v instead of $(date) — bash built-in, no subprocess (~2ms savings)
  printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1

  local lock_file="${_FIELD_DEPS_TSV}.lock"
  # { } block instead of ( ) subshell — avoids subprocess creation (~3ms savings)
  {
    flock -n 200 || return 0

    # 10MB超で5世代ローテーション（偵察cmd_1041指摘: 無限肥大防止）
    if [[ -f "$_FIELD_DEPS_TSV" ]]; then
      local size
      size=$(stat -c%s "$_FIELD_DEPS_TSV" 2>/dev/null || echo 0)
      if [[ "$size" -gt 10485760 ]]; then
        local i=4
        while [[ $i -ge 1 ]]; do
          [[ -f "${_FIELD_DEPS_TSV}.${i}" ]] && mv -f "${_FIELD_DEPS_TSV}.${i}" "${_FIELD_DEPS_TSV}.$((i + 1))"
          i=$((i - 1))
        done
        mv -f "$_FIELD_DEPS_TSV" "${_FIELD_DEPS_TSV}.1"
        touch "$_FIELD_DEPS_TSV"
      fi
    fi

    printf '%s\t%s\t%s\t%s\n' "$caller" "$file" "$field" "$ts" >> "$_FIELD_DEPS_TSV"
  } 200>"$lock_file" 2>/dev/null
}

# ══════════════════════════════════════════════════════
# 単体テスト (bash scripts/lib/field_get.sh --test)
# テスト項目: (a)YAML取得 (b)JSON取得 (c)空結果WARN (d)デフォルト値 (e)依存記録 (f)YAML配列
# ══════════════════════════════════════════════════════
_field_get_run_tests() {
  local pass=0
  local fail=0
  local tmpdir
  tmpdir=$(mktemp -d)

  # テスト用の一時TSVに差し替え（グローバル変数上書き）
  _FIELD_DEPS_TSV="${tmpdir}/field_deps.tsv"

  _assert() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
      echo "  PASS: $desc"
      pass=$((pass + 1))
    else
      echo "  FAIL: $desc"
      echo "        expected: '$expected'"
      echo "        actual:   '$actual'"
      fail=$((fail + 1))
    fi
  }

  echo "=== field_get unit tests ==="

  # ──────────────────────────────────────
  # (a) YAML取得
  # ──────────────────────────────────────
  local yaml_file="${tmpdir}/test.yaml"
  cat > "$yaml_file" <<'YAML'
task:
  status: pending
  assigned_to: hayate
  parent_cmd: cmd_372
  title: 'test task'
top_level: root_value
YAML

  local result
  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "status")
  _assert "YAML: ネストフィールド取得(status)" "pending" "$result"

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "assigned_to")
  _assert "YAML: ネストフィールド取得(assigned_to)" "hayate" "$result"

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "top_level")
  _assert "YAML: トップレベルフィールド取得" "root_value" "$result"

  # (a2) colon含むYAML値の取得テスト
  local yaml_colon_file="${tmpdir}/test_colon.yaml"
  cat > "$yaml_colon_file" <<'YAML'
task:
  deployed_at: '2026-03-18T02:12:06'
  url: https://example.com:8080/path
  description: 'content: with colon'
top_url: http://host:3000
YAML

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_colon_file" "deployed_at")
  _assert "YAML: colon含む値(timestamp)" "2026-03-18T02:12:06" "$result"

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_colon_file" "url")
  _assert "YAML: colon含む値(URL)" "https://example.com:8080/path" "$result"

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_colon_file" "description")
  _assert "YAML: colon含む値(text with colon)" "content: with colon" "$result"

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_colon_file" "top_url")
  _assert "YAML: トップレベルcolon含む値" "http://host:3000" "$result"

  # (a3) 最浅マッチテスト: AC内statusとtask-level statusの共存（cmd_1185 AC1）
  local yaml_shallow_file="${tmpdir}/test_shallow.yaml"
  cat > "$yaml_shallow_file" <<'YAML'
task:
  acceptance_criteria:
    AC1:
      status: pending
    AC2:
      status: pending
  status: idle
  assigned_to: hayate
YAML

  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_shallow_file" "status")
  _assert "YAML: 最浅マッチ(task-level status=idle vs AC status=pending)" "idle" "$result"

  local yaml_array_file="${tmpdir}/test_array.yaml"
  cat > "$yaml_array_file" <<'YAML'
task:
  lesson_referenced:
    - L034
    - L035
    - L100
YAML
  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_array_file" "lesson_referenced")
  _assert "YAML: ブロック配列をインライン変換" "L034, L035, L100" "$result"

  # ──────────────────────────────────────
  # (b) JSON取得
  # ──────────────────────────────────────
  if command -v jq &>/dev/null; then
    local json_file="${tmpdir}/test.json"
    printf '{"status": "active", "count": 5, "name": "field_get"}\n' > "$json_file"

    result=$(FIELD_GET_NO_LOG=1 field_get "$json_file" "status")
    _assert "JSON: フィールド取得(status)" "active" "$result"

    result=$(FIELD_GET_NO_LOG=1 field_get "$json_file" "name")
    _assert "JSON: フィールド取得(name)" "field_get" "$result"
  else
    echo "  SKIP: JSON test (jq not installed)"
  fi

  # ──────────────────────────────────────
  # (c) 空結果WARN — 存在しないフィールド
  # ──────────────────────────────────────
  local warn_output
  warn_output=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "nonexistent_field_xyz" 2>&1 >/dev/null)
  if echo "$warn_output" | grep -q "\[field_get\] WARN"; then
    echo "  PASS: 空結果WARN出力(stderr)"
    pass=$((pass + 1))
  else
    echo "  FAIL: 空結果WARNが出力されなかった"
    echo "        stderr: '$warn_output'"
    fail=$((fail + 1))
  fi

  # ──────────────────────────────────────
  # (d) デフォルト値
  # ──────────────────────────────────────
  result=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "nonexistent_field_xyz" "default_val")
  _assert "デフォルト値返却" "default_val" "$result"

  # デフォルト値指定時はWARNが出ないこと
  warn_output=$(FIELD_GET_NO_LOG=1 field_get "$yaml_file" "nonexistent_field_xyz" "default_val" 2>&1 >/dev/null)
  if echo "$warn_output" | grep -q "\[field_get\] WARN"; then
    echo "  FAIL: デフォルト値指定時にWARNが出力された"
    fail=$((fail + 1))
  else
    echo "  PASS: デフォルト値指定時WARNなし"
    pass=$((pass + 1))
  fi

  # ──────────────────────────────────────
  # (e) 依存記録 — field_deps.tsv への追記
  # ──────────────────────────────────────
  FIELD_GET_NO_LOG=0 field_get "$yaml_file" "status" >/dev/null 2>&1 || true
  # flock処理は非同期サブシェルのため少し待つ
  sleep 0.1

  if [[ -f "${tmpdir}/field_deps.tsv" ]] && grep -q "status" "${tmpdir}/field_deps.tsv"; then
    echo "  PASS: 依存記録(field_deps.tsv に追記)"
    pass=$((pass + 1))
  else
    echo "  FAIL: 依存記録がfield_deps.tsvに追記されなかった"
    echo "        tsv exists: $(ls -la "${tmpdir}/field_deps.tsv" 2>&1)"
    fail=$((fail + 1))
  fi

  # ──────────────────────────────────────
  # (f) ローテーション — 10MB超で世代管理
  # ──────────────────────────────────────
  # 11MBのダミーTSVを作成してローテーション発火を確認
  dd if=/dev/zero of="${tmpdir}/field_deps.tsv" bs=1M count=11 2>/dev/null
  FIELD_GET_NO_LOG=0 field_get "$yaml_file" "status" >/dev/null 2>&1 || true
  sleep 0.1

  if [[ -f "${tmpdir}/field_deps.tsv.1" ]]; then
    echo "  PASS: ローテーション発火(10MB超→.1作成)"
    pass=$((pass + 1))
  else
    echo "  FAIL: ローテーションが発火しなかった"
    fail=$((fail + 1))
  fi

  rm -rf "$tmpdir"

  echo ""
  echo "=== Results: ${pass} passed, ${fail} failed ==="
  if [[ "$fail" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ──────────────────────────────────────────────────────
# field_get_multi <file> <field1> <field2> ...
#   1回のawk passで複数フィールドを一括取得。
#   出力: field1='value1'\nfield2='value2'\n...  (eval可能)
#   未存在フィールドは空文字列。
# ──────────────────────────────────────────────────────
field_get_multi() {
    local file="$1"
    shift
    if [ ! -f "$file" ] || [ "$#" -eq 0 ]; then return 1; fi

    local fields_str=""
    local _f _cnt=0
    for _f in "$@"; do
        if [ "$_cnt" -gt 0 ]; then fields_str="${fields_str}|${_f}"; else fields_str="$_f"; fi
        _cnt=$((_cnt + 1))
    done

    awk -v fields_str="$fields_str" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2); gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "\047" && substr(s,length(s),1) == "\047") {
            s = substr(s, 2, length(s)-2)
        }
    }
    return s
}
function shell_escape(s,    out) {
    gsub(/\047/, "\047\\\047\047", s)
    return "\047" s "\047"
}
BEGIN {
    nf = split(fields_str, farr, "|")
    for (i = 1; i <= nf; i++) { found[i] = 0; vals[i] = "" }
}
{
    for (i = 1; i <= nf; i++) {
        if (!found[i]) {
            pat = "^[[:space:]]*" farr[i] ":[[:space:]]+"
            if ($0 ~ pat) {
                v = $0; sub(pat, "", v); v = trim(v)
                if (substr(v, 1, 1) != "\"" && substr(v, 1, 1) != "\047") {
                    sub(/[[:space:]]+#.*$/, "", v)
                }
                v = trim(unquote(v))
                vals[i] = v; found[i] = 1
            }
        }
    }
}
END {
    for (i = 1; i <= nf; i++) {
        printf "%s=%s\n", farr[i], shell_escape(vals[i])
    }
}
' "$file"
}

# ──────────────────────────────────────────────────────
# メイン実行 (直接実行時のみ)
# ──────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--test" ]]; then
    _field_get_run_tests
  else
    echo "Usage: bash scripts/lib/field_get.sh --test" >&2
    echo "       or: . scripts/lib/field_get.sh  (source)" >&2
    exit 1
  fi
fi
