#!/usr/bin/env bash
# ============================================================
# gate_field_get.sh
# field_get.sh の契約テスト — 主要YAMLの代表フィールドが正常取得できることを検証
#
# Usage:
#   bash scripts/gates/gate_field_get.sh
#
# 教訓:
#   L070: grep -E "^\s+" で任意インデント対応(field_get.shで解決済)
#   L071: SCRIPT_DIR はリポルート基準(多数派方式)
#   L072: 新規スクリプト作成後は git add を忘れずに
#   L073: パス指定は realpath で実機確認
#
# Exit code: 0=全テストPASS, 1=FAIL
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# field_get.sh をsource (FIELD_GET_NO_LOG=1 でテスト中の依存記録を抑制)
export FIELD_GET_NO_LOG=1
# shellcheck source=../lib/field_get.sh
source "${SCRIPT_DIR}/scripts/lib/field_get.sh"

PASS=0
FAIL=0

assert_nonempty() {
  local desc="$1"
  local actual="$2"
  if [[ -n "$actual" ]]; then
    echo "  PASS: $desc (value: ${actual:0:40})"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (empty)"
    FAIL=$((FAIL + 1))
  fi
}

assert_match() {
  local desc="$1"
  local pattern="$2"
  local actual="$3"
  if [[ "$actual" =~ $pattern ]]; then
    echo "  PASS: $desc (value: ${actual:0:40})"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected pattern: $pattern, actual: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_warn() {
  local desc="$1"
  local stderr_output="$2"
  if echo "$stderr_output" | grep -q '\[field_get\] WARN'; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (no WARN in stderr: $stderr_output)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== gate_field_get.sh: 契約テスト ==="

# ──────────────────────────────────────────────
# (1) queue/shogun_to_karo.yaml → "status" (ネストフィールド)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 1: shogun_to_karo.yaml → status ---"
FILE1="${SCRIPT_DIR}/queue/shogun_to_karo.yaml"
if [[ -f "$FILE1" ]]; then
  result=$(field_get "$FILE1" "status")
  assert_nonempty "shogun_to_karo: status は非空" "$result"
else
  echo "  FAIL: $FILE1 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (2) queue/tasks/hayate.yaml → "status"
# ──────────────────────────────────────────────
echo ""
echo "--- Test 2: tasks/hayate.yaml → status ---"
FILE2="${SCRIPT_DIR}/queue/tasks/hayate.yaml"
if [[ -f "$FILE2" ]]; then
  result=$(field_get "$FILE2" "status")
  assert_match "hayate: status は既知値" "^(pending|acknowledged|in_progress|completed|done|idle)$" "$result"
else
  echo "  FAIL: $FILE2 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (3) queue/tasks/hayate.yaml → "task_id"
# ──────────────────────────────────────────────
echo ""
echo "--- Test 3: tasks/hayate.yaml → task_id ---"
if [[ -f "$FILE2" ]]; then
  result=$(field_get "$FILE2" "task_id")
  assert_nonempty "hayate: task_id は非空" "$result"
else
  echo "  FAIL: $FILE2 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (4) config/settings.yaml → "language"
# ──────────────────────────────────────────────
echo ""
echo "--- Test 4: settings.yaml → language ---"
FILE4="${SCRIPT_DIR}/config/settings.yaml"
if [[ -f "$FILE4" ]]; then
  result=$(field_get "$FILE4" "language")
  assert_match "settings: language は言語コード" "^(ja|en|es|zh|ko|fr|de)$" "$result"
else
  echo "  FAIL: $FILE4 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (5) config/projects.yaml → "projects" (配列の存在確認)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 5: projects.yaml → projects (top-level) ---"
FILE5="${SCRIPT_DIR}/config/projects.yaml"
if [[ -f "$FILE5" ]]; then
  # "projects:" はトップレベルキーで、値は空(YAML配列が次行以降)
  # field_get は空を返す可能性がある → "projects:" 行が存在すること自体を確認
  if grep -qE '^projects:' "$FILE5"; then
    echo "  PASS: projects.yaml にトップレベル 'projects:' キー存在"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: projects.yaml にトップレベル 'projects:' キーなし"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: $FILE5 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (6) config/projects.yaml → ネストフィールド "name" (PJ名の取得)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 6: projects.yaml → name (nested) ---"
if [[ -f "$FILE5" ]]; then
  result=$(field_get "$FILE5" "name")
  assert_nonempty "projects: name は非空" "$result"
else
  echo "  FAIL: $FILE5 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (7) WARN出力テスト — 意図的に存在しないフィールド名
# ──────────────────────────────────────────────
echo ""
echo "--- Test 7: 壊れたフィールド名でWARN出力確認 ---"
if [[ -f "$FILE4" ]]; then
  warn_output=$(field_get "$FILE4" "zzz_nonexistent_field_xyz" 2>&1 >/dev/null)
  assert_warn "存在しないフィールドでWARN出力" "$warn_output"
else
  echo "  FAIL: $FILE4 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (8) デフォルト値テスト — 存在しないフィールドにdefault指定
# ──────────────────────────────────────────────
echo ""
echo "--- Test 8: デフォルト値返却確認 ---"
if [[ -f "$FILE4" ]]; then
  result=$(field_get "$FILE4" "zzz_nonexistent_field_xyz" "my_default" 2>/dev/null)
  if [[ "$result" == "my_default" ]]; then
    echo "  PASS: デフォルト値 'my_default' が返却された"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: デフォルト値が返却されない (actual: $result)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: $FILE4 not found"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# 結果サマリ
# ──────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
