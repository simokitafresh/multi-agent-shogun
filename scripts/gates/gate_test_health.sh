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
LEDGER_STALE_HOURS="${LEDGER_STALE_HOURS:-168}"
REGRESSION_PCT="${TEST_TIMING_REGRESSION_PCT:-25}"

MEASURE=false
LEDGER_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --timing) MEASURE=true ;;
    --ledger-health) LEDGER_ONLY=true ;;
  esac
done

alert=0

# ─── 共通: ファイルリストと@test一覧を1回取得 ───
mapfile -t _bats_files < <(find "$TESTS_DIR" -name "*.bats" | sort)
_all_tests=$(grep -h "^@test " "${_bats_files[@]}" 2>/dev/null || true)

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

  for f in "${_bats_files[@]}"; do
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
  done

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

elif [ -f "$LEDGER" ] && head -1 "$LEDGER" | grep -q '^run_id'; then
  latest_fresh_epoch=$(awk -F'\t' '$9=="pass" && $11==0 && ($4=="all" || $4=="unit") {gsub(/Z$/, "", $13); cmd="date -u -d \"" $13 "\" +%s"; cmd | getline e; close(cmd); if(e>m)m=e} END{print m+0}' "$LEDGER")
  now_epoch=$(date +%s)
  age_hours=$(( (now_epoch - latest_fresh_epoch) / 3600 ))
  if (( latest_fresh_epoch == 0 || age_hours > LEDGER_STALE_HOURS )); then
    echo "WARN: timing ledger stale (age=${age_hours}h threshold=${LEDGER_STALE_HOURS}h); writer停止を確認してください"
    alert=1
  else
    echo "OK: timing ledger fresh (age=${age_hours}h threshold=${LEDGER_STALE_HOURS}h)"
  fi
  mapfile -t completed_runs < <(awk -F'\t' '$9=="pass" && $11==0 && ($4=="all" || $4=="unit") {seen[$1]=$13} END{for(r in seen) print seen[r] "\t" r}' "$LEDGER" | sort -r | cut -f2 | head -2)
  if (( ${#completed_runs[@]} >= 2 )); then
    current="${completed_runs[0]}" previous="${completed_runs[1]}"
    current_wall=$(awk -F'\t' -v r="$current" '$1==r && $11==0{s+=$8} END{print s+0}' "$LEDGER")
    previous_wall=$(awk -F'\t' -v r="$previous" '$1==r && $11==0{s+=$8} END{print s+0}' "$LEDGER")
    regression=$(awk -v c="$current_wall" -v p="$previous_wall" 'BEGIN{if(p<=0)print 0;else printf "%.1f",(c-p)*100/p}')
    echo "suite wall: ${previous_wall}s -> ${current_wall}s (${regression}%)"
    if awk -v r="$regression" -v th="$REGRESSION_PCT" 'BEGIN{exit !(r>th)}'; then
      echo "WARN: suite wall regression > ${REGRESSION_PCT}%"
      alert=1
    fi
    awk -F'\t' -v c="$current" -v p="$previous" -v th="$REGRESSION_PCT" '
      $1==c && $11==0 {cw[$6]=$8} $1==p && $11==0 {pw[$6]=$8}
      END {for(f in cw) if(pw[f]>0 && (cw[f]-pw[f])*100/pw[f]>th) printf "WARN: per-file regression %.1f%% %s\n",(cw[f]-pw[f])*100/pw[f],f}' "$LEDGER" | sort -nr -k4 | head -5
  else
    echo "INFO: regression comparison requires two completed all/unit runs"
  fi
  total_count=$(awk -F'\t' 'NR>1{count++} END{print count+0}' "$LEDGER")
  slow_count=$(awk -F'\t' -v th="$SLOW_THRESHOLD" 'NR>1 && $11==0 && $8+0>th{count++} END{print count+0}' "$LEDGER")
  echo "台帳読込: ${LEDGER}"
  echo "合計: ${total_count}行 / SLOW(>${SLOW_THRESHOLD}s): ${slow_count}行"
elif [ -f "$LEDGER" ]; then
  echo "WARN: legacy timing ledger schema; normal run_tests.sh完走で14列へ移行してください"
  alert=1
  total_count=0
  slow_count=0
else
  echo "INFO: 台帳未生成。--timing オプションで実行時間を計測してください。"
  echo "  bash scripts/gates/gate_test_health.sh --timing"
fi

echo ""

if $LEDGER_ONLY; then
  if (( alert > 0 )); then
    echo "総合判定: ALERT — timing ledger health"
    exit 1
  fi
  echo "総合判定: OK — timing ledger health"
  exit 0
fi

# ─────────────────────────────────────────────
# AC2: 重複テスト名検出
# ─────────────────────────────────────────────
echo "=== [AC2] 重複テスト名検出 ==="

dup_names=$(echo "$_all_tests" | sort | uniq -d | sed 's/@test "//;s/" {$//' || true)

if [ -n "$dup_names" ]; then
  echo "⚠ 重複テスト名を検出:"
  while IFS= read -r name; do
    echo "  \"${name}\""
    grep -rl "@test \"${name}\"" "${_bats_files[@]}" 2>/dev/null | sed 's/^/    → /'
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
while IFS=$'\t' read -r count f; do
  consolidate_list+=("${count}\t${f}")
done < <(
  awk -v th="$CONSOLIDATE_THRESHOLD" \
    '/^@test /{c[FILENAME]++} END{for(f in c) if(c[f]+0<=th) printf "%s\t%s\n", c[f], f}' \
    "${_bats_files[@]}" 2>/dev/null | sort -t$'\t' -k2
)

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
total_files=${#_bats_files[@]}
total_tests=$(echo "$_all_tests" | wc -l || echo 0)
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
