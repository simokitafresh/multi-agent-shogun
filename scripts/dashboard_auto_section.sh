#!/usr/bin/env bash
# ============================================================
# dashboard_auto_section.sh
# ダッシュボードの機械的セクション(リアルタイム状況)を自動生成
#
# Usage: bash scripts/dashboard_auto_section.sh [--dry-run]
#   --dry-run: 標準出力に出力(dashboard.md未変更)
#
# Input:
#   queue/karo_snapshot.txt  → 忍者配備状況
#   queue/shogun_to_karo.yaml → パイプライン(active cmd一覧)
#   logs/gate_metrics.log    → 連勝数・CLEAR率・総cmd数
#   queue/tasks/*.yaml       → 各忍者の現タスク詳細
#   config/settings.yaml     → モデル名
#
# Output:
#   dashboard.md の DASHBOARD_AUTO_START ～ DASHBOARD_AUTO_END 間を上書き
#   マーカー外(家老記入セクション)は一切変更しない
#
# Exit:
#   0: 成功
#   1: 失敗
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Paths ───
DASHBOARD="$PROJECT_DIR/dashboard.md"
SNAPSHOT="$PROJECT_DIR/queue/karo_snapshot.txt"
STK="$PROJECT_DIR/queue/shogun_to_karo.yaml"
GATE_LOG="$PROJECT_DIR/logs/gate_metrics.log"
TASKS_DIR="$PROJECT_DIR/queue/tasks"
SETTINGS="$PROJECT_DIR/config/settings.yaml"
ARCHIVE_STK_DONE="$PROJECT_DIR/queue/archive/shogun_to_karo_done.yaml"
LESSON_EFFECT_STATUS_FILE="$PROJECT_DIR/queue/lesson_effectiveness_status.txt"
KM_JSON_CACHE="/tmp/dashboard_km_json_cache.txt"
KM_MODEL_CACHE="/tmp/dashboard_km_model_cache.txt"
KM_CACHE_LINES="/tmp/dashboard_km_cache_lines.txt"

MARKER_START="<!-- DASHBOARD_AUTO_START -->"
MARKER_END="<!-- DASHBOARD_AUTO_END -->"

TMPFILE=$(mktemp)
TMP_METRICS=$(mktemp)
TMP_PIPELINE=$(mktemp)
TMP_RESULTS=$(mktemp)
TMP_TITLES=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMP_METRICS" "$TMP_PIPELINE" "$TMP_RESULTS" "$TMP_TITLES"' EXIT

NOW=$(TZ=Asia/Tokyo date '+%H:%M')

ALL_NINJAS="sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru"

# ─── Helper: Japanese name ───
name_jp() {
    case "$1" in
        sasuke)   echo "佐助" ;;
        kirimaru) echo "霧丸" ;;
        hayate)   echo "疾風" ;;
        kagemaru) echo "影丸" ;;
        hanzo)    echo "半蔵" ;;
        saizo)    echo "才蔵" ;;
        kotaro)   echo "小太郎" ;;
        tobisaru) echo "飛猿" ;;
        *)        echo "$1" ;;
    esac
}

# ─── Helper: Get model for a ninja from settings.yaml ───
get_model() {
    local ninja="$1"
    local profiles_yaml="$PROJECT_DIR/config/cli_profiles.yaml"
    [[ ! -f "$SETTINGS" || ! -f "$profiles_yaml" ]] && { echo "unknown"; return; }
    python3 - "$SETTINGS" "$profiles_yaml" "$ninja" <<'PY'
import sys
import yaml

settings_path, profiles_path, ninja = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(settings_path, encoding="utf-8") as f:
        settings = yaml.safe_load(f) or {}
    with open(profiles_path, encoding="utf-8") as f:
        profiles_data = yaml.safe_load(f) or {}
except Exception:
    print("unknown")
    raise SystemExit(0)

cli = settings.get("cli", {}) if isinstance(settings, dict) else {}
agents = cli.get("agents", {}) if isinstance(cli, dict) else {}
agent_cfg = agents.get(ninja, {})
default_cli = str(cli.get("default", "claude") or "claude")
effort = str(settings.get("effort", "") or "").strip()
profiles = profiles_data.get("profiles", {}) if isinstance(profiles_data, dict) else {}

cli_type = default_cli
model_label = ""
has_explicit_model = False
if isinstance(agent_cfg, str):
    cli_type = str(agent_cfg or default_cli).strip() or default_cli
elif isinstance(agent_cfg, dict):
    cli_type = str(agent_cfg.get("type") or default_cli).strip() or default_cli
    model_label = " ".join(str(agent_cfg.get("model_name") or "").split())
    has_explicit_model = bool(model_label)

if not model_label:
    profile = profiles.get(cli_type, {}) if isinstance(profiles, dict) else {}
    model_label = " ".join(str(profile.get("display_name") or cli_type or "").split())

parts = [model_label]
if has_explicit_model and effort and effort not in model_label.split():
    parts.append(effort)

result = " ".join(part for part in parts if part).strip()
print(result or "unknown")
PY
}

