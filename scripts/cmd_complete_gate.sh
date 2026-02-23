#!/bin/bash
# cmd_complete_gate.sh — cmd完了時の全ゲートフラグ確認スクリプト（ディレクトリ方式）
# Usage: bash scripts/cmd_complete_gate.sh <cmd_id>
# Exit 0: GATE CLEAR (全ゲートdone、または緊急override)
# Exit 1: GATE BLOCK (未完了フラグあり)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="${1:-}"

if [ -z "$CMD_ID" ]; then
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: 第1引数はcmd_id（cmd_XXX形式）でなければならない。" >&2
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
LOG_DIR="$SCRIPT_DIR/logs"
GATE_METRICS_LOG="$LOG_DIR/gate_metrics.log"
mkdir -p "$GATES_DIR" "$LOG_DIR"

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local lock_file="${YAML_FILE}.lock"

    (
        flock -w 10 200 || { echo "ERROR: flock取得失敗 (${cmd_id})" >&2; return 1; }

        if sed -n "/^  - id: ${cmd_id}$/,/^  - id: /p" "$YAML_FILE" | grep -q "^    status: completed"; then
            echo "STATUS ALREADY COMPLETED: ${cmd_id} (skip)"
            return 0
        fi

        sed -i "/^  - id: ${cmd_id}$/,/^  - id: /{s/    status: pending/    status: completed/}" "$YAML_FILE"

        echo "STATUS UPDATED: ${cmd_id} → completed"
    ) 200>"$lock_file"
}

# ─── changelog自動記録関数 ───
append_changelog() {
    local cmd_id="$1"
    local changelog="$SCRIPT_DIR/queue/completed_changelog.yaml"
    local completed_at
    completed_at=$(date '+%Y-%m-%dT%H:%M:%S')

    # shogun_to_karo.yamlから該当cmdのpurposeとprojectを抽出
    local purpose
    purpose=$(awk -v id="  - id: ${cmd_id}" '
        $0 == id { found=1; next }
        found && /^  - id:/ { exit }
        found && /^    purpose:/ { sub(/^    purpose: *"?/, ""); sub(/"$/, ""); print; exit }
    ' "$YAML_FILE")

    local project
    project=$(awk -v id="  - id: ${cmd_id}" '
        $0 == id { found=1; next }
        found && /^  - id:/ { exit }
        found && /^    project:/ { sub(/^    project: */, ""); print; exit }
    ' "$YAML_FILE")

    if [ -z "$purpose" ]; then
        echo "CHANGELOG WARNING: purpose not found for ${cmd_id}"
        return 0
    fi
    [ -z "$project" ] && project="unknown"

    # ファイルが無ければヘッダ作成
    if [ ! -f "$changelog" ]; then
        echo "entries:" > "$changelog"
    fi

    # エントリ追記
    cat >> "$changelog" <<EOF
  - id: ${cmd_id}
    project: ${project}
    purpose: "${purpose}"
    completed_at: "${completed_at}"
EOF

    # 20件超なら古い順に剪定（各エントリ=4行、ヘッダ=1行）
    local entry_count
    entry_count=$(grep -c '^  - id:' "$changelog" 2>/dev/null || echo 0)
    if [ "$entry_count" -gt 20 ]; then
        { head -1 "$changelog"; tail -n 80 "$changelog"; } > "${changelog}.tmp"
        mv "${changelog}.tmp" "$changelog"
    fi

    echo "CHANGELOG: ${cmd_id} recorded (project=${project})"
}

# ─── task_type検出: タスクYAMLからparent_cmd一致のtask_typeを収集 ───
detect_task_types() {
    local cmd_id="$1"
    local has_recon=false
    local has_implement=false

    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        # parent_cmdが一致するか確認
        if grep -q "parent_cmd: ${cmd_id}" "$task_file" 2>/dev/null; then
            local ttype
            ttype=$(grep 'task_type:' "$task_file" 2>/dev/null | head -1 | sed 's/.*task_type: *//' | tr -d '[:space:]')
            case "$ttype" in
                recon) has_recon=true ;;
                implement) has_implement=true ;;
            esac
        fi
    done

    # 結果を標準出力に返す（スペース区切り）
    echo "${has_recon} ${has_implement}"
}

