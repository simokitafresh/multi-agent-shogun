#!/usr/bin/env bash
# gate_three_layer_health.sh — Three-layer memory cache capacity and tmp hygiene gate.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Round8 lane #0': complete entrypoint wall-clock telemetry.
THREE_LAYER_HEALTH_TOTAL_T0_US="${EPOCHREALTIME/./}"
THREE_LAYER_HEALTH_TOTAL_T0_US="${THREE_LAYER_HEALTH_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$repo_root}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
if [[ -f "$repo_root/scripts/lib/defense_overhead_writer.sh" ]]; then
    source "$repo_root/scripts/lib/defense_overhead_writer.sh"
else
    # Lightweight gate fixtures may intentionally omit optional telemetry
    # dependencies; preserve the gate's original judgement contract there.
    defense_overhead_write_async() { return 0; }
fi
THREE_LAYER_HEALTH_TOTAL_RECORDED=0
three_layer_health_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${THREE_LAYER_HEALTH_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    THREE_LAYER_HEALTH_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - THREE_LAYER_HEALTH_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    # Keep the existing source=three_layer_health cache-gap row namespace
    # unchanged; the entrypoint total has its own source namespace so legacy
    # consumers that count cache-gap observations remain byte-compatible.
    defense_overhead_write_async three_layer_health_total three_layer_health_total "$wall_ms" "$verdict" \
        "three-layer-health-${BASHPID}-${THREE_LAYER_HEALTH_TOTAL_T0_US}" || true
}
three_layer_health_total_on_exit() { local rc=$?; three_layer_health_record_total "$rc"; return "$rc"; }
trap three_layer_health_total_on_exit EXIT
db_path="${SHOGUN_MEMORY_DB:-$repo_root/data/multi_agent_shogun_memory.db}"
warn_bytes="${SHOGUN_THREE_LAYER_CACHE_WARN_BYTES:-5368709120}"
cleanup_script="${SHOGUN_THREE_LAYER_CLEANUP_SCRIPT:-$repo_root/scripts/cleanup_three_layer_tmp.sh}"
overall="PASS"

if [ -f "$repo_root/scripts/lib/memory_db_cache.sh" ]; then
    # shellcheck source=scripts/lib/memory_db_cache.sh
    source "$repo_root/scripts/lib/memory_db_cache.sh"
fi

# Resolve cache_path in bash (mirrors memory_db_live_insert.memory_db_cache_path()).
# Eliminates the first Python subprocess call. Uses bash parameter expansion
# (##*/ for basename, %/* for dirname) to avoid subprocess forks.
if [ -n "${SHOGUN_MEMORY_DB_CACHE_PATH:-}" ]; then
    cache_path="${SHOGUN_MEMORY_DB_CACHE_PATH}"
    cache_dir="${cache_path%/*}"
else
    cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
    _repo_key="${repo_root//[^A-Za-z0-9_.-]/_}"
    cache_path="${cache_dir}/${_repo_key}_${db_path##*/}"
fi

# cache追随チェックの判定値を既存台帳(logs/defense_overhead.jsonl)へ1行残す。
# 表示だけでは startup gate の出力が流れて消え、過去の値を後から追えない。
# 記録は観測専用であり、gateの判定・出力・exit codeには一切影響させない
# (書込み失敗もgateを落とさない。標準出力へは何も足さない)。
record_cache_rowid_gap() {
    local cache_rowid="$1" source_rowid="$2" gap="$3" verdict="$4"
    local writer="$repo_root/scripts/lib/defense_overhead_writer.sh"
    [ -f "$writer" ] || return 0
    # shellcheck source=scripts/lib/defense_overhead_writer.sh
    source "$writer" 2>/dev/null || return 0
    local stamp event_id ledger_verdict
    printf -v stamp '%(%s)T' -1
    # 共有writerの5フィールド契約(source/check_id/wall_ms/verdict/event_id)は
    # 変えずに、値は event_id へ詰める。event_idの許容文字は [A-Za-z0-9_.:-] の
    # ため区切りは '-' を使う。既存の grep + json parse がそのまま使える。
    # writerはevent_id重複を排除する。秒だけだと同一秒に走った別プロセスの
    # 観測が1件へ潰れる(実測: 2並列で1行しか残らなかった)ため、PIDも含めて
    # 「1実行=1行」を厳密にする。
    event_id="cache_rowid_gap:cache-${cache_rowid}:source-${source_rowid}:gap-${gap}:warn-${rowid_gap_warn}:${stamp}-$$"
    case "$verdict" in
        PASS|WARN) ledger_verdict="$verdict" ;;
        # 欠測は WARN として残す。行を書かなければ『測ってgap=0』と
        # 『測れなかった』が区別できなくなる。
        *) ledger_verdict="WARN" ;;
    esac
    defense_overhead_write three_layer_health cache_rowid_gap 0 \
        "$ledger_verdict" "$event_id" >/dev/null 2>&1 || true
    return 0
}

