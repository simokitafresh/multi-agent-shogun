#!/bin/bash
# semantic-links: [[Silent Fallback品質]]
# gate_gunshi_report_precheck.sh — 軍師レビュー前の機械的検証を自動化
# 目的: 7つの意志依存ステップを1コマンドに統合。意志依存ゼロ。
# Usage: bash scripts/gates/gate_gunshi_report_precheck.sh <report_yaml_path>
# 知性の外部化: deepdive Phase 7。自分の問題を自分で解決する。
# §3.2最適化: python3 -c 13回 → engine.py 1回呼出。390ms/report → 30ms/report

set -euo pipefail

REPORT_PATH="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/project_path.sh
source "${REPO_ROOT}/scripts/lib/project_path.sh"
DM_SIGNAL_PATH="$(get_project_path 'dm-signal')"
export DM_SIGNAL_PATH

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

# Project directory (commit検証用)
PROJECT_DIR=""
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    PROJECT_DIR="${DM_SIGNAL_PATH}"
else
    PROJECT_DIR="$REPO_ROOT"
fi

print_sg_pre9() {
    echo ""
    echo "■ SG-PRE9: T1違反予防(binary_checks no検出)"
    if [ "${BC_HAS_NO:-0}" = "1" ]; then
        echo "  ★★★ WARN: binary_checks result:no検出: ${BC_NO_ITEMS}"
        if [ -n "${BC_NO_WAIVE_ITEMS:-}" ]; then
            echo "  → waive_reason付きresult:no: ${BC_NO_WAIVE_ITEMS}"
        fi
        echo "  → gate_prediction: BLOCK固定(waive_reason/test_triageがあっても免除なし)"
        echo "  → GP-128: verdict PASS + result:no → gate機械的BLOCK"
        echo "  → 見落とし実績: cmd_1897, cmd_1900, cmd_2093 (T1違反3回)"
    else
        echo "  PASS: binary_checks全result:yes (or検出対象なし)"
    fi
}

