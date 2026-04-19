#!/bin/bash
# gate_gunshi_report_precheck.sh — 軍師レビュー前の機械的検証を自動化
# 目的: 7つの意志依存ステップを1コマンドに統合。意志依存ゼロ。
# Usage: bash scripts/gates/gate_gunshi_report_precheck.sh <report_yaml_path>
# 知性の外部化: deepdive Phase 7。自分の問題を自分で解決する。
# §3.2最適化: python3 -c 13回 → engine.py 1回呼出。390ms/report → 30ms/report

set -euo pipefail

REPORT_PATH="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "FAIL: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

echo "=== 軍師レビュー前検証: $(basename "$REPORT_PATH") ==="

ERRORS=0

# ─── Engine: 1回のファイル読込で全Pythonチェックを実行 ───────────────────
# 出力: WORKER_ID / PARENT_CMD / IS_DM_SIGNAL / FILES_MODIFIED /
#       BINARY_CHECKS_MSG / SAME_CMD_NINJAS / TASK_FILE
eval "$(python3 "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py" \
    --report "$REPORT_PATH" \
    --tasks-dir "$REPO_ROOT/queue/tasks" 2>/dev/null)"

# DM-Signal project directory
PROJECT_DIR=""
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    PROJECT_DIR="/mnt/c/Python_app/DM-Signal"
fi

# ─── SG-PRE1: gate_report_format.sh ───
echo ""
echo "■ SG-PRE1: gate_report_format.sh"
if bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT_PATH" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL — フォーマット不備あり。詳細は上記出力参照"
    ERRORS=$((ERRORS + 1))
fi

# ─── SG-PRE2: ninja workaround rate ───
echo ""
echo "■ SG-PRE2: ninja workaround rate"
if [ -n "${WORKER_ID:-}" ]; then
    bash "$REPO_ROOT/scripts/gates/gate_ninja_workaround_rate.sh" --ninja "$WORKER_ID" 2>/dev/null || true
else
    echo "  SKIP: worker_id not found"
fi

# ─── SG-PRE3: commit検証 ───
echo ""
echo "■ SG-PRE3: commit検証"

if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
    if [ -n "${FILES_MODIFIED:-}" ]; then
        COMMIT_FOUND=0
        while IFS= read -r fpath; do
            COMMIT_LINE=$(cd "$PROJECT_DIR" && git log --oneline -1 -- "$fpath" 2>/dev/null || echo "")
            if [ -n "$COMMIT_LINE" ]; then
                if echo "$COMMIT_LINE" | grep -qi "${PARENT_CMD:-}" 2>/dev/null; then
                    echo "  PASS: $fpath → $COMMIT_LINE"
                    COMMIT_FOUND=1
                else
                    echo "  WARN: $fpath → $COMMIT_LINE (cmd_id不一致)"
                fi
            else
                echo "  WARN: $fpath → commit not found"
                # GP-202補完: commit不在時にファイル実在を代替確認(RESEARCH cmd対応)
                if [ -f "$PROJECT_DIR/$fpath" ] 2>/dev/null || [ -f "$fpath" ] 2>/dev/null; then
                    echo "    → FILE EXISTS (untracked/uncommitted)"
                else
                    echo "    → FILE NOT FOUND — 成果物不在の可能性"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done <<< "${FILES_MODIFIED:-}"

        if [ "$COMMIT_FOUND" -eq 0 ]; then
            echo "  WARN: cmd_id一致のcommitなし"
        fi
    else
        echo "  SKIP: files_modified empty"
    fi

    # ─── SG-PRE4: backend/app/変更チェック ───
    echo ""
    echo "■ SG-PRE4: backend/app/変更チェック"
    # Find the latest commit for any modified file
    LATEST_COMMIT=$(cd "$PROJECT_DIR" && echo "${FILES_MODIFIED:-}" | head -1 | xargs -I{} git log --format=%H -1 -- {} 2>/dev/null || echo "")
    if [ -n "$LATEST_COMMIT" ]; then
        BACKEND_CHANGES=$(cd "$PROJECT_DIR" && git diff --name-only "${LATEST_COMMIT}^..${LATEST_COMMIT}" -- backend/app/ 2>/dev/null || echo "")
        if [ -z "$BACKEND_CHANGES" ]; then
            echo "  PASS: backend/app/変更なし"
        else
            echo "  WARN: backend/app/に変更あり:"
            while IFS= read -r _line; do echo "    $_line"; done <<< "$BACKEND_CHANGES"
        fi
    else
        echo "  SKIP: commit not resolved"
    fi
else
    echo "  SKIP: project directory not detected"
    echo ""
    echo "■ SG-PRE4: backend/app/変更チェック"
    echo "  SKIP: project directory not detected"
