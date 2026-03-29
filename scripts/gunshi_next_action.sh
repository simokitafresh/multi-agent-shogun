#!/usr/bin/env bash
# gunshi_next_action.sh — 軍師自走サイクル推薦エンジン
# Phase 4: 意志依存排除。Phase 7: 自走。Phase 8: 利他。
# レビュー完了後・idle時に実行し、次の最善行動を推薦する。
# 止まるな。考えて行動、考えて行動。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INBOX="$REPO_ROOT/queue/inbox/gunshi.yaml"
WA_LOG="$REPO_ROOT/logs/karo_workarounds.yaml"
REVIEW_LOG="$REPO_ROOT/logs/gunshi_review_log.yaml"
SNAPSHOT="$REPO_ROOT/queue/karo_snapshot.txt"
# gate_fire_log path for P6 self-study reference
_FIRE_LOG="$REPO_ROOT/logs/gate_fire_log.yaml"
INSIGHTS="$REPO_ROOT/queue/insights.yaml"

echo "=== 軍師サイクル推薦 $(date +%H:%M:%S) ==="
echo ""

# --- CTX Budget Check (cmd_1501) ---
CTX_HIGH=false
# shellcheck source=lib/ctx_utils.sh
source "$REPO_ROOT/scripts/lib/ctx_utils.sh"
CTX_PCT=$(get_ctx_pct "${TMUX_PANE:-}" "gunshi" 2>/dev/null || echo 50)
echo "CTX: ${CTX_PCT}%"
if (( CTX_PCT > 70 )); then
    echo "⚠ CTX ${CTX_PCT}% > 70% — idle観察スキップ。/clear推奨"
    CTX_HIGH=true
fi
echo ""

# --- Priority 1: inbox未読 ---
unread=0
if [[ -f "$INBOX" ]]; then
    unread=$(grep -c 'read: false' "$INBOX" 2>/dev/null || true)
fi
if (( unread > 0 )); then
    echo "★★★ P1: inbox未読 ${unread}件 → 即時処理せよ"
    echo "    Read queue/inbox/gunshi.yaml"
    echo ""
fi

# --- Priority 2: 稼働中cmdの報告待ち（利他準備） ---
active_cmds=$(grep -E '^ninja\|.*\|(assigned|in_progress)' "$SNAPSHOT" 2>/dev/null || true)
if [[ -n "$active_cmds" ]]; then
    echo "■ P2: 稼働中cmd — 報告レビュー準備"
    while IFS='|' read -r _ ninja task status _ _; do
        echo "    $ninja: $task ($status) → 関連コードを事前学習し、報告レビューの精度を上げよ"
    done <<< "$active_cmds"
    echo ""
fi

# --- Priority 2.5: 直近レビュー対象のcommit状態チェック（SG2自動化） ---
# Phase 4: 意志依存排除。commit確認を手順ではなく環境に埋め込む
latest_reports=$(find "$REPO_ROOT/queue/reports" -name '*.yaml' -mmin -60 2>/dev/null || true)
if [[ -n "$latest_reports" ]]; then
    commit_issues=0
    while IFS= read -r rpt; do
        rpt_project=$(grep -m1 'project:' "$rpt" 2>/dev/null | sed 's/.*project: *//' | tr -d "'" || true)
        if [[ "$rpt_project" == "dm-signal" ]]; then
            proj_dir="/mnt/c/Python_app/DM-signal"
        else
            continue
        fi
        # files_modifiedからパスを抽出
        fm_paths=$(grep -A1 'path:' "$rpt" 2>/dev/null | grep 'path:' | sed 's/.*path: *//' | tr -d "'" || true)
        if [[ -n "$fm_paths" ]]; then
            while IFS= read -r fpath; do
                if [[ -n "$fpath" ]] && cd "$proj_dir" 2>/dev/null; then
                    gst=$(git status --porcelain -- "$fpath" 2>/dev/null || true)
                    if [[ "$gst" == "??"* ]]; then
                        if (( commit_issues == 0 )); then
                            echo "■ P2.5: ★commit未完了ファイル検出（SG2自動チェック）"
                        fi
                        commit_issues=$((commit_issues + 1))
                        echo "    ?? $fpath ($(basename "$rpt"))"
                    fi
                    cd "$REPO_ROOT"
                fi
            done <<< "$fm_paths"
        fi
    done <<< "$latest_reports"
    if (( commit_issues > 0 )); then
        echo "    → 計${commit_issues}ファイル未commit。レビュー時に指摘必須"
        echo ""
    fi
fi

# --- Priority 3: workaround新規パターン検出 ---
if [[ -f "$WA_LOG" ]]; then
    recent_wa=$(tail -20 "$WA_LOG" | grep -c 'workaround: true' 2>/dev/null || true)
    if (( recent_wa > 0 )); then
        echo "■ P3: 直近workaround ${recent_wa}件(直近20行)"
        echo "    → パターン分析し、レビュー観点に還流できないか検討せよ"
        echo ""
    fi