echo "=== three-layer memory health ==="
echo "db_path=$db_path"
echo "cache_path=${cache_path:-unknown}"

query_db="${cache_path:-}"

echo "■ events.state分布"
if [ -f "$query_db" ]; then
    if ! python3 - "$query_db" <<'PY'; then
import sqlite3
import sys

db_path = sys.argv[1]

warn = False

def has_column(conn, table, column):
    return any(row[1] == column for row in conn.execute(f"PRAGMA table_info({table})"))

def has_table(conn, table):
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None

def scalar(conn, query, params=()):
    value = conn.execute(query, params).fetchone()[0]
    return int(value or 0)

conn = sqlite3.connect(f"file:{db_path}?mode=ro&immutable=1", uri=True)
try:
    has_events = has_table(conn, "events")
    if not has_events:
        raise RuntimeError("events table not found")

    has_state = has_column(conn, "events", "state")
    has_raw_content = has_column(conn, "events", "raw_content")

    if has_state:
        state_rows = list(
            conn.execute(
                """
                SELECT COALESCE(NULLIF(TRIM(state), ''), 'raw') AS state_name, COUNT(*)
                FROM events
                GROUP BY state_name
                ORDER BY COUNT(*) DESC, state_name
                """
            )
        )
    else:
        state_rows = [("state_column_missing", 0)]
    for state_name, count in state_rows:
        print(f"  state分布 {state_name}: {count}")

    if has_raw_content:
        total, filled = conn.execute(
            """
            SELECT COUNT(*),
                   SUM(CASE WHEN raw_content IS NOT NULL AND TRIM(raw_content) != '' THEN 1 ELSE 0 END)
            FROM events
            """
        ).fetchone()
        filled = filled or 0
        rate = (filled * 100.0 / total) if total else 0.0
        print(f"  raw_content充填率: {filled}/{total} ({rate:.1f}%)")
    else:
        print("  raw_content充填率: raw_content column missing")

    if has_state:
        contradiction_candidates = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state = 'contradiction_candidate'"
        ).fetchone()[0]
        promote_candidates = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state = 'obsidian_candidate'"
        ).fetchone()[0]
    else:
        contradiction_candidates = 0
        promote_candidates = 0
    print(f"  contradiction候補件数: {contradiction_candidates}")
    print(f"  promote昇格候補件数: {promote_candidates}")

    print("■ 三層記憶 使用計測")
    if has_table(conn, "search_logs"):
        search_logs_7d = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM search_logs
            WHERE COALESCE(ts, created_at, '') >= datetime('now', '-7 days')
            """,
        )
        print(f"  search_logs検索件数(直近7日): {search_logs_7d}")
        if search_logs_7d == 0:
            print("WARN: search_logs検索件数が0。三層記憶検索が使われていない可能性あり。")
            warn = True
    else:
        print("WARN: search_logs table missing")
        warn = True

    if has_state:
        state_transition_count = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE COALESCE(NULLIF(TRIM(state), ''), 'raw') != 'raw'
            """,
        )
        candidate_count = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE COALESCE(state, '') LIKE '%candidate'
            """,
        )
    else:
        state_transition_count = 0
        candidate_count = 0
    print(f"  state遷移件数(state!=raw): {state_transition_count}")
    if state_transition_count == 0:
        print("WARN: state遷移件数が0。想起制御/候補化が使われていない可能性あり。")
        warn = True

    if has_raw_content:
        raw_content_saved = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE raw_content IS NOT NULL AND TRIM(raw_content) != ''
            """,
        )
    else:
        raw_content_saved = 0
    print(f"  raw_content原文保存件数: {raw_content_saved}")
    if raw_content_saved == 0:
        print("WARN: raw_content原文保存件数が0。原文保存経路が使われていない可能性あり。")
        warn = True

    print(f"  candidate候補生成件数: {candidate_count}")
    if candidate_count == 0 and state_transition_count == 0:
        print("WARN: candidate候補生成件数が0かつstate遷移件数が0。矛盾/重複/Obsidian候補生成が使われていない可能性あり。")
        warn = True

    if warn:
        sys.exit(2)