# ─── BLOCK理由収集 ───
record_block_reason() {
    local reason="$1"
    if [ -n "$reason" ]; then
        BLOCK_REASONS+=("$reason")
    fi
}

# ─── 必須フラグ構築 ───
ALWAYS_REQUIRED=("archive" "lesson")

# task_type検出
read -r HAS_RECON HAS_IMPLEMENT <<< "$(detect_task_types "$CMD_ID")"

CONDITIONAL=()
if [ "$HAS_RECON" = "true" ]; then
    CONDITIONAL+=("report_merge")
fi
if [ "$HAS_IMPLEMENT" = "true" ]; then
    CONDITIONAL+=("review_gate")
fi

ALL_GATES=("${ALWAYS_REQUIRED[@]}" "${CONDITIONAL[@]}")

# ─── 忍者報告からlesson_candidate自動draft登録 ───
echo "Auto-draft lesson candidates:"
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi
    ninja_name=$(basename "$task_file" .yaml)
    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    if [ -f "$report_file" ]; then
        if bash "$SCRIPT_DIR/scripts/auto_draft_lesson.sh" "$report_file" 2>&1; then
            true
        else
            echo "  WARN: auto_draft_lesson.sh failed for ${ninja_name} (non-blocking)"
        fi
    else
        echo "  ${ninja_name}: no report file"
    fi
done
echo ""

# ─── 緊急override確認 ───
if [ -f "$GATES_DIR/emergency.override" ]; then
    echo "GATE CLEAR (緊急override): ${CMD_ID}の全ゲートをバイパス"
    for gate in "${ALL_GATES[@]}"; do
        echo "  ${gate}: OVERRIDE"
    done
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  WARN: gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID"
    append_changelog "$CMD_ID"
    exit 0
fi

# ─── 各フラグの状態確認 ───
MISSING_GATES=()
BLOCK_REASONS=()
ALL_CLEAR=true

