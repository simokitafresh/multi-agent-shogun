#!/bin/bash
# deploy_task.sh — タスク配備ヘルパー（忍者状態自動検知付き）
# Usage: bash scripts/deploy_task.sh <ninja_name> "<message>" [type] [from]
# Example: bash scripts/deploy_task.sh hanzo "タスクYAMLを読んで作業開始せよ" task_assigned karo
#
# 機能:
#   1. 対象忍者のCTX%とidle状態を自動検知
#   2. CTX:0%(clear済み) → プロンプト準備を確認してから起動
#   3. CTX>0%(通常) → そのままinbox_writeで通知
#   4. 動作ログを記録
#
# cmd_102: 殿の哲学「人が従う」ではなく「仕組みが強制する」

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/deploy_task.log"

# cli_lookup.sh — CLI Profile SSOT参照（CLI種別判定・パターン取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

NINJA_NAME="${1:-}"
MESSAGE="${2:-}"
TYPE="${3:-task_assigned}"
FROM="${4:-karo}"

if [ -z "$NINJA_NAME" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: deploy_task.sh <ninja_name> <message> [type] [from]" >&2
    echo "例: deploy_task.sh sasuke \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$NINJA_NAME" == cmd_* ]]; then
    echo "ERROR: 第1引数はninja_name（例: hanzo, sasuke）。cmd_idではない。" >&2
    echo "Usage: deploy_task.sh <ninja_name> <message> [type] [from]" >&2
    echo "例: deploy_task.sh sasuke \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEPLOY] $1" >> "$LOG"
    echo "[DEPLOY] $1" >&2
}

# ─── ペインターゲット解決 ───
resolve_pane() {
    local name="$1"
    # ninja_states.yamlから取得（ninja_monitorが定期更新）
    local pane
    pane=$(python3 -c "
import yaml, sys
try:
    with open('$SCRIPT_DIR/logs/ninja_states.yaml') as f:
        data = yaml.safe_load(f)
    ninja = data.get('ninjas', {}).get('$name', {})
    print(ninja.get('pane', ''))
except:
    pass
" 2>/dev/null)

    if [ -n "$pane" ]; then
        echo "$pane"
        return 0
    fi

    # フォールバック: 既知のペインマッピング
    case "$name" in
        karo)     echo "shogun:agents.1" ;;
        sasuke)   echo "shogun:agents.2" ;;
        kirimaru) echo "shogun:agents.3" ;;
        hayate)   echo "shogun:agents.4" ;;
        kagemaru) echo "shogun:agents.5" ;;
        hanzo)    echo "shogun:agents.6" ;;
        saizo)    echo "shogun:agents.7" ;;
        kotaro)   echo "shogun:agents.8" ;;
        tobisaru) echo "shogun:agents.9" ;;
        *) echo "" ;;
    esac
}

# ─── CTX%取得（cli_profiles.yaml経由でCLI種別に応じたパターンを取得） ───
get_ctx_pct() {
    local pane_target="$1"
    local ctx_num

    # Source 1: tmux pane variable
    ctx_num=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    if [ -n "$ctx_num" ] 2>/dev/null; then
        echo "$ctx_num"
        return 0
    fi

    # Source 2: capture-pane + cli_profiles.yamlのパターン
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null)

    local ctx_pattern ctx_mode
    ctx_pattern=$(cli_profile_get "$NINJA_NAME" "ctx_pattern")
    ctx_mode=$(cli_profile_get "$NINJA_NAME" "ctx_mode")

    if [ -n "$ctx_pattern" ]; then
        ctx_num=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
        if [ -n "$ctx_num" ]; then
            if [ "$ctx_mode" = "remaining" ]; then
                echo $((100 - ctx_num))
            else
                echo "$ctx_num"
            fi
            return 0
        fi
    fi

    echo "0"
}

# ─── idle検知（cli_profiles.yaml経由でBUSY/IDLEパターンを取得） ───
check_idle() {
    local pane_target="$1"

    # Source 1: @agent_state変数
    local state
    state=$(tmux show-options -p -t "$pane_target" -v @agent_state 2>/dev/null)
    if [ "$state" = "idle" ]; then
        return 0
    elif [ -n "$state" ] && [ "$state" != "idle" ]; then
        return 1
    fi

    # Source 2: capture-pane フォールバック
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null)

    # cli_profiles.yaml経由でBUSY/IDLEパターンを取得
    local busy_raw idle_pattern
    busy_raw=$(cli_profile_get "$NINJA_NAME" "busy_patterns")
    idle_pattern=$(cli_profile_get "$NINJA_NAME" "idle_pattern")

    # BUSYパターン（cli_lookupはリストをパイプ区切りで返す → grep -E の alternation として使用）
    if [ -n "$busy_raw" ] && echo "$output" | grep -qE "$busy_raw"; then
        return 1
    fi

    # IDLEパターン: プロンプト表示
    if [ -n "$idle_pattern" ] && echo "$output" | tail -3 | grep -qF "$idle_pattern"; then
        return 0
    fi

    return 1  # デフォルト: BUSY（安全側）
}