# ─── Build cmd→ninjas mapping (from task YAMLs) ───
declare -A CMD_NINJAS=()
for n in $ALL_NINJAS; do
    tf="$TASKS_DIR/${n}.yaml"
    [[ ! -f "$tf" ]] && continue
    pcmd=$(grep -E '^\s*parent_cmd:' "$tf" | head -1 | sed 's/.*parent_cmd:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
    [[ -z "$pcmd" ]] && continue
    jp=$(name_jp "$n")
    if [[ -n "${CMD_NINJAS[$pcmd]:-}" ]]; then
        CMD_NINJAS[$pcmd]="${CMD_NINJAS[$pcmd]},${jp}"
    else
        CMD_NINJAS[$pcmd]="$jp"
    fi
done

# ─── Get idle list from snapshot ───
IDLE_LIST=""
[[ -f "$SNAPSHOT" ]] && IDLE_LIST=$(grep '^idle|' "$SNAPSHOT" | head -1 | cut -d'|' -f2 || true)

# ─── Calculate active ninjas from snapshot ───
ACTIVE_COUNT=0
ACTIVE_NAMES=""
for _an in $ALL_NINJAS; do
    if ! echo ",$IDLE_LIST," | grep -q ",${_an}," 2>/dev/null; then
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        _jp_an=$(name_jp "$_an")
        if [[ -n "$ACTIVE_NAMES" ]]; then
            ACTIVE_NAMES="${ACTIVE_NAMES}, ${_jp_an}"
        else
            ACTIVE_NAMES="$_jp_an"
        fi
    fi
done
[[ -z "$ACTIVE_NAMES" ]] && ACTIVE_NAMES="—"

# ─── Parse pipeline commands from STK (pre-compute for subshell access) ───
if [[ -f "$STK" ]] && grep -qE '^  -[[:space:]]*id:' "$STK" 2>/dev/null; then
    # Output tab-delimited: id\ttitle\tstatus
    # Only match command-level "- id:" (2-space indent), not nested AC entries (6+)
    awk '
        /^  -[[:space:]]*id:/ {
            if (cid != "") printf "%s\t%s\t%s\n", cid, tit, sta
            sub(/.*-[[:space:]]*id:[[:space:]]*/, "")
            gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
            cid=$0; tit=""; sta=""
        }
        /^    title:/ && cid!="" {
            sub(/.*title:[[:space:]]*/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if (length($0)>50) $0=substr($0,1,47)"..."
            tit=$0
        }
        /^    status:/ && cid!="" {
            sub(/.*status:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
            sta=$0
        }
        END { if (cid!="") printf "%s\t%s\t%s\n", cid, tit, sta }
    ' "$STK" > "$TMP_PIPELINE"
fi

# ─── Calculate gate metrics ───
STREAK=0
STREAK_START=""
STREAK_END=""
CLEAR_RATE="0.0%"
TOTAL_CMDS=0
LAST_GATE="—"

if [[ -f "$GATE_LOG" ]]; then
    # Cmd-latest dedup (exclude test cmds), sorted by timestamp
    awk -F'\t' '
        NF>=3 && $2 !~ /^cmd_test/ {
            cmd=$2; ts[cmd]=$1; st[cmd]=$3
        }
        END {
            for (c in st) printf "%s\t%s\t%s\n", ts[c], c, st[c]
        }
    ' "$GATE_LOG" | sort -t$'\t' -k1,1 > "$TMP_METRICS"

    TOTAL_CMDS=$(wc -l < "$TMP_METRICS" | tr -d ' ')
    CLEAR_COUNT=$(awk -F'\t' '$3=="CLEAR"{c++} END{print c+0}' "$TMP_METRICS")

    if [[ "$TOTAL_CMDS" -gt 0 ]]; then
        CLEAR_RATE=$(awk -v c="$CLEAR_COUNT" -v t="$TOTAL_CMDS" 'BEGIN{printf "%.1f%%", (c/t)*100}')
    fi

    # Streak: consecutive CLEARs from the end (L074: avoid ((var++)))
    STREAK=0
    STREAK_START=""
    STREAK_END=""
    while IFS=$'\t' read -r _ts _cmd result; do
        if [[ "$result" == "CLEAR" ]]; then
            if [[ $STREAK -eq 0 ]]; then
                STREAK_START="$_cmd"
            fi
            STREAK=$((STREAK + 1))
            STREAK_END="$_cmd"
        else
            STREAK=0
            STREAK_START=""
            STREAK_END=""
        fi
    done < "$TMP_METRICS"

    # Last GATE time
    last_line=$(tail -1 "$TMP_METRICS" || true)
    if [[ -n "$last_line" ]]; then
        _last_ts=$(echo "$last_line" | cut -f1)
        if [[ "$_last_ts" =~ T([0-9]{2}:[0-9]{2}) ]]; then
            LAST_GATE="${BASH_REMATCH[1]}"
        fi
    fi
fi

# Build CLEAR'd cmd set for pipeline filtering (must be outside subshell blocks)
declare -A CLEARED_CMDS=()
if [[ -s "$TMP_METRICS" ]]; then
    while IFS=$'\t' read -r _ts _cmd _result; do
        [[ "$_result" == "CLEAR" ]] && CLEARED_CMDS[$_cmd]=1
    done < "$TMP_METRICS"
fi

# ─── Knowledge metrics (cached — only re-run when gate_metrics.log changes) ───
KM_INJECT_RATE="—"
KM_REF_RATE="—"
KM_DELTA_PP="—"
KM_LESSON_EFFECT="—"
KM_LESSON_THRESHOLD="—"
KM_PROBLEM_LESSONS="—"
KM_PROJECT_ROWS=""
KM_KNOWLEDGE_MODEL_ROWS=""
KM_TOP_LESSON_ROWS=""
KM_BOTTOM_LESSON_ROWS=""
MODEL_SCOREBOARD_ROWS=""
CONTEXT_WARNINGS="$(bash "$SCRIPT_DIR/context_freshness_check.sh" --dashboard-warnings 2>/dev/null || true)"

_gate_signature="missing"
if [[ -f "$GATE_LOG" ]]; then
    _gate_signature=$(cksum "$GATE_LOG" | awk '{print $1 ":" $2}')
fi
_cached_signature=""
[[ -f "$KM_CACHE_LINES" ]] && _cached_signature=$(tr -d '[:space:]' < "$KM_CACHE_LINES" 2>/dev/null)

if [[ "$_gate_signature" != "$_cached_signature" ]] || [[ ! -f "$KM_JSON_CACHE" ]] || ! grep -q '^model_row=' "$KM_MODEL_CACHE" 2>/dev/null; then
    bash "$SCRIPT_DIR/knowledge_metrics.sh" --json --by-project --by-model > "$KM_JSON_CACHE" 2>/dev/null || true
    bash "$SCRIPT_DIR/model_analysis.sh" --summary > "$KM_MODEL_CACHE" 2>/dev/null || true
    echo "$_gate_signature" > "$KM_CACHE_LINES"
fi

# Parse JSON cache (inject_rate, ref_rate, normalized_delta.delta_pp + knowledge breakdown rows)
if [[ -f "$KM_JSON_CACHE" ]] && [[ -s "$KM_JSON_CACHE" ]]; then
    _km_parsed=$(python3 -c "
import json, sys
def fmt_pct(value):
    return f'{value:.1f}%' if value is not None else '—'
def safe_text(value):
    return str(value if value is not None else '—').replace('|', '/').replace('\n', ' ').strip() or '—'
try:
    data = json.load(sys.stdin)
    ir = data.get('inject_rate')
    rr = data.get('ref_rate')
    nd = data.get('normalized_delta', {})
    dp = nd.get('delta_pp')
    le = data.get('lesson_effectiveness')
    pl = data.get('problem_lessons', 0)
    ir_s = f'{ir:.1f}%' if ir is not None else '—'
    rr_s = f'{rr:.1f}%' if rr is not None else '—'
    dp_s = f'{dp:+.1f}pp' if dp is not None else '—'
    le_s = f'{le:.1f}%' if le is not None else '—'
    pl_s = str(pl) if pl is not None else '0'
    print(f'summary={ir_s}\t{rr_s}\t{dp_s}\t{le_s}\t{pl_s}')
    for row in data.get('by_project', []):
        print(f'project_row=| {safe_text(row.get(\"project\"))} | {fmt_pct(row.get(\"inject_rate\"))} | {fmt_pct(row.get(\"effectiveness_rate\"))} | {row.get(\"n\", \"—\")} |')
    for row in data.get('by_model', []):
        label = row.get('display_name') or row.get('model') or 'unknown'
        print(f'knowledge_model_row=| {safe_text(label)} | {fmt_pct(row.get(\"ref_rate\"))} | {fmt_pct(row.get(\"effectiveness_rate\"))} | {row.get(\"n\", \"—\")} |')
    for row in data.get('top_helpful', []):
        print(f'top_lesson_row=| {safe_text(row.get(\"id\"))} | {safe_text(row.get(\"project\"))} | {row.get(\"reference_count\", 0)} | {row.get(\"injection_count\", 0)} | {fmt_pct(row.get(\"effectiveness_rate\"))} |')
    for row in data.get('bottom_lessons', []):
        print(f'bottom_lesson_row=| {safe_text(row.get(\"id\"))} | {safe_text(row.get(\"project\"))} | {row.get(\"reference_count\", 0)} | {row.get(\"injection_count\", 0)} | {fmt_pct(row.get(\"effectiveness_rate\"))} |')
except Exception:
    print('summary=—\t—\t—\t—\t0')
" < "$KM_JSON_CACHE" 2>/dev/null || echo "summary=—	—	—	—	0")
    while IFS= read -r _line; do
        case "$_line" in
            summary=*)
                _payload=${_line#summary=}
                IFS=$'\t' read -r KM_INJECT_RATE KM_REF_RATE KM_DELTA_PP KM_LESSON_EFFECT KM_PROBLEM_LESSONS <<< "$_payload"
                ;;
            project_row=*)
                KM_PROJECT_ROWS="${KM_PROJECT_ROWS}${_line#project_row=}"$'\n'
                ;;
            knowledge_model_row=*)
                KM_KNOWLEDGE_MODEL_ROWS="${KM_KNOWLEDGE_MODEL_ROWS}${_line#knowledge_model_row=}"$'\n'
                ;;
            top_lesson_row=*)
                KM_TOP_LESSON_ROWS="${KM_TOP_LESSON_ROWS}${_line#top_lesson_row=}"$'\n'
                ;;
            bottom_lesson_row=*)
                KM_BOTTOM_LESSON_ROWS="${KM_BOTTOM_LESSON_ROWS}${_line#bottom_lesson_row=}"$'\n'
                ;;
        esac
    done <<< "$_km_parsed"
