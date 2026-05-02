#!/usr/bin/env bash
# shellcheck disable=SC1091
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
  if [[ "$stderr_output" == *"[field_get] WARN"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (no WARN in stderr: $stderr_output)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== gate_field_get.sh: 契約テスト ==="

TMP_PREFIX="${TMPDIR:-/tmp}/gate_field_get.$$"
FIELD_FIXTURE="${TMP_PREFIX}.yaml"
trap 'rm -f "$FIELD_FIXTURE"' EXIT

printf '%s\n' \
  'task:' \
  '  status: assigned' \
  '  parent_cmd: cmd_fixture' \
  '  acceptance_criteria:' \
  '    AC1:' \
  '      status: pending' \
  '  lesson_referenced:' \
  '    - L034' \
  '    - L035' \
  'language: ja' \
  'projects:' \
  '  - id: dm-signal' \
  '    name: DM-Signal' \
  > "$FIELD_FIXTURE"

eval "$(field_get_multi "$FIELD_FIXTURE" status parent_cmd language name)"

# ──────────────────────────────────────────────
# (1) task fixture → "status" (ネストフィールド)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 1: task fixture → status ---"
assert_match "task: status は既知値" "^(assigned|pending|acknowledged|in_progress|completed|done|idle)$" "$status"

# ──────────────────────────────────────────────
# (2) task fixture → "parent_cmd"
# ──────────────────────────────────────────────
echo ""
echo "--- Test 2: task fixture → parent_cmd ---"
assert_nonempty "task: parent_cmd は非空" "$parent_cmd"

# ──────────────────────────────────────────────
# (3) task fixture → 最浅status
# ──────────────────────────────────────────────
echo ""
echo "--- Test 3: task fixture → 最浅status ---"
assert_match "task: AC内statusではなくtask直下statusを取得" "^assigned$" "$status"

# ──────────────────────────────────────────────
# (4) settings fixture → "language"
# ──────────────────────────────────────────────
echo ""
echo "--- Test 4: settings fixture → language ---"
assert_match "settings: language は言語コード" "^(ja|en|es|zh|ko|fr|de)$" "$language"

# ──────────────────────────────────────────────
# (5) projects fixture → "projects" (配列の存在確認)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 5: projects fixture → projects (top-level) ---"
if [[ $(<"$FIELD_FIXTURE") == *$'\nprojects:'* ]]; then
  echo "  PASS: projects fixture にトップレベル 'projects:' キー存在"
  PASS=$((PASS + 1))
else
  echo "  FAIL: projects fixture にトップレベル 'projects:' キーなし"
  FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────
# (6) projects fixture → ネストフィールド "name" (PJ名の取得)
# ──────────────────────────────────────────────
echo ""
echo "--- Test 6: projects fixture → name (nested) ---"
assert_nonempty "projects: name は非空" "$name"

# ──────────────────────────────────────────────
# (7) field_get scalar取得テスト
# ──────────────────────────────────────────────
echo ""
echo "--- Test 7: field_get scalar取得確認 ---"
result=$(field_get "$FIELD_FIXTURE" "language")
assert_match "field_get: top-level scalarを取得" "^ja$" "$result"

# ──────────────────────────────────────────────
# (8) ブロック配列取得テスト
# ──────────────────────────────────────────────
echo ""
echo "--- Test 8: ブロック配列取得確認 ---"
result=$(field_get "$FIELD_FIXTURE" "lesson_referenced")
assert_match "field_get: block arrayをinline取得" "^L034, L035$" "$result"

# ──────────────────────────────────────────────
# 結果サマリ
# ──────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