# ─── プロンプト準備待ち（/clear後用） ───
wait_for_prompt() {
    local pane_target="$1"
    local max_wait=30  # 最大30秒
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if check_idle "$pane_target"; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log "WARNING: $NINJA_NAME prompt not ready after ${max_wait}s, proceeding anyway"
    return 1
}

# ─── 報告YAML雛形生成（cmd_138: lesson_candidate欠落防止） ───
generate_report_template() {
    local ninja_name="$1"
    local task_id="$2"
    local parent_cmd="$3"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"

    mkdir -p "$SCRIPT_DIR/queue/reports"

    # 受領条件の存在確認（grepで取得。監査ログ用途）
    local ac_count=0
    if [ -f "$task_file" ] && grep -q '^  acceptance_criteria:' "$task_file" 2>/dev/null; then
        ac_count=$(grep -A 60 '^  acceptance_criteria:' "$task_file" 2>/dev/null | grep -cE '^[[:space:]]*-[[:space:]]' || true)
    fi

    cat > "$report_file" <<EOF
worker_id: ${ninja_name}
task_id: ${task_id}
parent_cmd: ${parent_cmd}
timestamp: ""
status: ""
result:
  summary: ""
lesson_candidate:
  found: false
lesson_referenced: []
skill_candidate:
  found: false
decision_candidate:
  found: false
EOF

    log "${ninja_name}: report template generated (${report_file}, acceptance_criteria=${ac_count})"
}

# ─── 教訓自動注入（task YAMLにrelated_lessonsを挿入） ───
inject_related_lessons() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_lessons: task file not found: $task_file"
        return 0
    fi

    python3 -c "