fi

# Parse model cache (model_analysis.sh --summary: model_row=<slug>\t<label>\t<clear>\t<impl>\t<trend>\t<n>)
if [[ -f "$KM_MODEL_CACHE" ]] && [[ -s "$KM_MODEL_CACHE" ]]; then
    while IFS= read -r _line; do
        [[ "$_line" == model_row=* ]] || continue
        _payload=${_line#model_row=}
        IFS=$'\t' read -r _slug _label _clear _impl _trend _n <<< "$_payload"
        [[ -z "$_label" ]] && continue
        _label=${_label//_/ }

        _clear_display="—"
        [[ -n "$_clear" && "$_clear" != "—" ]] && _clear_display="${_clear}%"

        _impl_display="—"
        [[ -n "$_impl" && "$_impl" != "—" ]] && _impl_display="${_impl}%"

        _trend_display="→"
        case "$_trend" in
            up) _trend_display="↑" ;;
            down) _trend_display="↓" ;;
        esac

        MODEL_SCOREBOARD_ROWS="${MODEL_SCOREBOARD_ROWS}| ${_label} | ${_clear_display} | ${_impl_display} | ${_trend_display} | ${_n:-—} |
"
    done < "$KM_MODEL_CACHE"
fi

# Parse lesson effectiveness threshold snapshot (from gate_lesson_health.sh)
if [[ -f "$LESSON_EFFECT_STATUS_FILE" ]] && [[ -s "$LESSON_EFFECT_STATUS_FILE" ]]; then
    _threshold_status=$(awk -F= '/^status=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_rate=$(awk -F= '/^rate=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_window=$(awk -F= '/^window_cmds=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_ref=$(awk -F= '/^referenced=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_inj=$(awk -F= '/^injected=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    if [[ -n "$_threshold_status" ]]; then
        case "$_threshold_status" in
            ALERT|WARN|OK)
                KM_LESSON_THRESHOLD="${_threshold_status} (${_threshold_rate}%, ${_threshold_ref}/${_threshold_inj}, ${_threshold_window}cmd)"
                ;;
            NODATA)
                KM_LESSON_THRESHOLD="NODATA"
                ;;
            *)
                KM_LESSON_THRESHOLD="${_threshold_status}"
                ;;
        esac
    fi