fi

# --- Priority 4: GATE未確認エントリ ---
gate_null=$(grep -c 'gate_result: null' "$REVIEW_LOG" 2>/dev/null || true)
if (( gate_null > 5 )); then
    echo "■ P4: GATE未確認 ${gate_null}件"
    echo "    → karo_workaroundsと照合しgate_result更新せよ"
    echo ""
fi

# --- Priority 5: pending GP ---
pending_gp=$(grep -c '| pending' "$REVIEW_LOG" 2>/dev/null || true)
if (( pending_gp > 0 )); then
    gp_detail=$(grep '| pending' "$REVIEW_LOG" | head -3)
    echo "■ P5: pending GP ${pending_gp}件"
    echo "$gp_detail" | while IFS= read -r line; do
        echo "    $line"
    done
    echo ""
fi

# --- Priority 5.5: insightキュー消費 (cmd_1501) ---
pending_insights=0
if [[ -f "$INSIGHTS" ]]; then
    pending_insights=$(grep -c 'status: pending' "$INSIGHTS" 2>/dev/null || true)
fi
if (( pending_insights > 0 )); then
    echo "■ P5.5: insightキュー pending ${pending_insights}件"
    echo "    → queue/insights.yamlのpendingエントリを分析し、解決 or 行動せよ"
    echo ""
fi

# --- Priority 6: 自己研鑽サイクル（動的生成） ---
if [[ "$CTX_HIGH" == "true" ]]; then
    echo "■ P6: CTX ${CTX_PCT}% > 70% のためidle観察スキップ。/clearを実行せよ"
    echo ""
else

p6_items=()

# (a) 教訓効果率: lesson_impact.tsvが古い or 未存在なら推薦
if [[ -f "$REPO_ROOT/logs/lesson_impact.tsv" ]]; then
    impact_age=$(( ($(date +%s) - $(stat -c %Y "$REPO_ROOT/logs/lesson_impact.tsv" 2>/dev/null || echo 0)) / 86400 ))
    if (( impact_age > 3 )); then
        p6_items+=("(a) 教訓効果率分析 — ${impact_age}日前。再分析で低効果教訓を特定")
    fi
else
    p6_items+=("(a) 教訓効果率分析 — 未実施。lesson_impact.tsvを生成せよ")
fi

# (b) gate_fire_log: 本番FAIL率が15%超なら推薦
if [[ -f "$_FIRE_LOG" ]]; then
    prod_total=$(grep -v '/tmp/' "$_FIRE_LOG" | grep -c 'result:' 2>/dev/null || true)
    prod_fail=$(grep -v '/tmp/' "$_FIRE_LOG" | grep -c 'result: FAIL' 2>/dev/null || true)
    if (( prod_total > 0 )); then
        fail_pct=$(( prod_fail * 100 / prod_total ))
        if (( fail_pct > 15 )); then
            p6_items+=("(b) gate_fire_log分析 — 本番FAIL率${fail_pct}%(${prod_fail}/${prod_total})。パターン検出せよ")
        fi
    fi
fi

# (c) 次cmdの先行学習: snapshotから直近cmdを読み取り
latest_cmd=$(grep -oP 'cmd_\d+' "$SNAPSHOT" 2>/dev/null | sort -t_ -k2 -n | tail -1)
if [[ -n "$latest_cmd" ]]; then
    reviewed=$(grep -c "cmd_id: $latest_cmd" "$REVIEW_LOG" 2>/dev/null || true)
    if (( reviewed == 0 )); then
        p6_items+=("(c) ${latest_cmd}先行学習 — 未レビュー。関連コードを事前学習せよ")
    fi
fi

# (d) WARN率改善: 直近10件のWARN比率が高ければ推薦
warn_recent=$(tail -30 "$REVIEW_LOG" | grep -c 'gate_result: WARN' 2>/dev/null || true)
if (( warn_recent > 3 )); then
    p6_items+=("(d) WARN率改善分析 — 直近30行で${warn_recent}件WARN。パターン改善せよ")
fi

if (( ${#p6_items[@]} > 0 )); then
    echo "■ P6: 自己研鑽候補"
    for item in "${p6_items[@]}"; do
        echo "    $item"
    done
    echo ""
else
    echo "■ P6: 全項目健全。新たな気づきを探せ"
    echo ""
fi

fi  # CTX_HIGH

# --- サイクルの心得 ---
echo "─────────────────────────────"
echo "止まるな。考えて行動、考えて行動。"
echo "気づき → なぜ → 行動 → 観察 → 次の気づき"
echo "─────────────────────────────"