fi

# ─── SG-PRE5: binary_checks項目数(task YAML vs report) ───
echo ""
echo "■ SG-PRE5: binary_checks項目数整合"
if [ -f "${TASK_FILE:-}" ]; then
    echo "${BINARY_CHECKS_MSG:-  SKIP}"
else
    echo "  SKIP: task YAML not found: ${TASK_FILE:-}"
fi

# ─── SG-PRE6: ファイル行数確認 ───
echo ""
echo "■ SG-PRE6: files_modified行数"
if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ] && [ -n "${FILES_MODIFIED:-}" ]; then
    while IFS= read -r fpath; do
        FULL_PATH="$PROJECT_DIR/$fpath"
        if [ -f "$FULL_PATH" ]; then
            LINE_COUNT=$(wc -l < "$FULL_PATH")
            echo "  $fpath: ${LINE_COUNT}行"
        else
            echo "  $fpath: NOT FOUND"
        fi
    done <<< "${FILES_MODIFIED:-}"
else
    echo "  SKIP"
fi

# ─── SG-PRE7: cmd仕様パラメータ突合リマインダ ───
echo ""
echo "■ SG-PRE7: cmd仕様パラメータ突合"
if [ -n "${PARENT_CMD:-}" ]; then
    CMD_SPEC=$(grep -A60 "${PARENT_CMD}:" "$REPO_ROOT/queue/shogun_to_karo.yaml" 2>/dev/null | head -60 || true)
    if [ -n "$CMD_SPEC" ]; then
        # Extract numeric parameters from cmd spec
        PARAMS=$(echo "$CMD_SPEC" | grep -oE '(m=|window|threshold|d=|k=|alpha|span|lookback)[^,)]*[0-9][0-9.]*' || true)
        PARAMS=$(echo "$PARAMS" | head -10)
        if [ -n "$PARAMS" ]; then
            echo "  ★ cmd仕様に数値パラメータ検出。報告との突合必須:"
            echo "$PARAMS" | while IFS= read -r p; do echo "    $p"; done
        else
            echo "  PASS: cmd仕様に明示パラメータなし"
        fi
    else
        echo "  SKIP: shogun_to_karo.yamlに${PARENT_CMD}なし(アーカイブ済み?)"
    fi
else
    echo "  SKIP: parent_cmd not found"
fi

# ─── SG-PRE8: 二重配備検出 ───
echo ""
echo "■ SG-PRE8: 二重配備検出"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${WORKER_ID:-}" ]; then
    if [ -n "${SAME_CMD_NINJAS:-}" ]; then
        echo "  WARN: 二重配備検出! ${PARENT_CMD}は他の忍者にも配備済み: ${SAME_CMD_NINJAS}"
    else
        echo "  PASS: ${PARENT_CMD}は${WORKER_ID}のみ"
    fi
else
    echo "  SKIP: parent_cmd or worker_id not found"
fi

# ─── SG-PRE9: binary_checks result:no → gate_prediction BLOCK予告 (GP-193) ───
echo ""
echo "■ SG-PRE9: T1違反予防(binary_checks no検出)"
if [ "${BC_HAS_NO:-0}" = "1" ]; then
    echo "  ★★★ WARN: binary_checks result:no検出: ${BC_NO_ITEMS}"
    echo "  → gate_prediction: BLOCK固定(waive_reasonがあっても免除なし)"
    echo "  → GP-128: verdict PASS + result:no → gate機械的BLOCK"
    echo "  → 見落とし実績: cmd_1897, cmd_1900, cmd_2093 (T1違反3回)"
else
    echo "  PASS: binary_checks全result:yes (or検出対象なし)"
fi

# ─── SG-PRE10: ac_version照合 ───
echo ""
echo "■ SG-PRE10: ac_version照合"
echo "${AC_VERSION_MSG:-  SKIP}"
if echo "${AC_VERSION_MSG:-}" | grep -q "FAIL"; then
    ERRORS=$((ERRORS + 1))
fi

# ─── SG-PRE11: lessons_useful形式検証 ───
echo ""
echo "■ SG-PRE11: lessons_useful形式検証"
echo "${LESSONS_USEFUL_MSG:-  SKIP}"

# ─── SG-PRE12: lesson_candidate有 → gate_prediction WARN必須 (GP-195) ───
echo ""
echo "■ SG-PRE12: lesson_candidate存在チェック"
if [ "${HAS_LESSON_CANDIDATE:-0}" = "1" ]; then
    echo "  ★★★ WARN: lesson_candidate有。gate_prediction: WARN/BLOCK必須"
    echo "  → draft_lessons BLOCKリスク(家老がlesson登録するまでGATE通過しない)"
    echo "  → 見落とし実績: cmd_1811, cmd_1814, cmd_1909, cmd_1911 (4回)"