fi

# ─── Build cmd→title map (for 戦果 section) ───
# Priority: gate_metrics.log(9列目) > active STK > archive STK done
if [[ -f "$GATE_LOG" ]]; then
    awk -F'\t' '
        NF >= 9 {
            cmd = $2
            title = $9
            gsub(/\r/, "", title)
            gsub(/\t/, " ", title)
            if (title == "") {
                next
            }
            if (length(title) > 50) {
                title = substr(title, 1, 47) "..."
            }
            latest_title[cmd] = title  # 同一cmdは最後の行を採用
        }
        END {
            for (cmd in latest_title) {
                print cmd "\t" latest_title[cmd]
            }
        }
    ' "$GATE_LOG" >> "$TMP_TITLES"
fi
if [[ -s "$TMP_PIPELINE" ]]; then
    awk -F'\t' '{print $1"\t"$2}' "$TMP_PIPELINE" >> "$TMP_TITLES"
fi
if [[ -f "$ARCHIVE_STK_DONE" ]]; then
    awk '
        /^ *- id: cmd_/ {
            sub(/.*- id: */, ""); gsub(/["\047[:space:]]/, "")
            cid=$0; tit=""
        }
        /^    title:/ && cid!="" {
            sub(/.*title: */, "")
            gsub(/^["\047]|["\047]$/, "")
            if (length($0)>50) $0=substr($0,1,47)"..."
            tit=$0
            print cid"\t"tit
            cid=""
        }
    ' "$ARCHIVE_STK_DONE" >> "$TMP_TITLES"
fi

# ─── Get last 5 CLEAR cmds for battle results ───
if [[ -s "$TMP_METRICS" ]]; then
    awk -F'\t' '$3=="CLEAR"' "$TMP_METRICS" | tail -5 > "$TMP_RESULTS"
fi

# ═══════════════════════════════════════════════════════
# Generate auto section content
# ═══════════════════════════════════════════════════════
{
    echo "$MARKER_START"
    echo "## 📊 リアルタイム状況 (${NOW} 自動更新)"
    echo ""

    # ─── 忍者配備 ───
    echo "### 忍者配備"
    echo "| 忍者 | モデル | 状態 | cmd | 内容 |"
    echo "|------|--------|------|-----|------|"

    for ninja in $ALL_NINJAS; do
        jp=$(name_jp "$ninja")
        model=$(get_model "$ninja")

        # Status from idle list
        status="稼働中"
        if echo ",$IDLE_LIST," | grep -q ",${ninja}," 2>/dev/null; then
            status="idle"
        fi

        # Status from snapshot (done override)
        if [[ -f "$SNAPSHOT" ]]; then
            snap_line=$(grep "^ninja|${ninja}|" "$SNAPSHOT" | head -1 || true)
            if [[ -n "$snap_line" ]]; then
                snap_status=$(echo "$snap_line" | cut -d'|' -f4)
                [[ "$snap_status" == "done" ]] && status="done"
            fi
        fi

        # parent_cmd from task YAML
        cmd="—"
        tf="$TASKS_DIR/${ninja}.yaml"
        if [[ -f "$tf" ]]; then
            _cmd=$(grep -E '^\s*parent_cmd:' "$tf" | head -1 | sed 's/.*parent_cmd:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
            [[ -n "$_cmd" ]] && cmd="$_cmd"
        fi

        # cmd title from TMP_TITLES (50 char limit already applied)
        title="—"
        if [[ "$cmd" != "—" ]] && [[ -s "$TMP_TITLES" ]]; then
            _title=$(grep "^${cmd}"$'\t' "$TMP_TITLES" | head -1 | cut -f2 || true)
            [[ -n "$_title" ]] && title="$_title"
        fi

        echo "| ${jp} | ${model} | ${status} | ${cmd} | ${title} |"
    done

    echo ""

    # ─── CI Status (cmd_715) ───
    _ci_status=$(bash "$SCRIPT_DIR/ci_status_check.sh" --status 2>/dev/null || echo "UNKNOWN")
    case "$_ci_status" in
        GREEN)
            echo "### CI Status"
            echo "CI GREEN"
            echo ""
            ;;
        RED:*)
            _ci_run_id=$(echo "$_ci_status" | cut -d: -f2)
            _ci_failed=$(echo "$_ci_status" | cut -d: -f3-)
            echo "### CI Status"
            echo "**CI RED: run ${_ci_run_id} — ${_ci_failed}**"
            echo ""
            ;;
        *)
            # UNKNOWN — skip section
            ;;
    esac

    # ─── パイプライン ───
    echo "### パイプライン"

    if [[ ! -s "$TMP_PIPELINE" ]]; then
        echo "パイプライン空 — 次cmd待ち"
    else
        echo "| cmd | タイトル | status | 配備忍者 |"
        echo "|-----|---------|--------|----------|"

        shown=0
        while IFS=$'\t' read -r cid tit sta; do
            # Skip completed commands and already GATE CLEAR'd commands.
            [[ "$sta" == "completed" ]] && continue
            [[ -n "${CLEARED_CMDS[$cid]:-}" ]] && continue
            ninjas="${CMD_NINJAS[$cid]:-—}"
            echo "| ${cid} | ${tit} | ${sta} | ${ninjas} |"
            shown=$((shown + 1))
        done < "$TMP_PIPELINE"

        if [[ $shown -eq 0 ]]; then
            echo "パイプライン空 — 次cmd待ち"
        fi
    fi

    echo ""

    # ─── 戦況メトリクス ───
    echo "### 戦況メトリクス"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| cmd完了(GATE CLEAR) | ${CLEAR_COUNT:-0}/${TOTAL_CMDS} |"
    echo "| 稼働忍者 | ${ACTIVE_COUNT}/8 (${ACTIVE_NAMES}) |"
    if [[ -n "$STREAK_START" ]] && [[ -n "$STREAK_END" ]]; then
        echo "| 連勝(CLEAR streak) | ${STREAK} (${STREAK_START}〜${STREAK_END}) |"
    else
        echo "| 連勝(CLEAR streak) | ${STREAK} |"
    fi

    echo ""

    # ─── モデル別スコアボード ───
    echo "### モデル別スコアボード"
    echo "| モデル | CLEAR率 | impl率 | 傾向 | N |"
    echo "|--------|---------|--------|------|---|"
    if [[ -n "$MODEL_SCOREBOARD_ROWS" ]]; then
        printf "%s" "$MODEL_SCOREBOARD_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""

    # ─── 知識サイクル健全度 ───
    echo "### 知識サイクル健全度"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| 教訓注入率 | ${KM_INJECT_RATE} |"
    echo "| 教訓効果率 | ${KM_LESSON_EFFECT} |"
    echo "| 効果率閾値 | ${KM_LESSON_THRESHOLD} |"
    echo "| 問題教訓 | ${KM_PROBLEM_LESSONS}件 |"

    echo ""
    echo "#### PJ別"
    echo "| PJ | 注入率 | 効果率 | N |"
    echo "|----|--------|--------|---|"
    if [[ -n "$KM_PROJECT_ROWS" ]]; then
        printf "%s" "$KM_PROJECT_ROWS"
    else
        echo "| — | — | — | — |"
    fi

    echo ""
    echo "#### モデル別"
    echo "| モデル | 参照率 | 効果率 | N |"
    echo "|--------|--------|--------|---|"
    if [[ -n "$KM_KNOWLEDGE_MODEL_ROWS" ]]; then
        printf "%s" "$KM_KNOWLEDGE_MODEL_ROWS"
    else
        echo "| — | — | — | — |"
    fi

    echo ""
    echo "#### 教訓ランキング"
    echo "Top 5 有効教訓"
    echo "| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |"
    echo "|------|----|----------|----------|--------|"
    if [[ -n "$KM_TOP_LESSON_ROWS" ]]; then
        printf "%s" "$KM_TOP_LESSON_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""
    echo "Bottom 5 低効果教訓"
    echo "| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |"
    echo "|------|----|----------|----------|--------|"
    if [[ -n "$KM_BOTTOM_LESSON_ROWS" ]]; then
        printf "%s" "$KM_BOTTOM_LESSON_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""

    # ─── Context freshness warnings (cmd_778 A-layer) ───
    echo "### Context鮮度警告"
    if [[ -n "$CONTEXT_WARNINGS" ]]; then
        printf "%s\n" "$CONTEXT_WARNINGS"
    else
        echo "なし"
    fi

    echo ""

    # ─── 戦果（直近5件） ───
    echo "### 戦果（直近5件）"
    if [[ -s "$TMP_RESULTS" ]]; then
        echo "| cmd | 内容 | 結果 | 完了日時 |"
        echo "|-----|------|------|----------|"
        # Reverse order (newest first)
        tac "$TMP_RESULTS" | while IFS=$'\t' read -r _ts _cmd _result; do
            # Look up title
            _title=$(grep "^${_cmd}"$'\t' "$TMP_TITLES" | head -1 | cut -f2 || true)
            [[ -z "$_title" ]] && _title="—"
            # Format timestamp (2026-02-27T12:26:56 → 02-27 12:26)
            _date="—"
            if [[ "$_ts" =~ ([0-9]{4}-([0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2})) ]]; then
                _date="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
            fi
            echo "| ${_cmd} | ${_title} | GATE CLEAR | ${_date} |"
        done
    else
        echo "(戦果データなし)"
    fi

    echo ""
    echo "> 過去の戦果は archive/dashboard/ を参照"

    echo "$MARKER_END"
} > "$TMPFILE"

# ═══════════════════════════════════════════════════════
# Output or update dashboard.md
# ═══════════════════════════════════════════════════════
if [[ "$DRY_RUN" == true ]]; then
    cat "$TMPFILE"
    exit 0
fi

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

if ! grep -qF "$MARKER_START" "$DASHBOARD"; then
    echo "ERROR: $MARKER_START not found in dashboard.md" >&2
    exit 1
fi

if ! grep -qF "$MARKER_END" "$DASHBOARD"; then
    echo "ERROR: $MARKER_END not found in dashboard.md" >&2
    exit 1
fi

# Replace content between markers (inclusive)
{
    # Lines before start marker
    awk -v m="$MARKER_START" '$0==m{exit} {print}' "$DASHBOARD"
    # New content (includes markers)
    cat "$TMPFILE"
    # Lines after end marker
    awk -v m="$MARKER_END" 'f{print} $0==m{f=1}' "$DASHBOARD"
} > "${DASHBOARD}.tmp"

mv "${DASHBOARD}.tmp" "$DASHBOARD"
echo "OK: dashboard.md auto section updated (${NOW})"