is_generated_large_artifact() {
    local path="$1"
    case "$path" in
        outputs/grid_search/*.db|outputs/grid_search/*.sqlite|outputs/grid_search/*.sqlite3|outputs/grid_search/*.duckdb|outputs/grid_search/*.db-shm|outputs/grid_search/*.db-wal|\
        */outputs/grid_search/*.db|*/outputs/grid_search/*.sqlite|*/outputs/grid_search/*.sqlite3|*/outputs/grid_search/*.duckdb|*/outputs/grid_search/*.db-shm|*/outputs/grid_search/*.db-wal)
            return 0
            ;;
    esac
    return 1
}

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE9" ]; then
    print_sg_pre9
    exit 0
fi

# ─── L5: GATE CLEAR≠レビュー免除リマインド (殿厳命2026-06-08) ───
echo ""
echo "★★★ レビューの目的は実装の正しさ確認。GATE CLEARはレビュー免除の理由にならない(洗脳#1防止) ★★★"
echo "★★★ infra/scripts変更: binary_checks=yesを鵜呑みにするな。実際に実行して動作確認せよ(洗脳#2防止) ★★★"

# ─── SG-PRE1: gate_report_format.sh ───
echo ""
echo "■ SG-PRE1: gate_report_format.sh"
if GATE_NO_LOG=1 SHOGUN_DISABLE_MEMORY_DB_CACHE=1 bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT_PATH" 2>/dev/null; then
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

# ─── Batch git data (WSL2最適化: N*2 per-file git log → 2 batch calls) ───
_PRE_CMD_FILES=""
_PRE_RECENT_DATA=""
_REPORT_HASHES=$(grep -oiP '(?:commit|commit_hash:)\s*\K[0-9a-f]{7,40}' "$REPORT_PATH" 2>/dev/null | sort -u || true)
if [ -n "${FILES_MODIFIED:-}" ] && [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        # PRE3/PRE14: report記載hashがあれば広域git logを避ける(WSL2 NTFS対策)
        while IFS= read -r _hash; do
            [ -z "$_hash" ] && continue
            # 注: hashが別repo(clinic等)のものだとgit fatal(128)→代入の終了コード=128→set -e全死亡するため || true 必須(2026-06-11 cmd_3277で発火した既存バグ)
            _PRE_CMD_FILES+="$(
                cd "${PROJECT_DIR:-$REPO_ROOT}" \
                    && timeout 2 git diff-tree --no-commit-id --name-only -r "$_hash" 2>/dev/null || true
            )"$'\n'
            _PRE_RECENT_DATA+="$(
                cd "$REPO_ROOT" \
                    && git show --oneline --name-only "$_hash" 2>/dev/null || true
            )"$'\n'
        done <<< "$_REPORT_HASHES"
        _PRE_CMD_FILES=$(printf '%s\n' "$_PRE_CMD_FILES" | sed '/^$/d' | sort -u)
    else
        # PRE3用: cmd固有commitが触れたファイル一覧 (1 call)
        _PRE_CMD_FILES=$(cd "${PROJECT_DIR:-$REPO_ROOT}" && timeout 2 git log --grep="${PARENT_CMD}" --format="" --name-only 2>/dev/null | sort -u) || true
        # PRE14用: 直近20 commitとファイル (1 call)
        _PRE_RECENT_DATA=$(cd "$REPO_ROOT" && timeout 2 git log --oneline -20 --name-only 2>/dev/null) || true
    fi
fi

# ─── SG-PRE3: commit検証 ───
echo ""
echo "■ SG-PRE3: commit検証"

if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
    if [ -n "${FILES_MODIFIED:-}" ]; then
        COMMIT_FOUND=0
        while IFS= read -r fpath; do
            # batch dataから判定 (per-file git log不要)
            if echo "$_PRE_CMD_FILES" | grep -qF "$fpath" 2>/dev/null; then
                echo "  PASS: $fpath → cmd commit found"
                COMMIT_FOUND=1
            elif [ -f "$PROJECT_DIR/$fpath" ] 2>/dev/null || [ -f "$fpath" ] 2>/dev/null; then
                echo "  WARN: $fpath → commit not found"
                echo "    → FILE EXISTS (untracked/uncommitted)"
            else
                echo "  WARN: $fpath → commit not found"
                echo "    → FILE NOT FOUND — 成果物不在の可能性"
                ERRORS=$((ERRORS + 1))
            fi
        done <<< "${FILES_MODIFIED:-}"

        if [ "$COMMIT_FOUND" -eq 0 ]; then
            echo "  WARN: cmd_id一致のcommitなし"
        fi
    else
        echo "  SKIP: files_modified empty"
    fi

    # ─── SG-PRE3b: commit hash実在検証 (バグ2対策: 忍者手動記入hash検証) ───
    echo ""
    echo "■ SG-PRE3b: commit hash実在検証"
    REPORT_HASHES="$_REPORT_HASHES"
    if [ -n "$REPORT_HASHES" ]; then
        while IFS= read -r hash; do
            [ -z "$hash" ] && continue
            if git -C "$PROJECT_DIR" show --quiet "$hash" >/dev/null 2>&1; then
                echo "  PASS: $hash 実在確認(${PROJECT_DIR})"
            elif git -C "$REPO_ROOT" show --quiet "$hash" >/dev/null 2>&1; then
                echo "  PASS: $hash 実在確認(${REPO_ROOT})"
            else
                echo "  ★★★ WARN: $hash が両リポジトリに不在。commit hash誤記の可能性"
            fi
        done <<< "$REPORT_HASHES"
    else
        echo "  SKIP: 報告にcommit hashなし"
    fi

    # ─── SG-PRE4: backend/app/変更チェック ───
    echo ""
    echo "■ SG-PRE4: backend/app/変更チェック"
    # Find the latest commit for any modified file
    LATEST_COMMIT=$(cd "$PROJECT_DIR" && echo "${FILES_MODIFIED:-}" | head -1 | xargs -I{} timeout 2 git log --format=%H -1 -- {} 2>/dev/null || echo "")
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
        if is_generated_large_artifact "$fpath"; then
            echo "  $fpath: SKIP generated large artifact(line-count capped)"
            continue
        fi
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
print_sg_pre9

# ─── SG-PRE9b: waive_reason×commit_hash矛盾検出 (GP-248) ───
if [ -n "${WAIVE_COMMIT_CONTRADICTION:-}" ]; then
    echo "  ★★★ WARN: ${WAIVE_COMMIT_CONTRADICTION}"
    echo "  → waive_reasonが事実と矛盾。commit存在するのにbc commit:no。FAILが正しい可能性"
fi

# ─── SG-PRE9c: binary_checks yes×task_clarity矛盾検出 (LG043) ───
echo ""
echo "■ SG-PRE9c: binary_checks yes×task_clarity矛盾検出(LG043)"
if [ "${BC_YES_CLARITY_CONTRADICTION:-0}" = "1" ]; then
    echo "  ★★★ ERROR: binary_checks全yesだがtask_clarity/assumption/purpose_gapに未達成・委譲・保留語あり: ${BC_YES_CLARITY_TERMS}"
    echo "  → cmd_3532再発防止: unclear/discretionに『デプロイ後に家老実施』等が残るなら虚偽yes。LGTMではなくFAIL/REQUEST_CHANGES"
    ERRORS=$((ERRORS + 1))
else
    echo "  PASS: binary_checks全yesとtask_clarity系の明示矛盾なし"
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
if [ -f "$REPORT_PATH" ]; then
    _lu_has_items=$(sed -n '/^lessons_useful:/,/^[^ ]/p' "$REPORT_PATH" | grep -c '^\s*- id:' 2>/dev/null || true)
    [[ "$_lu_has_items" =~ ^[0-9]+$ ]] || _lu_has_items=0
    _lu_is_empty_list=$(grep -cE '^lessons_useful:\s*\[\s*\]' "$REPORT_PATH" 2>/dev/null || true)
    [[ "$_lu_is_empty_list" =~ ^[0-9]+$ ]] || _lu_is_empty_list=0
    _lu_field_exists=0
    grep -q '^lessons_useful:' "$REPORT_PATH" 2>/dev/null && _lu_field_exists=1
    # related_lessonsが空なら lessons_useful: [] は正当(FP防止 2026-06-20 cmd_3474で発見)
    _rl_has_items=$(sed -n '/^  related_lessons:/,/^  [a-z]/p' "${TASK_FILE:-/dev/null}" 2>/dev/null | grep -c '^\s*- id:' 2>/dev/null || true)
    [[ "$_rl_has_items" =~ ^[0-9]+$ ]] || _rl_has_items=0
    if { [ "${_lu_is_empty_list:-0}" -gt 0 ] || { [ "$_lu_field_exists" -eq 1 ] && [ "${_lu_has_items:-0}" -eq 0 ]; }; } && [ "${_rl_has_items:-0}" -gt 0 ]; then
        echo "  ERROR: lessons_useful空リスト。related_lessonsが注入済み(${_rl_has_items}件)ならフィードバック必須→GATE BLOCK確実"
        ERRORS=$((ERRORS + 1))
    elif { [ "${_lu_is_empty_list:-0}" -gt 0 ] || { [ "$_lu_field_exists" -eq 1 ] && [ "${_lu_has_items:-0}" -eq 0 ]; }; } && [ "${_rl_has_items:-0}" -eq 0 ]; then
        echo "  PASS: lessons_useful空リスト(related_lessonsも空のため正当)"
    else
        echo "  PASS: lessons_useful ${_lu_has_items}件"
    fi
else
    echo "${LESSONS_USEFUL_MSG:-  SKIP}"
fi

# ─── SG-PRE12: lesson_candidate有 → INFO通知 (GP-195改: FP率高のためWARN→INFO降格) ───
echo ""
echo "■ SG-PRE12: lesson_candidate存在チェック"
if [ "${HAS_LESSON_CANDIDATE:-0}" = "1" ]; then
    echo "  INFO: lesson_candidate有。draft_lessons実件数(PRE12b)で判定"
    echo "  → lesson_candidate有のみではWARN/BLOCKとしない(直近5/5件CLEAR=FP率高)"
    echo "  → draft_lessonsが1件以上あればbash側でWARN昇格(L977-982)"
else
    echo "  PASS: lesson_candidateなし"
fi

# ─── SG-PRE12b: draft_lessons検出 (GP-237) ───
echo ""
echo "■ SG-PRE12b: draft_lessons検出(project lessons.md)"
_draft_lessons_total=0
for _lf in "$REPO_ROOT/tasks/lessons.md" "${PROJECT_DIR:+${PROJECT_DIR}/tasks/lessons.md}"; do
    [ -z "$_lf" ] || [ ! -f "$_lf" ] && continue
    _dc=$(grep -c '^\- \*\*status\*\*: draft' "$_lf" 2>/dev/null || true)
    _dc=${_dc:-0}
    if [ "$_dc" -gt 0 ]; then
        echo "  ★★★ WARN: $_lf にdraft教訓${_dc}件。gate_prediction: WARN(draft_lessons)"
        _draft_lessons_total=$((_draft_lessons_total + _dc))
    fi
done
if [ "$_draft_lessons_total" -eq 0 ]; then
    echo "  PASS: draft教訓なし"
fi

# ─── SG-PRE13: hook/gate系ファイルの大規模削減検出 (GP-205, cmd_1975反省) ───
echo ""
echo "■ SG-PRE13: hook/gate大規模削減検出"
if [ -n "${FILES_MODIFIED:-}" ]; then
    HOOK_GATE_WARN=0
    # §speed最適化(2026-07-01 gunshi-D0): git log --grep をper-fileループ外で1回だけ実行。
    # 従来はhook/gateファイルごとにgit log(全履歴grep走査~2s/回)を呼びN倍遅延(cmd_3632で2gate×2s=4s実測)。
    # 全ファイル分のnumstatを1回取得→ループ内はawkでfpath該当行を抽出集計(挙動同一・等価性検証済み)。
    _pre13_numstat=$( { timeout 3 git -C "$REPO_ROOT" log --grep="${PARENT_CMD}" --format="" --numstat 2>/dev/null || true; } )
    while IFS= read -r fpath; do
        case "$fpath" in
            *.claude/hooks/*|*scripts/hooks/*|*scripts/gates/*)
                # ループ外取得済みのnumstatからfpath該当分を抽出(per-file git log廃止)
                read -r added deleted < <(
                    printf '%s\n' "$_pre13_numstat" | \
                    awk -v f="$fpath" '$3==f {a+=$1; d+=$2} END{print a+0, d+0}'
                )
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
        # batch dataから判定 (per-file git log不要。_PRE_RECENT_DATAで事前取得済み)
        if echo "$_PRE_RECENT_DATA" | grep -B1 -F "$fpath" 2>/dev/null | grep -qi 'revert'; then
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
source "$REPO_ROOT/scripts/lib/agent_config.sh" 2>/dev/null || true
_ninja_task_files=()
for _nn in $(get_ninja_names 2>/dev/null); do
    [ -f "$REPO_ROOT/queue/tasks/${_nn}.yaml" ] && _ninja_task_files+=("$REPO_ROOT/queue/tasks/${_nn}.yaml")
done
BUSY_NINJAS=$(awk '
    /^[[:space:]]*status:/ {
        st=$2; gsub(/["'"'"']/, "", st)
        if (st=="in_progress" || st=="acknowledged") busy++
        nextfile
    }
    END{print busy+0}
' "${_ninja_task_files[@]}" 2>/dev/null || echo 0)
if [ "$BUSY_NINJAS" -ge 3 ]; then
    echo "  ★★★ WARN: ${BUSY_NINJAS}名の忍者が稼働中。before/after計測値がWSL2 I/O負荷で汚染されている可能性。全忍者idle後の再計測を推奨"
elif [ "$BUSY_NINJAS" -ge 1 ]; then
    echo "  INFO: ${BUSY_NINJAS}名の忍者が稼働中。計測値への影響は軽微"
else
    echo "  PASS: 全忍者idle。計測値は信頼可能"
fi

# ─── SG-PRE15.5: L5 adversarial事前リマインド (§5.6自動化系cmd) ───
echo ""
echo "■ SG-PRE15.5: adversarial事前リマインド(自動化系cmd)"
# §3.2最適化: python3 -c 4回→engine変数参照(ADV_TARGET_MATCH/ADV_FM_SCRIPTS/ADV_BLAST_HIGH)
if [ "${ADV_TARGET_MATCH:-0}" = "1" ]; then
    echo "  ★ target_pathが自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6)"
elif [ "${ADV_FM_SCRIPTS:-0}" = "1" ]; then
    echo "  ★ files_modifiedに自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6/GP-263b)"
elif [ "${ADV_BLAST_HIGH:-0}" = "1" ]; then
    echo "  ★ blast_radius=highファイル検出。changed_lines<200でもadversarial推奨(GP-265)"
elif [ -z "${TASK_FILE:-}" ] || [ ! -f "${TASK_FILE:-/dev/null}" ]; then
    echo "  SKIP: task YAML不在+非自動化系files_modified"
else
    echo "  PASS: 非自動化系target"
fi

# ─── SG-PRE16: BE impl ゴールデンデータ突合チェック (L-GoldenDataFirst) ───
echo ""
echo "■ SG-PRE16: ゴールデンデータ突合チェック"
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    # §3.2最適化: python3 -c 2回→engine変数参照(TASK_TYPE_BE/HAS_GOLDEN_REF)
    if [ "${TASK_TYPE_BE:-0}" = "1" ]; then
        if [ "${HAS_GOLDEN_REF:-0}" = "0" ]; then
            echo "  ★★★ WARN: BE impl報告にゴールデンデータ突合の記述なし"
            echo "  → 壊れた前後比較ではないか確認せよ(L-GoldenDataFirst)"
            echo "  → docs/research/gunshi_fof_mr_nonlinear_rootcause_20260424.md §8"
        else
            echo "  PASS: ゴールデンデータ突合の記述あり"
        fi
    else
        echo "  SKIP: BE impl/fixタスクではない"
    fi
else
    echo "  SKIP: DM-Signalプロジェクトではない"
fi

# ─── SG-PRE17: AC ID照合(stale AC contamination検出 GP-235) ───
echo ""
echo "■ SG-PRE17: AC ID照合(stale AC検出)"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${CMD_SPEC:-}" ]; then
    # cmdソースからAC IDを抽出
    CMD_AC_IDS=$(echo "$CMD_SPEC" | grep -oP '(?<=id: )AC[0-9]+' | sort -u || true)
    # 報告binary_checksからAC IDを抽出(commitは除外)
    REPORT_AC_IDS=$(awk '/^binary_checks:/{bc=1;next} bc && /^[^ ]/{exit} bc && /^  [A-Z]/{gsub(/:.*$/,"",$0);gsub(/^ +/,"",$0);print}' "$REPORT_PATH" 2>/dev/null | grep -v '^commit$' | sort -u || true)
    if [ -n "$CMD_AC_IDS" ] && [ -n "$REPORT_AC_IDS" ]; then
        STALE_ACS=$(comm -23 <(echo "$REPORT_AC_IDS") <(echo "$CMD_AC_IDS"))
        if [ -n "$STALE_ACS" ]; then
            echo "  ★★★ WARN: stale AC検出! 報告にcmd原本にないAC ID: ${STALE_ACS//$'\n'/, }"
            echo "  → cmd原本AC: ${CMD_AC_IDS//$'\n'/, } / 報告AC: ${REPORT_AC_IDS//$'\n'/, }"
        else
            echo "  PASS: 報告AC IDはcmd原本と一致"
        fi
    else
        echo "  SKIP: AC ID抽出不可(cmd_spec=${#CMD_AC_IDS} report=${#REPORT_AC_IDS})"
    fi
else
    echo "  SKIP: cmd仕様取得不可"
fi

# ─── SG-PRE18: adversarial blast_radius判定 (GP-236) ───
echo ""
echo "■ SG-PRE18: adversarial blast_radius判定(GP-236)"
INFRA_DETECTED=0
INFRA_FILES=""
if [ -n "${FILES_MODIFIED:-}" ]; then
    while IFS= read -r fpath; do
        case "$fpath" in
            *scripts/hooks/*|*scripts/gates/*|*CLAUDE.md|*instructions/*|*.claude/settings*|*config/settings.yaml|*scripts/deploy_task.sh|*scripts/ninja_monitor.sh|*scripts/inbox_write.sh|*scripts/cmd_save.sh|*scripts/cmd_publish.sh|*scripts/cmd_complete_gate.sh|*scripts/report_field_set.sh|*scripts/cmd_quality_log.sh)
                INFRA_FILES="${INFRA_FILES:+$INFRA_FILES, }$fpath"
                INFRA_DETECTED=1
                ;;
        esac
    done <<< "$FILES_MODIFIED"
fi
if [ "$INFRA_DETECTED" -eq 1 ]; then
    echo "  ★★★ WARN: infra対象ファイル検出: ${INFRA_FILES}"
    echo "  → adversarial_review必須。blast_radius大(hook/gate/CLAUDE.md/instructions/settings)"
    echo "  → Red-Team第2パス: 破壊シナリオ・rollback不能性・監視穴を確認せよ"
else
    echo "  PASS: infra対象ファイルなし"
fi

# ─── SG-PRE19: total changed_lines計算 (adversarial観点冷え対策) ───
echo ""
echo "■ SG-PRE19: total changed_lines(adversarial review必要性判定)"
TOTAL_ADDED=0
TOTAL_DELETED=0
_files_modified_trimmed=$(printf '%s\n' "${FILES_MODIFIED:-}" | sed '/^[[:space:]]*$/d' | head -1)
if [ -z "$_files_modified_trimmed" ]; then
    echo "  SKIP: files_modified empty"
elif [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        _changed_counts=$(
            REPORT_HASHES="$_REPORT_HASHES" \
            REPO_ROOT="$REPO_ROOT" \
            IS_DM_SIGNAL="${IS_DM_SIGNAL:-0}" \
            DM_SIGNAL_PATH="${DM_SIGNAL_PATH}" \
            python3 - <<'PY'
import os
import subprocess

repos = [os.environ["REPO_ROOT"]]
_dm_path = os.environ.get("DM_SIGNAL_PATH", "")
if os.environ.get("IS_DM_SIGNAL") == "1" and _dm_path and os.path.isdir(f"{_dm_path}/.git"):
    repos.append(_dm_path)

added_total = 0
deleted_total = 0
for commit_hash in os.environ.get("REPORT_HASHES", "").splitlines():
    commit_hash = commit_hash.strip()
    if not commit_hash:
        continue
    for repo in repos:
        try:
            proc = subprocess.run(
                ["git", "-C", repo, "diff-tree", "--no-commit-id", "--numstat", "-r", commit_hash],
                text=True,
                capture_output=True,
                timeout=2,
                check=False,
            )
        except subprocess.TimeoutExpired:
            continue
        for line in proc.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) < 2 or parts[0] == "-" or parts[1] == "-":
                continue
            try:
                added_total += int(parts[0])
                deleted_total += int(parts[1])
            except ValueError:
                continue
print(f"{added_total} {deleted_total}")
PY
        )
        TOTAL_ADDED="${_changed_counts%% *}"
        TOTAL_DELETED="${_changed_counts##* }"
    else
        # shogunリポジトリ
        while IFS=$'\t' read -r added deleted _; do
            [[ "$added" == "-" ]] && continue
            TOTAL_ADDED=$((TOTAL_ADDED + added))
            TOTAL_DELETED=$((TOTAL_DELETED + deleted))
        done < <(timeout 2 git -C "$REPO_ROOT" log --no-merges --fixed-strings --grep="${PARENT_CMD}" --format="" --numstat 2>/dev/null || true)
        # DM-Signalリポジトリ（プロジェクトがDM-Signalの場合）
        if [ "${IS_DM_SIGNAL:-0}" = "1" ] && [ -d "${DM_SIGNAL_PATH}/.git" ]; then
            while IFS=$'\t' read -r added deleted _; do
                [[ "$added" == "-" ]] && continue
                TOTAL_ADDED=$((TOTAL_ADDED + added))
                TOTAL_DELETED=$((TOTAL_DELETED + deleted))
            done < <(timeout 2 git -C "${DM_SIGNAL_PATH}" log --no-merges --fixed-strings --grep="${PARENT_CMD}" --format="" --numstat 2>/dev/null || true)
        fi
    fi
    TOTAL_CHANGED=$((TOTAL_ADDED + TOTAL_DELETED))
    echo "  changed_lines: +${TOTAL_ADDED}/-${TOTAL_DELETED} = ${TOTAL_CHANGED}"
    if [ "$TOTAL_CHANGED" -ge 200 ]; then
        echo "  ★★★ adversarial_review必須(changed_lines=${TOTAL_CHANGED} >= 200)"
        echo "  → review_logにchanged_lines: ${TOTAL_CHANGED}とadversarial_review:を記録せよ"
    fi
else
    echo "  SKIP: PARENT_CMD未取得"
fi

# ─── SG-PRE20: related_lessons+lessons_useful空検出 (SG7盲点補完) ───
echo ""
echo "■ SG-PRE20: related_lessons+lessons_useful整合"
if [ -f "${TASK_FILE:-}" ]; then
    _rl_count=$(awk '
        /^  related_lessons:/ { sec=1; next }
        sec && /^  [A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
        sec && /^  - id:/ { c++ }
        END { print c+0 }
    ' "$TASK_FILE" 2>/dev/null)
    _lu_count=$(awk '
        /^lessons_useful:/ { sec=1; next }
        sec && /^[A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
        sec && /^[[:space:]]*- id:/ { c++ }
        END { print c+0 }
    ' "$REPORT_PATH" 2>/dev/null)
    if [ "${_rl_count:-0}" -gt 0 ] && [ "${_lu_count:-0}" -eq 0 ]; then
        echo "  WARN: related_lessons ${_rl_count}件注入済みだがlessons_useful空リスト → BLOCK確実"
        ERRORS=$((ERRORS + 1))
    else
        echo "  PASS: related_lessons=${_rl_count} lessons_useful=${_lu_count}"
    fi
else
    echo "  SKIP: task YAML未取得"
fi

# ─── SG-PRE21: 因果辺照合(L7穴1対策: レビュー時の因果消費) ───
echo ""
echo "■ SG-PRE21: 因果辺照合(causal_backlinks)"
if [ -n "${FILES_MODIFIED:-}" ]; then
    _causal_script="$REPO_ROOT/scripts/causal_backlinks.sh"
    if [ -f "$_causal_script" ]; then
        _causal_out=""
        _causal_timeout=0
        for fpath in $FILES_MODIFIED; do
            if is_generated_large_artifact "$fpath"; then
                _causal_out="${_causal_out}  ${fpath}→ SKIP: generated large artifact"$'\n'
                continue
            fi
            _stem=$(basename "$fpath" | sed 's/\.[^.]*$//')
            set +e
            _links=$(timeout 3 bash "$_causal_script" "$_stem" 2>/dev/null)
            _rc=$?
            set -e
            _links=$(printf '%s\n' "$_links" | head -3)
            if [ "$_rc" -eq 124 ]; then
                _causal_timeout=1
                _causal_out="${_causal_out}  ${_stem}→ WARN: causal_backlinks timeout(3s). 手動照合せよ"$'\n'
                continue
            fi
            [ -n "$_links" ] && _causal_out="${_causal_out}  ${_stem}→ ${_links}"$'\n'
        done
        if [ -n "$_causal_out" ]; then
            if [ "$_causal_timeout" -eq 1 ]; then
                echo "  因果辺照合WARN(タイムアウトあり。PASS扱い禁止):"
            else
                echo "  因果辺あり(設計意図カタログ照合せよ):"
            fi
            echo "$_causal_out" | head -10
        else
            echo "  PASS: 因果辺なし(causal_backlinks 0件)"
        fi
    else
        echo "  SKIP: causal_backlinks.sh not found"
    fi
else
    echo "  SKIP: files_modified empty"
fi

# ─── SG-PRE22: semantic概念表示(L7浸透: レビュー時に関連概念を強制表示) ───
echo ""
echo "■ SG-PRE22: semantic関連概念(L7)"
_semantic_script="$REPO_ROOT/scripts/semantic_search.sh"
_purpose=""
if [ -n "${CMD_SPEC:-}" ]; then
    _purpose=$(echo "$CMD_SPEC" | grep 'purpose:' | head -1 | sed 's/.*purpose: *//' | sed 's/"//g')
fi
[ -z "$_purpose" ] && [ -n "${PARENT_CMD:-}" ] && _purpose="$PARENT_CMD"
if [ -f "$_semantic_script" ] && [ -n "${_purpose:-}" ]; then
    set +e
    _sem_result=$(SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 timeout 1 bash "$_semantic_script" "$_purpose" 2>/dev/null)
    _sem_rc=$?
    set -e
    _sem_result=$(printf '%s\n' "$_sem_result" | head -5)
    if [ "$_sem_rc" -eq 124 ]; then
        echo "  WARN: semantic_search timeout(1s). 手動で関連概念を確認せよ"
    elif [ -n "$_sem_result" ]; then
        echo "  関連概念:"
        printf '%s\n' "$_sem_result" | while IFS= read -r _line; do echo "    $_line"; done
    else
        echo "  NO_MATCH: 関連概念なし(aliases候補として蓄積検討)"
    fi
else
    echo "  SKIP: semantic_search.sh not found or purpose empty"
fi

# ─── SG-PRE23: context/*.md変更時のvercel_phase参照切れ検出(GP-264) ───
echo "■ SG-PRE23: vercel_phase参照切れ検出"
_context_files=()
while IFS= read -r _fm_line; do
    case "$_fm_line" in context/*.md*) _context_files+=("$_fm_line");; esac
done < <(echo "$FILES_MODIFIED" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep '^context/.*\.md' || true)
if [ "${#_context_files[@]}" -gt 0 ] && [ -f "$REPO_ROOT/scripts/gates/gate_vercel_phase.sh" ]; then
    if bash "$REPO_ROOT/scripts/gates/gate_vercel_phase.sh" "${_context_files[@]}" 2>/dev/null; then
        echo "  PASS: context変更の参照先は全て実在"
    else
        echo "  [CRITICAL] gate_vercel_phase FAIL — context変更に参照切れあり"
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }vercel_phase:broken_refs"
    fi
else
    echo "  SKIP: context/*.md変更なし or gate_vercel_phase.sh不在"
fi

# ─── SG-PRE24: instructions変更時のgenerated/貫通チェック(GP-265) ───
echo "■ SG-PRE24: generated/貫通チェック"
# instructions正本からrole名を抽出し、対応するgenerated/ファイルの内容貫通を検証
_instr_files=()
while IFS= read -r _if; do
    _instr_files+=("$_if")
done < <(echo "$FILES_MODIFIED" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -E '^instructions/(shogun|karo|gunshi|ashigaru)' || true)
if [ "${#_instr_files[@]}" -gt 0 ] && [ -d "$REPO_ROOT/instructions/generated" ]; then
    _pre24_pass=true
    for _ifile in "${_instr_files[@]}"; do
        _rname=$(echo "$_ifile" | grep -oP '(shogun|karo|gunshi|ashigaru)' | head -1)
        [ -z "$_rname" ] && continue
        # generated/内の対応ファイルを検索
        _gen_files=$(find "$REPO_ROOT/instructions/generated/" -name "*${_rname}*" -type f 2>/dev/null)
        if [ -z "$_gen_files" ]; then
            echo "  ★ BLOCK: ${_ifile}変更だがgenerated/に対応ファイルなし。build_instructions.sh再実行要"
            _pre24_pass=false
            continue
        fi
        _gen_first=$(echo "$_gen_files" | head -1)
        # 判定: marker存在 OR generated commit/mtime が正本以降 → PASS
        _file_pass=false
        # Check 1: marker — 正本diffから代表語句を抽出し、generatedに存在するか
        _marker=$(git diff HEAD~1 -- "$REPO_ROOT/$_ifile" 2>/dev/null | grep '^+[^+]' | grep -v '^+++' | head -5 | sed 's/^+//' | grep -oP '\S{8,}' | head -1 || true)
        if [ -n "$_marker" ] && grep -qF "$_marker" "$_gen_first" 2>/dev/null; then
            echo "  PASS: ${_ifile} → marker「${_marker}」がgenerated/に存在"
            _file_pass=true
        fi
        # Check 2: commit/mtime — generatedのcommitが正本と同一以降か
        if [ "$_file_pass" = false ]; then
            _src_hash=$(timeout 2 git log --format=%H -1 -- "$REPO_ROOT/$_ifile" 2>/dev/null || true)
            _gen_hash=$(echo "$_gen_first" | xargs timeout 2 git log --format=%H -1 -- 2>/dev/null || true)
            if [ -n "$_src_hash" ] && [ -n "$_gen_hash" ]; then
                if [ "$_src_hash" = "$_gen_hash" ]; then
                    # 同一commitで両方更新 → 貫通済み
                    echo "  PASS: ${_ifile} → generated/が同一commitで更新済み"
                    _file_pass=true
                else
                    _src_ts=$(timeout 2 git log --format=%ct -1 -- "$REPO_ROOT/$_ifile" 2>/dev/null || echo 0)
                    _gen_ts=$(echo "$_gen_first" | xargs timeout 2 git log --format=%ct -1 -- 2>/dev/null || echo 0)
                    if [ "$_gen_ts" -ge "$_src_ts" ]; then
                        echo "  PASS: ${_ifile} → generated/が正本以降のcommitで更新済み"
                        _file_pass=true
                    fi
                fi
            fi
        fi
        if [ "$_file_pass" = false ]; then
            echo "  ★ BLOCK: ${_ifile}変更がgenerated/に未反映。build_instructions.sh再実行要"
            [ -n "$_marker" ] && echo "    marker「${_marker}」がgenerated/に不在"
            _pre24_pass=false
        fi
    done
    if ! $_pre24_pass; then
        echo "  ★ generated/未貫通 BLOCK"
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }generated_not_penetrated"
    fi
else
    echo "  SKIP: instructions正本変更なし or generated/不在"
fi

# ─── SG-PRE25: command×files_modified名前照合 (LG036 Step3.5自動化) ───
# readonly_ref除外ロジック: cmd_complete_gate.sh L4204-4312と同一判定
echo ""
echo "■ SG-PRE25: command×files_modified名前照合(LG036)"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${FILES_MODIFIED:-}" ]; then
    _cmd_spec="$REPO_ROOT/queue/shogun_to_karo.yaml"
    if [ -f "$_cmd_spec" ]; then
        _pre25_result=$(bash "$REPO_ROOT/scripts/lib/extract_command_files.sh" \
            --cmd-id "${PARENT_CMD}" \
            --spec "$_cmd_spec" \
            --repo "$REPO_ROOT" \
            --files-modified "${FILES_MODIFIED}" \
            --report "$REPORT_PATH" 2>/dev/null || true)
        # 複数行出力対応: READONLY_EXCLUDED行とWARN/PASS行を分離処理
        _has_warn=0
        _has_readonly=0
        while IFS= read -r _line; do
            case "$_line" in
                PASS*)
                    echo "  PASS: command欄ファイルとfiles_modified名前照合OK(readonly_ref除外済み)"
                    ;;
                WARN:*)
                    echo "  ★★★ ERROR: command欄ファイルがfiles_modifiedに不在(readonly_ref除外後): ${_line#WARN: }"
                    echo "  → verdict: FAILにせよ。gateのcommand_files_modified_mismatchはLG037の3分類を区別できない(殿厳命Step3.5。5件連続LGTM→BLOCK)"
                    _has_warn=1
                    ERRORS=$((ERRORS + 1))
                    ;;
                READONLY_EXCLUDED:*)
                    echo "  INFO: readonly_ref除外済み: ${_line#READONLY_EXCLUDED: }"
                    _has_readonly=1
                    ;;
                SKIP*)
                    echo "  ${_line}"
                    ;;
                *)
                    echo "  ${_line}"
                    ;;
            esac
        done <<< "$_pre25_result"
    else
        echo "  SKIP: shogun_to_karo.yaml不在"
    fi
elif [ "${FM_FORMAT_INVALID:-0}" = "1" ]; then
    # files_modifiedはあるがpath:キーが1件も抽出できない=形式違反(check/result散文等)。
    # 黙ってSKIPするとSG-PRE25素通り→gate mismatch BLOCK(cmd_3274実証 2026-06-10)
    echo "  ★★★ ERROR: files_modifiedにpath:キーが1件もない(形式違反)。gateのcommand_files_modified_mismatchでBLOCKされる"
    echo "  → verdict: FAILにせよ。忍者に path: 形式での再記入を求めよ(report_field_set.sh経由)"
    ERRORS=$((ERRORS + 1))
else
    echo "  SKIP: PARENT_CMD or FILES_MODIFIED empty"
fi

# ─── GATE_PREDICTION (自動計算) ───
# PRE12b draft_lessons補正: engine.pyに未連携のためbash側で上書き
if [ "${_draft_lessons_total:-0}" -gt 0 ]; then
    if [ "${GATE_PREDICTION:-CLEAR}" = "CLEAR" ]; then
        GATE_PREDICTION="WARN"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }draft_lessons:${_draft_lessons_total}件(tasks/lessons.md)"
    fi
fi
# ─── SG-PRE26: 三層記憶検索(殿厳命2026-06-10: 使用しないのはバグ) ───
echo ""
echo "■ SG-PRE26: 三層記憶検索(L0-L7貫通)"
_mem_query="${_purpose:-${PARENT_CMD:-}}"
if [ -n "$_mem_query" ]; then
    _mem_db_script="$REPO_ROOT/scripts/memory_db_query.sh"
    if [ -f "$_mem_db_script" ]; then
        _mem_keywords=$(echo "$_mem_query" | tr ' 　/\n' '\n' | grep -E '.{2,}' | head -3 | tr '\n' ' ')
        _mem_result=""
        _mem_tmpdir=$(mktemp -d /tmp/gunshi_pre26_XXXXXX)
        _mem_i=0
        _mem_pids=()
        for _kw in $_mem_keywords; do
            _mem_i=$((_mem_i + 1))
            bash "$_mem_db_script" "SELECT ts, substr(summary,1,80) FROM events WHERE summary LIKE '%${_kw}%' ORDER BY ts DESC LIMIT 2" > "$_mem_tmpdir/$_mem_i" 2>/dev/null &
            _mem_pids+=("$!")
        done
        for _pid in "${_mem_pids[@]}"; do
            wait "$_pid" || true
        done
        for _f in "$_mem_tmpdir"/*; do
            [ -f "$_f" ] || continue
            _hit=$(head -4 "$_f")
            [ -n "$_hit" ] && _mem_result="${_mem_result}${_hit}"$'\n'
        done
        rm -rf "$_mem_tmpdir"
        if [ -n "$_mem_result" ]; then
            echo "  記憶DB関連エントリ:"
            # 注: ループ本体最後の[ -n ]がfalseだとset -e+pipefailで全体死亡するためelse分岐必須(2026-06-11発見の既存バグ)
            printf '%s\n' "$_mem_result" | head -6 | while IFS= read -r _line; do if [ -n "$_line" ]; then echo "    $_line"; fi; done
            echo "  ★ 上記を[MEM: memory_db ts=YYYY-MM-DD]で引用してレビューに反映せよ"
        else
            echo "  記憶DB: 関連エントリなし(検索キーワード: $_mem_keywords)"
        fi
    else
        echo "  SKIP: memory_db_query.sh not found"
    fi
else
    echo "  SKIP: cmd purpose/id empty"
fi

# ─── SG-PRE27: verify系関数evidence検出(LG040: 検証関数は単体実行で検証せよ) ───
# cmd_3275: verify_sheets()がranges配列バグで常時Falseなのにevidence「一致確認」記載。
# 関数呼出形に限定した有界パターン(LG039: 無制限マッチの貪欲FP防止)
echo ""
echo "■ SG-PRE27: verify系関数evidence検出(LG040)"
_verify_fns=$(grep -oE '\b(verify|validate|readback|parity)_[a-z_]{1,40}\(' "$REPORT_PATH" 2>/dev/null | sort -u | head -5 || true)
if [ -n "$_verify_fns" ]; then
    echo "  INFO: 報告に検証関数の呼出evidenceあり:"
    printf '%s\n' "$_verify_fns" | while IFS= read -r _fn; do if [ -n "$_fn" ]; then echo "    - ${_fn})"; fi; done
    echo "  ★ LG040: 当該関数を自分で単体実行し戻り値を確認せよ。evidenceの「一致確認」は関数が動く証明ではない(cmd_3275実証)"
else
    echo "  OK: verify系関数evidenceなし(対象外確認済み)"
fi

# ─── SG-PRE28: 正直報告×AC本旨照合リマインダー(LG044: 正直報告はAC未達の免罪符ではない) ───
echo ""
echo "■ SG-PRE28: 正直報告×AC本旨照合(LG044)"
_has_assumption_inv=$(grep -c 'assumption_invalidation:' "$REPORT_PATH" 2>/dev/null || true)
_assumption_found=$(grep -A1 'assumption_invalidation:' "$REPORT_PATH" 2>/dev/null | grep -c 'found: true' || true)
_has_decision_cand=$(grep -c 'decision_candidate:' "$REPORT_PATH" 2>/dev/null || true)
_decision_found=$(grep -A1 'decision_candidate:' "$REPORT_PATH" 2>/dev/null | grep -c 'found: true' || true)
_has_with_concerns=$(grep -ci 'WITH_CONCERNS\|status_detail.*PARTIAL\|status_detail.*INCOMPLETE' "$REPORT_PATH" 2>/dev/null || true)
if [ "${_assumption_found:-0}" -gt 0 ] || [ "${_decision_found:-0}" -gt 0 ] || [ "${_has_with_concerns:-0}" -gt 0 ]; then
    echo "  INFO: 正直報告フラグ検出(assumption_invalidation/decision_candidate/WITH_CONCERNS)"
    echo "  ★ LG044: AC本文の要求語(名詞句)がresult/detailsに実体として出ているか1対1照合せよ"
    echo "  ★ 正直な懸念報告は評価材料であって免罪符ではない。AC未達ならFAIL/REQUEST_CHANGES"
else
    echo "  PASS: 正直報告フラグなし(通常レビュー)"
fi

# ─── SG-PRE29: FE変更時Next build確認リマインダー(LG045: pytest/JestだけではApp Router制約を検出できない) ───
echo ""
echo "■ SG-PRE29: FE変更×Next build確認(LG045)"
_fe_files=$(grep -A50 'files_modified:' "$REPORT_PATH" 2>/dev/null | grep -E 'frontend/|\.tsx|\.ts' | grep -v '#' || true)
if [ -n "$_fe_files" ]; then
    _has_build_mention=$(grep -ci 'npm run build\|next build' "$REPORT_PATH" 2>/dev/null || true)
    _has_build_fail=$(grep -ci 'build.*\(FAIL\|failed\|error\)\|\(FAIL\|failed\|error\).*build' "$REPORT_PATH" 2>/dev/null || true)
    _has_build_pass=$(grep -ci 'build.*\(PASS\|passed\|succeeded\|success\)\|\(PASS\|passed\|succeeded\|success\).*build' "$REPORT_PATH" 2>/dev/null || true)
    if [ "${_has_build_mention:-0}" -eq 0 ]; then
        echo "  WARN: files_modifiedにfrontend配下あり。npm run build/next build確認が報告に見当たらない"
        echo "  ★ LG045: pytest/JestだけではApp Router page export制約を検出できない。build確認せよ"
    elif [ "${_has_build_fail:-0}" -gt 0 ]; then
        echo "  WARN: build失敗記載あり(FAIL/failed/error)。build PASSを確認せよ"
        echo "  ★ LG045: build失敗報告はLGTM不可"
    elif [ "${_has_build_pass:-0}" -gt 0 ]; then
        echo "  PASS: frontend変更あり+build PASS記載あり"
    else
        echo "  INFO: build言及あるが成否不明。PASS/succeeded/FAIL/failed語を確認せよ"
    fi
else
    echo "  PASS: frontend変更なし(対象外)"
fi

# ─── SG-PRE30: daemon lib-only再利用時グローバル変数列挙リマインド(LG046) ───
# 関数化: テストから呼出し可能にする
_sg_pre30_check() {
    local report_path="$1"
    # files_modifiedブロックのみ抽出(次のトップレベルキーで停止)
    local _fm_block
    _fm_block=$(awk '/^files_modified:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    local _daemon_files
    _daemon_files=$(echo "$_fm_block" | grep -iE 'ninja_monitor|ntfy_listener|inbox_watcher|dashboard_auto' | grep -v '#' || true)
    local _lib_only_mention
    _lib_only_mention=$(grep -ciE 'LIB_ONLY|source.*\.sh|lib.only' "$report_path" 2>/dev/null || true)
    if [ -n "$_daemon_files" ] || [ "${_lib_only_mention:-0}" -gt 0 ]; then
        echo "  INFO: daemonスクリプト変更またはlib-only/source再利用を検出"
        echo "  ★ LG046: 対象関数のグローバル変数を grep -oE '\$[A-Z_][A-Z0-9_]*|\$\{[A-Z_][A-Z0-9_]*' で機械列挙し、"
        echo "    daemon初期化ブロック外でも初期化されるか/\${VAR:-}を持つか突合せよ"
        echo "    部分列挙や目視でLGTMしない(bb140170d hotfix 2本の再発防止)"
    else
        echo "  PASS: daemon/lib-only変更なし(対象外)"
    fi
}
echo ""
echo "■ SG-PRE30: daemon lib-only再利用(LG046)"
_sg_pre30_check "$REPORT_PATH"

# ─── SG-PRE31: N×M一致パターン意味検算リマインド(LG048: きれいな数値一致は意味検算のサイン) ───
_sg_pre31_check() {
    local report_path="$1"
    # resultブロックから数値を抽出（整数のみ、10以上の値）
    local _result_block
    _result_block=$(awk '/^result:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    if [ -z "$_result_block" ]; then
        echo "  SKIP: resultブロックなし"
        return
    fi
    # 3以上の整数を抽出（重複排除・ソート。1,2は偽陽性が多すぎるため除外）
    # 先頭0の数字列を除外(bashが8進数として解釈しエラーになるため。commitハッシュ断片等)
    # テスト結果行(passed/failed/skipped/suites/tests)を除外(FP防止: 33 passed×3=99等)
    local _nums
    _nums=$(echo "$_result_block" | grep -viE 'passed|failed|skipped|suites|tests|PASS|FAIL' | grep -oE '[0-9]+' | grep -v '^0[0-9]' | awk '$1 >= 3' | sort -un || true)
    local _num_count
    _num_count=$(echo "$_nums" | grep -c '[0-9]' || true)
    if [ "${_num_count:-0}" -lt 3 ]; then
        echo "  PASS: 数値3個未満(N×M照合対象外)"
        return
    fi
    # N×M=Cの関係を探索
    local _found=0
    local _a _b _c
    while IFS= read -r _a; do
        [ -z "$_a" ] && continue
        while IFS= read -r _b; do
            [ -z "$_b" ] && continue
            [ "$_b" -le "$_a" ] && continue
            _c=$(( _a * _b )) || true
            if echo "$_nums" | grep -qx "$_c" 2>/dev/null; then
                echo "  INFO(LG048): N×M一致検出: ${_a}×${_b}=${_c}"
                echo "  ★ 意味検算せよ: この整数関係は仕様上の分類(PF種別/trigger別/月別等)と整合するか？"
                echo "    全件一律の数値は過剰集約や分類漏れの兆候。内訳を再計算して確認せよ"
                _found=1
            fi
        done <<< "$_nums"
    done <<< "$_nums"
    if [ "$_found" -eq 0 ]; then
        echo "  PASS: N×M一致パターンなし"
    fi
}
echo ""
echo "■ SG-PRE31: N×M意味検算(LG048)"
_sg_pre31_check "$REPORT_PATH"

# ─── SG-PRE32: 視点列間の全行一致検出(LG049: 独立視点の縮退検出) ───
# 関数化: テストから呼出し可能にする
_sg_pre32_check() {
    local files_modified_text="${1:-}"
    local project_dir="${2:-$PROJECT_DIR}"
    local repo_root="${3:-$REPO_ROOT}"
    local detector="$repo_root/scripts/lib/detect_view_column_degeneracy.py"

    if [ -z "$files_modified_text" ]; then
        echo "  PASS: files_modified空(対象外)"
        return
    fi
    if [ ! -f "$detector" ]; then
        echo "  WARN(LG049): detector missing: $detector"
        return
    fi

    local _found_md=0
    local _found_warn=0
    local _path _full_path _detected
    while IFS= read -r _path; do
        _path="$(echo "$_path" | sed 's/.*path: *//' | tr -d "'\"" | sed 's/^[[:space:]-]*//;s/[[:space:]]*$//')"
        [ -z "$_path" ] && continue
        case "$_path" in
            *.md|*.markdown) ;;
            *) continue ;;
        esac
        _found_md=1
        _full_path="$project_dir/$_path"
        if [ ! -f "$_full_path" ]; then
            _full_path="$repo_root/$_path"
        fi
        if [ ! -f "$_full_path" ]; then
            continue
        fi
        _detected="$(python3 "$detector" "$_full_path" 2>/dev/null || true)"
        if [ -n "$_detected" ]; then
            echo "  WARN(LG049): $_path"
            echo "$_detected" | sed 's/^/    /'
            echo "    → 視点列が全データ行で一致。Expanding/WF等の独立算出が同一系列へ縮退していないか確認せよ"
            _found_warn=1
        fi
    done <<< "$files_modified_text"

    if [ "$_found_warn" -eq 0 ]; then
        if [ "$_found_md" -eq 0 ]; then
            echo "  PASS: Markdown成果物なし(対象外)"
        else
            echo "  PASS: 視点列間の全行一致なし"
        fi
    fi
}
echo ""
echo "■ SG-PRE32: 視点列間一致検出(LG049)"
_sg_pre32_check "${FILES_MODIFIED:-}" "$PROJECT_DIR" "$REPO_ROOT"

echo ""
echo "■ GATE_PREDICTION (自動計算 — SG7 gate_predictionに転記せよ)"
echo "  prediction: ${GATE_PREDICTION:-UNKNOWN}"
echo "  reason: ${GATE_PREDICTION_REASON:-engine未実行}"
if [ "${GATE_PREDICTION:-}" = "WARN" ] || [ "${GATE_PREDICTION:-}" = "BLOCK" ]; then
    echo "  ★★★ gate_prediction: ${GATE_PREDICTION} をSG7バンドルに転記必須"
fi

# ─── 出力フォールバックERRORカウント(cmd定義消失時のSG-PRE25 ERROR見逃し防止) ───
# SG-PRE25等がERROR行を出力したがERROR変数が加算されなかったケースを捕捉
_output_errors=$(echo "${_pre25_result:-}" | grep -c '^WARN:' || true)
if [ "${_output_errors:-0}" -gt 0 ] && [ "$ERRORS" -eq 0 ]; then
    ERRORS=$((_output_errors))
    echo "★ フォールバックERROR検出: SG-PRE25出力にWARN ${_output_errors}件だがERRORS未加算だった"
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
