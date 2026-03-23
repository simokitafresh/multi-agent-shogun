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

    # q6_not_hiding: SG8自動消火チェック（段階的導入 — BLOCKではなくWARNING）
    # 目的: 表面的対処で根源的問題を隠し改革動機を殺すcmdを防止
    # 起源: cmd_1278事件 — lessons.yaml読込削除が7,552行の構造問題を隠蔽
    if ! echo "$CMD_BLOCK" | grep -v '^\s*#' | grep -q "q6_not_hiding:"; then
        echo "WARNING: q6_not_hiding未記入。「この変更は根源的問題を隠さないか？表面的対処で改革動機を殺さないか？」" >&2
        echo '  例: q6_not_hiding: "no — Vercel化は構造改革であり表面的対処ではない"' >&2
    fi
fi

# --- Check 4: flock競合検出 ---
# flock -n: ノンブロッキング。取得成功=競合なし、取得失敗=家老が書き込み中
if ! (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
    echo "WARN: $LOCK_FILE がロック中です（家老が書き込み中の可能性）" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# --- Check 5: uncommitted changes検出 ---
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | grep -v 'queue/shogun_to_karo\.yaml' || true)
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

# --- 結果出力 ---
if [[ "$WARN_COUNT" -eq 0 ]]; then
    echo "保存確認OK: ${CMD_ID}"
else
    echo "保存確認NG: ${CMD_ID} (${WARN_COUNT}件のWARN)" >&2
    exit 1
fi
