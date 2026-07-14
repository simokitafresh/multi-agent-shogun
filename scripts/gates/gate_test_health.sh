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
RATCHET_MIN_RUNS="${TEST_TIMING_RATCHET_MIN_RUNS:-5}"
RATCHET_SUITE_ABS_SEC="${TEST_TIMING_RATCHET_SUITE_ABS_SEC:-30}"
RATCHET_EXCEPTIONS="${TEST_TIMING_RATCHET_EXCEPTIONS:-${REPO_ROOT}/config/test_timing_budget_exceptions.tsv}"
ASSET_CATALOG="${TEST_ASSET_CATALOG:-${REPO_ROOT}/logs/test_asset_catalog.tsv}"
PRODUCTION_ROOT="${TEST_PRODUCTION_ROOT:-${REPO_ROOT}}"

MEASURE=false
LEDGER_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --timing) MEASURE=true ;;
    --ledger-health) LEDGER_ONLY=true ;;
  esac
done

alert=0
ratchet_block=0

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
  ledger_fresh=0
  latest_fresh_epoch=$(awk -F'\t' '$9=="pass" && $11==0 && ($4=="all" || $4=="unit") {gsub(/Z$/, "", $13); cmd="date -u -d \"" $13 "\" +%s"; cmd | getline e; close(cmd); if(e>m)m=e} END{print m+0}' "$LEDGER")
  now_epoch=$(date +%s)
  age_hours=$(( (now_epoch - latest_fresh_epoch) / 3600 ))
  if (( latest_fresh_epoch == 0 || age_hours > LEDGER_STALE_HOURS )); then
    echo "WARN: timing ledger stale (age=${age_hours}h threshold=${LEDGER_STALE_HOURS}h); writer停止を確認してください"
    alert=1
  else
    echo "OK: timing ledger fresh (age=${age_hours}h threshold=${LEDGER_STALE_HOURS}h)"
    ledger_fresh=1
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

  # D3 budget ratchet.  It only compares complete, non-cache all/unit runs
  # produced by the same repo/suite_root/resource_tags pipeline.  Until five
  # comparable runs exist, a threshold is deliberately not invented.
  ratchet_out="$(python3 - "$LEDGER" "$RATCHET_MIN_RUNS" "$REGRESSION_PCT" "$RATCHET_SUITE_ABS_SEC" "$RATCHET_EXCEPTIONS" "$ledger_fresh" <<'PY'
import csv, datetime as dt, math, pathlib, statistics, sys

ledger, min_runs, pct, suite_abs, exception_path, ledger_fresh = sys.argv[1:]
min_runs, pct, suite_abs = int(min_runs), float(pct), float(suite_abs)
if ledger_fresh != "1":
    print("WARN: timing ratchet unavailable: stale ledger; BLOCK disabled")
    raise SystemExit(0)
rows = list(csv.DictReader(open(ledger, encoding="utf-8"), delimiter="\t"))
required = {"run_id", "repo", "commit_sha", "suite_root", "test_file", "wall_sec",
            "status", "skip_count", "cache_hit", "source_fingerprint", "measured_at", "resource_tags"}
if not rows or not required.issubset(rows[0]):
    print("WARN: timing ratchet unavailable: legacy schema")
    raise SystemExit(0)

runs = {}
for row in rows:
    if row["status"] != "pass" or row["cache_hit"] != "0" or row["suite_root"] not in ("all", "unit"):
        continue
    runs.setdefault(row["run_id"], []).append(row)

valid = []
mixed = 0
for run_id, items in runs.items():
    identity = {(r["repo"], r["suite_root"], r["resource_tags"], r["commit_sha"], r["measured_at"]) for r in items}
    if len(identity) != 1 or any(r["skip_count"] != "0" for r in items):
        mixed += 1
        continue
    repo, suite, tags, revision, measured = next(iter(identity))
    try:
        stamp = dt.datetime.fromisoformat(measured.replace("Z", "+00:00"))
    except ValueError:
        mixed += 1
        continue
    valid.append(((repo, suite, tags), stamp, revision, items))

if mixed:
    print(f"WARN: timing ratchet ignored {mixed} mixed-revision/incomplete run(s)")
    print("WARN: timing ratchet unavailable: mixed revision; BLOCK disabled")
    raise SystemExit(0)