finally:
    conn.close()
PY
        overall="WARN"
        # The cache freshness predicate intentionally uses cheap metadata only.
        # A real query failure is the authoritative corruption signal: recover
        # asynchronously so this run remains WARN and only a later run can PASS.
        if [ "$query_db" = "$cache_path" ] && [ -f "$db_path" ] \
            && declare -F force_refresh_memory_db_cache_async >/dev/null; then
            echo "WARN: cache query failed; scheduling single-flight atomic refresh"
            force_refresh_memory_db_cache_async "$repo_root" "$db_path" "$cache_path"
        fi
    fi
else
    echo "WARN: 三層記憶DBが存在しない: $query_db"
    overall="WARN"
fi

echo "■ cache追随チェック(cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726)"
# 疾風の偵察(cmd_karo_recon_memory_cache_mtime_freshness_20260726)実証: STATUS
# PASSを表示中にmemory_db_query.shの検索が0件を返す(A8=沈黙の検査)。cacheが
# 本体に追随しているかをrowid水位で直接検査する。gap>0自体は正常
# (非同期cache再生成の合間に生じる/delta-searchが自動で埋める)なので、
# 実測の定常gap(数件程度)を大きく超える異常な乖離のみWARNとする。
rowid_gap_warn="${SHOGUN_THREE_LAYER_CACHE_ROWID_GAP_WARN:-1000}"
if [ -f "$query_db" ] && [ -f "$db_path" ]; then
    cache_max_rowid="$(python3 - "$query_db" <<'PY' 2>/dev/null || true
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    row = conn.execute("SELECT COALESCE(MAX(rowid), 0) FROM events").fetchone()
print(int(row[0]) if row else 0)
PY
)"
    # 本体は9P越しの可能性があるため、高負荷時のstall防止にtimeoutで防御する。
    source_max_rowid="$(timeout 2 python3 - "$db_path" <<'PY' 2>/dev/null || true
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    row = conn.execute("SELECT COALESCE(MAX(rowid), 0) FROM events").fetchone()
print(int(row[0]) if row else 0)
PY
)"
    if [[ "$cache_max_rowid" =~ ^[0-9]+$ ]] && [[ "$source_max_rowid" =~ ^[0-9]+$ ]]; then
        rowid_gap=$((source_max_rowid - cache_max_rowid))
        [ "$rowid_gap" -lt 0 ] && rowid_gap=0
        echo "cache_max_rowid=$cache_max_rowid source_max_rowid=$source_max_rowid gap=$rowid_gap warn_gap=$rowid_gap_warn"
        if [ "$rowid_gap" -gt "$rowid_gap_warn" ]; then
            echo "WARN: cacheが本体に追随していない(gap=${rowid_gap}件 > 閾値${rowid_gap_warn}件)。async refresh/delta-search機構を確認せよ。"
            overall="WARN"
            _rowid_gap_verdict="WARN"
        else
            echo "OK: cacheは本体に追随している(gap=${rowid_gap}件)"
            _rowid_gap_verdict="PASS"
        fi
        # 表示は流れて消えるため、判定と同じ値を既存台帳へ1行だけ残す。
        # 新ledgerは作らない(車輪の再発明防止)。event_idへ値を詰めるのは、
        # 共有writerの5フィールド契約を変えずに済ませるため(writerはscope外)。
        record_cache_rowid_gap "$cache_max_rowid" "$source_max_rowid" "$rowid_gap" "$_rowid_gap_verdict"
    else
        # 9P高負荷時のtimeout等でrowid水位を取得できないケース。実検索経路
        # (memory_db_query.sh)は自前でcacheのみへフォールバックし利用者へは
        # 影響しないため、この診断プローブの失敗単独をWARNにしない(AC3:
        # 9p高負荷時のフォールバック防御を診断側でも壊さない)。
        echo "INFO: cache/本体のrowid水位を取得できない(9p timeout等)。追随状態を判定不能のためskip"
        # 欠測は明示的に記録する。行を書かないと『測ってgap=0だった』と
        # 『測れなかった』が後から区別できない(沈黙は解釈不能)。
        record_cache_rowid_gap na na na UNMEASURED
    fi