echo "Gate check: ${CMD_ID}"
echo "  Required: ${ALL_GATES[*]}"
if [ ${#CONDITIONAL[@]} -gt 0 ]; then
    echo "  Conditional: ${CONDITIONAL[*]} (task_type: recon=${HAS_RECON}, implement=${HAS_IMPLEMENT})"
fi
echo ""

for gate in "${ALL_GATES[@]}"; do
    done_file="$GATES_DIR/${gate}.done"

    if [ -f "$done_file" ]; then
        detail=$(head -1 "$done_file" 2>/dev/null)
        if [ -n "$detail" ]; then
            echo "  ${gate}: DONE (${detail})"
        else
            echo "  ${gate}: DONE"
        fi
    else
        echo "  ${gate}: MISSING ← 未完了"
        MISSING_GATES+=("$gate")
        record_block_reason "missing_gate:${gate}"
        ALL_CLEAR=false
    fi
done

# ─── related_lessons存在チェック（deploy_task.sh経由確認） ───
echo ""
echo "Related lessons injection check:"
RL_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    RL_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)

    has_rl_key=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    print('yes' if 'related_lessons' in task else 'no')
except:
    print('error')
" 2>/dev/null)

    if [ "$has_rl_key" = "yes" ]; then
        echo "  ${ninja_name}: OK (related_lessons present)"
    elif [ "$has_rl_key" = "no" ]; then
        echo "  ${ninja_name}: WARN ← related_lessonsキー欠落（deploy_task.sh経由でない可能性）"
    else
        echo "  ${ninja_name}: WARN ← related_lessons解析エラー"
    fi
done
if [ "$RL_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lesson_referenced検証（related_lessonsあり→報告にlesson_referenced必須） ───
echo ""
echo "Lesson referenced check:"
LESSON_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    # related_lessonsの有無をチェック（空リスト[]やnullは除外）
    has_lessons=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    rl = task.get('related_lessons', [])
    print('yes' if rl and len(rl) > 0 else 'no')
except:
    print('no')
" 2>/dev/null)

    if [ "$has_lessons" = "yes" ]; then
        LESSON_CHECKED=true
        ninja_name=$(basename "$task_file" .yaml)
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"

        if [ -f "$report_file" ]; then
            if grep -q 'lesson_referenced:' "$report_file" 2>/dev/null; then
                echo "  ${ninja_name}: OK (lesson_referenced present)"
            else
                echo "  ${ninja_name}: NG ← related_lessonsあり、lesson_referencedフィールド欠落"
                record_block_reason "${ninja_name}:missing_lesson_referenced"
                ALL_CLEAR=false
            fi
        else
            echo "  ${ninja_name}: SKIP (report not found)"
        fi
    fi
done
if [ "$LESSON_CHECKED" = false ]; then
    echo "  (no tasks with related_lessons for this cmd)"
fi

# ─── reviewed:false残存チェック（教訓確認の強制） ───
echo ""
echo "Lesson reviewed check:"
REVIEWED_OK=true
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    unreviewed=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    rl = task.get('related_lessons', [])
    if not rl:
        sys.exit(0)
    unrev = [l.get('id','?') for l in rl if l.get('reviewed') == False]
    if unrev:
        print(','.join(unrev))
except:
    pass
" 2>/dev/null)

    ninja_name=$(basename "$task_file" .yaml)
    if [ -n "$unreviewed" ]; then
        echo "  ${ninja_name}: NG ← reviewed:false残存 [${unreviewed}]"
        record_block_reason "${ninja_name}:unreviewed_lessons:${unreviewed}"
        REVIEWED_OK=false
        ALL_CLEAR=false
    else
        echo "  ${ninja_name}: OK (all reviewed)"
    fi
done
if [ "$REVIEWED_OK" = true ]; then
    echo "  (all lessons reviewed or no lessons)"
fi

# ─── lesson_candidate検証（found:trueなのに未登録を防止） ───
echo ""
echo "Lesson candidate check:"
LC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    LC_CHECKED=true

    # lesson_candidateフィールドの検証
    lc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    lc = data.get('lesson_candidate')
    if lc is None:
        print('missing')
    elif not isinstance(lc, dict):
        print('malformed')
    elif 'found' not in lc:
        print('malformed')
    elif lc['found'] == False:
        print('ok_false')
    elif lc['found'] == True:
        print('found_true')
    else:
        print('malformed')
except:
    print('error')
" 2>/dev/null)

    case "$lc_status" in
        ok_false)
            echo "  ${ninja_name}: OK (lesson_candidate: found=false)"
            ;;
        found_true)
            # lesson.doneのsource確認
            lesson_done="$GATES_DIR/lesson.done"
            if [ -f "$lesson_done" ]; then
                lsource=$(grep '^source:' "$lesson_done" 2>/dev/null | sed 's/source: *//')
                if [ "$lsource" = "lesson_write" ]; then
                    echo "  ${ninja_name}: OK (lesson_candidate found:true, registered via lesson_write)"
                else
                    echo "  ${ninja_name}: NG ← lesson_candidate found:true but lesson.done source=${lsource} (not lesson_write)"
                    record_block_reason "${ninja_name}:lesson_done_source:${lsource}"
                    ALL_CLEAR=false
                fi
            else
                echo "  ${ninja_name}: NG ← lesson_candidate found:true but lesson.done not found"
                record_block_reason "${ninja_name}:lesson_done_missing"
                ALL_CLEAR=false
            fi
            ;;
        missing)
            echo "  ${ninja_name}: NG ← lesson_candidateフィールド欠落"
            record_block_reason "${ninja_name}:lesson_candidate_missing"
            ALL_CLEAR=false
            ;;
        malformed)
            echo "  ${ninja_name}: NG ← lesson_candidate構造不正（foundキーなし等）"
            record_block_reason "${ninja_name}:lesson_candidate_malformed"
            ALL_CLEAR=false
            ;;
        *)
            echo "  ${ninja_name}: NG ← lesson_candidate解析エラー"
            record_block_reason "${ninja_name}:lesson_candidate_parse_error"
            ALL_CLEAR=false
            ;;
    esac