cohorts = {}
for item in valid:
    cohorts.setdefault(item[0], []).append(item)
if not cohorts:
    print("WARN: timing ratchet unavailable: no comparable completed runs")
    raise SystemExit(0)

cohort, history = max(cohorts.items(), key=lambda pair: max(x[1] for x in pair[1]))
history.sort(key=lambda x: x[1])
if len(history) < min_runs:
    print(f"WARN: timing ratchet warm-up {len(history)}/{min_runs} comparable runs; BLOCK disabled")
    raise SystemExit(0)

def percentile(values, q):
    values = sorted(values)
    pos = (len(values) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    return values[lo] if lo == hi else values[lo] + (values[hi] - values[lo]) * (pos - lo)

current, baseline = history[-1], history[:-1]
baseline_files = [float(r["wall_sec"]) for run in baseline for r in run[3]]
p50, p90, p95, maximum = (percentile(baseline_files, q) for q in (.50, .90, .95, 1.0))
walls = [sum(float(r["wall_sec"]) for r in run[3]) for run in baseline]
wall_median = statistics.median(walls)
current_wall = sum(float(r["wall_sec"]) for r in current[3])
print(f"ratchet cohort repo={cohort[0]} suite={cohort[1]} tags={cohort[2]} runs={len(history)}")
print(f"ratchet file distribution p50={p50:.3f}s p90={p90:.3f}s p95={p95:.3f}s max={maximum:.3f}s")
print(f"ratchet suite rolling_median={wall_median:.3f}s current={current_wall:.3f}s")

active_exception = False
path = pathlib.Path(exception_path)
if path.exists():
    exception_rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
    if not exception_rows or set(exception_rows[0]) != {"owner", "expires", "reason"}:
        print("BLOCK: timing ratchet exception schema must be owner<TAB>expires<TAB>reason")
        raise SystemExit(2)
    today = dt.datetime.now(dt.timezone.utc).date()
    for item in exception_rows:
        try:
            expiry = dt.date.fromisoformat(item["expires"])
        except (TypeError, ValueError):
            print("BLOCK: timing ratchet exception expires must be YYYY-MM-DD")
            raise SystemExit(2)
        if not item["owner"].strip() or not item["reason"].strip():
            print("BLOCK: timing ratchet exception requires owner and measured reason")
            raise SystemExit(2)
        active_exception |= expiry >= today

limit_ratio = 1.0 + pct / 100.0
# A file budget applies only at the change boundary.  Compare each current
# row with the newest baseline row for that same test_file: absence means new;
# a different source fingerprint means changed.  Existing unchanged slowness
# remains visible in distribution output but cannot newly trip the file BLOCK.
latest_baseline_file = {}
for run in baseline:
    for row in run[3]:
        latest_baseline_file[row["test_file"]] = row
changed_rows = []
for row in current[3]:
    previous = latest_baseline_file.get(row["test_file"])
    if previous is None or previous["source_fingerprint"] != row["source_fingerprint"]:
        changed_rows.append(row)
file_hits = [r for r in changed_rows if float(r["wall_sec"]) > p95 and float(r["wall_sec"]) > p95 * limit_ratio]
suite_hit = current_wall > wall_median + suite_abs and current_wall > wall_median * limit_ratio
if file_hits or suite_hit:
    if active_exception:
        print("WARN: timing ratchet exceeded but active measured exception suppresses BLOCK")
    else:
        if file_hits:
            print("BLOCK: new/changed test budget exceeded: " + ", ".join(r["test_file"] for r in file_hits))
        if suite_hit:
            print(f"BLOCK: suite wall exceeded absolute +{suite_abs:.1f}s and relative +{pct:.1f}%")
        raise SystemExit(2)
else:
    print("OK: timing budget ratchet within absolute and relative limits")
PY
)" || ratchet_rc=$?
  ratchet_rc="${ratchet_rc:-0}"
  printf '%s\n' "$ratchet_out"
  if (( ratchet_rc == 2 )); then
    ratchet_block=1
    alert=1
  elif [[ "$ratchet_out" == *WARN:* ]]; then
    alert=1
  fi
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
  if (( ratchet_block > 0 )); then
    echo "総合判定: BLOCK — timing budget ratchet"
    exit 2
  fi
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
# AC4: 陳腐化4列 + test-double許可4類型catalog (D4')
# ─────────────────────────────────────────────
echo "=== [AC4] test asset / double catalog ==="

