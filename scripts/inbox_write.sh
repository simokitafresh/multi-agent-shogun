#!/bin/bash
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from]
# Example: bash scripts/inbox_write.sh karo "半蔵、任務完了" report_received hanzo
#
# Supported types:
#   wake_up              — デフォルト。汎用起動通知
#   task_assigned        — タスク配備通知（家老→忍者）
#   task_cancel          — タスク取消通知（家老→忍者）
#   cmd_new              — 新cmd通知（将軍→家老）
#   report_received      — 忍者報告完了通知（忍者→家老）※報告YAML検証+auto-done hookあり
#   uncommitted_block    — 未commitブロック通知
#   review_draft         — draft cmdレビュー依頼（家老→軍師）
#   review_result        — レビュー結果（軍師→家老）
#   review_feedback      — GATEフィードバック（家老→軍師）
#   report_review        — 忍者報告一次レビュー依頼（家老→軍師）
#   report_review_result — 忍者報告レビュー結果（軍師→家老）
#   workaround_feedback  — workaround原因共有（家老→軍師）
#   review_hint          — レビューヒント（家老→軍師）
#   analysis_result      — idle時データ分析結果（軍師→家老）
#   gunshi_lesson_candidate — 軍師教訓候補（軍師→家老）
#   decomposition_feedback  — 分解フィードバック（軍師→家老）
#   verify_request       — RC修正再検証依頼（家老→軍師）
#   verify_result        — RC修正再検証結果（軍師→家老）
#   clear_command        — /clear送信（特殊: inbox_watcherがCLI直接操作）
#   model_switch         — /model切替（特殊: inbox_watcherがCLI直接操作）
#   recovery             — 復帰通知

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
if [ "${INBOX_WRITE_TEST:-}" != "1" ] && [ -f "$SCRIPT_DIR/scripts/lib/agent_config.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    NINJA_NAMES=$(get_ninja_names)
else
    NINJA_NAMES=""
fi
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$TARGET" == cmd_* ]]; then
    echo "ERROR: 第1引数はtarget_agent（例: karo, hanzo）。cmd_idではない。" >&2
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# HIGH-2: パストラバーサル防止 + sender/target制約
# INBOX_WRITE_TEST=1 or agent_config.sh未ロード: テスト環境でバリデーションをスキップ
if [ "${INBOX_WRITE_TEST:-}" != "1" ] && type get_allowed_targets &>/dev/null; then
    ALLOWED_TARGETS=$(get_allowed_targets)
    valid_target=0
    for allowed in $ALLOWED_TARGETS; do
        if [ "$TARGET" = "$allowed" ]; then
            valid_target=1
            break
        fi
    done
    if [ "$valid_target" -eq 0 ]; then
        echo "ERROR: Invalid target agent: '$TARGET'. Allowed: $ALLOWED_TARGETS" >&2
        exit 1
    fi

    is_ninja_sender=0
    for ninja in $NINJA_NAMES; do
        if [ "$FROM" = "$ninja" ]; then
            is_ninja_sender=1
            break
        fi
    done

    if [ "$is_ninja_sender" -eq 1 ] && [ "$TARGET" = "shogun" ]; then
        echo "ERROR: Ninja cannot send inbox to shogun directly. Use karo as relay." >&2
        exit 1
    fi

    if [ "$FROM" = "ninja_monitor" ] && [ "$TARGET" != "karo" ] && [ "$TARGET" != "shogun" ]; then
        echo "ERROR: ninja_monitor can send only to karo or shogun." >&2
        exit 1
    fi
fi

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    mkdir -p "$(dirname "$INBOX")"
    echo "messages: []" > "$INBOX"
fi

# Generate unique message ID (timestamp-based)
MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

# Pre-action auto-capture: 将軍→エージェント送信時、送信先ペインの現在状態を送信前に自動表示+ログ
# 目的: 「観察なき行動」を構造的に防止（知性の外部化原則 2026-03-21）
if [ "$FROM" = "shogun" ] || [ "$FROM" = "karo" ]; then
    _pane_idx=""
    while IFS=' ' read -r _idx _aid; do
        if [ "$_aid" = "$TARGET" ]; then
            _pane_idx="$_idx"
            break
        fi
    done < <(tmux list-panes -t shogun:agents -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)

    if [ -n "$_pane_idx" ]; then
        _capture=$(tmux capture-pane -t "shogun:agents.${_pane_idx}" -p 2>/dev/null | tail -8 || true)
        echo "[pre-send capture] ${TARGET} pane state BEFORE message:"
        echo "$_capture"
        echo "---"
        # Persistent log (survives /clear, enables post-mortem)
        _logdir="$SCRIPT_DIR/logs"
        mkdir -p "$_logdir"
        printf '%s [%s→%s type=%s] pane:\n%s\n---\n' \
            "$TIMESTAMP" "$FROM" "$TARGET" "$TYPE" "$_capture" \
            >> "$_logdir/shogun_action_log.txt" 2>/dev/null || true
    fi
fi

# Report format gate: type=report_received → 報告YAMLのフォーマット検証
# 目的: 家老の手動修正作業を根絶（karo_workarounds 5件連続同一問題を自動化×強制で解消）
if [ "$TYPE" = "report_received" ]; then
    # Find report YAML path from task YAML
    is_ninja_reporter=0
    for ninja in $NINJA_NAMES; do
        if [ "$FROM" = "$ninja" ]; then
            is_ninja_reporter=1
            break
        fi
    done

    if [ "$is_ninja_reporter" -eq 1 ]; then
        TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
        if [ -f "$TASK_YAML" ]; then
            REPORT_PATH=$(TASK_PATH="$TASK_YAML" python3 -c "
import yaml, os
try:
    with open(os.environ['TASK_PATH']) as f:
        data = yaml.safe_load(f)
    if data and 'task' in data:
        rp = data['task'].get('report_path', '')
        if rp:
            print(rp)
except:
    pass
" 2>/dev/null || true)

            FULL_REPORT=""
            if [ -n "$REPORT_PATH" ]; then
                FULL_REPORT="$SCRIPT_DIR/$REPORT_PATH"
            else
                # Fallback: report_path未設定 → queue/reports/{from}_report_{cmd_id}*.yaml を検索
                CMD_ID=$(TASK_PATH="$TASK_YAML" python3 -c "
import yaml, os
try:
    with open(os.environ['TASK_PATH']) as f:
        data = yaml.safe_load(f)
    if data and 'task' in data:
        pc = data['task'].get('parent_cmd', '')
        if pc:
            print(pc)
except:
    pass
" 2>/dev/null || true)
                if [ -n "$CMD_ID" ]; then
                    FALLBACK=$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -name "${FROM}_report_${CMD_ID}*.yaml" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2- || true)
                    if [ -n "$FALLBACK" ]; then
                        FULL_REPORT="$FALLBACK"
                        echo "[report_format_gate] fallback: report_path未設定 → $(basename "$FALLBACK") を検出" >&2
                    else
                        echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: queue/reports/${FROM}_report_${CMD_ID}*.yaml" >&2
                        exit 1
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: report_path未設定 + parent_cmd未設定 (ninja: ${FROM})" >&2
                    exit 1
                fi
            fi

            if [ -n "$FULL_REPORT" ]; then
                if [ -f "$FULL_REPORT" ]; then
                    # Phase 1: 機械的フォーマット自動修正（忍者ペインで局所免疫）
                    AUTOFIX_RESULT=$("$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$FULL_REPORT" 2>&1 || true)
                    if echo "$AUTOFIX_RESULT" | grep -q "^AUTO-FIXED"; then
                        echo "[report_autofix] $AUTOFIX_RESULT" >&2
                    fi
                    # Phase 2: フォーマット検証（auto-fix後に実行）
                    GATE_RESULT=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$FULL_REPORT" 2>&1 || true)
                    if echo "$GATE_RESULT" | grep -q "^FAIL"; then
                        # Phase 3: 品質問題→軍師に自動ルーティング（第二層分離）
                        # auto-fixで直せない = 品質判断が必要 = 軍師の仕事
                        GUNSHI_INBOX="$SCRIPT_DIR/queue/inbox/gunshi.yaml"
                        ROUTE_TS=$(date -Is)
                        ROUTE_ID="msg_$(date +%s%N | head -c 16)"
                        GATE_ERRORS=${GATE_RESULT//\"/\\\"}
                        (
                            flock -w 5 200 2>/dev/null
                            GUNSHI_INBOX="$GUNSHI_INBOX" ROUTE_ID="$ROUTE_ID" ROUTE_TS="$ROUTE_TS" \
                            ROUTE_FROM="$FROM" REPORT_FILE="$FULL_REPORT" GATE_ERRORS="$GATE_ERRORS" \
                            python3 -c "
import yaml, os, sys
inbox_path = os.environ['GUNSHI_INBOX']
try:
    with open(inbox_path) as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}
msgs = data.get('messages', [])
msgs.append({
    'id': os.environ['ROUTE_ID'],
    'from': 'system',
    'timestamp': os.environ['ROUTE_TS'],
    'type': 'quality_fix_request',
    'read': False,
    'content': f\"忍者{os.environ['ROUTE_FROM']}の報告YAMLに品質問題。auto-fix不可のため軍師に転送。修正後にinbox_writeでkaroに送信せよ。\",
    'report_path': os.environ['REPORT_FILE'],
    'gate_errors': os.environ['GATE_ERRORS'],
    'original_ninja': os.environ['ROUTE_FROM'],
})
data['messages'] = msgs
with open(inbox_path, 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
" 2>/dev/null
                        ) 200>"$GUNSHI_INBOX.lock" 2>/dev/null || true
                        echo "[report_quality_route] 品質問題を軍師に転送: $GATE_RESULT" >&2
                        echo "[report_quality_route] 軍師が修正→karoに再送信する。忍者${FROM}は次のタスクに進んでよい" >&2
                        # 忍者をブロックしない — 品質問題は軍師が処理。メッセージはkaroに届けない
                        exit 0
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: $FULL_REPORT" >&2
                    exit 1
                fi
            fi

            # Git uncommitted check: 報告YAMLのfiles_modified + task YAMLのtarget_pathを確認
            # cmd_1296教訓: 全repoではなく忍者が申告したファイルのみチェック（運用ファイル誤検知防止）
            # サイクル2: WARNING→BLOCK昇格。commit漏れは忍者ペインで止める（局所免疫）
            GIT_CHECK_PATHS=$(REPORT_YAML="$FULL_REPORT" TASK_PATH="$TASK_YAML" python3 -c "
import yaml, os
paths = set()
# Source 1: 報告YAMLのfiles_modified（auto-fix後はdict list形式）
try:
    rp = os.environ.get('REPORT_YAML', '')
    if rp and os.path.isfile(rp):
        with open(rp) as f:
            rdata = yaml.safe_load(f)
        if rdata:
            fm = rdata.get('files_modified', [])
            if isinstance(fm, list):
                for item in fm:
                    if isinstance(item, dict) and 'path' in item:
                        paths.add(item['path'])
                    elif isinstance(item, str):
                        paths.add(item)
except Exception:
    pass
# Source 2: task YAMLのtarget_path/files（fallback）
try:
    tp = os.environ.get('TASK_PATH', '')
    if tp and os.path.isfile(tp):
        with open(tp) as f:
            tdata = yaml.safe_load(f)
        if tdata and 'task' in tdata:
            task = tdata['task']
            t = task.get('target_path', '')
            if isinstance(t, str) and t:
                paths.add(t)
            elif isinstance(t, list):
                paths.update(p for p in t if isinstance(p, str) and p)
            files = task.get('files', [])
            if isinstance(files, str) and files:
                paths.add(files)
            elif isinstance(files, list):
                paths.update(p for p in files if isinstance(p, str) and p)
except Exception:
    pass
for p in sorted(paths):
    print(p)
" 2>/dev/null || true)

            if [ -n "$GIT_CHECK_PATHS" ]; then
                mapfile -t _check_paths <<< "$GIT_CHECK_PATHS"
                UNCOMMITTED=$(git -C "$SCRIPT_DIR" status --porcelain -- "${_check_paths[@]}" 2>/dev/null || true)
                if [ -n "$UNCOMMITTED" ]; then
                    echo "[git_uncommitted_gate] BLOCKED: 未commitファイルあり (ninja: ${FROM})" >&2
                    while IFS= read -r _uline; do
                        echo "  $_uline" >&2
                    done <<< "$UNCOMMITTED"
                    echo "[git_uncommitted_gate] git add + git commitを実行してから報告せよ" >&2
                    exit 1
                fi
            fi
        fi
    fi
fi

# Atomic write with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        # Add message via python3 — HIGH-1: 全変数を環境変数経由で渡す（インジェクション防止）
        INBOX_PATH="$INBOX" MSG_ID="$MSG_ID" MSG_FROM="$FROM" \
        MSG_TIMESTAMP="$TIMESTAMP" MSG_TYPE="$TYPE" MSG_CONTENT="$CONTENT" \
        python3 -c "
import yaml, sys, os

try:
    inbox_path  = os.environ['INBOX_PATH']
    msg_id      = os.environ['MSG_ID']
    msg_from    = os.environ['MSG_FROM']
    msg_ts      = os.environ['MSG_TIMESTAMP']
    msg_type    = os.environ['MSG_TYPE']
    msg_content = os.environ['MSG_CONTENT']

    # Load existing inbox
    with open(inbox_path) as f:
        data = yaml.safe_load(f)

    # Initialize if needed
    if not data:
        data = {}
    if not data.get('messages'):
        data['messages'] = []

    # Add new message
    new_msg = {
        'id':        msg_id,
        'from':      msg_from,
        'timestamp': msg_ts,
        'type':      msg_type,
        'content':   msg_content,
        'read':      False
    }
    data['messages'].append(new_msg)

    # Overflow protection: keep max 50 messages
    if len(data['messages']) > 50:
        msgs   = data['messages']
        unread = [m for m in msgs if not m.get('read', False)]
        read   = [m for m in msgs if m.get('read', False)]
        # Keep all unread + newest 30 read messages
        data['messages'] = unread + read[-30:]

    # Atomic write: tmp file + rename (prevents partial reads)
    import tempfile
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

    ) 200>"$LOCKFILE"; then
        # Success — inbox message persisted

        # Hook: report_received from ninja → auto-update task YAML to done
        if [ "$TYPE" = "report_received" ]; then
            is_ninja=0
            for ninja in $NINJA_NAMES; do
                if [ "$FROM" = "$ninja" ]; then
                    is_ninja=1
                    break
                fi
            done

            if [ "$is_ninja" -eq 1 ]; then
                TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
                TASK_LOCKFILE="${TASK_YAML}.lock"

                if [ -f "$TASK_YAML" ]; then
                    # Report YAML existence verification before done transition (cmd_813)
                    REPORT_FILENAME=$(TASK_PATH="$TASK_YAML" NINJA_NAME="$FROM" python3 -c "
import yaml, os
try:
    with open(os.environ['TASK_PATH']) as f:
        data = yaml.safe_load(f)
    if data and 'task' in data:
        rf = data['task'].get('report_filename', '')
        if rf:
            print(rf)
        else:
            pc = data['task'].get('parent_cmd', '')
            if pc:
                print(os.environ['NINJA_NAME'] + '_report_' + pc + '.yaml')
except:
    pass
" 2>/dev/null || true)

                    report_found=0
                    if [ -n "$REPORT_FILENAME" ]; then
                        if [ -f "$SCRIPT_DIR/queue/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                        elif [ -f "$SCRIPT_DIR/queue/archive/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                        else
                            # Archive files may have date suffix
                            base="${REPORT_FILENAME%.yaml}"
                            shopt -s nullglob
                            archived=("$SCRIPT_DIR/queue/archive/reports/${base}"_*.yaml)
                            shopt -u nullglob
                            if [ "${#archived[@]}" -gt 0 ]; then
                                report_found=1
                            fi
                        fi
                    fi

                    if [ "$report_found" -eq 0 ]; then
                        echo "[inbox_write] auto-done BLOCKED: report YAML not found: ${REPORT_FILENAME:-unknown} (ninja: $FROM)" >&2
                    else
                        (
                            flock -w 5 201 || exit 0  # Lock failure is non-fatal

                            TASK_PATH="$TASK_YAML" python3 -c "
import yaml, tempfile, os, sys

task_path = os.environ['TASK_PATH']
try:
    with open(task_path) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    current_status = data['task'].get('status', '')
    # done/failed/blocked — do not overwrite (idempotent)
    if current_status in ('done', 'failed', 'blocked'):
        sys.exit(0)

    # assigned/in_progress → done
    data['task']['status'] = 'done'

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_path)
    except:
        os.unlink(tmp_path)
        raise
except Exception as e:
    print(f'[inbox_write] task-auto-done WARN: {e}', file=sys.stderr)
"
                        ) 201>"$TASK_LOCKFILE"
                    fi
                fi
            fi
        fi

        exit 0
    else
        # Lock timeout or error
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX (target=$TARGET, from=$FROM)" >&2
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "[inbox_write] FAIL: lock取得失敗 target=$TARGET from=$FROM" 2>/dev/null || true
            exit 1
        fi
    fi
done