done
if [ "$LC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── skill_candidate検証（WARNのみ、ブロックしない） ───
echo ""
echo "Skill candidate check:"
SC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    SC_CHECKED=true

    sc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    sc = data.get('skill_candidate')
    if sc is None:
        print('missing')
    elif not isinstance(sc, dict):
        print('malformed')
    elif 'found' not in sc:
        print('no_found')
    else:
        print('ok')
except:
    print('error')
" 2>/dev/null)

    case "$sc_status" in
        ok)
            echo "  ${ninja_name}: OK (skill_candidate.found present)"
            ;;
        missing)
            echo "  WARN: ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        no_found)
            echo "  WARN: ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        malformed)
            echo "  WARN: ${ninja_name}_report.yaml skill_candidate構造不正"
            ;;
        *)
            echo "  WARN: ${ninja_name}_report.yaml skill_candidate解析エラー"
            ;;
    esac
done
if [ "$SC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate検証（WARNのみ、ブロックしない） ───
echo ""
echo "Decision candidate check:"
DC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    DC_CHECKED=true

    dc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    dc = data.get('decision_candidate')
    if dc is None:
        print('missing')
    elif not isinstance(dc, dict):
        print('malformed')
    elif 'found' not in dc:
        print('no_found')
    else:
        print('ok')
except:
    print('error')
" 2>/dev/null)

    case "$dc_status" in
        ok)
            echo "  ${ninja_name}: OK (decision_candidate.found present)"
            ;;
        missing)
            echo "  WARN: ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        no_found)
            echo "  WARN: ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        malformed)
            echo "  WARN: ${ninja_name}_report.yaml decision_candidate構造不正"
            ;;
        *)
            echo "  WARN: ${ninja_name}_report.yaml decision_candidate解析エラー"
            ;;
    esac
