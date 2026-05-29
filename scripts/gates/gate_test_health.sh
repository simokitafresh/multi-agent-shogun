#!/usr/bin/env bash
# gate_test_health.sh — テスト品質自動管理ゲート (cmd_3103)
#
# 用途:
#   1. テスト実行時間台帳を自動生成し、30秒超ファイルを一覧化 (AC1)
#   2. 重複テスト名を検出 (AC2)
#   3. テスト数5件以下のファイル(統合候補)を一覧化 (AC3)
#
# Usage:
#   bash scripts/gates/gate_test_health.sh [--timing] [--all] [--report]
#
# Options:
#   --timing    テスト実行時間計測を実行(省略時は台帳の最新値を表示)
#
# 出力ファイル:
#   logs/test_timing_ledger.tsv   テスト実行時間台帳

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="${TESTS_DIR:-${REPO_ROOT}/tests/unit}"
LEDGER="${TEST_TIMING_LEDGER:-${REPO_ROOT}/logs/test_timing_ledger.tsv}"
SLOW_THRESHOLD="${SLOW_THRESHOLD:-30}"
CONSOLIDATE_THRESHOLD="${CONSOLIDATE_THRESHOLD:-5}"

MEASURE=false
for arg in "$@"; do
  case "$arg" in
    --timing) MEASURE=true ;;
  esac
done

alert=0

# ─────────────────────────────────────────────
# AC1: テスト実行時間台帳
# ─────────────────────────────────────────────
echo "=== [AC1] テスト実行時間台帳 ==="

if $MEASURE; then
  mkdir -p "$(dirname "$LEDGER")"
  echo -e "seconds\tfile\ttest_count\tstatus" > "$LEDGER"

  slow_files=()
  total_files=0
  measured=0

  while IFS= read -r f; do
    total_files=$((total_files + 1))
    test_count=$(grep -c "^@test " "$f" 2>/dev/null || echo 0)
    start_ns=$(date +%s%N)
    if bats --jobs 1 "$f" > /dev/null 2>&1; then
      bats_status="ok"
    else
      bats_status="fail"
    fi
    end_ns=$(date +%s%N)
    # bash整数演算: nanoseconds→seconds(切り捨て)
    elapsed_ns=$((end_ns - start_ns))
    elapsed=$((elapsed_ns / 1000000000))
    measured=$((measured + 1))

    echo -e "${elapsed}\t${f}\t${test_count}\t${bats_status}" >> "$LEDGER"

    if (( elapsed > SLOW_THRESHOLD )); then
      slow_files+=("${elapsed}s\t${test_count}tests\t${f}")
    fi
  done < <(find "$TESTS_DIR" -name "*.bats" | sort)

  echo "計測完了: ${measured}/${total_files} ファイル"
  echo "台帳出力: ${LEDGER}"
  echo ""

  if (( ${#slow_files[@]} > 0 )); then
    echo "⚠ SLOW FILES (>${SLOW_THRESHOLD}s):"
    for item in "${slow_files[@]}"; do
      echo -e "  ${item}"
    done
    alert=1
  else
    echo "OK: ${SLOW_THRESHOLD}秒超のファイルなし"
  fi

elif [ -f "$LEDGER" ]; then
  # 既存台帳を表示
  slow_count=$(awk -F'\t' -v th="$SLOW_THRESHOLD" 'NR>1 && $1+0 > th {count++} END {print count+0}' "$LEDGER")
  total_count=$(awk 'NR>1{count++} END{print count+0}' "$LEDGER")
  echo "台帳読込: ${LEDGER}"
  echo "合計: ${total_count}ファイル / SLOW(>${SLOW_THRESHOLD}s): ${slow_count}ファイル"

  if (( slow_count > 0 )); then
    echo ""
    echo "⚠ SLOW FILES (>${SLOW_THRESHOLD}s):"
    awk -F'\t' -v th="$SLOW_THRESHOLD" 'NR>1 && $1+0 > th {printf "  %ss\t%stests\t%s\n", $1, $3, $2}' "$LEDGER"
    alert=1
  else
    echo "OK: ${SLOW_THRESHOLD}秒超のファイルなし"
  fi
else
  echo "INFO: 台帳未生成。--timing オプションで実行時間を計測してください。"
  echo "  bash scripts/gates/gate_test_health.sh --timing"
fi

echo ""

# ─────────────────────────────────────────────
# AC2: 重複テスト名検出
# ─────────────────────────────────────────────
echo "=== [AC2] 重複テスト名検出 ==="

dup_names=$(grep -rh "^@test " "$TESTS_DIR"/*.bats 2>/dev/null | sort | uniq -d | sed 's/@test "//;s/" {$//' || true)

if [ -n "$dup_names" ]; then
  echo "⚠ 重複テスト名を検出:"
  while IFS= read -r name; do
    echo "  \"${name}\""
    grep -rl "@test \"${name}\"" "$TESTS_DIR"/*.bats 2>/dev/null | sed 's/^/    → /'
  done <<< "$dup_names"
  alert=1
else
  echo "OK: 重複テスト名なし"
fi

echo ""

# ─────────────────────────────────────────────
# AC3: 統合候補(テスト数≤5件)一覧化
# ─────────────────────────────────────────────
echo "=== [AC3] 統合候補ファイル (テスト数≤${CONSOLIDATE_THRESHOLD}件) ==="

consolidate_list=()
while IFS= read -r f; do
  count=$(grep -c "^@test " "$f" 2>/dev/null || echo 0)
  if (( count <= CONSOLIDATE_THRESHOLD )); then
    consolidate_list+=("${count}\t${f}")
  fi
done < <(find "$TESTS_DIR" -name "*.bats" | sort)

if (( ${#consolidate_list[@]} > 0 )); then
  echo "統合候補: ${#consolidate_list[@]}ファイル"
  for item in "${consolidate_list[@]}"; do
    echo -e "  ${item}"
  done
else
  echo "OK: 統合候補なし"
fi

echo ""

# ─────────────────────────────────────────────
# 総合判定
# ─────────────────────────────────────────────
total_files=$(find "$TESTS_DIR" -name "*.bats" | wc -l)
total_tests=$(grep -rh "^@test " "$TESTS_DIR"/*.bats 2>/dev/null | wc -l || echo 0)
echo "=== 総合サマリ ==="
echo "テストファイル数: ${total_files}"
echo "テスト総件数: ${total_tests}"
echo "統合候補: ${#consolidate_list[@]}ファイル"

if [ -n "$dup_names" ]; then
  echo "重複テスト名: $(echo "$dup_names" | wc -l)件 ⚠"
else
  echo "重複テスト名: 0件 OK"
fi

if (( alert > 0 )); then
  echo ""
  echo "総合判定: ALERT — 上記の警告を確認してください"
  exit 1
else
  echo ""
  echo "総合判定: OK"
  exit 0
fi