import yaml, sys, os, re, tempfile

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[INJECT] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    project = task.get('project', '')

    if not project:
        task['related_lessons'] = []
        # Atomic write
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print('[INJECT] No project field, set related_lessons: []', file=sys.stderr)
        sys.exit(0)

    lessons_path = os.path.join(script_dir, 'projects', project, 'lessons.yaml')
    if not os.path.exists(lessons_path):
        task['related_lessons'] = []
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print(f'[INJECT] WARN: lessons.yaml not found for project={project}', file=sys.stderr)
        sys.exit(0)

    with open(lessons_path) as f:
        lessons_data = yaml.safe_load(f)

    lessons = lessons_data.get('lessons', []) if lessons_data else []
    if not lessons:
        task['related_lessons'] = []
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print(f'[INJECT] No lessons for project={project}', file=sys.stderr)
        sys.exit(0)

    # Build task text for keyword extraction
    title = task.get('title', '')
    description = task.get('description', '')
    ac_list = task.get('acceptance_criteria', [])
    ac_text = ' '.join(ac_list) if isinstance(ac_list, list) else str(ac_list or '')
    task_text = f'{title} {description} {ac_text}'

    # Extract keywords: split by non-word chars, exclude <=3 chars, lowercase, dedup
    words = re.split(r'[^a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+', task_text)
    keywords = list(set(w.lower() for w in words if len(w) > 3))

    # Score each lesson
    scored = []
    for lesson in lessons:
        lid = lesson.get('id', '')
        l_title = str(lesson.get('title', ''))
        l_summary = str(lesson.get('summary', ''))
        l_content = str(lesson.get('content', ''))
        l_source = str(lesson.get('source', ''))

        title_text = l_title.lower()
        other_text = f'{l_summary} {l_content} {l_source}'.lower()

        score = 0
        for kw in keywords:
            if kw in title_text:
                score += 3
            elif kw in other_text:
                score += 1

        if score > 0:
            scored.append((score, lid, l_summary or l_title))

    # Sort by score descending, take top 5
    scored.sort(key=lambda x: -x[0])
    top = scored[:5]

    # Fallback: if 0 matches, take most recent 3 lessons
    if not top:
        recent = lessons[:3]  # lessons.yaml is already ordered by recency
        top = [(0, l.get('id', ''), l.get('summary', '') or l.get('title', '')) for l in recent]

    related = [{'id': lid, 'summary': summary, 'reviewed': False} for _, lid, summary in top]
    task['related_lessons'] = related

    # (A) description冒頭に教訓要約を挿入（忍者が即座に目にする）
    if related:
        desc = task.get('description', '')
        marker = '【注入教訓】'
        if marker not in str(desc):
            lines = [marker + ' 必ず確認し reviewed: true に変更せよ']
            for r in related:
                lines.append(f\"  - {r['id']}: {r['summary'][:80]}\")
            lines.append('─' * 40)
            prefix = '\\n'.join(lines) + '\\n\\n'
            task['description'] = prefix + str(desc or '')

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    ids = [r['id'] for r in related]
    print(f'[INJECT] Injected {len(related)} lessons: {ids} for project={project}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── 偵察報告自動注入（task YAMLにreports_to_readを挿入） ───
inject_reports_to_read() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_reports: task file not found: $task_file"
        return 0
    fi

    python3 -c "
import yaml, sys, os, tempfile

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[INJECT_REPORTS] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreports_to_readが設定済みなら上書きしない
    if task.get('reports_to_read'):
        print('[INJECT_REPORTS] reports_to_read already exists, skipping', file=sys.stderr)
        sys.exit(0)

    blocked_by = task.get('blocked_by', [])
    if not blocked_by:
        print('[INJECT_REPORTS] No blocked_by, skipping', file=sys.stderr)
        sys.exit(0)

    # blocked_byの各タスクIDから忍者名を解決
    tasks_dir = os.path.join(script_dir, 'queue', 'tasks')
    reports_dir = os.path.join(script_dir, 'queue', 'reports')
    report_paths = []

    for blocked_task_id in blocked_by:
        # queue/tasks/*.yamlを検索してtask_idが一致するものを見つける
        if not os.path.isdir(tasks_dir):
            continue
        for fname in os.listdir(tasks_dir):
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(tasks_dir, fname)
            try:
                with open(fpath) as f:
                    tdata = yaml.safe_load(f)
                if not tdata or 'task' not in tdata:
                    continue
                t = tdata['task']
                if t.get('task_id') == blocked_task_id:
                    assigned_to = t.get('assigned_to', '')
                    if assigned_to:
                        report_path = os.path.join(reports_dir, f'{assigned_to}_report.yaml')
                        if os.path.exists(report_path):
                            report_paths.append(f'queue/reports/{assigned_to}_report.yaml')
                        else:
                            print(f'[INJECT_REPORTS] WARN: report not found: {report_path}', file=sys.stderr)
                    break
            except Exception:
                continue

    if not report_paths:
        print('[INJECT_REPORTS] No report files found for blocked_by tasks', file=sys.stderr)
        sys.exit(0)

    # deduplicate while preserving order
    seen = set()
    unique_paths = []
    for p in report_paths:
        if p not in seen:
            seen.add(p)
            unique_paths.append(p)

    task['reports_to_read'] = unique_paths

    # description冒頭に参照報告を挿入
    desc = task.get('description', '')
    marker = '【参照報告】'
    if marker not in str(desc):
        lines = [marker + ' 以下の報告を読んでからレビューせよ']
        for rp in unique_paths:
            lines.append(f'  - {rp}')
        lines.append('─' * 40)
        prefix = '\\n'.join(lines) + '\\n\\n'
        task['description'] = prefix + str(desc or '')

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[INJECT_REPORTS] Injected {len(unique_paths)} reports: {unique_paths}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_REPORTS] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ═══════════════════════════════════════
# メイン処理
# ═══════════════════════════════════════

PANE_TARGET=$(resolve_pane "$NINJA_NAME")
if [ -z "$PANE_TARGET" ]; then
    log "ERROR: Unknown ninja: $NINJA_NAME"
    exit 1
fi

CTX_PCT=$(get_ctx_pct "$PANE_TARGET")
IS_IDLE=false
check_idle "$PANE_TARGET" && IS_IDLE=true

# タスクステータス確認
TASK_STATUS=$(grep -m1 '^  status:' "$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml" 2>/dev/null | awk '{print $2}' || echo "unknown")

log "${NINJA_NAME}: CTX=${CTX_PCT}%, idle=${IS_IDLE}, task_status=${TASK_STATUS}, pane=${PANE_TARGET}"

# 教訓自動注入（失敗してもデプロイは継続）
TASK_FILE="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
inject_related_lessons "$TASK_FILE" || true

# 偵察報告自動注入（失敗してもデプロイは継続）
inject_reports_to_read "$TASK_FILE" || true

# 状態に応じた処理
if [ "$CTX_PCT" -le 0 ] 2>/dev/null; then
    # CTX:0% — /clear済み、またはフレッシュセッション
    log "${NINJA_NAME}: CTX=0% detected (clear済み). Waiting for prompt..."
    wait_for_prompt "$PANE_TARGET"
    log "${NINJA_NAME}: Sending inbox_write (post-clear wake-up)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"

elif [ "$IS_IDLE" = "true" ]; then
    # CTX>0% + idle — 通常idle、nudge可能
    log "${NINJA_NAME}: CTX=${CTX_PCT}%, idle. Sending inbox_write (normal nudge)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"

else
    # CTX>0% + busy — 稼働中、メッセージはキューに入る
    log "${NINJA_NAME}: CTX=${CTX_PCT}%, busy. Sending inbox_write (queued, watcher will nudge later)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
fi

# 報告YAML雛形生成（配備完了ログの直前）
TASK_ID=$(grep -m1 '^  task_id:' "$TASK_FILE" 2>/dev/null | sed 's/^  task_id:[[:space:]]*//' || true)
PARENT_CMD=$(grep -m1 '^  parent_cmd:' "$TASK_FILE" 2>/dev/null | sed 's/^  parent_cmd:[[:space:]]*//' || true)
generate_report_template "$NINJA_NAME" "$TASK_ID" "$PARENT_CMD"

log "${NINJA_NAME}: deployment complete (type=${TYPE})"
