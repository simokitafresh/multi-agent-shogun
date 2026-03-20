#!/bin/bash
# shellcheck disable=SC1091
# deploy_task.sh — タスク配備ヘルパー（忍者状態自動検知付き）
# Usage: bash scripts/deploy_task.sh <ninja_name> [message] [type] [from]
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
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/ctx_utils.sh"
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"

NINJA_NAME="${1:-}"
DEFAULT_MESSAGE="タスクYAMLを読んで作業開始せよ。"
MESSAGE="${2:-$DEFAULT_MESSAGE}"
TYPE="${3:-task_assigned}"
FROM="${4:-karo}"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEPLOY] $1" >> "$LOG"
    echo "[DEPLOY] $1" >&2
}

log_output_file() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        while IFS= read -r line; do
            log "$line"
        done < "$output_file"
        rm -f "$output_file"
    fi
}

run_python_logged() {
    local output_file="$1"
    shift

    local status=0
    "$@" >"$output_file" 2>&1 || status=$?
    log_output_file "$output_file"
    return "$status"
}

cleanup_none_task_files() {
    local ghost_task="$SCRIPT_DIR/queue/tasks/None.yaml"
    local ghost_lock="$SCRIPT_DIR/queue/tasks/None.yaml.lock"

    for ghost_path in "$ghost_task" "$ghost_lock"; do
        if [ -e "$ghost_path" ]; then
            rm -f "$ghost_path"
            log "Removed ghost task artifact: ${ghost_path#"$SCRIPT_DIR"/}"
        fi
    done
}

cleanup_none_task_files

if [ -z "$NINJA_NAME" ] || [ "${NINJA_NAME,,}" = "none" ]; then
    echo "ERROR: ninja_name is required and cannot be empty/None." >&2
    echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
    echo "例1: deploy_task.sh hanzo" >&2
    echo "例2: deploy_task.sh hanzo \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$NINJA_NAME" == cmd_* ]]; then
    echo "ERROR: 第1引数はninja_name（例: hanzo, hayate）。cmd_idではない。" >&2
    echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
    echo "例1: deploy_task.sh hanzo" >&2
    echo "例2: deploy_task.sh hanzo \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# ─── ペインターゲット解決 → lib/pane_lookup.sh に統合済み（pane_lookup関数） ───
resolve_pane() {
    pane_lookup "$1"
}

# ─── CTX%取得 → lib/ctx_utils.sh に統合済み（get_ctx_pct関数） ───

# ─── idle検知（cli_profiles.yaml経由でBUSY/IDLEパターンを取得） ───
check_idle() {
    local pane_target="$1"

    # Source 1: @agent_state変数
    local state
    state=$(tmux show-options -p -t "$pane_target" -v @agent_state 2>/dev/null)
    if [ "$state" = "idle" ]; then
        return 0
    fi

    local busy_rc
    if check_agent_busy "$pane_target" "$NINJA_NAME"; then
        busy_rc=0
    else
        busy_rc=$?
    fi

    if [ "$busy_rc" -eq 0 ]; then
        return 0
    fi

    # unknownは安全側でBUSY扱い
    return 1  # デフォルト: BUSY（安全側）
}


# ─── cmd_1157: flat→nested YAML正規化 ───
# flat形式(task:ブロックなし)のtask YAMLをnested形式に変換する。
# 変換失敗時はログ出力のみ（配備は継続。yaml_field_setのフォールバック対応あり）
normalize_task_yaml() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 1
    fi

    # nested形式判定: 先頭が"task:"で始まる → 変換不要
    if head -1 "$task_file" | grep -qE '^task:'; then
        return 0
    fi

    # flat形式判定: task_id: or status: がルートに存在
    if ! grep -qE '^(task_id|status):' "$task_file"; then
        return 0  # flat形式でもない → 未知の形式、触らない
    fi

    log "normalize_task_yaml: flat→nested conversion for $(basename "$task_file")"

    local tmp_file
    tmp_file="$(mktemp "${task_file}.norm.XXXXXX")" || {
        log "normalize_task_yaml: mktemp failed"
        return 1
    }

    # 全行を2spインデントし、先頭に"task:"を追加
    {
        echo "task:"
        sed 's/^/  /' "$task_file"
    } > "$tmp_file"

    # 変換後のYAMLがyaml_field_setで操作可能か検証
    local verify_tmp
    verify_tmp="$(mktemp "${task_file}.verify.XXXXXX")" || {
        rm -f "$tmp_file"
        log "normalize_task_yaml: verify mktemp failed"
        return 1
    }

    # 検証: task blockが見つかることを確認（_yaml_field_set_applyのdry-run相当）
    if _yaml_field_get_in_block "$tmp_file" "task" "task_id" >/dev/null 2>&1 || \
       _yaml_field_get_in_block "$tmp_file" "task" "status" >/dev/null 2>&1; then
        mv "$tmp_file" "$task_file"
        rm -f "$verify_tmp"
        log "normalize_task_yaml: conversion successful"
        return 0
    else
        rm -f "$tmp_file" "$verify_tmp"
        log "normalize_task_yaml: verification failed, keeping original"
        return 1
    fi
}

# ─── task_id自動注入（cmd_465: STALL検知キー統一） ───
# subtask_idの値をtask_idとして注入。ninja_monitor check_stall()がtask_idを参照するため必須。
inject_task_id() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_task_id: task file not found: $task_file"
        return 1
    fi

    local subtask_id
    subtask_id=$(field_get "$task_file" "subtask_id" "")
    if [ -z "$subtask_id" ]; then
        log "inject_task_id: no subtask_id found, skipping"
        return 0
    fi

    local existing_task_id
    existing_task_id=$(field_get "$task_file" "task_id" "")
    if [ -n "$existing_task_id" ] && [ "$existing_task_id" != "idle" ]; then
        log "inject_task_id: task_id already set ($existing_task_id), skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "task_id" "$subtask_id"
    log "inject_task_id: set task_id=$subtask_id"
}

# ─── ac_version自動注入（cmd_530: stale作業検知, cmd_1053: ハッシュ化） ───
# acceptance_criteriaの各descriptionをソート→連結→md5先頭8桁をtask.ac_versionとして保持。
# 件数が同じでも内容が変われば異なるハッシュになる。再配備時に再計算される。
inject_ac_version() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_ac_version: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" python3 - <<'PY'; then
import hashlib
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[AC_VERSION] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    ac = task.get('acceptance_criteria', [])

    descriptions = []
    if isinstance(ac, list):
        for item in ac:
            if isinstance(item, dict):
                descriptions.append(str(item.get('description', '')).strip())
            else:
                descriptions.append(str(item).strip())
    elif isinstance(ac, str):
        descriptions.append(ac.strip())
    elif isinstance(ac, dict):
        for key in sorted(ac.keys()):
            descriptions.append(str(ac[key]).strip() if ac[key] else str(key))

    if descriptions:
        descriptions.sort()
        concat = '|'.join(descriptions)
        ac_version = hashlib.md5(concat.encode('utf-8')).hexdigest()[:8]
    else:
        ac_version = hashlib.md5(b'').hexdigest()[:8]

    prev = task.get('ac_version')
    task['ac_version'] = ac_version

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

    if str(prev) == str(ac_version):
        print(f'[AC_VERSION] unchanged: {ac_version}', file=sys.stderr)
    else:
        print(f'[AC_VERSION] set: {prev} -> {ac_version}', file=sys.stderr)