else
    # sourceまたはcacheが存在しない場合(初回起動前・cache未生成等)は
    # 追随チェックの対象外。三層記憶DB不在そのものは上のevents.state分布
    # セクションが別途検出する。
    echo "INFO: cache/本体のいずれかが不在のため追随チェックをskip(query_db=$query_db db_path=$db_path)"
    # 不在によるskipも欠測として残す。ここで行を書かないと、台帳上は
    # 『gapが記録された実行』と『そもそも測れなかった実行』の区別がつかず、
    # 記録が無いことを「正常だった」と読み違える余地が残る。
    record_cache_rowid_gap na na na UNMEASURED
fi

echo "■ cache容量チェック"
if [ -d "$cache_dir" ]; then
    # WSL2ではdu -sbが過大報告する(sparse files等)。ls -lベースで実ファイルサイズ合計を取得
    cache_bytes="$(ls -lR "$cache_dir" 2>/dev/null | awk '/^-/{sum+=$5} END{print sum+0}')"
else
    cache_bytes=0
fi
echo "cache_dir=$cache_dir bytes=$cache_bytes warn_bytes=$warn_bytes"
# initial_scan is diagnostic only.  It walks the directory with a different
# file-selection implementation from cleanup_three_layer_tmp.sh and therefore
# cannot be the capacity verdict's denominator.
echo "cache_capacity_measured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ) observed_bytes=$cache_bytes source=initial_scan"

echo "■ tmp残骸cleanup dry-run"
if [ -x "$cleanup_script" ]; then
    cleanup_measured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if cleanup_output="$(bash "$cleanup_script" --dry-run --cache-dir "$cache_dir" --max-bytes "$warn_bytes" 2>&1)"; then
        printf '%s\n' "$cleanup_output"
        cleanup_total_bytes="$(
            printf '%s\n' "$cleanup_output" |
                awk '/mode=dry-run/ { for (i=1; i<=NF; i++) if ($i ~ /^total_bytes=/) { sub(/^total_bytes=/, "", $i); print $i; exit } }'
        )"
        case "$cleanup_total_bytes" in
            ''|*[!0-9]*)
                echo "BLOCK: cleanup dry-runのtotal_bytesを解釈できない。容量判定の母数を確定できない"
                overall="BLOCK"
                ;;
            *)
                echo "cleanup_capacity_measured_at=$cleanup_measured_at adopted_bytes=$cleanup_total_bytes source=cleanup_dry_run"
                if [ "$cleanup_total_bytes" -gt "$warn_bytes" ]; then
                    cleanup_candidates="$(
                        printf '%s\n' "$cleanup_output" |
                            awk '/mode=dry-run/ { for (i=1; i<=NF; i++) if ($i ~ /^candidates=/) { sub(/^candidates=/, "", $i); print $i; exit } }'
                    )"
                    case "$cleanup_candidates" in
                        ''|*[!0-9]*)
                            echo "BLOCK: cache容量超過だがcleanup dry-runのcandidatesを解釈できない。回収経路を証明できない"
                            overall="BLOCK"
                            ;;
                        0)
                            echo "BLOCK: cache容量が閾値超過(total_bytes=$cleanup_total_bytes > max_bytes=$warn_bytes)かつ回収候補0件。external_dependency=protected_or_nonreclaimable"
                            echo "BLOCK: 回収不能をWARNで継続せず、保護対象/外部依存の解消後に再実行せよ"
                            overall="BLOCK"
                            ;;
                        *)
                            echo "BLOCK: cache容量が閾値超過(total_bytes=$cleanup_total_bytes > max_bytes=$warn_bytes)、回収候補=$cleanup_candidates"
                            printf 'RECOVERY: bash %q --apply --cache-dir %q --max-bytes %q\n' \
                                "$cleanup_script" "$cache_dir" "$warn_bytes"
                            overall="BLOCK"
                            ;;
                    esac
                fi
                ;;
        esac
    else
        cleanup_status=$?
        printf '%s\n' "$cleanup_output"
        echo "BLOCK: cleanup dry-run failed status=$cleanup_status。容量判定と回収経路を証明できない"
        overall="BLOCK"
    fi
