#!/usr/bin/env bash
# ============================================================
# cmd_save.sh
# 将軍がEdit toolでshogun_to_karo.yamlに書いたcmdブロックの保存前安全チェック
#
# Usage: bash scripts/cmd_save.sh <cmd_id>
#   cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）
#
# チェック内容:
#   1. cmdブロックがshogun_to_karo.yamlに存在するか
#   2. archive/cmds/配下の完了済みcmd_idとの重複チェック
#   3. quality_gateフィールド検査（q1_firefighting, q2_learning, q3_next_quality, q4_depth[WARNING]）
#   4. flock競合検出（家老との同時書き込み防止）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
ARCHIVE_CMD_DIR="$PROJECT_DIR/queue/archive/cmds"
LOCK_FILE="/tmp/shogun_to_karo.lock"

# --- Usage ---
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/cmd_save.sh <cmd_id>" >&2
    echo "  cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）" >&2
    exit 1
fi

# --- cmd_id正規化（cmd_プレフィックスを付与） ---
RAW_ID="$1"
if [[ "$RAW_ID" =~ ^cmd_ ]]; then
    CMD_ID="$RAW_ID"
else
    CMD_ID="cmd_${RAW_ID}"
fi

WARN_COUNT=0

# --- Check 1: cmdブロック存在確認 ---
if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "WARN: $QUEUE_FILE が存在しません" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
elif ! grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    echo "WARN: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# --- Check 2: 重複チェック（アーカイブ済みcmd_idとの衝突） ---
if [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    # パターン: cmd_XXXX_completed_YYYYMMDD.yaml
    if ls "$ARCHIVE_CMD_DIR"/"${CMD_ID}"_completed_*.yaml 1>/dev/null 2>&1; then
        echo "WARN: ${CMD_ID} は既にアーカイブ済みです（重複の可能性）" >&2
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

# --- Check 3: quality_gateフィールド検査 ---
# cmdブロック内にquality_gate（q1_firefighting, q2_learning, q3_next_quality）があるか検査
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    # cmdブロックを抽出（cmd_id行の次行から、次のcmd_行の直前まで）
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")

    if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "quality_gate:"; then
        echo "BLOCK: quality_gate未記入。3問に答えてからcmd_save.shを実行せよ" >&2
        cat >&2 <<'QG_TEMPLATE'
---
quality_gate:
  q1_firefighting: "no/yes — 理由"
  q2_learning: "奪わない/奪う — 学習機会への影響"
  q3_next_quality: "上がる/下がる — 品質への影響"
---
QG_TEMPLATE
        exit 1
    fi

    MISSING_KEYS=()
    for _QG_KEY in q1_firefighting q2_learning q3_next_quality; do
        if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "${_QG_KEY}:"; then
            MISSING_KEYS+=("$_QG_KEY")
        fi
    done

    if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
        echo "BLOCK: quality_gate未記入。3問に答えてからcmd_save.shを実行せよ" >&2
        echo "  未記入キー: ${MISSING_KEYS[*]}" >&2
        {
            echo "---"
            echo "quality_gate:"
            for _MK in "${MISSING_KEYS[@]}"; do
                case "$_MK" in
                    q1_firefighting)  echo '  q1_firefighting: "no/yes — 理由"' ;;
                    q2_learning)      echo '  q2_learning: "奪わない/奪う — 学習機会への影響"' ;;
                    q3_next_quality)  echo '  q3_next_quality: "上がる/下がる — 品質への影響"' ;;
                esac
            done
            echo "---"
        } >&2
        exit 1
    fi

    # q4_depth: 段階的導入のためBLOCKではなくWARNING（WARN_COUNTに加算しない）
    if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "q4_depth:"; then
        echo "WARNING: q4_depth未記入。深堀り度を記入推奨: q4_depth: \"shallow/medium/deep — 理由\"" >&2
    fi

    # q5_verified_source: cmdの前提を一次情報源で確認したか（BLOCK）
    # 一次情報源 = コード/本番DB/API応答。前cmdの報告は一次情報源ではない
    if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "q5_verified_source:"; then
        echo "BLOCK: q5_verified_source未記入。cmdの前提を何で確認したか記載せよ" >&2
        echo "  一次情報源 = コード/本番DB/API応答。前cmdの報告は一次情報源ではない" >&2
        echo '  例: q5_verified_source: "engine.py L107-137 + 本番FoF API GET応答で構造確認"' >&2
        exit 1
    fi

    # q5検証レベル分類（段階的導入 — WARN_COUNTに加算しない）
    # cmd_1481教訓: code_readingをproduction_verifiedに見せかけた。忍者に信頼度を正直に伝える(利他)
    q5_val=$(echo "$CMD_BLOCK" | grep "q5_verified_source:" | head -1)
    if echo "$q5_val" | grep -qiE "code_reading|コード読み|読んだだけ"; then
        echo "INFO: q5=code_reading。根因仮説は未実行検証。忍者は独自検証が必要" >&2
    elif ! echo "$q5_val" | grep -qiE "実行|execute|pipeline|本番|production|API応答|DB確認|テスト実行"; then
        echo "WARNING: q5に検証方法が不明確。レベル明記推奨: code_reading(コード読み) / isolated_test(単体実行) / pipeline_test(結合実行) / production_verified(本番確認)" >&2
    fi

    # q6_not_hiding: SG8自動消火チェック（段階的導入 — BLOCKではなくWARNING）
    # 目的: 表面的対処で根源的問題を隠し改革動機を殺すcmdを防止
    # 起源: cmd_1278事件 — lessons.yaml読込削除が7,552行の構造問題を隠蔽
    if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "q6_not_hiding:"; then
        echo "WARNING: q6_not_hiding未記入。「この変更は根源的問題を隠さないか？表面的対処で改革動機を殺さないか？」" >&2
        echo '  例: q6_not_hiding: "no — Vercel化は構造改革であり表面的対処ではない"' >&2
    fi

    # q7_branch_coverage: 条件分岐変更cmdの本番データ分岐確認AC提案（段階的導入 — WARNING）
    # 起源: cmd_1443事例 — 本番未使用コードパスへの無駄修正
    # 目的: type=impl + 条件分岐キーワード検出時に、本番での分岐実行頻度確認ACの追加を提案
    _Q7_TASK_TYPE=$(echo "$CMD_BLOCK" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    if [[ "${_Q7_TASK_TYPE:-}" == "impl" ]]; then
        _Q7_FIELDS=$(echo "$CMD_BLOCK" | grep -E '^\s*(purpose|title):' || true)
        if echo "$_Q7_FIELDS" | grep -qiE '\bif\b|\bcase\b|条件|分岐|フラグ|\bflag\b|\belif\b|\bswitch\b'; then
            echo "WARNING: q7_branch_coverage — 条件分岐変更を含むimpl cmdです。本番データでの分岐実行頻度確認ACの追加を検討してください" >&2
            echo "  推奨アクション: 本番DBで該当条件がtrue/falseになるレコード数を確認せよ" >&2
            echo "  (cmd_1443教訓: 本番未使用コードパスへの修正は無駄コスト+リスク)" >&2
        fi
    fi

    # --- Check 3.7: チェックリスト制約転写確認（WARNING） ---
    # cmd_1397事故: チェックリストStep7(再計算禁止)がcmdに転写されず忍者が再計算実行
    # cmdにチェックリスト参照がある場合、隣接Step制約の転写を促す
    if echo "$CMD_BLOCK" | grep -qiE 'チェックリスト|checklist-'; then
        echo "WARNING: チェックリスト参照cmdです。隣接Stepの🛑制約(禁止事項)をACまたは制約欄に転写しましたか？" >&2
        echo "  (cmd_1397教訓: Step7再計算禁止がcmd未記載→忍者が再計算実行)" >&2
    fi
fi

# --- Check 4: flock競合検出 ---
# flock -n: ノンブロッキング。取得成功=競合なし、取得失敗=家老が書き込み中
if ! (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
    echo "WARN: $LOCK_FILE がロック中です（家老が書き込み中の可能性）" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# --- Check 5: uncommitted changes検出 ---
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain -uno 2>/dev/null | grep -v 'queue/shogun_to_karo\.yaml' || true)
if [[ -n "$UNCOMMITTED" ]]; then
    echo "WARN: 未コミット変更を検出（コミット忘れ注意）:" >&2
    echo "$UNCOMMITTED" | while IFS= read -r line; do
        echo "  $line" >&2
    done
fi

# --- Check 6: パイプラインGP重複チェック（非BLOCK — WARN_COUNTに加算しない） ---
# 新cmdのcommandフィールドからGP-XXXパターンを抽出し、
# 直近20件のdelegated/in_progress cmdと照合。一致時WARN（非BLOCK）
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    NEW_CMD_LINE=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /command:/{print; exit}" "$QUEUE_FILE")
    NEW_GP=$(echo "$NEW_CMD_LINE" | grep -oE 'GP-[0-9]+' | sort -u || true)

    if [[ -n "$NEW_GP" ]]; then
        RECENT_CMDS=$(grep -oE "^  cmd_[0-9]+:" "$QUEUE_FILE" | sed 's/: *$//; s/^ *//' | tail -20 | grep -v "^${CMD_ID}$" || true)

        if [[ -n "$RECENT_CMDS" ]]; then
            while IFS= read -r OTHER_CMD; do
                [[ -z "$OTHER_CMD" ]] && continue
                OTHER_BLOCK=$(awk "/^  ${OTHER_CMD}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
                OTHER_STATUS=$(echo "$OTHER_BLOCK" | awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}')

                if [[ "$OTHER_STATUS" == "delegated" || "$OTHER_STATUS" == "in_progress" ]]; then
                    OTHER_CMD_LINE=$(echo "$OTHER_BLOCK" | grep -m1 "command:" || true)
                    while IFS= read -r gp; do
                        [[ -z "$gp" ]] && continue
                        if echo "$OTHER_CMD_LINE" | grep -qF "$gp"; then
                            echo "WARN: ${CMD_ID} のGP番号 ${gp} が ${OTHER_CMD}(status:${OTHER_STATUS}) と重複" >&2
                        fi
                    done <<< "$NEW_GP"
                fi
            done <<< "$RECENT_CMDS"
        fi
    fi
fi

# --- Check 7: 軍師既存分析チェック（偵察cmd重複防止） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに偵察cmd重複起票
# 目的: recon/scout cmdの起票前に軍師の関連分析有無を確認させる
check_gunshi_analysis_overlap() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # task_typeがrecon/scoutの場合のみチェック（impl等は対象外）
    local TASK_TYPE
    TASK_TYPE=$(echo "$CMD_BLOCK" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    if [[ "$TASK_TYPE" != "recon" && "$TASK_TYPE" != "scout" ]]; then
        return 0
    fi

    # context/gunshi-*.md の存在チェック
    local GUNSHI_FILES
    GUNSHI_FILES=$(find "$PROJECT_DIR/context" -name "gunshi-*.md" -type f 2>/dev/null)
    [[ -z "$GUNSHI_FILES" ]] && return 0

    # 軍師分析ファイルの見出しを表示
    local HIT=false
    while IFS= read -r gfile; do
        [[ -z "$gfile" || ! -f "$gfile" ]] && continue
        local title mtime_hr
        title=$(head -5 "$gfile" | grep -m1 '^#' | sed 's/^# *//')
        mtime_hr=$(date -r "$gfile" '+%m-%d %H:%M' 2>/dev/null || echo "unknown")
        if [[ "$HIT" == false ]]; then
            echo "WARNING: 偵察cmd起票前に軍師の既存分析を確認したか？" >&2
            HIT=true
        fi
        echo "  $(basename "$gfile") [$mtime_hr] — $title" >&2
    done <<< "$GUNSHI_FILES"

    if [[ "$HIT" == true ]]; then
        echo "  → 重複起票防止(cmd_1451教訓): 軍師が先行分析済みの可能性あり" >&2
    fi
}

check_gunshi_analysis_overlap

# --- Check 8: PI番号衝突チェック（Production Invariant重複防止） ---
# 起源: cmd_1453事件 — PI-015を起票したが既存PI-015と衝突。hayateがPI-016に修正
# 目的: cmdにPI-0XXが含まれる場合、既存PIと衝突しないか自動チェック
check_pi_number_collision() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # cmdブロックからPI-0XX番号を抽出
    local PI_NUMS
    PI_NUMS=$(echo "$CMD_BLOCK" | grep -oE 'PI-[0-9]{3}' | sort -u || true)
    [[ -z "$PI_NUMS" ]] && return 0

    # 全projects/*.yamlから既存PI番号を収集
    local EXISTING_PIS
    EXISTING_PIS=$(grep -ohE 'PI-[0-9]{3}' "$PROJECT_DIR"/projects/*.yaml 2>/dev/null | sort -u || true)
    [[ -z "$EXISTING_PIS" ]] && return 0

    # 衝突検出
    local HIT=false
    while IFS= read -r pi; do
        [[ -z "$pi" ]] && continue
        if echo "$EXISTING_PIS" | grep -qx "$pi"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: PI番号衝突検出（cmd_1453教訓）" >&2
                HIT=true
            fi
            echo "  $pi は既に projects/*.yaml に登録済み" >&2
        fi
    done <<< "$PI_NUMS"

    if [[ "$HIT" == true ]]; then
        # 次の空き番号を表示
        local MAX_PI
        MAX_PI=$(echo "$EXISTING_PIS" | grep -oE '[0-9]+' | sort -n | tail -1)
        local NEXT_PI
        NEXT_PI=$(printf "PI-%03d" $((10#$MAX_PI + 1)))
        echo "  → 次の空き番号: $NEXT_PI" >&2
    fi
}

check_pi_number_collision

# --- Check 9: 未消化insightsサーフェス（知識循環デッドエンド防止） ---
# 起源: insights 18件死蔵発見(2026-03-28) — 書込み専用で消費者不在
# 目的: cmd起票時にpending insightsを表示し、将軍がinsightsを消費する動線を作る
show_pending_insights() {
    local INSIGHTS_FILE="$PROJECT_DIR/queue/insights.yaml"
    [[ ! -f "$INSIGHTS_FILE" ]] && return 0

    local PENDING_COUNT
    PENDING_COUNT=$(grep -c 'status: pending' "$INSIGHTS_FILE" 2>/dev/null) || PENDING_COUNT=0
    [[ "$PENDING_COUNT" -eq 0 ]] && return 0

    echo "INFO: 未消化insights ${PENDING_COUNT}件 — 起票前に確認推奨:" >&2
    python3 - "$INSIGHTS_FILE" 3 <<'PY' >&2
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
items = data.get("insights", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
limit = int(sys.argv[2])
shown = 0
for i in items:
    if not isinstance(i, dict) or i.get("status") != "pending": continue
    text = str(i.get("insight", ""))[:70].replace("\n", " ")
    print(f"  → {text}")
    shown += 1
    if shown >= limit: break
PY
    if [[ "$PENDING_COUNT" -gt 3 ]]; then
        echo "  ... 他 $((PENDING_COUNT - 3))件 (queue/insights.yaml)" >&2
    fi
}

show_pending_insights

# --- Check 10: AC内ファイルパス存在チェック（informational — WARN_COUNTに加算しない） ---
# 起源: cmd_1464事故 — AC内「generators/monthly_returns.py」指定→実体はservices/return_calculator.py
# 目的: AC内のファイルパス参照が実在するか事前警告
check_ac_file_paths() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # AC内からファイルパス(拡張子付き)を抽出
    local PATHS
    PATHS=$(echo "$CMD_BLOCK" | grep -oE '[A-Za-z0-9_-]+(/[A-Za-z0-9_.+-]+)+\.(py|ts|tsx|js|jsx|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)' | sort -u || true)
    [[ -z "$PATHS" ]] && return 0

    # プロジェクトWDを取得: cmdブロックのproject → current_project → fallback
    local PROJECT_ID PROJECT_WD
    PROJECT_ID=$(echo "$CMD_BLOCK" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)

    if [[ -n "${PROJECT_ID:-}" ]]; then
        PROJECT_WD=$(awk -v id="$PROJECT_ID" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)
    fi

    [[ -z "${PROJECT_WD:-}" ]] && return 0

    # 各パスの存在チェック
    local HAS_MISSING=false
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if [[ ! -e "$PROJECT_WD/$fpath" ]]; then
            if [[ "$HAS_MISSING" == false ]]; then
                echo "WARNING: AC内のファイルパスが存在しません（cmd_1464教訓）:" >&2
                HAS_MISSING=true
            fi
            echo "  ✗ $fpath (in $PROJECT_WD)" >&2
        fi
    done <<< "$PATHS"

    if [[ "$HAS_MISSING" == true ]]; then
        echo "  → パス名の確認を推奨（BLOCKではありません）" >&2
    fi
}

check_ac_file_paths

# --- Check 11: impl cmd push/deploy AC検出（informational — WARN_COUNTに加算しない） ---
# 目的: project=dm-signal + type=impl のcmdにpush/deploy ACがない場合に警告
check_impl_push_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project取得
    local PROJECT_ID
    PROJECT_ID=$(echo "$CMD_BLOCK" | awk '/project:/{gsub(/.*project: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # task_type取得
    local TASK_TYPE
    TASK_TYPE=$(echo "$CMD_BLOCK" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    # CMD_BLOCK内のpush/deploy関連キーワード検索
    if ! echo "$CMD_BLOCK" | grep -qiE 'push|deploy|デプロイ|Render|本番反映'; then
        echo "WARNING: project=dm-signal + type=impl にpush/deploy関連ACがありません。本番反映手順の追加を検討してください" >&2
    fi
}

check_impl_push_ac

# --- Quality Summary (品質パターン表示) ---
show_quality_summary() {
    local QUALITY_LOG="$PROJECT_DIR/logs/cmd_design_quality.yaml"

    # AC3: ファイル不存在・空→スキップ（エラーなし）
    if [[ ! -f "$QUALITY_LOG" ]] || [[ ! -s "$QUALITY_LOG" ]]; then
        return 0
    fi

    # Single awk pass: parse entries, output AC1 summary + AC2 warnings
    awk '
    /^ *- cmd_id:/ { n++ }
    /karo_rework:/ {
        val = $2; gsub(/[" ]/, "", val)
        if (val == "yes") rw[n] = 1
    }
    /ninja_blockers:/ {
        val = $2 + 0
        if (val > 0) bl[n] = 1
    }
    /supplementary_cmds:/ {
        val = $2 + 0
        if (val > 0) sp[n] = 1
    }
    END {
        if (n == 0) exit

        # AC1: 直近10件サマリー（10件未満ならあるだけ）
        s10 = (n > 10) ? n - 9 : 1
        c10 = n - s10 + 1
        rw10 = 0; bl10 = 0; sp10 = 0
        for (i = s10; i <= n; i++) {
            rw10 += rw[i]; bl10 += bl[i]; sp10 += sp[i]
        }
        printf "品質: %dcmd中 rework=%d blocker=%d supplementary=%d\n", c10, rw10, bl10, sp10

        # AC2: 直近5件でパターン警告
        s5 = (n > 5) ? n - 4 : 1
        c5 = n - s5 + 1
        if (c5 < 2) exit
        r5 = 0; b5 = 0; p5 = 0
        for (i = s5; i <= n; i++) {
            r5 += rw[i]; b5 += bl[i]; p5 += sp[i]
        }
        rr = (r5 / c5) * 100
        br = (b5 / c5) * 100
        sr = (p5 / c5) * 100
        if (rr > 20) printf "WARNING: rework率%.0f%%。AC設計の精度を確認せよ\n", rr
        if (br > 10) printf "WARNING: blocker率%.0f%%。前提条件の確認を強化せよ\n", br
        if (sr > 30) printf "WARNING: 補足cmd率%.0f%%。スコープ漏れの傾向\n", sr
    }
    ' "$QUALITY_LOG" || true
}

show_quality_summary

# --- Gunshi直近指摘表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_recent_issues() {
    local GUNSHI_LOG="$PROJECT_DIR/logs/gunshi_review_log.yaml"

    # AC3: ファイル不存在/空→スキップ
    if [[ ! -f "$GUNSHI_LOG" ]] || [[ ! -s "$GUNSHI_LOG" ]]; then
        return 0
    fi

    # AC1+AC2: 直近REQ_CHANGES/FAILを最大3件表示
    awk '
    /^- cmd_id:/ {
        n++
        cmd[n] = $3
    }
    /^  verdict:/ {
        v = $2
        gsub(/#.*/, "", v)
        gsub(/[" ]/, "", v)
        verdict[n] = v
    }
    /^  findings_summary:/ {
        s = $0
        sub(/^  findings_summary: *"?/, "", s)
        sub(/"$/, "", s)
        summary[n] = substr(s, 1, 60)
    }
    END {
        m = 0
        for (i = 1; i <= n; i++) {
            if (verdict[i] == "REQUEST_CHANGES" || verdict[i] == "FAIL") {
                issues[++m] = i
            }
        }
        if (m == 0) exit
        start = (m > 3) ? m - 2 : 1
        for (j = start; j <= m; j++) {
            k = issues[j]
            printf "軍師直近指摘: %s %s — %s\n", cmd[k], verdict[k], summary[k]
        }
    }
    ' "$GUNSHI_LOG" 2>/dev/null || true
}

show_gunshi_recent_issues

# --- 軍師ペイン活動状況表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_pane_status() {
    local PANE_TARGET="shogun:2.2"

    # ペイン存在確認（tmux未起動 or ペインなし → スキップ）
    if ! tmux capture-pane -t "$PANE_TARGET" -p >/dev/null 2>&1; then
        return 0
    fi

    # 最終3行をキャプチャ（空行を除去してから末尾3行）
    local PANE_CONTENT
    PANE_CONTENT=$(tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | sed '/^$/d' | tail -n 3) || return 0

    if [[ -n "$PANE_CONTENT" ]]; then
        echo "軍師ペイン(最終3行):"
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$PANE_CONTENT"
    fi
}

show_gunshi_pane_status

# --- 結果出力 ---
if [[ "$WARN_COUNT" -eq 0 ]]; then
    echo "保存確認OK: ${CMD_ID}"
else
    echo "保存確認NG: ${CMD_ID} (${WARN_COUNT}件のWARN)" >&2
    exit 1
fi