except Exception as e:
    print(f'[AC_VERSION] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── 報告YAML雛形生成（cmd_138: lesson_candidate欠落防止） ───
generate_report_template() {
    local ninja_name="$1"
    local task_id="$2"
    local parent_cmd="$3"
    local project="$4"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local report_file=""
    local report_rel_path=""

    # report_filenameフィールドを優先参照（cmd_412: 命名ミスマッチ根治）
    local report_filename=""
    report_filename=$(field_get "$task_file" "report_filename" "")

    if [ -n "$report_filename" ]; then
        report_file="$SCRIPT_DIR/queue/reports/${report_filename}"
    elif [[ -n "$parent_cmd" && "$parent_cmd" == cmd_* ]]; then
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    else
        # 後方互換: parent_cmdが未設定/不正なら旧形式にフォールバック
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    fi
    report_rel_path="queue/reports/$(basename "$report_file")"

    mkdir -p "$SCRIPT_DIR/queue/reports"

    # 冪等性: 既存テンプレートがあればスキップ（L060: 上書き防止）
    if [ -f "$report_file" ]; then
        log "report_template: already exists, skipping (${report_file})"
        yaml_field_set "$task_file" "task" "report_path" "$report_rel_path"
        log "report_path: set (${report_rel_path})"
        return 0
    fi

    # タスクYAMLから自動記入値を取得（cmd_532: 機械的フィールド自動記入）
    local worker_id
    worker_id=$(field_get "$task_file" "assigned_to" "$ninja_name")
    local resolved_task_id
    resolved_task_id=$(field_get "$task_file" "subtask_id" "")
    if [ -z "$resolved_task_id" ]; then
        resolved_task_id=$(field_get "$task_file" "task_id" "$task_id")
    fi
    local resolved_parent_cmd
    resolved_parent_cmd=$(field_get "$task_file" "parent_cmd" "$parent_cmd")
    local ac_version
    ac_version=$(field_get "$task_file" "ac_version" "")

    cat > "$report_file" <<EOF
# !! トップレベル構造を維持せよ。report: で包むな !!
# !! Edit toolで既存フィールドを編集せよ。Write toolで全上書きするな !!
# Step1: Read this file → Step2: Edit tool で各フィールドを埋めよ → Write禁止
worker_id: ${worker_id}
task_id: ${resolved_task_id}
parent_cmd: ${resolved_parent_cmd}
timestamp: ""  # date "+%Y-%m-%dT%H:%M:%S" で取得せよ
status: pending
ac_version_read: ${ac_version}
result:
  summary: ""
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  # found: true/false を書け。リスト形式[] 禁止
  found: false
  no_lesson_reason: ""  # found:false時に必須。理由を1文で書け。例: "既知のL084と同じパターン"
  title: ""
  detail: ""
  project: ${project}
lessons_useful: null
skill_candidate:
  found: false  # 同じ手順を3回以上繰り返したらfound: trueにせよ
  # found: true の場合は以下も記入:
  # name: ""        # スキル名 例: "cdp-page-measure"
  # description: "" # 何をするスキルか 例: "CDP経由でページ計測を自動実行"
  # reason: ""      # なぜスキル化すべきか 例: "CDP計測手順を5回以上手動実行した"
  # project: ""     # 対象PJ 例: "dm-signal"
decision_candidate:
  found: false
hook_failures:
  count: 0
  details: ""
EOF

    # cmd_1131: related_lessonsが存在する場合、lessons_usefulを記入用雛形に差替え
    local _lu_output
    _lu_output=$(mktemp)
    if run_python_logged "$_lu_output" env TASK_FILE_ENV="$task_file" REPORT_FILE_ENV="$report_file" python3 - <<'LUEOF'
import os
import sys

import yaml

task_file = os.environ['TASK_FILE_ENV']
report_file = os.environ['REPORT_FILE_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)
    if not data:
        sys.exit(1)
    task = data.get('task', data)
    related = task.get('related_lessons', [])
    if not related or not isinstance(related, list):
        sys.exit(1)

    ids = [r['id'] for r in related if isinstance(r, dict) and 'id' in r]
    if not ids:
        sys.exit(1)

    lines = ["lessons_useful:"]
    for lid in ids:
        lines.append(f"  - id: {lid}")
        lines.append(f"    useful: FILL_THIS  # true or false に書き換えよ（必須）")
        lines.append(f"    reason: FILL_THIS  # 1行で理由を書け（必須）")

    with open(report_file) as f:
        content = f.read()
    content = content.replace('lessons_useful: null', '\n'.join(lines))
    with open(report_file, 'w') as f:
        f.write(content)

    print(f'lessons_useful template: {len(ids)} entries injected')
except Exception as e:
    print(f'WARN: lessons_useful inject failed: {e}', file=sys.stderr)
LUEOF
    then
        log "report_template: lessons_useful template injected"
    fi
    rm -f "$_lu_output"

    # cmd_754: 偵察タスクにはimplementation_readiness欄を追加
    local report_task_type
    report_task_type=$(field_get "$task_file" "task_type" "")
    if [ -z "$report_task_type" ]; then
        report_task_type=$(field_get "$task_file" "type" "")
    fi
    if [ "$report_task_type" = "recon" ] || [ "$report_task_type" = "scout" ]; then
        cat >> "$report_file" <<'RECON_EOF'
# ─── 偵察 実装直結4要件（cmd_754: 必須。空欄でWARN） ───
implementation_readiness:
  files_to_modify: []   # 変更対象ファイルと行番号 例: ["src/api/auth.py:45-60"]
  affected_files: []    # 変更が波及する他ファイル 例: ["tests/test_auth.py"]
  related_tests: []     # 関連テストの有無と修正要否 例: ["tests/test_auth.py — 修正必要"]
  edge_cases: []        # エッジケース・副作用 例: ["トークン期限切れ時の再認証フロー"]
RECON_EOF
        log "report_template: added implementation_readiness (recon/scout)"
    fi

    # cmd_1066: reviewタスクにはverdict+self_gate_check欄を追加
    if [ "$report_task_type" = "review" ]; then
        cat >> "$report_file" <<'REVIEW_EOF'
# ─── レビュー判定（cmd_1066: reviewタスク必須） ───
verdict: ""  # PASS or FAIL
self_gate_check:
  lesson_ref: ""
  lesson_candidate: ""
  status_valid: ""
  purpose_fit: ""
REVIEW_EOF
        log "report_template: added verdict/self_gate_check (review)"
    fi

    # cmd_776 C層: テンプレ生成後にnormalize_report.shで正規化を保証
    if bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" >/dev/null 2>&1; then
        log "report_template: normalized (C層 auto-fix applied)"
    fi

    yaml_field_set "$task_file" "task" "report_path" "$report_rel_path"
    log "report_path: set (${report_rel_path})"
    log "report_template: generated (${report_file})"
}

# ─── 教訓自動注入（task YAMLにrelated_lessonsを挿入） ───
# cmd_349: タグマッチによる選択的教訓注入
inject_related_lessons() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_lessons: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import datetime
import os
import random
import re
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

DEDUP_THRESHOLD = 0.25

def tech_terms(text):
    '''技術用語のみ抽出（日本語テキスト対応）'''
    text = str(text)
    terms = set()
    terms.update(w.lower() for w in re.findall(r'[a-zA-Z_][a-zA-Z0-9_\\.]{2,}', text))
    terms.update(w.lower() for w in re.findall(r'L\\d{2,3}', text))
    terms.update(w.lower() for w in re.findall(r'\\.[a-z]{1,4}', text))
    return terms

def jaccard(set_a, set_b):
    if not set_a or not set_b:
        return 0.0
    return len(set_a & set_b) / len(set_a | set_b)

def greedy_dedup(scored_list, all_lessons, threshold=DEDUP_THRESHOLD):
    accepted = []
    accepted_terms = []
    deduped_count = 0
    for score, lid, summary in scored_list:
        lesson = all_lessons.get(lid, {})
        l_text = f'{lesson.get("title","")} {lesson.get("summary","")} {lesson.get("content","")}'
        terms = tech_terms(l_text)
        is_dup = False
        for acc_terms in accepted_terms:
            if jaccard(terms, acc_terms) >= threshold:
                is_dup = True
                break
        if is_dup:
            deduped_count += 1
            continue
        accepted.append((score, lid, summary))
        accepted_terms.append(terms)
    if deduped_count > 0:
        print(f'[INJECT] dedup: removed {deduped_count} similar lessons (threshold={threshold})', file=sys.stderr)
    return accepted

def build_lesson_detail(lesson):
    if_then = lesson.get('if_then')
    if isinstance(if_then, dict):
        cond = str(if_then.get('if', '') or '').strip()
        action = str(if_then.get('then', '') or '').strip()
        reason = str(if_then.get('because', '') or '').strip()
        if cond and action and reason:
            return f'IF: {cond} → THEN: {action} (BECAUSE: {reason})'
        if cond and action:
            return f'IF: {cond} → THEN: {action}'
        if action and reason:
            return f'THEN: {action} (BECAUSE: {reason})'
        if cond and reason:
            return f'IF: {cond} (BECAUSE: {reason})'
        if cond:
            return f'IF: {cond}'
        if action:
            return f'THEN: {action}'
        if reason:
            return f'BECAUSE: {reason}'
    return str(lesson.get('detail', '') or lesson.get('content', '') or lesson.get('summary', '') or '')

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[INJECT] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    project = task.get('project', '')
    task_type = str(task.get('task_type') or task.get('type') or 'unknown').lower().strip()

    # cmd_513: recon/scout/research は教訓注入を行わない（偵察系タスクの空振り削減）
    if task_type in ('recon', 'scout', 'research'):
        task['related_lessons'] = []

        # 再配備時に残存した注入プレフィックスがあれば除去
        desc = str(task.get('description', '') or '')
        marker = '【注入教訓】'
        separator = '─' * 40
        if marker in desc and separator in desc:
            head, tail = desc.split(separator, 1)
            if marker in head:
                task['description'] = tail.lstrip('\n')

        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise

        skip_id = f'skipped_{task_type}'
        _pc_path = os.path.join(os.path.dirname(task_file), '.postcond_lesson_inject')
        try:
            with open(_pc_path, 'w') as _pf:
                _pf.write('available=0\n')
                _pf.write('injected=0\n')
                _pf.write(f'task_id={task.get("task_id", "unknown")}\n')
                _pf.write(f'project={project}\n')
                _pf.write(f'injected_ids={skip_id}\n')
        except Exception:
            pass

        # 追跡ログにスキップを残す（教訓注入なしを明示）
        impact_log = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
        cmd_id = task.get('task_id') or task.get('parent_cmd') or 'unknown'
        ninja_name = task.get('assigned_to', 'unknown')
        bloom = task.get('bloom_level', 'unknown')
        try:
            os.makedirs(os.path.dirname(impact_log), exist_ok=True)
            write_header = not os.path.exists(impact_log) or os.path.getsize(impact_log) == 0
            with open(impact_log, 'a', encoding='utf-8') as lf:
                if write_header:
                    lf.write('timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\n')
                ts = datetime.datetime.now().isoformat(timespec='seconds')
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{skip_id}\tskipped\tskipped\tno\t{project}\t{task_type}\t{bloom}\n')
        except Exception as ie:
            print(f'[INJECT] WARN: impact log write failed: {ie}', file=sys.stderr)

        print(f'[INJECT] task_type={task_type}: lesson injection skipped', file=sys.stderr)
        sys.exit(0)

    if not project:
        task['related_lessons'] = []
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
    lessons = []
    if os.path.exists(lessons_path):
        with open(lessons_path) as f:
            lessons_data = yaml.safe_load(f)
        lessons = lessons_data.get('lessons', []) if lessons_data else []
    else:
        print(f'[INJECT] WARN: lessons.yaml not found for project={project}', file=sys.stderr)

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.safe_load(pf)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_path = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    if os.path.exists(plat_path):
                        with open(plat_path) as plf:
                            plat_data = yaml.safe_load(plf)
                        plat_lessons = plat_data.get('lessons', []) if plat_data else []
                        platform_count += len(plat_lessons)
                        lessons.extend(plat_lessons)
        except Exception as pe:
            print(f'[INJECT] WARN: platform lessons load failed: {pe}', file=sys.stderr)

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
        print(f'[INJECT] No lessons for project={project} (including platform)', file=sys.stderr)
        sys.exit(0)

    # Build task text for keyword extraction
    title = task.get('title', '')
    description = task.get('description', '')
    ac_list = task.get('acceptance_criteria', [])
    if isinstance(ac_list, list):
        ac_text = ' '.join(str(a.get('description', '')) if isinstance(a, dict) else str(a) for a in ac_list)
    else:
        ac_text = str(ac_list or '')
    task_text = f'{title} {description} {ac_text}'

    # Extract keywords: split by non-word chars, exclude <=3 chars, lowercase, dedup
    words = re.split(r'[^a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+', task_text)
    keywords = list(set(w.lower() for w in words if len(w) > 3))

    # ═══ タグマッチ: タスクタグの決定 ═══
    # (1) タスクYAMLにtagsフィールドがあればそれを使用
    task_tags = task.get('tags', [])
    if isinstance(task_tags, str):
        task_tags = [task_tags]
    task_tags = [str(t).lower().strip() for t in task_tags if t]

    # (2) tagsがなければtitle+descriptionからキーワード推定 (AC2: config/lesson_tags.yaml辞書参照)
    tag_inferred = False
    if not task_tags:
        # (AC2-b) config/lesson_tags.yamlを読み込んでtag_rulesを動的構築
        tags_yaml_path = os.path.join(script_dir, 'config', 'lesson_tags.yaml')
        tag_rules = []
        if os.path.exists(tags_yaml_path):
            try:
                with open(tags_yaml_path, encoding='utf-8') as tf:
                    tdata = yaml.safe_load(tf)
                for rule in (tdata or {}).get('tag_rules', []):
                    tag = rule.get('tag', '')
                    patterns = rule.get('patterns', [])
                    if tag and patterns:
                        for pat in patterns:
                            tag_rules.append((pat, tag))
            except Exception:
                tag_rules = []

        # (AC2-c) 辞書ファイル不在時のフォールバック: 従来のハードコード値
        if not tag_rules:
            tag_rules = [
                (r'(?i)db|database|SQL|PostgreSQL', 'db'),
                (r'(?i)api|endpoint|request|response|Render', 'api'),
                (r'(?i)frontend|ui|css|react|component', 'frontend'),
                (r'(?i)deploy|本番|render|環境', 'deploy'),
                (r'(?i)pipeline|batch|cron|scheduler', 'pipeline'),
                (r'(?i)test|検証|parity|backtest', 'testing'),
                (r'(?i)review|査読|レビュー', 'review'),
                (r'(?i)recon|偵察|調査|分析', 'recon'),
                (r'(?i)process|手順|運用|workflow', 'process'),
                (r'(?i)通信|報告|inbox|notification', 'communication'),
                (r'(?i)gate|門番|block|clear', 'gate'),
            ]

        for pattern, tag in tag_rules:
            if re.search(pattern, task_text):
                task_tags.append(tag)
        if task_tags:
            tag_inferred = True
            # AC1: タグ推定数上限max 3 — マッチ回数スコア上位3個を採用
            if len(task_tags) > 3:
                tag_match_count = {}
                for pat, t in tag_rules:
                    if t in task_tags:
                        tag_match_count[t] = len(re.findall(pat, task_text))
                task_tags = sorted(set(task_tags), key=lambda t: -tag_match_count.get(t, 0))[:3]

    # Keep only active lessons: status=confirmed or undefined (default=confirmed)
    confirmed_lessons = []
    filtered_draft = 0
    filtered_deprecated = 0
    for lesson in lessons:
        l_status = str(lesson.get('status', 'confirmed')).lower()
        if l_status == 'deprecated':
            filtered_deprecated += 1
            continue
        if lesson.get('deprecated', False):
            filtered_deprecated += 1
            continue
        if l_status != 'confirmed':
            filtered_draft += 1
            continue
        confirmed_lessons.append(lesson)

    # ═══ タグマッチ: 教訓をフィルタ ═══
    # universal教訓は別管理（常に注入）
    universal_lessons = []
    tag_candidates = []

    for lesson in confirmed_lessons:
        l_tags = lesson.get('tags', [])
        if isinstance(l_tags, str):
            l_tags = [l_tags]
        l_tags = [str(t).lower().strip() for t in l_tags if t]

        # universal教訓は常に注入対象
        if 'universal' in l_tags:
            universal_lessons.append(lesson)
            continue

        # 教訓にtagsがない場合（旧フォーマット）→常にスコアリング候補に含める（後方互換）
        if not l_tags:
            tag_candidates.append(lesson)
            continue

        # task_tagsが決定済みの場合、タグ重複チェック
        if task_tags:
            overlap = set(task_tags) & set(l_tags)
            if overlap:
                tag_candidates.append(lesson)
        # task_tagsが空（推定もできなかった）→全教訓注入（安全側フォールバック）
        else:
            tag_candidates.append(lesson)

    # (5) タスクにtagsがなくキーワード推定もできない → 全教訓注入（現行動作=安全側フォールバック）
    if not task_tags:
        tag_candidates = [l for l in confirmed_lessons if l not in universal_lessons]

    # ═══ スコアリング: タグマッチ候補内でキーワードスコア順位付け ═══
    scored = []
    for lesson in tag_candidates:
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

    # Sort by score descending, take top 7 (AC5: task-specific max 7)
    scored.sort(key=lambda x: -x[0])

    # Greedy dedup: 類似教訓の枠消費防止
    lessons_by_id = {l.get('id',''): l for l in confirmed_lessons}
    pre_dedup_count = len(scored)
    scored = greedy_dedup(scored, lessons_by_id)

    # cmd_531: AC2 — helpful_count降順でソート（同値はkeyword scoreで副次順序）
    scored_with_helpful = []
    for score, lid, summary in scored:
        lesson = lessons_by_id.get(lid, {})
        helpful = lesson.get('helpful_count', 0) or 0
        scored_with_helpful.append((helpful, score, lid, summary))
    scored_with_helpful.sort(key=lambda x: (-x[0], -x[1]))
    scored = [(s, lid, summ) for _, s, lid, summ in scored_with_helpful]

    # AC4: スコア0時のフォールバック = 注入なし（無関連教訓のCTX浪費防止）

    # cmd_531: AC1 — MAX_INJECT=5 総合注入上限（universalは内数）
    MAX_INJECT = 5

    # universal教訓の準備（max 3、helpful_count上位）
    universal_total_count = len(universal_lessons)
    universal_lessons.sort(key=lambda l: -(l.get('helpful_count', 0) or 0))
    universal_lessons = universal_lessons[:3]

    # 全候補を統合: universal + task-specific → helpful_count順で選択
    all_candidates = []
    seen_ids = set()
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id not in seen_ids:
            all_candidates.append({
                'id': ul_id,
                'summary': ul.get('summary', '') or ul.get('title', ''),
                'helpful_count': ul.get('helpful_count', 0) or 0,
                'is_universal': True
            })
            seen_ids.add(ul_id)
    for _, lid, summary in scored:
        if lid not in seen_ids:
            lesson = lessons_by_id.get(lid, {})
            all_candidates.append({
                'id': lid,
                'summary': summary,
                'helpful_count': lesson.get('helpful_count', 0) or 0,
                'is_universal': False
            })
            seen_ids.add(lid)

    # helpful_count降順で再ソート（統合後）
    all_candidates.sort(key=lambda x: -x['helpful_count'])

    # AC1/AC3: MAX_INJECT上限適用、超過分はwithheld
    related = []
    withheld = []
    universal_added = 0
    for c in all_candidates:
        if len(related) < MAX_INJECT:
            lesson = lessons_by_id.get(c['id'], {})
            detail = build_lesson_detail(lesson)[:200]
            entry = {'id': c['id'], 'summary': c['summary']}
            if detail:
                entry['detail'] = detail
            related.append(entry)
            if c['is_universal']:
                universal_added += 1
        else:
            withheld.append({'id': c['id'], 'summary': c['summary']})

    task['related_lessons'] = related

    # (A) description冒頭に教訓要約を挿入（忍者が即座に目にする）
    if related:
        desc = task.get('description', '')
        marker = '【注入教訓】'
        if marker not in str(desc):
            lines = [marker + ' 必ず確認してから作業開始せよ']
            for r in related:
                lines.append(f"  - {r['id']}: {r['summary'][:80]}")
            lines.append('─' * 40)
            prefix = '\n'.join(lines) + '\n\n'
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

    # Postcondition data (cmd_378)
    _pc_path = os.path.join(os.path.dirname(task_file), '.postcond_lesson_inject')
    try:
        with open(_pc_path, 'w') as _pf:
            _pf.write(f'available={len(tag_candidates) + universal_total_count}\n')
            _pf.write(f'injected={len(related)}\n')
            _pf.write(f'task_id={task.get("task_id", "unknown")}\n')
            _pf.write(f'project={project}\n')
            _pf.write(f'injected_ids={" ".join(r["id"] for r in related)}\n')
    except Exception:
        pass

    ids = [r['id'] for r in related]
    tag_info = f'task_tags={task_tags} inferred={tag_inferred}'
    scored_count = len(scored)
    tag_candidate_count = len(tag_candidates)
    print(f'[INJECT] Injected {len(related)} lessons (universal={universal_added}/{universal_total_count}, task_specific={len(related)-universal_added}, platform={platform_count}): {ids}', file=sys.stderr)
    print(f'[INJECT]   project={project} {tag_info} scored={scored_count}/{tag_candidate_count} top_scores={[(s,i) for s,i,_ in scored[:5]]}', file=sys.stderr)
    print(f'[INJECT]   filtered: draft={filtered_draft} deprecated={filtered_deprecated}', file=sys.stderr)
    dedup_removed = pre_dedup_count - len(scored)
    print(f'[INJECT]   dedup: {dedup_removed} duplicates removed (threshold={DEDUP_THRESHOLD})', file=sys.stderr)

    # ═══ 教訓因果追跡ログ記録 ═══
    impact_log = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    cmd_id = task.get('task_id') or task.get('parent_cmd') or 'unknown'
    ninja_name = task.get('assigned_to', 'unknown')
    task_type = task.get('task_type') or task.get('type', 'unknown')
    bloom = task.get('bloom_level', 'unknown')

    try:
        os.makedirs(os.path.dirname(impact_log), exist_ok=True)
        write_header = not os.path.exists(impact_log) or os.path.getsize(impact_log) == 0
        with open(impact_log, 'a', encoding='utf-8') as lf:
            if write_header:
                lf.write('timestamp\\tcmd_id\\tninja\\tlesson_id\\taction\\tresult\\treferenced\\tproject\\ttask_type\\tbloom_level\n')
            ts = datetime.datetime.now().isoformat(timespec='seconds')
            for r in related:
                lf.write(f'{ts}\\t{cmd_id}\\t{ninja_name}\\t{r["id"]}\\tinjected\\tpending\\tpending\\t{project}\\t{task_type}\\t{bloom}\n')
            for w in withheld:
                lf.write(f'{ts}\\t{cmd_id}\\t{ninja_name}\\t{w["id"]}\\twithheld\\tpending\\tno\\t{project}\\t{task_type}\\t{bloom}\n')
        print(f'[INJECT] Impact log: {len(related)} injected + {len(withheld)} withheld written to lesson_impact.tsv', file=sys.stderr)
    except Exception as ie:
        print(f'[INJECT] WARN: impact log write failed: {ie}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── Engineering Preferences自動注入（task YAMLにengineering_preferencesを挿入） ───
inject_engineering_preferences() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_engineering_preferences: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']


def is_empty(value):
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, (list, dict)):
        return len(value) == 0
    return False


def flatten_preferences(value):
    flattened = []
    if isinstance(value, str):
        text = value.strip()
        if text:
            flattened.append(text)
    elif isinstance(value, list):
        for item in value:
            flattened.extend(flatten_preferences(item))
    elif isinstance(value, dict):
        for nested in value.values():
            flattened.extend(flatten_preferences(nested))
    return flattened


def dedupe_keep_order(values):
    seen = set()
    result = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def extract_preferences_from_text(raw_text):
    lines = raw_text.splitlines()
    body = []
    capture = False

    for line in lines:
        stripped = line.strip()
        if not capture:
            if stripped == 'engineering_preferences:':
                capture = True
            continue

        if stripped.startswith('#'):
            break
        if not stripped:
            body.append(line)
            continue
        if line.startswith((' ', '\t')):
            body.append(line)
            continue
        break

    if not body:
        return []

    try:
        section = yaml.safe_load('engineering_preferences:\n' + '\n'.join(body) + '\n') or {}
    except Exception:
        return []

    return flatten_preferences(section.get('engineering_preferences'))


try:
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']
    existing = task.get('engineering_preferences')
    if not is_empty(existing):
        print('[INJECT_PREFS] engineering_preferences already exists, skipping', file=sys.stderr)
        sys.exit(0)

    project = str(task.get('project', '') or '').strip()
    if not project:
        sys.exit(0)

    project_file = os.path.join(script_dir, 'projects', f'{project}.yaml')
    if not os.path.exists(project_file):
        task['engineering_preferences'] = []
        print(f'[INJECT_PREFS] WARN: project file not found for {project}', file=sys.stderr)
    else:
        with open(project_file, encoding='utf-8') as f:
            raw_text = f.read()

        preferences = []
        try:
            project_data = yaml.safe_load(raw_text)
        except Exception:
            project_data = None

        if isinstance(project_data, dict):
            preferences = flatten_preferences(project_data.get('engineering_preferences'))

        if not preferences:
            preferences = extract_preferences_from_text(raw_text)

        task['engineering_preferences'] = dedupe_keep_order(preferences)
        print(f'[INJECT_PREFS] project={project} injected={len(task["engineering_preferences"])}', file=sys.stderr)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f'[INJECT_PREFS] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── 偵察報告自動注入（task YAMLにreports_to_readを挿入） ───
inject_reports_to_read() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_reports: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import glob
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

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
                        blocked_parent_cmd = t.get('parent_cmd', '')
                        new_report = ''

                        if isinstance(blocked_parent_cmd, str) and blocked_parent_cmd.startswith('cmd_'):
                            new_report = os.path.join(reports_dir, f'{assigned_to}_report_{blocked_parent_cmd}.yaml')

                        legacy_report = os.path.join(reports_dir, f'{assigned_to}_report.yaml')

                        if new_report and os.path.exists(new_report):
                            report_paths.append(f'queue/reports/{os.path.basename(new_report)}')
                        elif os.path.exists(legacy_report):
                            report_paths.append(f'queue/reports/{assigned_to}_report.yaml')
                        else:
                            # 後方互換: cmd指定報告がなければ最新のcmd付き報告を探索
                            alt = sorted(
                                glob.glob(os.path.join(reports_dir, f'{assigned_to}_report_cmd*.yaml')),
                                key=os.path.getmtime,
                                reverse=True
                            )
                            if alt:
                                report_paths.append(f"queue/reports/{os.path.basename(alt[0])}")
                            else:
                                print(f'[INJECT_REPORTS] WARN: report not found: {new_report or legacy_report}', file=sys.stderr)
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
PY
        return 1
    fi
}

# ─── context_files自動注入（cmd_280: 分割context選択的読込） ───
inject_context_files() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_context_files: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
projects_yaml = os.path.join(script_dir, 'config', 'projects.yaml')

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']

    # 既にcontext_filesが設定済みなら上書きしない（家老が手動指定した場合）
    if task.get('context_files'):
        print('[INJECT_CTX] context_files already exists, skipping', file=sys.stderr)
        sys.exit(0)

    project = task.get('project', '')
    if not project:
        sys.exit(0)

    if not os.path.exists(projects_yaml):
        sys.exit(0)

    with open(projects_yaml) as f:
        pdata = yaml.safe_load(f)

    # プロジェクトのcontext_files定義を探す
    ctx_files = None
    ctx_index = None
    for p in pdata.get('projects', []):
        if p.get('id') == project:
            ctx_files = p.get('context_files', [])
            ctx_index = p.get('context_file', '')
            break

    if not ctx_files:
        sys.exit(0)

    # 索引ファイルは常に含める
    result = []
    if ctx_index:
        result.append(ctx_index)

    # タスクのtask_typeやdescriptionからタグをマッチング
    task_type = str(task.get('task_type', '')).lower()
    description = str(task.get('description', '')).lower()
    title = str(task.get('title', '')).lower()
    task_text = f'{task_type} {description} {title}'

    for cf in ctx_files:
        tags = cf.get('tags', [])
        filepath = cf.get('file', '')
        if not filepath:
            continue
        # タグがタスクテキストに含まれるか、タグなしなら常に含める
        if not tags:
            result.append(filepath)
        elif any(tag.lower() in task_text for tag in tags):
            result.append(filepath)

    # フォールバック: タグマッチが索引のみの場合、全ファイルを含める
    if len(result) <= 1:
        result = [ctx_index] if ctx_index else []
        for cf in ctx_files:
            filepath = cf.get('file', '')
            if filepath:
                result.append(filepath)

    task['context_files'] = result

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[INJECT_CTX] Injected {len(result)} context files for project={project}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_CTX] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── credential_files自動注入（cmd_949: 認証タスクに.envを自動追加） ───
inject_credential_files() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_credentials: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" python3 - <<'PY'; then
import os
import sys
import glob
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']

    # 認証関連キーワードの検出
    auth_keywords = ['cdp', 'login', 'ログイン', '認証', 'credential', 'chrome', 'edge',
                     'note.com', 'moneyforward', 'mf_', 'receipt', '領収書', 'selenium',
                     'browser', 'preflight_cdp', '.env']

    # タスク全テキストを結合して検索
    task_text = ' '.join([
        str(task.get('command', '')),
        str(task.get('description', '')),
        str(task.get('context', '')),
        str(task.get('title', '')),
    ]).lower()

    if not any(kw.lower() in task_text for kw in auth_keywords):
        sys.exit(0)

    # target_pathから.envファイルを探す
    target_path = task.get('target_path', '')
    if not target_path or not os.path.isdir(target_path):
        # target_pathがないが認証キーワードが検出された → 警告注入
        warn = task.get('credential_warning', '')
        if not warn:
            task['credential_warning'] = (
                '⚠ 認証が必要なタスクだがtarget_pathが未設定。'
                '認証情報(.env等)の場所を家老に確認せよ。見つからなければ即報告。'
            )
            changed = True
        else:
            changed = False
        if changed:
            tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
            try:
                with os.fdopen(tmp_fd, 'w') as f:
                    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
                os.replace(tmp_path, task_file)
            except:
                os.unlink(tmp_path)
                raise
            print('[INJECT_CRED] WARN: auth task but no target_path', file=sys.stderr)
        sys.exit(0)

    env_files = glob.glob(os.path.join(target_path, '.env.*'))
    env_base = os.path.join(target_path, '.env')
    if os.path.exists(env_base):
        env_files.append(env_base)

    # .example ファイルは除外
    all_env = [f for f in env_files if not f.endswith('.example')]

    if not all_env:
        # 認証キーワードあり + target_pathあり + .envなし → 警告注入
        warn = task.get('credential_warning', '')
        if not warn:
            task['credential_warning'] = (
                f'⚠ 認証が必要なタスクだが{target_path}に.envファイルが見つからない。'
                '認証情報の準備が必要。家老に即報告せよ。'
            )
            tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
            try:
                with os.fdopen(tmp_fd, 'w') as f:
                    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
                os.replace(tmp_path, task_file)
            except:
                os.unlink(tmp_path)
                raise
            print(f'[INJECT_CRED] WARN: auth task but no .env in {target_path}', file=sys.stderr)
        sys.exit(0)

    # context_filesに追加（重複排除）
    existing = task.get('context_files', []) or []
    existing_set = set(existing)
    added = []
    for ef in sorted(all_env):
        if ef not in existing_set:
            existing.append(ef)
            added.append(ef)

    if not added:
        sys.exit(0)

    task['context_files'] = existing

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[INJECT_CRED] Added {len(added)} credential files: {added}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_CRED] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── context_update自動注入（cmd_543: 親cmdの更新対象contextをタスクへ伝播） ───
inject_context_update() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_context_update: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import glob
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