done
if [ "$DC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── draft教訓存在チェック（プロジェクト関連のdraft未査読をブロック） ───
echo ""
echo "Draft lesson check:"
# cmdのprojectを取得
CMD_PROJECT=$(awk -v id="  - id: ${CMD_ID}" '
    $0 == id { found=1; next }
    found && /^  - id:/ { exit }
    found && /^    project:/ { sub(/^    project: */, ""); print; exit }
' "$YAML_FILE")

if [ -n "$CMD_PROJECT" ]; then
    # projectのSSOTパスを取得
    DRAFT_SSOT_PATH=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$CMD_PROJECT':
        print(p['path'])
        break
" 2>/dev/null)

    if [ -n "$DRAFT_SSOT_PATH" ]; then
        DRAFT_LESSONS_FILE="$DRAFT_SSOT_PATH/tasks/lessons.md"
        if [ -f "$DRAFT_LESSONS_FILE" ]; then
            draft_count=$(grep -c '^\- \*\*status\*\*: draft' "$DRAFT_LESSONS_FILE" 2>/dev/null || true)
            draft_count=${draft_count:-0}
            if [ "$draft_count" -gt 0 ]; then
                echo "  NG ← ${CMD_PROJECT}に${draft_count}件のdraft未査読教訓あり"
                record_block_reason "draft_lessons:${draft_count}"
                ALL_CLEAR=false
            else
                echo "  OK (no draft lessons in ${CMD_PROJECT})"
            fi
        else
            echo "  SKIP (lessons file not found: ${DRAFT_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project path not found for: ${CMD_PROJECT})"
    fi
else
    echo "  SKIP (project not found in cmd)"
fi

# ─── inbox_archive強制チェック（WARNのみ、ブロックしない） ───
echo ""
echo "Inbox archive check:"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$KARO_INBOX" ]; then
    read_count=$(grep -c 'read: true' "$KARO_INBOX" 2>/dev/null || true)
    read_count=${read_count:-0}

    if [ "$read_count" -ge 10 ]; then
        echo "INBOX_ARCHIVE_WARN: karo has ${read_count} read messages, running inbox_archive.sh"
        if bash "$SCRIPT_DIR/scripts/inbox_archive.sh" karo; then
            echo "  karo: inbox_archive completed"
        else
            echo "  WARN: inbox_archive.sh failed for karo"
        fi
    else
        echo "  karo: OK (read:true=${read_count}, threshold=10)"
    fi
else
    echo "  WARN: karo inbox file not found: ${KARO_INBOX}"
fi

# ─── 未反映PD検出（WARNのみ、ブロックしない） ───
echo ""
echo "Pending decision context sync check:"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$PD_FILE" ]; then
    unsynced_pds=$(python3 -c "
import yaml, sys
try:
    with open('$PD_FILE') as f:
        data = yaml.safe_load(f)
    if not data or not data.get('decisions'):
        sys.exit(0)
    for d in data['decisions']:
        if d.get('source_cmd') == '${CMD_ID}' and d.get('status') == 'resolved' and d.get('context_synced') == False:
            print(d.get('id', '???'))
except:
    pass
" 2>/dev/null)

    if [ -n "$unsynced_pds" ]; then
        while IFS= read -r pd_id; do
            echo "  ⚠️ WARNING: ${pd_id} resolved but context not synced"
        done <<< "$unsynced_pds"
    else
        echo "  OK (no unsynced resolved PDs for ${CMD_ID})"
    fi
else
    echo "  SKIP (pending_decisions.yaml not found)"
fi

# ─── 穴4: 調査恒久化チェック（WARNのみ、ブロックしない） ───
echo ""
echo "Recon knowledge persistence check (穴4):"
# purposeを取得（append_changelog内と同じawk）
CMD_PURPOSE=$(awk -v id="  - id: ${CMD_ID}" '
    $0 == id { found=1; next }
    found && /^  - id:/ { exit }
    found && /^    purpose:/ { sub(/^    purpose: *"?/, ""); sub(/"$/, ""); print; exit }
' "$YAML_FILE")

IS_RECON=false
if echo "$CMD_PURPOSE" | grep -qE '偵察|調査|棚卸し|recon|investigation'; then
    IS_RECON=true
fi

if [ "$IS_RECON" = true ]; then
    if [ -n "$CMD_PROJECT" ]; then
        CONTEXT_FILE="$SCRIPT_DIR/context/${CMD_PROJECT}.md"
        PROJECT_YAML="$SCRIPT_DIR/projects/${CMD_PROJECT}.yaml"
        HAS_CHANGE=false

        # git diffで変更有無を確認（ステージ済み+未ステージ両方）
        if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff HEAD -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff HEAD -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        # ステージ済みの変更もチェック
        if [ "$HAS_CHANGE" = false ]; then
            if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff --cached -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
            if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff --cached -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
        fi

        if [ "$HAS_CHANGE" = true ]; then
            echo "  OK (context/${CMD_PROJECT}.md or projects/${CMD_PROJECT}.yaml has changes)"
        else
            echo "  ⚠️ 穴4: 調査結果が知識基盤に未反映。context/*.md or projects/*.yaml を更新せよ"
        fi
    else
        echo "  SKIP (project not found in cmd — cannot check knowledge files)"
    fi
else
    echo "  SKIP (non-recon cmd: purpose does not contain recon keywords)"
fi

# ─── 判定結果 ───
echo ""
if [ "$ALL_CLEAR" = true ]; then
    echo "GATE CLEAR: cmd完了許可"
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tCLEAR\tall_gates_passed" >> "$GATE_METRICS_LOG"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  WARN: gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID"
    append_changelog "$CMD_ID"
    exit 0
else
    missing_list=$(IFS=,; echo "${MISSING_GATES[*]}")
    if [ ${#BLOCK_REASONS[@]} -gt 0 ]; then
        block_reason=$(IFS='|'; echo "${BLOCK_REASONS[*]}")
    elif [ -n "$missing_list" ]; then
        block_reason="missing_gates:${missing_list}"
    else
        block_reason="unknown_block_reason"
    fi
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tBLOCK\t${block_reason}" >> "$GATE_METRICS_LOG"
    echo "GATE BLOCK: 不足フラグ=[${missing_list}] 理由=${block_reason}"
    exit 1
fi