else
    echo "  PASS: lesson_candidateなし"
fi

# ─── SG-PRE13: hook/gate系ファイルの大規模削減検出 (GP-205, cmd_1975反省) ───
echo ""
echo "■ SG-PRE13: hook/gate大規模削減検出"
if [ -n "${FILES_MODIFIED:-}" ]; then
    HOOK_GATE_WARN=0
    while IFS= read -r fpath; do
        case "$fpath" in
            *.claude/hooks/*|*scripts/hooks/*|*scripts/gates/*)
                # git diff --statで変更規模を確認
                added=$(git log --grep="${PARENT_CMD}" --format="" --numstat -- "$fpath" 2>/dev/null | awk '{a+=$1}END{print a+0}')
                deleted=$(git log --grep="${PARENT_CMD}" --format="" --numstat -- "$fpath" 2>/dev/null | awk '{d+=$2}END{print d+0}')
                if [ "$deleted" -gt 0 ]; then
                    total_before=$((added + deleted))  # 近似: 追加+削除≈変更前行数
                    delete_ratio=$((deleted * 100 / total_before))
                    if [ "$delete_ratio" -gt 50 ]; then
                        echo "  ★★★ WARN: $fpath — 削減率${delete_ratio}%(+${added}/-${deleted})。hook/gateの大規模削減は機能破壊の可能性。git diffで現物確認せよ"
                        HOOK_GATE_WARN=1
                    fi
                fi
                ;;
        esac
    done <<< "$FILES_MODIFIED"
    if [ "$HOOK_GATE_WARN" -eq 0 ]; then
        echo "  PASS: hook/gate系の大規模削減なし"
    fi
else
    echo "  SKIP: files_modified不明"
fi

# ─── SG-PRE14: revert検出 (cmd_2107事故: revert後にAC3:yesのまま報告) ───
echo ""
echo "■ SG-PRE14: revert検出(files_modified内にrevertされたファイルがないか)"
REVERT_FOUND=0
if [ -n "${FILES_MODIFIED:-}" ] && [ -n "${PARENT_CMD:-}" ]; then
    while IFS= read -r line; do
        fpath=$(echo "$line" | sed 's/.*path: *//' | tr -d "'\"")
        [ -z "$fpath" ] && continue
        [[ "$fpath" == -* ]] && continue
        # files_modifiedの各ファイルについて直近5 commitにrevertが含まれるか
        if git -C "$REPO_ROOT" log --oneline -5 -- "$fpath" 2>/dev/null | grep -qi 'revert'; then
            echo "  ★★★ WARN: $fpath に直近revert commitあり。before/after数値がrevert前の可能性。再計測を確認せよ"
            REVERT_FOUND=1
        fi
    done <<< "$FILES_MODIFIED"
    if [ "$REVERT_FOUND" -eq 0 ]; then
        echo "  PASS: revertなし"
    fi
else
    echo "  SKIP"
fi

# ─── SG-PRE15: 並列負荷警告 (計測値汚染リスク) ───
echo ""
echo "■ SG-PRE15: 並列負荷警告(before/after計測値の信頼性)"
BUSY_NINJAS=0
for task_file in "$REPO_ROOT"/queue/tasks/{hayate,kagemaru,hanzo,saizo,kotaro,tobisaru}.yaml; do
    [ -f "$task_file" ] || continue
    task_status=$(grep -m1 'status:' "$task_file" 2>/dev/null | sed 's/.*status: *//' | tr -d "'\"" || true)
    if [ "$task_status" = "in_progress" ] || [ "$task_status" = "acknowledged" ]; then
        BUSY_NINJAS=$((BUSY_NINJAS + 1))
    fi
done
if [ "$BUSY_NINJAS" -ge 3 ]; then
    echo "  ★★★ WARN: ${BUSY_NINJAS}名の忍者が稼働中。before/after計測値がWSL2 I/O負荷で汚染されている可能性。全忍者idle後の再計測を推奨"
elif [ "$BUSY_NINJAS" -ge 1 ]; then
    echo "  INFO: ${BUSY_NINJAS}名の忍者が稼働中。計測値への影響は軽微"
else
    echo "  PASS: 全忍者idle。計測値は信頼可能"
fi

# ─── 総合判定 ───
echo ""
echo "=== 総合: ERRORS=$ERRORS ==="
if [ "$ERRORS" -gt 0 ]; then
    echo "★ FAIL項目あり。レビュー前に確認せよ"
    exit 1
else
    echo "★ 機械的検証PASS。6観点レビューに進め"
    exit 0
fi