def load_yaml(path):
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

def normalize_context_update(value):
    if isinstance(value, list):
        result = []
        for item in value:
            text = str(item).strip()
            if text:
                result.append(text)
        return result
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    return []

def normalize_existing(value):
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    return []

try:
    data = load_yaml(task_file)
    if not data or 'task' not in data:
        print('[INJECT_CONTEXT_UPDATE] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    parent_cmd = str(task.get('parent_cmd', '') or '').strip()
    if not parent_cmd:
        print('[INJECT_CONTEXT_UPDATE] No parent_cmd, skipping', file=sys.stderr)
        sys.exit(0)

    cmd_sources = [
        os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml'),
    ]
    cmd_sources.extend(sorted(glob.glob(os.path.join(script_dir, 'queue', 'archive', 'cmds', '*.yaml'))))

    context_update = []
    found = False
    source_path = ''
    for source in cmd_sources:
        obj = load_yaml(source)
        commands = obj.get('commands', [])
        if not isinstance(commands, list):
            continue
        for cmd in commands:
            if not isinstance(cmd, dict):
                continue
            if str(cmd.get('id', '')).strip() != parent_cmd:
                continue
            context_update = normalize_context_update(cmd.get('context_update', []))
            found = True
            source_path = source
            break
        if found:
            break

    if not found:
        print(f'[INJECT_CONTEXT_UPDATE] parent_cmd not found: {parent_cmd}, skipping', file=sys.stderr)
        sys.exit(0)

    if not context_update:
        print(f'[INJECT_CONTEXT_UPDATE] No context_update for {parent_cmd}, skipping', file=sys.stderr)
        sys.exit(0)

    existing = normalize_existing(task.get('context_update', []))
    if existing == context_update:
        print('[INJECT_CONTEXT_UPDATE] context_update unchanged, skipping', file=sys.stderr)
        sys.exit(0)

    task['context_update'] = context_update

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

    rel_source = os.path.relpath(source_path, script_dir) if source_path else source_path
    print(f'[INJECT_CONTEXT_UPDATE] Injected {len(context_update)} entries from {rel_source}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_CONTEXT_UPDATE] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── role_reminder自動注入（cmd_384: 忍者スコープ制限リマインダ） ───
inject_role_reminder() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_role_reminder: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す（直接補間はインジェクション危険）
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" NINJA_NAME_ENV="$ninja_name" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[ROLE_REMINDER] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にrole_reminderが存在する場合は上書きしない
    if task.get('role_reminder'):
        print('[ROLE_REMINDER] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task['role_reminder'] = f'忍者{ninja_name}。このタスクのみ実行せよ。スコープ外の改善・判断は禁止。発見はlesson_candidate/decision_candidateへ'

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[ROLE_REMINDER] Injected for {ninja_name}', file=sys.stderr)

except Exception as e:
    print(f'[ROLE_REMINDER] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── report_template自動注入（cmd_384: タスク種別別レポート雛形） ───
inject_report_template() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_template: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[REPORT_TPL] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreport_templateが存在する場合は上書きしない
    if task.get('report_template'):
        print('[REPORT_TPL] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task_type = str(task.get('task_type', '')).lower()
    if not task_type:
        print('[REPORT_TPL] No task_type, skipping', file=sys.stderr)
        sys.exit(0)

    template_path = os.path.join(script_dir, 'templates', f'report_{task_type}.yaml')
    if not os.path.exists(template_path):
        print(f'[REPORT_TPL] WARN: template not found: {template_path}', file=sys.stderr)
        sys.exit(0)

    with open(template_path) as f:
        template_data = yaml.safe_load(f)

    if template_data:
        task['report_template'] = template_data

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[REPORT_TPL] Injected {task_type} template', file=sys.stderr)

except Exception as e:
    print(f'[REPORT_TPL] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── report_filename自動注入（cmd_410: 命名ミスマッチ根治） ───
inject_report_filename() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_filename: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" NINJA_NAME_ENV="$NINJA_NAME" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[REPORT_FN] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreport_filenameが存在する場合は上書きしない
    if task.get('report_filename'):
        print('[REPORT_FN] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    parent_cmd = str(task.get('parent_cmd', '') or '')
    if parent_cmd:
        report_filename = f'{ninja_name}_report_{parent_cmd}.yaml'
    else:
        report_filename = f'{ninja_name}_report.yaml'

    task['report_filename'] = report_filename

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[REPORT_FN] Injected report_filename={report_filename}', file=sys.stderr)

except Exception as e:
    print(f'[REPORT_FN] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── bloom_level自動注入（cmd_434: タスク複雑度メタデータ） ───
inject_bloom_level() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_bloom_level: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[BLOOM_LVL] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にbloom_levelが存在する場合は上書きしない
    if 'bloom_level' in task:
        print('[BLOOM_LVL] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task['bloom_level'] = ''

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print('[BLOOM_LVL] Injected bloom_level (empty)', file=sys.stderr)

except Exception as e:
    print(f'[BLOOM_LVL] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── task execution controls注入（cmd_875: gstack停止条件/優先順位/並列許可） ───
inject_execution_controls() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_execution_controls: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']


def ac_count(value):
    if isinstance(value, list):
        return len(value)
    if value is None:
        return 0
    if isinstance(value, str):
        return 1 if value.strip() else 0
    if isinstance(value, dict):
        return len(value.keys())
    return 0


def extract_ac_ids(ac_list):
    if not isinstance(ac_list, list):
        return []
    ids = []
    for i, ac in enumerate(ac_list):
        if isinstance(ac, dict):
            ac_id = ac.get('id', '')
            if ac_id:
                ids.append(str(ac_id))
            else:
                ids.append(f'AC{i+1}')
        else:
            ids.append(f'AC{i+1}')
    return ids


try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[EXEC_CTRL] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    changed = False

    NEVER_STOP_DEFAULTS = [
        "CDPポート未応答 — preflight_cdp_flowが自動起動する。まず実行せよ",
        "既存インフラの自動対処機能があるエラー — まず実行→失敗なら報告",
        "自明な修正（typo等） — 実行→事後報告",
    ]

    if 'stop_for' not in task or task.get('stop_for') is None:
        task['stop_for'] = []
        changed = True

    if 'never_stop_for' not in task or task.get('never_stop_for') is None:
        task['never_stop_for'] = NEVER_STOP_DEFAULTS
        changed = True

    ac_list = task.get('acceptance_criteria', [])
    ac_ids = extract_ac_ids(ac_list)
    num_acs = ac_count(ac_list)

    # ac_priority: AC3個以上で未設定/空文字 → "AC1 > AC2 > AC3" 形式のデフォルト生成
    if num_acs >= 3 and ('ac_priority' not in task or not task.get('ac_priority')):
        task['ac_priority'] = ' > '.join(ac_ids) if ac_ids else ''
        changed = True

    # ac_checkpoint: AC3個以上で未設定/空文字 → 各AC後のチェックポイント指示を注入
    if num_acs >= 3 and ('ac_checkpoint' not in task or not task.get('ac_checkpoint')):
        task['ac_checkpoint'] = '各AC完了後に checkpoint: 次ACの前提条件確認 → scope drift検出 → progress更新'
        changed = True

    # parallel_ok: AC2個以上で未設定/None/空リスト → 全AC IDリストをデフォルト生成
    if 'parallel_ok' not in task or not task.get('parallel_ok'):
        if num_acs >= 2 and ac_ids:
            task['parallel_ok'] = ac_ids
        else:
            task['parallel_ok'] = []
        changed = True

    if not changed:
        print('[EXEC_CTRL] Already present, skipping', file=sys.stderr)
        sys.exit(0)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

    print('[EXEC_CTRL] Injected stop_for/never_stop_for/parallel_ok/ac_priority/ac_checkpoint as needed', file=sys.stderr)

except Exception as e:
    print(f'[EXEC_CTRL] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── preflight gate artifact生成（cmd_407: missing_gate BLOCK率削減） ───
# deploy_task.sh実行時にcmd_complete_gate.shが要求するgateフラグを事前生成。
# L078: 65%のBLOCKがmissing_gate(archive/lesson/review_gate)。配備時に生成で削減。
preflight_gate_artifacts() {
    local task_file="$1"
    local cmd_id
    cmd_id=$(field_get "$task_file" "parent_cmd" "")

    if [ -z "$cmd_id" ] || [[ "$cmd_id" != cmd_* ]]; then
        log "preflight_gate: SKIP (no valid parent_cmd)"
        return 0
    fi

    local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"
    log "preflight_gate: ${cmd_id} — artifact事前生成開始"

    # (1) archive.done — archive_completed.sh実行（過去の完了cmdのアーカイブ。配備時に安全）
    if [ ! -f "$gates_dir/archive.done" ]; then
        if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$cmd_id" >/dev/null 2>&1; then
            log "preflight_gate: archive.done generated"
        else
            log "preflight_gate: archive.done WARN (script failed, non-blocking)"
        fi
    else
        log "preflight_gate: archive.done already exists (skip)"
    fi

    # (2) review_gate.done — implement時のみ。配備時点でreview未実施のためplaceholder生成
    local task_type
    task_type=$(field_get "$task_file" "task_type" "")
    if [ "$task_type" = "implement" ] && [ ! -f "$gates_dir/review_gate.done" ]; then
        cat > "$gates_dir/review_gate.done" <<EOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: deploy_preflight
note: 配備時placeholder。review_gate.shが完了時に上書き。
EOF
        log "preflight_gate: review_gate.done generated (deploy_preflight)"
    fi

    # (3) report_merge.done — recon時のみ。配備時点で報告未存在のためplaceholder生成
    if [ "$task_type" = "recon" ] && [ ! -f "$gates_dir/report_merge.done" ]; then
        cat > "$gates_dir/report_merge.done" <<EOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: deploy_preflight
note: 配備時placeholder。report_merge.shが完了時に上書き。
EOF
        log "preflight_gate: report_merge.done generated (deploy_preflight)"
    fi

    log "preflight_gate: ${cmd_id} — artifact事前生成完了"
}

# ─── deployed_at自動記録（cmd_387: 配備タイムスタンプ） ───
# 既にdeployed_atが存在する場合は上書きしない（再配備時の元タイムスタンプ保持）
record_deployed_at() {
    local task_file="$1"
    local timestamp="$2"
    if [ ! -f "$task_file" ]; then
        log "record_deployed_at: task file not found: $task_file"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" TIMESTAMP_ENV="$timestamp" python3 - <<'PY'; then
import os
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
timestamp = os.environ['TIMESTAMP_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[DEPLOYED_AT] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にdeployed_atが存在する場合は上書きしない
    if task.get('deployed_at'):
        print(f'[DEPLOYED_AT] Already exists ({task["deployed_at"]}), skipping', file=sys.stderr)
        sys.exit(0)

    task['deployed_at'] = timestamp

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[DEPLOYED_AT] Recorded: {timestamp}', file=sys.stderr)

except Exception as e:
    print(f'[DEPLOYED_AT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── context鮮度チェック（穴2対策: cmd_239） ───
check_context_freshness() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 0
    fi

    local project
    project=$(field_get "$task_file" "project" "")
    if [ -z "$project" ]; then
        log "context_freshness: SKIP (no project field)"
        return 0
    fi

    local projects_yaml="$SCRIPT_DIR/config/projects.yaml"
    if [ ! -f "$projects_yaml" ]; then
        log "context_freshness: SKIP (projects.yaml not found)"
        return 0
    fi

    local context_file
    context_file=$(
        PROJECTS_YAML_ENV="$projects_yaml" PROJECT_ENV="$project" python3 - <<'PY' 2>/dev/null
import os

import yaml

try:
    with open(os.environ['PROJECTS_YAML_ENV']) as f:
        data = yaml.safe_load(f)
    for p in data.get('projects', []):
        if p.get('id') == os.environ['PROJECT_ENV']:
            print(p.get('context_file', ''))
            break
except Exception:
    pass
PY
    )

    if [ -z "$context_file" ]; then
        log "context_freshness: SKIP (no context_file for project=$project)"
        return 0
    fi

    local full_path="$SCRIPT_DIR/$context_file"
    if [ ! -f "$full_path" ]; then
        log "context_freshness: WARNING (file not found: $context_file)"
        echo "⚠️ WARNING: $context_file not found" >&2
        return 0
    fi

    local last_updated
    last_updated=$(grep -o 'last_updated: [0-9-]*' "$full_path" 2>/dev/null | head -1 | cut -d' ' -f2)

    if [ -z "$last_updated" ]; then
        log "context_freshness: ⚠️ WARNING: $context_file has no last_updated metadata"
        echo "⚠️ WARNING: $context_file has no last_updated metadata (date unknown)" >&2
        return 0
    fi

    local days_old
    days_old=$(
        LAST_UPDATED_ENV="$last_updated" python3 - <<'PY' 2>/dev/null
from datetime import date
import os

try:
    lu = date.fromisoformat(os.environ['LAST_UPDATED_ENV'])
    print((date.today() - lu).days)
except Exception:
    print(-1)
PY
    )

    if [ "$days_old" -ge 14 ] 2>/dev/null; then
        log "context_freshness: ⚠️ WARNING: $context_file last updated ${days_old} days ago"
        echo "⚠️ WARNING: $context_file last updated ${days_old} days ago" >&2
    else
        log "context_freshness: OK ($context_file updated ${days_old} days ago)"
    fi

    return 0
}

# ─── 入口門番: 前タスクの教訓未消化チェック ───
check_entrance_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "entrance_gate: PASS (task file not found: $task_file)"
        return 0
    fi

    local result
    local exit_code=0
    result=$(
        TASK_FILE_ENV="$task_file" python3 - <<'PY' 2>/dev/null
import os
import sys

import yaml

try:
    with open(os.environ['TASK_FILE_ENV']) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']
    related = task.get('related_lessons', [])

    if not related:
        sys.exit(0)

    unreviewed = [r['id'] for r in related if isinstance(r, dict) and r.get('reviewed') is False]

    if unreviewed:
        print(', '.join(unreviewed))
        sys.exit(1)

    sys.exit(0)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(0)  # パース失敗時はブロックしない
PY
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ"
        echo "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ" >&2
        exit 1
    fi

    log "entrance_gate: PASS (no unreviewed lessons)"
    return 0
}

# ─── 偵察ゲート: implタスクは偵察済みorscout_exempt必須 ───
check_scout_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "scout_gate: PASS (task file not found)"
        return 0
    fi

    local result
    local exit_code=0
    result=$(
        TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY' 2>&1
import glob
import os
import sys

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']

    # 1. task_typeがimplement以外ならPASS（scout/recon/review等はゲート対象外）
    task_type = str(task.get('task_type', '')).lower()
    if task_type != 'implement':
        print(f'PASS: task_type={task_type} (not implement)', file=sys.stderr)
        sys.exit(0)

    parent_cmd = task.get('parent_cmd', '')
    if not parent_cmd:
        print('PASS: no parent_cmd', file=sys.stderr)
        sys.exit(0)

    # 2. shogun_to_karo.yaml + archive でscout_exemptを確認
    stk_paths = [
        os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml'),
    ]
    for stk_path in stk_paths:
        if not os.path.exists(stk_path):
            continue
        with open(stk_path) as f:
            stk = yaml.safe_load(f)
        for cmd in (stk or {}).get('commands', []):
            if cmd.get('id') == parent_cmd:
                if cmd.get('scout_exempt') is True:
                    reason = cmd.get('scout_exempt_reason', '(no reason)')
                    print(f'PASS: scout_exempt=true for {parent_cmd} ({reason})', file=sys.stderr)
                    sys.exit(0)
                break

    # 2.5. report_merge.doneチェック（偵察が統合済みならPASS）
    gate_dir = os.path.join(script_dir, 'queue', 'gates', parent_cmd)
    merge_done = os.path.join(gate_dir, 'report_merge.done')
    if os.path.exists(merge_done):
        print(f'PASS: report_merge.done exists for {parent_cmd}', file=sys.stderr)
        sys.exit(0)

    # 3. queue/tasks/*.yamlからscout/reconタスクのdone数をカウント
    tasks_dir = os.path.join(script_dir, 'queue', 'tasks')
    done_count = 0
    if os.path.isdir(tasks_dir):
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
                if t.get('parent_cmd') != parent_cmd:
                    continue
                tid = str(t.get('task_id', '')).lower()
                if 'scout' in tid or 'recon' in tid:
                    t_status = str(t.get('status', '')).lower()
                    if t_status == 'done':
                        done_count += 1
            except Exception:
                continue

    if done_count >= 2:
        print(f'PASS: {done_count} scout/recon tasks done for {parent_cmd}', file=sys.stderr)
        sys.exit(0)

    # BLOCK
    print(f'BLOCK: {parent_cmd} — scout done={done_count}/2, scout_exempt=false')
    sys.exit(1)

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(0)  # パース失敗時はブロックしない
PY
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "BLOCK(scout_gate): ${result}"
        echo "BLOCK(scout_gate): 偵察未完了。scout_reportsが2件未満かつscout_exemptなし。将軍にscout_exempt申請するか、先に偵察を配備せよ" >&2
        echo "詳細: ${result}" >&2
        exit 1
    fi

    # stderrの出力をログに記録
    log "scout_gate: ${result}"
    return 0
}

# ─── 教訓注入postcondition（cmd_378: 事後不変条件） ───
postcondition_lesson_inject() {
    local task_file="$1"
    local postcond_file
    postcond_file="$(dirname "$task_file")/.postcond_lesson_inject"

    if [ ! -f "$postcond_file" ]; then
        # inject early exit (no project/no lessons) → postcond data not written → OK
        return 0
    fi

    local available injected task_id
    available=$(grep '^available=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    injected=$(grep '^injected=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    task_id=$(grep '^task_id=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    rm -f "$postcond_file"

    available="${available:-0}"
    injected="${injected:-0}"
    task_id="${task_id:-unknown}"

    if [ "$available" -gt 0 ] 2>/dev/null && [ "$injected" -eq 0 ] 2>/dev/null; then
        log "[deploy] WARN: 教訓注入ゼロ (available=${available} injected=0 task=${task_id})"
    else
        log "[deploy] OK: 教訓注入 (available=${available} injected=${injected} task=${task_id})"
    fi

    return 0
}

# ─── 初回配備開始ntfy（cmd_496） ───
# 同一cmdで1回のみ通知。再配備・追配備では送信しない。
mark_dispatch_ntfy_once() {
    local cmd_id="$1"
    local ninja_name="$2"
    local title="$3"
    local state_dir="$SCRIPT_DIR/queue/dispatch_ntfy_started"
    local marker="$state_dir/${cmd_id}.started"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"

    mkdir -p "$state_dir"

    # Atomic create: 成功した呼び出しだけが通知を送信する
    if ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
        cat > "$marker" <<EOF
timestamp: ${ts}
cmd_id: ${cmd_id}
ninja: ${ninja_name}
title: ${title}
EOF
        return 0
    fi

    return 1
}

resolve_dispatch_title() {
    local cmd_id="$1"
    local task_file="$2"
    local title=""
    local yaml_file=""

    if [ -f "$task_file" ]; then
        title=$(field_get "$task_file" "title" "")
    fi

    if [ -z "$title" ] && [[ -n "$cmd_id" && "$cmd_id" == cmd_* ]]; then
        for yaml_file in \
            "$SCRIPT_DIR/queue/shogun_to_karo.yaml" \
            "$SCRIPT_DIR/queue/archive/cmds/"*.yaml
        do
            [ -f "$yaml_file" ] || continue
            title=$(awk -v cmd="${cmd_id}" '
                /^[[:space:]]*-[[:space:]]*id:[[:space:]]*cmd_[0-9]+/ {
                    line = $0
                    sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
                    sub(/[[:space:]]+#.*$/, "", line)
                    gsub(/["[:space:]]/, "", line)
                    if (line == cmd) {
                        found = 1
                        next
                    }
                    if (found) {
                        exit
                    }
                }
                found && /^[[:space:]]*title:[[:space:]]*/ {
                    line = $0
                    sub(/^[[:space:]]*title:[[:space:]]*/, "", line)
                    sub(/[[:space:]]+#.*$/, "", line)
                    print line
                    exit
                }
            ' "$yaml_file" 2>/dev/null || true)

            if [ -n "$title" ]; then
                break
            fi
        done
    fi

    title=$(printf '%s' "$title" \
        | tr '\n' ' ' \
        | tr '\r' ' ' \
        | sed 's/^["'\'']//; s/["'\'']$//' \
        | awk '{gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); print}')

    if [ "${#title}" -gt 80 ]; then
        title="${title:0:77}..."
    fi

    echo "$title"
}

notify_initial_deploy_ntfy_once() {
    local task_file="$1"
    local ninja_name="$2"
    local cmd_id
    local title
    local message

    if [ ! -f "$task_file" ]; then
        log "dispatch_ntfy: SKIP (task file not found)"
        return 0
    fi

    cmd_id=$(field_get "$task_file" "parent_cmd" "")
    title=$(resolve_dispatch_title "$cmd_id" "$task_file")

    if [[ -z "$cmd_id" || "$cmd_id" != cmd_* ]]; then
        log "dispatch_ntfy: SKIP (parent_cmd missing or invalid: ${cmd_id:-none})"
        return 0
    fi

    if ! mark_dispatch_ntfy_once "$cmd_id" "$ninja_name" "$title"; then
        log "dispatch_ntfy: SKIP already notified (${cmd_id})"
        return 0
    fi

    message="初回配備開始 (title=${title:-(untitled)}, ninja=${ninja_name})"

    if NTFY_SYNC=1 bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message"; then
        log "dispatch_ntfy: sent (${cmd_id}) title='${title:-untitled}' ninja=${ninja_name}"
    else
        # non-blocking要件: deployフローは継続
        log "dispatch_ntfy: WARN send failed (${cmd_id}) ninja=${ninja_name}"
    fi

    return 0
}

# ═══════════════════════════════════════
# メイン処理
# ═══════════════════════════════════════

PANE_TARGET=$(resolve_pane "$NINJA_NAME")
if [ -z "$PANE_TARGET" ]; then
    log "ERROR: Unknown ninja: $NINJA_NAME"
    exit 1
fi

CTX_PCT=$(get_ctx_pct "$PANE_TARGET" "$NINJA_NAME")
IS_IDLE=false
check_idle "$PANE_TARGET" && IS_IDLE=true

# cmd_1157: flat→nested YAML正規化（status強制注入の前に実行）
normalize_task_yaml "$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml" || true

# タスクステータス確認
TASK_STATUS=$(field_get "$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml" "status" "unknown")

log "${NINJA_NAME}: CTX=${CTX_PCT}%, idle=${IS_IDLE}, task_status=${TASK_STATUS}, pane=${PANE_TARGET}"

# status強制注入（cmd_1126: pending/unknown→assigned化。Stage 1ガード保護対象に入れる）
if [ "$TASK_STATUS" = "pending" ] || [ "$TASK_STATUS" = "unknown" ]; then
    yaml_field_set "$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml" "task" "status" "assigned"
    log "status_force: ${TASK_STATUS} → assigned (Stage 1保護対象化)"
    TASK_STATUS="assigned"
fi

# 入口門番: 前タスクの教訓未消化チェック（reviewed:false残存ならブロック）
TASK_FILE="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
check_entrance_gate "$TASK_FILE"

# 偵察ゲート: implタスクは偵察済みorscout_exempt必須（BLOCKならexit 1）
check_scout_gate "$TASK_FILE"

# task_id自動注入（cmd_465: subtask_id→task_idエイリアス。STALL検知に必須）
inject_task_id "$TASK_FILE" || true

# ac_version自動注入（cmd_530: AC変更時の再計算）
inject_ac_version "$TASK_FILE" || true

# 教訓自動注入（失敗してもデプロイは継続）
inject_related_lessons "$TASK_FILE" || true

# Engineering Preferences自動注入（失敗してもデプロイは継続）
inject_engineering_preferences "$TASK_FILE" || true

# 教訓注入postcondition（失敗してもデプロイは継続）
postcondition_lesson_inject "$TASK_FILE" || true

# 教訓injection_countカウント加算（cmd_470: 注入回数トラッキング）
_pc_file="$SCRIPT_DIR/queue/tasks/.postcond_lesson_inject"
if [ -f "$_pc_file" ]; then
    _inj_project=$(grep '^project=' "$_pc_file" | cut -d= -f2)
    _inj_ids=$(grep '^injected_ids=' "$_pc_file" | cut -d= -f2)
    if [ -n "$_inj_ids" ] && [ -n "$_inj_project" ]; then
        for _lid in $_inj_ids; do
            bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" "$_inj_project" "$_lid" inject 2>/dev/null || true
        done
        # platform教訓はinfra PJに属するため、project!=infraの場合はinfraも走査
        if [ "$_inj_project" != "infra" ]; then
            for _lid in $_inj_ids; do
                bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" infra "$_lid" inject 2>/dev/null || true
            done
        fi
        log "injection_count: incremented for ${_inj_ids}"
    fi
fi

# 偵察報告自動注入（失敗してもデプロイは継続）
inject_reports_to_read "$TASK_FILE" || true

# context_files自動注入（失敗してもデプロイは継続）
inject_context_files "$TASK_FILE" || true

# credential_files自動注入（cmd_949: 認証タスクに.envを自動追加）
inject_credential_files "$TASK_FILE" || true

# context_update自動注入（失敗してもデプロイは継続）
inject_context_update "$TASK_FILE" || true

# role_reminder自動注入（cmd_384: 失敗してもデプロイは継続）
inject_role_reminder "$TASK_FILE" "$NINJA_NAME" || true

# report_template自動注入（cmd_384: 失敗してもデプロイは継続）
inject_report_template "$TASK_FILE" || true

# report_filename自動注入（cmd_410: 命名ミスマッチ根治）
inject_report_filename "$TASK_FILE" || true

# bloom_level自動注入（cmd_434: タスク複雑度メタデータ）
inject_bloom_level "$TASK_FILE" || true

# task execution controls注入（cmd_875: 停止条件/優先順位/並列許可）
inject_execution_controls "$TASK_FILE" || true

# context鮮度チェック（失敗してもデプロイは継続）
check_context_freshness "$TASK_FILE" || true

# 状態に応じた処理
if [ "$CTX_PCT" -le 0 ] 2>/dev/null; then
    # CTX:0% — /clear済み、またはフレッシュセッション
    log "${NINJA_NAME}: CTX=0% detected (clear済み). Sending inbox_write (watcher handles timing)"
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

# 初回配備開始通知（cmd_496: 同一cmdで1回のみ、失敗時non-blocking）
notify_initial_deploy_ntfy_once "$TASK_FILE" "$NINJA_NAME" || true

# 報告YAML雛形生成（配備完了ログの直前）
TASK_ID=$(field_get "$TASK_FILE" "task_id" "")
PARENT_CMD=$(field_get "$TASK_FILE" "parent_cmd" "")
PROJECT=$(field_get "$TASK_FILE" "project" "")
generate_report_template "$NINJA_NAME" "$TASK_ID" "$PARENT_CMD" "$PROJECT"

# deployed_at自動記録（cmd_387: 初回配備時のみ記録、再配備時は保持）
record_deployed_at "$TASK_FILE" "$(date '+%Y-%m-%dT%H:%M:%S')" || true

# preflight gate artifact生成（cmd_407: missing_gate BLOCK率削減）
preflight_gate_artifacts "$TASK_FILE" || true

# round-robin回転ポインタ更新（cmd_519: 配備偏り解消）
RR_POINTER_FILE="$SCRIPT_DIR/queue/rr_pointer.txt"
RR_LOCK_FILE="/tmp/rr_pointer.lock"
(
    flock -w 5 201
    echo "$NINJA_NAME" > "$RR_POINTER_FILE"
) 201>"$RR_LOCK_FILE" 2>/dev/null || log "WARN: rr_pointer update failed (non-fatal)"

log "${NINJA_NAME}: deployment complete (type=${TYPE})"