# Static-only scan.  Optional annotations make symbol/spec intent explicit:
#   # test-health: production-symbol function_name
#   # test-health: spec-status active|superseded|removed
# Double allow-list categories are declared beside the use site:
#   # test-health: mock-category external-service|destructive-operation|real-time|failure-injection
asset_out="$(python3 - "$PRODUCTION_ROOT" "$ASSET_CATALOG" "${_bats_files[@]}" <<'PY'
import pathlib, re, subprocess, sys

root, catalog, *test_files = sys.argv[1:]
root = pathlib.Path(root).resolve()
catalog = pathlib.Path(catalog)
catalog.parent.mkdir(parents=True, exist_ok=True)
path_re = re.compile(r"(?<![A-Za-z0-9_.-])((?:scripts|src|app|lib)/[A-Za-z0-9_./-]+)")
symbol_re = re.compile(r"test-health:\s*production-symbol\s+([A-Za-z_][A-Za-z0-9_]*)")
spec_re = re.compile(r"test-health:\s*spec-status\s+(active|superseded|removed)")
mock_re = re.compile(r"\b(?:mock|monkeypatch|patch|stub|fake)(?:_|\b)", re.I)
category_re = re.compile(r"test-health:\s*mock-category\s+(external-service|destructive-operation|real-time|failure-injection)")

latest_sha = {}
try:
    history = subprocess.run(
        ["git", "-C", str(root), "log", "-500", "--format=@@%H", "--name-only", "--", "scripts", "src", "app", "lib"],
        check=False, capture_output=True, text=True, timeout=10,
    ).stdout.splitlines()
    commit = ""
    for item in history:
        if item.startswith("@@"):
            commit = item[2:]
        elif item and commit:
            latest_sha.setdefault(item, commit)
except (OSError, subprocess.TimeoutExpired):
    pass

rows, stale, outside, production_cache = [], [], [], {}
for raw_path in test_files:
    path = pathlib.Path(raw_path)
    text = path.read_text(encoding="utf-8", errors="replace")
    refs = sorted(set(path_re.findall(text)))
    ref_exists = all((root / ref).exists() for ref in refs) if refs else True
    symbols = symbol_re.findall(text)
    production_text = ""
    for ref in refs:
        target = root / ref
        if target.is_file():
            if ref not in production_cache:
                production_cache[ref] = target.read_text(encoding="utf-8", errors="replace")
            production_text += production_cache[ref] + "\n"
    symbol_exists = all(re.search(rf"\b{re.escape(symbol)}\b", production_text) for symbol in symbols) if symbols else True
    existing_refs = [ref for ref in refs if (root / ref).exists()]
    sha = next((latest_sha[ref] for ref in existing_refs if ref in latest_sha), "untracked" if existing_refs else "none")
    spec = (spec_re.findall(text) or ["active"])[-1]
    stale_candidate = (not ref_exists) or (not symbol_exists) or spec in {"superseded", "removed"}
    if stale_candidate:
        stale.append(str(path))

    lines = text.splitlines()
    for number, line in enumerate(lines, 1):
        if not mock_re.search(line) or "test-health: mock-category" in line:
            continue
        nearby = "\n".join(lines[max(0, number - 3):min(len(lines), number + 2)])
        category = category_re.search(nearby)
        if not category:
            outside.append(f"{path}:{number}")

    rows.append((str(path), str(ref_exists).lower(), str(symbol_exists).lower(), sha, spec))

with catalog.open("w", encoding="utf-8") as handle:
    handle.write("test_file\treferenced_path_exists\tproduction_symbol_exists\tlast_target_change_sha\tspec_status\n")
    for row in rows:
        handle.write("\t".join(row) + "\n")
print(f"catalog: {catalog}")
print(f"stale candidates: {len(stale)}")
for item in stale:
    print(f"WARN: stale test candidate {item}")
print(f"outside mock categories: {len(outside)}")
for item in outside:
    print(f"WARN: mock outside allowed categories {item}")
if stale or outside:
    raise SystemExit(1)
PY
)" || asset_rc=$?
asset_rc="${asset_rc:-0}"
printf '%s\n' "$asset_out"
if (( asset_rc != 0 )); then
  alert=1
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
