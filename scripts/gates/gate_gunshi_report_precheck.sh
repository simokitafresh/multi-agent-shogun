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
    PROJECT_DIR="/mnt/c/Python_app/DM-Signal"
else
    PROJECT_DIR="/mnt/c/tools/multi-agent-shogun"
fi

print_sg_pre9() {
    echo ""
    echo "■ SG-PRE9: T1違反予防(binary_checks no検出)"
    if [ "${BC_HAS_NO:-0}" = "1" ]; then
        echo "  ★★★ WARN: binary_checks result:no検出: ${BC_NO_ITEMS}"
        if [ "${TEST_TRIAGE:-}" = "pre_existing" ]; then
            echo "  → test_triage=pre_existing: gate WARN降格でCLEAR見込み(cmd_2339実証)"
            echo "  → gate_prediction: WARN(BLOCK→降格)"
        else
            echo "  → gate_prediction: BLOCK固定(waive_reasonがあっても免除なし)"
        fi
        echo "  → GP-128: verdict PASS + result:no → gate機械的BLOCK"
        echo "  → 見落とし実績: cmd_1897, cmd_1900, cmd_2093 (T1違反3回)"
    else
        echo "  PASS: binary_checks全result:yes (or検出対象なし)"
    fi
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
_REPORT_HASHES=$(grep -oiP '(?:commit|commit_hash:)\s*\K[0-9a-f]{7,12}' "$REPORT_PATH" 2>/dev/null | sort -u || true)
if [ -n "${FILES_MODIFIED:-}" ] && [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        # PRE3/PRE14: report記載hashがあれば広域git logを避ける(WSL2 NTFS対策)
        while IFS= read -r _hash; do
            [ -z "$_hash" ] && continue
            _PRE_CMD_FILES+="$(
                cd "${PROJECT_DIR:-$REPO_ROOT}" \
                    && timeout 2 git diff-tree --no-commit-id --name-only -r "$_hash" 2>/dev/null
            )"$'\n'
            _PRE_RECENT_DATA+="$(
                cd "$REPO_ROOT" \
                    && git show --oneline --name-only "$_hash" 2>/dev/null
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
    while IFS= read -r fpath; do
        case "$fpath" in
            *.claude/hooks/*|*scripts/hooks/*|*scripts/gates/*)
                # git diff --statで変更規模を確認 (1回のgit log で added+deleted を同時取得)
                read -r added deleted < <(
                    { timeout 2 git -C "$REPO_ROOT" log --grep="${PARENT_CMD}" --format="" --numstat -- "$fpath" 2>/dev/null || true; } | \
                    awk '{a+=$1; d+=$2} END{print a+0, d+0}'
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
BUSY_NINJAS=$(awk '
    /^[[:space:]]*status:/ {
        st=$2; gsub(/["'"'"']/, "", st)
        if (st=="in_progress" || st=="acknowledged") busy++
        nextfile
    }
    END{print busy+0}
' "$REPO_ROOT"/queue/tasks/{hayate,kagemaru,hanzo,saizo,kotaro,tobisaru}.yaml 2>/dev/null || echo 0)
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
if [ -n "${TASK_FILE:-}" ] && [ -f "${TASK_FILE}" ]; then
    _adv_target=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('${TASK_FILE}'))
    t = d.get('task', {})
    tp = str(t.get('target_path', ''))
    if any(k in tp for k in ['scripts/', '.sh', 'gate_', 'hook_', 'monitor', 'cron', 'cleanup']):
        print('automation')
except OSError: pass
" || true)
    if [ "$_adv_target" = "automation" ]; then
        echo "  ★ target_pathが自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6)"
    else
        # フォールバック: target_path未設定時はfiles_modifiedからscripts/パスを検出(GP-263b)
        _adv_fm=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('${REPORT_PATH}'))
    fm = d.get('files_modified', [])
    for f in (fm or []):
        p = str(f.get('path', '') if isinstance(f, dict) else f)
        if any(k in p for k in ['scripts/', '.sh', 'gate_', 'hook_', 'monitor', 'cron', 'cleanup']):
            print('automation'); break
except: pass
" 2>/dev/null || true)
        if [ "$_adv_fm" = "automation" ]; then
            echo "  ★ files_modifiedに自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6/GP-263b)"
        else
            # blast_radius=high判定: 全cmd影響ファイルはchanged_lines < 200でもadversarial推奨(GP-265)
            _adv_blast=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('${REPORT_PATH}'))
    fm = d.get('files_modified', [])
    HIGH_BLAST = ['deploy_task.sh', 'CLAUDE.md', 'ninja_monitor.sh', 'inbox_write.sh', 'cmd_complete_gate.sh']
    for f in (fm or []):
        p = str(f.get('path', '') if isinstance(f, dict) else f)
        if any(h in p for h in HIGH_BLAST) or p.startswith('instructions/'):
            print('high'); break
except: pass
" 2>/dev/null || true)
            if [ "$_adv_blast" = "high" ]; then
                echo "  ★ blast_radius=highファイル検出。changed_lines<200でもadversarial推奨(GP-265)"
            else
                echo "  PASS: 非自動化系target"
            fi
        fi
    fi
else
    # TASK_FILE不在でもfiles_modified+blast_radiusで判定(GP-265拡張)
    _adv_fm_notp=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('${REPORT_PATH}'))
    fm = d.get('files_modified', [])
    HIGH_BLAST = ['deploy_task.sh', 'CLAUDE.md', 'ninja_monitor.sh', 'inbox_write.sh', 'cmd_complete_gate.sh']
    for f in (fm or []):
        p = str(f.get('path', '') if isinstance(f, dict) else f)
        if any(k in p for k in ['scripts/', '.sh', 'gate_', 'hook_', 'monitor', 'cron', 'cleanup']):
            print('automation'); break
        if any(h in p for h in HIGH_BLAST) or p.startswith('instructions/'):
            print('high'); break
except: pass
" 2>/dev/null || true)
    if [ "$_adv_fm_notp" = "automation" ]; then
        echo "  ★ files_modifiedに自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6/GP-263b)"
    elif [ "$_adv_fm_notp" = "high" ]; then
        echo "  ★ blast_radius=highファイル検出。changed_lines<200でもadversarial推奨(GP-265)"
    else
        echo "  SKIP: task YAML不在+非自動化系files_modified"
    fi
fi

# ─── SG-PRE16: BE impl ゴールデンデータ突合チェック (L-GoldenDataFirst) ───
echo ""
echo "■ SG-PRE16: ゴールデンデータ突合チェック"
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    # target_pathにbackendを含むimpl/fixか判定
    TASK_TYPE=""
    if [ -n "${TASK_FILE:-}" ] && [ -f "${TASK_FILE}" ]; then
        TASK_TYPE=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('${TASK_FILE}'))
    t = d.get('task', {})
    tp = str(t.get('target_path', ''))
    tt = str(t.get('task_type', ''))
    if 'backend' in tp and tt in ('impl', 'fix'):
        print('be_impl')
except OSError: pass
" || true)
    fi
    if [ "$TASK_TYPE" = "be_impl" ]; then
        # 報告のdetails/summaryにgolden/snapshot/ゴールデン/パリティの記述があるか
        HAS_GOLDEN=$(python3 -c "
import yaml, re, sys
try:
    d = yaml.safe_load(open('${REPORT_PATH}'))
    texts = str(d.get('result', {}).get('summary', '')) + str(d.get('result', {}).get('details', ''))
    pat = re.compile(r'golden|snapshot.*比較|ゴールデン|golden\.json|パリティ.*diff.*0|parity.*diff.*0', re.I)
    print('yes' if pat.search(texts) else 'no')
except: print('no')
" 2>/dev/null || echo "no")
        if [ "$HAS_GOLDEN" = "no" ]; then
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
if [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        _changed_counts=$(
            REPORT_HASHES="$_REPORT_HASHES" \
            REPO_ROOT="$REPO_ROOT" \
            IS_DM_SIGNAL="${IS_DM_SIGNAL:-0}" \
            python3 - <<'PY'
import os
import subprocess

repos = [os.environ["REPO_ROOT"]]
if os.environ.get("IS_DM_SIGNAL") == "1" and os.path.isdir("/mnt/c/Python_app/DM-Signal/.git"):
    repos.append("/mnt/c/Python_app/DM-Signal")

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
        done < <(git -C "$REPO_ROOT" log --no-merges --grep="${PARENT_CMD}" --format="" --numstat 2>/dev/null || true)
        # DM-Signalリポジトリ（プロジェクトがDM-Signalの場合）
        if [ "${IS_DM_SIGNAL:-0}" = "1" ] && [ -d "/mnt/c/Python_app/DM-Signal/.git" ]; then
            while IFS=$'\t' read -r added deleted _; do
                [[ "$added" == "-" ]] && continue
                TOTAL_ADDED=$((TOTAL_ADDED + added))
                TOTAL_DELETED=$((TOTAL_DELETED + deleted))
            done < <(git -C "/mnt/c/Python_app/DM-Signal" log --no-merges --grep="${PARENT_CMD}" --format="" --numstat 2>/dev/null || true)
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
    _rl_count=$(grep -c '^\s*- id:' <(sed -n '/^  related_lessons:/,/^  [^ ]/p' "$TASK_FILE") 2>/dev/null || echo 0)
    _lu_count=$(grep -c '^\s*- id:' <(sed -n '/^lessons_useful:/,/^[^ ]/p' "$REPORT_PATH") 2>/dev/null || echo 0)
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
            _src_hash=$(git log --format=%H -1 -- "$REPO_ROOT/$_ifile" 2>/dev/null || true)
            _gen_hash=$(echo "$_gen_first" | xargs git log --format=%H -1 -- 2>/dev/null || true)
            if [ -n "$_src_hash" ] && [ -n "$_gen_hash" ]; then
                if [ "$_src_hash" = "$_gen_hash" ]; then
                    # 同一commitで両方更新 → 貫通済み
                    echo "  PASS: ${_ifile} → generated/が同一commitで更新済み"
                    _file_pass=true
                else
                    _src_ts=$(git log --format=%ct -1 -- "$REPO_ROOT/$_ifile" 2>/dev/null || echo 0)
                    _gen_ts=$(echo "$_gen_first" | xargs git log --format=%ct -1 -- 2>/dev/null || echo 0)
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
        # python: command欄からファイルパスを抽出し、readonly_ref除外後にfiles_modifiedと照合
        _pre25_result=$(python3 - "$_cmd_spec" "${PARENT_CMD}" "${FILES_MODIFIED}" "$REPO_ROOT" <<'PYEOF'
import yaml, re, sys, os, glob
try:
    spec_file, cmd_id, fm_raw, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    # shogun_to_karo.yaml (active)
    cmd_text = ''
    with open(spec_file) as f:
        d = yaml.safe_load(f) or {}
    cmds = d.get('commands', {}) or {}
    spec = cmds.get(cmd_id, {})
    if spec:
        cmd_text = spec.get('command', '')
    # fallback: archive
    if not cmd_text:
        for p in sorted(glob.glob(os.path.join(repo, 'queue', 'archive', 'cmds', f'{cmd_id}*.yaml')), reverse=True):
            with open(p) as f:
                ad = yaml.safe_load(f) or {}
            acmds = ad.get('commands', {}) or {}
            aspec = acmds.get(cmd_id, {}) or {}
            cmd_text = aspec.get('command', '')
            if cmd_text:
                break
    if not cmd_text:
        print('SKIP: command欄なし')
        sys.exit(0)

    # ── readonly_ref判定 (cmd_complete_gate.sh L4204-4312と同一ロジック) ──
    pattern = re.compile(
        r"(?<![A-Za-z0-9_./-])"
        r"((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+"
        r"\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv))"
        r"(?![A-Za-z0-9_.-])"
    )
    read_markers = (
        "読む", "読んで", "読み", "確認", "参照", "調査", "精査", "review", "read", "inspect", "refer",
        "実行", "実行のみ", "変更対象外", "走らせ", "検証", "run", "execute",
    )
    write_markers = (
        "修正", "更新", "変更", "編集", "実装", "追加", "削除", "作成", "反映",
        "modify", "update", "edit", "add", "remove", "delete", "create", "write", "implement",
    )

    def marker_pos(text, markers):
        positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
        return min(positions) if positions else -1

    matches = list(pattern.finditer(cmd_text))
    seen = set()
    write_refs = []
    readonly_refs = []
    for idx, match in enumerate(matches):
        ref = match.group(1).strip().strip("`'\".,:;()[]{}")
        if not ref or ref in seen:
            continue
        seen.add(ref)
        sentence_end_candidates = [
            pos for pos in (
                cmd_text.find("\n", match.end()),
                cmd_text.find("。", match.end()),
                cmd_text.find("；", match.end()),
                cmd_text.find(";", match.end()),
            )
            if pos >= 0
        ]
        sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(cmd_text)
        next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
        local = cmd_text[match.end():next_file_start]
        sentence_tail = cmd_text[match.end():sentence_end]
        read_pos = marker_pos(local, read_markers)
        if read_pos < 0:
            read_pos = marker_pos(sentence_tail, read_markers)
        write_pos = marker_pos(sentence_tail, write_markers)
        next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (
            write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos
        )
        is_readonly = read_pos >= 0 and (write_pos < 0 or read_pos < write_pos) and (
            write_pos < 0 or next_ref_before_write
        )
        base = os.path.basename(ref)
        if is_readonly:
            readonly_refs.append(base)
        else:
            write_refs.append(base)

    fm_bases = set(os.path.basename(p.strip()) for p in fm_raw.split('\n') if p.strip())
    unmatched = sorted(set(write_refs) - fm_bases)

    lines = []
    if readonly_refs:
        lines.append('READONLY_EXCLUDED: ' + ' '.join(sorted(set(readonly_refs))))
    if unmatched:
        lines.append('WARN: ' + ' '.join(unmatched))
    else:
        lines.append('PASS')
    print('\n'.join(lines))
except Exception as e:
    print(f'SKIP: {e}')
PYEOF
)
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
echo ""
echo "■ GATE_PREDICTION (自動計算 — SG7 gate_predictionに転記せよ)"
echo "  prediction: ${GATE_PREDICTION:-UNKNOWN}"
echo "  reason: ${GATE_PREDICTION_REASON:-engine未実行}"
if [ "${GATE_PREDICTION:-}" = "WARN" ] || [ "${GATE_PREDICTION:-}" = "BLOCK" ]; then
    echo "  ★★★ gate_prediction: ${GATE_PREDICTION} をSG7バンドルに転記必須"
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