else
    echo "BLOCK: cleanup script not executable: $cleanup_script。容量判定と回収経路を証明できない"
    overall="BLOCK"
fi

echo "■ 三層連鎖(memory_db_knowledge_write.sh Layer2/3)失敗検知"
chain_log="${THREE_LAYER_CHAIN_LOG:-$repo_root/logs/three_layer_chain_async.log}"
chain_state_dir="${THREE_LAYER_CHAIN_STATE_DIR:-$repo_root/logs/three_layer_chain_state}"
pending_stale_seconds="${THREE_LAYER_CHAIN_PENDING_STALE_SECONDS:-120}"
if [ -f "$chain_log" ]; then
    chain_fail_count="$(
        awk '
            function event_id(line,    tmp) {
                tmp = line
                if (tmp ~ /event=[^[:space:]]+/) {
                    sub(/^.*event=/, "", tmp)
                    sub(/[[:space:]].*$/, "", tmp)
                    return tmp
                }
                return "line:" NR
            }
            / ERROR / { unresolved[event_id($0)] = 1 }
            / OK / { delete unresolved[event_id($0)] }
            END {
                count = 0
                for (id in unresolved) count++
                print count + 0
            }
        ' "$chain_log" 2>/dev/null || true
    )"
    chain_fail_count="${chain_fail_count:-0}"
    echo "chain_log=$chain_log 未貫通件数=$chain_fail_count"
    if [ "$chain_fail_count" -gt 0 ]; then
        echo "WARN: 三層連鎖Layer2/3の未貫通件数=$chain_fail_count。$chain_log を確認せよ。"
        [ "$overall" = "BLOCK" ] || overall="WARN"
    else
        echo "OK: 三層連鎖失敗ゼロ"
    fi
else
    echo "chain_log=$chain_log (未生成。三層連鎖の実行履歴なし)"
fi

stale_pending=0
failed_results=0
now_epoch="$(date +%s)"
if [ -d "$chain_state_dir" ]; then
    while IFS= read -r pending; do
        [ -n "$pending" ] || continue
        mtime="$(stat -c %Y "$pending" 2>/dev/null || echo "$now_epoch")"
        if [ $((now_epoch - mtime)) -gt "$pending_stale_seconds" ]; then
            stale_pending=$((stale_pending + 1))
        fi
    done < <(find "$chain_state_dir" -maxdepth 1 -type f -name '*.pending.json' -print 2>/dev/null)
    while IFS= read -r result; do
        [ -n "$result" ] || continue
        grep -q '^state=FAIL$' "$result" && failed_results=$((failed_results + 1))
    done < <(find "$chain_state_dir" -maxdepth 1 -type f -name '*.result' -print 2>/dev/null)
fi
echo "chain_state_dir=$chain_state_dir stale_pending=$stale_pending failed_results=$failed_results"
if [ "$stale_pending" -gt 0 ] || [ "$failed_results" -gt 0 ]; then
    echo "WARN: durable三層連鎖の未完了/失敗を検出。pending/resultを確認せよ。"
    [ "$overall" = "BLOCK" ] || overall="WARN"
else
    echo "OK: durable三層連鎖の未完了/失敗ゼロ"
fi

echo "STATUS: $overall"
[ "$overall" = "PASS" ] && exit 0
exit 2
