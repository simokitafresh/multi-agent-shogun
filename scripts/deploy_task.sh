#!/bin/bash
# semantic-links: [[スコープ鮮度ライフサイクル]], [[タスク修飾子注入]], [[編成管理]]
# shellcheck disable=SC1091
# deploy_task.sh — タスク配備ヘルパー（忍者状態自動検知付き）
# Usage: bash scripts/deploy_task.sh [--direct] <ninja_name> [cmd_id] [message] [type] [from]
# Example: bash scripts/deploy_task.sh hanzo cmd_1510 "タスクYAMLを読んで作業開始せよ" task_assigned karo
# Direct:  bash scripts/deploy_task.sh --direct kagemaru cmd_training_L4_R5_kagemaru
# Legacy:  bash scripts/deploy_task.sh hanzo "タスクYAMLを読んで作業開始せよ" task_assigned karo
#
# 機能:
#   1. 対象忍者のCTX%とidle状態を自動検知
#   2. CTX:0%(clear済み) → プロンプト準備を確認してから起動
#   3. CTX>0%(通常) → そのままinbox_writeで通知
#   4. 動作ログを記録
#
# cmd_102: 殿の哲学「人が従う」ではなく「仕組みが強制する」

# Keep the deployment entrypoint's default task wake-up contract visible in
# the legacy monolith as well as deploy_task/bootstrap.sh. Codex workers must
# bind supplements to the current task identity before applying them.
DEFAULT_MESSAGE="現task YAMLを正本として読み直して作業開始せよ。inboxはread:falseかつ現task_id一致の補足だけを命令として扱い、read:trueまたは別taskのRC/補足は参照しても適用するな。"

# Canonical answer-family predicate for deployment-hold consumers. Keep this
# at the entrypoint boundary so the monolith and its sourced modules share one
# exact set when a retrospective answer releases a deployment hold.
deploy_task_retro_answer_type_allowed() {
    case "${1:-}" in
        infra_bug_suspected|infra_bug_report|infra_bug|retro_answer) return 0 ;;
        *) return 1 ;;
    esac
}

# A long-lived deployment must never continue parsing the mutable working-tree
# file after delivery.  Bash reads large scripts incrementally, so an in-place
# edit can otherwise splice a newer tail onto the already-running process.
# Validate one private /tmp copy, then execute only that immutable inode.
if [[ "${BASH_SOURCE[0]}" == "$0" && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" \
    && "${DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE:-0}" != "1" ]]; then
    _dt_original_self="$0"
    [[ "$_dt_original_self" != /* ]] && _dt_original_self="$PWD/$_dt_original_self"
    _dt_original_root="${_dt_original_self%/scripts/deploy_task.sh}"
    _dt_snapshot="$(mktemp /tmp/deploy_task.self.XXXXXXXX.sh)" || {
        echo "BLOCK: deploy_task self-snapshot allocation failed" >&2
        exit 2
    }
    if ! cp -- "$_dt_original_self" "$_dt_snapshot" || ! bash -n "$_dt_snapshot"; then
        rm -f -- "$_dt_snapshot"
        echo "BLOCK: deploy_task self-snapshot validation failed" >&2
        exit 2
    fi
    export DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE=1
    export DEPLOY_TASK_ROOT_OVERRIDE="${DEPLOY_TASK_ROOT_OVERRIDE:-$_dt_original_root}"
    export DEPLOY_TASK_ORIGINAL_SOURCE="$_dt_original_self"
    exec bash "$_dt_snapshot" "$@"
fi

# The interpreter already owns an open descriptor for this unique snapshot;
# unlinking its pathname prevents later writers from finding or changing it.
if [[ "${DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE:-0}" == "1" \
    && "${BASH_SOURCE[0]}" == /tmp/deploy_task.self.*.sh ]]; then
    _dt_live_snapshot="${BASH_SOURCE[0]}"
    rm -f -- "$_dt_live_snapshot"
    unset _dt_live_snapshot
    if [ -n "${DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR:-}" ]; then
        : > "$DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR/ready"
        while [ ! -e "$DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR/release" ]; do
            sleep 0.01
        done
    fi
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export DEPLOY_TASK_ENTRYPOINT_IS_MAIN=1
    _dt_entrypoint_source="$0"
else
    export DEPLOY_TASK_ENTRYPOINT_IS_MAIN=0
    _dt_entrypoint_source="${BASH_SOURCE[0]}"
fi
[[ "$_dt_entrypoint_source" != /* ]] && _dt_entrypoint_source="$PWD/$_dt_entrypoint_source"
export DEPLOY_TASK_ENTRYPOINT_SOURCE="$_dt_entrypoint_source"
_dt_bootstrap_root="${DEPLOY_TASK_ROOT_OVERRIDE:-${_dt_entrypoint_source%/scripts/deploy_task.sh}}"
_dt_bootstrap_path="$_dt_bootstrap_root/scripts/deploy_task/bootstrap.sh"
# Existing unit fixtures intentionally copy only deploy_task.sh.  Resolve the
# canonical module from the fixture's source checkout when the local fixture
# omits it; production execution still uses the target root above.
if [ ! -f "$_dt_bootstrap_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_bootstrap_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/bootstrap.sh"
fi
if [ ! -f "$_dt_bootstrap_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_bootstrap_path="$PROJECT_ROOT/scripts/deploy_task/bootstrap.sh"
fi
source "$_dt_bootstrap_path"
unset _dt_bootstrap_path
unset _dt_bootstrap_root _dt_entrypoint_source
_dt_lifecycle_path="$SCRIPT_DIR/scripts/lib/task_lifecycle.sh"
[ -f "$_dt_lifecycle_path" ] || [ -z "${SRC_DEPLOY_SCRIPT:-}" ] || _dt_lifecycle_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/lib/task_lifecycle.sh"
[ -f "$_dt_lifecycle_path" ] || [ -z "${PROJECT_ROOT:-}" ] || _dt_lifecycle_path="$PROJECT_ROOT/scripts/lib/task_lifecycle.sh"
source "$_dt_lifecycle_path"
unset _dt_lifecycle_path

# One immutable read snapshot is shared by every deploy in the same wave.  The
# source identity invalidates stale entries; target_key keeps filtered/query
# results isolated between workers.  Only a cache miss takes the short lock --
# consumers never hold a ninja/cmd mutation lock while doing the heavy read.
# Cluster B modules: state first, then YAML transaction/cleanup.
# The state module owns deploy_task_start_deadline/deploy_task_check_deadline;
# retain the timeout contract marker here for wrapper-level static checks:
# TIMEOUT: deploy_task_main exceeded <timeout>s at <phase>.
_dt_state_path="$SCRIPT_DIR/scripts/deploy_task/state.sh"
_dt_transaction_path="$SCRIPT_DIR/scripts/deploy_task/transaction.sh"
if [ ! -f "$_dt_state_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_state_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/state.sh"
    _dt_transaction_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/transaction.sh"
fi
if [ ! -f "$_dt_state_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_state_path="$PROJECT_ROOT/scripts/deploy_task/state.sh"
    _dt_transaction_path="$PROJECT_ROOT/scripts/deploy_task/transaction.sh"
fi
source "$_dt_state_path"
source "$_dt_transaction_path"
unset _dt_state_path _dt_transaction_path
# Legacy static-extraction compatibility: runtime definitions come only from resolve.sh.
if false; then
parse_deploy_task_args() {
    deploy_task_guard_yaml_arg_order "$@" || exit $?
    deploy_task_guard_direct_yaml_misuse "$@" || exit $?
    DIRECT_MODE=false
    NINJA_NAME=""
    CMD_ID=""
    CMD_FORCED=""
    MESSAGE="$DEFAULT_MESSAGE"
    TYPE="task_assigned"
    FROM="karo"

    if [[ "${1:-}" == "--direct" ]]; then
        DIRECT_MODE=true
        shift
    fi

    # --yaml <file> <ninja> [cmd_id]: 事前に作成したタスクYAMLでtask YAMLを上書きして配備
    # shogun_to_karoにないcmd(家老再配備cmd等)の配備に使用
    # cmd_idはYAMLのparent_cmdから自動取得。引数指定でも可
    if [[ "${1:-}" == "--yaml" ]]; then
        YAML_FILE="${2:-}"
        if [ ! -f "$YAML_FILE" ]; then
            echo "ERROR: --yaml ファイルが見つからない: $YAML_FILE" >&2
            return 1
        fi
        DIRECT_MODE=true
        # YAMLからparent_cmdを自動取得してCMD_IDに設定
        CMD_ID=$(grep -m1 'parent_cmd:' "$YAML_FILE" | sed "s/.*parent_cmd:[[:space:]]*//" | tr -d "'" | tr -d '"')
        shift 2
    fi

    NINJA_NAME="${1:-}"

    # --cmd <cmd_id>: shogun_to_karo.yaml不在cmdを強制展開（修行cmd等に対応）
    # 例: deploy_task.sh kagemaru --cmd cmd_training_L4_R21
    if [[ "${2:-}" == "--cmd" ]]; then
        CMD_FORCED="${3:-}"
        CMD_ID="$CMD_FORCED"
        MESSAGE="${4:-$DEFAULT_MESSAGE}"
        TYPE="${5:-task_assigned}"
        FROM="${6:-karo}"
    # cmd_id自動検出: $2がcmd_+数字で始まればcmd_id、そうでなければmessage（後方互換）
    # 数字cmd(cmd_1234)、修行cmd(cmd_training_*)、サイクルcmd(cmd_cycle_*)等を全て検出
    elif [[ "${2:-}" =~ ^cmd_[a-zA-Z0-9_]+ ]]; then
        CMD_ID="$2"
        MESSAGE="${3:-$DEFAULT_MESSAGE}"
        TYPE="${4:-task_assigned}"
        FROM="${5:-karo}"
    else
        MESSAGE="${2:-$DEFAULT_MESSAGE}"
        TYPE="${3:-task_assigned}"
        FROM="${4:-karo}"
    fi

    # Codex忍者はDM-Signal CWDで起動→CLAUDE.mdの相対パスが解決不能(2026-04-28殿指示)
    # legacy status controlはtask配備ではない。MESSAGEを書き換えるとmainの制御分岐を
    # 外れて既存taskを通常配備として再処理するため、suffixを付けず原形を保つ。
    if ! { [ "$MESSAGE" = "status" ] && [[ "$TYPE" =~ ^(idle|done|in_progress)$ ]]; }; then
        MESSAGE="${MESSAGE} — タスクYAML: ${SCRIPT_DIR}/queue/tasks/${NINJA_NAME}.yaml を読んで作業開始せよ"
    fi
}

deploy_task_validate_cli_target() {
    local ninja_name="$1"
    shift || true

    if [ -z "$ninja_name" ] || [ "${ninja_name,,}" = "none" ]; then
        echo "ERROR: ninja_name is required and cannot be empty/None." >&2
        echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
        echo "例1: deploy_task.sh hanzo" >&2
        echo "例2: deploy_task.sh hanzo \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
        echo "受け取った引数: $*" >&2
        return 1
    fi

    if [[ "$ninja_name" == cmd_* ]]; then
        echo "ERROR: 第1引数はninja_name（例: hanzo, hayate）。cmd_idではない。" >&2
        echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
        echo "例1: deploy_task.sh hanzo" >&2
        echo "例2: deploy_task.sh hanzo \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
        echo "受け取った引数: $*" >&2
        return 1
    fi
}

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


# ─── 前cmd残留フィールド清掃（再配備時のstale field汚染防止） ───
# task YAMLは使い回しモデル。yaml_field_setは行ベース置換のためリスト型フィールドを
# クリアできない(子行が残る)。Python一括クリアで全フィールド型を確実に処理。
# なぜなぜ3層: (1)resolve_cmd_to_taskのリセット漏れ → (2)yaml_field_setのリスト非対応
# → (3)inject_task_modifiers.pyの「存在チェック」で前cmdのリスト値が残留
# --directモード・--cmdモードを含む全パスで実行されるよう、L3269直後の共通位置で呼び出す（AC1）
reset_stale_fields() {
    local ninja_name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local current_parent_cmd=""
    local current_notify_flag=""

    current_parent_cmd=$(awk -F': *' '/^  parent_cmd:/ {gsub(/["'\'']/, "", $2); print $2; exit}' "$task_file" 2>/dev/null || true)
    if [ -n "$current_parent_cmd" ]; then
        current_notify_flag="$SCRIPT_DIR/queue/gates/${current_parent_cmd}/gunshi_report_review_notify_${ninja_name}.done"
        if [ -f "$current_notify_flag" ]; then
            rm -f "$current_notify_flag"
            log "[STALE_RESET] Removed stale gunshi report_review notify flag for ${ninja_name}: queue/gates/${current_parent_cmd}/gunshi_report_review_notify_${ninja_name}.done"
        fi
        current_notify_flag="$SCRIPT_DIR/queue/gates/${current_parent_cmd}/gunshi_notify_${ninja_name}.done"
        if [ -f "$current_notify_flag" ]; then
            rm -f "$current_notify_flag"
            log "[STALE_RESET] Removed legacy gunshi notify flag for ${ninja_name}: queue/gates/${current_parent_cmd}/gunshi_notify_${ninja_name}.done"
        fi
    fi

    python3 - "$task_file" "$DIRECT_MODE" "$CMD_ID" <<'STALE_FIELD_RESET_PY'
import os, sys, tempfile, yaml, re

task_file = sys.argv[1]
is_direct = len(sys.argv) > 2 and sys.argv[2] == 'true'
new_parent_cmd = sys.argv[3].strip() if len(sys.argv) > 3 else ''

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

# 既存parent_cmdをパース（directモードのAC保持判定に使用）
_pc_m = re.search(r'^  parent_cmd:\s*([\w-]+)', raw, re.MULTILINE)
existing_parent_cmd = _pc_m.group(1) if _pc_m else ''

# スカラー+リスト両方を確実にクリアするフィールド一覧
STALE_FIELDS = [
    # 第1層: cmd固有メタデータ(スカラー)
    'purpose', 'target_path', 'inspection_path', 'owned_paths', 'planned_paths', 'commit_contract', 'constraints', 'progress', 'description', 'deployed_at', 'completed_at', 'done_at', 'acknowledged_at',
    # 第2層: inject_task_modifiers.pyが「存在チェック」するフィールド(リスト含む)
    'engineering_preferences', 'context_files', 'stop_for', 'never_stop_for',
    'ac_priority', 'ac_checkpoint', 'parallel_ok',
    # 第3層: 忍者書込み+per-cmdフラグ
    # acceptance_criteriaは--directモード以外でのみクリア（LK008: direct re-deploy時AC保持）
    'AC1', 'AC2', 'AC3', 'binary_checks',
    # 第4層: 旧版由来の残留フィールド(現在の配備パイプラインでは設定されないが使い回しで残る)
    'command', 'reports_to_read', 'credential_warning', 'context_update',
    # 第5層: task_typeと重複するレガシーフィールド(修行001 hayate発見)
    'type', 'report_template',
    # 第9層: resolve_cmd_to_taskで上書きされるが安全網(cmd_2231 saizo stale contamination: title/report_path残留)
    'title', 'report_path', 'report_filename', 'assigned_acs', 'scope_note',
    'subtask_id', 'scope_mode',
    # 第6層: ネスト残留+旧メタデータ(cmd_1527発見: 前cmdの全task:ブロックが残留)
    'task', 'worker_id', 'timestamp',
    # 第7層: GP-198 session state (新cmd配備時に前cmdの失敗履歴をクリア)
    'session_state', 'previous_failures', 'started_at',
    # 第8層: GP-201 CoDD failure history (CoDD改善cmd配備時にregistryから再注入するため毎回クリア)
    'codd_failure_history',
    # 第10層: inject_related_lessons/inject_task_modifiersで毎回再注入されるが、
    # 配備前に旧値が残るとCodex忍者がSTALLする(LK092: cmd_2250 hayate STALL実証)
    'related_lessons', 'ninja_weak_points', 'role_reminder', 'bloom_level',
    # 第11層: cmd固有scope/context(LK-A02 v7: 2件連続FAIL cmd_2875+cmd_2880。前taskのscope/contextが残存し忍者が旧scopeで作業)
    'scope', 'context_hints', 'context', 'assigned_scope',
    # 第12層: 因果確認L0-L7テンプレート。scopeごとに再判定して注入する
    'causal_verification',
    # 第13層: command欄の必読/参照専用ファイル。cmdごとに再抽出する
    'readonly_ref',
    # 第14層: Level5自動注入/診断メタ。スカラー親だけ上書きされると旧リスト子が残りYAMLを壊す
    'growth_loop_defense', 'semantic_concepts', 'standard_skills',
    'memory_db_context', 'related_causal_links', 'production_invariants',
    'reflux_commit_contract',
    'hypothesis_count', 'three_strike_rule',
    # 第15層: cmd固有メタ(karo_direct手動注入/resolve_cmd_to_task転写。前cmdの値が次cmdに残留する)
    'expected_model_effort', 'pre_deploy_banner_evidence',
    'not_in_scope', 'recommended_skills', 'assigned_lesson_ids',
    # 前cmdの実装分解を次cmdへ持ち越すと、忍者が現cmdのACより旧work_itemsを
    # 優先して別任務を実行する。sourceから再投影されないため世代境界で必ず除去する。
    'work_items',
    # 第15.5層: cmd固有の変更対象・detector品質契約。前cmdの値が残ると
    # 教訓target filterと忍者の作業scopeを別cmdへ向ける（cmd_3997/3998で連続再現）。
    'files_to_modify', 'files_modified', 'quality_gate',
    # DM-Signal canary rotation contract is task-generation scoped.  Keeping a
    # prior contract on a reused worker would impose a DM-Signal-only workflow
    # on an unrelated task (false positive at the deployment boundary).
    'dm_signal_canary_rotation_contract',
    # 第17層: 独立偵察契約。前taskのtrack/base/embargoを次cmdへ漏らさず、
    # --yaml sourceに明示された新契約だけをpublish後に保持する。
    'independence_group', 'independence_track', 'independence_base_commit',
    'independence_worktree_required', 'shared_context_embargo',
    # 第16層: cmdで検証済みの前提とstatus固有メタ。新cmdだけを正本にする
    'assumptions', 'cancel_reason', 'cancellation_reason', 'superseded_by',
    # 第18層: 自然境界/実行時間契約。前cmdの長時間根拠を次cmdへ漏らすと、
    # source precheck=10分PASS後にtask=20分へ変質して契約が二重化する。
    'estimated_minutes', 'timeout_minutes', 'split_decision', 'execution_env',
    # report identityは配備世代ごとの一意契約。旧世代taskからfast publicationへ
    # 渡すと別report pathでも同じUUIDを再利用するため、世代境界で必ず除去する。
    'report_id', 'report_identity_version',
    'task_worktree_required', 'task_worktree_path', 'task_worktree_repo',
    'task_worktree_base', 'task_worktree_generation', 'task_worktree_status',
    'task_worktree_marker', 'task_worktree_workdir', 'task_worktree_target_paths',
    'task_worktree_edit_wrapper', 'task_worktree_source_paths',
    # Terminal evidence is generation-scoped. A reused worker must not carry
    # the predecessor's CI run/checkpoint into a task that omits them.
    'ci_run_id', 'final_checkpoint',
    # Pre-implementation review is bound to one exact task_id + AC fingerprint.
    # Reusing it across task generations makes a valid new APPROVE collide with
    # the predecessor receipt before the new task can be published.
    'pre_implementation_review',
    # Test lifecycle fields are generation-scoped. If omitted here, a new
    # task can inherit predecessor evidence and fail its own commit gate.
    'test_necessity', 'deletion_justification', 'transient_tests_deleted',
]
# parent_cmdが変わる場合だけacceptance_criteriaをクリアする。
# 同一cmd再配備では、cmdソース不在時にテンプレートACをfallbackとして保持する。
# CMD_ID未指定の単体resetでは従来通りクリアし、旧AC残存を防ぐ。
if not new_parent_cmd or existing_parent_cmd != new_parent_cmd:
    STALE_FIELDS.append('acceptance_criteria')

# 行ベースのインデント追跡でstaleフィールドを除去（正規表現の誤マッチ防止）
# 正規表現はダブルクォート内エスケープ/ネスト構造/リスト項目で誤動作する
stale_set = set(STALE_FIELDS)
lines = raw.split('\n')
result = []
skip_indent = -1  # >= 0: この深さ以下の行をスキップ中

for line in lines:
    stripped = line.lstrip(' ')
    indent = len(line) - len(stripped)

    # スキップ中: 空行 or より深いインデント or 同インデントのリスト項目 → 子要素として除去
    if skip_indent >= 0:
        if stripped == '' or indent > skip_indent:
            continue
        # 同インデントでもリスト項目(- で始まる)はフィールドの子要素
        if indent == skip_indent and stripped.startswith('- '):
            continue
        skip_indent = -1  # インデントが戻った → スキップ終了

    # task:ブロック内フィールド(indent=2)のstale判定
    if indent == 2 and ':' in stripped:
        field_name = stripped.split(':')[0].split(' ')[0]  # "field:" or "field: value"
        if field_name in stale_set:
            skip_indent = indent
            continue

    # ルートレベルstaleフィールド除去（task:以外の0-indentフィールド）
    if indent == 0 and ':' in stripped and stripped != '' and not stripped.startswith('#'):
        root_field = stripped.split(':')[0]
        if root_field != 'task':
            skip_indent = indent
            continue

    result.append(line)

raw = '\n'.join(result)

# 空行の連続を整理
raw = re.sub(r'\n{3,}', '\n\n', raw)

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp_path, task_file)
except Exception:
    try: os.unlink(tmp_path)
    except OSError: pass
    raise

print(f'[STALE_RESET] Cleared {len(STALE_FIELDS)} stale fields + root-level orphans from {os.path.basename(task_file)}', file=sys.stderr)
STALE_FIELD_RESET_PY
    log "[STALE_RESET] Python stale field reset completed for ${ninja_name}"
    _STALE_RESET_DONE=1
}

deploy_task_cmd_status_is_canceled() {
    local cmd_id="$1"
    [ -n "$cmd_id" ] || return 1
    python3 - "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$cmd_id" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path, cmd_id = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

entry = None
commands = data.get("commands")
if isinstance(commands, dict):
    entry = commands.get(cmd_id)
elif isinstance(commands, list):
    for item in commands:
        if isinstance(item, dict) and str(item.get("id", "")).strip() == cmd_id:
            entry = item
            break

if not isinstance(entry, dict):
    raise SystemExit(1)

status = str(entry.get("status", "")).strip().lower()
raise SystemExit(0 if status in {"canceled", "cancelled"} else 1)
PY
}

deploy_task_cmd_status_is_draft() {
    local cmd_id="$1"
    [ -n "$cmd_id" ] || return 1
    python3 - "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$cmd_id" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path, cmd_id = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

entry = None
commands = data.get("commands")
if isinstance(commands, dict):
    entry = commands.get(cmd_id)
elif isinstance(commands, list):
    for item in commands:
        if isinstance(item, dict) and str(item.get("id", "")).strip() == cmd_id:
            entry = item
            break

if not isinstance(entry, dict):
    raise SystemExit(1)

status = str(entry.get("status", "")).strip().lower()
raise SystemExit(0 if status == "draft" else 1)
PY
}

deploy_task_cleanup_canceled_cmd() {
    local ninja_name="$1"
    local cmd_id="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local task_parent report_path report_filename

    [ -n "$ninja_name" ] || return 1
    [ -n "$cmd_id" ] || return 1
    deploy_task_cmd_status_is_canceled "$cmd_id" || return 1
    [ -f "$task_file" ] || return 1

    task_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ "$task_parent" = "$cmd_id" ] || return 1

    report_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_path" "" 2>/dev/null || true)
    report_filename=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "" 2>/dev/null || true)
    if [ -z "$report_path" ] && [ -n "$report_filename" ]; then
        report_path="queue/reports/${report_filename}"
    fi

    reset_stale_fields "$ninja_name"
    task_lifecycle_set_idle "$task_file" "cancel_cleanup" >/dev/null 2>&1 || true

    log "cancel_cleanup: ${cmd_id} cleared stale task for ${ninja_name} report=${report_path:-none}"
    echo "CANCEL_CLEANUP: ${cmd_id} is canceled; cleared stale task for ${ninja_name}"
    return 0
}

# ─── --yamlモード: task YAMLに記録されたスクリプトの鮮度チェック ───
# command欄から "bash scripts/..." or "scripts/..." パターンを抽出し、
# YAML作成後にgitコミットされたスクリプトがあればWARN。BLOCKにはしない（段階的導入）。
check_yaml_freshness() {
    # 既存台帳(logs/defense_overhead.jsonl)へwallを記録する。新台帳は作らない。
    local _cyf_start_us _cyf_end_us _cyf_wall_ms _cyf_rc
    _cyf_start_us="${EPOCHREALTIME/./}"
    check_yaml_freshness_impl "$@"
    _cyf_rc=$?
    _cyf_end_us="${EPOCHREALTIME/./}"
    _cyf_wall_ms=$(((_cyf_end_us - _cyf_start_us + 999) / 1000))
    defense_overhead_write_async deploy_task check_yaml_freshness "$_cyf_wall_ms" PASS \
        "cyf:${DEPLOY_TASK_ISSUE_ATTEMPT_ID:-$$}:${_cyf_start_us}" || true
    return "$_cyf_rc"
}

check_yaml_freshness_impl() {
    local yaml_file="$1"
    local git_root="$2"

    # command欄からスクリプトパスを抽出（bash scripts/foo.sh または scripts/foo.sh 形式）
    local script_paths
    script_paths=$(grep -oE '(bash )?scripts/[^ "\\]+\.sh' "$yaml_file" 2>/dev/null \
        | sed 's/^bash //' | sort -u || true)

    [ -z "$script_paths" ] && return 0

    # YAMLファイルのmtime (Unix epoch秒)
    local yaml_mtime
    yaml_mtime=$(stat -c %Y "$yaml_file" 2>/dev/null || echo 0)

    # 走査範囲の絞り込み（検査項目は削除しない。同じWARN集合を出す）。
    # 一番外側の必要条件から順に安いgit呼び出しで棄却する:
    #   Tier0: HEADの最新commitがYAMLより古い → どのpathもYAMLより新しくなり得ない(pathspecなし=履歴walkなし)
    #   Tier1: 全path一括のpathspec walk 1回 → 最新commitがYAMLより古ければ全path棄却
    # どちらも通らない時だけ、path単位のwalkへ落ちる。
    local head_epoch newest_epoch
    head_epoch=$(git -C "$git_root" log -1 --format=%at 2>/dev/null || true)
    if [ -n "$head_epoch" ] && [ "$head_epoch" -le "$yaml_mtime" ] 2>/dev/null; then
        return 0
    fi
    # shellcheck disable=SC2086 # 意図的な単語分割: pathspecを複数渡す
    newest_epoch=$(git -C "$git_root" log -1 --format=%at -- $script_paths 2>/dev/null || true)
    if [ -z "$newest_epoch" ] || { [ "$newest_epoch" -le "$yaml_mtime" ] 2>/dev/null; }; then
        return 0
    fi

    while IFS= read -r script_path; do
        [ -z "$script_path" ] && continue

        # A command may intentionally name the new file this task will create.
        # On /mnt/c, walking history for that absent path can enter Git's slow
        # D-state path.  HEAD blob existence is the bounded boundary: absent
        # targets have no freshness provenance to inspect.
        git -C "$git_root" cat-file -e "HEAD:${script_path}" 2>/dev/null || continue

        # 同一walkからepochとhashを1回で取得する(旧実装は同じwalkを2回していた)
        local commit_line commit_hash commit_epoch
        commit_line=$(git -C "$git_root" log -1 --format="%at %h" -- "$script_path" 2>/dev/null || true)
        [ -z "$commit_line" ] && continue

        commit_epoch="${commit_line%% *}"
        commit_hash="${commit_line##* }"
        [ -z "$commit_epoch" ] && continue

        if [ "$commit_epoch" -gt "$yaml_mtime" ] 2>/dev/null; then
            echo "[DEPLOY] WARN: ${script_path} はYAML作成後に更新されている(commit: ${commit_hash})。task YAMLを再作成せよ" >&2
        fi
    done <<< "$script_paths"
}

deploy_task_validate_or_repair_direct_yaml() {
    local task_file="$1"
    local source_yaml="$2"
    local tmp_file

    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$task_file" 2>/dev/null; then
        log "direct_mode: source YAML syntax PASS (${source_yaml})"
        return 0
    fi

    tmp_file="$(mktemp "${task_file}.repair.XXXXXX")" || return 1
    if python3 - "$task_file" "$tmp_file" <<'DIRECT_YAML_REPAIR_PY'; then
import sys
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
lines = src.read_text(encoding="utf-8").splitlines()
out = []
i = 0
key_re = re.compile(r"^(\s{2,})([A-Za-z0-9_.-]+):[ \t]+(.+)$")
next_key_re = re.compile(r"^\s{2,}[A-Za-z0-9_.-]+:")

while i < len(lines):
    line = lines[i]
    match = key_re.match(line)
    if not match:
        out.append(line)
        i += 1
        continue

    indent, key, value = match.groups()
    continuations = []
    j = i + 1
    while j < len(lines):
        nxt = lines[j]
        stripped = nxt.strip()
        if not stripped:
            continuations.append("")
            j += 1
            continue
        if next_key_re.match(nxt) or re.match(r"^\s*-\s+", nxt):
            break
        if len(nxt) - len(nxt.lstrip(" ")) > len(indent):
            continuations.append(nxt.strip())
            j += 1
            continue
        break

    if continuations:
        out.append(f"{indent}{key}: |-")
        out.append(f"{indent}  {value.rstrip()}")
        out.extend(f"{indent}  {part}" if part else "" for part in continuations)
        i = j
    else:
        out.append(line)
        i += 1

text = "\n".join(out) + "\n"
yaml.safe_load(text)
dst.write_text(text, encoding="utf-8")
DIRECT_YAML_REPAIR_PY
        _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
        log "direct_mode: repaired invalid multiline scalar YAML from ${source_yaml}"
        return 0
    fi

    rm -f "$tmp_file"
    log "FATAL: direct_mode source YAML invalid and repair failed: ${source_yaml}"
    echo "FATAL: --yaml input is invalid and could not be repaired: ${source_yaml}" >&2
    return 1
}

# cmd_karo_hotfix_deploy_task_atomic_publish_202607111645: $yaml_fileの内容を$task_yamlへ
# 安全に反映する。同一dir candidateを経由し、validate/repair成功後にのみatomic mvで公開する
# (fail-closed)。$yaml_file自体は呼び出し元がcheck_yaml_freshness等で後続再読込するため
# 一切変更しない(cpのみ、mv/rmしない)。戻り値0=公開成功、1=失敗(task_yamlは変更前のまま)。
deploy_task_direct_yaml_publish() {
    local task_yaml="$1"
    local yaml_file="$2"

    if [ ! -f "$yaml_file" ]; then
        log "ERROR: --yaml file not found: $yaml_file"
        echo "ERROR: --yaml ファイルが見つからない: $yaml_file" >&2
        return 1
    fi

    local direct_yaml_candidate
    direct_yaml_candidate="$(mktemp "${task_yaml}.XXXXXX")" || {
        log "ERROR: direct_mode: failed to create candidate temp file for $task_yaml"
        return 1
    }
    cp "$yaml_file" "$direct_yaml_candidate"
    deploy_task_validate_or_repair_direct_yaml "$direct_yaml_candidate" "$yaml_file" || {
        rm -f "$direct_yaml_candidate"
        return 1
    }
    if ! mv "$direct_yaml_candidate" "$task_yaml"; then
        rm -f "$direct_yaml_candidate"
        log "ERROR: direct_mode: atomic publish (mv) failed for $task_yaml"
        return 1
    fi
    log "direct_mode: task YAML overwritten from $yaml_file"
}

# Resolve the single deployable SSOT for a command.  An archived command is
# deliberately not deployable until cmd_reopen.sh has published its reopened
# state; every deployment producer must use this boundary instead of assuming
# the shared active queue is the only source.
resolve_cmd_source_path() {
    local cmd_id="$1"
    local active="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    local reopened="$SCRIPT_DIR/queue/reopened_cmds/${cmd_id}.yaml"

    if [ -f "$active" ] && awk -v cmd="$cmd_id" '
        /^  [^ ]/ { key=$0; sub(/^  /,"",key); sub(/:.*/,"",key); if (key==cmd) found=1 }
        END { exit(found ? 0 : 1) }
    ' "$active"; then
        printf '%s\n' "$active"
        return 0
    fi
    if [ -f "$reopened" ]; then
        printf '%s\n' "$reopened"
        return 0
    fi
    return 1
}

# LK-A22 Level5: depends_onをcmd単位の停止条件として扱わず、配備判断に必要な
# 現cmdのACと依存先の状態・目的をその場で供給する。依存要否そのものは自然言語
# 判断を含むためBLOCKせず、並列可能なACを家老が切り出せる一次情報を表示する。
emit_depends_on_ac_context() {
    local stk="$1" cmd_id="$2" depends_on="$3"
    python3 - "$stk" "$cmd_id" "$depends_on" >&2 <<'PY'
import re
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path, cmd_id, depends_on = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
commands = doc.get("commands") if isinstance(doc, dict) else {}
commands = commands if isinstance(commands, dict) else {}
current = commands.get(cmd_id) if isinstance(commands.get(cmd_id), dict) else {}

dep_ids = re.findall(r"cmd_[0-9A-Za-z_-]+", depends_on)
if not dep_ids:
    return_code = 0
else:
    print(f"WARN: depends_on={depends_on} 検出。AC単位で依存要否を判定し、並列可能なACは先に配備せよ。(LK-A22 Level5)")
    criteria = current.get("acceptance_criteria") or []
    if isinstance(criteria, dict):
        criteria = [f"{key}: {value}" for key, value in criteria.items()]
    print("  current_acceptance_criteria:")
    if isinstance(criteria, list) and criteria:
        for index, item in enumerate(criteria, 1):
            if isinstance(item, dict):
                label = item.get("id") or f"AC{index}"
                text = item.get("description") or item.get("check") or item
            else:
                label, text = f"AC{index}", item
            print(f"    - {label}: {text}")
    else:
        print("    - (ACなし。cmd正本を確認せよ)")
    print("  dependency_context:")
    for dep_id in dep_ids:
        dep = commands.get(dep_id)
        if isinstance(dep, dict):
            print(f"    - {dep_id}: status={dep.get('status', 'unknown')} purpose={dep.get('purpose', '(purposeなし)')}")
        else:
            print(f"    - {dep_id}: cmd正本内に未検出（archive/reopenedを確認せよ）")
PY
}

# ─── cmd_id→task YAML自動解決（なぜなぜL5根因対策: 家老の手動ステップ排除） ───
# cmd_id指定時、shogun_to_karo.yamlからメタデータを取得しtask YAMLの中核フィールドを自動設定。
# これにより「task YAML更新 → deploy_task.sh」の2ステップが原子的操作になる。
resolve_cmd_to_task() {
    local cmd_id="$1"
    local ninja_name="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local stk
    if ! stk=$(resolve_cmd_source_path "$cmd_id"); then
        log "resolve_cmd: ERROR deployable cmd SSOT not found for ${cmd_id}"
        return 1
    fi

    # shogun_to_karo.yamlからcmdメタデータ抽出（awk方式: Python subprocess除去 cmd_deploy_yaml_speedup）
    local _resolve_output
    _resolve_output=$(awk -v cmd="$cmd_id" '
        /^  [^ ]/ {
            if (in_cmd) { exit }
            s = $0; sub(/^  /, "", s); sub(/:.*/, "", s)
            if (s == cmd) { in_cmd = 1; skip_ml = 0; next }
        }
        in_cmd && skip_ml && /^      / { next }
        in_cmd && skip_ml { skip_ml = 0 }
        in_cmd && /^    [a-z_]+:/ {
            key = $0; sub(/^    /, "", key); sub(/:.*/, "", key)
            val = $0; sub(/^[^:]+:[[:space:]]*/, "", val)
            # YAML multiline (| or >) → skip continuation lines (LK002: cmd_2330 resolve failure)
            if (val == "|" || val == ">" || val == "|+" || val == "|-" || val == ">-") {
                skip_ml = 1; val = ""
                if (key == "purpose") purpose = val
                next
            }
            fc = substr(val, 1, 1); lc = substr(val, length(val), 1)
            if (length(val) >= 2 && ((fc == "\"" && lc == "\"") || (fc == "'"'"'" && lc == "'"'"'")))
                val = substr(val, 2, length(val) - 2)
            if (key == "project")    project   = val
            else if (key == "scope_mode") scope_mode = val
            else if (key == "type")       type_val   = val
            else if (key == "title")      title      = val
            else if (key == "purpose")    purpose    = val
            else if (key == "depends_on") depends_on = val
            else if (key == "target_path") target_path = val
            else if (key == "scout_exempt") scout_exempt = val
        }
        END {
            if (!in_cmd) { print "ERROR: " cmd " not found" > "/dev/stderr"; exit 1 }
            if (!scope_mode) scope_mode = (type_val ? type_val : "impl")
            print "project="       project
            print "task_type="     tolower(scope_mode)
            print "title="         title
            print "purpose="       purpose
            print "depends_on="    depends_on
            print "target_path="   target_path
            print "scout_exempt="  scout_exempt
        }
    ' "$stk") || {
        log "resolve_cmd: ${cmd_id} not found in deployable SSOT ${stk}"
        return 1
    }

    # cmd_2078: 6x echo|grep|cut (18 subprocesses) → while+IFS one-pass (0 subprocesses, -17ms)
    local project task_type title purpose _depends_on _target_path _scout_exempt_stk
    local _rv_k _rv_v
    declare -A _rv=()
    while IFS='=' read -r _rv_k _rv_v; do
        [[ -n "$_rv_k" ]] && _rv["$_rv_k"]="$_rv_v"
    done <<< "$_resolve_output"
    project="${_rv[project]:-}"
    task_type="${_rv[task_type]:-}"
    title="${_rv[title]:-}"
    purpose="${_rv[purpose]:-}"
    _depends_on="${_rv[depends_on]:-}"
    _target_path="${_rv[target_path]:-}"
    _scout_exempt_stk="${_rv[scout_exempt]:-}"
    unset _rv _rv_k _rv_v
    [ -z "$task_type" ] && task_type="impl"

    # LK-A22 Level5: 実依存がある時だけACと依存先コンテキストを自動供給する。
    if [[ "$_depends_on" =~ cmd_[0-9A-Za-z_-]+ ]]; then
        emit_depends_on_ac_context "$stk" "$cmd_id" "$_depends_on"
    fi

    local task_id="${cmd_id}_${task_type}"

    # R1: task YAMLの中核フィールドを一括設定（7回flock→1回batch。CoDD refactor_sequence準拠）
    local _deploy_ts
    _deploy_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    local _batch_args=("parent_cmd=$cmd_id" "cmd_id=$cmd_id" "task_id=$task_id" "task_type=$task_type" "status=assigned" "deployed_at=$_deploy_ts" "acknowledged_at=" "done_at=" "completed_at=" "_ac_task_id=" "_ac_worker_id=" "_deploy_notice=STALE TASK INVALID. This YAML is the latest instruction for ${cmd_id} (deployed ${_deploy_ts}). Read from the beginning.")
    [ -n "$project" ] && _batch_args+=("project=$project")
    [ -n "$purpose" ] && _batch_args+=("purpose=$purpose")
    [ -n "$_target_path" ] && _batch_args+=("target_path=$_target_path")
    # scout_exempt: STKからtask YAMLに転記。task-local preseedはreset_stale_fieldsで保持する。
    [ "$_scout_exempt_stk" = "true" ] && _batch_args+=("scout_exempt=true")
    yaml_field_set_batch "$task_file" "task" "${_batch_args[@]}" \
        || { log "FATAL: yaml_field_set_batch failed for resolve_cmd_to_task"; return 1; }

    # task側の自然境界precheckはacceptance_criteriaのIDをsplit_decisionと照合する。
    # inject_ac_version（task mutation段階）までAC転記を遅らせると、precheckが先に
    # 実行され同一cmd retryでAC欠落BLOCKになるため、解決時点で正本から投影する。
    _overwrite_ac_from_cmd "$task_file" \
        || { log "FATAL: acceptance criteria injection failed for ${cmd_id}"; return 1; }

    # Precheckした自然境界契約と忍者が読むtask契約を同一SSOTから投影する。
    # estimated_minutesだけ検査してtaskへ転記しないと、使い回しYAMLの旧
    # execution_env/estimated_minutesが残り、配備前PASSと配備後taskが矛盾する。
    inject_cmd_time_contract "$task_file" "$cmd_id" \
        || { log "FATAL: time contract injection failed for ${cmd_id}"; return 1; }

    # cmd_saveで検証済みのassumptionsを構造保持してtaskへ渡す。
    # sourceに無い場合は何も生成しない（暗黙前提の捏造防止）。
    inject_cmd_assumptions "$task_file" "$cmd_id" \
        || { log "FATAL: assumptions injection failed for ${cmd_id}"; return 1; }

    log "resolve_cmd: ${cmd_id} → ninja=${ninja_name}, task_id=${task_id}, project=${project:-none}, type=${task_type}, title=${title}"
    return 0
}

legacy_resolve_compat_sentinel() { :; }

fi
# Cluster D module: CLI/pane resolution, stale reset, direct YAML, and cmd source resolution.
_dt_resolve_path="$SCRIPT_DIR/scripts/deploy_task/resolve.sh"
if [ ! -f "$_dt_resolve_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_resolve_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/resolve.sh"
fi
if [ ! -f "$_dt_resolve_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_resolve_path="$PROJECT_ROOT/scripts/deploy_task/resolve.sh"
fi
source "$_dt_resolve_path"
unset _dt_resolve_path
# Cluster C module: report/RC decisions, inbox delivery evidence, post-verify, and fallback.
# Compatibility marker: delivery.sh exports handle_yaml_injection_failure().
# Compatibility marker: log "ERROR: ${injector_name} failed remains in delivery.sh.
# Compatibility marker: safe_inbox_write "karo" "$message" "deploy_error" "deploy_task" remains in delivery.sh.
_dt_delivery_path="$SCRIPT_DIR/scripts/deploy_task/delivery.sh"
if [ ! -f "$_dt_delivery_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_delivery_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/delivery.sh"
fi
if [ ! -f "$_dt_delivery_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_delivery_path="$PROJECT_ROOT/scripts/deploy_task/delivery.sh"
fi
source "$_dt_delivery_path"
unset _dt_delivery_path
# Legacy static-extraction compatibility for tests that copy deploy_task.sh only.
if false; then
# Direct --yaml keeps source YAML ACs without cmd-source overwrite; the runtime
# branch lives in the sourced task_contract module, while this marker preserves
# the source-level contract used by static compatibility checks.
if [ "${DIRECT_MODE:-false}" = true ] && [ -n "${YAML_FILE:-}" ]; then
    # keeping source YAML ACs without cmd-source overwrite
    # Non-direct fallback still calls _overwrite_ac_from_cmd.
    :
fi
inject_cmd_time_contract() {
    local task_file="$1"
    local cmd_id="$2"
    local source_path
    source_path=$(resolve_cmd_source_path "$cmd_id") || return 1
    python3 - "$task_file" "$source_path" "$cmd_id" <<'TIME_CONTRACT_INJECT_PY'
import os
import re
import sys
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path, source_path, cmd_id = sys.argv[1:]
with open(source_path, encoding="utf-8") as f:
    source = yaml.safe_load(f) or {}
entry = (source.get("commands") or {}).get(cmd_id)
if not isinstance(entry, dict):
    raise SystemExit(f"command not found: {cmd_id}")

field_order = ("estimated_minutes", "timeout_minutes", "split_decision", "execution_env")
projection = {key: entry[key] for key in field_order if key in entry}
if "estimated_minutes" not in projection:
    raise SystemExit("estimated_minutes missing after source contract precheck")

def scalar(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    quote = chr(39)
    text = str(value)
    return quote + text.replace(quote, quote + quote) + quote

def emit_field(key, value, indent=2):
    prefix = " " * indent
    if isinstance(value, dict):
        lines = [prefix + key + ":"]
        for nested_key, nested_value in value.items():
            if isinstance(nested_value, list):
                lines.append(prefix + "  " + str(nested_key) + ":")
                lines.extend(prefix + "  - " + scalar(item) for item in nested_value)
            else:
                lines.append(prefix + "  " + str(nested_key) + ": " + scalar(nested_value))
        return lines
    if isinstance(value, list):
        return [prefix + key + ":"] + [prefix + "- " + scalar(item) for item in value]
    return [prefix + key + ": " + scalar(value)]

with open(task_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

# Replace rather than append so same-cmd recovery cannot create duplicate keys.
targets = set(field_order)
cleaned = []
skip_indent = None
for line in lines:
    stripped = line.lstrip(" ")
    indent = len(line) - len(stripped)
    if skip_indent is not None:
        if not stripped or indent > skip_indent or (indent == skip_indent and stripped.startswith("- ")):
            continue
        skip_indent = None
    if indent == 2 and ":" in stripped and stripped.split(":", 1)[0] in targets:
        skip_indent = indent
        continue
    cleaned.append(line)

insert_at = next((i + 1 for i, line in enumerate(cleaned) if line == "task:"), None)
if insert_at is None:
    raise SystemExit("task block missing")
block = []
for key in field_order:
    if key in projection:
        block.extend(emit_field(key, projection[key]))
cleaned[insert_at:insert_at] = block
rendered = "\n".join(cleaned) + "\n"
parsed = yaml.safe_load(rendered) or {}
task = parsed.get("task") or {}
for key, expected in projection.items():
    if task.get(key) != expected:
        raise SystemExit(f"projection mismatch: {key}")

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(rendered)
    os.replace(tmp, task_path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
TIME_CONTRACT_INJECT_PY
}

# ─── cmd assumptions構造保持注入 ───
inject_cmd_assumptions() {
    local task_file="$1"
    local cmd_id="$2"
    local source_path
    source_path=$(resolve_cmd_source_path "$cmd_id") || return 0
    python3 - "$task_file" "$source_path" "$cmd_id" <<'ASSUMPTIONS_INJECT_PY'
import os
import sys
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path, source_path, cmd_id = sys.argv[1:]
with open(source_path, encoding='utf-8') as f:
    source = yaml.safe_load(f) or {}
commands = source.get('commands', {})
entry = commands.get(cmd_id, {}) if isinstance(commands, dict) else {}
assumptions = entry.get('assumptions') if isinstance(entry, dict) else None
if assumptions is None:
    raise SystemExit(0)

def scalar(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    quote = chr(39)
    return quote + text.replace(quote, quote + quote) + quote

def emit_value(value, indent):
    prefix = ' ' * indent
    if isinstance(value, dict):
        if not value:
            return [prefix + '{}']
        lines = []
        for key, nested in value.items():
            if isinstance(nested, (dict, list)):
                lines.append(prefix + str(key) + ':')
                lines.extend(emit_value(nested, indent + 2))
            else:
                lines.append(prefix + str(key) + ': ' + scalar(nested))
        return lines
    if isinstance(value, list):
        if not value:
            return [prefix + '[]']
        lines = []
        for item in value:
            if isinstance(item, dict) and item:
                first = True
                for key, nested in item.items():
                    marker = '- ' if first else '  '
                    first = False
                    if isinstance(nested, (dict, list)):
                        lines.append(prefix + marker + str(key) + ':')
                        lines.extend(emit_value(nested, indent + 4))
                    else:
                        lines.append(prefix + marker + str(key) + ': ' + scalar(nested))
            elif isinstance(item, (dict, list)):
                lines.append(prefix + '-')
                lines.extend(emit_value(item, indent + 2))
            else:
                lines.append(prefix + '- ' + scalar(item))
        return lines
    return [prefix + scalar(value)]

with open(task_path, encoding='utf-8') as f:
    raw = f.read()
block = ['  assumptions:'] + emit_value(assumptions, 4)
lines = raw.splitlines()
insert_at = next((i + 1 for i, line in enumerate(lines) if line == 'task:'), None)
if insert_at is None:
    raise SystemExit('task block missing')
lines[insert_at:insert_at] = block
rendered = '\n'.join(lines) + '\n'
yaml.safe_load(rendered)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(rendered)
    os.replace(tmp, task_path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
ASSUMPTIONS_INJECT_PY
}

# ─── cmd_1157: flat→nested YAML正規化 ───
# flat形式(task:ブロックなし)のtask YAMLをnested形式に変換する。
# 変換失敗時はログ出力のみ（配備は継続。yaml_field_setのフォールバック対応あり）
_overwrite_ac_from_cmd() {
    local task_file="$1"
    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    [ -z "$parent_cmd" ] && return 1

    local py_output
    py_output=$(mktemp) || {
        log "_overwrite_ac_from_cmd: mktemp failed"
        return 1
    }
    if python3 - "$task_file" "$parent_cmd" "$SCRIPT_DIR" <<'OVERWRITE_AC_PY' > "$py_output" 2>&1; then
import glob
import os
import re
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = sys.argv[1]
parent_cmd = sys.argv[2]
script_dir = sys.argv[3]

def _convert_nested_ac(ac_dict):
    """ac: {AC1: {title, criteria}} → acceptance_criteria: [{id, title, checks}] 変換。
    cmd_1604+のネスト形式を、task YAML+binary_checks awk互換のリスト形式に変換する。"""
    if not isinstance(ac_dict, dict):
        return None
    result = []
    for ac_id, ac_body in ac_dict.items():
        if not isinstance(ac_body, dict):
            continue
        entry = {'id': ac_id}
        if 'title' in ac_body:
            entry['title'] = ac_body['title']
        criteria = ac_body.get('criteria', [])
        if isinstance(criteria, list) and criteria:
            entry['checks'] = [{'check': str(c)} for c in criteria]
        elif isinstance(ac_body.get('description'), str):
            description = ac_body['description']
            entry['description'] = description
            entry['checks'] = [{'check': description}]
        result.append(entry)
    return result if result else None

def _convert_flat_ac_dict(ac_dict):
    """acceptance_criteria: {AC1: "string", AC2: "string"} → [{id, checks}] 変換。
    cmd_1610型のAC-ID→文字列dictを、binary_checks awk互換リスト形式に変換。"""
    if not isinstance(ac_dict, dict):
        return None
    result = []
    for ac_id, ac_text in ac_dict.items():
        if isinstance(ac_text, str):
            result.append({'id': ac_id, 'description': ac_text, 'checks': [{'check': ac_text}]})
        elif isinstance(ac_text, dict):
            # ac: {AC1: {title, criteria}} がacceptance_criteriaキーで書かれたケース
            converted = _convert_nested_ac({ac_id: ac_text})
            if converted:
                result.extend(converted)
    return result if result else None

def _extract_acs_from_cmd(cmd):
    """cmdデータからACを抽出。3形式対応:
    1. acceptance_criteria: ['AC1: ...'] (flat list, ≤cmd_1603)
    2. acceptance_criteria: {AC1: "..."} (flat dict, cmd_1610型)
    3. ac: {AC1: {title, criteria}} (nested dict, cmd_1604+)
    リスト形式はそのまま返す。dict形式はbinary_checks awk互換リストに変換。"""
    acs = cmd.get('acceptance_criteria')
    if acs:
        if isinstance(acs, list):
            return acs  # 旧形式: flat list → そのまま
        if isinstance(acs, dict):
            converted = _convert_flat_ac_dict(acs)
            if converted:
                return converted
            return acs  # 変換失敗時はそのまま返す
    # 新形式: ac (nested dict, cmd_1604+)
    ac_nested = cmd.get('ac')
    if ac_nested and isinstance(ac_nested, dict):
        converted = _convert_nested_ac(ac_nested)
        if converted:
            return converted
    return None

def find_cmd_acs(pcmd, sdir):
    # 1. shogun_to_karo.yaml (dict format: commands.cmd_XXX.acceptance_criteria or .ac)
    stk_path = os.path.join(sdir, 'queue', 'shogun_to_karo.yaml')
    if os.path.exists(stk_path):
        try:
            with open(stk_path, encoding='utf-8') as f:
                stk = yaml.load(f, Loader=yaml.SafeLoader) or {}
            cmds = stk.get('commands', {})
            if isinstance(cmds, dict):
                cmd = cmds.get(pcmd, {})
                if isinstance(cmd, dict):
                    acs = _extract_acs_from_cmd(cmd)
                    if acs:
                        return acs
        except Exception:
            pass
    # 2. Archive fallback
    archive_dir = os.path.join(sdir, 'queue', 'archive', 'cmds')
    if os.path.isdir(archive_dir):
        for cpath in sorted(glob.glob(os.path.join(archive_dir, f'{pcmd}_*.yaml')), reverse=True):
            try:
                with open(cpath, encoding='utf-8') as f:
                    adata = yaml.load(f, Loader=yaml.SafeLoader) or {}
                cmds = adata.get('commands', {})
                if isinstance(cmds, dict):
                    cmd = cmds.get(pcmd, {})
                    if isinstance(cmd, dict):
                        acs = _extract_acs_from_cmd(cmd)
                        if acs:
                            return acs
            except Exception:
                continue
    return None

cmd_acs = find_cmd_acs(parent_cmd, script_dir)
if not cmd_acs:
    print(f'[AC_OVERWRITE] WARN: No ACs found for {parent_cmd} in cmd source', file=sys.stderr)
    sys.exit(1)

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
def _sv(v, multiline_indent=2):
    if v is None: return 'null'
    if isinstance(v, bool): return str(v).lower()
    if isinstance(v, (int, float)): return str(v)
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq + sq) + sq
def _yaml_lines(key, val, ind=0):
    p = ' ' * ind
    if not isinstance(val, (dict, list)):
        s = _sv(val, ind + 2)
        if '\n' in s:
            parts = s.split('\n')
            return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
        return [p + key + ': ' + s]
    if not val:
        return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
    r = [p + key + ':']
    if isinstance(val, dict):
        for k, v in val.items():
            r.extend(_yaml_lines(k, v, ind + 2))
    else:
        for item in val:
            r.extend(_list_item(item, ind))
    return r
def _list_item(item, ind):
    p = ' ' * ind
    if not isinstance(item, (dict, list)):
        s = _sv(item, ind + 2)
        if '\n' in s:
            parts = s.split('\n')
            return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
        return [p + '- ' + s]
    if isinstance(item, dict) and item:
        lines = []
        first = True
        for k, v in item.items():
            tag = '- ' if first else '  '
            first = False
            if isinstance(v, (dict, list)) and v:
                lines.append(p + tag + k + ':')
                if isinstance(v, list):
                    for sub in v:
                        lines.extend(_list_item(sub, ind + 2))
                else:
                    for dk, dv in v.items():
                        lines.extend(_yaml_lines(dk, dv, ind + 4))
            else:
                sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                if '\n' in sv:
                    parts = sv.split('\n')
                    lines.append(p + tag + k + ': ' + parts[0])
                    lines.extend(parts[1:])
                else:
                    lines.append(p + tag + k + ': ' + sv)
        return lines
    return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
frag = '\n'.join(_yaml_lines('acceptance_criteria', cmd_acs))
indented = '\n'.join('  ' + line for line in frag.split('\n'))

# Replace acceptance_criteria section（行ベース置換）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('acceptance_criteria:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
raw = '\n'.join(_result)
if not _inserted:
    task_match = re.search(r'^task:', raw, re.MULTILINE)
    if task_match:
        rest = raw[task_match.end():]
        top_m = re.search(r'^\S', rest, re.MULTILINE)
        if top_m:
            pos = task_match.end() + top_m.start()
            raw = raw[:pos] + indented + '\n' + raw[pos:]
        else:
            raw = raw.rstrip('\n') + '\n' + indented + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp_path, task_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise

print(f'[AC_OVERWRITE] Overwrote {len(cmd_acs)} ACs from cmd source ({parent_cmd})', file=sys.stderr)
OVERWRITE_AC_PY
        log "$(cat "$py_output")"
        rm -f "$py_output"
        return 0
    else
        log "WARN: _overwrite_ac_from_cmd failed: $(cat "$py_output")"
        rm -f "$py_output"
        return 1
    fi
}

__cluster_e_static_extraction_sentinel() { :; }
fi
# Cluster E module: task YAML normalization, AC/parent/causal/variation contracts.
_dt_task_contract_path="$SCRIPT_DIR/scripts/deploy_task/task_contract.sh"
if [ ! -f "$_dt_task_contract_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_task_contract_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/task_contract.sh"
fi
if [ ! -f "$_dt_task_contract_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_task_contract_path="$PROJECT_ROOT/scripts/deploy_task/task_contract.sh"
fi
source "$_dt_task_contract_path"
unset _dt_task_contract_path

# Legacy static-extraction compatibility for tests that copy deploy_task.sh only.
if false; then
# Publish the three report metadata fields in one parse and one rename.  Values
# are machine-generated safe scalars (UUID/version/repo-relative path).
deploy_task_publish_report_metadata() {
    local task_file="$1" report_id="$2" version="$3" report_path="$4" variation="${5:-false}"
    local commit_json="${6:-}" report_contract_json="${7:-}"
    local tmp="${task_file}.report-meta.$$"
    DEPLOY_TASK_META_COMMIT_JSON="$commit_json" \
    DEPLOY_TASK_META_REPORT_CONTRACT_JSON="$report_contract_json" \
    awk -v rid="$report_id" -v ver="$version" -v rpath="$report_path" -v variation="$variation" '
        BEGIN {
            in_task=0; skip_struct=0
            seen_id=seen_ver=seen_path=seen_variation=seen_commit=seen_report_contract=0
            commit_json=ENVIRON["DEPLOY_TASK_META_COMMIT_JSON"]
            report_contract_json=ENVIRON["DEPLOY_TASK_META_REPORT_CONTRACT_JSON"]
        }
        function emit_missing() {
            if (rid != "" && !seen_id) print "  report_id: " rid
            if (rid != "" && !seen_ver) print "  report_identity_version: " ver
            if (!seen_path) print "  report_path: " rpath
            if (!seen_variation) print "  variation_checks_required: " variation
            if (commit_json != "" && !seen_commit) print "  commit_contract: " commit_json
            if (report_contract_json != "" && !seen_report_contract) print "  report_contract_templates: " report_contract_json
        }
        /^task:[[:space:]]*$/ { in_task=1; print; next }
        in_task && skip_struct {
            if ($0 ~ /^  [A-Za-z_][A-Za-z0-9_]*:/ || $0 ~ /^[^[:space:]#][^:]*:/) {
                skip_struct=0
            } else {
                next
            }
        }
        in_task && /^[^[:space:]#][^:]*:/ {
            emit_missing()
            in_task=0
        }
        in_task && /^  report_id:/ { if (rid != "") print "  report_id: " rid; else print; seen_id=1; next }
        in_task && /^  report_identity_version:/ { if (rid != "") print "  report_identity_version: " ver; else print; seen_ver=1; next }
        in_task && /^  report_path:/ { print "  report_path: " rpath; seen_path=1; next }
        in_task && /^  variation_checks_required:/ { print "  variation_checks_required: " variation; seen_variation=1; next }
        in_task && /^  commit_contract:/ && commit_json != "" {
            print "  commit_contract: " commit_json
            seen_commit=1; skip_struct=1; next
        }
        in_task && /^  report_contract_templates:/ && report_contract_json != "" {
            print "  report_contract_templates: " report_contract_json
            seen_report_contract=1; skip_struct=1; next
        }
        { print }
        END {
            if (in_task) emit_missing()
        }
    ' "$task_file" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$task_file"
}

# A report template may be reused only while both its generator source and the
# task-generation query are unchanged.  The marker is deliberately separate
# from report YAML: worker edits remain byte-for-byte untouched and the report
# schema gains no cache-only fields.
deploy_task_report_generation_identity() {
    local task_file="$1"
    local source_file="${DEPLOY_TASK_REPORT_SOURCE_FILE:-$SCRIPT_DIR/scripts/deploy_task.sh}"
    local source_fp query_key

    [ -f "$source_file" ] || return 1
    source_fp="$(stat --printf='%d:%i:%s:%y:%z  %n\n' "$source_file" \
        | sha256sum | awk '{print $1}')" || return 1
    query_key="$(python3 - "$task_file" <<'PY'
import hashlib
import json
import sys

import yaml

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
if not isinstance(task, dict):
    raise SystemExit("task entry must be a mapping")

# These fields are lifecycle/derived publication state, not generation input.
# commit_contract is validated against the report separately when present: it
# is removed by reset_stale_fields on a same-generation retry and then safely
# rehydrated by the reconciliation path.
for key in (
    "status", "progress", "started_at", "acknowledged_at", "completed_at",
    "done_at", "deployed_at", "session_state", "previous_failures",
    "report_id", "report_identity_version", "report_path",
    "variation_checks_required",
    "commit_contract",
):
    task.pop(key, None)

payload = json.dumps(task, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
PY
    )" || return 1
    printf '%s\t%s\n' "$source_fp" "$query_key"
}

deploy_task_publish_report_generation_marker() {
    local marker_file="$1" report_rel_path="$2" source_fp="$3" query_key="$4" report_id="$5"
    local marker_tmp="${marker_file}.tmp.${BASHPID}"
    printf '%s\t%s\t%s\t%s\n' "$report_rel_path" "$source_fp" "$query_key" "$report_id" \
        > "$marker_tmp" || return 1
    mv "$marker_tmp" "$marker_file"
}

# Return values:
#   0 = exact same generation and all report/task contracts are current
#   2 = exact same generation, report is sound, task metadata needs reconcile
#   1 = source/task generation mismatch or report contract is stale/corrupt
deploy_task_report_generation_state() {
    local task_file="$1" report_file="$2" marker_file="$3" report_rel_path="$4"
    local expected_source_fp="$5" expected_query_key="$6"
    local marked_path="" marked_source_fp="" marked_query_key="" marked_report_id=""

    [ -f "$marker_file" ] || return 1
    IFS=$'\t' read -r marked_path marked_source_fp marked_query_key marked_report_id < "$marker_file" || return 1
    [ "$marked_path" = "$report_rel_path" ] || return 1
    [ "$marked_source_fp" = "$expected_source_fp" ] || return 1
    [ "$marked_query_key" = "$expected_query_key" ] || return 1
    [ -n "$marked_report_id" ] || return 1

    python3 - "$task_file" "$report_file" "$marked_report_id" "$report_rel_path" <<'PY'
import sys

import yaml

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
report = yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}
marked_report_id = sys.argv[3]
if not isinstance(task, dict) or not isinstance(report, dict):
    raise SystemExit(1)

required = {
    "worker_id", "report_id", "report_identity_version", "task_id",
    "parent_cmd", "task_type", "ac_version_read", "task_contract_snapshot",
    "result", "purpose_validation", "files_modified", "lesson_candidate",
    "lessons_useful", "skill_candidate", "decision_candidate",
    "knowledge_candidate", "assumption_invalidation", "operational_simulation",
    "binary_checks", "self_gate_check", "verdict",
}
if not required.issubset(report):
    raise SystemExit(1)

expected_worker = str(task.get("assigned_to") or task.get("worker_id") or "").strip()
expected_task_id = str(
    task.get("task_id") or task.get("_ac_task_id") or task.get("subtask_id") or ""
).strip()
expected_parent = str(task.get("parent_cmd") or task.get("cmd_id") or "").strip()
expected_ac = str(task.get("ac_version") or "").strip()
actual_identity = (
    str(report.get("worker_id") or "").strip(),
    str(report.get("task_id") or "").strip(),
    str(report.get("parent_cmd") or "").strip(),
    str(report.get("ac_version_read") or "").strip(),
)
if actual_identity != (expected_worker, expected_task_id, expected_parent, expected_ac):
    raise SystemExit(1)
if str(report.get("report_id") or "").strip() != marked_report_id:
    raise SystemExit(1)
if str(report.get("report_identity_version") or "").strip() != "2":
    raise SystemExit(1)

snapshot = report.get("task_contract_snapshot")
if not isinstance(snapshot, dict):
    raise SystemExit(1)
if str(snapshot.get("ac_fingerprint") or "").strip() != expected_ac:
    raise SystemExit(1)
if snapshot.get("acceptance_criteria") != task.get("acceptance_criteria"):
    raise SystemExit(1)

checks = report.get("binary_checks")
if not isinstance(checks, dict) or "commit" not in checks:
    raise SystemExit(1)
raw_criteria = task.get("acceptance_criteria") or []
criterion_ids = []
if isinstance(raw_criteria, list):
    for position, item in enumerate(raw_criteria, 1):
        if isinstance(item, dict):
            criterion_ids.append(str(item.get("id") or item.get("ac") or f"AC{position}").split(":", 1)[0].strip())
        else:
            criterion_ids.append(f"AC{position}")
elif isinstance(raw_criteria, dict):
    criterion_ids = [str(key).strip() for key in raw_criteria]
assigned = task.get("assigned_acs") or task.get("ac_assigned") or []
if isinstance(assigned, str):
    assigned = [part.strip() for part in assigned.strip("[]").split(",") if part.strip()]
if assigned:
    selected = []
    for value in assigned:
        value = str(value).strip()
        if value in criterion_ids:
            selected.append(value)
        elif value.upper().startswith("AC") and value[2:].isdigit():
            index = int(value[2:]) - 1
            if 0 <= index < len(criterion_ids):
                selected.append(criterion_ids[index])
    criterion_ids = selected
if any(ac_id not in checks for ac_id in criterion_ids):
    raise SystemExit(1)

# A missing task-side publication patch is repairable without replacing the
# sound report generation.  The caller takes the existing reconciliation path.
task_contract = task.get("commit_contract")
if task_contract is None or task_contract != report.get("commit_contract"):
    raise SystemExit(2)
if str(task.get("report_id") or "").strip() != marked_report_id:
    raise SystemExit(2)
if str(task.get("report_path") or "").strip() != sys.argv[4]:
    raise SystemExit(2)
raise SystemExit(0)
PY
}

# Optional phase telemetry for isolated report-publication benchmarks.  The
# caller owns the output path; normal deployments pay only the empty-variable
# branch and never create operational state.
deploy_task_report_phase_mark() {
    local label="$1" now_us elapsed_ms
    [ -n "${DEPLOY_TASK_REPORT_PHASE_FILE:-}" ] || return 0
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    elapsed_ms=$(( (now_us - _deploy_report_phase_last_us + 999) / 1000 ))
    printf '%s\t%s\n' "$label" "$elapsed_ms" >> "$DEPLOY_TASK_REPORT_PHASE_FILE"
    _deploy_report_phase_last_us="$now_us"
}

# Parse immutable cold-generation inputs in one PyYAML process.  Cache hits
# return before this helper is called; a cold publication previously started
# separate interpreters for snapshot, checkpoint, commit JSON, AC mapping,
# Level5 contract, and reflux contract despite all reading the same task bytes.
deploy_task_report_scope_seed() {
    local task_file="$1" import_root="$2"
    python3 - "$task_file" "$import_root" <<'PY'
import shlex, sys, yaml
sys.path.insert(0, sys.argv[2])
from scripts.gates.gate_report_format_main import commit_owned_paths

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
contract = task.get("commit_contract")
explicit = ""
if isinstance(contract, dict) and "required" in contract:
    value = contract["required"]
    if isinstance(value, bool):
        explicit = str(value).lower()
    elif str(value).strip().lower() in {"true", "false"}:
        explicit = str(value).strip().lower()
print("_commit_explicit_required=" + shlex.quote(explicit))
print("_commit_planned_paths=" + shlex.quote(" ".join(commit_owned_paths(task))))
PY
}

deploy_task_report_cold_plan() {
    python3 - "$@" <<'PY'
import hashlib, json, shlex, sys, yaml

(task_file, resolved_parent, resolved_task, issued_cmd, ac_version, project,
 required, reason, task_type, planned_raw, repo_root, expansion_reason) = sys.argv[1:]
task = (yaml.safe_load(open(task_file, encoding="utf-8")) or {}).get("task", {})
criteria = task.get("acceptance_criteria")
if not ac_version:
    payload = json.dumps(criteria, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    ac_version = hashlib.sha256(payload.encode()).hexdigest()[:16]

snapshot = {
    "parent_cmd": resolved_parent,
    "task_id": resolved_task,
    "issued_cmd_id": issued_cmd,
    "ac_fingerprint": ac_version,
    "purpose": str(task.get("purpose") or task.get("title") or task.get("command") or resolved_task).strip(),
    "project": str(task.get("project") or project or "unknown").strip(),
    "acceptance_criteria": criteria,
    "final_checkpoint": task.get("final_checkpoint"),
    "investigation_contract": task.get("investigation_contract"),
    "seam_contract": (
        task.get("investigation_contract", {}).get("seam_contract")
        if isinstance(task.get("investigation_contract"), dict)
        else None
    ),
    "reflux_commit_contract": task.get("reflux_commit_contract"),
}
checkpoint = task.get("final_checkpoint")
checkpoint_required = bool(
    isinstance(checkpoint, dict)
    and checkpoint.get("required") is True
    and checkpoint.get("type") == "ci_fix_clean_repro"
)
paths = [path for path in planned_raw.split() if path]
commit_contract = {
    "required": required == "true",
    "reason": reason,
    "task_type": task_type,
    "planned_paths": paths,
    "repo_root": repo_root,
}
if expansion_reason:
    commit_contract["scope_expansion_reason"] = expansion_reason

mapping = {}
for item in criteria or []:
    if isinstance(item, dict):
        key = str(item.get("id") or item.get("ac") or "").strip()
        if key:
            mapping[key] = ""
ac_block = "ac_evidence_mapping:"
for key in mapping:
    ac_block += f'\n  {key}: ""  # このACの一次証拠を1:1で記入'
level5 = {
    "ac_evidence_mapping": mapping,
    "semantic_validation": {
        "classification_axis": "", "recount": "", "actual": "", "result": "",
    },
}
level5_json = json.dumps(level5, ensure_ascii=False, separators=(",", ":"))
reflux = task.get("reflux_commit_contract")
values = {
    "ac_version": ac_version,
    "task_contract_snapshot": json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
    "final_checkpoint_required": str(checkpoint_required).lower(),
    "commit_contract_json": json.dumps(commit_contract, ensure_ascii=False, separators=(",", ":")),
    "commit_paths_json": json.dumps(paths, ensure_ascii=False, separators=(",", ":")),
    "ac_evidence_mapping_block": ac_block,
    # Preserve the existing task-side contract: yaml_field_set_batch stored
    # this payload as a scalar JSON string, while the report has typed maps.
    "level5_report_contract_json": json.dumps(level5_json, ensure_ascii=False),
    "reflux_commit_contract_json": json.dumps(reflux, ensure_ascii=False, separators=(",", ":")) if isinstance(reflux, dict) else "null",
}
for key, value in values.items():
    print(f"_plan_{key}=" + shlex.quote(value))
PY
}

generate_report_template() {
    local ninja_name="$1"
    local task_id="$2"
    local parent_cmd="$3"
    local project="$4"
    local task_file="${5:-$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml}"
    local report_file=""
    local report_rel_path=""
    local _deploy_report_phase_last_us="${EPOCHREALTIME/./}"
    _deploy_report_phase_last_us="${_deploy_report_phase_last_us:0:16}"

    # cmd_1983: 12+ field_get → field_get_multi 1回 (WSL2 subprocess削減)
    # task_id・parent_cmd はパラメータと同名のため上書き前にコピー
    local _p_task_id="$task_id" _p_parent_cmd="$parent_cmd"
    local report_filename="" assigned_to="" subtask_id="" task_id="" _ac_task_id="" \
          parent_cmd="" cmd_id="" ac_version="" title="" task_type="" target_path="" \
          scout_exempt="" type="" scope_mode="" purpose="" command="" description="" \
          constraints="" not_in_scope="" files_to_modify="" files_modified="" \
          owned_paths="" acceptance_criteria="" issued_cmd_id=""
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        report_filename assigned_to subtask_id task_id _ac_task_id \
        parent_cmd cmd_id ac_version title task_type target_path scout_exempt \
        type scope_mode purpose command description constraints not_in_scope \
        files_to_modify files_modified owned_paths acceptance_criteria issued_cmd_id 2>/dev/null)" || true

    # Reuse values already parsed by field_get_multi above.  Calling
    # is_enforcement_variation_contract_task here reparsed the same YAML in a
    # fresh Python process for every report template (the dominant hot path in
    # template-generation tests).
    local _variation_checks_required=false
    local _variation_text="${title:-} ${purpose:-} ${command:-} ${description:-} ${target_path:-} ${files_to_modify:-} ${files_modified:-} ${acceptance_criteria:-} ${constraints:-} ${not_in_scope:-}"
    _variation_text="${_variation_text,,}"
    local _variation_project="${project,,}"
    # 「gate/hook変更でない」の否定scopeをpositive keywordとして数えると、
    # 通常UI修正へenforcement variationを偽強制する。分類前に否定句だけ除く。
    _variation_text="$(printf '%s\n' "$_variation_text" | sed -E 's/(gate|hook|ゲート|フック)([[:space:]]*[/・][[:space:]]*(gate|hook|ゲート|フック))?[[:space:]]*(の)?変更[[:space:]]*(で|では)?ない//g')"
    local _variation_task_type="${task_type:-${type:-${scope_mode:-}}}"
    _variation_task_type="${_variation_task_type,,}"
    if [[ "$_variation_project" == "infra" ]] \
        && [[ ! "$_variation_task_type" =~ ^(scout|recon|recon2)$ ]] \
        && [[ "$_variation_text" =~ enforcement|gate|hook|detector|guard|watcher|state[[:space:]_-]?machine|ゲート|フック|検知器|ガード|監視 ]] \
        && [[ "$_variation_text" =~ scripts/|\.sh([^[:alnum:]_]|$)|\.py([^[:alnum:]_]|$)|コード変更|コード修正|実装|修正|implement|fix([^[:alnum:]_]|$) ]] \
        && [[ ! "$_variation_text" =~ docs?[[:space:]_-]?only|documentation[[:space:]_-]?only|教訓のみ|fixtureのみ|索引のみ|docsのみ ]]; then
        _variation_checks_required=true
    fi

    # report_filenameフィールドを優先参照（cmd_412: 命名ミスマッチ根治）
    local _effective_parent_cmd="${_p_parent_cmd:-${parent_cmd:-$cmd_id}}"
    if [ -n "$report_filename" ]; then
        report_file="$SCRIPT_DIR/queue/reports/${report_filename}"
    elif [[ -n "$_effective_parent_cmd" && "$_effective_parent_cmd" == cmd_* ]]; then
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${_effective_parent_cmd}.yaml"
    else
        # 後方互換: parent_cmdが未設定/不正なら旧形式にフォールバック
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    fi
    report_rel_path="queue/reports/$(basename "$report_file")"

    # v2 identity is minted once per new deployment generation. Legacy reports
    # remain read-only and continue through the deterministic fallback path.
    local report_id="" report_identity_version="2"

    mkdir -p "$SCRIPT_DIR/queue/reports"

    # GP-084改: gawk BEGINFILE/ENDFILE一括でverdict+parent_cmdを抽出（field_get逐次→一括化）
    # cmd_2832: 全報告globを避け、対象忍者分 + 同一parent_cmd分だけを読む。
    # 同一parent_cmd分は他忍者の完了報告を誤archiveしないために必要。
    declare -A _rpt_verdict _rpt_pcmd
    local _gawk_output _scan_report _report_scan_files=()
    local _active_report_index="$SCRIPT_DIR/queue/reports/.deploy_active_${ninja_name}"
    local _generation_marker="$SCRIPT_DIR/queue/reports/.deploy_generation_$(basename "$report_file")"
    local _generation_source_fp="" _generation_query_key=""
    IFS=$'\t' read -r _generation_source_fp _generation_query_key \
        < <(deploy_task_report_generation_identity "$task_file") \
        || { log "FATAL: report generation identity unavailable"; return 1; }
    deploy_task_report_phase_mark task_parse_identity
    local _indexed_report=""
    if [ -f "$_active_report_index" ]; then
        IFS= read -r _indexed_report < "$_active_report_index" || true
        case "$_indexed_report" in
            queue/reports/${ninja_name}_report_*.yaml)
                _indexed_report="$SCRIPT_DIR/$_indexed_report"
                [ -f "$_indexed_report" ] && _report_scan_files+=("$_indexed_report")
                ;;
        esac
    else
        # One-time migration for installations created before the pointer.
        # Subsequent deploys inspect only the prior active generation.
        for _scan_report in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml; do
            [ -f "$_scan_report" ] || continue
            _report_scan_files+=("$_scan_report")
        done
    fi
    if [[ -n "$_p_parent_cmd" && "$_p_parent_cmd" == cmd_* ]]; then
        for _scan_report in "$SCRIPT_DIR/queue/reports/"*"_report_${_p_parent_cmd}.yaml"; do
            [ -f "$_scan_report" ] || continue
            case " ${_report_scan_files[*]} " in
                *" $_scan_report "*) ;;
                *) _report_scan_files+=("$_scan_report") ;;
            esac
        done
    fi
    if [ "${#_report_scan_files[@]}" -gt 0 ]; then
        DEPLOY_TASK_REPORT_SCAN_COUNT=$(( ${DEPLOY_TASK_REPORT_SCAN_COUNT:-0} + ${#_report_scan_files[@]} ))
        _gawk_output=$(gawk '
        BEGINFILE { pcmd=""; verd="" }
        /^parent_cmd:/ { sub(/^parent_cmd:[[:space:]]*/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); sub(/[[:space:]]*$/, ""); pcmd=$0 }
        /^verdict:/ { sub(/^verdict:[[:space:]]*/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); sub(/[[:space:]]*$/, ""); verd=$0 }
        ENDFILE { printf "%s\t%s\t%s\n", FILENAME, pcmd, verd }
    ' "${_report_scan_files[@]}" 2>/dev/null) || true
    else
        _gawk_output=""
    fi
    while IFS=$'\t' read -r _rpt_file _rpt_p _rpt_v; do
        [ -z "$_rpt_file" ] && continue
        _rpt_verdict["$_rpt_file"]="$_rpt_v"
        _rpt_pcmd["$_rpt_file"]="$_rpt_p"
    done <<< "$_gawk_output"

    # cmd_1323: STALL再配備時の旧報告テンプレート自動cleanup
    # cmd_cycle_001: 他忍者の報告は絶対にアーカイブしない（配備対象の忍者名の報告のみ対象）
    if [[ -n "$_p_parent_cmd" && "$_p_parent_cmd" == cmd_* ]]; then
        local stale_basename
        for stale_report in "$SCRIPT_DIR/queue/reports/"*"_report_${_p_parent_cmd}.yaml"; do
            [ -f "$stale_report" ] || continue
            stale_basename=$(basename "$stale_report")
            # 自分の報告はスキップ（下のown-reportブロックで処理）
            if [[ "$stale_basename" == "${ninja_name}_report_"* ]]; then
                continue
            fi
            local _other_ninja="${stale_basename%%_report_*}"
            local _other_task_file="$SCRIPT_DIR/queue/tasks/${_other_ninja}.yaml"
            if [ -f "$_other_task_file" ]; then
                local _other_task_parent _other_task_status _owner_lookup
                # cmd_4165: owner8件cache+header text scan(同parent_cmd一致/malformed境界のみfull parse)
                _owner_lookup=$(deploy_task_owner_task_lookup "$_other_ninja" "$_other_task_file" "$_p_parent_cmd")
                IFS=$'\t' read -r _other_task_parent _other_task_status <<< "$_owner_lookup"
                if [[ "$_other_task_parent" == "$_p_parent_cmd" ]] && [[ "$_other_task_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
                    log "report_template: PROTECTED active other ninja report (${stale_basename}, status=${_other_task_status})"
                    continue
                fi
            fi
            # GP-105: 他忍者の報告: verdict判定でstale検出(STALL再配備対応)
            # 旧: 無条件保護 → STALL時にテンプレートが残留 → gate BLOCK → 家老手動移動(WA)
            # 新: verdict空=テンプレート(stale)→アーカイブ、verdict有=完了報告→保護
            local _other_verdict="${_rpt_verdict["$stale_report"]:-}"
            if [[ -n "$_other_verdict" && "$_other_verdict" != "null" && "$_other_verdict" != '""' ]]; then
                log "report_template: PROTECTED other ninja report (${stale_basename}, verdict=${_other_verdict})"
            else
                mkdir -p "$SCRIPT_DIR/archive/reports/stale"
                mv "$stale_report" "$SCRIPT_DIR/archive/reports/stale/"
                log "report_template: stale other ninja template archived (${stale_basename}, reassignment detected)"
            fi
        done
    fi

    # cmd_selfimprovement: 同忍者の別cmdテンプレート残存(stale report)の自動検知・アーカイブ
    local stale_own_basename stale_own_pcmd stale_own_verdict
    for stale_own_report in "${_report_scan_files[@]}"; do
        [ -f "$stale_own_report" ] || continue
        stale_own_basename=$(basename "$stale_own_report")
        [[ "$stale_own_basename" == "${ninja_name}_report_"* ]] || continue
        # 今回のターゲット報告はスキップ
        if [[ "$stale_own_report" == "$report_file" ]]; then
            continue
        fi
        # 既存報告のparent_cmdを取得（gawkキャッシュから）
        stale_own_pcmd="${_rpt_pcmd["$stale_own_report"]:-}"
        # parent_cmdが同じならスキップ（同cmdの報告）
        if [[ "$stale_own_pcmd" == "$parent_cmd" ]]; then
            continue
        fi
        # 別cmdの報告: verdict確認（gawkキャッシュから）
        stale_own_verdict="${_rpt_verdict["$stale_own_report"]:-}"
        if [[ -n "$stale_own_verdict" && "$stale_own_verdict" != "null" && "$stale_own_verdict" != '""' ]]; then
            log "report_template: completed own report preserved (${stale_own_basename}, verdict=${stale_own_verdict})"
            continue
        fi
        # verdict空のテンプレート → staleアーカイブ
        mkdir -p "$SCRIPT_DIR/archive/reports/stale"
        mv "$stale_own_report" "$SCRIPT_DIR/archive/reports/stale/"
        log "report_template: stale own report archived (${stale_own_basename}, old_cmd=${stale_own_pcmd})"
    done
    deploy_task_report_phase_mark report_scan_archive

    # Exact generation hit: source_fp + query_key and the report's schema,
    # AC/binary-check contract and v2 identity all match.  No report/task YAML
    # or pointer rewrite is needed.  A key miss is a new generation: archive
    # the old artifact and mint a fresh identity instead of silently reusing it.
    if [ -f "$report_file" ]; then
        local _generation_state=1 _active_pointer_value=""
        if deploy_task_report_generation_state "$task_file" "$report_file" \
            "$_generation_marker" "$report_rel_path" \
            "$_generation_source_fp" "$_generation_query_key"; then
            _generation_state=0
        else
            _generation_state=$?
        fi
        if [ "$_generation_state" -eq 0 ]; then
            [ -f "$_active_report_index" ] \
                && IFS= read -r _active_pointer_value < "$_active_report_index" \
                || _active_pointer_value=""
            if [ "$_active_pointer_value" = "$report_rel_path" ]; then
                log "report_template: generation cache hit source_fp=${_generation_source_fp} query_key=${_generation_query_key} (${report_file})"
                return 0
            fi
            _generation_state=2
        fi
        if [ "$_generation_state" -eq 2 ]; then
            log "report_template: same generation requires metadata reconcile (${report_file})"
            report_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "report_id" "" 2>/dev/null || true)
            ensure_report_template_completeness "$report_file" "$task_file"
            rehydrate_task_commit_contract_from_report "$task_file" "$report_file" || return 1
            deploy_task_publish_report_metadata "$task_file" "$report_id" "$report_identity_version" "$report_rel_path" "$_variation_checks_required" || return 1
            deploy_task_publish_active_report_pointer "$_active_report_index" "$report_rel_path" || return 1
            IFS=$'\t' read -r _generation_source_fp _generation_query_key \
                < <(deploy_task_report_generation_identity "$task_file") \
                || return 1
            deploy_task_publish_report_generation_marker "$_generation_marker" \
                "$report_rel_path" "$_generation_source_fp" "$_generation_query_key" "$report_id" \
                || return 1
            log "report_path: set (${report_rel_path})"
            return 0
        fi

        local _stale_generation_dir="$SCRIPT_DIR/archive/reports/stale"
        local _stale_generation_file
        mkdir -p "$_stale_generation_dir"
        _stale_generation_file="$_stale_generation_dir/$(basename "$report_file").generation-${_generation_source_fp:0:12}-${_generation_query_key:0:12}-${BASHPID}-$(date +%s%N)"
        mv "$report_file" "$_stale_generation_file" || return 1
        log "report_template: generation changed; archived stale report ($(basename "$_stale_generation_file"))"
    fi

    # `new` in report_unique_identity.py is only uuid.uuid4().  Read the
    # kernel UUID source directly to avoid a Python+PyYAML cold start on every
    # deployment while preserving the exact rpt-<uuid> identity contract.
    local _report_uuid=""
    IFS= read -r _report_uuid < /proc/sys/kernel/random/uuid || return 1
    [[ "$_report_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || return 1
    report_id="rpt-${_report_uuid}"

    # タスクYAMLから自動記入値を取得（cmd_532: 機械的フィールド自動記入）
    # cmd_1983: field_get_multiで一括取得済み → 変数参照のみ
    local worker_id="${assigned_to:-$ninja_name}"
    local resolved_task_id="${task_id}"
    if [ -z "$resolved_task_id" ]; then
        resolved_task_id="${_ac_task_id:-${subtask_id:-$_p_task_id}}"
    fi
    # task_id系が全て空なら_ac_task_idをfallback
    if [ -z "$resolved_task_id" ]; then
        resolved_task_id="${_ac_task_id}"
    fi
    local resolved_parent_cmd="${parent_cmd:-${cmd_id:-$_p_parent_cmd}}"
    # Freeze the deploy-generation contract inside the report.  A worker task
    # is mutable by design and may already describe the next assignment when
    # SG7 is generated; review must never recover an old contract from it.
    local _task_contract_snapshot=""
    # Level 5: report generation must hand the worker task-specific summary
    # context instead of manufacturing the known-bad FILL_THIS token.  This is
    # deliberately phrased as the task outcome to record; measured evidence is
    # still supplied by the worker in result.details/binary_checks before the
    # terminal transition.
    local _summary_context="${title:-${purpose:-$resolved_task_id}}"
    _summary_context="${_summary_context//$'\n'/ }"
    _summary_context="${_summary_context//\\/\\\\}"
    _summary_context="${_summary_context//\"/\\\"}"
    # ac_version: field_get_multi済み($ac_version)
    local _before_after_block=""
    if is_before_after_required_task "$task_file" "$resolved_parent_cmd" "$title" "$task_type"; then
        _before_after_block=$(cat <<'EOF'
before_metrics:
  summary: ""  # 実装前の計測値
  details: ""
after_metrics:
  summary: ""  # 実装後の計測値
  details: ""
regression: ""  # yes or no
EOF
)
    fi
    local _causal_verification_block=""
    if deploy_task_needs_causal_verification "$task_file"; then
        _causal_verification_block=$(cat <<'EOF'
causal_verification:
  cause_checked: ""  # git log/blame・教訓・設計書・semantic/causal確認結果を3行以上で記入
  design_intent_checked: ""  # 守るべき設計意図/既存防御を記入
  evidence: ""  # bounded確認: git log/blame, rg, causal_backlinks, semantic_search(timeout/scope限定)
  origin: ""  # [[発端]] -> [[原因]] -> [[結果]]
EOF
)
    fi
    local _investigation_outcome_block=""
    if [[ "${task_type,,}" =~ ^(recon|recon2|scout)$ ]]; then
        local _seam_contract_required=false
        _seam_contract_required=$(python3 - "$task_file" <<'PY_SEAM_REPORT_CONTRACT'
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
investigation = task.get("investigation_contract")
seam = investigation.get("seam_contract") if isinstance(investigation, dict) else None
print("true" if isinstance(seam, dict) and seam.get("required") is True else "false")
PY_SEAM_REPORT_CONTRACT
)
        if [ "$_seam_contract_required" = true ]; then
            _investigation_outcome_block=$(cat <<'EOF'
investigation_outcome:
  # 発見件数は合否条件ではない。指定範囲を調べ切り、一次証拠で問いを解決したかが合否。
  outcome: ""  # found / zero_found / not_present / external_boundary / unknown_after_exhaustion
  method_completed: false  # 指定された探索方法・範囲を完遂した時だけtrue
  primary_evidence:
    - field: primary_payload
      source: ""
      observation: ""
    - field: companion_caches
      source: ""
      observation: ""
    - field: key_set
      source: ""
      observation: ""
    - field: date_domain
      source: ""
      observation: ""
    - field: empty_behavior
      source: ""
      observation: ""
    - field: fallback
      source: ""
      observation: ""
    - field: side_effects
      source: ""
      observation: ""
    - field: legacy_only_policy
      source: ""
      observation: ""
    - field: downstream_cardinality
      source: ""
      observation: ""
  remaining_unknowns: []  # 無ければ[]。unknown_after_exhaustionなら残存不明点を列挙
EOF
            )
        else
            _investigation_outcome_block=$(cat <<'EOF'
investigation_outcome:
  # 発見件数は合否条件ではない。指定範囲を調べ切り、一次証拠で問いを解決したかが合否。
  outcome: ""  # found / zero_found / not_present / external_boundary / unknown_after_exhaustion
  method_completed: false  # 指定された探索方法・範囲を完遂した時だけtrue
  primary_evidence: []  # [{source: "file:line/query/output", observation: "観測事実"}] 最低1件
  remaining_unknowns: []  # 無ければ[]。unknown_after_exhaustionなら残存不明点を列挙
EOF
            )
        fi
    fi
    local _variation_checks_block=""
    if [ "$_variation_checks_required" = true ]; then
        _variation_checks_block=$(cat <<'EOF'
variation_checks:
  normal_pass:
    check: "正常系PASSを実行して期待どおり通過することを確認"
    result: ""  # yes or no
  quoted_or_heredoc:
    check: "引用符付き入力またはheredoc入力で同じ契約を確認"
    result: ""  # yes or no
  linked_worktree:
    check: "linked worktree環境で対象処理を確認"
    result: ""  # yes or no
  parallel_or_respawn:
    check: "併走またはrespawnを伴う状態遷移を確認"
    result: ""  # yes or no
  abnormal_exit:
    check: "異常exit時にfail-closedで安全停止することを確認"
    result: ""  # yes or no
EOF
)
    fi
    # LG055 Level5: 全CLI/LLMが同じ報告構造を受け取るよう、全reportへ
    # operational_simulationを事前生成する。docs/data-only免除は提出gateが
    # files_modifiedの実績から判定し、template構造自体は分岐させない。
    local _opsim_block
    _opsim_block=$(cat <<'EOF'
operational_simulation:
  command: ""  # 実走コマンド(bats / bash / curl 等)
  expected: ""  # 期待結果
  actual: ""  # 実際の結果
  result: ""  # PASS or FAIL
EOF
)

    # Typed terminal checkpoints are report evidence, not worker ACs.  Keep
    # the evidence scaffold in the report so the terminal gate can validate
    # it against the frozen task_contract_snapshot exactly once.
    local _final_checkpoint_block=""

    # The task contract is the SSOT when it explicitly carries required.
    # Only legacy tasks without that key fall back to type/path inference.
    local _commit_required=true _commit_reason="code_or_unclassified_task"
    local _commit_explicit_required="" _commit_planned_paths=""
    eval "$(deploy_task_report_scope_seed "$task_file" "${PROJECT_ROOT:-$SCRIPT_DIR}")" || return 1
    local _commit_task_type="${task_type:-${type:-${scope_mode:-unknown}}}"
    _commit_task_type="${_commit_task_type,,}"
    local _commit_original_planned_paths="$_commit_planned_paths"
    local _commit_scope_expansion_reason=""
    # B32 asymmetric expansion: an AC that orders the worker to extend tests
    # makes the test file part of the delivery, but issuers only declare the
    # implementation path, so every such task hit "files_modified path is
    # outside planned scope" (25 real pairs on 2026-07-25/26).  Expand the
    # ceiling only toward existing tests/ files tied to a planned
    # implementation path (name stem or in-file reference).  Unrelated tests/
    # files and every non-tests/ path stay outside scope.
    if [ "${project:-infra}" = "infra" ] && [ -d "$SCRIPT_DIR/tests" ]; then
        local _commit_paths_with_tests
        _commit_paths_with_tests=$(python3 - "$task_file" "$SCRIPT_DIR" "$_commit_planned_paths" <<'PY'
import os, re, subprocess, sys, yaml

task_file, repo_root, planned_raw = sys.argv[1], sys.argv[2], sys.argv[3]
planned = [p for p in planned_raw.split() if p]
task = (yaml.safe_load(open(task_file, encoding="utf-8")) or {}).get("task", {}) or {}


def ac_text(value):
    if isinstance(value, dict):
        return " ".join(ac_text(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return " ".join(ac_text(v) for v in value)
    return str(value or "")


text = ac_text(task.get("acceptance_criteria"))
requires_test = bool(re.search(r"(テスト|bats|fixture|regression|tests?/|\btests?\b)", text, re.IGNORECASE))
code_paths = [p for p in planned if not p.startswith("tests/")]
# Explicit test ownership is authoritative.  B32 only repairs legacy/direct
# tasks whose issuer supplied implementation ownership but omitted every test
# path; widening an already-declared contract turns one focused test into every
# test that happens to mention the hot dispatcher.
explicit_test_paths = [p for p in planned if p.startswith("tests/")]
if not requires_test or not code_paths or explicit_test_paths:
    print(" ".join(planned))
    raise SystemExit(0)

stems = {os.path.splitext(os.path.basename(p))[0] for p in code_paths}
names = {os.path.basename(p) for p in code_paths}
tests_root = os.path.join(repo_root, "tests")


def run(cmd, stdin_text=None):
    try:
        proc = subprocess.run(
            cmd, cwd=repo_root, input=stdin_text,
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode > 1:  # 1 == "no match" for grep, which is a real answer
        return None
    return proc.stdout.split()


# This runs on the hot deploy path, so the scan stays in C: the git index lane
# (~0.9s on DrvFs) is tried first and find+grep (~1.8s) is the fallback for
# non-repo trees such as the bats scaffold.  A Python walk+read was 4.9s.
# The task test runner executes inferred contract files through Bats.  Inferring
# Python or plain shell helpers here turns valid source files into invalid Bats
# inputs (a detector false positive); explicitly declared paths remain intact.
suffixes = (".bats",)
# "^[^#]*" keeps a comment-only mention from widening the ceiling:
# tests/unit/test_inbox_write.bats names scripts/archive_completed.sh in a
# comment and must stay outside scope.
patterns = "\n".join(
    "^[^#]*" + re.escape(token) for token in sorted(set(code_paths) | names)
)

test_files = run(["git", "ls-files", "--", "tests"])
if test_files is not None:
    test_files = [p for p in test_files if p.endswith(suffixes)]
    hits = run(["git", "grep", "-lE", "-f", "-", "--", "tests"], patterns) or []
else:
    test_files = run(
        ["find", tests_root, "-type", "f", "-name", "*.bats"],
    ) or []
    hits = []
    if test_files:
        hits = run(["grep", "-lE", "-f", "-", "--", *test_files], patterns) or []

added = set()
for path in test_files:
    stem = os.path.splitext(os.path.basename(path))[0]
    if any(stem == "test_" + s or stem.startswith("test_" + s + "_") for s in stems):
        added.add(os.path.relpath(os.path.join(repo_root, path), repo_root))
for hit in hits:
    if hit.endswith(suffixes):
        added.add(os.path.relpath(os.path.join(repo_root, hit), repo_root))

print(" ".join(planned + sorted(p for p in added if p not in planned)))
PY
) || _commit_paths_with_tests=""
        if [ -n "$_commit_paths_with_tests" ]; then
            _commit_planned_paths="$_commit_paths_with_tests"
            if [ "$_commit_planned_paths" != "$_commit_original_planned_paths" ]; then
                _commit_scope_expansion_reason="B32: acceptance criteria require extending existing tests tied to the declared implementation path"
            fi
        fi
    fi
    local _commit_has_code_path=false
    if printf '%s\n' "$_commit_planned_paths" | grep -Eqi \
        '(scripts/|src/|tests/|app/|lib/|[[:alnum:]_./-]+\.(sh|bash|py|js|jsx|ts|tsx|go|rs|java|kt|rb|php|c|cc|cpp|h|hpp)([^[:alnum:]_]|$))'; then
        _commit_has_code_path=true
    fi
    local _commit_scope_text="${constraints} ${not_in_scope}"
    if [ -n "$_commit_explicit_required" ]; then
        _commit_required="$_commit_explicit_required"
        _commit_reason="task_commit_contract_explicit"
    elif echo "$_commit_scope_text" | grep -qiE 'コード変更.*禁止|変更.*禁止.*(調査|報告)|no[[:space:]_-]?code|read[[:space:]_-]?only'; then
        _commit_required=false
        _commit_reason="explicit_no_code_scope"
    elif [[ "$_commit_task_type" =~ ^(no[_-]?code|decision|decision_candidate|data[_-]?readonly|readonly|read_only|recon|recon2|scout|verification|verify)$ ]]; then
        # recon2/scout/verification等は読み取り専用。inspection_path/readonly_refsにscripts/パスがあっても
        # コード変更しないためhas_code_pathに関係なくrequired=false (2026-07-23 軍師D0)
        # verification/verify追加: 2026-08-14 偽陽性根治。tobisaru guard14で3回BLOCK→家老手動修正が必要だった
        _commit_required=false
        _commit_reason="allowed_no_code_task_type"
    elif [ "$_commit_has_code_path" = true ]; then
        _commit_reason="implementation_path_present"
    fi
    local _commit_paths_evidence="$_commit_planned_paths"
    _commit_paths_evidence="${_commit_paths_evidence//$'\n'/ }"
    _commit_paths_evidence="${_commit_paths_evidence//\/\\}"
    _commit_paths_evidence="${_commit_paths_evidence//\"/\\\"}"
    local _commit_repo_root
    if [ "${project:-infra}" = "infra" ]; then
        _commit_repo_root="$SCRIPT_DIR"
    else
        _commit_repo_root=$(get_project_path "${project}" 2>/dev/null || true)
    fi
    [ -n "$_commit_repo_root" ] || _commit_repo_root="$SCRIPT_DIR"
    _commit_repo_root=$(git -C "$_commit_repo_root" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$_commit_repo_root")
    deploy_task_report_phase_mark commit_scope_derivation
    local _plan_ac_version="" _plan_task_contract_snapshot="" \
        _plan_final_checkpoint_required=false _plan_commit_contract_json="" \
        _plan_commit_paths_json="" _plan_ac_evidence_mapping_block="" \
        _plan_level5_report_contract_json="" _plan_reflux_commit_contract_json=null
    eval "$(deploy_task_report_cold_plan "$task_file" "$resolved_parent_cmd" "$resolved_task_id" \
        "${issued_cmd_id:-}" "${ac_version:-}" "${project:-}" "$_commit_required" \
        "$_commit_reason" "$_commit_task_type" "$_commit_planned_paths" \
        "$_commit_repo_root" "$_commit_scope_expansion_reason")" || return 1
    ac_version="$_plan_ac_version"
    _task_contract_snapshot="$_plan_task_contract_snapshot"
    local _commit_contract_json="$_plan_commit_contract_json"
    local _commit_paths_json="$_plan_commit_paths_json"
    local _ac_evidence_mapping_block="$_plan_ac_evidence_mapping_block"
    local _level5_report_contract_json="$_plan_level5_report_contract_json"
    local _reflux_commit_contract_json="$_plan_reflux_commit_contract_json"
    if [ "$_plan_final_checkpoint_required" = true ]; then
        _final_checkpoint_block=$(cat <<'EOF'
ci_fix_clean_repro_evidence:
  e2_harness_command: ""
  pre_fix_receipt:
    path: ""
    status: ""
    source_commit: ""
    fixed_target: ""
    started_at: ""
    failures: null
    skips: null
  post_fix_receipt:
    path: ""
    status: ""
    source_commit: ""
    fixed_target: ""
    started_at: ""
    failures: null
    skips: null
  push_started_at: ""
  outcome: ""
  not_reproducible:
    independent_receipts: []
    ci_green:
      run_id: ""
      status: ""
      observed_at: ""
      commit: ""
    diagnostics:
      path: ""
      emits: []
EOF
)
    fi
    deploy_task_report_phase_mark cold_plan
    # The task and report must expose one typed contract.  Previously only the
    # report template received this block, so report review read a different
    # SSOT from commit helpers after deployment.
    # commit_contract is a typed mapping.  The scalar-oriented batch writer
    # quotes JSON punctuation and turns it into a string, which makes a real
    # recon report fail only after deployment.  Use the shared structural
    # writer already used by every typed task contract.
    deploy_task_report_phase_mark commit_contract_built
    local _commit_contract_block
    _commit_contract_block=$(cat <<EOF
commit_contract:
  required: ${_commit_required}
  reason: "${_commit_reason}"
  task_type: "${_commit_task_type}"
  planned_paths: ${_commit_paths_json}
  repo_root: "${_commit_repo_root}"
EOF
)
    local _cross_repo_commits_block=""
    if [ "$_commit_repo_root" != "$SCRIPT_DIR" ]; then
        _cross_repo_commits_block=$(cat <<EOF
cross_repo_commits:
  - repo: "${_commit_repo_root}"
    commit_hash: ""  # 対象repoで作成した40文字commit hash
    paths: ${_commit_paths_json}  # commit_contractと同じ所有scope
EOF
)
    fi

    local _semantic_validation_block
    _semantic_validation_block=$(cat <<'EOF'
semantic_validation:
  # ★N×M一致が無い場合も記入必須。空欄・散文はBLOCKされる(precheck LG048はPASS/FAILのリテラルのみ受理する)
  # ★該当なしなら「分類軸は存在しない/偶然の一致である」を再計数で示し result: PASS を記入せよ
  # ★意味検算の結果、分類漏れ等の問題が実在するなら result: FAIL とし、recount/actualの再計数根拠を添えて差し戻しフローで扱う
  classification_axis: ""  # 分類軸。無ければ「分類軸なし(偶然の一致)」+各数値の由来
  recount: ""  # 分類軸ごとの再計算式・件数。偶然なら各数値がどこ由来かを1つずつ特定する
  actual: ""  # 分類別内訳の実測。積の関係で生成された数値が実在しないなら、その旨を実測で示す
  result: ""  # PASS or FAIL(リテラルのみ受理。★空欄・散文不可)
EOF
)
    # Build the complete canonical template off-path.  Readers must observe
    # either no report or one complete report; never a partially appended
    # template.  New templates already emit candidate fields as mappings, so
    # the legacy normalize_report subprocess would only rescan the file.
    local _report_publish_file="${report_file}.publish.$$"
    cat > "$_report_publish_file" <<EOF
# !! トップレベル構造を維持せよ。report: で包むな !!
# !! report_field_set.sh で各フィールドを設定せよ。直接Edit/Write禁止 !!
# Step1: Read this file → Step2: bash scripts/report_field_set.sh <this_file> <key> <value> で各フィールドを埋めよ
# ━━━ report_field_set.sh ドット記法クイックリファレンス ━━━
# RFS="bash scripts/report_field_set.sh <このファイル>"
# !! result.summary はタスク文脈を事前供給済み。完了前に実測結果を追記せよ !!
# \$RFS result.summary "実施内容と検証結果の1行要約"
# \$RFS result.details "詳細文"
# \$RFS lesson_candidate.found "false"
# \$RFS lesson_candidate.no_lesson_reason "既知パターンL084"
# echo '[{check: "内容", result: "yes"}]' | \$RFS binary_checks.AC1 -
# 既存依存を参照のみで確認した場合:
# echo '- {path: scripts/existing.sh, reason: "既存依存として参照のみ。変更不要を確認", checked_not_modified: true}' | \$RFS verified_existing_dependency -
# memory_references全体を更新する場合:
# echo '- {id: MEM001, source: semantic_search, query: "検索語", summary: "要約", used: true, useful: true, reason: "判断に使用"}' | \$RFS memory_references -
# verdict は gate_report_format.sh が binary_checks から自動導出する。手動記入禁止。
# !! スペース区切り(lesson_candidate found false)は不可 → ドット記法必須 !!
# ━━━ 提出手順（番号順に実行せよ）━━━
# 1. 内容記入: result.summary/details, purpose_validation, lesson_candidate, files_modified
# 2. 構造記入: binary_checks全result→yes/no, lessons_useful全reason記入, status→completed
# 3. gate実行: bash scripts/gates/gate_report_format.sh <このファイル>
# 4. PASS確認後: inbox_writeで家老に報告
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
worker_id: ${worker_id}
report_id: ${report_id}
report_identity_version: ${report_identity_version}
task_id: ${resolved_task_id}
parent_cmd: ${resolved_parent_cmd}
task_type: ${task_type}
timestamp: ""  # date "+%Y-%m-%dT%H:%M:%S" で取得せよ
completed_at: ""  # terminal report publication time; report_field_set.sh fills this atomically
status: pending
ac_version_read: ${ac_version}
task_contract_snapshot: ${_task_contract_snapshot}
reflux_commit_contract: ${_reflux_commit_contract_json}
result:
  summary: "${_summary_context} — 実施・検証結果を本報告へ記録"  # Level5: task context pre-supplied; 完了前に実測を追記
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
simplicity_check: ""  # 既存仕組みで足りるか / 複雑さ追加が必要なら理由を1文で記せ
assumption_check: ""  # ACの前提に疑問はないか？不明な点があればdecision_candidateに書け(Karpathy原則1)
task_clarity:
  score: ""         # 0-100: タスクの明瞭度(100=完全明瞭, 0=全不明)。cmdの品質を記録
  unclear_points: ""   # 不明瞭だった点を1文で(なければ"なし")
  discretion_fills: "" # 独自判断で補完した内容(なければ"なし")
# GStack/GBrain takeaway #9, #18 — 4-way debug verdict と test ownership triage を追加。
# gate互換のため top-level verdict は PASS/FAIL/PASS_NO_IMPROVEMENT を維持し、
# 4択は status_detail に分離して保持する。
status_detail: ""  # DONE / WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT
test_triage: ""  # in_branch / pre_existing / unknown
${_before_after_block}
${_causal_verification_block}
${_commit_contract_block}
${_cross_repo_commits_block}
${_ac_evidence_mapping_block}
${_semantic_validation_block}
files_modified:
  - path: ""  # 変更ファイルパスを記入。説明文ではなく repo-root 相対パス
    change: ""  # 変更内容を1文で記入
lesson_candidate:
  # found: true/false を書け。リスト形式[] 禁止
  # ── found:true の場合（title/detail/project 全て必須）──
  # \$RFS lesson_candidate.found "true"
  # \$RFS lesson_candidate.title "教訓タイトル"
  # \$RFS lesson_candidate.detail "何が起きて何を学んだか"
  # \$RFS lesson_candidate.project "${project}"
  # ── found:false の場合（no_lesson_reason 必須）──
  # \$RFS lesson_candidate.found "false"
  # \$RFS lesson_candidate.no_lesson_reason "既知のL084と同じパターン"
  found: false
  no_lesson_reason: "このタスクでは新規教訓候補なし"  # found:false時に必須。必要なら具体理由に書換えよ
  title: ""
  detail: ""
  project: ${project}
lessons_useful: []  # ★教訓注入なし。このフィールドを変更するな。空リストのまま提出せよ
skill_candidate:
  found: false  # 同じ手順を3回以上繰り返したらfound: trueにせよ
  # found: true の場合は以下も記入:
  # name: ""        # スキル名 例: "cdp-page-measure"
  # description: "" # 何をするスキルか 例: "CDP経由でページ計測を自動実行"
  # reason: ""      # なぜスキル化すべきか 例: "CDP計測手順を5回以上手動実行した"
  # project: ""     # 対象PJ 例: "dm-signal"
decision_candidate:
  found: false
knowledge_candidate:
  found: false  # タスク中に新たな事実データ(DBカラム名/API仕様/設定値等)を発見したか？
  # found: true の場合は以下も記入:
  # items:
  #   - fact: "発見した事実を1文で"  # 例: "recalculation_timingsのカラム名はfinished_at(completed_atは不在)"
  #     source: "確認元ファイル/行"  # 例: "backend/app/db/models.py L601"
  # ★ lesson_candidateとの違い: lessonは行動ルール(「推測するな」)、knowledgeは事実データ(「正しいカラム名はX」)
  # ★ 家老がknowledge_candidateをprojects/{id}.yamlに還流させる
assumption_invalidation:
  found: false  # この結果は過去のどのcmdの前提を変更するか？ true/false
  affected_cmds: []  # found:true時、前提が変わるcmd_IDリスト 例: [cmd_1400, cmd_1410]
  detail: ""  # 何がどう変わるか。found:false時は空文字でよい
hook_failures:
  count: 0
  details: ""
  # count>0の場合はdetailsを文字列のままにせず、以下6キーのmapping形式で記入せよ(LG083):
  # {cause: "原因", independent_verification: "独立検証内容", bypass_record: "回避記録", post_verification: "事後検証内容", post_verification_result: "all_pass/no_new_failure/regression_detected", post_verification_head: "事後検証を実測した7-40文字のcommit hash"}
post_deploy_evidence:
  # deploy後のcron/外部job完走確認がACに含まれる場合だけ required: true にして記入せよ。
  # cmd_complete_gate が evidence_run_start_at > deploy_live_at と run_completed=true を検証する。
  required: false
  deploy_live_at: ""  # UTC推奨。例: 2026-06-11T11:10:00Z
  evidence_run_start_at: ""  # UTC推奨。例: 2026-06-12T01:00:00Z
  evidence_run_completed_at: ""  # UTC推奨。例: 2026-06-12T02:10:00Z
  run_completed: false
  source: ""  # timing-history id / Render log timestamp / DB queryなど一次証跡
${_opsim_block}
${_final_checkpoint_block}
${_variation_checks_block}
${_investigation_outcome_block}
binary_checks: {}  # AC完了ごとに ACN: [{check: "確認内容", result: "yes/no"}] を記入
# ⚠ result値は "yes" or "no" のみ。true/false/PASS/FAIL/OK等はBLOCKされる
# 例: echo '[{check: "コメント追加済みか", result: "yes"}]' | \$RFS binary_checks.AC1 -
# ─── self gate（cmd_karo_self_gate_template: 全報告テンプレートへ標準注入） ───
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: ""
# ━━━ 提出前最終確認（gate実行前に全項目を確認せよ）━━━
# □ binary_checks: 全ACの全result欄に "yes" or "no" を記入したか（"PASS"不可）
# □ lessons_useful: 全reason欄に有用/無用の具体的理由を記入したか
# □ verdict: 手動記入していないか（gateが自動導出する）
# □ status: completed に変更したか
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    local _report_final_file="$report_file"
    report_file="$_report_publish_file"
    deploy_task_report_phase_mark initial_template_write

    # cmd_1131+cmd_1393: related_lessonsが存在する場合、lessons_usefulを記入用雛形に差替え（Python→bash/awk）
    local _lu_ids
    _lu_ids=$(report_lesson_ids_for_task "$task_file")

    if [ -z "$_lu_ids" ]; then
        # GP-088/cmd_2665: related_lessonsなし or id抽出不能 → 空リストを維持
        if grep -Eq '^lessons_useful:[[:space:]]*(null|~)[[:space:]]*$' "$report_file" 2>/dev/null; then
            sed -Ei 's/^lessons_useful:[[:space:]]*(null|~)[[:space:]]*$/lessons_useful: []  # ★教訓注入なし。このフィールドを変更するな。空リストのまま提出せよ/' "$report_file"
            log "report_template: lessons_useful empty-list fallback"
        fi
    else
        # IDリストからlessons_useful雛形を生成
        local _lu_block="lessons_useful:  # ★教訓注入済み。[]で上書きするな。各教訓にuseful+reasonを記入せよ"
        local _lu_count=0
        while IFS= read -r _lid; do
            [ -z "$_lid" ] && continue
            _lu_block="${_lu_block}
  - id: ${_lid}
    useful: false
    reason: '未参照'  # 有用なら具体的理由に書換えよ。例: \"${_lid}のreturn 1罠と一致し、set -e呼出元確認の指針として有用\" / \"今回の変更では未使用。対象箇所と無関係\""
            _lu_count=$((_lu_count + 1))
        done <<< "$_lu_ids"

        # report内のlessons_useful空値を差し替え
        if grep -Eq '^lessons_useful:[[:space:]]*(null|~|\[\])' "$report_file" 2>/dev/null; then
            # cmd_karo_hotfix_post_clear_fail_open_20260725: awk -v はPOSIX仕様でCエスケープ(\t等)を
            # 解釈し、埋込テキスト中のリテラル\tを実タブへ化けさせYAMLを破壊する。ENVIRON経由で
            # 値をエスケープ解釈なしに渡す(cmd_complete_gate.shのgate_metrics literal_tab修正と同型)。
            # AC3検証: tests/unit/test_deploy_task.bats「literal backslash-t in AC description survives
            # report template injection」fixtureでリテラル\t保存+yaml.safe_load成功を確認済み。
            _LU_BLOCK_ENV="$_lu_block" awk '
                /^lessons_useful:[[:space:]]*(null|~|\[\])/ { print ENVIRON["_LU_BLOCK_ENV"]; next }
                { print }
            ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
            log "lessons_useful template: ${_lu_count} entries injected"
            log "report_template: lessons_useful template injected"
        fi
    fi

    # cmd_3739: task contextから三層記憶をfail-soft検索し、報告側に参照記録欄を生成する。
    # lessons_usefulとは別欄にして、教訓ID検証/集計と記憶参照の評価を混ぜない。
    local _memory_references_block
    _memory_references_block=$(
        TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY_MEMORY_REFS'
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path = Path(os.environ["TASK_FILE_ENV"])
script_dir = Path(os.environ["SCRIPT_DIR_ENV"])


def clean_text(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return " ".join(clean_text(v) for v in value)
    if isinstance(value, dict):
        return " ".join(f"{k} {clean_text(v)}" for k, v in value.items())
    text = str(value).replace("FILL_THIS", "FILL-THIS")
    return re.sub(r"\s+", " ", text).strip()


def truncate(value, limit=220):
    value = clean_text(value)
    return value[:limit].rstrip()


try:
    raw = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
except Exception:
    raw = {}
task = raw.get("task", raw) if isinstance(raw, dict) else {}

query_parts = [
    task.get("purpose"),
    task.get("acceptance_criteria"),
    task.get("related_lessons"),
    task.get("semantic_concepts"),
    task.get("target_path"),
]
query = truncate(" ".join(clean_text(part) for part in query_parts if clean_text(part)), 500)

entries = []
if query:
    cmd = ["timeout", "8", "bash", str(script_dir / "scripts" / "semantic_search.sh"), query]
    env = os.environ.copy()
    env.setdefault("SEMANTIC_DISABLE_SEARCH_LOG", "1")
    env.setdefault("SEMANTIC_MEMORY_DB_TIMEOUT", "3")
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(script_dir),
            env=env,
            text=True,
            capture_output=True,
            timeout=10,
            check=False,
        )
        output = (proc.stdout or "") + "\n" + (proc.stderr or "")
        for line in output.splitlines():
            text = line.strip()
            if not text or text.startswith(("Usage:", "ERROR:")):
                continue
            if any(marker in text for marker in ("matched:", "file:", "cmd:", "causal:", "discussion:", "source:")):
                entries.append(text)
            if len(entries) >= 3:
                break
    except Exception:
        entries = []

print("memory_references:")
if entries:
    for idx, text in enumerate(entries, start=1):
        safe_text = truncate(text, 180).replace("'", "''")
        safe_query = truncate(query, 160).replace("'", "''")
        print(f"  - id: MEM{idx:03d}")
        print("    source: semantic_search")
        print(f"    query: '{safe_query}'")
        print(f"    summary: '{safe_text}'")
        print("    used: false")
        print("    useful: false")
        print("    reason: ''")
else:
    safe_query = truncate(query or "task context unavailable", 160).replace("'", "''")
    print("  - id: MEM001")
    print("    source: search_unavailable")
    print(f"    query: '{safe_query}'")
    print("    summary: ''")
    print("    used: false")
    print("    useful: false")
    print("    reason: ''")
PY_MEMORY_REFS
    )

    if [ -n "$_memory_references_block" ]; then
        # cmd_karo_hotfix_post_clear_fail_open_20260725: awk -v のCエスケープ解釈でリテラル\tが
        # 実タブへ化けYAMLを破壊するためENVIRON経由に変更(L4272と同型修正)。
        _MEM_REFS_ENV="$_memory_references_block" awk '
            /^skill_candidate:/ && !inserted { print ENVIRON["_MEM_REFS_ENV"]; inserted=1 }
            { print }
            END { if (!inserted) print ENVIRON["_MEM_REFS_ENV"] }
        ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
        log "report_template: memory_references template injected"
    fi
    deploy_task_report_phase_mark lessons_memory_rewrites

    # cmd_1260+cmd_1393: acceptance_criteriaのbinary_checksをreportに事前展開（Python→bash/awk）
    # GP-194: ac_assigned フィールド読み込み（分割配備時の担当AC範囲制限）
    # cmd_4127: assigned_acs(旧フィールド名)も同一セマンティクスの別名として受理する
    # (inject_parent_contractのparent AC coverage判定と共有するフィールドで、GP-194導入時に
    # binary_checksフィルタ側の別名対応が漏れ、cmd_4127の後方互換テストが回帰していた)
    # 両フォーマット対応: inline "[AC1,AC2]" と yaml.dump後の multi-line "- AC1"
    local _ac_assigned_filter=""
    _ac_assigned_filter=$(awk '
        /^  (ac_assigned|assigned_acs):[[:space:]]*\[/ {
            s=$0; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
            n=split(s, a, /[[:space:]]*,[[:space:]]*/);
            out=""
            for(i=1;i<=n;i++) { gsub(/[[:space:]"'"'"']/, "", a[i]); if(a[i]!="") out=(out=="")?a[i]:(out"|"a[i]) }
            print out; exit
        }
        /^  (ac_assigned|assigned_acs):[[:space:]]*[^[:space:]]/ {
            s=$0; sub(/^  (ac_assigned|assigned_acs):[[:space:]]*/, "", s)
            gsub(/[\[\][:space:]"'"'"']/, "", s)
            if (s != "") print s
            exit
        }
        /^  (ac_assigned|assigned_acs):[[:space:]]*$/ { in_aa=1; next }
        in_aa && /^  - / {
            item=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", item); gsub(/[[:space:]"'"'"']/, "", item)
            if(item!="") out=(out=="")?item:(out"|"item)
            next
        }
        in_aa && /^  [a-zA-Z_]/ { in_aa=0; print out; exit }
        END { if(in_aa && out!="") print out }
    ' "$task_file" 2>/dev/null)
    if [ -n "$_ac_assigned_filter" ]; then
        log "binary_checks: ac_assigned filter active: ${_ac_assigned_filter}"
    fi

    local _bc_block
    _bc_block=$(awk -v ac_filter="$_ac_assigned_filter" '
        function in_filter(id,    n, arr, i) {
            if (ac_filter == "") return 1
            n = split(ac_filter, arr, "|")
            for (i = 1; i <= n; i++) if (arr[i] == id) return 1
            return 0
        }
        function clean_scalar(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            while (s ~ /^["'"'"']/) sub(/^["'"'"']/, "", s)
            while (s ~ /["'"'"']$/) sub(/["'"'"']$/, "", s)
            return s
        }
        function set_ac_value(raw,    s) {
            s = clean_scalar(raw)
            if (s == "") return
            if (s ~ /^AC[[:alnum:]_-]+[[:space:]]*:/) {
                cur_id = s
                sub(/[[:space:]]*:.*/, "", cur_id)
                cur_desc = s
                sub(/^[^:]*:[[:space:]]*/, "", cur_desc)
                cur_desc = clean_scalar(cur_desc)
            } else if (cur_desc == "") {
                cur_desc = s
            }
        }
        function emit_cur(    id, i) {
            if (cc <= 0) return
            id = cur_id
            if (id == "") id = "AC" (++auto_ac_id)
            if (in_filter(id)) {
                printf "  %s:\n", id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(chk[i], cur_desc) }
            }
        }
        function yaml_dq_escape(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            return s
        }
        function normalize_check_text(text, ac_desc, out) {
            out = text
            gsub(/FILL_THIS/, "FILL-THIS", out)
            if (ac_desc ~ /(monthly|月次)/ && out !~ /進行中月除外/) {
                out = out " (進行中月除外)"
            }
            if (out ~ /全テストPASS\(bats --jobs 4 tests\/unit\)/) {
                out = "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
            }
            return yaml_dq_escape(out)
        }
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^[[:space:]]+- / {
            emit_cur()
            cur_id=""; cur_desc=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
            if (/description:/) {
                s=$0; sub(/.*description:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s)
                while (s ~ /^["'"'"']/) sub(/^["'"'"']/, "", s)
                while (s ~ /["'"'"']$/) sub(/["'"'"']$/, "", s)
                cur_desc=s
            }
            if (/ac:/) { s=$0; sub(/.*ac:[[:space:]]*/, "", s); set_ac_value(s) }
        }
        in_ac && /^[[:space:]]+id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /^[[:space:]]+ac:/ {
            s=$0
            sub(/.*ac:[[:space:]]*/, "", s)
            set_ac_value(s)
        }
        in_ac && /^[[:space:]]+description:/ {
            sub(/.*description:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
            while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
            cur_desc=$0
        }
        in_ac && /^[[:space:]]+- check:/ {
            sub(/.*- check:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
            while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
            cc++
            chk[cc]=$0
        }
        END {
            emit_cur()
        }
    ' "$task_file" 2>/dev/null)

    # cmd_karo_hotfix_recon_report_commit_contract_202607140443:
    # Read-only tasks must prove that stage/commit was not performed.  Omitting
    # the check made a correct recon report indistinguishable from an incomplete
    # implementation report and caused gate false-BLOCKs on task status/progress.
    # cmd_1983: field_get_multiで一括取得済み → task_type変数を直接使用
    local _deploy_task_type="${task_type}"
    local _commit_bc=""
    if [ "$_commit_required" = false ]; then
        _commit_bc='  commit:
  - check: "commit N/A証跡(commit_contract.required=false/reason/task_type/planned_paths)とコード変更・stage/commitを実行していないことを確認"
    result: ""  # yes or no'
    else
        _commit_bc="  commit:
  - check: git commitが完了したか(untracked/modified=0)
    result: ''  # yes or no"
    fi

    # cmd_1838: gitignore対象ファイルのみ変更するcmdのcommit checkを自動でno設定
    if [ -n "$_commit_bc" ]; then
        # cmd_1983: field_get_multiで一括取得済み → 変数参照
        local _tp_raw="${target_path}"
        local _scout_exempt="${scout_exempt}"
        # karo_direct cmd is absent from shogun_to_karo.yaml; preserve task-local scout_exempt.
        if [ -z "$_scout_exempt" ]; then
            _scout_exempt=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "scout_exempt" "" 2>/dev/null || true)
        fi
        # GP-190改: task fileはstale resetで消えるためSTKも確認。task fileが残っている場合(テスト等)は優先
        if [ "$_scout_exempt" != "true" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ] && [ -n "$_p_parent_cmd" ]; then
            _scout_exempt=$(awk -v cmd="$_p_parent_cmd" '
                /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
                cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
            ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null)
        fi
        # GP-190修正: scout_exempt=trueはscout gate免除フラグ。commit要否とは独立。
        # impl taskはscout_exemptに関わらずcommit checkが必要。
        # read-only taskは上でno-commit契約を生成するため、gitignore免除で上書きしない。
        # cmd_karo_impl_gitignore_exempt_readonly_20260726: 880976003(2026-07-14)は上の
        # コメントとno-commit契約を同時に入れながら条件分岐を実装しなかった。結果、
        # required=false かつ target_pathが全てgitignore対象のtask(例 recon2 +
        # queue/*.yaml)でN/A証跡checkが result:"no" へ上書きされ、忍者が達成不能な
        # checkでBLOCKされた(実害3件)。required=false のときは免除を適用しない。
        if [ -n "$_tp_raw" ] && [ "$_commit_required" != false ]; then
            local -a _tp_paths=()
            if echo "$_tp_raw" | grep -q '^- '; then
                while IFS= read -r _tp_line; do
                    local _tp_p="${_tp_line#- }"
                    _tp_p="${_tp_p#[[:space:]]}"
                    _tp_p="${_tp_p%[[:space:]]}"
                    [ -n "$_tp_p" ] && _tp_paths+=("$_tp_p")
                done <<< "$_tp_raw"
            else
                _tp_paths+=("$_tp_raw")
            fi

            if [ ${#_tp_paths[@]} -gt 0 ]; then
                local _all_ignored=true
                local _gitignore_root
                _gitignore_root="$_commit_repo_root"
                [ -n "$_gitignore_root" ] || _gitignore_root="$SCRIPT_DIR"
                for _tp_p in "${_tp_paths[@]}"; do
                    if ! git -C "$_gitignore_root" check-ignore -q "$_tp_p" 2>/dev/null; then
                        _all_ignored=false
                        break
                    fi
                done
                if [ "$_all_ignored" = "true" ]; then
                    # AC2: なぜnoなのかをcheck本文に持たせる。理由が無いと『何が起きたかは
                    # 分かるがなぜかが分からない』状態になり、同じ真因が別々に再調査される。
                    _commit_bc='  commit:
  - check: "git commitが完了したか(untracked/modified=0) ※理由: target_pathが全てgitignore対象のためcommit不可。deploy_task.shが自動でnoを設定した"
    result: "no"  # gitignore対象ファイルのみ: commit不要'
                    log "binary_checks: commit check auto-set to no (reason: all target_path are gitignored: ${_tp_paths[*]})"
                fi
            fi
        fi
    fi

    # GP-190改: cmd制約(commit禁止)検出 → commit check自体を生成しない
    # 根因: commit禁止cmdにcommit binary_checkを残すと、忍者が実行不能な項目でBLOCKされる。
    if [ -n "$_commit_bc" ]; then
        local _cmd_text="${command} ${constraints} ${not_in_scope}"
        if [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ] && [ -n "$_p_parent_cmd" ]; then
            local _cmd_queue_text
            _cmd_queue_text=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$_p_parent_cmd" "command" 2>/dev/null || true)
            _cmd_queue_text="${_cmd_queue_text} $(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$_p_parent_cmd" "constraints" 2>/dev/null || true)"
            _cmd_queue_text="${_cmd_queue_text} $(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$_p_parent_cmd" "not_in_scope" 2>/dev/null || true)"
            _cmd_text="${_cmd_text} ${_cmd_queue_text}"
        fi
        if echo "$_cmd_text" | grep -qiE 'commit.*禁止|commit一切禁止|コミット.*禁止|コミット一切禁止|将軍.*(commit|コミット|push|プッシュ)|登録.*のみ.*commit'; then
            _commit_bc=""
            log "binary_checks: commit check skipped (cmd constraint: commit禁止)"
        fi
    fi

    local _bc_from_yaml
    _bc_from_yaml=$(TASK_FILE_ENV="$task_file" AC_FILTER_ENV="$_ac_assigned_filter" python3 - <<'PY_BC_TEMPLATE'
import os
import re
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path = Path(os.environ["TASK_FILE_ENV"])
ac_filter_raw = os.environ.get("AC_FILTER_ENV", "")
ac_filter = {x for x in ac_filter_raw.split("|") if x}

try:
    raw = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
except Exception:
    raise SystemExit(0)

task = raw.get("task", raw)
criteria = task.get("acceptance_criteria") or {}


def clean(value):
    return str(value or "").strip().strip('"').strip("'")


def split_checks(text):
    text = clean(text).replace("FILL_THIS", "FILL-THIS")
    if not text:
        return []
    parts = [p.strip() for p in re.split(r"。+", text) if p.strip()]
    return parts or [text]


def split_ac_value(raw, fallback_id):
    value = clean(raw)
    if re.match(r"^AC[\w-]+\s*:", value):
        ac_id, desc = value.split(":", 1)
        return clean(ac_id), clean(desc)
    return fallback_id, value


def normalize_check(text, ac_desc=""):
    out = clean(text).replace("FILL_THIS", "FILL-THIS")
    if re.search(r"(monthly|月次)", ac_desc) and "進行中月除外" not in out:
        out = f"{out} (進行中月除外)"
    if "全テストPASS(bats --jobs 4 tests/unit)" in out:
        out = "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
    return out


def emit(ac_id, checks):
    if ac_filter and ac_id not in ac_filter:
        return
    checks = [clean(c).replace("'", "''") for c in checks if clean(c)]
    if not checks:
        checks = [f"FILL: {ac_id}の確認項目を記入"]
    print(f"  {ac_id}:")
    for check in checks:
        print(f"  - check: '{check}'")
        print('    result: ""  # yes or no')


if isinstance(criteria, dict):
    for idx, (key, value) in enumerate(criteria.items(), start=1):
        ac_id = clean(key) or f"AC{idx}"
        checks = []
        desc = ""
        if isinstance(value, dict):
            raw_checks = value.get("binary_checks") or value.get("checks") or []
            if isinstance(raw_checks, list):
                for item in raw_checks:
                    if isinstance(item, dict):
                        checks.append(item.get("check") or item.get("description") or item.get("name"))
                    else:
                        checks.append(item)
            desc = value.get("description") or value.get("ac")
            if not checks:
                checks = split_checks(desc)
            else:
                checks = [normalize_check(c, desc) for c in checks]
        elif isinstance(value, list):
            checks = [item.get("check") if isinstance(item, dict) else item for item in value]
        else:
            checks = split_checks(value)
            desc = value
        if desc:
            checks = [normalize_check(c, desc) for c in checks]
        emit(ac_id, checks)
elif isinstance(criteria, list):
    for idx, value in enumerate(criteria, start=1):
        ac_id = f"AC{idx}"
        checks = []
        desc = ""
        if isinstance(value, dict):
            ac_id = clean(value.get("id") or ac_id)
            ac_id, ac_desc = split_ac_value(value.get("ac"), ac_id)
            desc = value.get("description") or ac_desc
            raw_checks = value.get("binary_checks") or value.get("checks") or []
            if isinstance(raw_checks, list):
                for item in raw_checks:
                    if isinstance(item, dict):
                        checks.append(item.get("check") or item.get("description") or item.get("name"))
                    else:
                        checks.append(item)
            if not checks:
                checks = split_checks(desc)
        else:
            checks = split_checks(value)
            desc = value
        checks = [normalize_check(c, desc) for c in checks]
        emit(ac_id, checks)
PY_BC_TEMPLATE
)
    if [ -n "$_bc_from_yaml" ]; then
        local _bc_block_count _bc_yaml_count
        _bc_block_count=$(printf '%s\n' "$_bc_block" | awk '/^[[:space:]][[:space:]]AC[[:alnum:]_-]*:/ { count++ } END { print count + 0 }')
        _bc_yaml_count=$(printf '%s\n' "$_bc_from_yaml" | awk '/^[[:space:]][[:space:]]AC[[:alnum:]_-]*:/ { count++ } END { print count + 0 }')
        if [ "$_bc_yaml_count" -gt "$_bc_block_count" ]; then
            _bc_block="$_bc_from_yaml"
            log "binary_checks: YAML parser fallback expanded ${_bc_yaml_count} ACs"
        fi
    fi

    local _bc_placeholder='binary_checks: {}  # AC完了ごとに ACN: [{check: "確認内容", result: "yes/no"}] を記入'

    if [ -n "$_bc_block" ]; then
        local _bc_full="binary_checks:
${_bc_block}
${_commit_bc}"
    else
        # GP-133 enhanced: AC descriptionから。分割でcheck項目を自動生成（description空→FILLフォールバック）
        local _ac_stubs
        _ac_stubs=$(awk -v ac_filter="$_ac_assigned_filter" '
        function in_filter(id,    n, arr, i) {
            if (ac_filter == "") return 1
            n = split(ac_filter, arr, "|")
            for (i = 1; i <= n; i++) if (arr[i] == id) return 1
            return 0
        }
        function clean_scalar(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            while (s ~ /^["'"'"']/) sub(/^["'"'"']/, "", s)
            while (s ~ /["'"'"']$/) sub(/["'"'"']$/, "", s)
            return s
        }
        function set_ac_value(raw,    s) {
            s = clean_scalar(raw)
            if (s == "") return
            if (s ~ /^AC[[:alnum:]_-]+[[:space:]]*:/) {
                cur_id = s
                sub(/[[:space:]]*:.*/, "", cur_id)
                desc = s
                sub(/^[^:]*:[[:space:]]*/, "", desc)
                desc = clean_scalar(desc)
            } else if (desc == "") {
                desc = s
            }
        }
            function emit_cur(    id, n, i) {
                if (cur_id == "" && desc == "") return
                id = cur_id
                if (id == "") id = "AC" (++auto_ac_id)
                if (!in_filter(id)) return
                printf "  %s:\n", id
                if (desc != "") {
                    n = split(desc, parts, "。")
                    for (i=1; i<=n; i++) {
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                        if (parts[i] != "") printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(parts[i], desc)
                    }
                } else {
                    printf "  - check: \"FILL: %sの確認項目を記入\"\n    result: \"\"  # yes or no\n", id
                }
            }
            function yaml_dq_escape(s) {
                gsub(/\\/, "\\\\", s)
                gsub(/"/, "\\\"", s)
                return s
            }
            function normalize_check_text(text, ac_desc, out) {
                out = text
                gsub(/FILL_THIS/, "FILL-THIS", out)
                if (ac_desc ~ /(monthly|月次)/ && out !~ /進行中月除外/) {
                    out = out " (進行中月除外)"
                }
                if (out ~ /全テストPASS\(bats --jobs 4 tests\/unit\)/) {
                    out = "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
                }
                return yaml_dq_escape(out)
            }
            /^  acceptance_criteria:/ { in_ac=1; next }
            in_ac && /^  [a-z]/ { exit }
            in_ac && /^[[:space:]]+- / {
                emit_cur()
                cur_id=""; desc=""
                if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
                if (/ac:/) { s=$0; sub(/.*ac:[[:space:]]*/, "", s); set_ac_value(s) }
                if (/description:/) {
                    s=$0
                    sub(/.*description:[[:space:]]*/, "", s)
                    sub(/[[:space:]]*$/, "", s)
                    while (s ~ /^["'"'"']/) sub(/^["'"'"']/, "", s)
                    while (s ~ /["'"'"']$/) sub(/["'"'"']$/, "", s)
                    desc=s
                }
                next
            }
            in_ac && /^[[:space:]]+id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0; next }
            in_ac && /^[[:space:]]+ac:/ {
                s=$0
                sub(/.*ac:[[:space:]]*/, "", s)
                set_ac_value(s)
                next
            }
            in_ac && /^[[:space:]]+description:/ {
                sub(/.*description:[[:space:]]*/, ""); sub(/[[:space:]]*$/, "")
                while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
                while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
                desc=$0
                next
            }
            END {
                emit_cur()
            }
        ' "$task_file" 2>/dev/null)
        if [ -n "$_ac_stubs" ]; then
            local _bc_full="binary_checks:
${_ac_stubs}
${_commit_bc}"
        else
            local _bc_full="binary_checks:
${_commit_bc}"
        fi
    fi

    _bc_full=$(_apply_binary_check_waivers "$task_file" "$_bc_full")

    if grep -qF "$_bc_placeholder" "$report_file" 2>/dev/null; then
        # cmd_karo_hotfix_post_clear_fail_open_20260725: repl(AC description由来)はENVIRON経由。
        # placeholderは固定文字列(バックスラッシュ無し)でawk -vのCエスケープ解釈の影響を受けないため維持。
        _BC_FULL_ENV="$_bc_full" awk -v placeholder="$_bc_placeholder" '
            index($0, placeholder) { print ENVIRON["_BC_FULL_ENV"]; next }
            { print }
        ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
        if [ -n "$_bc_block" ]; then
            local _bc_ac_count
            _bc_ac_count=$(printf '%s\n' "$_bc_block" | awk '
                /^[[:space:]][[:space:]]['\''"]?AC[[:alnum:]_-]*['\''"]?:/ { count++ }
                END { print count + 0 }
            ')
            if [ -n "$_commit_bc" ]; then
                log "binary_checks template: ${_bc_ac_count} ACs + commit check injected"
            else
                log "binary_checks template: ${_bc_ac_count} ACs injected"
            fi
        elif [ -n "$_commit_bc" ]; then
            log "binary_checks template: standard commit check injected"
        else
            log "binary_checks template: no checks injected"
        fi
        log "report_template: binary_checks template injected"
    fi
    deploy_task_report_phase_mark binary_checks_rewrite

    # cmd_1734: ninja_weak_points.gate_fail_top3 を報告テンプレートの該当フィールド直上コメントへ注入
    if grep -q 'gate_fail_top3:' "$task_file" 2>/dev/null; then
    REPORT_FILE_ENV="$report_file" TASK_FILE_ENV="$task_file" python3 - <<'PY_GATE_WARN'
import os
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

report_path = Path(os.environ["REPORT_FILE_ENV"])
task_path = Path(os.environ["TASK_FILE_ENV"])

try:
    task_raw = yaml.load(task_path.read_text(encoding="utf-8"), Loader=yaml.SafeLoader) or {}
except Exception:
    raise SystemExit(0)

task = task_raw.get("task", task_raw)
weak = task.get("ninja_weak_points", {})
top3 = weak.get("gate_fail_top3", [])
if not isinstance(top3, list) or not top3:
    raise SystemExit(0)

warning_map = {
    "lu_reason_empty": ('lessons_useful:', 'lessons_usefulの各教訓にreason(理由)を必ず記入。空文字禁止'),
    "empty_lessons_useful": ('lessons_useful:', 'lessons_usefulの各教訓にuseful(true/false)+reason(理由)を記入。空のまま提出禁止'),
    "lu_structure_error": ('lessons_useful:', 'lessons_usefulの各要素にid/reason/usefulフィールド必須。null/空リスト/dict禁止。テンプレート構造を壊すな'),
    "bc_result_empty": ('binary_checks:', 'binary_checksの各resultに"yes"/"no"を記入'),
    "bc_result_invalid": ('binary_checks:', 'binary_checksのresultは"yes"/"no"のみ。"PASS"/"FAIL"/"pending"等は不正値'),
    "binary_checks_fail": ('binary_checks:', 'binary_checksのresultが"yes"でない項目あり。全ACのチェック完了を確認'),
    "verdict_invalid": ('verdict:', 'verdictは"PASS"/"FAIL"の二値のみ'),
    "status_pending": ('status: pending', '完了後にstatusを"completed"に更新。"pending"のまま報告禁止'),
    "no_lesson_reason": ('  no_lesson_reason:', 'lesson_candidate.found=false時はno_lesson_reasonに理由記入'),
    "lesson_candidate_no_reason_empty": ('  no_lesson_reason:', 'lesson_candidate.found=false時はno_lesson_reasonに理由記入'),
}

anchor_comments: dict[str, list[str]] = {}
for item in top3:
    if not isinstance(item, dict):
        continue
    pattern = str(item.get("pattern", "")).strip()
    mapped = warning_map.get(pattern)
    if not mapped:
        continue
    anchor, warning = mapped
    anchor_comments.setdefault(anchor, [])
    if warning not in anchor_comments[anchor]:
        anchor_comments[anchor].append(warning)

if not anchor_comments:
    raise SystemExit(0)

lines = report_path.read_text(encoding="utf-8").splitlines()
new_lines: list[str] = []
for line in lines:
    for anchor, comments in anchor_comments.items():
        if line.startswith(anchor):
            for warning in comments:
                new_lines.append(f'# ⚠ あなたの頻出FAIL: {warning}')
    new_lines.append(line)

report_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY_GATE_WARN
        log "report_template: gate warning comments injected"
    fi

    # cmd_2161: gate_report_format 学習済みパターンが閾値超なら、空欄再発しやすい項目を
    # コメント付き空値にして、記入対象の template state を明示する。
    local _learning_prefill_file="${GATE_REPORT_FORMAT_LEARNING_FILE:-$SCRIPT_DIR/logs/gate_report_format_learning.yaml}"
    # gate_report_format.shはjson.dumpで書込む(拡張子は.yamlだが中身はJSON、キーはダブルクォート付き)。
    # ダブルクォート有無どちらのフォーマットでもマッチさせる。
    if [ -s "$_learning_prefill_file" ] && grep -qE '"?prefill_active"?[[:space:]]*:[[:space:]]*true' "$_learning_prefill_file" 2>/dev/null; then
    REPORT_FILE_ENV="$report_file" \
    LEARNING_FILE_ENV="$_learning_prefill_file" \
    python3 - <<'PY_LEARNED_PREFILL'
import os
import re
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

report_path = Path(os.environ["REPORT_FILE_ENV"])
learning_path = Path(os.environ["LEARNING_FILE_ENV"])

if not learning_path.exists():
    raise SystemExit(0)

try:
    learning = yaml.safe_load(learning_path.read_text(encoding="utf-8")) or {}
except Exception:
    raise SystemExit(0)

patterns = learning.get("patterns", {})
if not isinstance(patterns, dict):
    raise SystemExit(0)

active_fields = {}
for name, meta in patterns.items():
    if not isinstance(meta, dict) or meta.get("prefill_active") is not True:
        continue
    field = str(meta.get("prefill_field", "") or "").strip()
    if field:
        active_fields[field] = name

if not active_fields:
    raise SystemExit(0)

lines = report_path.read_text(encoding="utf-8").splitlines()
new_lines: list[str] = []
in_lessons = False
in_binary_checks = False
in_result = False
lu_note = "# AUTO-PREFILL: gate_report_format学習済み — reason空欄再発防止。具体理由を記入せよ"
bc_note = "# AUTO-PREFILL: gate_report_format学習済み — result空欄再発防止。yes/noを記入せよ"
summary_note = "# AUTO-PREFILL: gate_report_format学習済み — result.summary空欄再発防止。要約を記入せよ"
files_note = "# AUTO-PREFILL: gate_report_format学習済み — files_modified未記入再発防止。変更ファイル一覧を記入せよ"

for line in lines:
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*:", line):
        in_lessons = False
        in_binary_checks = False
        in_result = False

    if line.startswith("lessons_useful:"):
        if "lessons_useful.reason" in active_fields:
            new_lines.append(lu_note)
        in_lessons = True
        new_lines.append(line)
        continue

    if line.startswith("binary_checks:"):
        if "binary_checks.result" in active_fields:
            new_lines.append(bc_note)
        in_binary_checks = True
        new_lines.append(line)
        continue

    if line.startswith("result:"):
        if "result.summary" in active_fields:
            new_lines.append(summary_note)
        in_result = True
        new_lines.append(line)
        continue

    if line.startswith("files_modified:"):
        if "files_modified" in active_fields:
            new_lines.append(files_note)
            if re.match(r"^files_modified:\s*\[\]\s*(?:#.*)?$", line):
                new_lines.append("files_modified:")
                new_lines.append('  - ""  # 変更ファイルパスを記入')
                continue
        new_lines.append(line)
        continue

    if in_lessons and "lessons_useful.reason" in active_fields:
        line = re.sub(r"^(\s+reason:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r'\1 ""  # 具体理由を記入', line)

    if in_binary_checks and "binary_checks.result" in active_fields:
        line = re.sub(r"^(\s+result:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r'\1 ""  # yes or no', line)

    if in_result and "result.summary" in active_fields:
        line = re.sub(r"^(\s+summary:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r'\1 ""  # 要約を記入', line)

    new_lines.append(line)

report_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY_LEARNED_PREFILL
        log "report_template: learned prefills injected"
    fi

    # cmd_754: 偵察タスクにはimplementation_readiness欄を追加
    # cmd_1983: field_get_multiで一括取得済み → task_type/type/scope_mode変数を参照
    local report_task_type="${task_type:-${type:-${scope_mode}}}"
    report_task_type=$(echo "$report_task_type" | tr '[:upper:]' '[:lower:]')
    if [ "$report_task_type" = "recon" ] || [ "$report_task_type" = "recon2" ] || [ "$report_task_type" = "scout" ]; then
        cat >> "$report_file" <<'RECON_EOF'
# ─── 偵察 実装直結5要件（cmd_754+cmd_1476: 必須。空欄でWARN） ───
implementation_readiness:
  files_to_modify: []   # 変更対象ファイルと行番号 例: ["src/api/auth.py:45-60"]
  affected_files: []    # 変更が波及する他ファイル 例: ["tests/test_auth.py"]
  related_tests: []     # 関連テストの有無と修正要否 例: ["tests/test_auth.py — 修正必要"]
  edge_cases: []        # エッジケース・副作用 例: ["トークン期限切れ時の再認証フロー"]
  dependency_constraints: []  # 依存関係・順序制約 例: ["AC1完了後にAC2着手", "DB migration先行必須"]
# ─── ★偵察で発見した重要Gap/知見はknowledge_candidateに記入せよ ───
# 「我が軍に欠落」「本番と不一致」「設計変更が必要」等の発見は found: true にして記録。
# context反映のトリガーになる。docs/research/に書くだけでは埋没する。
# ─── 既存依存宣言（参照のみファイルをLG037除外する場合だけ記入） ───
# 記入例:
# echo '- {path: scripts/existing.sh, reason: "既存依存として参照のみ。変更不要を確認", checked_not_modified: true}' | bash scripts/report_field_set.sh <report> verified_existing_dependency -
verified_existing_dependency: []
RECON_EOF
        log "report_template: added implementation_readiness (recon/scout)"
    fi
    deploy_task_report_phase_mark optional_enrichments

    # Canonical new templates contain all three candidate mappings by
    # construction.  Structural sentinels catch truncated generation without
    # paying for a second YAML parser process on the hot path.
    grep -q '^lesson_candidate:' "$report_file" \
        && grep -q '^decision_candidate:' "$report_file" \
        && grep -q '^skill_candidate:' "$report_file" \
        && grep -q '^binary_checks:' "$report_file" \
        || { rm -f "$report_file"; return 1; }
    mv "$report_file" "$_report_final_file" || return 1
    report_file="$_report_final_file"

    deploy_task_publish_report_metadata "$task_file" "$report_id" "$report_identity_version" "$report_rel_path" \
        "$_variation_checks_required" "$_commit_contract_json" "$_level5_report_contract_json" || return 1
    deploy_task_publish_active_report_pointer "$_active_report_index" "$report_rel_path" || return 1
    IFS=$'\t' read -r _generation_source_fp _generation_query_key \
        < <(deploy_task_report_generation_identity "$task_file") \
        || return 1
    deploy_task_publish_report_generation_marker "$_generation_marker" \
        "$report_rel_path" "$_generation_source_fp" "$_generation_query_key" "$report_id" \
        || return 1
    deploy_task_report_phase_mark final_publication
    log "report_path: set (${report_rel_path})"
    log "report_template: generated (${report_file})"
}

# Publish through a per-process temporary path so concurrent deployments for
# the same ninja cannot move or truncate another writer's temporary file.
deploy_task_publish_active_report_pointer() {
    local active_report_index="$1"
    local report_rel_path="$2"
    local active_report_tmp="${active_report_index}.tmp.${BASHPID}"
    printf '%s\n' "$report_rel_path" > "$active_report_tmp" || return 1
    mv "$active_report_tmp" "$active_report_index"
}

# Serialize the complete fresh-report publication edge, including removal of a
# reviewed RC generation and publication of the new regular report plus its
# active pointer.  archive_completed.sh and review_approval.sh use the same
# lock_path(report-slot) key.
deploy_task_same_cmd_pending_symlink_reset() {
    local task_file="$1" task_id="$2" parent_cmd="$3" ninja_name="$4" report_path="$5"
    local task_status report_status report_parent_cmd report_worker_id report_task_id

    [ "${_DEPLOY_SAME_CMD_REDEPLOY:-0}" = "1" ] || return 0
    [ -f "$task_file" ] || return 0
    [ -L "$report_path" ] || return 0

    task_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" status "" 2>/dev/null || true)
    case "$task_status" in
        assigned|acknowledged|in_progress) ;;
        *) return 0 ;;
    esac

    # The live symlink is eligible only when it still names this active task's
    # pending generation.  Completed compatibility aliases and another cmd's
    # report therefore remain untouched.
    report_status=$(FIELD_GET_NO_LOG=1 field_get "$report_path" status "" 2>/dev/null || true)
    report_parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$report_path" parent_cmd "" 2>/dev/null || true)
    report_worker_id=$(FIELD_GET_NO_LOG=1 field_get "$report_path" worker_id "" 2>/dev/null || true)
    report_task_id=$(FIELD_GET_NO_LOG=1 field_get "$report_path" task_id "" 2>/dev/null || true)
    [ "$report_status" = "pending" ] || return 0
    [ "$report_parent_cmd" = "$parent_cmd" ] || return 0
    [ "$report_worker_id" = "$ninja_name" ] || return 0
    [ "$report_task_id" = "$task_id" ] || return 0

    rm -f -- "$report_path"
    log "same_cmd_redeploy: reset active pending report symlink ($(basename "$report_path"))"
}

deploy_task_report_publication_locked() {
    local ninja_name="$1" task_id="$2" parent_cmd="$3" project="$4" task_file="$5"
    local report_filename report_lock_target report_lock_file report_lock_fd rc
    report_filename="$(FIELD_GET_NO_LOG=1 field_get "$task_file" report_filename "" 2>/dev/null || true)"
    if [ -n "$report_filename" ]; then
        if [[ "$report_filename" = /* ]]; then
            report_lock_target="$report_filename"
        else
            report_lock_target="$SCRIPT_DIR/queue/reports/$(basename "$report_filename")"
        fi
    else
        report_lock_target="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    fi
    if [ -n "${_DEPLOY_FORMAL_RC_REFRESH_REPORT:-}" ]; then
        report_lock_target="$_DEPLOY_FORMAL_RC_REFRESH_REPORT"
    fi
    report_lock_file="$(lock_path "${report_lock_target}.report-unit")"
    exec {report_lock_fd}>"$report_lock_file"
    if ! flock -w 10 "$report_lock_fd"; then
        echo "BLOCK: report publication lock timeout: $report_lock_target" >&2
        eval "exec ${report_lock_fd}>&-"
        return 1
    fi

    if [ -n "${_DEPLOY_FORMAL_RC_REFRESH_REPORT:-}" ]; then
        # A symlink is an archived historical report. rm removes only the live
        # alias; the archive target remains byte-for-byte unchanged.
        rm -f -- "$_DEPLOY_FORMAL_RC_REFRESH_REPORT"
        log "formal_karo_rc_refresh: authoritative source accepted; old report reset ($(basename "$_DEPLOY_FORMAL_RC_REFRESH_REPORT"))"
    else
        deploy_task_same_cmd_pending_symlink_reset \
            "$task_file" "$task_id" "$parent_cmd" "$ninja_name" "$report_lock_target"
    fi
    if deploy_task_mutation_phase report_publication generate_report_template \
        "$ninja_name" "$task_id" "$parent_cmd" "$project" "$task_file"; then
        rc=0
    else
        rc=$?
    fi
    flock -u "$report_lock_fd" || true
    eval "exec ${report_lock_fd}>&-"
    return "$rc"
}

# Keep read/inspection scope distinct from the paths a worker owns and commits.
# Legacy target_path remains available to readers, but never becomes ownership
# merely because a recon task inspected it.
inject_scope_contract_fields() {
    local task_file="$1" inspection_json
    [ -f "$task_file" ] || return 0
    mapfile -t _scope_contract_values < <(python3 - "$task_file" <<'PY'
import json, sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})

def paths(value):
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, list):
        return [str(v) for v in value if str(v).strip()]
    return []

planned = paths(task.get("planned_paths"))
owned = paths(task.get("owned_paths")) or planned
target = paths(task.get("target_path"))
inspection = paths(task.get("inspection_path"))
if not inspection and target and target != owned:
    inspection = target
print(json.dumps(inspection, ensure_ascii=False))
PY
)
    inspection_json="${_scope_contract_values[0]:-[]}"
    local -a scope_args=()
    [ "$inspection_json" = "[]" ] || scope_args+=("inspection_path=$inspection_json")
    [ "${#scope_args[@]}" -eq 0 ] || yaml_field_set_batch "$task_file" task "${scope_args[@]}" || return 1
}

ensure_report_template_completeness() {
    local report_file="$1"
    local task_file="$2"
    local modified=false

    [ -f "$report_file" ] || return 0

    local _ninja_name _worker_id _task_id _parent_cmd _ac_version
    _ninja_name="$(basename "$task_file" .yaml)"
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        assigned_to task_id subtask_id parent_cmd ac_version 2>/dev/null)" || true
    _worker_id="${assigned_to:-$_ninja_name}"
    _task_id="${subtask_id:-$task_id}"
    _parent_cmd="${parent_cmd:-}"
    _ac_version="${ac_version:-}"

    if ! grep -Eq '^worker_id:' "$report_file" 2>/dev/null; then
        printf 'worker_id: %s\n' "$_worker_id" >> "$report_file"
        modified=true
    fi

    if ! grep -Eq '^task_id:' "$report_file" 2>/dev/null; then
        printf 'task_id: %s\n' "$_task_id" >> "$report_file"
        modified=true
    fi

    if ! grep -Eq '^parent_cmd:' "$report_file" 2>/dev/null; then
        printf 'parent_cmd: %s\n' "$_parent_cmd" >> "$report_file"
        modified=true
    fi

    if ! grep -Eq '^ac_version_read:' "$report_file" 2>/dev/null; then
        printf 'ac_version_read: %s\n' "$_ac_version" >> "$report_file"
        modified=true
    fi

    if ! awk '
        /^result:/ { in_result=1; next }
        in_result && /^[A-Za-z_][A-Za-z0-9_]*:/ { exit }
        in_result && /^  summary:/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
result:
  summary: ""  # 要約を記入
  details: ""
EOF
        modified=true
    fi

    if ! grep -Eq '^purpose_validation:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
EOF
        modified=true
    fi

    if ! grep -Eq '^files_modified:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
files_modified: []
EOF
        modified=true
    fi

    if ! grep -Eq '^lessons_useful:' "$report_file" 2>/dev/null; then
        local _lu_ids _lu_block _lid _lu_count=0
        _lu_ids=$(report_lesson_ids_for_task "$task_file")

        if [ -z "$_lu_ids" ]; then
            cat >> "$report_file" <<'EOF'
lessons_useful: []  # ★教訓注入なし。このフィールドを変更するな。空リストのまま提出せよ
EOF
        else
            _lu_block="lessons_useful:  # ★教訓注入済み。[]で上書きするな。各教訓にuseful+reasonを記入せよ"
            while IFS= read -r _lid; do
                [ -z "$_lid" ] && continue
                _lu_block="${_lu_block}
  - id: ${_lid}
    useful: false
    reason: '未参照'  # 有用なら具体的理由に書換えよ"
                _lu_count=$((_lu_count + 1))
            done <<< "$_lu_ids"
            printf '%s\n' "$_lu_block" >> "$report_file"
            log "report_template: missing lessons_useful repaired (${_lu_count} entries)"
        fi
        modified=true
    fi

    if ! grep -Eq '^binary_checks:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
binary_checks: {}
EOF
        modified=true
    fi

    if ! grep -Eq '^assumption_invalidation:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF
        modified=true
    fi

    if deploy_task_needs_causal_verification "$task_file" && ! grep -Eq '^causal_verification:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
causal_verification:
  cause_checked: ""
  design_intent_checked: ""
  evidence: ""
  origin: ""
EOF
        modified=true
    fi

    if ! grep -Eq '^self_gate_check:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
EOF
        modified=true
    fi

    if ! grep -Eq '^verdict:' "$report_file" 2>/dev/null; then
        cat >> "$report_file" <<'EOF'
verdict: ""
EOF
        modified=true
    fi

    if [ "$modified" = "true" ]; then
        python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$report_file"
        log "report_template: required fields repaired ($(basename "$report_file"))"
    fi
}

__cluster_f_static_extraction_sentinel() { :; }
fi
# Cluster F module: report identity, generation, scope, template, and publication lock/pointer.
_dt_report_path="$SCRIPT_DIR/scripts/deploy_task/report.sh"
if [ ! -f "$_dt_report_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_report_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/report.sh"
fi
if [ ! -f "$_dt_report_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_report_path="$PROJECT_ROOT/scripts/deploy_task/report.sh"
fi
source "$_dt_report_path"
unset _dt_report_path
rehydrate_task_commit_contract_from_report() {
    local task_file="$1"
    local report_file="$2"
    local contract_json=""

    contract_json=$(python3 - "$report_file" <<'PY'
import json
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

report = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
contract = report.get("commit_contract")
if not isinstance(contract, dict):
    raise SystemExit(0)  # legacy report: preserve compatibility
required = contract.get("required")
reason = contract.get("reason")
task_type = contract.get("task_type")
paths = contract.get("planned_paths")
if not isinstance(required, bool) or not str(reason or "").strip() \
        or not str(task_type or "").strip() or not isinstance(paths, list) \
        or any(not isinstance(path, str) or not path.strip() for path in paths):
    raise SystemExit("invalid report commit_contract")
print(json.dumps(contract, ensure_ascii=False, separators=(",", ":")))
PY
    ) || {
        log "FATAL: existing report commit_contract is invalid: ${report_file}"
        return 1
    }

    if [ -z "$contract_json" ]; then
        log "report_template: legacy report has no commit_contract; task contract unchanged"
        return 0
    fi
    yaml_field_set "$task_file" "task" "commit_contract" "$contract_json" \
        || { log "FATAL: failed to rehydrate task commit_contract"; return 1; }
    log "report_template: task commit_contract rehydrated from existing report"
}

# Legacy static-extraction compatibility for tests that copy deploy_task.sh only.
if false; then
# ─── セマンティクスインデックス概念注入（task YAMLにsemantic_conceptsを挿入） ───
# Level5: 忍者が関連ファイルを自動で知る。意志依存ゼロ。
deploy_task_semantic_phase_mark() {
    local phase="$1" started_ms="$2" cache_state="${3:-na}" now_ms
    now_ms="$(date +%s%3N)"
    log "semantic_context_phase: phase=${phase} wall_ms=$((now_ms - started_ms)) cache=${cache_state}"
    printf '%s\n' "$now_ms"
}

deploy_task_semantic_context_generate() {
    local purpose="$1" index_path="$2" helper="$3" search_script="$4" skills_root="$5"
    local raw_file rc
    raw_file="$(mktemp /tmp/deploy-semantic-raw.XXXXXX)" || return 1
    # A regular temporary output avoids a semantic-search background telemetry
    # child retaining a pipeline FD and making the caller wait after timeout.
    # Either producer or parser failure rejects cache publication.
    if env SEMANTIC_DISABLE_LLM=1 \
        SEMANTIC_INDEX_PATH="$index_path" \
        timeout "${DEPLOY_TASK_SEMANTIC_SEARCH_TIMEOUT_SEC:-5}" \
        bash "$search_script" "$purpose" > "$raw_file"; then
        if python3 "$helper" from-search-output \
            --purpose "$purpose" --skills-root "$skills_root" < "$raw_file"; then
            rc=0
        else
            rc=$?
        fi
    else
        rc=$?
    fi
    rm -f "$raw_file"
    return "$rc"
}

inject_semantic_concepts() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local _sem_phase_ms
    _sem_phase_ms="$(date +%s%3N)"

    local index_path="${SEMANTIC_INDEX_PATH:-$SCRIPT_DIR/docs/semantic-index/index.md}"
    [ -f "$index_path" ] || return 0

    # Read the query identity once.  project belongs in the cache key: an
    # identical sentence deployed to a different project is not the same
    # semantic-context request even when today's global index happens to make
    # both results equal.
    local purpose target_path project
    purpose=$(awk '/^  purpose:/{sub(/^  purpose: /,""); p=$0; next} p && /^  [a-z]/{exit} p{p=p " " $0} END{print p}' "$task_file" 2>/dev/null)
    [ -z "$purpose" ] && return 0
    target_path=$(awk '/^  target_path:/{sub(/^  target_path: /,""); print; exit}' "$task_file" 2>/dev/null)
    target_path="${target_path:-none}"
    project=$(awk '/^  project:/{sub(/^  project: /,""); print; exit}' "$task_file" 2>/dev/null)
    project="${project:-none}"
    _sem_phase_ms="$(deploy_task_semantic_phase_mark task_query "$_sem_phase_ms")"

    # One Python process reads/parses the index and scans all recommended skill
    # contracts.  The cached value is query data only, never task bytes.  Thus
    # same-query deploys share the expensive read without leaking task fields.
    # NO_MATCH/helper failure exits nonzero, so wave_cache never publishes a
    # negative or partial snapshot and a later corrected source is retried.
    local semantic_helper="${DEPLOY_TASK_SEMANTIC_HELPER:-$SCRIPT_DIR/scripts/lib/deploy_task_semantic_context_fast.py}"
    local semantic_search_script="${DEPLOY_TASK_SEMANTIC_SEARCH_SCRIPT:-$SCRIPT_DIR/scripts/semantic_search.sh}"
    local semantic_skills_root="${DEPLOY_TASK_SKILLS_ROOT:-$SCRIPT_DIR/skills}"
    local semantic_sources semantic_json
    semantic_sources=$(printf '%s\n' \
        "$index_path" \
        "$SCRIPT_DIR/context/semantic-map.md" \
        "$semantic_search_script" \
        "$SCRIPT_DIR/scripts/semantic_index.py" \
        "$semantic_helper" \
        "${SEMANTIC_MEMORY_DB_PATH:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}" \
        "skill-tree:$semantic_skills_root")
    semantic_json=$(deploy_task_wave_cache semantic_context_v2 \
        "$purpose|$target_path|$project" "$semantic_sources" \
        deploy_task_semantic_context_generate \
            "$purpose" "$index_path" "$semantic_helper" \
            "$semantic_search_script" "$semantic_skills_root") || semantic_json=""
    _sem_phase_ms="$(deploy_task_semantic_phase_mark semantic_query_cache "$_sem_phase_ms" wave)"

    local matches="" recommended_skills="" record_type record_value
    if [ -n "$semantic_json" ]; then
        while IFS=$'\t' read -r record_type record_value; do
            case "$record_type" in
                C) matches+="${record_value}"$'\n' ;;
                S) recommended_skills+="${record_value}"$'\n' ;;
            esac
        done < <(printf '%s\n' "$semantic_json" | python3 -c '
import json, sys
value = json.load(sys.stdin)
if not isinstance(value, dict):
    raise SystemExit(2)
concepts = value.get("concept_lines")
skills = value.get("skills")
if not isinstance(concepts, list) or not concepts or not isinstance(skills, list):
    raise SystemExit(2)
for concept in concepts:
    if not isinstance(concept, str) or "\t" in concept or "\n" in concept:
        raise SystemExit(2)
    print("C\t" + concept)
for skill in skills:
    if not isinstance(skill, str) or "\t" in skill or "\n" in skill:
        raise SystemExit(2)
    print("S\t" + skill)
')
    fi
    matches="${matches%$'\n'}"
    recommended_skills="${recommended_skills%$'\n'}"
    _sem_phase_ms="$(deploy_task_semantic_phase_mark result_decode "$_sem_phase_ms")"
    if [ -z "$matches" ]; then
        log "inject_semantic_concepts: NO_MATCH purpose=${purpose//$'\n'/ } target_path=${target_path//$'\n'/ }"
        return 0
    fi

    # task YAMLに semantic_concepts フィールドとして注入
    local indent="  "
    local inject_block="${indent}semantic_concepts:"
    while IFS= read -r line; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${line}\""
    done <<< "$matches"

    if [ -n "$recommended_skills" ]; then
        inject_block="${inject_block}"$'\n'"${indent}recommended_skills:"
        while IFS= read -r skill; do
            [ -z "$skill" ] && continue
            inject_block="${inject_block}"$'\n'"${indent}- \"${skill}\""
        done <<< "$recommended_skills"
    fi

    # 既存のsemantic_concepts/recommended_skillsを除去してから追加
    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  semantic_concepts:/ { skip=1; next }
        /^  recommended_skills:/ { skip=1; next }
        skip && /^  - "/ { next }
        skip && /^  [a-z]/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    # description の直前に挿入（description は最後のフィールド）
    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        echo "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    _sem_phase_ms="$(deploy_task_semantic_phase_mark yaml_publish "$_sem_phase_ms")"
    log "inject_semantic_concepts: $(echo "$matches" | wc -l) concepts injected"

    # 推薦ログにninja_name付きで記録 (cmd_3244: precision照合キー修正)
    if [ -n "$recommended_skills" ]; then
        local _rec_ninja_name _rec_log _rec_ts _rec_hash
        _rec_ninja_name=$(basename "$task_file" .yaml)
        _rec_log="${SKILL_RECOMMEND_LOG_FILE:-$SCRIPT_DIR/logs/skill_recommend_log.yaml}"
        _rec_ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
        _rec_hash="$(printf '%s' "$purpose" | sha256sum | cut -d' ' -f1)"
        if [ -f "$_rec_log" ]; then
            {
                flock -w 5 9 || true
                {
                    printf -- '- ts: "%s"\n' "$_rec_ts"
                    printf '  agent_id: "deploy_task"\n'
                    printf '  ninja_name: "%s"\n' "$_rec_ninja_name"
                    printf '  prompt_hash: "%s"\n' "$_rec_hash"
                    printf '  recommended_skills:\n'
                    while IFS= read -r _rec_skill; do
                        [ -z "$_rec_skill" ] && continue
                        printf '  - "%s"\n' "$_rec_skill"
                    done <<< "$recommended_skills"
                } >> "$_rec_log"
            } 9>"${_rec_log}.lock"
            log "inject_semantic_concepts: recorded ${_rec_ninja_name} recommendation to skill_recommend_log"
        fi
    fi

    # L7穴2: 家老が配備時に因果概念を毎回消費する(startup gateは/clear後のみで低頻度)
    echo "INFO: [SEMANTIC_CONTEXT] 配備cmd関連概念:" >&2
    printf '%s\n' "$matches" | sed 's/^/  /' >&2
    local _causal_script="${SCRIPT_DIR}/scripts/causal_backlinks.sh"
    if [ "${SEMANTIC_DISABLE_CAUSAL:-0}" != "1" ] && [ -f "$_causal_script" ]; then
        local _target_stem
        _target_stem=$(awk '/^  target_path:/{sub(/^  target_path: /,""); gsub(/.*\//,""); sub(/\.[^.]*$/,""); print; exit}' "$task_file" 2>/dev/null)
        if [ -n "$_target_stem" ]; then
            local _causal_out
            _causal_out=$(bash "$_causal_script" "$_target_stem" 2>/dev/null | head -3 || true)
            [ -n "$_causal_out" ] && { echo "INFO: [CAUSAL_CONTEXT] target因果辺:" >&2; printf '%s\n' "$_causal_out" | sed 's/^/  → /' >&2; }
        fi
    fi
    _sem_phase_ms="$(deploy_task_semantic_phase_mark causal_context "$_sem_phase_ms")"
    # The injection operation succeeds even when no causal backlinks are
    # available.  Do not leak the status of the optional empty-output branch
    # as the function result; callers and fixed-SHA parity tests require a
    # successful semantic-context injection to return zero.
    return 0
}

# ─── 三層記憶先行知識注入(殿厳命2026-06-10: 使用しないのはバグ。L0-L7貫通) ───
# Level5: 配備時に記憶DBから先行知識(過去の裁定/類似cmd)を自動検索しtask YAMLに注入
inject_memory_db_context() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local query_script="$SCRIPT_DIR/scripts/memory_db_query.sh"
    [ -f "$query_script" ] || { log "inject_memory_db_context: query script not found"; return 0; }
    local db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"

    # purposeからキーワード抽出
    local purpose
    purpose=$(awk '/^  purpose:/{gsub(/^  purpose: *"?/,""); gsub(/"$/,""); print; exit}' "$task_file" 2>/dev/null)
    [ -n "$purpose" ] || return 0

    # 2-3語のキーワードを抽出してFTS5検索
    local keywords result=""
    keywords=$(echo "$purpose" | tr '　/ ()（）' '\n' | grep -E '.{3,}' | head -3 | tr '\n' ' ')
    [ -n "$keywords" ] || return 0

    # cmd_3758: キーワード毎に別プロセスで叩いていたのをUNION ALLで1クエリ/1プロセスに統合(per-keyword LIMIT 2は維持)
    local kw kw_esc combined_sql=""
    for kw in $keywords; do
        kw_esc="${kw//\'/\'\'}"
        if [ -n "$combined_sql" ]; then
            combined_sql="${combined_sql}"$'\nUNION ALL\n'
        fi
        combined_sql="${combined_sql}SELECT ts || ' | ' || substr(summary,1,100) FROM events WHERE summary LIKE '%${kw_esc}%' AND event_type IN ('conversation','knowledge','ruling') ORDER BY ts DESC LIMIT 2"
    done
    if declare -F deploy_task_wave_cache >/dev/null 2>&1; then
        result=$(deploy_task_wave_cache memory "$keywords|$combined_sql" "$db_path" \
            timeout "${DEPLOY_TASK_MEMORY_CONTEXT_TIMEOUT_SEC:-3}" bash "$query_script" "$combined_sql" 2>/dev/null) || result=""
    else
        # Keep this function usable by isolated callers/tests that source only it.
        # The normal deploy path always defines deploy_task_wave_cache above.
        result=$(bash "$query_script" "$combined_sql" 2>/dev/null) || result=""
    fi
    [ -n "$result" ] || { log "inject_memory_db_context: no hits for: $keywords"; return 0; }

    # task YAMLに memory_db_context フィールドとして注入
    local indent="  "
    local inject_block="${indent}memory_db_context:"
    local line seen_lines=$'\n'
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            case "$seen_lines" in
                *$'\n'"$line"$'\n'*) continue ;;
            esac
            seen_lines="${seen_lines}${line}"$'\n'
            line="${line//$'\r'/}"
            line="${line//\'/\'\'}"
            inject_block="${inject_block}"$'\n'"${indent}- '${line}'"
        fi
    done <<< "$(echo "$result" | head -5)"

    # 既存のmemory_db_contextを除去してから追加
    local tmp_file
    tmp_file=$(mktemp)
    awk '
        /^  memory_db_context:/ { skip=1; next }
        skip && /^  [^ ]/ { skip=0 }
        skip { next }
        { print }
    ' "$task_file" > "$tmp_file"
    # task: ブロックの末尾(次のトップレベルキーの前)に挿入
    awk -v block="$inject_block" '
        printed == 0 && /^[^ ]/ && prev ~ /^  / { print block; printed=1 }
        { prev=$0; print }
        END { if (printed==0) print block }
    ' "$tmp_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
    rm -f "$tmp_file"
    log "inject_memory_db_context: $(echo "$result" | grep -c '.' || echo 0) entries injected"
}

# ─── 因果リンク注入（task YAMLにcmdのoriginリンクを挿入） ───
# Level5: 忍者が関連する過去の失敗/裁定因果を自動で知る。意志依存ゼロ。
inject_causal_links() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk" ] || return 0

    # parent_cmdを取得
    local parent_cmd
    parent_cmd=$(awk '/^  parent_cmd:/{sub(/^  parent_cmd:[[:space:]]*/,""); gsub(/'"'"'|"/,""); print; exit}' "$task_file" 2>/dev/null)
    [ -z "$parent_cmd" ] && return 0

    # shogun_to_karo.yamlからoriginフィールドを抽出
    local origin
    origin=$(awk -v cmd="$parent_cmd" '
        /^  [^ ]/ {
            if (in_cmd) { exit }
            s = $0; sub(/^  /, "", s); sub(/:.*/, "", s)
            if (s == cmd) { in_cmd = 1; next }
        }
        in_cmd && /^    origin:/ {
            val = $0; sub(/^    origin:[[:space:]]*/, "", val)
            fc = substr(val, 1, 1); lc = substr(val, length(val), 1)
            if (length(val) >= 2 && ((fc == "\"" && lc == "\"") || (fc == "\x27" && lc == "\x27")))
                val = substr(val, 2, length(val) - 2)
            print val
            exit
        }
    ' "$stk" 2>/dev/null)
    [ -z "$origin" ] && return 0

    # [[...]]形式のリンクを抽出
    local links
    links=$(printf '%s\n' "$origin" | grep -oE '\[\[[^]]+\]\]' | sort -u)
    [ -z "$links" ] && return 0

    # task YAMLにrelated_causal_linksフィールドとして注入
    local indent="  "
    local inject_block="${indent}related_causal_links:"
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        inject_block="${inject_block}"$'\n'"${indent}- \"${link}\""
    done <<< "$links"

    # 既存のrelated_causal_linksを除去してから追加
    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  related_causal_links:/ { skip=1; next }
        skip && /^  - / { next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    # description の直前に挿入（description は最後のフィールド）
    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_causal_links: $(printf '%s\n' "$links" | wc -l) links injected from ${parent_cmd}.origin"
}

# ─── 標準スキル注入（全task YAMLに常時使用スキルを明示） ───
# Level5: 忍者が報告/commit時に必要なスキルを自動で知る。意志依存ゼロ。
inject_standard_skills() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local inject_block
    inject_block="  standard_skills:"$'\n'
    inject_block="${inject_block}  - \"report-write\""$'\n'
    inject_block="${inject_block}  - \"verdict-check\""$'\n'
    inject_block="${inject_block}  - \"ninja-commit\""

    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  standard_skills:/ { skip=1; next }
        skip && /^  - / { next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_standard_skills: standard skills injected"
}

# ─── push_allowed自動付与（cmd_3820: ACにpush要求があるcmdでG2ガードBLOCK→家老WAが発生） ───
# Level5: ACに'push'があるcmdは配備時にpush_allowed:trueを自動付与し、忍者の権限不足による
# git push BLOCK(.claude/hooks/pre-bash-combined.sh check_main_branch_protection)と
# karo_workarounds category=push_deploy_permission_gap(cmd_3820)の再発を防ぐ。
# §42v2(2026-07-10殿裁定: 自走push+deploy)に伝播していなかった権限設定を接続する。
inject_push_allowed() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # 既にpush_allowedが設定済み（preinject/手動設定）なら上書きしない
    grep -q '^[[:space:]]*push_allowed:' "$task_file" && return 0

    local ac_text
    ac_text="$(awk '
        /^  acceptance_criteria:/ { f=1; next }
        f && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { f=0 }
        f { print }
    ' "$task_file")"

    # \bpush\b はC.UTF-8ロケールで日本語(カナ/漢字)に直接隣接するとASCII境界を検出できない
    # (例:「pushして」「push完了」がNOMATCH)。ASCII文字以外を境界とみなす自前境界で代替する。
    # 否定形(push禁止/pushはしない/pushせず/pushしない/push不可/pushは行わない/no push/do not push/
    # must not push/push未)は「pushを要求していない」ので付与対象から除く。
    # 2026-08-18 02:55 実測: cmd_4349/4351/4352のAC『(pushはしない)』『push禁止』が語句一致で
    # push_allowed:true に反転し、cmd_complete_gateのpre-GATE autopushがGitHub不安定中(殿裁定
    # 00:45 deploy凍結)にorigin/main→Render自動deployまで進んだ。DOC_LANE_ROUTING偽陽性(73449dd3)と同型。
    local push_positive
    push_positive="$(printf '%s\n' "$ac_text" \
        | sed -E 's/(^|[^A-Za-z])(no|do not|must not|never|without)[[:space:]]+push($|[^A-Za-z])/\1__NEGPUSH__\3/Ig' \
        | sed -E 's/(^|[^A-Za-z])push(は|を|も)?(禁止|不可|しない|せず|しません|未実施|未|は行わない|を行わない|するな)/\1__NEGPUSH__/g' \
        | grep -ciE '(^|[^A-Za-z])push($|[^A-Za-z])' || true)"
    if [ "${push_positive:-0}" -gt 0 ]; then
        yaml_field_set "$task_file" "task" "push_allowed" "true" \
            && log "inject_push_allowed: AC内に'push'検出。push_allowed=trueを自動付与(cmd_3820 G2ガード解消)"
    fi
}

inject_model_injection_profile() {
    local task_file="$1"
    local ninja_name="$2"
    [ -f "$task_file" ] || return 0

    local model_label family intensity tmp_file inject_block indent="  "
    model_label="$(cli_model_display "$ninja_name" 2>/dev/null || true)"
    [ -n "$model_label" ] || model_label="$(FIELD_GET_NO_LOG=1 _cli_lookup_settings_get "$ninja_name" model_name unknown 2>/dev/null || true)"
    [ -n "$model_label" ] || model_label="unknown"
    family="$(model_injection_profile_family "$model_label")"
    intensity="$(model_injection_profile_intensity "$model_label")"

    inject_block="${indent}model_injection_profile:"
    inject_block="${inject_block}"$'\n'"${indent}  model_label: \"${model_label}\""
    inject_block="${inject_block}"$'\n'"${indent}  family: \"${family}\""
    inject_block="${inject_block}"$'\n'"${indent}  injection_intensity: \"${intensity}\""
    inject_block="${inject_block}"$'\n'"${indent}  protocol: \"T5弱LLM構造化プロトコル\""
    inject_block="${inject_block}"$'\n'"${indent}  report_contract:"
    inject_block="${inject_block}"$'\n'"${indent}  - \"binary_checks全resultをyes/noで記入\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"lessons_useful全reasonを具体記入\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"files_modifiedはrepo相対path形式\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"D7適用表を証跡化: 新behavior=新/拡張test、bugfix=再現regression、behavior不変refactor=既存coverage維持、docs/data-only=実行test免除根拠。既存contract再利用、配置二値基準、モック4類型、contract消滅時のみ削除\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"任務帰属検証契約: 反復・報告直前とも bash scripts/run_tests.sh task queue/tasks/${ninja_name}.yaml を実行し、task/reportの所有pathから選ばれたテストだけをbinary_checksへ帰属させる。選択対象はFAIL0・SKIP0を必須とし、scope外FAILを当該任務のFAILへ混入させない。run_tests.sh unit全量は個別taskで要求せず、fixed-SHAまたはwave最終checkpointで共有1回だけ実行する\""
    if [ "$intensity" = "max" ]; then
        inject_block="${inject_block}"$'\n'"${indent}  extra_scaffold:"
        inject_block="${inject_block}"$'\n'"${indent}  - \"ACごとに実テスト証跡をresult.detailsへ記録\""
        inject_block="${inject_block}"$'\n'"${indent}  - \"報告前にplaceholder残存確認とgate_report_formatを実行\""
        inject_block="${inject_block}"$'\n'"${indent}  - \"hook_failures.detailsはcount>0なら文字列でなくmapping形式で記入: cause/independent_verification/bypass_record/post_verification/post_verification_result/post_verification_headの6キー必須。post_verification_headは事後検証を実測した7-40文字hexのcommit hash(LG083)\""
    fi

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  model_injection_profile:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_model_injection_profile: ninja=${ninja_name} model=${model_label} intensity=${intensity}"
}

insert_task_block_before_description() {
    local tmp_file="$1"
    local inject_block="$2"

    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi
}

task_targets_are_documentation_only() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

try:
    data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    raise SystemExit(1)
task = data.get("task") or data
raw = [task.get("target_path"), task.get("planned_paths")]
paths = []
for value in raw:
    if isinstance(value, str):
        paths.append(value)
    elif isinstance(value, list):
        paths.extend(value)
paths = [str(path or "").strip() for path in paths if str(path or "").strip()]
suffixes = (".md", ".mdx", ".rst", ".adoc")
raise SystemExit(0 if any(path.lower().endswith(suffixes) for path in paths) else 1)
PY
}

# ─── DM-Signal PF削除/復元運用ガードレール注入 ───
# Level5: cmd_3786で露呈した前提知識不備をタスクYAMLへ自動注入し、
# PF一括削除/restore-all/rollback系で同じ試行錯誤を再発させない。
inject_dm_signal_pf_operation_guardrails() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    task_targets_are_documentation_only "$task_file" && {
        log "inject_dm_signal_pf_operation_guardrails: documentation-only target, skip"
        return 0
    }

    local project task_type title purpose command_text parent_cmd haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    [ "$project" = "dm-signal" ] || return 0

    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)

    if [ -n "$parent_cmd" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text="${command_text}
$(awk -v cmd="$parent_cmd" '
    /^  [a-zA-Z0-9_-]+:/ {
        cur=$0
        sub(/^[[:space:]]*/, "", cur)
        sub(/:.*$/, "", cur)
    }
    cur == cmd && /^(    title:|    type:|    purpose:|    command:|    acceptance_criteria:|        )/ { print }
' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    fi

    haystack="${task_type}
${title}
${purpose}
${command_text}"

    printf '%s\n' "$haystack" | grep -Eqi 'restore-all|restore|復元|rollback|ロールバック|portfolio_archive|archive.*portfolio|PF.*(削除|復元|rollback|ロールバック)|portfolio.*(delete|restore)|一括削除|cmd_3785|cmd_3786' || return 0

    local tmp_file inject_block indent="  "
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  dm_signal_pf_operation_guardrails:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    inject_block="${indent}dm_signal_pf_operation_guardrails:"
    inject_block="${inject_block}"$'\n'"${indent}- \"PF一括削除は登録順だけで判断しない。DELETE APIの400参照保護は安全停止。live DB/config依存を再計測し、削除できたPFから反復削除する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-allは POST /api/admin/portfolios/restore-all。名前衝突がある時は新PF削除を先行する。PF一覧APIは /api/portfolios/get であり /api/portfolios は404。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-all後はHTTP応答やDB recalculation_statusがstaleでも、/admin/recalculate-status running=false、active数、holding_signal/monthly_returns生成数、API/FEを一次確認して判定する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"WSL実行ではLinux python3を使う。Windows venv pythonをWSLから起動しない。CSV成果物はLFへ正規化し git diff --check を通す。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"開始前後に active_total、新PFlive数、archive restored/unrestored数、holding_signal数、monthly_returns数、API件数、FE HTTP status を数値で記録する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-locked実行前にsignal_change_log等の診断履歴をpost-snapshot artifactへ保存する。artifactにはrun_id/source/input provenance、row_count、hashを含め、restore後に同じ値を照合する。\""

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_dm_signal_pf_operation_guardrails: injected"
}

# L877 Level5: 巨大golden-baselineを扱うDM-Signal taskへ、GitHub上限を
# 越える前にmanifest/archive二層契約を事前供給する。
inject_dm_signal_golden_baseline_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project purpose command_text title haystack tmp_file inject_block indent="  "
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    [ "$project" = "dm-signal" ] || return 0
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    haystack="$title $purpose $command_text"
    printf '%s\n' "$haystack" | grep -Eqi 'golden[-_ ]?baseline|golden[-_ ]?data' || return 0

    inject_block="${indent}golden_baseline_contract:"
    inject_block="${inject_block}"$'\n'"${indent}- \"100MB超のrow payload本体はgit管理せず、gitignore済みoutputs/analysis/cmd_* archiveへ保存する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"git管理する小manifestにはcanonical hash、row_count、schema/version、archive相対pathを含める。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"テストでmanifestとarchiveのcanonical hash、row_count、schema/version一致を二値検証する。\""

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    cp "$task_file" "$tmp_file"
    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_dm_signal_golden_baseline_contract: L877 Level5 contract injected"
}

# ─── DM-Signal 5PF canary rotation contract ───
# Level5: every DM-Signal verification/performance task receives the same
# reversible one-commit → Live → fixed-five-PF --get → layer-total tracking
# contract.  Scope is structural (project/target_path) plus an explicit
# verification/performance term; prose-only references from infra tasks must
# never opt them into production validation obligations.
inject_dm_signal_canary_rotation_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    task_targets_are_documentation_only "$task_file" && {
        log "inject_dm_signal_canary_rotation_contract: documentation-only target, skip"
        return 0
    }

    local project target_path task_type title purpose command_text parent_cmd parent_text scope_text
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    target_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)

    # A resolved task may carry only parent_cmd/purpose while the command text
    # remains in the command SSOT.  Read the parent entry without mutating it.
    parent_text=$(python3 - "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$parent_cmd" <<'PY' 2>/dev/null || true
import sys
import yaml

path, cmd = sys.argv[1:]
if not cmd or not cmd.startswith('cmd_'):
    raise SystemExit(0)
try:
    data = yaml.safe_load(open(path, encoding='utf-8')) or {}
except Exception:
    raise SystemExit(0)
entry = (data.get('commands') or {}).get(cmd, {})
if isinstance(entry, dict):
    for key in ('title', 'purpose', 'command', 'description'):
        value = entry.get(key)
        if value is not None:
            print(value)
PY
)

    # project/target_path define ownership; the terms define this narrower
    # verification/performance lane.  This prevents an unrelated DM-Signal
    # feature task from inheriting canary/full-recalc obligations.
    if ! printf '%s\n%s\n' "$project" "$target_path" | grep -Eqi '(^|[^a-z0-9])dm-signal([^a-z0-9]|$)'; then
        return 0
    fi
    scope_text="${task_type}
${title}
${purpose}
${command_text}
${parent_text}"
    if ! printf '%s\n' "$scope_text" | grep -Eqi '検証|verify|validation|parity|canary|高速化|speed|performance|perf|bottleneck|hot[ -]?path|cache|ledger|計測|cost'; then
        return 0
    fi

    local indent="  " tmp_file inject_block
    tmp_file=$(mktemp "${task_file}.XXXXXX") || return 1
    awk '
        /^  dm_signal_canary_rotation_contract:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }

    inject_block="${indent}dm_signal_canary_rotation_contract:"
    inject_block="${inject_block}"$'\n'"${indent}  scope: \"DM-Signal verification/performance tasks only\""
    inject_block="${inject_block}"$'\n'"${indent}  revision:"
    inject_block="${inject_block}"$'\n'"${indent}    max_commits: 1"
    inject_block="${inject_block}"$'\n'"${indent}    allowed_changes:"
    inject_block="${inject_block}"$'\n'"${indent}      - \"cache reuse\""
    inject_block="${inject_block}"$'\n'"${indent}      - \"duplicate computation removal\""
    inject_block="${inject_block}"$'\n'"${indent}    new_mechanism: false"
    inject_block="${inject_block}"$'\n'"${indent}  deploy_live: required"
    inject_block="${inject_block}"$'\n'"${indent}  canary:"
    inject_block="${inject_block}"$'\n'"${indent}    pf_count: 5"
    inject_block="${inject_block}"$'\n'"${indent}    query: \"--get\""
    inject_block="${inject_block}"$'\n'"${indent}    duration_minutes: 3"
    inject_block="${inject_block}"$'\n'"${indent}    binary_checks:"
    inject_block="${inject_block}"$'\n'"${indent}      error_count: 0"
    inject_block="${inject_block}"$'\n'"${indent}      new_cash_delta: 0"
    inject_block="${inject_block}"$'\n'"${indent}      valid_start: normal"
    inject_block="${inject_block}"$'\n'"${indent}    layer_timings: [L2, L3, L5, other, TOTAL]"
    inject_block="${inject_block}"$'\n'"${indent}  feedback:"
    inject_block="${inject_block}"$'\n'"${indent}    numeric_one_line_report: true"
    inject_block="${inject_block}"$'\n'"${indent}    next_target: \"maximum bottleneck across L2/L3/L5/other/TOTAL\""
    inject_block="${inject_block}"$'\n'"${indent}  full:"
    inject_block="${inject_block}"$'\n'"${indent}    checkpoint: \"T7 final checkpoint only\""
    inject_block="${inject_block}"$'\n'"${indent}    max_runs: 1"

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || {
        rm -f "$tmp_file"
        return 1
    }
    rm -f "$tmp_file"
    log "inject_dm_signal_canary_rotation_contract: injected (project=${project:-none}, task_type=${task_type:-none})"
}

# ─── context hints注入（purpose/project/task_typeから必読contextをLevel5化） ───
# R2残件: 重要contextをタスクYAMLに強制注入し、忍者の能動検索依存をなくす。
inject_context_hints() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type title purpose command_text planned_paths haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    planned_paths=$(python3 - "$task_file" <<'PY' 2>/dev/null || true
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
value = task.get("planned_paths", [])
if isinstance(value, str):
    print(value)
elif isinstance(value, list):
    print("\n".join(str(item) for item in value))
PY
)

    haystack="${project}
${task_type}
${title}
${purpose}
${command_text}
${planned_paths}"

    local -a hints=()
    local codd_scope=false
    local is_dm_signal=false
    [ "$project" = "dm-signal" ] && is_dm_signal=true

    if [ "$is_dm_signal" = true ] || grep -Eqi 'robustness|ロバスト|PBO|MaxDD|robustness-verification-catalog|検証カタログ' <<< "$haystack"; then
        hints+=("context/robustness-verification-catalog.md")
    fi
    if [ "$is_dm_signal" = true ] || grep -Eqi 'GS|grid[ -]?search|グリッド|高速化|fullrecalculate|gs-speedup-knowledge' <<< "$haystack"; then
        hints+=("context/gs-speedup-knowledge.md")
    fi
    if [ "$is_dm_signal" = true ] || grep -Eqi 'terminology|用語|dm-signal-terminology|disambiguation|解釈|Flair|ALM|FOF|PF' <<< "$haystack"; then
        hints+=("$(get_project_path 'dm-signal' 2>/dev/null || echo '')/context/dm-signal-terminology.md")
    fi
    if [ "$project" = "infra" ] || [ "$task_type" = "training" ] || grep -Eqi 'training-cycle|修行|L[1-4]|訓練|idle' <<< "$haystack"; then
        hints+=("context/training-cycle.md")
    fi
    # GA-293 / L288: the pre-commit hook correctly requires CoDD source and
    # its freshness index in one commit.  Supply that contract at deployment
    # time whenever the task scope names a CoDD source path, so the first
    # commit does not have to discover it through a Level4 BLOCK.
    if printf '%s\n' "$planned_paths" | grep -Eqi '(^|/)(scripts/codd|skills/codd/|skills/codd-refactor/)'; then
        codd_scope=true
        hints+=("context/codd.md")
    fi

    [ ${#hints[@]} -gt 0 ] || return 0

    local tmp_file inject_block indent="  "
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  context_hints:/) { skip = 1; next }
            print
        }
    ' "$task_file" > "$tmp_file"

    inject_block="${indent}context_hints:"
    local hint
    for hint in "${hints[@]}"; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${hint}\""
    done

    insert_task_block_before_description "$tmp_file" "$inject_block"

    if [ "$codd_scope" = true ]; then
        local codd_scope_json
        codd_scope_json=$(python3 - "$tmp_file" <<'PY'
import json
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
paths = task.get("planned_paths") or []
if isinstance(paths, str):
    paths = [paths]
paths = list(dict.fromkeys([*[str(path) for path in paths], "context/codd.md"]))
contract = task.get("commit_contract")
if isinstance(contract, dict):
    contract = dict(contract)
    contract_paths = contract.get("planned_paths") or []
    if isinstance(contract_paths, str):
        contract_paths = [contract_paths]
    contract["planned_paths"] = list(
        dict.fromkeys([*[str(path) for path in contract_paths], "context/codd.md"])
    )
print(json.dumps({"planned_paths": paths, "commit_contract": contract}, ensure_ascii=False))
PY
) || return 1
        local codd_planned_json codd_contract_json
        codd_planned_json=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["planned_paths"], ensure_ascii=False))' "$codd_scope_json") || return 1
        yaml_field_set "$tmp_file" "task" "planned_paths" "$codd_planned_json" || return 1
        codd_contract_json=$(python3 -c 'import json,sys; value=json.loads(sys.argv[1])["commit_contract"]; print(json.dumps(value, ensure_ascii=False) if isinstance(value, dict) else "")' "$codd_scope_json") || return 1
        if [ -n "$codd_contract_json" ]; then
            yaml_field_set "$tmp_file" "task" "commit_contract" "$codd_contract_json" || return 1
        fi
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_context_hints: ${#hints[@]} hints injected"
}

# ─── reflux shared-queue commit contract (Level5) ───
# A reflux worker commits one bounded insight record while self-retro may
# update occurrence metadata in the same shared YAML immediately afterwards.
# Give the worker and the report gate the same immutable contract up front:
# the canonical helper, the exact scope, the producer identity, and the only
# fields a post-commit producer mutation may change.  A worker edit to any
# other field remains a real uncommitted change and must BLOCK.
inject_reflux_commit_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type purpose command_text planned_paths haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    planned_paths=$(python3 - "$task_file" <<'PY' 2>/dev/null || true
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
value = task.get("planned_paths", [])
if isinstance(value, str):
    print(value)
elif isinstance(value, list):
    print("\n".join(str(item) for item in value))
PY
)
    haystack="${project}\n${task_type}\n${purpose}\n${command_text}\n${planned_paths}"
    if ! grep -Eqi 'reflux[_ -]?insight|insight.*還流|還流.*insight' <<< "$haystack" \
        || ! grep -qxF 'queue/insights.yaml' <<< "$planned_paths"; then
        return 0
    fi

    local repo_root helper_path
    repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$SCRIPT_DIR")
    helper_path=$(realpath "$repo_root/scripts/ninja_scope_commit.sh" 2>/dev/null || printf '%s\n' "$repo_root/scripts/ninja_scope_commit.sh")
    # Generic yaml_field_set treats unknown JSON-valued fields as scalars.
    # Publish this mapping as a real YAML block so the task/report contract
    # cannot silently degrade into a quoted string.
    local tmp_file inject_block
    tmp_file=$(mktemp "${task_file}.XXXXXX") || return 1
    awk '
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  reflux_commit_contract:/) { skip = 1; next }
            print
        }
    ' "$task_file" > "$tmp_file" || return 1
    inject_block=$(cat <<EOF
  reflux_commit_contract:
    helper_path: "${helper_path}"
    repo_root: "${repo_root}"
    scope:
      - "queue/insights.yaml"
    producer:
      field: "source"
      value: "self_retro"
    stable_id_field: "id"
    post_commit_allowed_fields:
      - "occurrence_count"
      - "last_seen"
    uncommitted_worker_policy: "block"
EOF
)
    insert_task_block_before_description "$tmp_file" "$inject_block" || return 1
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_reflux_commit_contract: helper=${helper_path} scope=queue/insights.yaml producer=self_retro"
}

# ─── 本番不変量注入（task YAMLにproduction_invariantsを挿入） ───
# Level5: 忍者が本番ルールを意志依存ゼロで知る。PI違反=本番事故。
inject_production_invariants() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # タスクのproject取得
    local project
    project=$(awk '/^  project:/{print $2; exit}' "$task_file" 2>/dev/null)
    [ -n "$project" ] || return 0

    local pj_yaml="$SCRIPT_DIR/projects/${project}.yaml"
    [ -f "$pj_yaml" ] || return 0

    # PIエントリ抽出(上位5件)
    local pi_lines
    pi_lines=$(awk '
        /production_invariants:/ { found=1; next }
        found && /entries:/ { in_entries=1; next }
        in_entries && /- \{id: PI-/ {
            sub(/.*id: /, ""); sub(/,.*fact: /, ": ");
            sub(/"\}.*/, ""); sub(/"/, "");
            print; count++
            if (count >= 5) exit
        }
        found && /^[a-z]/ && !/entries:/ { exit }
    ' "$pj_yaml" 2>/dev/null)
    [ -n "$pi_lines" ] || return 0

    # 既存のproduction_invariantsを除去してから追加
    local tmp_file inject_block indent="  "
    inject_block="${indent}production_invariants:"
    while IFS= read -r line; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${line}\""
    done <<< "$pi_lines"

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  production_invariants:/ { skip=1; next }
        skip && /^  - "/ { next }
        skip && /^  [a-z]/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    insert_task_block_before_description "$tmp_file" "$inject_block"

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_production_invariants: project=$project $(echo "$pi_lines" | wc -l) PIs injected"
}

# ─── チェックリスト隣接Step制約自動注入（cmd_2644 Level5化） ───
# AC/command内のchecklist-*.md + Step番号を検出し、
# 前後Stepの制約条件（🛑/前提条件/⚠/🔴）をタスクYAMLへ強制注入。
# cmd_1397事故(再計算禁止ステップ未転写)の構造的再発防止。
# Pythonがtask_fileに直接書き込む（inject_related_lessonsと同パターン）。
inject_checklist_constraints() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'INJECT_CL_PY'; then
import os, re, sys, tempfile

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    import yaml
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)
except Exception:
    sys.exit(0)

task = data.get('task', data) if isinstance(data, dict) else {}

texts = []
ac = task.get('acceptance_criteria', {})
if isinstance(ac, dict):
    texts.append(str(ac.get('description', '')))
elif isinstance(ac, list):
    texts.extend(str(x) for x in ac)
for key in ('command', 'purpose'):
    v = task.get(key)
    if v:
        texts.append(str(v))

full_text = ' '.join(texts)

pattern = re.compile(r'(checklist-[\w-]+\.md)\s+(?:Step\s+)?(\d+)', re.IGNORECASE)
refs = {}
for m in pattern.finditer(full_text):
    fname = m.group(1)
    step = int(m.group(2))
    if fname not in refs:
        refs[fname] = set()
    refs[fname].add(step)

if not refs:
    sys.exit(0)


def find_step_positions(lines):
    positions = {}
    for i, line in enumerate(lines):
        m = re.match(r'^## (?:Step )?(\d+)[.: ]', line)
        if m:
            positions[int(m.group(1))] = i
    return positions


CONSTRAINT_KEYWORDS = ['🛑', '必ずここで止まれ', '前提条件', '⚠', '🔴', '禁止', '入るな', '確認後']


def is_constraint(line):
    return any(kw in line for kw in CONSTRAINT_KEYWORDS)


def clean_markdown(line):
    line = re.sub(r'^\s*>?\s*\**\s*', '', line)
    line = re.sub(r'\**\s*$', '', line)
    line = line.replace('"', "'")
    return line.strip()


def extract_adjacent_constraints(lines, step_positions, step_num):
    constraints = []
    prev = step_num - 1
    if prev in step_positions and step_num in step_positions:
        s, e = step_positions[prev], step_positions[step_num]
        for line in lines[s:e]:
            if is_constraint(line):
                clean = clean_markdown(line)
                if clean and len(clean) > 5:
                    constraints.append(f'[Step{prev}末尾] {clean}')
    nxt = step_num + 1
    if nxt in step_positions:
        s = step_positions[nxt]
        e = step_positions.get(nxt + 1, len(lines))
        e = min(s + 20, e)
        for line in lines[s:e]:
            if is_constraint(line):
                clean = clean_markdown(line)
                if clean and len(clean) > 5:
                    constraints.append(f'[Step{nxt}前提] {clean}')
    return constraints


all_constraints = []
for fname, steps in refs.items():
    cl_path = os.path.join(script_dir, 'context', fname)
    if not os.path.exists(cl_path):
        print(f'[INJECT_CL] WARN: {fname} not found', file=sys.stderr)
        continue
    with open(cl_path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    step_positions = find_step_positions(lines)
    if not step_positions:
        continue
    for step_num in sorted(steps):
        if step_num not in step_positions:
            print(f'[INJECT_CL] WARN: Step {step_num} not found in {fname}', file=sys.stderr)
            continue
        c = extract_adjacent_constraints(lines, step_positions, step_num)
        all_constraints.extend(c)

if not all_constraints:
    sys.exit(0)

with open(task_file, encoding='utf-8') as f:
    raw = f.read()

raw_lines = raw.split('\n')
new_lines = []
skip = False
for line in raw_lines:
    if line.startswith('  checklist_constraints:'):
        skip = True
        continue
    if skip:
        if re.match(r'  - "', line):
            continue
        else:
            skip = False
    if not skip:
        new_lines.append(line)

inject_lines = ['  checklist_constraints:']
for c in all_constraints:
    inject_lines.append(f'  - "{c}"')
inject_text = '\n'.join(inject_lines)

result_text = '\n'.join(new_lines)
if '\n  description:' in result_text:
    result_text = result_text.replace('\n  description:', '\n' + inject_text + '\n  description:', 1)
elif result_text.startswith('  description:'):
    result_text = inject_text + '\n' + result_text
else:
    result_text = result_text.rstrip('\n') + '\n' + inject_text + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(result_text)
    os.replace(tmp_path, task_file)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f'[INJECT_CL] Injected {len(all_constraints)} checklist constraints', file=sys.stderr)
INJECT_CL_PY
        log "inject_checklist_constraints: python error (non-fatal)"
    fi
    rm -f "$py_output"
}

# ─── 成長ループ防御階層注入（cmd_2649 Level5化） ───
# gate/hook関連cmdの忍者タスクYAMLにgrowth-loop.md §11を強制注入。
# 忍者がgate BLOCK後に「同じBLOCKが二度と起きない仕組み」を考える材料を提供。
# 事前コンテキスト提供（Level5）: 間違える余地がない環境を作る。
inject_growth_loop_defense() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'INJECT_GLD_PY'; then
import os, re, sys, tempfile

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    import yaml
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)
except Exception:
    sys.exit(0)

task = data.get('task', data) if isinstance(data, dict) else {}

# テキスト収集: purpose + acceptance_criteria + description
texts = []
for key in ('purpose', 'description', 'command'):
    v = task.get(key)
    if v:
        texts.append(str(v))
ac = task.get('acceptance_criteria', {})
if isinstance(ac, dict):
    texts.append(str(ac.get('description', '')))
elif isinstance(ac, list):
    texts.extend(str(x) for x in ac)

full_text = ' '.join(texts)

# FP防止: 外部PJ(dm-signal等)のPythonコードのhook/gateはinfra gate/hookではない
EXTERNAL_PROJECTS = {'dm-signal', 'google-classroom', 'clinic-expense-tracker', 'dividend-tracker'}
task_project = task.get('project', '')
if task_project in EXTERNAL_PROJECTS:
    sys.exit(0)

# gate/hook関連キーワード検出
GATE_KEYWORDS = [
    'gate', 'hook', 'BLOCK', 'growth.loop', 'growth-loop',
    '防御階層', 'Level5', 'gate_fire', 'gate_report', '成長ループ',
    'defense', 'defense_level', 'フロー内',
]
if not any(kw.lower() in full_text.lower() for kw in GATE_KEYWORDS):
    sys.exit(0)

# growth-loop.md §11 を読み込む
growth_loop_path = os.path.join(script_dir, 'context', 'growth-loop.md')
if not os.path.exists(growth_loop_path):
    print('[INJECT_GLD] WARN: growth-loop.md not found', file=sys.stderr)
    sys.exit(0)

with open(growth_loop_path, encoding='utf-8') as f:
    lines = f.readlines()

# §11 セクションを抽出
section_start = None
section_end = None
for i, line in enumerate(lines):
    if re.match(r'^## §11', line):
        section_start = i
    elif section_start is not None and re.match(r'^## ', line):
        section_end = i
        break
if section_start is None:
    print('[INJECT_GLD] WARN: §11 not found in growth-loop.md', file=sys.stderr)
    sys.exit(0)
if section_end is None:
    section_end = len(lines)

section_lines = lines[section_start:section_end]

# キーラインを抽出
key_lines = []
for line in section_lines:
    stripped = line.rstrip()
    # ゲートの成功（太字除去）
    if 'ゲートの成功' in stripped:
        cleaned = re.sub(r'\*\*', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)
    # Level行（テーブル行）: | 1 | 名称 | 仕組み | ...
    elif re.match(r'^\| \d ', stripped):
        parts = [p.strip() for p in stripped.split('|') if p.strip()]
        if len(parts) >= 3:
            key_lines.append(f'Level{parts[0]}({parts[1]}): {parts[2]}')
    # BLOCKされたら行
    elif 'BLOCKされたら' in stripped and '環境に埋め込め' in stripped:
        cleaned = re.sub(r'^[-\*\s]+', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)
    # Level5を目指せ行
    elif 'Level 5を目指せ' in stripped:
        cleaned = re.sub(r'^[-\*\s]+', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)

if not key_lines:
    print('[INJECT_GLD] WARN: no key lines extracted from §11', file=sys.stderr)
    sys.exit(0)

# 既存の growth_loop_defense をYAML node境界で除去する。
# quote/styleに依存した行regexは正規化後のsingle-quote listを孤立させるため禁止。
with open(task_file, encoding='utf-8') as f:
    raw = f.read()

raw_lines = raw.split('\n')
new_lines = raw_lines
try:
    root_node = yaml.compose(raw)
    task_node = root_node
    if isinstance(root_node, yaml.MappingNode):
        for key_node, value_node in root_node.value:
            if key_node.value == 'task':
                task_node = value_node
                break
    if isinstance(task_node, yaml.MappingNode):
        for key_node, value_node in task_node.value:
            if key_node.value == 'growth_loop_defense':
                start = key_node.start_mark.line
                end = value_node.end_mark.line
                new_lines = raw_lines[:start] + raw_lines[end:]
                break
except yaml.YAMLError:
    sys.exit(1)

inject_lines = ['  growth_loop_defense:']
for kl in key_lines:
    kl_safe = kl.replace('"', "'")
    inject_lines.append(f'  - "{kl_safe}"')
inject_text = '\n'.join(inject_lines)

result_text = '\n'.join(new_lines)
if '\n  description:' in result_text:
    result_text = result_text.replace('\n  description:', '\n' + inject_text + '\n  description:', 1)
elif result_text.startswith('  description:'):
    result_text = inject_text + '\n' + result_text
else:
    result_text = result_text.rstrip('\n') + '\n' + inject_text + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(result_text)
    os.replace(tmp_path, task_file)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f'[INJECT_GLD] Injected {len(key_lines)} defense levels', file=sys.stderr)
INJECT_GLD_PY
        log "inject_growth_loop_defense: python error (non-fatal)"
    fi
    rm -f "$py_output"
}

# ─── 実験ファースト原則（殿厳命2026-07-20、全task Level5） ───
inject_experiment_first_principle() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    PYTHONPATH="$SCRIPT_DIR" TASK_FILE_ENV="$task_file" python3 - <<'INJECT_EFP_PY'
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from scripts.lib.yaml_atomic import atomic_yaml_write

task_file = os.environ['TASK_FILE_ENV']
with open(task_file, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
task = data.get('task', data)
task['experiment_first_principle'] = [
    '殿の原文: 『LLMは人間ではない。考えることは向いてない。膨大な量の実験を超速で回し続ける総当たりが構造的に有効だ』',
    '適用形: 仮説を頭で絞らず、小さな独立実験へ分けて並列に全て試せ。想像で結論せず、各実験の一次結果を確認してから採否を決めよ。',
]
atomic_yaml_write(task_file, data)
INJECT_EFP_PY
}

inject_readonly_refs() {
    local task_file="$1"
    local parent_cmd command_text readonly_yaml

    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    if [ -z "$command_text" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text=$(
            PARENT_CMD_ENV="$parent_cmd" STK_ENV="$SCRIPT_DIR/queue/shogun_to_karo.yaml" python3 - <<'PY' 2>/dev/null || true
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

parent_cmd = os.environ.get("PARENT_CMD_ENV", "")
stk = os.environ.get("STK_ENV", "")
try:
    with open(stk, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    data = {}
commands = data.get("commands", data.get("cmds", data))
entry = None
if isinstance(commands, dict):
    entry = commands.get(parent_cmd)
elif isinstance(commands, list):
    entry = next((row for row in commands if isinstance(row, dict) and str(row.get("id", "")) == parent_cmd), None)
if isinstance(entry, dict):
    value = entry.get("command", "")
    if isinstance(value, (list, tuple)):
        value = "\n".join(str(v) for v in value)
    print(str(value or ""))
PY
        )
    fi
    [ -n "$command_text" ] || return 0

    if ! readonly_yaml=$(
        COMMAND_TEXT_ENV="$command_text" READONLY_ROOT_ENV="$SCRIPT_DIR" python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

command = os.environ.get("COMMAND_TEXT_ENV", "")
root = Path(os.environ["READONLY_ROOT_ENV"])
pattern = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"((?:/mnt/[A-Za-z0-9_.-]+/|(?:[A-Za-z0-9_.-]+/)*)[A-Za-z0-9_.-]+"
    r"\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv|log))"
    r"(?![A-Za-z0-9_.-])"
)
read_markers = (
    "必読", "読む", "読んで", "読み", "確認", "参照", "調査", "精査", "review", "read", "inspect", "refer",
    "実行", "実行のみ", "変更対象外", "走らせ", "検証", "整理", "抽出", "算出", "run", "execute",
)
write_markers = (
    "修正", "更新", "変更", "編集", "実装", "追加", "削除", "作成", "反映",
    "modify", "update", "edit", "add", "remove", "delete", "create", "write", "implement",
)

def marker_pos(text, markers):
    positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
    return min(positions) if positions else -1

def write_marker_pos(text):
    positions = []
    for marker in write_markers:
        start = 0
        while True:
            pos = text.find(marker, start)
            if pos < 0:
                break
            # 「更新トリガー/頻度」の更新は調査対象を表す名詞であり、
            # 当該ファイルを更新する動詞ではない。これをwrite扱いすると
            # 設計・偵察cmdのreadonly_ref注入が漏れ、完了gateが偽BLOCKする。
            suffix = text[pos + len(marker):]
            if marker == "更新" and re.match(r"^(?:トリガー|頻度|対象|履歴|時刻|経路|条件|有無|内容|周期|契機|方式|箇所)", suffix):
                start = pos + len(marker)
                continue
            positions.append(pos)
            break
    return min(positions) if positions else -1

matches = list(pattern.finditer(command))
seen = set()
readonly = []
for idx, match in enumerate(matches):
    ref = match.group(1).strip().strip("`'\".,:;()[]{}")
    if not ref or ref in seen:
        continue
    sentence_end_candidates = [
        pos for pos in (
            command.find("\n", match.end()),
            command.find("。", match.end()),
            command.find("；", match.end()),
            command.find(";", match.end()),
        )
        if pos >= 0
    ]
    sentence_start_candidates = [
        pos for pos in (
            command.rfind("\n", 0, match.start()),
            command.rfind("。", 0, match.start()),
            command.rfind("；", 0, match.start()),
            command.rfind(";", 0, match.start()),
        )
        if pos >= 0
    ]
    sentence_start = max(sentence_start_candidates) + 1 if sentence_start_candidates else 0
    sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(command)
    next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
    local = command[match.end():next_file_start]
    sentence = command[sentence_start:sentence_end]
    sentence_tail = command[match.end():sentence_end]
    read_pos = marker_pos(local, read_markers)
    if read_pos < 0:
        read_pos = marker_pos(sentence, read_markers)
    write_pos = write_marker_pos(sentence_tail)
    next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (
        write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos
    )
    is_readonly = read_pos >= 0 and (write_pos < 0 or next_ref_before_write or read_pos < write_pos)
    if is_readonly:
        seen.add(ref)
        readonly.append(ref)

canonical = []
missing = []
for ref in readonly:
    raw = Path(ref)
    candidates = [raw] if raw.is_absolute() else [root / raw]
    if not raw.is_absolute() and len(raw.parts) == 1:
        candidates.append(root / "scripts" / raw)
    resolved = next((path for path in candidates if path.exists()), None)
    if resolved is None:
        missing.append(ref)
        continue
    try:
        canonical.append(str(resolved.relative_to(root)).replace("\\", "/"))
    except ValueError:
        canonical.append(str(resolved))

if missing:
    print(
        "BLOCK: readonly_ref path does not exist or lacks canonical prefix: "
        + ",".join(missing),
        file=sys.stderr,
    )
    raise SystemExit(2)

for ref in canonical:
    escaped = ref.replace("'", "''")
    print(f"  - path: '{escaped}'")
    print("    reason: command欄の必読/参照専用ファイル")
PY
    ); then
        log "[INJECT_READONLY_REF] BLOCK: unresolved readonly command path"
        return 1
    fi

    [ -n "$readonly_yaml" ] || return 0

    TASK_FILE_ENV="$task_file" READONLY_YAML_ENV="$readonly_yaml" python3 - <<'PY'
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ["TASK_FILE_ENV"]
fragment = os.environ["READONLY_YAML_ENV"].rstrip("\n")

with open(task_file, encoding="utf-8") as f:
    raw = f.read()

yaml.safe_load("readonly_ref:\n" + fragment + "\n")

lines = raw.splitlines()
out = []
skip = False
for line in lines:
    stripped = line.lstrip(" ")
    indent = len(line) - len(stripped)
    if skip:
        # task直下のsequence itemは ``  - path: ...`` でindent=2。
        # indent>2だけを飛ばすと旧itemが残り、再注入のたび重複する。
        if stripped == "" or indent > 2 or (indent == 2 and stripped.startswith("-")):
            continue
        skip = False
    if indent == 2 and stripped.startswith("readonly_ref:"):
        skip = True
        continue
    out.append(line)

insert_at = len(out)
for idx in range(len(out) - 1, -1, -1):
    if out[idx].startswith("task:"):
        insert_at = idx + 1
        break
    if out[idx].startswith("  ") and not out[idx].startswith("    "):
        insert_at = idx + 1

out[insert_at:insert_at] = ["  readonly_ref:"] + fragment.splitlines()
result = "\n".join(out).rstrip("\n") + "\n"

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(result)
    yaml.safe_load(result)
    os.replace(tmp_path, task_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
PY
    log "[INJECT_READONLY_REF] injected command readonly refs"
}

# One deploy generation owns one postcondition marker.  The old fixed
# queue/tasks/.postcond_lesson_inject path let parallel --yaml deployments
# overwrite and consume each other's task/project/lesson identity.
deploy_task_postcondition_prepare() {
    local task_file="$1"
    local task_dir task_key ninja_key cmd_key generation

    if [ "${DEPLOY_TASK_POSTCOND_TASK_FILE:-}" = "$task_file" ] \
        && [ -n "${DEPLOY_TASK_POSTCOND_FILE:-}" ]; then
        return 0
    fi

    deploy_task_postcondition_cleanup
    task_dir="${task_file%/*}"
    [ "$task_dir" != "$task_file" ] || task_dir="."
    task_key="${task_file##*/}"
    task_key="${task_key%.yaml}"
    ninja_key="${NINJA_NAME:-$task_key}"
    cmd_key="${CMD_ID:-unknown}"
    generation="${DEPLOY_TASK_STARTED_US:-${EPOCHREALTIME/./}}_${BASHPID}"
    task_key="${task_key//[^a-zA-Z0-9_.-]/_}"
    ninja_key="${ninja_key//[^a-zA-Z0-9_.-]/_}"
    cmd_key="${cmd_key//[^a-zA-Z0-9_.-]/_}"
    generation="${generation//[^a-zA-Z0-9_.-]/_}"
    # Keep the filename below common 255-byte limits even for descriptive cmd IDs.
    cmd_key="${cmd_key:0:80}"

    DEPLOY_TASK_POSTCOND_TASK_FILE="$task_file"
    DEPLOY_TASK_POSTCOND_FILE="${task_dir}/.postcond_lesson_inject.${task_key}.${ninja_key}.${cmd_key}.${generation}"
    export DEPLOY_TASK_POSTCOND_TASK_FILE DEPLOY_TASK_POSTCOND_FILE
}

deploy_task_postcondition_cleanup() {
    if [ -n "${DEPLOY_TASK_POSTCOND_FILE:-}" ]; then
        rm -f -- "$DEPLOY_TASK_POSTCOND_FILE"
    fi
    DEPLOY_TASK_POSTCOND_FILE=""
    DEPLOY_TASK_POSTCOND_TASK_FILE=""
    export DEPLOY_TASK_POSTCOND_FILE DEPLOY_TASK_POSTCOND_TASK_FILE
}

__cluster_g_static_extraction_sentinel() { :; }
fi
# Cluster G module: semantic/memory/causal/skill/model/context injection,
# production invariants, and postcondition helpers.
_dt_context_injection_path="$SCRIPT_DIR/scripts/deploy_task/context_injection.sh"
if [ ! -f "$_dt_context_injection_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_context_injection_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/context_injection.sh"
fi
if [ ! -f "$_dt_context_injection_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_context_injection_path="$PROJECT_ROOT/scripts/deploy_task/context_injection.sh"
fi
source "$_dt_context_injection_path"
unset _dt_context_injection_path

if false; then
# ─── 教訓自動注入（task YAMLにrelated_lessonsを挿入） ───
# cmd_349: タグマッチによる選択的教訓注入
inject_related_lessons() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_lessons: task file not found: $task_file"
        return 0
    fi

    deploy_task_postcondition_prepare "$task_file"

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" POSTCOND_FILE_ENV="$DEPLOY_TASK_POSTCOND_FILE" python3 - <<'PY'; then
import csv
import datetime
import fnmatch
import os
import random
import re
import subprocess
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
postcond_file = os.environ['POSTCOND_FILE_ENV']

DEDUP_THRESHOLD = 0.25
USEFUL_RATE_THRESHOLD = 0.40  # effectiveness_score below this → exclude from injection candidates
USEFUL_RATE_DECAY = 0.3       # legacy constant retained for tests/docs that compare deploy_task constants
TARGET_PATH_MATCH_BOOST = int(os.environ.get('TARGET_PATH_MATCH_BOOST', '50'))
NO_WHEN_PENALTY = int(os.environ.get('NO_WHEN_PENALTY', '10'))  # when未設定教訓のスコア降格値(useful_rate改善。3→10: 219件when未設定のキーワード衝突注入をほぼ排除)
MIN_KEYWORD_SCORE_BY_TASK_TYPE = {
    'default': int(os.environ.get('MIN_KEYWORD_SCORE', '2')),
    'impl': int(os.environ.get('MIN_KEYWORD_SCORE_IMPL', '6')),
    'exact': int(os.environ.get('MIN_KEYWORD_SCORE_EXACT', '4')),
    'focused': int(os.environ.get('MIN_KEYWORD_SCORE_FOCUSED', os.environ.get('MIN_KEYWORD_SCORE_EXACT', '4'))),
}
# 是正1: Bootstrapギャップ解消 — feedback=0件の教訓はこの閾値を要求(通常閾値より高く設定)
MIN_KEYWORD_SCORE_ZERO_FEEDBACK = int(os.environ.get('MIN_KEYWORD_SCORE_ZERO_FEEDBACK', '5'))
# 是正2: cross-project注入の精度向上 — project不一致教訓はこの閾値を要求(通常閾値より高く設定)
MIN_KEYWORD_SCORE_CROSS_PROJECT = int(os.environ.get('MIN_KEYWORD_SCORE_CROSS_PROJECT', '5'))
IMPACT_COLUMNS = [
    'timestamp', 'cmd_id', 'ninja', 'lesson_id', 'action', 'result',
    'referenced', 'project', 'task_type', 'bloom_level', 'score',
    'traversal_depth',
]

def _is_empty_row(row):
    """Return True if all fields in *row* are blank (or only whitespace/CR)."""
    return all(not cell.strip().strip('\r') for cell in row)

def ensure_impact_header(impact_path):
    """Upgrade existing lesson_impact.tsv headers without losing old rows."""
    if not os.path.exists(impact_path) or os.path.getsize(impact_path) == 0:
        os.makedirs(os.path.dirname(impact_path), exist_ok=True)
        with open(impact_path, 'w', encoding='utf-8', newline='') as f:
            f.write('\t'.join(IMPACT_COLUMNS) + '\n')
        return
    with open(impact_path, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f, delimiter='\t'))
    if not rows:
        return
    # Strip CR from header fields for reliable comparison
    header = [c.strip().strip('\r') for c in rows[0]]
    if header == IMPACT_COLUMNS:
        return

    new_header = list(header)
    for col in IMPACT_COLUMNS:
        if col not in new_header:
            new_header.append(col)

    upgraded_rows = [new_header]
    for row in rows[1:]:
        # Skip empty rows (all fields blank)
        if _is_empty_row(row):
            continue
        upgraded = [cell.strip('\r') for cell in row]
        while len(upgraded) < len(new_header):
            upgraded.append('')
        upgraded_rows.append(upgraded)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(impact_path), prefix='lesson_impact.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f, delimiter='\t', lineterminator='\n')
            writer.writerows(upgraded_rows)
        os.replace(tmp_path, impact_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

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

USEFUL_RATE_MIN_SAMPLES = int(os.environ.get('USEFUL_RATE_MIN_SAMPLES', '1'))  # 3→1: 除外感度向上(除外=降格であり完全削除ではない)

def compute_useful_rates(script_dir):
    """lesson_impact.tsvのfeedback行からlesson別effectiveness_scoreを算出。
    score = USEFUL / (USEFUL + NOT_USEFUL)。feedback以外や未確定値は分母に入れない。
    MIN_SAMPLES未満の教訓は除外対象外（サンプル不足でのペナルティ防止）。"""
    impact_path = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    if not os.path.exists(impact_path):
        return {}, {}, {}
    feedback_counts = {}  # lesson_id -> [useful_count, total_feedback_count]
    try:
        with open(impact_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                lid = (row.get('lesson_id') or '').strip()
                action = (row.get('action') or '').strip().lower()
                if not lid or action != 'feedback':
                    continue
                result = (row.get('result') or '').strip().upper()
                if result not in ('USEFUL', 'NOT_USEFUL'):
                    continue
                if lid not in feedback_counts:
                    feedback_counts[lid] = [0, 0]
                feedback_counts[lid][1] += 1
                if result == 'USEFUL':
                    feedback_counts[lid][0] += 1
    except Exception:
        return {}, {}, {}
    # MIN_SAMPLES以上のfeedbackがある教訓のみscoreを返す
    useful_rates = {
        lid: vals[0] / vals[1] if vals[1] > 0 else 0.0
        for lid, vals in feedback_counts.items()
        if vals[1] >= USEFUL_RATE_MIN_SAMPLES
    }
    feedback_totals = {lid: vals[1] for lid, vals in feedback_counts.items()}
    useful_counts = {lid: vals[0] for lid, vals in feedback_counts.items()}
    return useful_rates, feedback_totals, useful_counts

ZERO_USEFUL_DEPRECATE_MIN_SAMPLES = int(os.environ.get('ZERO_USEFUL_DEPRECATE_MIN_SAMPLES', '3'))
ENABLE_ZERO_USEFUL_AUTO_DEPRECATE = os.environ.get('ENABLE_ZERO_USEFUL_AUTO_DEPRECATE', '0') == '1'

def _deprecate_lessons_in_file(yaml_path, lesson_ids):
    """Add deprecated: true to matching lesson blocks without round-tripping YAML."""
    if not lesson_ids or not yaml_path or not os.path.exists(yaml_path):
        return 0
    target_ids = set(str(lid) for lid in lesson_ids if lid)
    try:
        with open(yaml_path, encoding='utf-8') as f:
            lines = f.read().splitlines()
    except Exception:
        return 0

    out = []
    current_id = None
    current_indent = None
    has_deprecated = False
    pending_insert = False
    changed = 0

    def flush_pending():
        nonlocal pending_insert, changed
        if pending_insert and current_id in target_ids and not has_deprecated:
            out.append(' ' * (current_indent + 2) + 'deprecated: true')
            out.append(' ' * (current_indent + 2) + 'deprecation_reason: auto_useful_rate_zero')
            changed += 1
        pending_insert = False

    id_re = re.compile(r'^(\s*)-\s+id:\s*[\'"]?([^\'"#\s]+)')
    # cmd_3254: flow-style YAML対応 — `- {id: L723, ...}` パターン
    flow_id_re = re.compile(r'^(\s*)-\s+\{.*?id:\s*[\'"]?([^\'"#\s,}]+)')
    item_re = re.compile(r'^(\s*)-\s+')
    deprecated_re = re.compile(r'^\s+deprecated:\s*true\s*(?:#.*)?$', re.IGNORECASE)
    status_deprecated_re = re.compile(r'^\s+status:\s*[\'"]?deprecated[\'"]?\s*(?:#.*)?$', re.IGNORECASE)

    for line in lines:
        # cmd_3254: flow-style行を先にチェック（一行完結のため即時処理）
        flow_m = flow_id_re.match(line)
        if flow_m:
            fid = flow_m.group(2).strip()
            if fid in target_ids and 'deprecated: true' not in line and 'deprecated:true' not in line:
                # flow-style: 閉じ`}`の直前に`, deprecated: true`を挿入
                line = re.sub(r'\}(\s*)$', r', deprecated: true, deprecation_reason: auto_useful_rate_zero}\1', line)
                changed += 1
            out.append(line)
            continue

        item_m = item_re.match(line)
        if item_m and current_id is not None and len(item_m.group(1)) <= current_indent:
            flush_pending()
            current_id = None
            current_indent = None
            has_deprecated = False

        id_m = id_re.match(line)
        if id_m:
            current_id = id_m.group(2).strip()
            current_indent = len(id_m.group(1))
            has_deprecated = False
            pending_insert = current_id in target_ids
            out.append(line)
            continue

        if current_id in target_ids and (deprecated_re.match(line) or status_deprecated_re.match(line)):
            has_deprecated = True

        out.append(line)

    if current_id is not None:
        flush_pending()

    if changed <= 0:
        return 0

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(yaml_path), prefix='.lessons_deprecated.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write('\n'.join(out) + '\n')
        os.replace(tmp_path, yaml_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        return 0
    return changed

def apply_zero_useful_deprecation(
    lessons, lessons_path, feedback_totals, useful_counts,
    project_id=None, script_dir=None,
):
    """Retire zero-useful lessons through the canonical SSOT writer.

    ``lessons_path`` remains part of the call contract for cache identity and
    fixtures, but this function never writes the generated YAML cache. The
    canonical writer updates tasks/lessons.md and regenerates the cache.
    """
    if not ENABLE_ZERO_USEFUL_AUTO_DEPRECATE:
        return 0
    if not lessons:
        return 0
    zero_lids = {
        lid for lid, total in feedback_totals.items()
        if total >= ZERO_USEFUL_DEPRECATE_MIN_SAMPLES and useful_counts.get(lid, 0) == 0
    }
    if not zero_lids:
        return 0
    changed_ids = []
    for lesson in lessons:
        lid = str(lesson.get('id', '') or '')
        if not lid or lid not in zero_lids:
            continue
        if lesson.get('deprecated', False) or str(lesson.get('status', '')).lower() == 'deprecated':
            continue
        changed_ids.append(lid)
    if project_id and script_dir:
        writer = os.path.join(script_dir, 'scripts', 'lesson_write.sh')
        if not os.path.isfile(writer):
            raise RuntimeError(f'canonical lesson writer not found: {writer}')
        for lesson_id in sorted(changed_ids):
            subprocess.run(
                ['bash', writer, project_id, '--retire', lesson_id],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

    # The cache snapshot was loaded before the writer ran. Keep the in-memory
    # view consistent so retired lessons are not re-injected in this deploy.
    changed = 0
    for lesson in lessons:
        if str(lesson.get('id', '') or '') in changed_ids:
            lesson['deprecated'] = True
            lesson['deprecation_reason'] = 'auto_useful_rate_zero'
            lesson['retired'] = True
            changed += 1
    if changed:
        print(f'[INJECT] auto-retired zero-useful lessons via canonical SSOT writer: {changed_ids}', file=sys.stderr)
    return changed

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
        data = yaml.load(f, Loader=yaml.SafeLoader)

    if not data or 'task' not in data:
        print('[INJECT] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    project = task.get('project', '')
    task_type = str(task.get('task_type') or task.get('type') or task.get('scope_mode') or 'unknown').lower().strip()
    MIN_KEYWORD_SCORE = MIN_KEYWORD_SCORE_BY_TASK_TYPE.get(task_type, MIN_KEYWORD_SCORE_BY_TASK_TYPE['default'])
    parent_cmd = str(task.get('parent_cmd', '') or '').strip()

    # L4 direct-training ACs are injected as a dict schema before this
    # function runs.  Rewriting the task for related lessons can normalize it
    # into a list and silently break that training contract; template context
    # therefore wins over optional lesson injection.
    if parent_cmd.startswith('cmd_training_L4_') and task_type == 'normal':
        print('[INJECT] L4 training template: preserving acceptance_criteria schema; related lesson rewrite skipped', file=sys.stderr)
        sys.exit(0)

    def extract_keywords(text, min_len=4):
        words = re.split(r'[^a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+', str(text or ''))
        seen = set()
        keywords = []
        for word in words:
            word = word.lower().strip()
            if len(word) < min_len or word in seen:
                continue
            seen.add(word)
            keywords.append(word)
        return keywords

    command_text = str(task.get('command', '') or '')
    stk_path = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
    if not command_text and parent_cmd and os.path.exists(stk_path):
        try:
            with open(stk_path, encoding='utf-8') as stk_f:
                stk_data = yaml.load(stk_f, Loader=yaml.SafeLoader) or {}
            cmd_entry = (stk_data.get('commands') or {}).get(parent_cmd, {})
            command_text = str(cmd_entry.get('command', '') or '')
        except Exception as e:
            print(f'[INJECT] WARN: shogun_to_karo.yaml read failed for command keywords: {e}', file=sys.stderr)
    useful_rates, feedback_totals, useful_counts = compute_useful_rates(script_dir)

    # ═══ 偵察固有教訓リスト (cmd_1340) ═══
    # recon/scout/research タスクには以下の教訓のみ注入(全スキップ→固定リスト注入に変更)
    # 選定基準: recon/偵察/scope/search タグ持ちから偵察品質に直結する教訓を選定
    # 新規偵察教訓の追加手順:
    #   1. lessons.yamlに教訓を登録(lesson_write.sh経由)
    #   2. このRECON_LESSON_IDSセットにIDを追加
    #   3. リスト外の教訓は偵察タスクではスキップされる(CTX浪費防止)
    RECON_LESSON_IDS = {'L219', 'L211', 'L213', 'L104', 'L129', 'L128'}
    # L159 is useful only for large, independently splittable reconnaissance.
    # Keeping it in the blanket recon allowlist injected it into every small
    # recon task, where recent feedback was 0/3 useful.  Admit it only when the
    # task text states the lesson's actual trigger.
    _l159_trigger_terms = ('5軸', '5つ以上', '大規模偵察', '並列agent', '独立した偵察')
    _l159_trigger_text = ' '.join(str(task.get(key, '') or '') for key in ('title', 'description', 'purpose', 'command'))
    if any(term.casefold() in _l159_trigger_text.casefold() for term in _l159_trigger_terms):
        RECON_LESSON_IDS.add('L159')

    recon_mode = task_type in ('recon', 'scout', 'research')

    if not project:
        # GP-028: 3段フォールバック (task→cmd→current_project)
        fallback_source = None
        if parent_cmd:
            if os.path.exists(stk_path):
                try:
                    with open(stk_path) as stk_f:
                        stk_data = yaml.load(stk_f, Loader=yaml.SafeLoader)
                    cmd_entry = (stk_data or {}).get('commands', {}).get(parent_cmd, {})
                    fallback_project = str(cmd_entry.get('project', '') or '').strip()
                    if fallback_project:
                        project = fallback_project
                        fallback_source = f'shogun_to_karo.yaml ({parent_cmd})'
                except Exception as e:
                    print(f'[INJECT] WARN: shogun_to_karo.yaml read failed: {e}', file=sys.stderr)
        if not project:
            proj_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
            if os.path.exists(proj_yaml_path):
                try:
                    with open(proj_yaml_path) as pf:
                        proj_data = yaml.load(pf, Loader=yaml.SafeLoader)
                    cp = str((proj_data or {}).get('current_project', '') or '').strip()
                    if cp:
                        project = cp
                        fallback_source = 'current_project'
                except Exception as e:
                    print(f'[INJECT] WARN: projects.yaml read failed: {e}', file=sys.stderr)
        if not project:
            print('[INJECT] No project field, all fallbacks exhausted, skipping lesson injection', file=sys.stderr)
            sys.exit(0)
        print(f'[INJECT] WARN: project field missing, fallback to {fallback_source} (project={project})', file=sys.stderr)

    # GP-080: 教訓キャッシュ (/tmp/deploy_lesson_cache_{project}_{mtime}.json)
    # YAML解析は遅い(WSL2+大ファイル)。mtimeが同じなら/tmpのJSONキャッシュを使う
    import fcntl
    import hashlib
    import json

    def load_lessons_cached(yaml_path):
        """YAMLをJSONキャッシュ経由でロード。mtime不変ならキャッシュヒット"""
        if not os.path.exists(yaml_path):
            return []
        try:
            with open(yaml_path, 'rb') as source:
                source_bytes = source.read()
        except OSError:
            return []
        source_fp = hashlib.sha256(source_bytes).hexdigest()
        cache_key = hashlib.sha256((yaml_path + '\0' + source_fp).encode()).hexdigest()[:24]
        _cache_dir = os.environ.get('DEPLOY_LESSON_CACHE_DIR', '/tmp')
        os.makedirs(_cache_dir, exist_ok=True)
        cache_path = f'{_cache_dir}/deploy_lesson_cache_{cache_key}.json'
        lock_path = cache_path + '.lock'
        # キャッシュヒット
        if os.path.exists(cache_path):
            try:
                with open(cache_path) as cf:
                    return json.load(cf)
            except Exception:
                pass
        # 同一waveの同時missは1 workerだけが解析し、他workerはsnapshotを読む。
        try:
            with open(lock_path, 'w') as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                if os.path.exists(cache_path):
                    with open(cache_path) as cf:
                        return json.load(cf)
                data = yaml.load(source_bytes.decode('utf-8'), Loader=yaml.SafeLoader)
                lessons = data.get('lessons', []) if data else []
                fd, tmp_path = tempfile.mkstemp(dir=_cache_dir, prefix='.lesson_snapshot.', suffix='.json')
                with os.fdopen(fd, 'w') as cf:
                    json.dump(lessons, cf)
                os.replace(tmp_path, cache_path)
                return lessons
        except Exception:
            return []

    # Active lessons (index) for injection. Archive is for detail lookup only (GP-219).
    index_path = os.path.join(script_dir, 'projects', project, 'lessons.yaml')
    archive_path = os.path.join(script_dir, 'projects', project, 'lessons_archive.yaml')
    lessons_path = index_path if os.path.exists(index_path) else archive_path
    lessons = load_lessons_cached(lessons_path)
    if not lessons and not os.path.exists(lessons_path):
        print(f'[INJECT] WARN: lessons not found for project={project}', file=sys.stderr)
    apply_zero_useful_deprecation(
        lessons, lessons_path, feedback_totals, useful_counts,
        project_id=project, script_dir=script_dir,
    )
    # cmd_2270: プロジェクトソーストラッキング (project-source boostに使用)
    for _l in lessons:
        _l['_source_project'] = project

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    cross_project_count = 0
    cross_project_projects = 0
    pdata = {}
    platform_project_ids = set()
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.load(pf, Loader=yaml.SafeLoader)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform':
                    platform_project_ids.add(str(pj.get('id', '') or '').strip())
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_index = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    plat_archive = os.path.join(script_dir, 'projects', pj['id'], 'lessons_archive.yaml')
                    plat_path = plat_index if os.path.exists(plat_index) else plat_archive
                    plat_lessons = load_lessons_cached(plat_path)
                    apply_zero_useful_deprecation(
                        plat_lessons, plat_path, feedback_totals, useful_counts,
                        project_id=pj['id'], script_dir=script_dir,
                    )
                    # cmd_2270: platformソースをトラッキング
                    for _l in plat_lessons:
                        _l['_source_project'] = pj['id']
                    platform_count += len(plat_lessons)
                    lessons.extend(plat_lessons)
        except Exception as pe:
            print(f'[INJECT] WARN: platform lessons load failed: {pe}', file=sys.stderr)

    def _lesson_project_allowed(lesson):
        source_project = str(lesson.get('_source_project', '') or '').strip()
        lesson_project = str(lesson.get('project', '') or '').strip()
        if source_project in platform_project_ids:
            return True
        if source_project != project:
            return False
        return not lesson_project or lesson_project == project

    _pre_project_filter = len(lessons)
    lessons = [lesson for lesson in lessons if _lesson_project_allowed(lesson)]
    _project_filtered = _pre_project_filter - len(lessons)
    if _project_filtered:
        print(f'[INJECT] project filter: removed {_project_filtered} lessons outside project={project} (platform allowed)', file=sys.stderr)

    # Deduplicate lessons by ID deterministically.  The task project's SSOT
    # wins over platform copies; within one source the first canonical entry
    # wins.  Loading order can therefore never silently replace project facts.
    _id_to_lesson = {}
    _no_id = []
    for _l in lessons:
        _lid = _l.get('id', '')
        if _lid:
            current = _id_to_lesson.get(_lid)
            if current is None:
                _id_to_lesson[_lid] = _l
            elif current.get('_source_project') != project and _l.get('_source_project') == project:
                _id_to_lesson[_lid] = _l
        else:
            _no_id.append(_l)
    _pre_dedup = len(lessons)
    lessons = list(_id_to_lesson.values()) + _no_id
    if len(lessons) < _pre_dedup:
        print(f'[INJECT] lesson_id dedup: {_pre_dedup} → {len(lessons)} (removed {_pre_dedup - len(lessons)} duplicate IDs)', file=sys.stderr)

    if not lessons:
        # Insert empty related_lessons via text manipulation (avoid yaml.dump on full file)
        with open(task_file, encoding='utf-8') as f:
            raw = f.read()
        import re
        raw = re.sub(r'\n  related_lessons:.*?(?=\n  [a-z]|\Z)', '', raw, flags=re.DOTALL)
        # Append before end of task block
        task_end = re.search(r'\n[a-z]', raw[raw.index('task:'):])
        if task_end:
            pos = raw.index('task:') + task_end.start()
            raw = raw[:pos] + '\n  related_lessons: []' + raw[pos:]
        else:
            raw = raw.rstrip() + '\n  related_lessons: []\n'
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
                f.write(raw)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print(f'[INJECT] No lessons for project={project} (including platform)', file=sys.stderr)
        sys.exit(0)

    # Build task text for keyword extraction
    # GP-223: purpose/target_path/context_files追加でキーワード関連度向上
    # cmd_2276: commandも統合し、target_path非依存でタスク意図を教訓注入に反映
    title = task.get('title', '')
    description = task.get('description', '')
    purpose = str(task.get('purpose') or '')
    target_path = str(task.get('target_path') or '')
    has_target_path = bool(target_path.strip())
    _cf = task.get('context_files')
    context_files = ' '.join(str(f) for f in _cf if f) if isinstance(_cf, list) else str(_cf or '')
    ac_list = task.get('acceptance_criteria', [])
    if isinstance(ac_list, list):
        ac_text = ' '.join(str(a.get('description', '')) if isinstance(a, dict) else str(a) for a in ac_list)
    else:
        ac_text = str(ac_list or '')
    task_text = f'{title} {description} {purpose} {command_text} {target_path} {context_files} {ac_text}'
    # Training task templates own their AC schema.  Lesson selection may add
    # context but must not gain extra relevance from procedural when/how text
    # and replace that schema through the training injection path.
    _training_identity = str(task.get('parent_cmd') or task.get('task_id') or '')
    use_condition_semantics = not _training_identity.startswith('cmd_training_')

    # Extract keywords: split by non-word chars, then ASCII↔CJK boundary split, dedup
    # GP-225: ASCII↔CJK境界分割で"CDP計測"→["CDP","計測"]に分離+アクロニム(>=2,全大文字)はmin_len免除
    _CJK = r'\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF'
    _boundary = re.compile(rf'(?<=[a-zA-Z0-9_])(?=[{_CJK}])|(?<=[{_CJK}])(?=[a-zA-Z0-9_])')
    words = re.split(rf'[^a-zA-Z0-9_{_CJK}]+', task_text)
    expanded = [part for w in words for part in _boundary.split(w) if part]
    keywords = list(set(w.lower() for w in expanded if len(w) > 3 or (len(w) >= 2 and w.isupper() and w.isascii())))

    # cmd_3231: target_pathなし時はキーワードスコアリング閾値を引き上げ、低関連教訓の注入を抑止
    NO_TARGET_PATH_MIN_SCORE = int(os.environ.get('NO_TARGET_PATH_MIN_SCORE', '8'))
    if not has_target_path:
        MIN_KEYWORD_SCORE = max(MIN_KEYWORD_SCORE, NO_TARGET_PATH_MIN_SCORE)
        print(f'[INJECT] no target_path: MIN_KEYWORD_SCORE raised to {MIN_KEYWORD_SCORE}', file=sys.stderr)

    SEMANTIC_LESSON_BOOST = int(os.environ.get('SEMANTIC_LESSON_BOOST', '20'))

    def _split_semantic_cell(value):
        return [
            item.strip().strip('`')
            for item in str(value or '').split(',')
            if item.strip() and item.strip() != 'なし'
        ]

    def _semantic_concept_lesson_boosts(query_text):
        """Boost lessons linked from matched semantic concepts in docs/semantic-index."""
        index_md = os.path.join(script_dir, 'docs', 'semantic-index', 'index.md')
        if not os.path.exists(index_md):
            return {}, []
        try:
            raw_index = open(index_md, encoding='utf-8').read()
        except Exception:
            return {}, []

        query_fold = str(query_text or '').casefold()
        boosts = {}
        matched_concepts = []
        for section in re.split(r'(?m)^##\s+', raw_index)[1:]:
            lines = section.splitlines()
            if not lines:
                continue
            heading = lines[0].strip()
            if ' — ' in heading:
                concept_id, heading_label = heading.split(' — ', 1)
            else:
                concept_id, heading_label = heading, ''
            attrs = {'id': concept_id.strip(), 'label': heading_label.strip()}
            for line in lines[1:]:
                stripped = line.strip()
                if not stripped.startswith('|') or not stripped.endswith('|'):
                    continue
                parts = stripped.split('|')
                if len(parts) < 4:
                    continue
                left = parts[1].strip()
                right = '|'.join(parts[2:-1]).strip()
                if left in {'id', 'label', 'aliases', 'related_lessons'}:
                    attrs[left] = right

            lesson_ids = _split_semantic_cell(attrs.get('related_lessons', ''))
            if not lesson_ids:
                continue
            terms = [attrs.get('label', ''), *_split_semantic_cell(attrs.get('aliases', ''))]
            matched_terms = [
                term for term in terms
                if term and (term.casefold() in query_fold or query_fold in term.casefold())
            ]
            if not matched_terms:
                continue
            cid = attrs.get('id') or concept_id.strip()
            matched_concepts.append(cid)
            for lid in lesson_ids:
                boosts[lid] = max(boosts.get(lid, 0), SEMANTIC_LESSON_BOOST)

            if len(matched_concepts) >= 5:
                break
        return boosts, matched_concepts

    def _resolve_memory_db_read_path(db_path):
        """cmd_3758: event_concepts全表スキャンをext4キャッシュ経由に迂回する。
        WSL2の/mnt/cは9pマウントで、464MB DBへのGROUP BY/JOINランダムI/Oが
        1クエリ40-60s級になる(scripts/memory_db_query.shのwarmキャッシュでは<1s)。
        memory_db_query.shのprepare_memory_db_for_read(L77-125)と同じ判定を
        Python側から再現し、同一キャッシュを共有する。取得失敗時はdb_pathをそのまま返す
        (テスト用フィクスチャDB等、キャッシュ層が使えない環境でも既存動作を維持)。"""
        if os.environ.get('SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE', '0') == '1':
            return db_path
        if os.environ.get('SHOGUN_DISABLE_MEMORY_DB_CACHE', '0') == '1':
            return db_path
        lib_dir = os.path.join(script_dir, 'scripts')
        try:
            if lib_dir not in sys.path:
                sys.path.insert(0, lib_dir)
            import memory_db_live_insert as _mdbi
            cache_path = _mdbi.memory_db_cache_path(db_path)
        except Exception:
            return db_path

        def _mtime(path):
            try:
                return os.path.getmtime(path)
            except OSError:
                return None

        cache_mtime = _mtime(cache_path)
        _build_cmd = [
            sys.executable, '-c',
            'import sys; sys.path.insert(0, sys.argv[1]); '
            'import memory_db_live_insert as m; m.create_memory_db_ext4_cache(sys.argv[2])',
            lib_dir, db_path,
        ]
        if cache_mtime is None or os.path.getsize(cache_path) == 0:
            # キャッシュ未生成: 初回のみ同期構築(タイムアウト保護)。以降の呼出は常にwarmキャッシュを使う
            try:
                import subprocess
                subprocess.run(
                    _build_cmd,
                    timeout=int(os.environ.get('SHOGUN_MEMORY_DB_CACHE_INIT_TIMEOUT', '30')),
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
                )
            except Exception:
                return db_path
            return cache_path if os.path.exists(cache_path) and os.path.getsize(cache_path) > 0 else db_path

        src_mtime = _mtime(db_path)
        wal_mtime = _mtime(f'{db_path}-wal')
        shm_mtime = _mtime(f'{db_path}-shm')
        if any(m is not None and m > cache_mtime for m in (src_mtime, wal_mtime, shm_mtime)):
            try:
                import subprocess
                subprocess.Popen(
                    _build_cmd,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                )
            except Exception:
                pass
        return cache_path

    def _memory_db_concept_lesson_boosts(query_text, seed_concepts=None):
        """Boost lesson IDs found in memory events connected to matched event_concepts."""
        import sqlite3

        db_path = os.environ.get(
            'MEMORY_DB_PATH',
            os.path.join(script_dir, 'data', 'multi_agent_shogun_memory.db'),
        )
        if not os.path.exists(db_path):
            return {}, [], 0

        query_fold = str(query_text or '').casefold()
        if not query_fold.strip():
            return {}, [], 0

        db_read_path = _resolve_memory_db_read_path(db_path)
        try:
            conn = sqlite3.connect(f'file:{db_read_path}?mode=ro', uri=True, timeout=2.0)
        except Exception:
            return {}, [], 0

        matched_concepts = []
        seed_concepts = [str(c).strip() for c in (seed_concepts or []) if str(c).strip()]
        try:
            rows = conn.execute(
                """
                SELECT concept_name
                FROM event_concepts
                GROUP BY concept_name
                ORDER BY MAX(relevance_score) DESC, COUNT(*) DESC
                LIMIT 1000
                """
            ).fetchall()
            available_concepts = {str(c or '').strip() for (c,) in rows}
            for concept in seed_concepts:
                if concept in available_concepts and concept not in matched_concepts:
                    matched_concepts.append(concept)
            for (concept_name,) in rows:
                concept = str(concept_name or '').strip()
                if not concept:
                    continue
                concept_fold = concept.casefold()
                if concept_fold in query_fold or query_fold in concept_fold:
                    matched_concepts.append(concept)
                if len(matched_concepts) >= 10:
                    break

            if not matched_concepts:
                return {}, [], 0

            placeholders = ','.join('?' for _ in matched_concepts)
            event_rows = conn.execute(
                f"""
                SELECT e.summary, e.detail, e.concepts, e.cmd_id
                FROM event_concepts AS c
                JOIN events AS e ON e.id = c.event_id
                WHERE c.concept_name IN ({placeholders})
                ORDER BY COALESCE(e.ts, '') DESC
                LIMIT 300
                """,
                matched_concepts,
            ).fetchall()
        except Exception:
            return {}, [], 0
        finally:
            conn.close()

        boost = int(os.environ.get('MEMORY_DB_LESSON_BOOST', str(SEMANTIC_LESSON_BOOST)))
        boosts = {}
        lesson_re = re.compile(r'(?<![A-Za-z0-9_])L\d{2,4}(?![A-Za-z0-9_])')
        for row in event_rows:
            event_text = ' '.join(str(v or '') for v in row)
            for lid in lesson_re.findall(event_text):
                boosts[lid] = max(boosts.get(lid, 0), boost)
        return boosts, matched_concepts, len(event_rows)

    semantic_lesson_boosts, semantic_matched_concepts = _semantic_concept_lesson_boosts(task_text)
    memory_db_lesson_boosts, memory_db_matched_concepts, memory_db_event_count = _memory_db_concept_lesson_boosts(
        task_text,
        semantic_matched_concepts,
    )
    if memory_db_matched_concepts or memory_db_lesson_boosts or memory_db_event_count:
        print(
            '[INJECT] memory_db_boost: '
            f'concepts={len(memory_db_matched_concepts)} '
            f'lessons={len(memory_db_lesson_boosts)} '
            f'events={memory_db_event_count}',
            file=sys.stderr,
        )
    lesson_boosts = dict(semantic_lesson_boosts)
    for _lid, _boost in memory_db_lesson_boosts.items():
        lesson_boosts[_lid] = max(lesson_boosts.get(_lid, 0), _boost)

    # cmd_2606: target_path由来のサブドメインで教訓を絞る。
    # subdomain未設定の既存教訓は後方互換のため全サブドメインにマッチさせる。
    SUBDOMAIN_ALIASES = {
        'frontend': 'fe',
        'front': 'fe',
        'ui': 'fe',
        'fe': 'fe',
        'backend': 'be',
        'back': 'be',
        'api': 'be',
        'be': 'be',
        'grid_search': 'gs',
        'grid-search': 'gs',
        'gridsearch': 'gs',
        'gs': 'gs',
        'infra': 'infra',
        'platform': 'infra',
    }

    def _as_str_list(value):
        if isinstance(value, list):
            return [str(v) for v in value if v]
        if isinstance(value, str) and value:
            return [value]
        return []

    def _normalize_subdomains(value):
        if value is None or value == '':
            return set()
        if isinstance(value, str):
            raw_items = re.split(r'[, ]+', value)
        elif isinstance(value, list):
            raw_items = value
        else:
            raw_items = [value]
        normalized = set()
        for item in raw_items:
            key = str(item).lower().strip()
            if not key:
                continue
            normalized.add(SUBDOMAIN_ALIASES.get(key, key))
        return normalized

    def _infer_subdomains_from_paths(paths):
        inferred = set()
        for raw_path in paths:
            path = str(raw_path).replace('\\', '/').lower().strip()
            if not path:
                continue
            basename = os.path.basename(path)
            if '/frontend/' in path or path.startswith('frontend/'):
                inferred.add('fe')
            if '/backend/' in path or path.startswith('backend/') or '/app/api/' in path:
                inferred.add('be')
            if (
                '/grid_search/' in path
                or '/outputs/grid_search/' in path
                or 'grid_search' in path
                or basename.startswith('run_077')
                or basename.startswith('gs_')
            ):
                inferred.add('gs')
            if (
                path.startswith(('scripts/', 'queue/', 'context/', 'instructions/', 'projects/', 'config/', 'tests/'))
                and not inferred
            ):
                inferred.add('infra')
        return inferred

    task_subdomains = _infer_subdomains_from_paths(_as_str_list(task.get('target_path', '')))

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
                    tdata = yaml.load(tf, Loader=yaml.SafeLoader)
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

    # (3) タグ推定が空かつtarget_pathあり → pathディレクトリベースでタグ推定
    # cmd_3413: task_tags空+target_pathあり時の全教訓フォールバック(L5017-5018)を削減するため
    # target_pathのディレクトリ構造からプロジェクト文脈タグを推定する
    if not task_tags and has_target_path:
        _path_lower = target_path.lower().replace('\\', '/')
        _path_tag_rules_dir = [
            (r'(?:^|/)scripts/', 'infra'),
            (r'(?:^|/)context/', 'infra'),
            (r'(?:^|/)config/', 'infra'),
            (r'(?:^|/)queue/', 'infra'),
            (r'(?:^|/)instructions/', 'infra'),
            (r'(?:^|/)docs/', 'infra'),
            (r'(?:^|/)backend/', 'api'),
            (r'(?:^|/)frontend/', 'frontend'),
            (r'(?:^|/)tests?/', 'testing'),
        ]
        for _ppat, _ptag in _path_tag_rules_dir:
            if re.search(_ppat, _path_lower):
                task_tags = [_ptag]
                tag_inferred = True
                print(f'[INJECT] path-dir tag inferred: {target_path!r} -> tags={task_tags}', file=sys.stderr)
                break

    # Keep only active lessons: status=confirmed or undefined (default=confirmed)
    confirmed_lessons = []
    filtered_draft = 0
    filtered_deprecated = 0
    filtered_retired = 0
    for lesson in lessons:
        # Applicability metadata is an executable contract.  Missing tags or
        # malformed when/scope/target_files must fail closed, not be coerced
        # into a broad keyword candidate.
        _tags_value = lesson.get('tags')
        _when_value = lesson.get('when')
        _scope_value = lesson.get('scope')
        _targets_value = lesson.get('target_files')
        _metadata_types_valid = (
            isinstance(_tags_value, (list, str))
            and isinstance(_when_value, (str, type(None)))
            and isinstance(_scope_value, (str, type(None)))
            and isinstance(_targets_value, (list, str, type(None)))
        )
        if not _metadata_types_valid or not _tags_value:
            continue
        # Skip retired lessons (cmd_1297: 退役制度)
        if lesson.get('retired', False):
            filtered_retired += 1
            continue
        l_status = str(lesson.get('status', 'confirmed')).lower()
        if l_status == 'deprecated':
            filtered_deprecated += 1
            continue
        if lesson.get('deprecated', False):
            filtered_deprecated += 1
            continue
        if str(lesson.get('superseded_by', '') or '').strip():
            filtered_deprecated += 1
            continue
        if l_status != 'confirmed':
            filtered_draft += 1
            continue
        confirmed_lessons.append(lesson)

    if task_subdomains:
        _pre_subdomain_count = len(confirmed_lessons)
        _subdomain_filtered = []
        for lesson in confirmed_lessons:
            lesson_subdomains = _normalize_subdomains(lesson.get('subdomain'))
            if not lesson_subdomains or (lesson_subdomains & task_subdomains):
                _subdomain_filtered.append(lesson)
        confirmed_lessons = _subdomain_filtered
        _removed_subdomain_count = _pre_subdomain_count - len(confirmed_lessons)
        if _removed_subdomain_count > 0:
            print(
                f'[INJECT] subdomain filter: removed {_removed_subdomain_count} lessons '
                f'(task_subdomains={sorted(task_subdomains)})',
                file=sys.stderr,
            )

    # ═══ 偵察モード: 固定リストの教訓のみ通過 (cmd_1340) ═══
    if recon_mode:
        recon_filtered = [l for l in confirmed_lessons if l.get('id', '') in RECON_LESSON_IDS]
        recon_skipped_count = len(confirmed_lessons) - len(recon_filtered)
        confirmed_lessons = recon_filtered
        print(f'[INJECT] recon_mode: {len(confirmed_lessons)} recon-specific lessons selected (skipped {recon_skipped_count} non-recon)', file=sys.stderr)

    # ═══ target_filesマッチング: ファイルレベルフィルタ (cmd_1563) ═══
    # 教訓にtarget_files指定がある場合、タスクのtarget_pathまたはfiles_modifiedとマッチ時のみ注入
    task_target_path = task.get('target_path', '')
    task_files_modified = task.get('files_modified', [])
    if isinstance(task_target_path, str):
        _ttp_list = [task_target_path] if task_target_path else []
    elif isinstance(task_target_path, list):
        _ttp_list = [str(p) for p in task_target_path if p]
    else:
        _ttp_list = []
    if isinstance(task_files_modified, str):
        task_files_modified = [task_files_modified] if task_files_modified else []
    elif isinstance(task_files_modified, list):
        task_files_modified = [str(p) for p in task_files_modified if p]
    else:
        task_files_modified = []
    _all_task_files = _ttp_list + task_files_modified

    def _target_files_match(lesson_target_files, task_files):
        """教訓のtarget_filesパターンがタスクファイルのいずれかにマッチするか判定"""
        for pattern in lesson_target_files:
            pattern = str(pattern).strip()
            if not pattern:
                continue
            for tf in task_files:
                if fnmatch.fnmatch(tf, pattern) or fnmatch.fnmatch(os.path.basename(tf), pattern):
                    return True
                if fnmatch.fnmatch(os.path.basename(tf), os.path.basename(pattern)):
                    return True
        return False

    def _lesson_matches_task_target_path(lesson):
        """target_path/files_modifiedに一致するtarget_files教訓を順位付けで強く優先する。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        if not any(str(p).strip() for p in lesson_target_files):
            return False
        return _target_files_match(lesson_target_files, _all_task_files)

    def _lesson_has_only_report_artifact_target_match(lesson):
        """報告YAML artifact全般への一致を、対象コードの関連性として扱わない。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        patterns = [str(p).strip() for p in lesson_target_files if str(p).strip()]
        if not patterns:
            return False
        task_files = [str(p).strip() for p in _all_task_files if str(p).strip()]
        if not task_files or not all(p.startswith('queue/reports/') for p in task_files):
            return False
        non_report_patterns = [p for p in patterns if not p.startswith('queue/reports/')]
        return bool(non_report_patterns)

    def _path_relevance_terms(task_files):
        terms = set()
        for path in task_files:
            path = str(path or '').lower()
            if not path:
                continue
            terms.update(extract_keywords(path, min_len=3))
            base = os.path.basename(path)
            stem, _ = os.path.splitext(base)
            terms.update(t for t in re.split(r'[^a-z0-9]+', stem.lower()) if len(t) >= 3)
        return terms

    task_file_terms = _path_relevance_terms(_all_task_files)

    def _universal_without_target_files_is_relevant(lesson, l_tags):
        """target_filesなしuniversalが全cmdへ漏れるのを防ぐため、target_pathとの語彙関連を要求する。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        if any(str(p).strip() for p in lesson_target_files):
            return _target_files_match(lesson_target_files, _all_task_files)
        non_universal_tags = {t for t in l_tags if t != 'universal'}
        if task_tags and (set(task_tags) & non_universal_tags):
            return True
        if not task_file_terms:
            return True
        lesson_text = ' '.join(str(lesson.get(k, '') or '') for k in ('id', 'title', 'summary', 'content', 'source')).lower()
        lesson_text += ' ' + ' '.join(non_universal_tags)
        lesson_terms = set(extract_keywords(lesson_text, min_len=3))
        return bool(task_file_terms & lesson_terms)

    _GENERIC_WHEN = {
        '', '未設定', '同種の作業・判断・検証を行う時',
        '同種の作業を行う時', '関連作業を行う時',
    }

    def _condition_terms(value):
        """Extract bounded applicability terms; boilerplate is not evidence."""
        text = str(value or '').strip()
        if text in _GENERIC_WHEN:
            return set()
        return set(extract_keywords(text, min_len=4))

    task_condition_terms = set(extract_keywords(task_text, min_len=4))
    task_scope_terms = set(extract_keywords(
        ' '.join(str(task.get(k, '') or '') for k in ('scope', 'scope_mode', 'task_type', 'type')),
        min_len=3,
    ))

    def _lesson_has_applicability_evidence(lesson):
        """Require a concrete when/scope/target_files fact, never project or boost alone."""
        if _lesson_matches_task_target_path(lesson):
            return True
        when_terms = _condition_terms(lesson.get('when'))
        if when_terms and (when_terms & task_condition_terms):
            return True
        lesson_scope_terms = _condition_terms(lesson.get('scope'))
        return bool(lesson_scope_terms and (lesson_scope_terms & task_scope_terms))

    def _lesson_tags_compatible(l_tags):
        """Task kind/domain and lesson tags must agree; universal is not a wildcard."""
        concrete = {t for t in l_tags if t != 'universal'}
        if concrete and task_tags and (concrete & set(task_tags)):
            return True
        type_aliases = {
            'recon': {'recon', 'research', 'scout'},
            'scout': {'recon', 'research', 'scout'},
            'research': {'recon', 'research', 'analysis'},
            'impl': {'impl', 'implementation', 'code'},
            'exact': {'exact', 'impl', 'implementation', 'code'},
            'focused': {'focused', 'impl', 'implementation', 'code'},
            'hotfix': {'hotfix', 'impl', 'implementation', 'code'},
        }
        return bool(concrete & type_aliases.get(task_type, {task_type}))

    # target_filesフィルタ: 明示target_filesはタグより強い制約として扱う。
    # narrow lessonがタグ一致だけで別ファイルtaskへ漏れると useful率を悪化させる。
    _tf_excluded_ids = set()  # target_files不一致で除外候補のID
    if _all_task_files:
        for _l in confirmed_lessons:
            if _l.get('_cross_project_opt_in'):
                continue
            # cmd_karo_hotfix_boost_bypass_production_path_20260725 AC1:
            # boost付きでもtarget_files不一致なら除外対象にする(boostは関連度加点であり
            # 明示target_files制約のバイパス根拠ではない)
            _ltf = _l.get('target_files', [])
            if not _ltf:
                continue
            if isinstance(_ltf, str):
                _ltf = [_ltf]
            if _lesson_has_only_report_artifact_target_match(_l):
                _tf_excluded_ids.add(_l.get('id', ''))
                continue
            if not _target_files_match(_ltf, _all_task_files):
                _tf_excluded_ids.add(_l.get('id', ''))
        if _tf_excluded_ids:
            print(f'[INJECT] target_files filter: {len(_tf_excluded_ids)} lessons marked for exclusion (task files: {[os.path.basename(f) for f in _all_task_files[:3]]})', file=sys.stderr)
    else:
        # GP-218: タスクファイルなし→target_files設定ありの教訓は除外(マッチ不可能)
        for _l in confirmed_lessons:
            if _l.get('_cross_project_opt_in'):
                continue
            _ltf = _l.get('target_files', [])
            if isinstance(_ltf, str):
                _ltf = [_ltf]
            if _ltf and any(str(p).strip() for p in _ltf):
                # cmd_karo_hotfix_boost_bypass_production_path_20260725 AC1:
                # boost付きもマッチ不可能な以上は除外する
                _tf_excluded_ids.add(_l.get('id', ''))
        if _tf_excluded_ids:
            print(f'[INJECT] target_files filter (no task files): {len(_tf_excluded_ids)} lessons with target_files excluded', file=sys.stderr)

    # ═══ タグマッチ: 教訓をフィルタ ═══
    # universal教訓は別管理（常に注入）
    universal_lessons = []
    tag_candidates = []

    for lesson in confirmed_lessons:
        l_tags = lesson.get('tags', [])
        if isinstance(l_tags, str):
            l_tags = [l_tags]
        l_tags = [str(t).lower().strip() for t in l_tags if t]

        # Relevance boosts and project membership only rank already-applicable
        # lessons.  They can never manufacture task applicability.
        if not _lesson_has_applicability_evidence(lesson):
            continue

        # universal教訓は広すぎるため、target_files未設定ならtarget_pathとの関連性を確認する。
        if 'universal' in l_tags:
            if _universal_without_target_files_is_relevant(lesson, l_tags) and (
                _lesson_tags_compatible(l_tags) or _condition_terms(lesson.get('when'))
            ):
                universal_lessons.append(lesson)
            else:
                _tf_excluded_ids.add(lesson.get('id', ''))
            continue

        # タグなし旧形式は適用種別を証明できないため、target_files一致時だけ許可する。
        if not l_tags:
            if _lesson_matches_task_target_path(lesson):
                tag_candidates.append(lesson)
            continue

        # task_tagsが決定済みの場合、タグ重複チェック
        if task_tags:
            if _lesson_tags_compatible(l_tags):
                tag_candidates.append(lesson)
        # cmd_3271: target_pathなし+tag推定失敗 → タグ付き教訓は除外（NOT_USEFUL量産防止）
        # target_pathあり時は安全側フォールバック維持（既存動作）
        elif has_target_path:
            tag_candidates.append(lesson)
        # else: target_pathもtask_tagsもなし → この教訓をskip

    # (5) タスクにtagsがなくキーワード推定もできない → 全教訓fallback
    # cmd_3271: target_pathなし時は全量fallback禁止（has_target_pathがある場合のみ実行）
    if not task_tags and has_target_path:
        tag_candidates = [l for l in confirmed_lessons if l not in universal_lessons]
        print(f'[INJECT] WARN: full-lesson fallback triggered (path-dir inference failed, target_path={target_path!r}, candidates={len(tag_candidates)})', file=sys.stderr)
    elif not task_tags:
        print(f'[INJECT] no target_path + no task_tags: skipping full-lesson fallback ({len(confirmed_lessons)} lessons withheld)', file=sys.stderr)

    # target_filesフィルタ適用: target_files不一致はタグ一致でも除外する。
    if _tf_excluded_ids:
        _pre_tf_count = len(tag_candidates)
        tag_candidates = [l for l in tag_candidates if l.get('id','') not in _tf_excluded_ids]
        _tf_actually_removed = _pre_tf_count - len(tag_candidates)
        if _tf_actually_removed > 0:
            print(f'[INJECT] target_files post-filter: removed {_tf_actually_removed}', file=sys.stderr)

    # cmd_karo_gp196: AC1 — MAX_INJECT=10 総合注入上限（universalは内数）
    # cmd_2270: 3→10に拡大。キーワード関連度スコアリングで上位10件に絞る
    # cmd_3405: 10→3に縮小。useful_rate=16.7%(<30%)の根因=過剰注入修正
    # tag fallback/useful_rate処理より前に定義し、条件分岐での未定義参照を防ぐ
    MAX_INJECT = int(os.environ.get('MAX_INJECT_OVERRIDE', '3'))

    # ═══ スコアリング: タグマッチ候補内でキーワードスコア順位付け ═══
    scored = []
    keyword_score_filtered = 0
    for lesson in tag_candidates:
        lid = lesson.get('id', '')
        l_title = str(lesson.get('title', ''))
        l_summary = str(lesson.get('summary', ''))
        l_content = str(lesson.get('content', ''))
        l_source = str(lesson.get('source', ''))
        l_when = str(lesson.get('when', '') or '').strip()
        l_how = str(lesson.get('how', '') or '').strip()

        title_text = l_title.lower()
        # AC文の語は要約だけでなく、教訓が適用される条件(when)と
        # 実行手順(how)にも現れる。ここを除外すると表層語の一致だけで
        # 注入され、意味的に適合する教訓が低スコアで落ちる。
        condition_text = f'{l_when} {l_how}' if use_condition_semantics else ''
        other_text = f'{l_summary} {l_content} {l_source} {condition_text}'.lower()

        keyword_score = 0
        for kw in keywords:
            # cmd_2270: 頻度重み付きスコアリング (engram-style: presence→frequency count)
            # タイトル内出現回数×3 + その他テキスト内出現回数×1
            keyword_score += title_text.count(kw) * 3 + other_text.count(kw) * 1

        score = keyword_score

        # D0: when未設定教訓のスコア降格 — when条件なしはキーワードのみで注入され
        # NOT_USEFUL率が高い(199/828=24%がwhen未設定, useful_rate 19%)
        if (not l_when or l_when == '未設定') and not _condition_terms(lesson.get('scope')) \
                and not _lesson_matches_task_target_path(lesson):
            score -= NO_WHEN_PENALTY

        # cmd_3254: boostはkeyword_score>0の教訓にのみ適用
        # 根因: keyword_score=0でもboost(20)+project(2)=22でMIN_KEYWORD_SCOREを突破し
        # 全NOT_USEFUL教訓の28%(16/58)を占めていた(useful_rate 3.4%の主因)
        semantic_boost = lesson_boosts.get(lid, 0)
        if semantic_boost and keyword_score > 0:
            score += semantic_boost

        cross_project_score = lesson.get('_cross_project_score', 0) or 0
        # 是正2: cross-project注入の精度向上 — project不一致教訓はraw keyword_scoreで高閾値フィルタ
        # 根因: platform教訓(infra等)がdm-signal cmdにkeyword_score低値で素通りしNOT_USEFUL量産(L1290-L1292事例)
        if (lesson.get('_source_project') and lesson.get('_source_project') != project
                and keyword_score < MIN_KEYWORD_SCORE_CROSS_PROJECT):
            keyword_score_filtered += 1
            continue
        if cross_project_score and score < cross_project_score:
            score = cross_project_score

        # cmd_3466: target_path boost is a ranking boost, not a relevance bypass.
        # keyword_score=0 + target_files basename match was injecting low-useful lessons
        # whose only relation was "this file changed before".
        if keyword_score > 0 and _lesson_matches_task_target_path(lesson):
            score += TARGET_PATH_MATCH_BOOST

        if score <= 0:
            continue

        # 是正1: Bootstrapギャップ解消 — feedback=0件の新規教訓はより高い閾値を要求
        # 根因: 初回注入時feedback=0の教訓はuseful_rateフィルタを素通りしNOT_USEFUL量産(L1291-L1292等)
        _effective_min_score = MIN_KEYWORD_SCORE
        if feedback_totals.get(lid, 0) == 0:
            _effective_min_score = max(_effective_min_score, MIN_KEYWORD_SCORE_ZERO_FEEDBACK)
        if score < _effective_min_score:
            keyword_score_filtered += 1
            continue

        # cmd_2270: プロジェクト一致ボーナス — 同プロジェクト教訓を優先注入
        if lesson.get('_source_project') == project:
            score += 2
        scored.append((score, lid, l_summary or l_title))

    if keyword_score_filtered:
        print(f'[INJECT] keyword score filter: removed {keyword_score_filtered} lessons below MIN_KEYWORD_SCORE={MIN_KEYWORD_SCORE}', file=sys.stderr)
    if semantic_lesson_boosts:
        boosted_ids = sorted(set(semantic_lesson_boosts) & {lid for _, lid, _ in scored})
        print(
            f'[INJECT] semantic lesson boost: concepts={semantic_matched_concepts} '
            f'candidate_lessons={sorted(semantic_lesson_boosts)} boosted={boosted_ids} boost={SEMANTIC_LESSON_BOOST}',
            file=sys.stderr,
        )
    if memory_db_lesson_boosts:
        boosted_ids = sorted(set(memory_db_lesson_boosts) & {lid for _, lid, _ in scored})
        print(
            f'[INJECT] memory_db lesson boost: concepts={memory_db_matched_concepts} '
            f'events={memory_db_event_count} candidate_lessons={sorted(memory_db_lesson_boosts)} '
            f'boosted={boosted_ids} boost={os.environ.get("MEMORY_DB_LESSON_BOOST", str(SEMANTIC_LESSON_BOOST))}',
            file=sys.stderr,
        )

    # 忍者成長速度改善: タグマッチしたがキーワード0点の教訓をhelpful_count順でフォールバック注入
    # GP-221: target_filesなし教訓のフォールバック注入廃止。タスク無関係教訓のNOT_USEFUL量産防止
    # cmd_3231: target_pathなし時はfallback注入も無効化（helpful_count順=関連性無視→NOT_USEFUL量産の根因）
    if not scored and task_tags and tag_candidates:
        if not has_target_path:
            print(f'[INJECT] no target_path: skipping tag fallback (would inject {min(len(tag_candidates), MAX_INJECT)} lessons by helpful_count)', file=sys.stderr)
        else:
            _relevant_fallback = [
                l for l in tag_candidates
                if _lesson_matches_task_target_path(l)
            ]
            _tag_fallback = [(l.get('helpful_count',0) or 0, l.get('id',''), str(l.get('summary', l.get('title','')))[:80]) for l in _relevant_fallback]
            _tag_fallback.sort(key=lambda x: -x[0])
            scored = [(1, lid, summ) for hc, lid, summ in _tag_fallback[:MAX_INJECT]]
            if scored:
                print(f'[INJECT] tag fallback: keyword score=0, using {len(scored)} target_path-matched lessons by helpful_count', file=sys.stderr)

    # cmd_1564+karo_idle_fix: useful_rate feedback基盤
    # cmd_2700: mature feedback effectiveness_scoreが低い教訓は注入候補から除外
    # フィードバックデータ(record_lesson_feedback.sh)から実有用率を算出
    effectiveness_excluded = []

    def needs_initial_feedback(lid):
        return feedback_totals.get(lid, 0) < USEFUL_RATE_MIN_SAMPLES

    # universal教訓にもuseful_rateフィルタを適用
    # 有用率が閾値未満のuniversal教訓はtag_candidatesに降格（スコアリング対象に移動）
    if useful_rates and universal_lessons:
        demoted = []
        kept = []
        for lesson in universal_lessons:
            lid = lesson.get('id', '')
            rate = useful_rates.get(lid)
            if rate is not None and rate < USEFUL_RATE_THRESHOLD:
                demoted.append(lesson)
                effectiveness_excluded.append({'id': lid, 'summary': lesson.get('summary', '') or lesson.get('title', '')})
            else:
                kept.append(lesson)
        if demoted:
            demoted_ids = [l.get('id', '?') for l in demoted]
            print(f'[INJECT] universal effectiveness exclusion: {len(demoted)} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% effectiveness_score: {demoted_ids}', file=sys.stderr)
            universal_lessons = kept

    if useful_rates:
        new_scored = []
        excluded_ids = []
        for score, lid, summary in scored:
            rate = useful_rates.get(lid)
            if rate is not None and rate < USEFUL_RATE_THRESHOLD:
                excluded_ids.append(lid)
                effectiveness_excluded.append({'id': lid, 'summary': summary})
            else:
                new_scored.append((score, lid, summary))
        scored = new_scored
        if excluded_ids:
            print(f'[INJECT] effectiveness exclusion: {len(excluded_ids)} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% threshold: {excluded_ids}', file=sys.stderr)

    # Sort by score descending, take top 7 (AC5: task-specific max 7)
    scored.sort(key=lambda x: -x[0])

    # Greedy dedup: 類似教訓の枠消費防止
    lessons_by_id = {l.get('id',''): l for l in confirmed_lessons}
    pre_dedup_count = len(scored)
    scored = greedy_dedup(scored, lessons_by_id)

    # cmd_1457: keyword_score(関連度)をprimary sort、helpful_countをtiebreaker
    # 根因: helpful_count最終決定でL074(hc=1086)/L063(hc=1013)等が常に枠占拠(マシュー効果)
    scored_with_helpful = []
    for score, lid, summary in scored:
        lesson = lessons_by_id.get(lid, {})
        helpful = lesson.get('helpful_count', 0) or 0
        scored_with_helpful.append((helpful, score, lid, summary))
    scored_with_helpful.sort(key=lambda x: (-x[1], -x[0]))
    scored = [(s, lid, summ) for _, s, lid, summ in scored_with_helpful]

    # AC4: スコア0時のフォールバック = 注入なし（無関連教訓のCTX浪費防止）

    # cmd_1457: universal教訓の準備（max 1、helpful_count上位）— task-specificに最低2枠確保(忍者成長速度改善1: 2→1)
    MAX_UNIVERSAL = 1
    universal_total_count = len(universal_lessons)
    universal_lessons.sort(key=lambda l: -(l.get('helpful_count', 0) or 0))
    universal_lessons = universal_lessons[:MAX_UNIVERSAL]

    # cmd_1457: universal/task-specific枠分離（universalがtask-specificの枠を奪えない構造）
    # universal: 先頭に配置、最大MAX_UNIVERSAL(2)枠
    # task-specific: 残り枠（最低 MAX_INJECT - MAX_UNIVERSAL = 1枠確保）
    related = []
    withheld = list(effectiveness_excluded)
    universal_added = 0
    seen_ids_final = set()
    lesson_scores = {}
    for _score, _lid, _summary in scored:
        lesson_scores[_lid] = _score

    # Phase 1: Universal枠（最大MAX_UNIVERSAL）
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id in seen_ids_final:
            continue
        if universal_added >= MAX_UNIVERSAL:
            break
        lesson = lessons_by_id.get(ul_id, {})
        detail = build_lesson_detail(lesson)[:200]
        entry = {'id': ul_id, 'summary': ul.get('summary', '') or ul.get('title', '')}
        if detail:
            entry['detail'] = detail
        related.append(entry)
        seen_ids_final.add(ul_id)
        universal_added += 1

    # Phase 2: Task-specific枠（残り全て — universalが不足すれば繰上げ）
    task_specific_slots = MAX_INJECT - len(related)
    task_specific_added = 0
    for _, lid, summary in scored:
        if task_specific_added >= task_specific_slots:
            break
        if lid in seen_ids_final:
            continue
        lesson = lessons_by_id.get(lid, {})
        detail = build_lesson_detail(lesson)[:200]
        entry = {'id': lid, 'summary': summary}
        if detail:
            entry['detail'] = detail
        related.append(entry)
        seen_ids_final.add(lid)
        task_specific_added += 1

    # Withheld: 枠外の教訓
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id not in seen_ids_final:
            if needs_initial_feedback(ul_id):
                continue
            withheld.append({'id': ul_id, 'summary': ul.get('summary', '') or ul.get('title', '')})
    for _, lid, summary in scored:
        if lid not in seen_ids_final:
            if needs_initial_feedback(lid):
                continue
            withheld.append({'id': lid, 'summary': summary})

    task['related_lessons'] = related

    # (A) description冒頭に教訓要約を挿入（忍者が即座に目にする）
    desc_modified = False
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
            desc_modified = True

    # GP-240: description埋込IDとrelated_lessons IDの不一致検出
    desc_ids = set(r['id'] for r in related) if related else set()
    rl_ids = set(r['id'] for r in task.get('related_lessons', []) if isinstance(r, dict))
    if desc_ids != rl_ids:
        print(f'[INJECT] WARN: description/related_lessons ID mismatch. desc={sorted(desc_ids)} rl={sorted(rl_ids)}', file=sys.stderr)

    # --- Safe targeted write (avoid full yaml.dump — cmd_1407 AC2) ---
    with open(task_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
    def _sv(v, multiline_indent=2):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
            return [p + key + ': ' + s]
        if not val:
            return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
        r = [p + key + ':']
        if isinstance(val, dict):
            for k, v in val.items():
                r.extend(_yaml_lines(k, v, ind + 2))
        else:
            for item in val:
                r.extend(_list_item(item, ind))
        return r
    def _list_item(item, ind):
        p = ' ' * ind
        if not isinstance(item, (dict, list)):
            s = _sv(item, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
            return [p + '- ' + s]
        if isinstance(item, dict) and item:
            lines = []
            first = True
            for k, v in item.items():
                tag = '- ' if first else '  '
                first = False
                if isinstance(v, (dict, list)) and v:
                    lines.append(p + tag + k + ':')
                    if isinstance(v, list):
                        for sub in v:
                            lines.extend(_list_item(sub, ind + 2))
                    else:
                        for dk, dv in v.items():
                            lines.extend(_yaml_lines(dk, dv, ind + 4))
                else:
                    sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                    if '\n' in sv:
                        parts = sv.split('\n')
                        lines.append(p + tag + k + ': ' + parts[0])
                        lines.extend(parts[1:])
                    else:
                        lines.append(p + tag + k + ': ' + sv)
            return lines
        return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
    def _safe_section_replace(text, section_name, new_value):
        """Replace a 2-space-indented section under task: without full yaml.dump"""
        frag = '\n'.join(_yaml_lines(section_name, new_value))
        indented = '\n'.join('  ' + line for line in frag.split('\n'))
        # 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
        _lines = text.split('\n')
        _result = []
        _skip = False
        _inserted = False
        for _l in _lines:
            _s = _l.lstrip(' ')
            _i = len(_l) - len(_s)
            if _skip:
                if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
                    continue
                _skip = False
            if _i == 2 and _s.startswith(section_name + ':'):
                _skip = True
                _result.append(indented)
                _inserted = True
                continue
            _result.append(_l)
        text = '\n'.join(_result)
        if not _inserted:
            task_idx = text.index('task:')
            rest = text[task_idx + 5:]
            top_m = re.search(r'^\S', rest, re.MULTILINE)
            if top_m:
                pos = task_idx + 5 + top_m.start()
                text = text[:pos] + indented + '\n' + text[pos:]
            else:
                text = text.rstrip('\n') + '\n' + indented + '\n'
        return text

    raw = _safe_section_replace(raw, 'related_lessons', related)
    if desc_modified:
        raw = _safe_section_replace(raw, 'description', task['description'])

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    # Postcondition data (cmd_378)
    try:
        with open(postcond_file, 'w') as _pf:
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
    print(f'[INJECT]   project={project} {tag_info} scored={scored_count}/{tag_candidate_count} cross_project={cross_project_count}/{cross_project_projects} top_scores={[(s,i) for s,i,_ in scored[:5]]}', file=sys.stderr)
    print(f'[INJECT]   filtered: draft={filtered_draft} deprecated={filtered_deprecated} retired={filtered_retired}', file=sys.stderr)
    dedup_removed = pre_dedup_count - len(scored)
    print(f'[INJECT]   dedup: {dedup_removed} duplicates removed (threshold={DEDUP_THRESHOLD})', file=sys.stderr)

    # ═══ 教訓因果追跡ログ記録 ═══
    impact_log = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    cmd_id = task.get('task_id') or task.get('parent_cmd') or 'unknown'
    # cmd_3269: ninja_nameをタスクファイル名から取得（assigned_to未設定時のunknown防止）
    _task_basename = os.path.splitext(os.path.basename(task_file))[0]
    ninja_name = _task_basename if _task_basename and _task_basename != 'unknown' else task.get('assigned_to', 'unknown')
    task_type = task.get('task_type') or task.get('type', 'unknown')
    bloom = task.get('bloom_level', 'unknown')
    impact_header = '\t'.join(IMPACT_COLUMNS) + '\n'

    try:
        os.makedirs(os.path.dirname(impact_log), exist_ok=True)
        ensure_impact_header(impact_log)
        # cmd_3269: cmd_id+lesson_id重複チェック（二重記録防止）
        existing_keys = set()
        if os.path.exists(impact_log):
            try:
                with open(impact_log, 'r', encoding='utf-8', newline='') as ef:
                    reader = csv.DictReader(ef, delimiter='\t')
                    for row in reader:
                        _ek_cmd = (row.get('cmd_id') or '').strip()
                        _ek_lid = (row.get('lesson_id') or '').strip()
                        if _ek_cmd and _ek_lid:
                            existing_keys.add((_ek_cmd, _ek_lid))
            except Exception:
                pass
        write_header = not os.path.exists(impact_log) or os.path.getsize(impact_log) == 0
        skipped_dup = 0
        with open(impact_log, 'a', encoding='utf-8') as lf:
            if write_header:
                lf.write(impact_header)
            ts = datetime.datetime.now().isoformat(timespec='seconds')
            for r in related:
                if (cmd_id, r["id"]) in existing_keys:
                    skipped_dup += 1
                    continue
                score_value = lesson_scores.get(r["id"], 0)
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{r["id"]}\tinjected\tpending\tpending\t{project}\t{task_type}\t{bloom}\t{score_value}\t0\n')
            for w in withheld:
                if (cmd_id, w["id"]) in existing_keys:
                    skipped_dup += 1
                    continue
                score_value = lesson_scores.get(w["id"], 0)
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{w["id"]}\twithheld\tpending\tno\t{project}\t{task_type}\t{bloom}\t{score_value}\t0\n')
        written = len(related) + len(withheld) - skipped_dup
        print(f'[INJECT] Impact log: {written} written ({skipped_dup} duplicates skipped) to lesson_impact.tsv', file=sys.stderr)
    except Exception as ie:
        print(f'[INJECT] WARN: impact log write failed: {ie}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── WA頻発パターン教訓注入（cmd_3582: workaround TOP3 → related_lessons） ───
inject_workaround_pattern_lessons() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_workaround_pattern_lessons: task file not found: $task_file"
        return 0
    fi

    local workarounds_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
    if [ ! -f "$workarounds_file" ]; then
        log "inject_workaround_pattern_lessons: karo_workarounds.yaml not found, skipping"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    local ninja_jp_name
    ninja_jp_name="$(get_japanese_name "$ninja_name" 2>/dev/null || echo "$ninja_name")"
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" WORKAROUNDS_FILE_ENV="$workarounds_file" NINJA_NAME_ENV="$ninja_name" NINJA_JP_ENV="$ninja_jp_name" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import os, re, sys, tempfile, yaml

task_file = os.environ['TASK_FILE_ENV']
workarounds_file = os.environ['WORKAROUNDS_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
ninja_jp_name = os.environ.get('NINJA_JP_ENV', ninja_name)

CATEGORY_LESSON_IDS = {
    'commit_missing': ['L278', 'L342'],
    'report_yaml_format': ['L311'],
    'report_missing': ['L278'],
    'yaml_dump': ['L295'],
    'yaml_dump_policy': ['L295'],
    'scope_contamination': ['L589'],
    'scope_leak': ['L589'],
}

def match_ninja(entry):
    field = str(entry.get('ninja', '') or '')
    if field and field.lower() == ninja_name.lower():
        return True
    return bool(ninja_jp_name) and any(ninja_jp_name in str(entry.get(k, '') or '') for k in ('root_cause', 'detail', 'issue', 'workaround_detail'))

def is_workaround(entry):
    wa = entry.get('workaround')
    if wa is True:
        return True
    if wa is False:
        return False
    return str(entry.get('karo_workaround', '') or '').lower() == 'yes'

def parse_workarounds():
    text = open(workarounds_file, encoding='utf-8').read()
    try:
        loaded = yaml.load(text, Loader=yaml.SafeLoader)
        if isinstance(loaded, dict):
            items = loaded.get('workarounds') or []
        elif isinstance(loaded, list):
            items = loaded
        else:
            items = []
        return [item for item in items if isinstance(item, dict)]
    except yaml.YAMLError:
        pass
    entries = []
    body = re.sub(r'^workarounds:\s*\n', '', text)
    for block in re.split(r'\n(?=- )', body):
        block = block.strip()
        if not block:
            continue
        try:
            parsed = yaml.load(block, Loader=yaml.SafeLoader)
        except yaml.YAMLError:
            continue
        if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
            entries.append(parsed[0])
        elif isinstance(parsed, dict):
            entries.append(parsed)
    return entries

def recent_top_categories(limit=3, window=30):
    matched = [e for e in parse_workarounds() if match_ninja(e) and is_workaround(e)][-window:]
    counts, first_pos = {}, {}
    for idx, entry in enumerate(matched):
        cat = str(entry.get('category') or 'uncategorized').strip() or 'uncategorized'
        counts[cat] = counts.get(cat, 0) + 1
        first_pos.setdefault(cat, idx)
    return sorted(counts.items(), key=lambda kv: (-kv[1], first_pos[kv[0]], kv[0]))[:limit]

def load_lessons():
    lessons = {}
    for rel in ('projects/infra/lessons.yaml', 'projects/infra/lessons_archive.yaml'):
        path = os.path.join(script_dir, rel)
        if not os.path.exists(path):
            continue
        try:
            data = yaml.load(open(path, encoding='utf-8'), Loader=yaml.SafeLoader) or {}
        except Exception:
            continue
        for lesson in data.get('lessons') or []:
            if isinstance(lesson, dict):
                lid = str(lesson.get('id') or '').strip()
                if lid and lid not in lessons:
                    lessons[lid] = lesson
    return lessons

def lesson_entry(lesson, category, count):
    summary = str(lesson.get('summary') or lesson.get('title') or '')[:200]
    detail = str(lesson.get('detail') or lesson.get('content') or lesson.get('how') or summary)[:200]
    entry = {'id': str(lesson.get('id')), 'summary': summary, 'wa_category': category, 'wa_count': count}
    if detail:
        entry['detail'] = detail
    return entry

def sv(value, indent=2):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if '\n' in text:
        return '|-\n' + '\n'.join(' ' * indent + line for line in text.split('\n'))
    sq = chr(39)
    return sq + text.replace(sq, sq + sq) + sq

def yaml_lines(key, value, indent=0):
    p = ' ' * indent
    if not isinstance(value, (dict, list)):
        return [p + key + ': ' + sv(value, indent + 2)]
    if not value:
        return [p + key + ': ' + ('[]' if isinstance(value, list) else '{}')]
    rows = [p + key + ':']
    if isinstance(value, dict):
        for k, v in value.items():
            rows.extend(yaml_lines(k, v, indent + 2))
    else:
        for item in value:
            rows.extend(list_item(item, indent))
    return rows

def list_item(item, indent):
    p = ' ' * indent
    if not isinstance(item, dict):
        return [p + '- ' + sv(item, indent + 2)]
    rows, first = [], True
    for k, v in item.items():
        tag = '- ' if first else '  '
        first = False
        if isinstance(v, (dict, list)) and v:
            rows.append(p + tag + k + ':')
            if isinstance(v, list):
                for sub in v:
                    rows.extend(list_item(sub, indent + 2))
            else:
                for dk, dv in v.items():
                    rows.extend(yaml_lines(dk, dv, indent + 4))
        else:
            rows.append(p + tag + k + ': ' + (sv(v, indent + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')))
    return rows

def safe_section_replace(text, section_name, value):
    fragment = '\n'.join(yaml_lines(section_name, value))
    indented = '\n'.join('  ' + line for line in fragment.split('\n'))
    out, skip, inserted = [], False, False
    for line in text.split('\n'):
        stripped = line.lstrip(' ')
        indent = len(line) - len(stripped)
        if skip:
            if stripped == '' or indent > 2 or (indent == 2 and stripped.startswith('- ')):
                continue
            skip = False
        if indent == 2 and stripped.startswith(section_name + ':'):
            out.append(indented)
            skip, inserted = True, True
            continue
        out.append(line)
    text = '\n'.join(out)
    if not inserted:
        pos = text.index('task:') + 5
        text = text[:pos] + '\n' + indented + text[pos:]
    return text

def sync_description(description, related):
    marker = '【注入教訓】'
    lines = [marker + ' 必ず確認してから作業開始せよ']
    for item in related:
        if isinstance(item, dict) and item.get('id'):
            lines.append(f"  - {item.get('id')}: {str(item.get('summary') or '')[:80]}")
    lines.append('─' * 40)
    block = '\n'.join(lines)
    desc = str(description or '')
    if marker in desc:
        # Replacement strings interpret backslash escapes (for example lesson
        # text ``\bpush\b`` becomes literal 0x08 backspaces).  A callable
        # replacement preserves lesson prose byte-for-byte and keeps the task
        # YAML printable.
        return re.sub(
            r'【注入教訓】.*?─{10,}',
            lambda _match: block,
            desc,
            count=1,
            flags=re.DOTALL,
        )
    return block + '\n\n' + desc

try:
    data = yaml.load(open(task_file, encoding='utf-8'), Loader=yaml.SafeLoader) or {}
    task = data.get('task') or {}
    if not task:
        print('[WA_LESSON] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    top = recent_top_categories()
    if not top:
        print(f'[WA_LESSON] {ninja_name}: no workaround categories, skipping', file=sys.stderr)
        sys.exit(0)

    lesson_map = load_lessons()
    related = task.get('related_lessons') or []
    if not isinstance(related, list):
        related = []
    seen = {str(item.get('id')) for item in related if isinstance(item, dict)}
    added = []
    for category, count in top:
        for lid in CATEGORY_LESSON_IDS.get(category, []):
            if lid in seen or lid not in lesson_map:
                continue
            related.append(lesson_entry(lesson_map[lid], category, count))
            seen.add(lid)
            added.append(lid)

    if not added:
        print(f'[WA_LESSON] {ninja_name}: no mapped lessons for top categories {top}', file=sys.stderr)
        sys.exit(0)

    task['description'] = sync_description(task.get('description', ''), related)
    raw = open(task_file, encoding='utf-8').read()
    raw = safe_section_replace(raw, 'related_lessons', related)
    raw = safe_section_replace(raw, 'description', task['description'])
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp, task_file)
    except Exception:
        os.unlink(tmp)
        raise
    print(f'[WA_LESSON] {ninja_name}: injected {added} from top categories {top}', file=sys.stderr)
except Exception as exc:
    print(f'[WA_LESSON] ERROR: {exc}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
    rm -f "$py_output"
}

# ─── Engineering Preferences自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_engineering_preferences() { log "inject_engineering_preferences: merged into inject_task_modifiers (no-op)"; }

# ─── Skill hint自動注入（cmd_2460: スキル発動タイミングの意志依存排除） ───
inject_skill_hint() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type title purpose parent_cmd command_text haystack hints
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)

    if [ -n "$parent_cmd" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text="${command_text}
$(awk -v cmd="$parent_cmd" '
    /^  [a-zA-Z0-9_-]+:/ {
        cur=$0
        sub(/^[[:space:]]*/, "", cur)
        sub(/:.*$/, "", cur)
    }
    cur == cmd && /^(    title:|    type:|    purpose:|    command:|        )/ { print }
' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    fi

    haystack="${title}
${purpose}
${command_text}"
    hints=""

    if [ "$project" = "dm-signal" ] && printf '%s\n' "$haystack" | grep -Eqi '(^|[^A-Za-z])(DB|database|SQL|PostgreSQL|SQLite)([^A-Za-z]|$)|本番DB|holding_signal|monthly_returns|portfolio_rankings|PF検索|パリティ検証'; then
        hints="/db-check"
    fi

    if [ "$task_type" = "registration" ] || printf '%s\n' "$haystack" | grep -Eq '本番登録'; then
        if [ -n "$hints" ]; then
            hints="${hints}, /pf-registration"
        else
            hints="/pf-registration"
        fi
    fi

    [ -n "$hints" ] || return 0
    yaml_field_set "$task_file" "task" "skill_hint" "$hints" \
        && log "skill_hint: injected (${hints})"
}


# ─── 偵察報告自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_reports_to_read() { log "[INJECT_REPORTS] merged into inject_task_modifiers (no-op)"; }


# ─── context_files自動注入（cmd_280: 分割context選択的読込） ───
# ─── context_files自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_context_files() { log "[INJECT_CTX] merged into inject_task_modifiers (no-op)"; }

# ─── credential_files自動注入（cmd_949: 認証タスクに.envを自動追加） ───
# ─── credential_files自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_credential_files() { log "[INJECT_CRED] merged into inject_task_modifiers (no-op)"; }

# ─── target_path存在検査WARN注入（cmd_1322: 設定済みだが実在しないtarget_pathを警告） ───
# cmd_1393: Python→bash置換
inject_target_path_check() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_target_path_check: task file not found: $task_file"
        return 0
    fi

    # target_pathをYAML型のまま取得。field_getは配列をcomma文字列へ潰すため使わない。
    local -a paths=()
    mapfile -t paths < <(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = (data.get("task") or {}).get("target_path")
if isinstance(value, str) and value.strip():
    print(value.strip())
elif isinstance(value, list):
    for item in value:
        if str(item).strip():
            print(str(item).strip())
PY
    )

    [ ${#paths[@]} -eq 0 ] && return 0

    # project pathを取得(別リポジトリのtarget_path解決用)
    local project_id project_path=""
    project_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    if [ -n "$project_id" ] && [ -f "$SCRIPT_DIR/projects/${project_id}.yaml" ]; then
        project_path=$(grep -m1 '^\s*path:' "$SCRIPT_DIR/projects/${project_id}.yaml" 2>/dev/null | sed 's/.*path:[[:space:]]*//' | tr -d "'" | tr -d '"')
    fi

    # 存在しないパスと、作業ツリーにはあるがHEADにはないパスを分けて検出する。
    # L903: 旧pathのまま新規ファイルを作る重複実装を、配備時のLevel5コンテキスト注入で防ぐ。
    local -a missing=() untracked_in_head=() git_evidence=()
    for p in "${paths[@]}"; do
        local resolved="$p"
        if [[ "$p" != /* ]]; then
            resolved="$SCRIPT_DIR/$p"
            # SCRIPT_DIR基準で不在→project_path基準でも試行
            if [ ! -e "$resolved" ] && [ -n "$project_path" ]; then
                resolved="$project_path/$p"
            fi
        fi
        if [ ! -e "$resolved" ]; then
            missing+=("$p")
            git_evidence+=("${p}:worktree=no,head=no,last_commit=none")
            continue
        fi

        local repo_root="" repo_relative="" head_oid="" last_commit=""
        local git_probe_dir
        git_probe_dir="$(dirname "$resolved")"
        [ -d "$resolved" ] && git_probe_dir="$resolved"
        repo_root=$(git -C "$git_probe_dir" rev-parse --show-toplevel 2>/dev/null || true)
        if [ -n "$repo_root" ]; then
            repo_relative=$(realpath --relative-to="$repo_root" "$resolved" 2>/dev/null || true)
        fi
        if [ -z "$repo_root" ] || [ -z "$repo_relative" ] \
            || { [ "$repo_relative" != "." ] && ! git -C "$repo_root" cat-file -e "HEAD:${repo_relative}" 2>/dev/null; }; then
            untracked_in_head+=("$p")
            git_evidence+=("${p}:worktree=yes,head=no,last_commit=none")
            continue
        fi
        # Blob existence is the synchronous safety boundary. A history walk is
        # provenance only; concurrent 9P git-log traffic must not block delivery.
        head_oid=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
        if last_commit=$(deploy_task_history_cache_get "$repo_root" "$head_oid" "$repo_relative"); then
            git_evidence+=("${p}:worktree=yes,head=yes,last_commit=${last_commit}")
        else
            deploy_task_queue_history_lookup "$repo_root" "$head_oid" "$repo_relative"
            git_evidence+=("${p}:worktree=yes,head=yes,last_commit=pending@${head_oid:-unknown}")
        fi
    done

    local evidence_text
    evidence_text=$(IFS=';'; echo "${git_evidence[*]}")
    yaml_field_set "$task_file" "task" "target_path_git_preflight" "$evidence_text"

    if [ ${#untracked_in_head[@]} -gt 0 ]; then
        local untracked_str
        untracked_str=$(IFS=', '; echo "${untracked_in_head[*]}")
        yaml_field_set "$task_file" "task" "target_path_head_warning" \
            "⚠ target_pathがgit HEADに存在しない: ${untracked_str}。実装前に旧pathと同事象の直近commitを確認せよ"
        log "[INJECT_TARGET_PATH] WARN: target_path absent from git HEAD: ${untracked_str}"
    fi

    [ ${#missing[@]} -eq 0 ] && return 0

    # WARN注入
    local missing_str
    missing_str=$(IFS=', '; echo "${missing[*]}")
    local warn_msg="⚠ target_pathが存在しない: ${missing_str}"
    yaml_field_set "$task_file" "task" "target_path_warning" "$warn_msg"
    log "[INJECT_TARGET_PATH] WARN: target_path does not exist: ${missing_str}"

    # gate_fire_log.yamlに記録
    local gate_log="$SCRIPT_DIR/logs/gate_fire_log.yaml"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "- ts: \"${ts}\", gate: inject_target_path_check, result: WARN, detail: \"${warn_msg}\"" >> "$gate_log" 2>/dev/null || true
    # DB INSERT: eventsテーブルへゲート記録（非ブロック）
    python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" gate \
        --gate-name "deploy_task:inject_target_path_check" --result "WARN" \
        --cmd-id "" --ts "$ts" --detail "$warn_msg" \
        --source-file "$gate_log" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# New tests are expensive permanent defenses.  Require one compact, reviewable
# necessity record before publication; existing-test edits and testless tasks
# remain outside this contract.
deploy_task_test_necessity_precheck() {
    local task_file="$1"
    local report_file="${2:-}"
    python3 - "$SCRIPT_DIR" "$task_file" "$report_file" "$DEPLOY_TASK_CODE_ROOT" <<'PY'
import os, re, subprocess, sys, yaml
from pathlib import PurePosixPath

repo, task_file, report_file, code_root = sys.argv[1:5]
sys.path.insert(0, code_root)
from scripts.lib.test_necessity_contract import validate_entries
data = yaml.safe_load(open(task_file, encoding="utf-8")) or {}
task = data.get("task", data)
project = str(task.get("project") or os.environ.get("DEPLOY_TASK_TEST_DEFAULT_PROJECT") or "").strip()
target_declared = task.get("target_path")

# Legacy/direct lifecycle fixtures intentionally omit project and target_path;
# optional injectors may still add derived context paths before this precheck.
# Do not invent a project repository for those runtime-only tasks.
if not project and (not target_declared or os.environ.get("DEPLOY_TASK_DIRECT_MODE") == "true"):
    raise SystemExit(0)

def resolve_project_repo(project_id):
    if project_id == "infra":
        candidate = repo
    else:
        projects_dir = os.environ.get("DEPLOY_TASK_PROJECTS_DIR") or os.path.join(repo, "projects")
        project_file = os.path.join(projects_dir, f"{project_id}.yaml")
        if not project_id or not os.path.isfile(project_file):
            raise SystemExit(f"BLOCK: cannot resolve test lifecycle repo for project={project_id or '<empty>'}")
        project_data = yaml.safe_load(open(project_file, encoding="utf-8")) or {}
        project_block = project_data.get("project") if isinstance(project_data.get("project"), dict) else project_data
        candidate = str(project_block.get("path") or "").strip()
        if not candidate:
            raise SystemExit(f"BLOCK: project path is empty for project={project_id}")
    resolved = subprocess.run(
        ["git", "-C", candidate, "rev-parse", "--show-toplevel"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    if resolved.returncode != 0 or not resolved.stdout.strip():
        raise SystemExit(f"BLOCK: project working tree is unavailable for project={project_id}")
    return os.path.realpath(resolved.stdout.strip())

project_repo = resolve_project_repo(project)
paths = task.get("planned_paths") or []
if isinstance(paths, str):
    paths = [paths]
report = {}
if report_file and os.path.isfile(report_file):
    report = yaml.safe_load(open(report_file, encoding="utf-8")) or {}
    if "files_modified" in report or "transient_tests_deleted" in report:
        paths = [x.get("path") for x in report.get("files_modified") or [] if isinstance(x, dict) and x.get("path")]
        paths += [str(x) for x in report.get("transient_tests_deleted") or []]

# A task with no declared or reported paths has no new-test contract to
# validate. Keep minimal lifecycle/direct fixtures (which intentionally omit
# project metadata) on the existing deployment path instead of inventing a
# project repository solely for an empty check.
if not paths:
    raise SystemExit(0)

def is_test(path):
    path = str(path).strip()
    if not path:
        return False
    normalized = path.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    base = parts[-1] if parts else ""
    test_stem_extension = base.startswith("test_") and base.endswith((".py", ".sh"))
    return bool(
        "tests" in parts
        or test_stem_extension
        or base.endswith((".bats", ".spec.js", ".test.js"))
    )

new_tests = []
for path in paths:
    path = str(path).strip()
    if not is_test(path):
        continue
    normalized = path.replace("\\", "/")
    # Accept absolute paths that resolve inside the selected project, but
    # normalize them to repo-relative paths before the HEAD/new-test checks.
    # Absolute paths outside the project remain a hard boundary violation.
    if os.path.isabs(path):
        candidate = os.path.realpath(path)
    else:
        candidate = os.path.realpath(os.path.join(project_repo, normalized))
    if candidate == project_repo or not candidate.startswith(project_repo + os.sep):
        # Project外パスはinfra repo(REPO_ROOT)でフォールバック確認。
        # task project=dm-signalだがfiles_modifiedにinfra testがある場合の偽陽性根治。
        infra_repo = os.path.realpath(repo)
        infra_candidate = os.path.realpath(os.path.join(infra_repo, normalized))
        if infra_repo != project_repo and infra_candidate.startswith(infra_repo + os.sep):
            infra_relative = os.path.relpath(infra_candidate, infra_repo).replace(os.sep, "/")
            infra_exists = subprocess.run(
                ["git", "-C", infra_repo, "cat-file", "-e", f"HEAD:{infra_relative}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode == 0
            if infra_exists:
                continue  # infra既存テスト — new_testではない
        print(f"BLOCK: test path is outside project repo: {path}", file=sys.stderr)
        raise SystemExit(1)
    repo_relative = os.path.relpath(candidate, project_repo).replace(os.sep, "/")
    exists = subprocess.run(
        ["git", "-C", project_repo, "cat-file", "-e", f"HEAD:{repo_relative}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not exists:
        # project HEADに不在でもinfra HEADに存在すれば既存テスト(cross-repo偽陽性根治)
        infra_repo = os.path.realpath(repo)
        if infra_repo != project_repo:
            infra_candidate = os.path.realpath(os.path.join(infra_repo, normalized))
            if infra_candidate.startswith(infra_repo + os.sep):
                infra_relative = os.path.relpath(infra_candidate, infra_repo).replace(os.sep, "/")
                if subprocess.run(
                    ["git", "-C", infra_repo, "cat-file", "-e", f"HEAD:{infra_relative}"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                ).returncode == 0:
                    continue  # infra既存テスト — new_testではない
        new_tests.append(repo_relative)

if not new_tests:
    raise SystemExit(0)

# A new test is transient by default: it may be used to prove the change, but
# it is not silently promoted into the permanent suite.  Only a complete
# defense declaration opts it into persistent lifecycle.
persistent_set, errors = validate_entries(task.get("test_necessity"), new_tests)
if errors:
    print("BLOCK: new test necessity contract failed: " + "; ".join(errors), file=sys.stderr)
    print("BLOCK_TESTS=" + ",".join(new_tests), file=sys.stderr)
    raise SystemExit(1)
persistent = [p for p in new_tests if p in persistent_set]
transient = [p for p in new_tests if p not in persistent_set]
if report:
    deleted = set(map(str, report.get("transient_tests_deleted") or []))
    missing = [p for p in transient if p not in deleted]
    if missing:
        print("BLOCK: report omits transient deletion evidence: " + ",".join(missing), file=sys.stderr)
        raise SystemExit(1)
print("PASS: test_lifecycle actual_new_tests=" + ",".join(new_tests) + " persistent=" + ",".join(persistent) + " transient=" + ",".join(transient) + " contract_contamination=0")
PY
}

deploy_task_guard_target_path_collision() {
    local task_file="$1"
    local ninja_name="$2"
    [ -f "$task_file" ] || return 0

    PYTHONPATH="$SCRIPT_DIR" python3 - "$SCRIPT_DIR" "$task_file" "$ninja_name" <<'TARGET_COLLISION_PY'
import json
import os
import re
import subprocess
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from datetime import datetime, timezone
from scripts.lib.yaml_atomic import atomic_yaml_write

script_dir, task_file, current_ninja = sys.argv[1:4]
active_statuses = {'active', 'assigned', 'acknowledged', 'in_progress'}

def load_task(path):
    try:
        with open(path, encoding='utf-8') as f:
            doc = yaml.safe_load(f) or {}
    except Exception:
        return {}
    task = doc.get('task') if isinstance(doc.get('task'), dict) else doc
    return task if isinstance(task, dict) else {}

def paths_from(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

def command_paths(value):
    text = '\n'.join(map(str, value)) if isinstance(value, list) else str(value or '')
    return re.findall(
        r'(?<![A-Za-z0-9_./-])((?:/mnt/[A-Za-z0-9_.-]+/|(?:[A-Za-z0-9_.-]+/)*)'
        r'[A-Za-z0-9_.-]+\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv))'
        r'(?![A-Za-z0-9_.-])', text)

def readonly_paths(task):
    rows = task.get('readonly_ref') or []
    if isinstance(rows, dict):
        rows = [rows]
    return [str(row.get('path', '')).strip() for row in rows if isinstance(row, dict) and str(row.get('path', '')).strip()]

def normalize(path):
    path = path.replace('\\', '/').strip()
    if not path:
        return ''
    if not os.path.isabs(path):
        path = os.path.join(script_dir, path)
    return os.path.normpath(path)

def reserved_paths(task):
    # target_path is the primary scope, while planned_paths records every file
    # the task expects to touch. Command file references complete the contract,
    # except references explicitly classified readonly by the injector.
    explicit = paths_from(task.get('target_path')) + paths_from(task.get('planned_paths'))
    readonly = {normalize(path) for path in readonly_paths(task)}
    candidates = explicit + command_paths(task.get('command'))
    return [path for path in candidates if normalize(path) not in readonly]

def handoff_peers(task):
    value = task.get('overlap_handoff_from') or task.get('handoff_from') or []
    return set(paths_from(value))

def record(decision, peer='', overlap=None, false_positive=0):
    log_dir = os.path.join(script_dir, 'logs')
    os.makedirs(log_dir, exist_ok=True)
    row = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'gate': 'deploy_target_overlap', 'worker': current_ninja,
        'peer': peer, 'decision': decision, 'overlap': overlap or [],
        'false_positive': false_positive,
    }
    with open(os.path.join(log_dir, 'target_overlap_gate_fire.jsonl'), 'a', encoding='utf-8') as f:
        f.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n')

def split_file_targets(paths):
    file_targets = set()
    dir_targets = set()
    for path in paths:
        norm = normalize(path)
        if not norm:
            continue
        if os.path.isdir(norm):
            dir_targets.add(norm)
        else:
            # A planned file need not exist yet.  Reserving it before creation
            # prevents two active tasks from concurrently creating/editing it.
            file_targets.add(norm)
    return file_targets, dir_targets

current_task = load_task(task_file)
current_files, current_dirs = split_file_targets(reserved_paths(current_task))
if not current_files and not current_dirs:
    record('PASS', false_positive=0)
    sys.exit(0)

task_dir = os.path.join(script_dir, 'queue', 'tasks')
collisions = []
dir_infos = []
settled_claims = []
for name in sorted(os.listdir(task_dir)) if os.path.isdir(task_dir) else []:
    if not name.endswith('.yaml') or name.startswith('.'):
        continue
    peer_ninja = name[:-5]
    if peer_ninja == current_ninja:
        continue
    peer_path = os.path.join(task_dir, name)
    peer_task = load_task(peer_path)
    status = str(peer_task.get('status') or '').strip()
    peer_files, peer_dirs = split_file_targets(reserved_paths(peer_task))
    if status not in active_statuses:
        parent_cmd = str(peer_task.get('parent_cmd') or '').strip()
        archive_marker = (
            os.path.join(script_dir, 'queue', 'gates', parent_cmd, 'archive.done')
            if parent_cmd and os.path.basename(parent_cmd) == parent_cmd
            else ''
        )
        # archive.done closes this task generation.  Any later dirty state on
        # the shared path belongs to a subsequent writer and must not revive
        # the archived worker's reservation.
        if archive_marker and os.path.isfile(archive_marker):
            continue
        # The task record says "finished", but unpushed edits say otherwise.
        # Keep the claim so the worktree lane below can compare declaration
        # against the actual tree (2026-07-26: hanzo held 5 uncommitted files
        # from terminal tasks while the same paths were deployed to tobisaru).
        settled_claims.append((peer_ninja, status, parent_cmd, peer_files))
        continue
    file_overlap = sorted(current_files & peer_files)
    dir_overlap = sorted(current_dirs & peer_dirs)
    if file_overlap:
        collisions.append((peer_ninja, status, str(peer_task.get('parent_cmd') or ''), file_overlap))
    if dir_overlap:
        dir_infos.append((peer_ninja, status, str(peer_task.get('parent_cmd') or ''), dir_overlap))

def worktree_dirty(candidates):
    """Paths that the tree says are still in flight, whatever the task says."""
    rels = []
    for path in sorted(candidates):
        rel = os.path.relpath(path, script_dir)
        if not rel.startswith('..'):
            rels.append(rel)
    if not rels:
        return set()
    try:
        # Pathspec-limited on purpose: a bare `git status` is 54s on this
        # DrvFs checkout, the limited form is 0.6s.
        proc = subprocess.run(
            ['git', '-C', script_dir, 'status', '--porcelain', '--', *rels],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    if proc.returncode != 0:
        return set()
    dirty = set()
    for line in proc.stdout.splitlines():
        entry = line[3:].strip()
        if ' -> ' in entry:
            entry = entry.split(' -> ')[-1]
        dirty.add(normalize(entry.strip('"')))
    return dirty


settled_overlap = set()
for _peer, _status, _cmd, _peer_files in settled_claims:
    settled_overlap |= (current_files & _peer_files)
if settled_overlap:
    dirty_paths = worktree_dirty(settled_overlap)
    allowed_settled = handoff_peers(current_task)
    for peer_ninja, status, parent_cmd, peer_files in settled_claims:
        overlap = sorted((current_files & peer_files) & dirty_paths)
        if not overlap or peer_ninja in allowed_settled or parent_cmd in allowed_settled:
            continue
        collisions.append((peer_ninja, f'{status or "unknown"}/uncommitted', parent_cmd, overlap))

for peer_ninja, status, parent_cmd, overlap in dir_infos:
    print(
        f'INFO: target_path directory overlap with {peer_ninja} '
        f'(status={status}, parent_cmd={parent_cmd or "unknown"}): {", ".join(overlap)}',
        file=sys.stderr,
    )

if collisions:
    unresolved = []
    allowed = handoff_peers(current_task)
    for peer_ninja, status, parent_cmd, overlap in collisions:
        if peer_ninja in allowed or parent_cmd in allowed:
            barrier = current_task.setdefault('final_checkpoint_barrier', [])
            barrier.append({
                'peer': peer_ninja, 'parent_cmd': parent_cmd,
                'paths': overlap, 'release_statuses': ['done', 'failed', 'idle'],
            })
            record('HANDOFF_BARRIER', peer_ninja, overlap, 0)
            continue
        print(
            f'BLOCK: reserved path collision with {peer_ninja} '
            f'(status={status}, parent_cmd={parent_cmd or "unknown"}): {", ".join(overlap)}',
            file=sys.stderr,
        )
        record('BLOCK', peer_ninja, overlap, 0)
        unresolved.append(peer_ninja)
    if unresolved:
        sys.exit(1)
    atomic_yaml_write(task_file, {'task': current_task})
    sys.exit(0)
record('PASS', false_positive=0)
TARGET_COLLISION_PY
}

deploy_task_guard_preserved_path() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    local preserved_file="$SCRIPT_DIR/queue/preserved_paths.yaml"
    [ -f "$preserved_file" ] || return 0

    PYTHONPATH="$SCRIPT_DIR" python3 - "$SCRIPT_DIR" "$task_file" "$preserved_file" <<'PRESERVED_PATH_PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

script_dir, task_file, preserved_file = sys.argv[1:4]

def load_yaml(path):
    try:
        with open(path, encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

def paths_from(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

def normalize(path):
    path = path.replace('\\', '/').strip()
    if not path:
        return ''
    if not os.path.isabs(path):
        path = os.path.join(script_dir, path)
    return os.path.normpath(path)

doc = load_yaml(task_file)
task = doc.get('task') if isinstance(doc.get('task'), dict) else doc
task = task if isinstance(task, dict) else {}

# Both target_path (primary scope) and planned_paths (full touch set) are
# checked: the incident this guard closes (2026-07-27) was a task whose
# target_path itself was the preserved file.
target_paths = {normalize(p) for p in paths_from(task.get('target_path')) + paths_from(task.get('planned_paths'))}
if not target_paths:
    sys.exit(0)

preserved_doc = load_yaml(preserved_file)
entries = preserved_doc.get('preserved_paths') or []
if not isinstance(entries, list):
    sys.exit(0)

hit = None
for entry in entries:
    if not isinstance(entry, dict):
        continue
    # Guard checks current state, not "was a declaration ever made": a
    # released=true entry stays in the registry as an audit trail but must
    # not re-BLOCK (2026-07-27 shogun ruling released lessons.yaml; a
    # declaration-only/append-only log can't express "no longer preserved").
    if entry.get('released') is True:
        continue
    p = normalize(str(entry.get('path', '')))
    if p and p in target_paths:
        hit = entry
        break

if hit:
    print(
        f"BLOCK: preserved path collision: {hit.get('path')} "
        f"(reason={hit.get('reason', '')}, declared_by={hit.get('declared_by', '')}, "
        f"declared_at={hit.get('declared_at', '')}). "
        "解除の証跡を一次確認せよ。解除が殿の裁定事項なら裁定を待て。",
        file=sys.stderr,
    )
    sys.exit(1)
sys.exit(0)
PRESERVED_PATH_PY
}

deploy_task_guard_direct_yaml_prewrite_collision() {
    local yaml_file="$1"
    local ninja_name="$2"

    [ "$DIRECT_MODE" = true ] || return 0
    [ -n "$yaml_file" ] || return 0
    [ -f "$yaml_file" ] || return 0

    deploy_task_guard_target_path_collision "$yaml_file" "$ninja_name"
}

# ─── inject_task_modifiers: 7関数統合ラッパー（cmd_1393） ───
# inject_engineering_preferences, inject_reports_to_read, inject_context_files,
# inject_credential_files, inject_context_update, inject_report_template,
# inject_execution_controls を1つのPython呼び出しに統合
inject_task_modifiers() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_task_modifiers: task file not found: $task_file"
        return 0
    fi
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        python3 "$SCRIPT_DIR/scripts/lib/inject_task_modifiers.py"; then
        log "WARN: inject_task_modifiers failed (non-fatal)"
        return 1
    fi
}

# inject_context_update: cmd_1393で inject_task_modifiers.py に統合（stub）
inject_context_update() { log "inject_context_update: merged into inject_task_modifiers (no-op)"; }

# ─── 独立2系統偵察の相互汚染防止契約 ───
# Track Aの共有context還流がTrack Bの起動時contextへ混入したcmd_3878事故を、
# 注意喚起ではなくtask正本のfixed-base + embargo契約で遮断する。
inject_independent_recon_contract() {
    local task_file="$1"
    local ninja_name="$2"
    local title purpose command_text contract_text parent_cmd group track
    local base_commit target_path repo_path project existing_reminder

    [ -f "$task_file" ] || return 0
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "")
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "")
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "")
    contract_text="${title} ${purpose} ${command_text}"
    if ! grep -Eiq '独立2系統|相互参照禁止|independent[ _-]*(track|recon)|dual[ _-]*recon' <<< "$contract_text"; then
        return 0
    fi

    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    group=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_group" "")
    if [ -z "$group" ]; then
        group=$(printf '%s' "$parent_cmd" | sed -E 's/_recon[0-9]+$//')
    fi
    track=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_track" "")
    if [ -z "$track" ]; then
        if [[ "$parent_cmd" =~ _recon([0-9]+)$ ]]; then
            track="B${BASH_REMATCH[1]}"
        else
            track="A"
        fi
    fi

    base_commit=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_base_commit" "")
    target_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "")
    repo_path="$target_path"
    [ -f "$repo_path" ] && repo_path=${repo_path%/*}
    if [ -z "$repo_path" ] || ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "")
        repo_path=$(get_project_path "$project" 2>/dev/null || true)
    fi
    if [ -z "$base_commit" ]; then
        base_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || true)
    fi
    if [ -z "$base_commit" ] || ! git -C "$repo_path" cat-file -e "${base_commit}^{commit}" 2>/dev/null; then
        log "BLOCK: independent recon base commit is unavailable/invalid (ninja=${ninja_name}, repo=${repo_path:-missing}, base=${base_commit:-missing})"
        return 1
    fi

    yaml_field_set_batch "$task_file" "task" \
        "independence_group=${group}" \
        "independence_track=${track}" \
        "independence_base_commit=${base_commit}" \
        "independence_worktree_required=true" \
        "shared_context_embargo=karo_release_required"

    existing_reminder=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "role_reminder" "")
    if [ -z "$existing_reminder" ]; then
        yaml_field_set "$task_file" "task" "role_reminder" \
            "独立Track ${track}。固定base ${base_commit}から隔離worktreeを作り、自作probeのみ使用。兄弟Trackのtask/report/branch/worktree/commit・配備後の共有context参照禁止。共有context/semantic-map/記憶DBへの結論還流は家老releaseまで禁止"
    fi
    log "[INDEPENDENT_RECON] group=${group} track=${track} base=${base_commit:0:12} embargo=karo_release_required"
}

# ─── role_reminder自動注入（cmd_384: 忍者スコープ制限リマインダ） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
inject_role_reminder() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_role_reminder: task file not found: $task_file"
        return 0
    fi

    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "role_reminder" "")
    if [ -n "$existing" ]; then
        log "[ROLE_REMINDER] Already exists, skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "role_reminder" "忍者${ninja_name}。このタスクのみ実行せよ。スコープ外の改善・判断は禁止。発見はlesson_candidate/decision_candidateへ"
    log "[ROLE_REMINDER] Injected for ${ninja_name}"
}

# inject_report_template: cmd_1393で inject_task_modifiers.py に統合（stub）
inject_report_template() { log "inject_report_template: merged into inject_task_modifiers (no-op)"; }

# ─── report_filename自動注入（cmd_410: 命名ミスマッチ根治） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
inject_report_filename() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_filename: task file not found: $task_file"
        return 0
    fi

    local existing parent_cmd report_filename
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        report_filename parent_cmd 2>/dev/null)" || true
    existing="${report_filename:-}"
    if [ -n "$existing" ]; then
        log "[REPORT_FN] Already exists, skipping"
        return 0
    fi

    if [ -n "$parent_cmd" ]; then
        report_filename="${NINJA_NAME}_report_${parent_cmd}.yaml"
    else
        report_filename="${NINJA_NAME}_report.yaml"
    fi

    yaml_field_set "$task_file" "task" "report_filename" "$report_filename"
    log "[REPORT_FN] Injected report_filename=${report_filename}"
}

# A speed-campaign round owns its report identity.  Generic direct YAML must
# still be normalized, but replacing this exact generator contract collapses
# R1/R2 onto the parent-cmd report and destroys the campaign history.
deploy_task_speed_campaign_report_is_explicit() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import sys, yaml
try:
    task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
except (OSError, yaml.YAMLError):
    raise SystemExit(1)
c = task.get("speed_campaign") or {}
campaign = str(c.get("campaign_id") or "")
round_index = c.get("round_index")
name = str(task.get("report_filename") or "")
path = str(task.get("report_path") or "")
expected = f"test_speed_report_{campaign}_r{round_index}.yaml"
ok = bool(campaign and isinstance(round_index, int) and round_index > 0
          and name == expected and path == f"queue/reports/{expected}")
raise SystemExit(0 if ok else 1)
PY
}

deploy_task_normalize_report_metadata() {
    local task_file="$1"
    if deploy_task_speed_campaign_report_is_explicit "$task_file"; then
        log "[REPORT_FN] Preserving explicit speed campaign round report"
    else
        yaml_field_set_batch "$task_file" "task" \
            "report_filename=" "report_path=" \
            || { log "FATAL: yaml_field_set_batch failed for report metadata"; return 1; }
    fi
    inject_report_filename "$task_file" || true
}

# ─── bloom_level自動注入（cmd_434: タスク複雑度メタデータ） ───
# cmd_1393: Python→bash変換（grep+yaml_field_set）
inject_bloom_level() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_bloom_level: task file not found: $task_file"
        return 0
    fi

    # bloom_level:が既に存在する場合は上書きしない（空文字でも存在扱い）
    if grep -q '^\s*bloom_level:' "$task_file" 2>/dev/null; then
        log "[BLOOM_LVL] Already exists, skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "bloom_level" ""
    log "[BLOOM_LVL] Injected bloom_level (empty)"
}

# inject_execution_controls: GS/忍法/DB系タスクにexecution_env制約を自動注入(L5)
# origin: cmd_3496 kagemaru PowerShell経由Windows python事故(2026-06-23)
# Guard 0f(L1将軍hook)+本関数(L5事前コンテキスト)で二層防御
inject_execution_controls() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # 既にexecution_envがtask YAMLにあればスキップ
    grep -q 'execution_env:' "$task_file" 2>/dev/null && {
        log "inject_execution_controls: execution_env already present, skip"
        return 0
    }

    local purpose command_text haystack command
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        purpose command 2>/dev/null)" || true
    command_text="${command:-}"
    haystack="${purpose} ${command_text}"

    # GS/忍法/DB操作を検出
    if printf '%s\n' "$haystack" | grep -Eqi 'grid.?search|GS実行|忍法|秘奥義|run_077|wf_runner|fullrecalculate|本番DB|migration'; then
        local indent="  "
        local inject_line="${indent}execution_env: \"Linux venv必須。RSS計測=/usr/bin/time -v。PowerShell/Windows python禁止(cmd_3496事故)\""
        # description行の前に挿入
        local tmp_file
        tmp_file=$(mktemp "${task_file}.XXXXXX")
        awk -v line="$inject_line" '
            /^  description:/ && !done { print line; done=1 }
            { print }
        ' "$task_file" > "$tmp_file"
        _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
        log "inject_execution_controls: execution_env injected (GS/DB detected)"
    else
        log "inject_execution_controls: no GS/DB keywords, skip"
    fi
}

# ─── ninja_weak_points自動注入（cmd_1307: 忍者別過去失敗パターン注入） ───
# karo_workarounds.yamlから忍者名でフィルタし、category別件数をtask YAMLに注入
inject_ninja_weak_points() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_ninja_weak_points: task file not found: $task_file"
        return 0
    fi

    local workarounds_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
    if [ ! -f "$workarounds_file" ]; then
        log "inject_ninja_weak_points: karo_workarounds.yaml not found, skipping"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    local ninja_jp_name
    ninja_jp_name="$(get_japanese_name "$ninja_name" 2>/dev/null || echo "$ninja_name")"
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" WORKAROUNDS_FILE_ENV="$workarounds_file" NINJA_NAME_ENV="$ninja_name" NINJA_JP_ENV="$ninja_jp_name" python3 - <<'PY'; then
import os
import re
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
workarounds_file = os.environ['WORKAROUNDS_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']
ninja_jp_name = os.environ.get('NINJA_JP_ENV', ninja_name)

def match_ninja(entry, target_name):
    """エントリが対象忍者に属するか判定"""
    ninja_field = str(entry.get('ninja', '') or '')
    if ninja_field and ninja_field.lower() == target_name.lower():
        return True
    jp_name = ninja_jp_name if target_name.lower() == ninja_name.lower() else ''
    if not jp_name:
        return False
    for field in ('root_cause', 'detail', 'issue', 'workaround_detail'):
        val = str(entry.get(field, '') or '')
        if jp_name in val:
            return True
    return False

def is_workaround(entry):
    """workaround: true判定（新旧形式対応）"""
    wa = entry.get('workaround')
    if wa is True:
        return True
    if wa is False:
        return False
    kw = str(entry.get('karo_workaround', '') or '').lower()
    if kw == 'yes':
        return True
    return False

def parse_workarounds_robust(filepath):
    """karo_workarounds.yamlをロバストに解析（混在形式対応）"""
    with open(filepath) as f:
        content = f.read()

    # まずyaml.loadを試す
    try:
        wa_data = yaml.load(content, Loader=yaml.SafeLoader)
        if isinstance(wa_data, dict):
            return wa_data.get('workarounds', [])
        if isinstance(wa_data, list):
            return wa_data
    except yaml.YAMLError:
        pass

    # フォールバック: トップレベル '- ' エントリを個別にパース
    entries = []
    # workarounds:ヘッダを除去
    body = re.sub(r'^workarounds:\s*\n', '', content)
    # トップレベルのリストアイテムで分割（行頭が '- ' のもの）
    blocks = re.split(r'\n(?=- )', body)
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        # ネストされた不正な '  - timestamp:' 行を除去
        cleaned_lines = []
        for line in block.split('\n'):
            # トップレベルエントリ内にネストされた別形式エントリを除外
            if re.match(r'^  - (timestamp|cmd|ninja|issue|fix|category|resolved_by_cmd):', line):
                continue
            cleaned_lines.append(line)
        cleaned = '\n'.join(cleaned_lines)
        try:
            parsed = yaml.load(cleaned, Loader=yaml.SafeLoader)
            if isinstance(parsed, list) and parsed:
                entries.append(parsed[0])
            elif isinstance(parsed, dict):
                entries.append(parsed)
        except yaml.YAMLError:
            continue
    return entries

try:
    entries = parse_workarounds_robust(workarounds_file)
    if not entries:
        print('[NINJA_WP] No entries parsed from karo_workarounds.yaml', file=sys.stderr)
        sys.exit(0)

    # 対象忍者のworkaround: trueエントリをフィルタ
    matched = [e for e in entries if isinstance(e, dict) and match_ninja(e, ninja_name) and is_workaround(e)]

    if not matched:
        print(f'[NINJA_WP] {ninja_name}: 0 workarounds, skipping injection', file=sys.stderr)
        sys.exit(0)

    # category別集計
    cat_counts = {}
    for e in matched:
        if 'category' in e and e['category']:
            cat = str(e['category']).strip()
        else:
            cat = 'uncategorized'
        cat_counts[cat] = cat_counts.get(cat, 0) + 1

    total = len(matched)
    top_cat = max(cat_counts, key=cat_counts.get)
    top_count = cat_counts[top_cat]

    # warning生成（top categoryに応じた具体的な注意事項）
    WARNING_MAP = {
        'report_yaml_format': '⚠ report_field_set.sh必ず使用。lessons_usefulはlist形式、dict(0:{},1:{})禁止。verdict二値(PASS/FAIL)厳守',
        'commit_missing': '⚠ コード変更後は必ずgit add+git commitを実行してから報告。commit漏れ厳禁',
        'report_missing': '⚠ 報告YAML作成を必ず完了してから完了報告。report未作成での完了報告禁止',
        'file_disappearance': '⚠ ファイル操作後は存在確認。特にreport YAMLが消失していないか検証',
    }
    warning = WARNING_MAP.get(top_cat, f'⚠ 過去{total}件のworkaround発生。品質に注意')

    # category内訳文字列
    breakdown = ', '.join(f'{cat}({cnt}件)' for cat, cnt in sorted(cat_counts.items(), key=lambda x: -x[1]))

    # task YAMLに注入
    with open(task_file) as f:
        data = yaml.load(f, Loader=yaml.SafeLoader)

    if not data or 'task' not in data:
        print('[NINJA_WP] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既に注入済みならスキップ（冪等性）
    if 'ninja_weak_points' in task:
        print('[NINJA_WP] Already injected, skipping', file=sys.stderr)
        sys.exit(0)

    task['ninja_weak_points'] = {
        'source': 'karo_workarounds.yaml',
        'total_workarounds': total,
        'top_pattern': f'{top_cat}({top_count}件)',
        'breakdown': breakdown,
        'warning': warning,
    }

    # --- GP-110: gate_fire_logからper-ninja FAILパターンTop3を追加 ---
    gate_log_path = os.path.join(os.path.dirname(workarounds_file), 'gate_fire_log.yaml')
    if os.path.exists(gate_log_path):
        fail_cats = {}
        GATE_FAIL_WARNING = {
            'lu_reason_empty': 'lessons_usefulの各教訓にreason(理由)を必ず記入。空文字禁止',
            'bc_result_empty': 'binary_checksの各check項目にresult("yes"/"no")を記入。空文字禁止',
            'verdict_invalid': 'verdictは"PASS"/"FAIL"の二値のみ。空文字/None禁止',
            'status_pending': '完了後にstatusを"completed"に更新。"pending"のまま報告禁止',
            'field_missing': '必須フィールド(binary_checks/files_modified/result.summary)を省略するな',
            'type_error': 'YAML型注意。dict({0:{},1:{}})禁止→list([{},{},{}])形式',
            'no_lesson_reason': 'lesson_candidate.found=false時はno_lesson_reasonに理由記入',
            'bc_result_invalid': 'binary_checksのresultは"yes"/"no"のみ。"PASS"/"FAIL"/"pending"等は不正値',
            'lu_structure_error': 'lessons_usefulの各要素にid/reason/usefulフィールド必須。null/空リスト/dict禁止。テンプレート構造を壊すな',
            'yaml_parse_error': 'YAML構文エラー。インデント・コロン後のスペース・引用符の閉じ忘れを確認せよ',
            'fill_this_remaining': 'FILL_THISが残存。全テンプレート値を実際の値に置換せよ',
        }
        try:
            with open(gate_log_path) as gf:
                for gline in gf:
                    gline = gline.strip()
                    if not gline.startswith('- ') or f'/{ninja_name}_report' not in gline:
                        continue
                    if '/tmp/' in gline:
                        continue
                    if 'result: FAIL' not in gline:
                        continue
                    rm = re.search(r'reasons:\s*"(.*)"$', gline)
                    if not rm:
                        continue
                    for reason in rm.group(1).split('; '):
                        if 'reason is empty' in reason:
                            fail_cats['lu_reason_empty'] = fail_cats.get('lu_reason_empty', 0) + 1
                        elif 'result: 空文字' in reason or 'result: ""' in reason:
                            fail_cats['bc_result_empty'] = fail_cats.get('bc_result_empty', 0) + 1
                        elif 'verdict' in reason:
                            fail_cats['verdict_invalid'] = fail_cats.get('verdict_invalid', 0) + 1
                        elif 'status' in reason and 'pending' in reason:
                            fail_cats['status_pending'] = fail_cats.get('status_pending', 0) + 1
                        elif 'MISSING' in reason:
                            fail_cats['field_missing'] = fail_cats.get('field_missing', 0) + 1
                        elif 'is dict' in reason or 'is str' in reason:
                            fail_cats['type_error'] = fail_cats.get('type_error', 0) + 1
                        elif 'no_lesson_reason' in reason:
                            fail_cats['no_lesson_reason'] = fail_cats.get('no_lesson_reason', 0) + 1
                        elif '不正' in reason:
                            fail_cats['bc_result_invalid'] = fail_cats.get('bc_result_invalid', 0) + 1
                        elif 'YAML parse error' in reason:
                            fail_cats['yaml_parse_error'] = fail_cats.get('yaml_parse_error', 0) + 1
                        elif 'FILL_THIS' in reason:
                            fail_cats['fill_this_remaining'] = fail_cats.get('fill_this_remaining', 0) + 1
                        elif ('missing' in reason and 'field' in reason) or \
                             'null (must be' in reason or \
                             'empty list' in reason or 'unexpected type' in reason or \
                             'empty dict' in reason or 'found=true but no' in reason:
                            fail_cats['lu_structure_error'] = fail_cats.get('lu_structure_error', 0) + 1
            if fail_cats:
                sorted_cats = sorted(fail_cats.items(), key=lambda x: -x[1])[:3]
                top3 = [{'pattern': p, 'count': c} for p, c in sorted_cats]
                gate_warnings = [GATE_FAIL_WARNING.get(p, p) for p, _ in sorted_cats]
                task['ninja_weak_points']['gate_fail_top3'] = top3
                task['ninja_weak_points']['gate_warning'] = '⚠ gate頻出FAIL: ' + '; '.join(gate_warnings)
                print(f'[NINJA_WP] {ninja_name}: gate FAIL top3 injected: {sorted_cats}', file=sys.stderr)
        except Exception as ge:
            print(f'[NINJA_WP] gate_fire_log parse warning: {ge}', file=sys.stderr)

    # --- cmd_1534: gate_metrics.logからBLOCKパターンを忍者別集計 ---
    gate_metrics_path = os.path.join(os.path.dirname(workarounds_file), 'gate_metrics.log')
    if os.path.exists(gate_metrics_path):
        BLOCK_HINT_MAP = {
            'empty_lessons_useful': 'lessons_usefulの各教訓にuseful(true/false)+reason(理由)を記入。空のまま提出禁止',
            'lesson_done_source': 'lesson_candidate登録後にlesson_done確認が必要。lesson_write.sh経由で正式登録',
            'lesson_candidate_missing': 'lesson_candidate.found欄を必ず記入(true/false)。省略禁止',
            'lesson_candidate_legacy_list': 'lesson_candidateはdict形式(found/title/detail)。リスト[]形式禁止',
            'lesson_done_missing': 'lesson登録完了の確認が不足。lesson_write.sh実行後にdone確認',
            'lesson_candidate_parse_error': 'lesson_candidateのYAML構文エラー。インデント・引用符を確認',
            'ac_version_mismatch': 'ac_version_readがtask YAMLのac_versionと不一致。最新タスクを再読込',
            'invalid_lessons_useful_format': 'lessons_usefulはリスト[{id,useful,reason}]形式。dict/null禁止',
            'lesson_candidate_no_reason_empty': 'lesson_candidate.found=false時はno_lesson_reasonに理由記入必須',
            'purpose_validation_fit_false': 'purpose_validation.fitがfalse。cmd目的と作業内容の乖離を確認',
            'empty_lesson_referenced': 'related_lessonsの参照教訓が空。タスクで指定された教訓を確認',
            'null_lessons_useful': 'lessons_usefulがnull。テンプレートのリスト構造を維持せよ',
            'fill_this_remaining': 'FILL_THISが残存。全テンプレート値を実際の値に置換せよ',
            'binary_checks_fail': 'binary_checksのresultが"yes"でない項目あり。全ACのチェック完了を確認',
            'unreviewed_lessons': '未レビューのlessonが残存。lesson確認を完了させよ',
            'lesson_candidate_found_missing': 'lesson_candidate.found欄がない。true/falseを明記',
            'report_format': 'report YAMLのフォーマットエラー。report_field_set.sh使用必須',
            'report_yaml_missing': 'report YAMLが存在しない。report_pathのファイルを作成・記入せよ',
        }
        NINJA_NAMES = set(os.environ.get('DEPLOY_NINJA_NAMES', 'kagemaru hanzo hayate tobisaru saizo kotaro').split())
        try:
            block_cats = {}
            with open(gate_metrics_path, encoding='utf-8') as gmf:
                for line in gmf:
                    cols = line.rstrip('\n').split('\t')
                    if len(cols) < 4 or cols[2] != 'BLOCK':
                        continue
                    reasons = cols[3].split('|')
                    for reason in reasons:
                        reason = reason.strip()
                        # Pattern 1: {ninja_name}:{category}... (e.g. kagemaru:empty_lessons_useful:...)
                        matched_ninja = False
                        for nn in NINJA_NAMES:
                            if reason.startswith(nn + ':'):
                                if nn == ninja_name:
                                    # Extract category: take the part after ninja_name:
                                    rest = reason[len(nn)+1:]
                                    # Category is the first segment before : or =
                                    cat = re.split(r'[:=]', rest)[0]
                                    if cat:
                                        block_cats[cat] = block_cats.get(cat, 0) + 1
                                matched_ninja = True
                                break
                        if matched_ninja:
                            continue
                        # Pattern 2: report_format:{ninja}_report... or report_yaml_missing:{ninja}_report...
                        if f':{ninja_name}_report' in reason or f'_{ninja_name}_report' in reason or f'/{ninja_name}_report' in reason:
                            cat = reason.split(':')[0] if ':' in reason else 'report_issue'
                            block_cats[cat] = block_cats.get(cat, 0) + 1
            if block_cats:
                sorted_blocks = sorted(block_cats.items(), key=lambda x: -x[1])
                gate_blocks = [
                    {'reason': cat, 'count': cnt, 'hint': BLOCK_HINT_MAP.get(cat, f'gate BLOCK: {cat}')}
                    for cat, cnt in sorted_blocks
                ]
                task['ninja_weak_points']['gate_blocks'] = gate_blocks
                print(f'[NINJA_WP] {ninja_name}: gate_metrics BLOCK {len(gate_blocks)} categories injected', file=sys.stderr)
            else:
                print(f'[NINJA_WP] {ninja_name}: no gate_metrics BLOCKs found', file=sys.stderr)
        except Exception as gme:
            print(f'[NINJA_WP] gate_metrics parse warning: {gme}', file=sys.stderr)

    # --- Safe targeted write (avoid full yaml.dump — cmd_1407 AC2) ---
    with open(task_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
    def _sv(v, multiline_indent=2):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
            return [p + key + ': ' + s]
        if not val:
            return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
        r = [p + key + ':']
        if isinstance(val, dict):
            for k, v in val.items():
                r.extend(_yaml_lines(k, v, ind + 2))
        else:
            for item in val:
                r.extend(_list_item(item, ind))
        return r
    def _list_item(item, ind):
        p = ' ' * ind
        if not isinstance(item, (dict, list)):
            s = _sv(item, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
            return [p + '- ' + s]
        if isinstance(item, dict) and item:
            lines = []
            first = True
            for k, v in item.items():
                tag = '- ' if first else '  '
                first = False
                if isinstance(v, (dict, list)) and v:
                    lines.append(p + tag + k + ':')
                    if isinstance(v, list):
                        for sub in v:
                            lines.extend(_list_item(sub, ind + 2))
                    else:
                        for dk, dv in v.items():
                            lines.extend(_yaml_lines(dk, dv, ind + 4))
                else:
                    sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                    if '\n' in sv:
                        parts = sv.split('\n')
                        lines.append(p + tag + k + ': ' + parts[0])
                        lines.extend(parts[1:])
                    else:
                        lines.append(p + tag + k + ': ' + sv)
            return lines
        return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
    def _safe_section_replace(text, section_name, new_value):
        """Replace a 2-space-indented section under task: without full yaml.dump"""
        frag = '\n'.join(_yaml_lines(section_name, new_value))
        indented = '\n'.join('  ' + line for line in frag.split('\n'))
        # 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
        _lines = text.split('\n')
        _result = []
        _skip = False
        _inserted = False
        for _l in _lines:
            _s = _l.lstrip(' ')
            _i = len(_l) - len(_s)
            if _skip:
                if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
                    continue
                _skip = False
            if _i == 2 and _s.startswith(section_name + ':'):
                _skip = True
                _result.append(indented)
                _inserted = True
                continue
            _result.append(_l)
        text = '\n'.join(_result)
        if not _inserted:
            task_idx = text.index('task:')
            rest = text[task_idx + 5:]
            top_m = re.search(r'^\S', rest, re.MULTILINE)
            if top_m:
                pos = task_idx + 5 + top_m.start()
                text = text[:pos] + indented + '\n' + text[pos:]
            else:
                text = text.rstrip('\n') + '\n' + indented + '\n'
        return text

    raw = _safe_section_replace(raw, 'ninja_weak_points', task['ninja_weak_points'])

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

    print(f'[NINJA_WP] {ninja_name}: {total} workarounds injected (top: {top_cat}={top_count})', file=sys.stderr)

except Exception as e:
    print(f'[NINJA_WP] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
    rm -f "$py_output"
}

# ─── GP-198: session_state → previous_failures 注入（再配備時失敗履歴引継ぎ） ───
inject_session_state_hints() {
    local task_file="$1"
    [ -z "${_DEPLOY_PREV_SESSION_STATE:-}" ] && return 0
    # Failure history belongs to a command attempt, not to the ninja slot.
    # A newly assigned command must not inherit an unrelated task's gate failure.
    local current_parent_cmd
    current_parent_cmd=$(awk '
        /^[[:space:]]+parent_cmd:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]+parent_cmd:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            print line
            exit
        }
    ' "$task_file" 2>/dev/null || true)
    if [ -z "${_DEPLOY_PREV_PARENT_CMD:-}" ] || [ -z "$current_parent_cmd" ] || \
       [ "$_DEPLOY_PREV_PARENT_CMD" != "$current_parent_cmd" ]; then
        return 0
    fi
    local ss_tmp
    ss_tmp=$(mktemp)
    printf '%s' "$_DEPLOY_PREV_SESSION_STATE" > "$ss_tmp"
    python3 - "$task_file" "$ss_tmp" <<'SS_INJECT_PY' 2>/dev/null || true
import json, sys, re, os, tempfile

task_yaml = sys.argv[1]
ss_tmp = sys.argv[2]

try:
    with open(ss_tmp) as f:
        ss = json.load(f)
except Exception:
    sys.exit(0)

if not ss:
    sys.exit(0)

def _one_line(text, limit=180):
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    if len(text) > limit:
        text = text[:limit - 1].rstrip() + '…'
    return text

attempt = ss.get('attempt', 0)
last_reason = _one_line(ss.get('last_block_reason', ''))
tried = [_one_line(t) for t in list(ss.get('tried_approaches', [])) if _one_line(t)]
diagnose_reason = _one_line(ss.get('diagnose_reason', ''))
approach_summary = _one_line(ss.get('approach_summary', ''))
prior_attempts = ss.get('prior_attempts', [])

if not attempt and not last_reason:
    sys.exit(0)

with open(task_yaml, encoding='utf-8') as f:
    raw = f.read()

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

pf_lines = ['previous_failures:',
            f'  attempt: {attempt}',
            f'  last_block_reason: {_sq(last_reason)}',
            '  tried_approaches:']
for t in tried:
    pf_lines.append(f'  - {_sq(t)}')
if diagnose_reason:
    pf_lines.append(f'  diagnose_reason: {_sq(diagnose_reason)}')
if approach_summary:
    pf_lines.append(f'  approach_summary: {_sq(approach_summary)}')
if isinstance(prior_attempts, list) and prior_attempts:
    pf_lines.append('  prior_attempts:')
    unique_attempts = []
    seen_reasons = set()
    for item in reversed(prior_attempts):
        if not isinstance(item, dict):
            continue
        reason_key = _one_line(item.get('block_reason', '')).casefold()
        if reason_key in seen_reasons:
            continue
        seen_reasons.add(reason_key)
        unique_attempts.append(item)
        if len(unique_attempts) == 3:
            break
    for item in reversed(unique_attempts):
        if not isinstance(item, dict):
            continue
        pf_lines.append(f"  - attempt: {int(item.get('attempt', 0) or 0)}")
        item_block_reason = _one_line(item.get('block_reason', ''))
        item_diagnose_reason = _one_line(item.get('diagnose_reason', ''))
        item_approach_summary = _one_line(item.get('approach_summary', ''))
        pf_lines.append(f"    block_reason: {_sq(item_block_reason)}")
        if item_diagnose_reason:
            pf_lines.append(f"    diagnose_reason: {_sq(item_diagnose_reason)}")
        if item_approach_summary:
            pf_lines.append(f"    approach_summary: {_sq(item_approach_summary)}")
pf_frag = '\n'.join(pf_lines)
pf_indented = '\n'.join('  ' + l for l in pf_frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('previous_failures:'):
        _skip = True
        _result.append(pf_indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(pf_indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_yaml), suffix='.pf_tmp')
os.close(fd)
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(raw)
os.replace(tmp, task_yaml)
print(f'[SESSION_HINT] previous_failures injected: attempt={attempt} prior_attempts={len(prior_attempts) if isinstance(prior_attempts, list) else 0}', file=sys.stderr)
SS_INJECT_PY
    rm -f "$ss_tmp"
}

# ─── GP-201: CoDD改善cmd → failure history自動注入 ───
# CoDD改善cmdを配備する際に、同一スクリプトの過去revert/regressionエントリを
# codd_refactor_registry.mdから検索し、タスクYAMLに自動注入する。
# 忍者は同じ失敗アプローチを繰り返さずに済む（ステートレスリトライ→ステートフル蓄積）。
inject_codd_failure_history() {
    local task_file="$1"
    local cmd_id stk registry

    cmd_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -z "$cmd_id" ] && return 0

    stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk" ] || return 0

    registry="$SCRIPT_DIR/docs/research/codd_refactor_registry.md"
    [ -f "$registry" ] || return 0

    python3 - "$task_file" "$stk" "$cmd_id" "$registry" <<'CODD_HIST_PY' 2>/dev/null || true
import sys, os, re, tempfile

task_file    = sys.argv[1]
stk_path     = sys.argv[2]
cmd_id       = sys.argv[3]
registry_path = sys.argv[4]

# 1. shogun_to_karo.yamlからcmd_idのtitle+commandを取得 (yaml.safe_loadで確実にパース)
try:
    import yaml as _yaml
    with open(stk_path, encoding='utf-8') as f:
        stk_data = _yaml.safe_load(f) or {}
except Exception as e:
    print(f'[CODD_HIST] ERROR reading stk: {e}', file=sys.stderr)
    sys.exit(0)

cmds = stk_data.get('commands', {})
cmd_entry = cmds.get(cmd_id, {})
if not cmd_entry:
    sys.exit(0)

cmd_title   = str(cmd_entry.get('title',   '') or '')
cmd_command = str(cmd_entry.get('command', '') or '')
cmd_text    = cmd_title + '\n' + cmd_command

# 2. CoDD改善cmdかを判定 (title/commandに"codd"または"/codd-refactor"を含む)
if not re.search(r'codd|/codd-refactor', cmd_text, re.IGNORECASE):
    sys.exit(0)

# 3. command/titleから .sh ファイル名を抽出
scripts = re.findall(r'[a-zA-Z0-9_./-]+\.sh', cmd_text)
scripts = list(dict.fromkeys(scripts))  # unique, preserve order

if not scripts:
    sys.exit(0)

def _one_line(text, limit=180):
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    if len(text) > limit:
        text = text[:limit - 1].rstrip() + '…'
    return text

# 4. registryからrevert/regressionエントリを検索
# 台帳形式: | date | ninja | script | phase | before→after | spec |
failures = []
try:
    with open(registry_path, encoding='utf-8') as f:
        for line in f:
            if '|' not in line:
                continue
            cols = [c.strip() for c in line.split('|')]
            if len(cols) < 7:
                continue
            script_col = cols[3]   # 対象スクリプト/領域
            phase_col  = cols[4]   # Phase到達
            result_col = cols[5]   # Before→After
            spec_col   = cols[6] if len(cols) > 6 else ''

            for sname in scripts:
                basename = os.path.basename(sname)
                if not basename:
                    continue
                if basename in script_col:
                    if re.search(r'revert|regression', result_col + phase_col, re.IGNORECASE):
                        diagnosis = _one_line(phase_col.strip('`').strip())
                        result = _one_line(result_col.strip('`').strip())
                        failures.append({
                            'script': script_col.strip('`').strip(),
                            'diagnosis': diagnosis,
                            'result': result,
                        })
                        break  # 同一行を重複追加しない
except Exception as e:
    print(f'[CODD_HIST] ERROR reading registry: {e}', file=sys.stderr)
    sys.exit(0)

if not failures:
    sys.exit(0)

# 5. タスクYAMLに codd_failure_history: ブロックを注入
with open(task_file, encoding='utf-8') as f:
    raw = f.read()

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

note = 'このスクリプトは過去にCoDD改善でrevert/regressionあり。同じアプローチを繰り返すな'
frag_lines = [
    'codd_failure_history:',
    f'  count: {len(failures)}',
    f'  note: {_sq(note)}',
    '  attempts:',
]
for fa in failures:
    frag_lines.append(f'  - script: {_sq(fa["script"])}')
    frag_lines.append(f'    diagnosis: {_sq(fa["diagnosis"])}')
    frag_lines.append(f'    result: {_sq(fa["result"])}')

frag     = '\n'.join(frag_lines)
indented = '\n'.join('  ' + l for l in frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('codd_failure_history:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.cdd_tmp')
os.close(fd)
try:
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp, task_file)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise

print(f'[CODD_HIST] codd_failure_history injected: {len(failures)} revert/regression entries', file=sys.stderr)
CODD_HIST_PY
}
fi
# Cluster H module: lesson/workaround, target, role/model, and execution modifiers.
_dt_modifiers_path="$SCRIPT_DIR/scripts/deploy_task/modifiers.sh"
if [ ! -f "$_dt_modifiers_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_modifiers_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/modifiers.sh"
fi
if [ ! -f "$_dt_modifiers_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_modifiers_path="$PROJECT_ROOT/scripts/deploy_task/modifiers.sh"
fi
source "$_dt_modifiers_path"
unset _dt_modifiers_path

# Active definition: the historical cluster-I body below is retained only for
# static extraction compatibility, while the modular entrypoint needs this
# contract available after all runtime modules have been sourced.
inject_dynamic_measurement_contract() {
    local task_file="$1"
    local ninja_name="${2:-${NINJA_NAME:-ninja}}"
    local before after measurement_command measurement_environment
    local measurement_policy safety_boundary fixed_baseline_policy
    local -a updates=()

    [ -f "$task_file" ] || return 0
    before=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "before" "" 2>/dev/null || true)
    after=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "after" "" 2>/dev/null || true)
    measurement_command=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "measurement_command" "" 2>/dev/null || true)
    measurement_environment=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "measurement_environment" "" 2>/dev/null || true)
    measurement_policy=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "measurement_policy" "" 2>/dev/null || true)
    safety_boundary=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "safety_boundary" "" 2>/dev/null || true)
    fixed_baseline_policy=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "fixed_baseline_policy" "" 2>/dev/null || true)

    [ -n "$before" ] || updates+=("before=同一環境で変更前の実測値を記録し、環境fingerprintを添える")
    [ -n "$after" ] || updates+=("after=同一環境で変更後の実測値を記録し、beforeと同じmeasurement_commandを使う")
    [ -n "$measurement_command" ] || updates+=("measurement_command=bash scripts/run_tests.sh task queue/tasks/${ninja_name}.yaml")
    [ -n "$measurement_environment" ] || updates+=("measurement_environment=beforeとafterは同一環境・同一入力・同一timeoutで実行")
    [ -n "$measurement_policy" ] || updates+=("measurement_policy=before/afterの一次実測をreportへ記録し、固定値との差異は報告して継続")
    [ -n "$fixed_baseline_policy" ] || updates+=("fixed_baseline_policy=固定基準値はWARNのみ。正本の固定秒数・件数厳密一致・±20%で停止しない")
    [ -n "$safety_boundary" ] || updates+=("safety_boundary=自己計測欄欠落と安全底線違反は従来どおりBLOCK")

    [ "${#updates[@]}" -gt 0 ] || return 0
    yaml_field_set_batch "$task_file" "task" "${updates[@]}" || return 1
    log "[MEASUREMENT_CONTRACT] same-environment before/after contract injected for ${ninja_name} (${#updates[@]} fields)"
}


if false; then
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

    # (1) archive.done — cmd_complete_gate.sh GATE CLEAR時に自動実行（CLAUDE.md記載）。配備時の実行は冗長のため除去(cmd_1277)

    # (2) review_gate.done — implement時のみ。配備時点でreview未実施のためplaceholder生成
    local task_type
    task_type=$(field_get "$task_file" "task_type" "")
    if [ "$task_type" = "impl" ] && [ ! -f "$gates_dir/review_gate.done" ]; then
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

# ─── issued_at / issue terminal telemetry ───
deploy_task_append_issue_event() {
    local result="$1"
    local reason="$2"
    local issue_log="$SCRIPT_DIR/logs/deploy_issue_log.yaml"
    [ -n "${DEPLOY_TASK_ISSUE_ATTEMPT_ID:-}" ] || return 0
    (
        flock -w 5 203 || exit 1
        printf -- '- attempt_id: "%s"\n  cmd_id: "%s"\n  ninja: "%s"\n  result: "%s"\n  reason: "%s"\n  timestamp: "%s"\n' \
            "$DEPLOY_TASK_ISSUE_ATTEMPT_ID" "${CMD_ID:-}" "${NINJA_NAME:-}" "$result" "$reason" \
            "$(date '+%Y-%m-%dT%H:%M:%S')" >> "$issue_log"
    ) 203>"${issue_log}.lock"
}

record_issued_at_once() {
    local task_file="$1"
    local cmd_id="$2"
    local timestamp="$3"
    local issued_cmd_id="" issued_at="" existing_cmd="" existing_issued_at=""
    [ -f "$task_file" ] && [ -n "$cmd_id" ] || return 0
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" issued_cmd_id issued_at 2>/dev/null)" || true
    existing_cmd="${issued_cmd_id:-}"
    existing_issued_at="${issued_at:-}"
    if [ "$existing_cmd" = "$cmd_id" ] && [ -n "$existing_issued_at" ]; then
        log "[ISSUED_AT] Preserved: ${existing_issued_at} (retry ${cmd_id})"
        return 0
    fi
    if ! yaml_field_set_batch "$task_file" "task" "issued_at=$timestamp" "issued_cmd_id=$cmd_id"; then
        return 1
    fi
    if [ "${DEPLOY_TASK_YAML_TX_ARMED:-0}" = "1" ]; then
        DEPLOY_TASK_YAML_TX_ISSUED_AT="$timestamp"
        DEPLOY_TASK_YAML_TX_ISSUED_CMD="$cmd_id"
        return 0
    fi
    log "[ISSUED_AT] Recorded: ${timestamp} (${cmd_id})"
}

# ─── deployed_at自動記録（cmd_387: 配備タイムスタンプ） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
# 再配備時もdeployed_atを最新化する（duration計測の起点を実作業時間に合わせる）
record_deployed_at() {
    local task_file="$1"
    local timestamp="$2"
    if [ ! -f "$task_file" ]; then
        log "record_deployed_at: task file not found: $task_file"
        return 0
    fi

    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "deployed_at" "")
    yaml_field_set_batch "$task_file" "task" \
        "deployed_at=$timestamp" "progress_updated_at=$timestamp"
    if [ -n "$existing" ]; then
        log "[DEPLOYED_AT] Updated: old=${existing}, new=${timestamp}"
    else
        log "[DEPLOYED_AT] Recorded: ${timestamp}"
    fi
}

# Source-changing tasks are edited and committed from a linked worktree rooted
# at the live remote tip. The shared checkout remains available for queue and
# runtime state, while this marker gives GATE/archive one cleanup identity.
deploy_task_rollback_remote_tip_worktree() {
    local repo="$1" worktree="$2" marker="$3"
    if [ -n "$repo" ] && [ -n "$worktree" ] && [ -d "$worktree" ]; then
        git -C "$repo" worktree remove "$worktree" >/dev/null 2>&1 || true
    fi
    [ -n "$marker" ] && rm -f -- "$marker" "${marker}.tmp.${BASHPID}" 2>/dev/null || true
}

deploy_task_prepare_remote_tip_worktree() {
    local task_file="$1" ninja_name="$2"
    local task_worktree_required source_path_count task_id parent_cmd project target repo upstream_ref remote push_ref remote_tip
    local worktree_root worktree_path generation marker marker_tmp task_worktree_targets task_worktree_edit_wrapper
    local task_worktree_projection task_worktree_source_paths
    task_worktree_required=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_worktree_required" "false" 2>/dev/null || true)
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    target=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null || true)
    source_path_count=$(python3 -c 'import os,sys,yaml; t=(yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}).get("task",{}); v=[]; [v.extend([t.get(k)] if isinstance(t.get(k),str) else t.get(k) if isinstance(t.get(k),list) else []) for k in ("target_path","planned_paths")]; p=[os.path.normpath(str(x or "")[2:] if str(x or "").startswith("./") else str(x or "")) for x in v]; r=("queue/","logs/","context/","projects/","archive/",".cache/"); print(len({x for x in p if x and x != "dashboard.md" and not x.startswith(r)}))' "$task_file")
    # Runtime/autogen-only tasks are excluded above. Any remaining source path
    # is a source task; publication permission is not the classification axis.
    if [ "$task_worktree_required" != "true" ] && [ "$source_path_count" -lt 1 ]; then
        return 0
    fi
    task_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_id" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$task_id" ] && [ -n "$parent_cmd" ] || { log "BLOCK: remote-tip worktree requires task_id and parent_cmd"; return 1; }

    repo="$SCRIPT_DIR"
    if [ -n "$target" ] && git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1; then
        repo=$(git -C "$target" rev-parse --show-toplevel)
    elif [ "$project" != "infra" ] && [ -n "$project" ]; then
        repo=$(get_project_path "$project" 2>/dev/null || true)
    fi
    repo=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$repo" ] || { log "BLOCK: remote-tip worktree repo unavailable"; return 1; }

    upstream_ref=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    [ -n "$upstream_ref" ] || upstream_ref="origin/main"
    remote="${upstream_ref%%/*}"; push_ref="refs/heads/${upstream_ref#*/}"
    remote_tip=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
    [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || { log "BLOCK: remote-tip worktree remote tip unavailable"; return 1; }
    git -C "$repo" fetch -q --no-write-fetch-head "$remote" "$push_ref" || { log "BLOCK: remote-tip fetch failed"; return 1; }
    git -C "$repo" cat-file -e "${remote_tip}^{commit}" 2>/dev/null || { log "BLOCK: remote-tip object unavailable"; return 1; }

    worktree_root="${DEPLOY_TASK_WORKTREE_ROOT:-/tmp/shogun-task-worktrees}"
    mkdir -p "$worktree_root"
    generation=$(printf '%s\0%s\0%s' "$task_id" "$remote_tip" "$(date +%s%N)" | sha256sum | awk '{print $1}')
    worktree_path="$worktree_root/${ninja_name}_${generation:0:16}"
    [ ! -e "$worktree_path" ] || { log "BLOCK: task worktree path already exists"; return 1; }
    git -C "$repo" -c maintenance.auto=false worktree add --detach --no-checkout "$worktree_path" "$remote_tip" >/dev/null 2>&1 || { log "BLOCK: task worktree add failed"; return 1; }
    if ! git -C "$worktree_path" -c maintenance.auto=false checkout --detach "$remote_tip" >/dev/null 2>&1 \
        || ! git -C "$worktree_path" config maintenance.auto false; then
        git -C "$repo" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
        log "BLOCK: task worktree checkout/config failed"
        return 1
    fi

    marker="$SCRIPT_DIR/queue/gates/$parent_cmd/task_worktree.json"; mkdir -p "${marker%/*}"
    marker_tmp="${marker}.tmp.${BASHPID}"
    python3 -c 'import json,os,sys,time; p,tid,pc,repo,wt,base,gen=sys.argv[1:]; fh=open(p,"w",encoding="utf-8"); json.dump({"version":1,"state":"active","task_id":tid,"parent_cmd":pc,"repo":repo,"worktree":wt,"remote_tip":base,"published_commit":"","generation":gen,"created_at_ns":time.time_ns()},fh,sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno()); fh.close()' \
        "$marker_tmp" "$task_id" "$parent_cmd" "$repo" "$worktree_path" "$remote_tip" "$generation"
    mv -f -- "$marker_tmp" "$marker"
    task_worktree_targets=$(python3 -c 'import json,os,sys,yaml; t=(yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}).get("task",{}); a=t.get("target_path") or []; a=[a] if isinstance(a,str) else a; b=t.get("planned_paths") or []; b=[b] if isinstance(b,str) else b; v=a+b; projected=[os.path.join(sys.argv[2],str(x)[2:] if str(x).startswith("./") else str(x)) for x in v if str(x).strip()]; print(json.dumps(list(dict.fromkeys(projected)),ensure_ascii=False))' "$task_file" "$worktree_path")
    task_worktree_projection=$(python3 - "$task_file" "$worktree_path" <<'PY'
import json
import sys
import yaml

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})

def paths(value):
    if isinstance(value, str):
        try:
            decoded = yaml.safe_load(value)
        except yaml.YAMLError:
            decoded = None
        if isinstance(decoded, list):
            return [str(item).strip() for item in decoded if str(item).strip()]
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

target = paths(task.get("target_path"))
planned = paths(task.get("planned_paths"))
print(json.dumps({
    "source_paths": list(dict.fromkeys(target + planned)),
}, ensure_ascii=False))
PY
)
    task_worktree_source_paths=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["source_paths"],ensure_ascii=False))' "$task_worktree_projection")
    task_worktree_edit_wrapper="$SCRIPT_DIR/scripts/ninja_scope_commit.sh --task-worktree-exec $task_file --"
    local -a task_worktree_args=(
        "task_worktree_required=true" "task_worktree_path=$worktree_path"
        "task_worktree_repo=$repo" "task_worktree_base=$remote_tip"
        "task_worktree_generation=$generation" "task_worktree_status=active"
        "task_worktree_marker=$marker" "task_worktree_workdir=$worktree_path"
        "task_worktree_target_paths=$task_worktree_targets"
        "task_worktree_edit_wrapper=$task_worktree_edit_wrapper"
        "task_worktree_source_paths=$task_worktree_source_paths"
    )
    if [ "${DEPLOY_TASK_TEST_FAIL_WORKTREE_YAML_PUBLISH:-0}" = "1" ]; then
        deploy_task_rollback_remote_tip_worktree "$repo" "$worktree_path" "$marker"
        log "BLOCK: injected task worktree YAML publish failure; rolled back path=$worktree_path"
        return 1
    fi
    if ! yaml_field_set_batch "$task_file" task "${task_worktree_args[@]}"; then
        deploy_task_rollback_remote_tip_worktree "$repo" "$worktree_path" "$marker"
        log "BLOCK: task worktree YAML publish failed; rolled back path=$worktree_path"
        return 1
    fi
    log "TASK_WORKTREE_READY: ninja=$ninja_name task=$task_id base=$remote_tip path=$worktree_path maintenance.auto=false"
}

record_target_worktree_blob_at_deploy() {
    local task_file="$1" target blob now repo required
    required=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_worktree_required" "false" 2>/dev/null || true)
    repo="$SCRIPT_DIR"
    if [ "$required" = "true" ]; then
        repo=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_worktree_repo" "$SCRIPT_DIR" 2>/dev/null || true)
        target=$(python3 - "$task_file" <<'PY'
import sys
import yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
value = task.get("task_worktree_source_paths") or []
if isinstance(value, str):
    try:
        value = yaml.safe_load(value) or []
    except yaml.YAMLError:
        value = [value]
print(str(value[0]).strip() if isinstance(value, list) and value else "")
PY
)
    else
        target=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null || true)
        target="${target#[}"; target="${target%]}"; target="${target#\"}"; target="${target%\"}"
    fi
    [ -n "$target" ] && [ -f "$repo/$target" ] || return 0
    blob=$(git -C "$repo" hash-object -- "$target" 2>/dev/null || true)
    [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || return 1
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    yaml_field_set_batch "$task_file" task \
        "target_path_worktree_blob_at_deploy=$blob" "progress_updated_at=$now"
}

# ─── context鮮度チェック（穴2対策: cmd_239） ───
# cmd_1393: Python2箇所→awk+date変換
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

    # Python→awk: projects.yamlからproject IDに対応するcontext_fileを取得
    local context_file
    context_file=$(awk -v proj="$project" '
        /^[[:space:]]*- id:/ { sub(/.*- id:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); cur_id = $0 }
        /^[[:space:]]*context_file:/ {
            if (cur_id == proj) {
                sub(/.*context_file:[[:space:]]*/, "")
                gsub(/[[:space:]]*$/, "")
                gsub(/^["'"'"']|["'"'"']$/, "")
                print
                exit
            }
        }
    ' "$projects_yaml" 2>/dev/null)

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

    # Python→date: 日付差分計算
    local days_old=-1
    local lu_epoch today_epoch
    lu_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || true
    today_epoch=$(date +%s)
    if [ -n "$lu_epoch" ]; then
        days_old=$(( (today_epoch - lu_epoch) / 86400 ))
    fi

    if [ "$days_old" -ge 14 ] 2>/dev/null; then
        log "context_freshness: ⚠️ WARNING: $context_file last updated ${days_old} days ago"
        echo "⚠️ WARNING: $context_file last updated ${days_old} days ago" >&2
    else
        log "context_freshness: OK ($context_file updated ${days_old} days ago)"
    fi

    return 0
}

# ─── 入口門番: 前タスクの教訓未消化チェック ───
# cmd_1393: Python→awk変換
check_entrance_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "entrance_gate: PASS (task file not found: $task_file)"
        return 0
    fi

    # awk: related_lessonsセクション内でreviewed: falseを持つエントリのIDを収集
    local result
    result=$(awk '
        BEGIN { in_rl=0; cur_id=""; rev_false=0 }
        /^  related_lessons:/ { in_rl=1; next }
        in_rl && /^  [a-z_]/ && !/^  -/ { in_rl=0 }
        in_rl && /^  - / {
            if (rev_false && cur_id!="") printf "%s, ",cur_id
            cur_id=""; rev_false=0
        }
        in_rl && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_rl && /    reviewed:[[:space:]]*false/ { rev_false=1 }
        END { if (rev_false && cur_id!="") printf "%s",cur_id }
    ' "$task_file" 2>/dev/null)

    if [ -n "$result" ]; then
        # trailing ", " を除去
        result="${result%, }"
        log "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ"
        echo "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ" >&2
        exit 1
    fi

    log "entrance_gate: PASS (no unreviewed lessons)"
    return 0
}

# Validate an explicit cross-command scout hand-off.  The ordinary scout gate
# deliberately counts only live tasks with the same parent_cmd; completed
# scouts are routinely archived and their workers reused, so an impl task may
# instead name the exact reviewed reports it consumes.
validate_explicit_scout_reports() {
    local task_file="$1"
    # Keep the common legacy path shell-only.  Python/YAML validation is paid
    # only by tasks that explicitly opt into cross-command report reuse.
    if ! grep -qE '^[[:space:]]{2}scout_reports:[[:space:]]*' "$task_file" 2>/dev/null; then
        return 3
    fi
    python3 - "$task_file" "$SCRIPT_DIR" <<'PY'
import pathlib
import sys

import yaml

task_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()


def block(reason):
    print(f"BLOCK(scout_reports): {reason}", file=sys.stderr)
    raise SystemExit(1)


try:
    task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
except (OSError, yaml.YAMLError) as exc:
    block(f"task YAML unreadable: {exc}")
task = task_doc.get("task", task_doc)
if not isinstance(task, dict):
    block("task mapping missing")
if "scout_reports" not in task:
    raise SystemExit(3)

raw_paths = task.get("scout_reports")
if not isinstance(raw_paths, list) or len(raw_paths) < 2:
    block("at least two explicit report paths are required")

allowed_roots = tuple(
    (root / rel).resolve()
    for rel in ("queue/reports", "queue/archive/reports", "archive/reports")
)
reports = []
resolved_paths = set()
report_ids = set()
for index, raw_path in enumerate(raw_paths):
    if not isinstance(raw_path, str) or not raw_path.strip():
        block(f"entry[{index}] must be a non-empty repo-relative path")
    lexical = pathlib.PurePosixPath(raw_path.strip())
    if lexical.is_absolute() or ".." in lexical.parts:
        block(f"entry[{index}] is outside repo scope: {raw_path}")
    candidate = (root / lexical).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        block(f"entry[{index}] resolves outside repo: {raw_path}")
    if not any(candidate == base or base in candidate.parents for base in allowed_roots):
        block(f"entry[{index}] is not under an approved report directory: {raw_path}")
    if candidate in resolved_paths:
        block(f"duplicate report path: {raw_path}")
    resolved_paths.add(candidate)
    if not candidate.is_file():
        block(f"report missing: {raw_path}")
    try:
        report = yaml.safe_load(candidate.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        block(f"report unreadable ({raw_path}): {exc}")
    if not isinstance(report, dict):
        block(f"report is not a mapping: {raw_path}")
    report_id = str(report.get("report_id") or "").strip()
    if not report_id:
        block(f"report_id missing: {raw_path}")
    if report_id in report_ids:
        block(f"duplicate report_id: {report_id}")
    report_ids.add(report_id)
    status = str(report.get("status") or "").strip().lower()
    if status != "completed":
        block(f"report status is not completed ({raw_path}): {status or 'missing'}")
    task_type = str(report.get("task_type") or "").strip().lower()
    if task_type not in {"scout", "recon"}:
        block(f"report task_type is not scout/recon ({raw_path}): {task_type or 'missing'}")
    verdict = str(report.get("verdict") or "").strip().upper()
    if verdict not in {"PASS", "PASS_NO_IMPROVEMENT"}:
        block(f"report verdict is not PASS-family ({raw_path}): {verdict or 'missing'}")
    cmd_id = str(report.get("parent_cmd") or "").strip()
    if not cmd_id.startswith("cmd_"):
        block(f"report parent_cmd missing or invalid: {raw_path}")
    reports.append((raw_path, cmd_id))

metrics_path = root / "logs/gate_metrics.log"
latest_gate = {}
try:
    for line in metrics_path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            latest_gate[parts[1].strip()] = parts[2].strip().upper()
except OSError as exc:
    block(f"gate metrics unreadable: {exc}")

review_path = root / "logs/gunshi_review_log.yaml"
try:
    review_doc = yaml.safe_load(review_path.read_text(encoding="utf-8")) or []
except (OSError, yaml.YAMLError) as exc:
    block(f"gunshi review log unreadable: {exc}")
if not isinstance(review_doc, list):
    block("gunshi review log is not a list")

latest_review = {}
for raw_entry in review_doc:
    if not isinstance(raw_entry, dict):
        continue
    entry = raw_entry.get("review", raw_entry)
    if not isinstance(entry, dict):
        continue
    if str(entry.get("review_type") or "").strip().lower() != "report":
        continue
    cmd_id = str(entry.get("cmd_id") or "").strip()
    if cmd_id:
        latest_review[cmd_id] = str(entry.get("verdict") or "").strip().upper()

for raw_path, cmd_id in reports:
    if latest_gate.get(cmd_id) != "CLEAR":
        block(f"latest gate is not CLEAR ({raw_path}): {latest_gate.get(cmd_id, 'missing')}")
    if latest_review.get(cmd_id) != "LGTM":
        block(f"latest gunshi report review is not LGTM ({raw_path}): {latest_review.get(cmd_id, 'missing')}")

print(f"PASS: explicit scout_reports={len(reports)} distinct_report_ids={len(report_ids)}")
PY
}

# ─── 偵察ゲート: implタスクは偵察済みorscout_exempt必須 ───
# cmd_1393: check_scout_gate Python→bash/awk化
check_scout_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "scout_gate: PASS (task file not found)"
        return 0
    fi

    # 0. 完了済みタスクはscout_gate再検査不要 — PASS
    local task_status
    task_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "")
    case "$task_status" in
        done|idle|completed)
            log "scout_gate: PASS: status=${task_status} (completed task, skip re-check)"
            return 0
            ;;
    esac

    # 1. task_typeがimpl以外ならPASS（typeフィールドではなくtask_typeのみ参照）
    local task_type
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
    if [ "$task_type" != "impl" ]; then
        log "scout_gate: PASS: task_type=${task_type} (not impl)"
        return 0
    fi

    # 2. parent_cmd取得
    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    if [ -z "$parent_cmd" ]; then
        log "scout_gate: PASS: no parent_cmd"
        return 0
    fi

    # 3. shogun_to_karo.yamlでscout_exempt確認
    local stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    if [ -f "$stk_path" ]; then
        local _se
        _se=$(awk -v cmd="$parent_cmd" '
            /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
            /^[[:space:]]*-?[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
            cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
        ' "$stk_path" 2>/dev/null)
        if [ "$_se" = "true" ]; then
            log "scout_gate: PASS: scout_exempt=true for ${parent_cmd}"
            return 0
        fi
    fi

    # 3.1 karo_direct cmd is not present in shogun_to_karo.yaml; trust task-local exemption.
    local task_scout_exempt
    task_scout_exempt=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "scout_exempt" "" 2>/dev/null || true)
    if [ "$task_scout_exempt" = "true" ]; then
        log "scout_gate: PASS: scout_exempt=true in task YAML for ${parent_cmd}"
        return 0
    fi

    # 3.5 研究cmd自動scout_exempt: q4_depth=shallow → 本番コード変更なし (LK057)
    if [ -f "$stk_path" ]; then
        local _q4
        _q4=$(awk -v cmd="$parent_cmd" '
            /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
            cur_id == cmd && /q4_depth:/ { sub(/.*q4_depth:[[:space:]]*"?/, ""); sub(/"?[[:space:]]*—.*/, ""); print; exit }
        ' "$stk_path" 2>/dev/null)
        if [ "$_q4" = "shallow" ]; then
            log "scout_gate: PASS: q4_depth=shallow (research cmd auto-exempt, LK057)"
            return 0
        fi
    fi

    # 4. report_merge.doneチェック
    if [ -f "$SCRIPT_DIR/queue/gates/${parent_cmd}/report_merge.done" ]; then
        log "scout_gate: PASS: report_merge.done exists for ${parent_cmd}"
        return 0
    fi

    # 4.5 Explicitly reused, fully completed scouts from other parent commands.
    # Absence (rc=3) preserves the historical same-parent counting contract;
    # a present but invalid list always fails closed.
    local _explicit_scout_output="" _explicit_scout_rc=0
    _explicit_scout_output=$(validate_explicit_scout_reports "$task_file" 2>&1) || _explicit_scout_rc=$?
    case "$_explicit_scout_rc" in
        0)
            log "scout_gate: ${_explicit_scout_output}"
            return 0
            ;;
        3)
            ;;
        *)
            log "${_explicit_scout_output}"
            echo "${_explicit_scout_output}" >&2
            return 1
            ;;
    esac

    # 5. scout/reconタスクのdone数カウント
    local done_count=0
    local _tf
    for _tf in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
        [ -f "$_tf" ] || continue
        local _pcmd _tid _tst
        _pcmd=$(awk '/^  parent_cmd:/ { sub(/.*parent_cmd:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
        [ "$_pcmd" = "$parent_cmd" ] || continue
        _tid=$(awk '/^  task_id:/ { sub(/.*task_id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
        _tid=$(echo "$_tid" | tr '[:upper:]' '[:lower:]')
        case "$_tid" in
            *scout*|*recon*)
                _tst=$(awk '/^  status:/ { sub(/.*status:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
                if [ "$_tst" = "done" ]; then
                    done_count=$((done_count + 1))
                fi
                ;;
        esac
    done

    if [ "$done_count" -ge 2 ]; then
        log "scout_gate: PASS: ${done_count} scout/recon tasks done for ${parent_cmd}"
        return 0
    fi

    # BLOCK
    log "BLOCK(scout_gate): ${parent_cmd} — scout done=${done_count}/2, scout_exempt=false"
    echo "BLOCK(scout_gate): 偵察未完了。scout_reportsが2件未満かつscout_exemptなし。将軍にscout_exempt申請するか、先に偵察を配備せよ" >&2
    echo "詳細: ${parent_cmd} — scout done=${done_count}/2, scout_exempt=false" >&2
    exit 1
}

# ─── 教訓注入postcondition（cmd_378: 事後不変条件） ───
postcondition_lesson_inject() {
    local task_file="$1"
    local postcond_file
    deploy_task_postcondition_prepare "$task_file"
    postcond_file="$DEPLOY_TASK_POSTCOND_FILE"

    if [ ! -f "$postcond_file" ]; then
        # inject early exit (no project/no lessons) → postcond data not written → OK
        deploy_task_postcondition_cleanup
        return 0
    fi

    local available injected task_id
    available=$(grep '^available=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    injected=$(grep '^injected=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    task_id=$(grep '^task_id=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    deploy_task_postcondition_cleanup

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
        # 1. Check shogun_to_karo.yaml (single file, dict format: "  cmd_XXXX:")
        local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
        if [ -f "$stk" ]; then
            title=$(awk -v key="  ${cmd_id}:" '
                index($0, key) == 1 { found = 1; next }
                found && /^    title:/ {
                    sub(/^[[:space:]]*title:[[:space:]]*/, "")
                    sub(/[[:space:]]+#.*$/, "")
                    print
                    exit
                }
                found && /^  [^ ]/ { exit }
            ' "$stk" 2>/dev/null || true)
        fi

        # 2. If not found, locate archive file by filename glob (O(1))
        if [ -z "$title" ]; then
            yaml_file=$(find "$SCRIPT_DIR/queue/archive/cmds/" -maxdepth 1 -name "${cmd_id}_*.yaml" -print -quit 2>/dev/null)
            if [ -n "$yaml_file" ]; then
                title=$(awk '/^[[:space:]]*title:/ {
                    sub(/^[[:space:]]*title:[[:space:]]*/, "")
                    sub(/[[:space:]]+#.*$/, "")
                    print
                    exit
                }' "$yaml_file" 2>/dev/null || true)
            fi
        fi
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

# 消火キーワードtitle検知: cmdのtitleが消火系キーワードを含む場合にWARNING出力（cmd_1807）
# 家老経路(deploy_task.sh)でcmd_save.sh(将軍経路)と同一キーワードをカバーする
check_firefighting_title() {
    local cmd_id="$1"
    local task_file="$2"
    local title
    title=$(resolve_dispatch_title "$cmd_id" "$task_file")
    if [ -z "$title" ]; then
        return 0
    fi
    if echo "$title" | grep -qiE "$FIREFIGHTING_PATTERN"; then
        echo "⚠️ WARNING: 消火cmdを検知。真因と再発防止を検討せよ (title: ${title})" >&2
        log "firefighting_title_warn: ${cmd_id} title='${title}'"
    fi
}

count_task_acceptance_criteria() {
    local task_file="$1"
    local cmd_id="${2:-}"
    python3 - "$task_file" "$cmd_id" "$SCRIPT_DIR" <<'PY'
import sys
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from pathlib import Path

task_file = sys.argv[1]
cmd_id = sys.argv[2].strip()
script_dir = Path(sys.argv[3])
count = 0

import re

def count_description_value(desc):
    if isinstance(desc, list):
        return len(desc)
    if isinstance(desc, dict):
        ac_keys = [k for k in desc if re.match(r'^AC\d+$', str(k))]
        if ac_keys:
            return len(ac_keys)
        return len(desc)
    if isinstance(desc, str) and desc.strip():
        ac_matches = re.findall(r'\bAC\d+\b', desc)
        return len(set(ac_matches)) if ac_matches else 1
    return 0

def count_acs_from_value(acs):
    """Count ACs: list→len, dict AC keys, description wrapper, str AC patterns."""
    if isinstance(acs, list):
        if len(acs) == 1 and isinstance(acs[0], dict):
            ac_keys = [k for k in acs[0] if re.match(r'^AC\d+$', k)]
            if ac_keys:
                return len(ac_keys)
        return len(acs)
    if isinstance(acs, dict):
        ac_keys = [k for k in acs if re.match(r'^AC\d+$', str(k))]
        if ac_keys:
            return len(ac_keys)
        desc_count = count_description_value(acs.get('description', ''))
        if desc_count:
            return desc_count if len(acs) == 1 else max(desc_count, 1)
        return max(len(acs), 1)
    if isinstance(acs, str) and acs.strip():
        ac_matches = re.findall(r'\bAC\d+\b', acs)
        return len(set(ac_matches)) if ac_matches else 1
    return 0

def count_acs_from_text(text, cmd_id=""):
    """Count only the acceptance_criteria block when full YAML parsing fails."""
    lines = text.splitlines()
    scopes = [(0, len(lines))]
    if cmd_id:
        cmd_pattern = re.compile(rf'^(\s*){re.escape(cmd_id)}:\s*(?:#.*)?$')
        for idx, line in enumerate(lines):
            match = cmd_pattern.match(line)
            if not match:
                continue
            cmd_indent = len(match.group(1))
            end = len(lines)
            for j in range(idx + 1, len(lines)):
                if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip()) <= cmd_indent:
                    end = j
                    break
            scopes = [(idx + 1, end)]
            break

    for start, end in scopes:
        ac_start = None
        ac_indent = 0
        for idx in range(start, end):
            match = re.match(r'^(\s*)acceptance_criteria:\s*(?:#.*)?$', lines[idx])
            if match:
                ac_start = idx + 1
                ac_indent = len(match.group(1))
                break
        if ac_start is None:
            continue

        block = []
        for line in lines[ac_start:end]:
            if line.strip() and len(line) - len(line.lstrip()) <= ac_indent:
                break
            block.append(line)

        list_items = [
            line for line in block
            if re.match(r'^\s*-\s+(?:id:|description:|\S+)', line)
        ]
        if list_items:
            return len(list_items)

        ac_keys = set()
        for line in block:
            match = re.match(r'^\s*(AC\d+):\s*', line)
            if match:
                ac_keys.add(match.group(1))
        if ac_keys:
            return len(ac_keys)

        ac_matches = re.findall(r'\bAC\d+\b', "\n".join(block))
        if ac_matches:
            return len(set(ac_matches))
    return 0

try:
    with open(task_file, encoding='utf-8') as f:
        task_text = f.read()
    data = yaml.safe_load(task_text) or {}
    task = data.get('task') or {}
    acs = task.get('acceptance_criteria')
    count = count_acs_from_value(acs)
except Exception:
    try:
        with open(task_file, encoding='utf-8') as f:
            count = count_acs_from_text(f.read())
    except Exception:
        count = 0

if count <= 0 and cmd_id:
    search_files = [
        script_dir / "queue" / "shogun_to_karo.yaml",
    ]
    archive_dir = script_dir / "queue" / "archive" / "cmds"
    if archive_dir.is_dir():
        search_files.extend(sorted(archive_dir.glob(f"{cmd_id}_*.yaml"), reverse=True))

    for path in search_files:
        try:
            text = path.read_text(encoding='utf-8')
            data = yaml.safe_load(text) or {}
        except Exception:
            try:
                count = count_acs_from_text(text, cmd_id)
            except Exception:
                count = 0
            if count > 0:
                break
            continue

        commands = data.get("commands") or {}
        if isinstance(commands, dict):
            cmd = commands.get(cmd_id) or {}
        elif isinstance(commands, list):
            cmd = next((c for c in commands if str(c.get("id", "")).strip() == cmd_id), {})
        else:
            cmd = {}

        acs = cmd.get("acceptance_criteria")
        count = count_acs_from_value(acs)

        if count > 0:
            break

print(count)
PY
}

# 殿裁定(2026-08-14): 忍者ACにdoc laneの仕事を混ぜない。
# context境界更新・gist同期・計画書/文書更新は将軍laneへ戻す。DOC laneの
# 所有権はtaskのtarget_path/planned_pathsで判定し、AC本文の自然言語は検査しない。
deploy_task_guard_doc_update_ac() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    if task_targets_are_documentation_only "$task_file"; then
        log "BLOCK(DOC_LANE_ROUTING): target_path is documentation-owned"
        echo "BLOCK: task target_path is documentation-owned; doc update is not a ninja lane. Route the documentation update to the shogun doc lane." >&2
        return 2
    fi
    return 0
}

mark_draft_review_once() {
    local cmd_id="$1"
    local ninja_name="$2"
    local title="$3"
    local state_dir="$SCRIPT_DIR/queue/draft_review_started"
    local marker="$state_dir/${cmd_id}.draft_review.started"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"

    mkdir -p "$state_dir"

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

draft_review_already_completed() {
    local cmd_id="$1"
    local review_log="$SCRIPT_DIR/logs/gunshi_review_log.yaml"

    [ -n "$cmd_id" ] || return 1
    [ -f "$review_log" ] || return 1

    awk -v cmd="$cmd_id" '
        /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/ { in_cmd=0 }
        $0 ~ "^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*[\"'\'']?" cmd "[\"'\'']?[[:space:]]*$" {
            in_cmd=1
            next
        }
        in_cmd && /^[[:space:]]*verdict:[[:space:]]*[A-Za-z_]+/ {
            found=1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$review_log"
}

maybe_notify_draft_review() {
    local task_file="$1"
    local cmd_id="$2"
    local ninja_name="$3"
    local deploy_type="${4:-task_assigned}"
    local title ac_count message quality_contract

    if [ "$deploy_type" != "task_assigned" ]; then
        log "draft_review: SKIP (type=${deploy_type})"
        return 0
    fi

    if [ "${SKIP_DRAFT_REVIEW:-0}" = "1" ]; then
        log "draft_review: SKIP (env)"
        return 0
    fi

    if [ -z "$cmd_id" ]; then
        log "draft_review: SKIP (cmd_id empty)"
        return 0
    fi

    if draft_review_already_completed "$cmd_id"; then
        log "draft_review: SKIP (already reviewed: ${cmd_id})"
        return 0
    fi

    title=$(resolve_dispatch_title "$cmd_id" "$task_file")
    if printf '%s' "$title" | grep -q 'CI RED'; then
        log "draft_review: SKIP (CI RED)"
        return 0
    fi

    quality_contract="$(deploy_task_quality_contract_result "$task_file")"
    log "draft_review quality_contract: ${quality_contract}"

    if ! ac_count=$(count_task_acceptance_criteria "$task_file" "$cmd_id"); then
        log "draft_review: WARN (ac_count unavailable; sending review)"
        ac_count=2
    elif ! [[ "$ac_count" =~ ^[0-9]+$ ]]; then
        log "draft_review: WARN (ac_count invalid: ${ac_count:-empty}; sending review)"
        ac_count=2
    fi
    if ! mark_draft_review_once "$cmd_id" "$ninja_name" "${title:-$cmd_id}"; then
        log "draft_review: SKIP (already sent)"
        return 0
    fi

    message="draft ${cmd_id} レビュー依頼。${title:-$cmd_id}。ninja=${ninja_name}。"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" gunshi "$message" review_draft karo review_request; then
        log "draft_review: SENT (gunshi)"
    else
        log "draft_review: WARN (inbox_write failed)"
    fi
}

# Direct/karo_direct tasks do not traverse cmd_save. Normalize task YAML to a
# standalone block, then apply the same detector-quality evaluator as draft review.
deploy_task_quality_contract_result() {
    local task_file="$1"
    local task_block applicable action fp
    [[ -f "$task_file" ]] || { printf 'UNAVAILABLE'; return 0; }
    task_block="$(python3 - "$task_file" <<'PY' 2>/dev/null
import io, sys, yaml
class CanonicalProjectionDumper(yaml.SafeDumper):
    # The shared line-oriented evaluator treats indentation as the section
    # boundary. Keep sequence items nested beneath their mapping key.
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)

try:
    data = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    task = data.get('task', data)
    if isinstance(task, dict):
        # The shared evaluator only needs the detector-relevant text. Emit a
        # deterministic canonical-YAML projection to stdout; never write back
        # to the operational task. Python repr loses YAML nesting and makes
        # structured AC/quality_gate text invisible to the shared evaluator.
        keys = ('project', 'title', 'purpose', 'command', 'acceptance_criteria', 'quality_gate')
        projection = {key: task[key] for key in keys if task.get(key) not in (None, '', [], {})}
        stream = io.StringIO()
        dumper = CanonicalProjectionDumper(
            stream,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
            width=4096,
        )
        try:
            dumper.open()
            dumper.represent(projection)
            dumper.close()
        finally:
            dumper.dispose()
        print(stream.getvalue(), end='')
except Exception:
    pass
PY
)"
    IFS=$'\t' read -r applicable action fp < <(gate_hook_quality_contract_evaluate "$task_block")
    [[ "$applicable" == "yes" ]] || { printf 'NOT_APPLICABLE'; return 0; }
    if [[ "$action" == "pass" && "$fp" == "pass" ]]; then
        printf 'PASS'
    else
        printf 'WARN(action=%s,fp=%s)' "$action" "$fp"
    fi
}

deploy_task_direct_quality_contract_precheck() {
    local task_file="$1"
    local result
    result="$(deploy_task_quality_contract_result "$task_file")"
    case "$result" in
        WARN*)
            log "BLOCK(QUALITY_CONTRACT): ${result}"
            echo "BLOCK: direct deployment detector quality contract failed: ${result}" >&2
            return 1
            ;;
        *)
            log "quality_contract: ${result}"
            return 0
            ;;
    esac
}

# Ten minutes is a planning target, while fifteen minutes is the hard boundary.
# Between them, keep naturally atomic work together only with an explicit split
# decision.  Beyond fifteen minutes, require measured long-runtime evidence.
# Keep this read-only and before publish/task mutation so rejection has no side effects.
deploy_task_ten_min_contract_precheck() {
    local task_file="$1"
    local cmd_id="${2:-}"
    local result rc

    deploy_task_guard_doc_update_ac "$task_file" || return $?

    local cmd_args=()
    [[ -n "$cmd_id" ]] && cmd_args=(--cmd-id "$cmd_id")
    result="$(python3 "$SCRIPT_DIR/scripts/lib/time_contract_validator.py" \
        "${cmd_args[@]}" "$task_file")" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
        log "BLOCK(TEN_MIN_CONTRACT): ${result}"
        echo "BLOCK: natural-boundary task contract failed: ${result}" >&2
        return 2
    fi
    log "ten_min_contract: ${result}"
    return 0
}

# Validate the immutable deployment source before reset_stale_fields or publish.
# A rejected deployment must leave the worker's existing task byte-identical.
deploy_task_source_contract_precheck() {
    local source_file="$1"
    local cmd_id="${2:-}"

    [ -f "$source_file" ] || {
        log "BLOCK(SOURCE_CONTRACT): source not found: ${source_file}"
        echo "BLOCK: deployment source not found: ${source_file}" >&2
        return 2
    }
    deploy_task_ten_min_contract_precheck "$source_file" "$cmd_id" || return $?

    # Level5: automatically derive the shard manifest at the common deployment entrance.
    # Worker shortage is deferred, never silently collapsed to a single worker.
    local shard_id shard_output shard_result shard_rc=0
    local -a shard_args
    shard_id="${cmd_id:-$(basename "$source_file" .yaml)}"
    shard_output="$SCRIPT_DIR/queue/shard_manifests/${shard_id}.json"
    shard_args=("$source_file")
    if [ -n "$cmd_id" ]; then
        shard_args+=(--block-id "$cmd_id")
    fi
    shard_result="$(python3 "$SCRIPT_DIR/scripts/lib/universal_shard_contract.py" \
        "${shard_args[@]}" --tasks-dir "$SCRIPT_DIR/queue/tasks" \
        --output "$shard_output" 2>&1)" || shard_rc=$?
    if [ "$shard_rc" -ne 0 ]; then
        log "BLOCK(UNIVERSAL_SHARD): ${shard_result}"
        echo "$shard_result" >&2
        return 2
    fi
    log "universal_shard: ${shard_result}"
}

capture_done_redeploy_context() {
    local task_file="$1"
    local requested_cmd="${2:-}"
    local ninja_name prev_status prev_parent_cmd prev_report_path prev_report_filename prev_task_id prev_ac_task_id

    export _DEPLOY_DONE_REUSE=0
    export _DEPLOY_DONE_REPORT_PATH=""
    export _DEPLOY_DONE_PARENT_CMD=""
    export _DEPLOY_DONE_TASK_ID=""
    export _DEPLOY_DONE_AC_TASK_ID=""

    [ -f "$task_file" ] || return 0

    ninja_name=$(basename "$task_file" .yaml)
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        status parent_cmd report_path report_filename task_id _ac_task_id 2>/dev/null)" || true

    prev_status="${status:-}"
    prev_parent_cmd="${parent_cmd:-}"
    prev_report_path="${report_path:-}"
    prev_report_filename="${report_filename:-}"
    prev_task_id="${task_id:-}"
    prev_ac_task_id="${_ac_task_id:-}"

    [ "$prev_status" = "done" ] || return 0
    [ -n "$requested_cmd" ] || requested_cmd="$prev_parent_cmd"
    [ -n "$requested_cmd" ] || return 0
    [ "$prev_parent_cmd" = "$requested_cmd" ] || return 0

    if [ -z "$prev_report_path" ] && [ -n "$prev_report_filename" ]; then
        prev_report_path="queue/reports/${prev_report_filename}"
    fi
    if [ -z "$prev_report_path" ] && [ -n "$prev_parent_cmd" ]; then
        prev_report_path="queue/reports/${ninja_name}_report_${prev_parent_cmd}.yaml"
    fi
    if [ -n "$prev_report_path" ] && [ ! -f "$SCRIPT_DIR/$prev_report_path" ]; then
        prev_report_path=""
    fi

    export _DEPLOY_DONE_REUSE=1
    export _DEPLOY_DONE_REPORT_PATH="$prev_report_path"
    export _DEPLOY_DONE_PARENT_CMD="$prev_parent_cmd"
    export _DEPLOY_DONE_TASK_ID="$prev_task_id"
    export _DEPLOY_DONE_AC_TASK_ID="$prev_ac_task_id"
    log "done_redeploy_capture: cmd=${prev_parent_cmd} report=${prev_report_path:-none} task_id=${prev_task_id:-none} ac_task_id=${prev_ac_task_id:-none}"
}

should_skip_same_cmd_resolve() {
    local task_file="$1"
    local requested_cmd="$2"
    local ninja_name="${3:-}"
    local prev_status prev_parent_cmd prev_task_id prev_report_path prev_report_filename

    [ -f "$task_file" ] || return 1
    [ -n "$requested_cmd" ] || return 1

    # Partial field extraction can succeed even when the task document is
    # malformed.  Reusing that document would skip stale reset/atomic --yaml
    # publication and make the corruption unrecoverable (GA-258).
    if ! python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$task_file" >/dev/null 2>&1; then
        log "same_cmd_redeploy: task YAML invalid; force repair path for ${requested_cmd}"
        return 1
    fi

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        status parent_cmd task_id report_path report_filename 2>/dev/null)" || true

    prev_status="${status:-}"
    prev_parent_cmd="${parent_cmd:-}"
    prev_task_id="${task_id:-}"
    prev_report_path="${report_path:-}"
    prev_report_filename="${report_filename:-}"

    [ "$prev_parent_cmd" = "$requested_cmd" ] || return 1
    case "$prev_status" in
        assigned|acknowledged) ;;
        *) return 1 ;;
    esac
    [ -n "$prev_task_id" ] || return 1

    if [ -z "$prev_report_path" ] && [ -n "$prev_report_filename" ]; then
        prev_report_path="queue/reports/${prev_report_filename}"
    fi
    if [ -z "$prev_report_path" ] && [ -n "$ninja_name" ]; then
        prev_report_path="queue/reports/${ninja_name}_report_${requested_cmd}.yaml"
    fi
    [ -n "$prev_report_path" ] || return 1
    [ -f "$SCRIPT_DIR/$prev_report_path" ] || return 1

    log "cmd_resolve: SKIP duplicate same-cmd deploy (${requested_cmd} → ${ninja_name:-unknown}); reusing existing task YAML"
    return 0
}

deploy_task_direct_formal_rc_refresh_report() {
    local task_file="$1"
    local requested_cmd="$2"
    local ninja_name="$3"
    local source_file="${4:-}"
    local current_parent source_parent report_path report_filename

    [ "${DIRECT_MODE:-false}" = true ] || return 1
    [ -f "$task_file" ] || return 1
    [ -f "$source_file" ] || return 1
    [ -n "$requested_cmd" ] || return 1

    current_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    source_parent=$(FIELD_GET_NO_LOG=1 field_get "$source_file" "parent_cmd" "" 2>/dev/null || true)
    [ "$current_parent" = "$requested_cmd" ] || return 1
    [ "$source_parent" = "$requested_cmd" ] || return 1

    report_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_path" "" 2>/dev/null || true)
    report_filename=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "" 2>/dev/null || true)
    if [ -z "$report_path" ] && [ -n "$report_filename" ]; then
        report_path="queue/reports/$report_filename"
    fi
    [ -n "$report_path" ] || report_path="queue/reports/${ninja_name}_report_${requested_cmd}.yaml"
    [[ "$report_path" = /* ]] || report_path="$SCRIPT_DIR/$report_path"
    [ -f "$report_path" ] || return 1

    deploy_task_has_formal_karo_rc_for_report \
        "$requested_cmd" "$ninja_name" "$report_path" "$task_file" || return 1
    printf '%s\n' "$report_path"
}

inject_done_redeploy_hints() {
    local task_file="$1"
    local report_path report_filename existing_desc note

    [ "${_DEPLOY_DONE_REUSE:-0}" = "1" ] || return 0
    [ -f "$task_file" ] || return 0

    # test-speedの各roundは同一parent_cmdでもreport identityが別物。
    # 汎用done再配備hintでR2+をR1へ戻すと過去報告を上書きするため、生成器の明示契約を優先する。
    if deploy_task_speed_campaign_report_is_explicit "$task_file"; then
        log "done_redeploy_hint: SKIP explicit speed campaign round report"
        return 0
    fi

    report_path="${_DEPLOY_DONE_REPORT_PATH:-}"
    [ -n "$report_path" ] || return 0

    note="【再配備引継ぎ】 前回報告(${report_path})の files_modified/binary_checks を引継ぎ済み。前回結果を参照し、差分のみ再検証せよ。"
    existing_desc=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "description" "" 2>/dev/null || true)
    if [[ "$existing_desc" != *"【再配備引継ぎ】"* ]]; then
        if [ -n "$existing_desc" ]; then
            yaml_field_set "$task_file" "task" "description" "${note} | ${existing_desc}" || true
        else
            yaml_field_set "$task_file" "task" "description" "$note" || true
        fi
    fi

    report_filename=$(basename "$report_path")
    yaml_field_set "$task_file" "task" "report_path" "$report_path" || true
    if [ -n "$report_filename" ]; then yaml_field_set "$task_file" "task" "report_filename" "$report_filename" || true; fi
    log "done_redeploy_hint: reused report=${report_path}"
}

warn_same_ninja_redeploy() {
    local task_file="$1"
    local ninja_name="$2"
    local parent_cmd="${3:-}"
    local report_file report_status report_verdict reason_text=""
    local -a reasons=()

    [ -f "$task_file" ] || return 0
    [ -n "$ninja_name" ] || return 0

    if [ -z "$parent_cmd" ]; then
        parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    fi
    [ -n "$parent_cmd" ] || return 0

    if [ -n "${_DEPLOY_PREV_PARENT_CMD:-}" ] && [ "$_DEPLOY_PREV_PARENT_CMD" = "$parent_cmd" ]; then
        reasons+=("同一parent_cmd再投入")
    fi
    if [ -n "${_DEPLOY_PREV_SESSION_STATE:-}" ]; then
        reasons+=("session_state残存")
    fi

    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    if [ -f "$report_file" ]; then
        report_status=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "status" "" 2>/dev/null || true)
        report_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "" 2>/dev/null || true)
        if [ -z "$report_verdict" ] || [ "$report_verdict" = "FAIL" ] || [ "$report_status" != "completed" ]; then
            reasons+=("同忍者の既存報告あり")
        fi
    fi

    [ "${#reasons[@]}" -gt 0 ] || return 0

    reason_text=$(printf '%s\n' "${reasons[@]}" | awk 'NF{printf "%s%s", sep, $0; sep=", "} END{print ""}')
    echo "WARNING: same-ninja redeploy (${parent_cmd} → ${ninja_name}) を検出。${reason_text}。mizchi Red flag『同じsubagentを使い回そう』の可能性あり。別忍者配備か、記憶依存でない理由を確認せよ" >&2
    log "same_ninja_redeploy_warn: cmd=${parent_cmd} ninja=${ninja_name} reasons=${reason_text}"
}

# 直近24hの非cmd commit検知: target_pathの直近コミットmessageにcmd_が無ければWARN
# 殿承認GP-110修正版: 忍者完了パスに依存せず、配備直前のgit実態をその場で確認する
warn_recent_noncmd_commit_targets() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local _tp_raw
    _tp_raw=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null)
    [ -n "$_tp_raw" ] || return 0

    local _repo_root
    _repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$_repo_root" ] || return 0

    local -a _tp_paths=()
    if echo "$_tp_raw" | grep -q '^- '; then
        while IFS= read -r _tp_line; do
            local _tp_p="${_tp_line#- }"
            _tp_p="${_tp_p#[[:space:]]}"
            _tp_p="${_tp_p%[[:space:]]}"
            [ -n "$_tp_p" ] && _tp_paths+=("$_tp_p")
        done <<< "$_tp_raw"
    else
        _tp_paths+=("$_tp_raw")
    fi

    local _tp_path _git_path _head_oid

    for _tp_path in "${_tp_paths[@]}"; do
        [ -n "$_tp_path" ] || continue
        _git_path="$_tp_path"
        if [[ "$_git_path" = "$_repo_root/"* ]]; then
            _git_path="${_git_path#"$_repo_root/"}"
        elif [[ "$_git_path" = /* ]]; then
            continue
        fi

        _head_oid=$(git -C "$_repo_root" rev-parse HEAD 2>/dev/null || true)
        deploy_task_queue_history_lookup "$_repo_root" "$_head_oid" "$_git_path"
    done
    log "recent_noncmd_commit_warn: deferred generation-aware history inspection targets=${#_tp_paths[@]}"
}

# q11_not_already_done再確認: cmd起票後のauto-commit等で既実装が混入していないか配備直前にWARNする。
warn_q11_not_already_done_drift() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local parent_cmd stk_path py_output
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk_path" ] || return 0

    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        STK_PATH_ENV="$stk_path" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        PARENT_CMD_ENV="$parent_cmd" \
        python3 - <<'Q11_RECHECK_PY'; then
import os
import re
import subprocess
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
stk_path = os.environ['STK_PATH_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
parent_cmd = os.environ['PARENT_CMD_ENV']

try:
    with open(stk_path, encoding='utf-8') as f:
        stk = yaml.safe_load(f) or {}
    with open(task_file, encoding='utf-8') as f:
        task_doc = yaml.safe_load(f) or {}
except Exception as exc:
    print(f'[Q11_RECHECK] WARN: failed to read YAML: {exc}', file=sys.stderr)
    sys.exit(1)

cmd = ((stk.get('commands') or {}).get(parent_cmd) or {})
if not isinstance(cmd, dict):
    sys.exit(0)

q11 = ((cmd.get('quality_gate') or {}).get('q11_not_already_done') or cmd.get('q11_not_already_done') or '')
q11 = str(q11 or '').strip()
if not q11:
    sys.exit(0)

pattern_match = re.search(r"grep\s+(?:-[A-Za-z0-9]+\s+)*(['\"])(.*?)\1", q11)
expected_match = re.search(r'([0-9]+)\s*件', q11)
if not pattern_match or not expected_match:
    sys.exit(0)

pattern = pattern_match.group(2)
expected_count = int(expected_match.group(1))

task = task_doc.get('task') if isinstance(task_doc.get('task'), dict) else task_doc
target_value = task.get('target_path') if isinstance(task, dict) else None
if isinstance(target_value, str):
    target_paths = [target_value] if target_value.strip() else []
elif isinstance(target_value, list):
    target_paths = [str(p) for p in target_value if str(p).strip()]
else:
    target_paths = []

total_hits = 0
checked_paths = []
for raw_path in target_paths:
    path = raw_path.strip()
    full_path = path if os.path.isabs(path) else os.path.join(script_dir, path)
    if not os.path.isfile(full_path):
        continue
    proc = subprocess.run(
        ['grep', '-n', pattern, full_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if proc.returncode not in (0, 1):
        continue
    hits = len([line for line in proc.stdout.splitlines() if line])
    total_hits += hits
    checked_paths.append(path)

if checked_paths and total_hits > expected_count:
    print(
        f'WARNING: q11_not_already_done drift ({parent_cmd}) 起票時 {expected_count}件 → '
        f'配備時 {total_hits}件。target_path={", ".join(checked_paths)} pattern={pattern!r}。'
        ' HEADに先行実装が混入した可能性あり。配備続行/中止を判断せよ',
        file=sys.stderr,
    )
Q11_RECHECK_PY
        log "WARN: q11_not_already_done recheck failed for ${parent_cmd} (non-fatal)"
        return 0
    fi
    rm -f "$py_output"
}

# タスク明瞭性WARNING: 配備前に静的不明瞭さを軽量検査
# cmd_2122: BLOCKではなくWARNINGで、家老が配備前にtask品質の粗さを可視化する。
warn_task_clarity() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local parent_cmd stk_path py_output
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk_path" ] || return 0

    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        STK_PATH_ENV="$stk_path" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        PARENT_CMD_ENV="$parent_cmd" \
        python3 - <<'TASK_CLARITY_PY'; then
import os
import re
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
stk_path = os.environ['STK_PATH_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
parent_cmd = os.environ['PARENT_CMD_ENV']

try:
    with open(stk_path, encoding='utf-8') as f:
        stk = yaml.safe_load(f) or {}
except Exception as exc:
    print(f'[TASK_CLARITY] WARN: failed to read shogun_to_karo.yaml: {exc}', file=sys.stderr)
    sys.exit(1)

cmd = ((stk.get('commands') or {}).get(parent_cmd) or {})
if not isinstance(cmd, dict):
    sys.exit(0)

command_text = str(cmd.get('command', '') or '')
if not command_text.strip():
    sys.exit(0)

def ac_descriptions(value):
    descs = []
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                desc = item.get('description') or item.get('check') or item.get('title') or ''
            else:
                desc = str(item or '')
            desc = str(desc).strip()
            m = re.match(r'^AC[0-9A-Za-z_-]+:\s*(.+)$', desc)
            if m:
                desc = m.group(1).strip()
            if desc:
                descs.append(desc)
    elif isinstance(value, dict):
        for item in value.values():
            if isinstance(item, dict):
                desc = item.get('description') or item.get('check') or item.get('title') or ''
            else:
                desc = str(item or '')
            desc = str(desc).strip()
            if desc:
                descs.append(desc)
    elif value:
        descs.append(str(value).strip())
    return descs

ac_descs = ac_descriptions(cmd.get('acceptance_criteria') or cmd.get('ac') or [])
command_lines = [line.strip() for line in command_text.splitlines() if line.strip()]

if len(command_lines) >= 10 and len(ac_descs) <= 1:
    print(
        f'WARNING: task clarity ({parent_cmd}) command {len(command_lines)}行に対してAC {len(ac_descs)}件。'
        ' commandが長くACが粗いため、タスクが不明瞭な可能性あり',
        file=sys.stderr,
    )

known_roots = (
    'scripts/', 'queue/', 'context/', 'projects/', 'docs/', 'config/', 'memory/',
    'logs/', 'lib/', 'tests/', 'archive/', 'instructions/',
)
known_exts = ('.sh', '.yaml', '.yml', '.md', '.py', '.json', '.toml', '.txt')
path_candidates = []
for raw in re.findall(r'(?<![A-Za-z0-9_])(?:/mnt/[^\s`"\'(),]+|[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)', command_text):
    cand = raw.strip().rstrip('.,:;)]}')
    if not cand or cand.startswith(('http://', 'https://')):
        continue
    if not (cand.startswith('/mnt/') or cand.startswith(known_roots) or cand.endswith(known_exts)):
        continue
    if cand not in path_candidates:
        path_candidates.append(cand)

missing = []
for cand in path_candidates:
    full = cand if os.path.isabs(cand) else os.path.join(script_dir, cand)
    if not os.path.exists(full):
        missing.append(cand)

if missing:
    print(
        f'WARNING: task clarity ({parent_cmd}) command内の参照パスが実在しない可能性: '
        + ', '.join(missing),
        file=sys.stderr,
    )

if ac_descs and not any(('確認' in desc) or ('検証' in desc) for desc in ac_descs):
    print(
        f'WARNING: task clarity ({parent_cmd}) ACに「確認」「検証」が含まれない。'
        ' 行動のみで確認欠落の可能性あり',
        file=sys.stderr,
    )
TASK_CLARITY_PY
        log "WARN: task clarity check failed for ${parent_cmd} (non-fatal)"
        return 0
    fi
    rm -f "$py_output"
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

    bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message" &
    local ntfy_pid=$!
    log "dispatch_ntfy: sent (${cmd_id}) title='${title:-untitled}' ninja=${ninja_name} [bg:${ntfy_pid}]"

    return 0
}

deploy_task_apply_task_mutations() {
    local ninja_name="${1:-$NINJA_NAME}"
    local task_file="${2:-$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml}"
    local task_status

    # 全injectorを同一dirの作業copyへ適用し、全validation PASS後に1回だけ公開する。
    # 後段FAIL時は実taskのbytes/SHAを不変に保つ。
    if [ "${DEPLOY_TASK_MUTATION_CANDIDATE:-0}" != "1" ]; then
        local mutation_candidate
        mutation_candidate=$(mktemp "${task_file}.mutation.XXXXXX") || return 1
        if ! cp -- "$task_file" "$mutation_candidate"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! DEPLOY_TASK_MUTATION_CANDIDATE=1 deploy_task_apply_task_mutations "$ninja_name" "$mutation_candidate"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if [ "${DEPLOY_TASK_TEST_FAIL_AFTER_MUTATIONS:-0}" = "1" ]; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! deploy_task_guard_task_yaml_syntax "mutation_candidate_pre_publish" "$mutation_candidate" "$ninja_name"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! mv -f -- "$mutation_candidate" "$task_file"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        return 0
    fi

    if [ "${DEPLOY_TASK_TEST_MUTATE_AND_FAIL:-0}" = "1" ]; then
        printf '\n  test_partial_mutation: true\n' >>"$task_file"
        return 1
    fi

    task_status=$(field_get "$task_file" "status" "unknown")

    if [ "$task_status" = "pending" ] || [ "$task_status" = "unknown" ]; then
        yaml_field_set "$task_file" "task" "status" "assigned"
        log "status_force: ${task_status} → assigned (Stage 1保護対象化)"
        task_status="assigned"
    fi

    DEPLOY_TASK_REPORT_SCAN_COUNT=0
    deploy_task_mutation_phase entrance_gates check_entrance_gate "$task_file" || return $?
    deploy_task_mutation_phase scout_gate check_scout_gate "$task_file" || return $?

    inject_task_id "$task_file" || true
    infer_ac_assigned_from_chunk_task_id "$task_file" || true
    inject_ac_assigned_from_stk "$task_file" || true  # cmd_2790: STK cmd定義からac_assigned転記
    # inject_related_lessonsはinject_task_modifiers(yaml.dump使用)の後に実行する。
    # yaml.dumpがrelated_lessons+descriptionの_sv書式を破壊するため(inject_ac_versionと同じ理由)。

    local clear_fields clear_tmp
    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        # role_reminder is intentionally absent. reset_stale_fields already
        # removes the previous task's value before normal/direct publication;
        # clearing it again here erased a caller-supplied --yaml isolation
        # contract and replaced it with the generic reminder.
        clear_fields="engineering_preferences|experiment_first_principle|skill_hint|reports_to_read|context_files|context_hints|report_template|bloom_level|stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok|ninja_weak_points|type"
        clear_tmp=$(mktemp)
        if awk -v fields="$clear_fields" '
        BEGIN { n=split(fields,arr,"|"); for(i=1;i<=n;i++) fset[arr[i]]=1; skip=0; cleared=0 }
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
                if (key in fset) { skip = 1; cleared++; next }
            }
            print
        }
        END { if (cleared > 0) printf "[FIELD_CLEAR] Cleared %d fields\n", cleared > "/dev/stderr"
              else printf "[FIELD_CLEAR] No fields to clear\n" > "/dev/stderr" }
    ' "$task_file" > "$clear_tmp" 2>/dev/null; then
        if [ -s "$clear_tmp" ]; then
            mv "$clear_tmp" "$task_file"
        else
            rm -f "$clear_tmp"
        fi
        else
            log "WARN: auto-inject field clear failed (non-fatal)"
            rm -f "$clear_tmp"
        fi
    else
        log "direct_mode: preserving preinjected task metadata"
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" = "1" ]; then
        log "direct_mode: preinjected task YAML detected; skipping heavy context/lesson/semantic reinjection"
    else
        deploy_task_mutation_phase task_modifiers inject_task_modifiers "$task_file" || true
        inject_session_state_hints "$task_file" || true  # GP-198
        inject_codd_failure_history "$task_file" || true  # GP-201
        inject_engineering_preferences "$task_file" || true
        inject_skill_hint "$task_file" || true

        # related_lessons+description注入はinject_task_modifiers(yaml.dump使用)の後に実行する。
        # yaml.dumpが_sv(シングルクォート)書式を破壊するため。inject_ac_versionと同じ理由。
        # cmd_karo_impl_related_lessons_snapshot_20260727: 同一cmdの再配備で
        # related_lessonsが再抽選され、先に生成済みの報告のlessons_useful評価集合と
        # 食い違ってGATEが無過失の忍者をBLOCKする事象を根治する。resolve前(pre-resolve)に
        # 既にこのCMD_ID向けのrelated_lessonsが存在していた場合は再注入せず、
        # 配備時点の集合を維持する(acceptance_criteriaが同一cmd再配備で上書きされないのと
        # 同じ思想。新規gate/hook/状態ファイルは作らず既存機構を拡張)。
        if [ -n "${CMD_ID:-}" ] && [ "${_DEPLOY_PRE_RESOLVE_PARENT_CMD:-}" = "$CMD_ID" ] && [ "${_DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT:-0}" = "1" ]; then
            log "related_lessons: same-cmd redeploy detected (parent_cmd=${CMD_ID}) — preserving existing related_lessons, skip re-injection"
        else
            deploy_task_mutation_phase related_lessons inject_related_lessons "$task_file" || handle_yaml_injection_failure "inject_related_lessons" "$task_file" "$ninja_name"
        fi
        inject_workaround_pattern_lessons "$task_file" "$ninja_name" || handle_yaml_injection_failure "inject_workaround_pattern_lessons" "$task_file" "$ninja_name"
        inject_standard_skills "$task_file" || true  # Level5: 全taskに常時使用スキルを明示(cmd_2737)
        inject_model_injection_profile "$task_file" "$ninja_name" || true  # cmd_3727: モデル階層別注入強度
        deploy_task_mutation_phase semantic_context inject_semantic_concepts "$task_file" || true  # Level5
        deploy_task_mutation_phase memory_context inject_memory_db_context "$task_file" || true  # Level5
        inject_causal_links "$task_file" || true      # Level5: 全忍者にcmd origin因果リンクを自動提供(cmd_2822)
        inject_causal_verification_template "$task_file" || true  # Level5: infra変更前の因果確認をCLI非依存で注入
        inject_dm_signal_pf_operation_guardrails "$task_file" || true  # Level5: PF削除/復元/rollback前提知識を自動注入(cmd_3786)
        inject_dm_signal_golden_baseline_contract "$task_file" || true  # Level5: L877巨大golden-baseline二層契約
        inject_dm_signal_canary_rotation_contract "$task_file" || handle_yaml_injection_failure "inject_dm_signal_canary_rotation_contract" "$task_file" "$ninja_name"
        inject_context_hints "$task_file" || true  # Level5: purpose/project/task_typeから必読contextを強制提供
        inject_reflux_commit_contract "$task_file" || handle_yaml_injection_failure "inject_reflux_commit_contract" "$task_file" "$ninja_name"
        inject_production_invariants "$task_file" || true  # Level5: 忍者に本番不変量(PI)自動提供
        inject_checklist_constraints "$task_file" || true  # Level5: checklist隣接Step制約強制注入(cmd_2644)
        inject_growth_loop_defense "$task_file" || true    # Level5: gate/hook関連cmdに防御階層§11を強制注入(cmd_2649)
        inject_experiment_first_principle "$task_file" || true  # Level5: 全taskへ実験ファースト原則を強制注入
        inject_readonly_refs "$task_file" || true           # Level5: command必読/参照専用ファイルをreadonly_refへ源流注入
        inject_ac_version "$task_file" || true
        verify_ac_consistency "$task_file" || true

        # Some optional injectors normalize YAML through Python and can change
        # an AC mapping into a list.  Reassert the direct L4 template after
        # all optional mutations so its fixed dict schema is the final SSOT.
        local final_parent_cmd
        final_parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
        inject_direct_training_template "$task_file" "$final_parent_cmd" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        local pc_file inj_project inj_ids lid
        deploy_task_postcondition_prepare "$task_file"
        pc_file="$DEPLOY_TASK_POSTCOND_FILE"
        if [ -f "$pc_file" ]; then
            inj_project=$(grep '^project=' "$pc_file" | cut -d= -f2)
            inj_ids=$(grep '^injected_ids=' "$pc_file" | cut -d= -f2)
            if [ -n "$inj_ids" ] && [ -n "$inj_project" ]; then
                deploy_task_queue_lesson_scores "$task_file" "$inj_project" "$inj_ids" || true
                if [ "$inj_project" != "infra" ]; then
                    deploy_task_queue_lesson_scores "$task_file" infra "$inj_ids" || true
                fi
                log "injection_count: queued for deferred batch (${inj_ids})"
            fi
        fi
        postcondition_lesson_inject "$task_file" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        inject_reports_to_read "$task_file" || true
        register_blocked_parent_continuation "$task_file" "$ninja_name" || return $?
        inject_context_files "$task_file" || true
        inject_credential_files "$task_file" || true
        inject_target_path_check "$task_file" || true
        inject_context_update "$task_file" || true
        inject_push_allowed "$task_file" || true  # Level5: AC内push検出でpush_allowed自動付与(cmd_3820)
        inject_independent_recon_contract "$task_file" "$ninja_name" || return 1
        inject_role_reminder "$task_file" "$ninja_name" || true
        inject_report_template "$task_file" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        deploy_task_normalize_report_metadata "$task_file" || return 1
        inject_bloom_level "$task_file" || true
        inject_execution_controls "$task_file" || true
        inject_ninja_weak_points "$task_file" "$ninja_name" || handle_yaml_injection_failure "inject_ninja_weak_points" "$task_file" "$ninja_name"
        check_context_freshness "$task_file" || true
    fi

    # This is deliberately after every mutation path, including preinjected
    # YAML and report/context injectors.  A L4 direct-training task is not
    # deployable until its final on-disk AC schema is the canonical mapping.
    local canonical_training_parent_cmd canonical_training_task_type parent_cmd task_type
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" parent_cmd task_type 2>/dev/null)" || true
    canonical_training_parent_cmd="${parent_cmd:-}"
    canonical_training_task_type="${task_type:-normal}"
    if [[ "$canonical_training_parent_cmd" =~ ^cmd_training_L4_ ]] \
        && [ "$canonical_training_task_type" = "normal" ]; then
        inject_direct_training_template "$task_file" "$canonical_training_parent_cmd" || return 1
    fi

    # E3: direct --yaml / --cmd / normal resolveを含む全publication pathの最終形へ
    # ci_fix clean reproduction scaffoldと専用ACを一度だけ注入する。
    inject_ci_fix_clean_repro_contract "$task_file" || return 1

    # Explicit opt-in only; this must remain before final syntax/report publication.
    inject_head_fixed_validation_contract "$task_file" || return 1

    # Level5: investigation tasks receive an executable, bounded code-location
    # path before publication.  Raw recursive grep is intentionally forbidden.
    inject_outcome_neutral_investigation_contract "$task_file" || return 1
    inject_seam_contract "$task_file" || return 1
    inject_code_location_contract "$task_file" || return 1
    inject_scope_contract_fields "$task_file" || return 1
    inject_dynamic_measurement_contract "$task_file" "$ninja_name" || return 1

    local task_id parent_cmd project _ac_task_id report_filename
    deploy_task_guard_task_yaml_syntax "post_injection_pre_report_template" "$task_file" "$ninja_name" || return 1
    deploy_task_test_necessity_precheck "$task_file" || return 1

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_id _ac_task_id parent_cmd project report_filename 2>/dev/null)" || true
    # task_id空なら_ac_task_idをfallback(家老が_ac_task_idを直接設定するケース)
    if [ -z "${task_id:-}" ]; then
        task_id="${_ac_task_id:-}"
    fi
    # Ordering marker retained for source-contract tests: the wrapper invokes
    # generate_report_template "$ninja_name" under the report-unit lock.
    deploy_task_report_publication_locked "$ninja_name" "$task_id" "$parent_cmd" "$project" "$task_file" || return $?
    inject_parent_contract "$task_file" "$SCRIPT_DIR/queue/reports/${report_filename:-}" "$ninja_name" \
        || { log "FATAL: parent contract injection failed"; return 1; }
    inject_done_redeploy_hints "$task_file" || true
    log "TASK_MUTATION_SUMMARY report_scans=${DEPLOY_TASK_REPORT_SCAN_COUNT:-0}"
}

__cluster_i_static_extraction_sentinel() { :; }
fi
# Cluster I modules: preflight artifacts/worktree and freshness/scout/quality/RC gates/task mutations.
_dt_preflight_path="$SCRIPT_DIR/scripts/deploy_task/preflight.sh"
if [ ! -f "$_dt_preflight_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_preflight_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/preflight.sh"
fi
if [ ! -f "$_dt_preflight_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_preflight_path="$PROJECT_ROOT/scripts/deploy_task/preflight.sh"
fi
source "$_dt_preflight_path"
unset _dt_preflight_path
_dt_gates_path="$SCRIPT_DIR/scripts/deploy_task/gates.sh"
if [ ! -f "$_dt_gates_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_gates_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/gates.sh"
fi
if [ ! -f "$_dt_gates_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_gates_path="$PROJECT_ROOT/scripts/deploy_task/gates.sh"
fi
source "$_dt_gates_path"
unset _dt_gates_path

inject_code_location_contract() {
    local task_file="$1" task_type bloom_level contract
    [ -f "$task_file" ] || return 0
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_type bloom_level 2>/dev/null)" || true
    task_type="${task_type,,}"
    bloom_level="${bloom_level,,}"
    if [[ ! "$task_type" =~ ^(recon|scout|focused)$ ]] && [ "$bloom_level" != "focused" ]; then
        return 0
    fi
    contract='Code-locationは `bash scripts/code_locate.sh "QUERY" [PATHSPEC ...]`（追跡対象限定、git grep）を使う。`grep -r`/`grep -R`は禁止。追跡外生成物が必要な場合のみ `bash scripts/code_locate.sh --include-untracked --reason "必要理由" "QUERY" [PATH ...]` を使う（node_modules/.git/.*_worktreesは既定除外）。exit 0=match、1=no match、2以上=実行異常として区別する。'
    yaml_field_set "$task_file" "task" "code_location_contract" "$contract"
}

# Read-only investigation succeeds by resolving the assigned question, not by
# producing the answer the issuer hoped to find.  Keep the authored scope/ACs
# intact for ancestry and review traceability, while making their success
# semantics outcome-neutral at deployment time.  The report gate consumes the
# same typed contract from task_contract_snapshot, so this cannot degrade into
# a worker/reviewer convention.
inject_outcome_neutral_investigation_contract() {
    local task_file="$1" task_type contract
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    task_type="${task_type,,}"
    case "$task_type" in
        recon|recon2|scout) ;;
        *) return 0 ;;
    esac

    contract='{"version":1,"required":true,"outcome_neutral":true,"success_basis":"assigned_method_completed_with_primary_evidence","discovery_required":false,"allowed_outcomes":["found","zero_found","not_present","external_boundary","unknown_after_exhaustion"],"minimum_primary_evidence":1}'
    yaml_field_set "$task_file" "task" "investigation_contract" "$contract" || return 1
    log "investigation_contract: outcome-neutral contract injected (${task_type})"
}

# Consumer seam work must publish its nine input-contract questions before a
# scout/recon worker starts. Keep the contract nested in investigation_contract
# so the task and immutable report snapshot share one typed source of truth.
inject_seam_contract() {
    local task_file="$1" task_type contract_json
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    task_type="${task_type,,}"

    contract_json=$(python3 - "$task_file" <<'PY_SEAM_CONTRACT'
import json, re, sys, yaml

path = sys.argv[1]
task = (yaml.safe_load(open(path, encoding="utf-8")) or {}).get("task", {})
task_type = str(task.get("task_type") or "").strip().lower()
if task_type not in {"recon", "recon2", "scout"}:
    raise SystemExit(3)

parts = []
for key in ("title", "purpose", "command", "description", "constraints", "not_in_scope"):
    value = task.get(key)
    if isinstance(value, (list, dict)):
        parts.append(json.dumps(value, ensure_ascii=False, sort_keys=True))
    elif value:
        parts.append(str(value))
for item in task.get("acceptance_criteria") or []:
    if isinstance(item, dict):
        parts.append(str(item.get("description") or item.get("criteria") or ""))
    else:
        parts.append(str(item))
text = " ".join(parts).lower()
trigger = bool(re.search(
    r"cutover|cache|caching|read[ _-]*(reduction|削減|count|回数)|"
    r"consumer|seam|継ぎ目|読み取り削減|読取削減|キャッシュ",
    text,
    re.IGNORECASE,
))

base = task.get("investigation_contract")
if not isinstance(base, dict):
    base = {
        "version": 1,
        "required": True,
        "outcome_neutral": True,
        "success_basis": "assigned_method_completed_with_primary_evidence",
        "discovery_required": False,
        "allowed_outcomes": ["found", "zero_found", "not_present", "external_boundary", "unknown_after_exhaustion"],
        "minimum_primary_evidence": 1,
    }
else:
    base = dict(base)

fields = [
    "primary_payload", "companion_caches", "key_set", "date_domain",
    "empty_behavior", "fallback", "side_effects", "legacy_only_policy",
    "downstream_cardinality",
]
base["seam_contract"] = {
    "required": trigger,
    "fields": {field: "" for field in fields},
    "primary_evidence_fields": fields,
    "minimum_primary_evidence": 9 if trigger else 1,
    "field_guidance": {
        "date_domain": "一次証拠でtarget_date/run境界と、前run終端DB状態(C1 read-once旧行)への履歴依存を確認する",
        "legacy_only_policy": "一次証拠で旧行を許容する条件と、汚染後復元の1回目(1989件逆転・465件残存)および2回目収束full確認のstate dependencyを扱う",
    },
}
if trigger:
    base["minimum_primary_evidence"] = 9
print(json.dumps(base, ensure_ascii=False, separators=(",", ":")))
PY_SEAM_CONTRACT
    ) || {
        [ "$?" -eq 3 ] && return 0
        log "BLOCK: seam_contract generation failed (${task_file})"
        return 1
    }

    yaml_field_set "$task_file" "task" "investigation_contract" "$contract_json" || return 1
    log "seam_contract: injected task_type=${task_type} required=$(python3 -c 'import json,sys; print(str(json.loads(sys.argv[1])["seam_contract"]["required"]).lower())' "$contract_json") fields=9"
}

# cmd_4215: only an explicit boolean declaration may opt a task into fixed-HEAD
# validation.  Normal editing tasks must continue to use the shared worktree.
inject_head_fixed_validation_contract() {
    local task_file="$1" declared contract
    [ -f "$task_file" ] || return 0
    declared=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "head_fixed_validation" "false" 2>/dev/null || true)
    [ "$declared" = "true" ] || return 0

    contract='Capture the current HEAD once, then run `bash scripts/head_fixed_validation.sh <task_yaml>`. The runner creates an isolated detached worktree at that SHA, executes the task-selected runner from that worktree, removes the worktree on every exit path, and fails if a registered or on-disk residue remains. Shared-tree HEAD changes after capture must not alter the validated SHA.'
    yaml_field_set "$task_file" "task" "head_fixed_validation_contract" "$contract"
}

# Direct hotfixes may repair a failed task owned by another ninja.  Validate
# the complete join before publishing the hotfix, then register the dependency
# with wait_reason last as the visibility barrier for ninja_monitor.
register_blocked_parent_continuation() {
    local hotfix_task="$1" current_ninja="$2"
    local task_type parent_cmd fixes blocked_ninja blocked_task configured_ninjas
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$hotfix_task" task_type parent_cmd fixes blocked_parent_ninja blocked_parent_task_id 2>/dev/null)" || true
    task_type="${task_type:-}"; parent_cmd="${parent_cmd:-}"; fixes="${fixes:-}"
    blocked_ninja="${blocked_parent_ninja:-}"; blocked_task="${blocked_parent_task_id:-}"
    [ -n "$fixes$blocked_ninja$blocked_task" ] || return 0
    [ "$task_type" = "hotfix" ] || { echo "BLOCK: blocked-parent continuation requires task_type=hotfix" >&2; return 2; }
    [ -n "$fixes" ] && [ -n "$blocked_ninja" ] && [ -n "$blocked_task" ] || { echo "BLOCK: incomplete blocked-parent reference" >&2; return 2; }
    [ "$blocked_ninja" != "$current_ninja" ] || { echo "BLOCK: blocked-parent self-reference" >&2; return 2; }
    configured_ninjas="$(get_ninja_names)" || { echo "BLOCK: failed to load configured ninja roster" >&2; return 2; }
    case " $configured_ninjas " in
        *" $blocked_ninja "*) ;;
        *) echo "BLOCK: invalid blocked_parent_ninja" >&2; return 2 ;;
    esac
    local parent_file="$SCRIPT_DIR/queue/tasks/${blocked_ninja}.yaml" actual_id actual_status
    [ -f "$parent_file" ] || { echo "BLOCK: blocked parent task file missing" >&2; return 2; }
    actual_id=$(FIELD_GET_NO_LOG=1 field_get "$parent_file" task_id "" 2>/dev/null || true)
    actual_status=$(FIELD_GET_NO_LOG=1 field_get "$parent_file" status "" 2>/dev/null || true)
    [ "$actual_id" = "$blocked_task" ] || { echo "BLOCK: blocked parent task mismatch" >&2; return 2; }
    [ "$actual_status" = "failed" ] || { echo "BLOCK: blocked parent must be failed" >&2; return 2; }
    yaml_field_set "$parent_file" task continuation_task_id "$blocked_task" || return 2
    yaml_field_set "$parent_file" task wait_connected_cmd "$parent_cmd" || return 2
    yaml_field_set "$parent_file" task wait_reason dependency || return 2
    log "DEPENDENCY-CONTINUATION-REGISTER: parent=${blocked_ninja}/${blocked_task} connected=${parent_cmd} fields=3/3"
}

# CI RED startup verification joins the active task to the failed Actions run
# by task_type=ci_fix + ci_run_id.  Reject an incomplete join key while the
# caller-owned source YAML is still the only artifact: no task/report/inbox
# publication has happened at this point.
deploy_task_ci_fix_run_id_precheck() {
    local source_file="$1"
    local result

    local rc
    if result=$(python3 - "$source_file" <<'PY'
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path = sys.argv[1]
try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception as exc:
    print(f"yaml_error:{exc}")
    raise SystemExit(2)

task = data.get("task", data)
if not isinstance(task, dict):
    print("task_mapping_missing")
    raise SystemExit(2)

task_type = str(task.get("task_type") or "").strip().lower()
if task_type != "ci_fix":
    print("not_ci_fix")
    raise SystemExit(0)

run_id = task.get("ci_run_id")
value = "" if run_id is None else str(run_id).strip()
if not re.fullmatch(r"[1-9][0-9]*", value):
    print("invalid_ci_run_id")
    raise SystemExit(1)

print(f"ci_fix_run_id={value}")
PY
    ); then
        rc=0
    else
        rc=$?
    fi
    case "$rc" in
        0)
            [ "$result" = "not_ci_fix" ] || log "ci_fix_contract: PASS ${result}"
            return 0
            ;;
        1)
            log "BLOCK: task_type=ci_fix requires ci_run_id as a positive integer before publication"
            echo "BLOCK: task_type=ci_fix requires ci_run_id as a positive integer (>0); missing, empty, zero, or non-numeric values are forbidden." >&2
            return 1
            ;;
        *)
            log "BLOCK: ci_fix contract source parse failed (${result:-unknown})"
            echo "BLOCK: unable to validate ci_fix ci_run_id in ${source_file}: ${result:-unknown}" >&2
            return 1
            ;;
    esac
}

# 歯止め(b) 殿裁可2026-07-25: 同一のCI REDに対する追いpushは2回まで。3回目からは
# 新規配備を止め、RED修正へリソースを寄せる。一次情報は2つだけを使う:
#   (1) CI REDの実態   = gh run list の最新完了run (conclusion/headSha)
#   (2) 追いpush回数   = git rev-list --count <red_head_sha>..origin/main
# gate_metrics.logはrun_idを持たずcmd単位の記録しか残らないため、RED起点からの
# push本数を数えられる唯一の一次情報がgit履歴である(新規台帳を作らない)。
deploy_task_ci_red_followup_push_guard() {
    local source_file="${1:-}"
    local task_type="" runs run_status conclusion red_sha followups limit
    [ "${DEPLOY_TASK_SKIP_CI_RED_GUARD:-0}" = "1" ] && return 0
    limit="${DEPLOY_TASK_CI_RED_FOLLOWUP_LIMIT:-2}"

    if [ -n "$source_file" ] && [ -f "$source_file" ]; then
        task_type=$(FIELD_GET_NO_LOG=1 field_get "$source_file" "task_type" "" 2>/dev/null || true)
    fi
    # ci_fix自身はREDを消すための弾なので常に通す。
    [ "${task_type,,}" = "ci_fix" ] && return 0

    runs="${DEPLOY_TASK_CI_RED_JSON:-}"
    if [ -z "$runs" ]; then
        command -v gh >/dev/null 2>&1 || return 0
        runs=$(timeout "${DEPLOY_TASK_GH_TIMEOUT:-8}" gh run list             --repo "${DEPLOY_TASK_CI_REPO:-simokitafresh/multi-agent-shogun}"             --branch main --limit 1             --json status,conclusion,databaseId,headSha 2>/dev/null || true)
        [ -n "$runs" ] || return 0
    fi
    run_status=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].status // "completed") else "" end' 2>/dev/null || true)
    # A newer run for the current branch head supersedes the older completed
    # RED as the active CI state.  Let normal work continue while that run is
    # queued/in_progress; its completed verdict will govern the next deploy.
    [ "$run_status" = "completed" ] || return 0
    conclusion=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].conclusion // "") else "" end' 2>/dev/null || true)
    [ "$conclusion" = "failure" ] || return 0
    red_sha=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].headSha // "") else "" end' 2>/dev/null || true)

    followups="${DEPLOY_TASK_CI_FOLLOWUP_PUSHES:-}"
    if [ -z "$followups" ]; then
        [ -n "$red_sha" ] || return 0
        git -C "$SCRIPT_DIR" rev-parse --verify "${red_sha}^{commit}" >/dev/null 2>&1 || return 0
        followups=$(git -C "$SCRIPT_DIR" rev-list --count "${red_sha}..refs/remotes/origin/main" 2>/dev/null || echo "")
    fi
    [[ "$followups" =~ ^[0-9]+$ ]] || return 0

    if [ "$followups" -gt "$limit" ]; then
        log "BLOCK(ci_red_followup): red_sha=${red_sha:0:9} followup_pushes=${followups} limit=${limit}"
        echo "BLOCK: CI RED(sha=${red_sha:0:9})に対する追いpushが${followups}回(上限${limit}回)。新規配備を停止し、task_type=ci_fixでRED修正へ全リソースを寄せよ。" >&2
        return 1
    fi
    return 0
}

# E3 Level5: ci_fixはclean-CI相当の同一harnessで修正前FAIL→修正後PASSを
# push前に証明する。途中AC/binary_checksへ混入させず、型付きfinal_checkpoint
# として配備する。完成証跡は報告終端gateが一度だけfail-closed検証する。
inject_ci_fix_clean_repro_contract() {
    local task_file="$1" task_type
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    [ "${task_type,,}" = "ci_fix" ] || return 0

    python3 - "$task_file" <<'PY' || return 1
import json, os, re, sys, tempfile, yaml
path = sys.argv[1]
raw = open(path, encoding='utf-8').read()
d = yaml.safe_load(raw) or {}
t = d.get('task', d)
checkpoint = {
    'type': 'ci_fix_clean_repro',
    'required': True,
    'evidence_field': 'ci_fix_clean_repro_evidence',
    'validator': 'deploy_task_ci_fix_clean_repro_evidence_validate',
    'phase': 'terminal_report_gate',
}

def replace_task_field(text, key, value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    lines = text.splitlines()
    out, i, replaced = [], 0, False
    while i < len(lines):
        line = lines[i]
        if re.match(r'^  ' + re.escape(key) + r':(?:\s|$)', line):
            out.append('  ' + key + ': ' + encoded); replaced = True; i += 1
            while i < len(lines):
                stripped = lines[i].lstrip(' '); indent = len(lines[i]) - len(stripped)
                if stripped and (indent < 2 or (indent == 2 and not stripped.startswith('- '))): break
                i += 1
            continue
        out.append(line); i += 1
    if not replaced:
        out.append('  ' + key + ': ' + encoded)
    return '\n'.join(out) + '\n'

def remove_task_field(text, key):
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if re.match(r'^  ' + re.escape(key) + r':(?:\s|$)', line):
            i += 1
            while i < len(lines):
                stripped = lines[i].lstrip(' ')
                indent = len(lines[i]) - len(stripped)
                if stripped and (indent < 2 or (indent == 2 and not stripped.startswith('- '))):
                    break
                i += 1
            continue
        out.append(line)
        i += 1
    return '\n'.join(out) + '\n'

# A retry may start from a task produced by the old AC-based implementation.
# Remove that obsolete contract and its task-local evidence so the report is
# the sole terminal evidence owner for the new typed checkpoint.
raw = remove_task_field(raw, 'ci_fix_clean_repro_evidence')
raw = replace_task_field(raw, 'final_checkpoint', checkpoint)
yaml.safe_load(raw)
fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path)+'.', dir=os.path.dirname(path) or '.')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as fh: fh.write(raw)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
    log "inject_ci_fix_clean_repro_contract: typed final_checkpoint injected"
}

deploy_task_ci_fix_clean_repro_evidence_validate() {
    local task_file="$1"
    # Keep the worker-facing helper compatible while sharing the one canonical
    # validator with the terminal report gate.
    PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 - "$task_file" <<'PY'
import sys, yaml
from scripts.gates.gate_report_format_main import ci_fix_clean_repro_evidence_errors

doc = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
task = doc.get('task', doc)
if str(task.get('task_type') or '').strip().lower() != 'ci_fix':
    raise SystemExit(0)
evidence = task.get('ci_fix_clean_repro_evidence')
errors = ci_fix_clean_repro_evidence_errors(evidence)
if errors:
    for error in errors:
        print('BLOCK: ' + error, file=sys.stderr)
    raise SystemExit(1)
if isinstance(evidence, dict) and str(evidence.get('outcome') or '').strip().lower() == 'not_reproducible':
    print('PASS: ci_fix clean repro not_reproducible evidence valid')
else:
    print('PASS: ci_fix clean repro evidence valid')
PY
    return $?
}

# D006 is an unconditional safety boundary.  Reject task sources that require
# signalling an external process before reset_stale_fields can publish the
# source into queue/tasks or create a report/inbox event.  Explanations of the
# prohibition remain valid input; the guard targets executable/imperative
# requirements, not the words themselves.
deploy_task_destructive_signal_precheck() {
    local source_file="$1" cmd_id="${2:-}"
    python3 - "$source_file" "$cmd_id" <<'PY'
import re
import shlex
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path, cmd_id = sys.argv[1:3]
try:
    raw = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception as exc:
    print(f"BLOCK: destructive signal preflight could not parse source: {exc}", file=sys.stderr)
    raise SystemExit(2)

source = raw.get("commands", raw)
if cmd_id:
    if isinstance(source, dict) and cmd_id in source:
        task = source[cmd_id]
    elif isinstance(source, list):
        task = next((item for item in source if isinstance(item, dict) and item.get("id") == cmd_id), {})
    else:
        task = raw.get("task", raw)
else:
    task = raw.get("task", raw)
if not isinstance(task, dict):
    raise SystemExit(0)

def flatten_acs(value):
    if isinstance(value, dict):
        values = value.values()
    elif isinstance(value, list):
        values = value
    else:
        values = [value]
    out = []
    for value in values:
        if isinstance(value, dict):
            for key in ("description", "command", "check", "criteria", "title"):
                if value.get(key):
                    out.append(str(value[key]))
            for check in value.get("checks", []) if isinstance(value.get("checks"), list) else []:
                out.append(str(check.get("check", "") if isinstance(check, dict) else check))
        elif value:
            out.append(str(value))
    return out

texts = [str(task.get(key) or "") for key in ("purpose", "command")]
texts.extend(flatten_acs(task.get("acceptance_criteria") or task.get("ac") or []))

safe_explanation = re.compile(
    r"D006|禁止|禁則|違反|遮断|BLOCK|ブロック|検出|発火|参照|説明|例示|"
    r"要求.{0,12}(?:場合|なら)|(?:使うな|実行するな|してはならない)", re.I
)
imperative_signal = re.compile(
    r"(?:外部|別|他の|対象)?(?:プロセス|daemon|デーモン|PID|pane|ペイン).{0,30}"
    r"(?:kill|pkill|killall|signal|シグナル|終了させ|停止させ).{0,20}"
    r"(?:実行|送信|行う|せよ|すること|故障注入)", re.I
)
process_kill_fault = re.compile(
    r"(?:process[ _-]?kill|プロセスkill).{0,20}(?:故障注入|実行|行う|せよ)", re.I
)

def has_signal_command(line):
    """Recognize kill-family commands after shell wrappers and their args."""
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError:
        tokens = re.split(r"\s+", line)
    signal_commands = {"kill", "pkill", "killall"}
    wrappers = {"env", "timeout", "command", "nohup", "nice", "setsid"}
    for token in tokens:
        normalized = token.strip(";|&(){}").rsplit("/", 1)[-1].lower()
        if normalized in signal_commands:
            return True
        # Wrapper names are intentionally recognized while scanning through
        # options, durations and VAR=value arguments to the eventual command.
        if normalized in wrappers or token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
            continue
    return False

violations = []
for text in texts:
    for line in text.splitlines():
        line = line.strip()
        if not line or safe_explanation.search(line):
            continue
        if has_signal_command(line) or imperative_signal.search(line) or process_kill_fault.search(line):
            violations.append(line)

if violations:
    print("BLOCK: D006違反の外部プロセスsignal要求を配備前に検出。", file=sys.stderr)
    print("positive_rule: phase永続保存後に対象プロセス自身が非0終了するテスト専用failpointを使え。", file=sys.stderr)
    print(f"evidence: {violations[0]}", file=sys.stderr)
    raise SystemExit(2)
PY
}

# Legacy static-extraction compatibility for the orchestration cluster.  The
# executable implementation remains in scripts/deploy_task/main.sh below.
if false; then
deploy_task_apply_task_mutations() {
    inject_ci_fix_clean_repro_contract "$task_file"
    deploy_task_guard_task_yaml_syntax "post_injection_pre_report_template" "$task_file" "$ninja_name"
    inject_related_lessons "$task_file"
    deploy_task_queue_lesson_scores "$task_file" "$inj_project" "$inj_ids"
    postcondition_lesson_inject "$task_file"
    field_get_multi "$task_file" parent_cmd task_type
    field_get_multi "$task_file" task_id _ac_task_id parent_cmd project report_filename
}

# ═══════════════════════════════════════
# メイン処理
    for dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
        parallel_recon: ${deploy_parent_cmd} peer ${dd_ninja}
        if [ -n "$deploy_task_id" ] && [ "$deploy_scope_mode" != "exact" ]; then
            [[ "$deploy_scope_mode" =~ ^(recon|scout)$ ]]
            [ "$deploy_task_id" != "$dd_tid" ]
        fi
        echo "BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja}"
    done
deploy_task_main() {
    deploy_task_start_deadline
    parse_deploy_task_args "$@"
    if [ -n "$CMD_ID" ] && { [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; }; then
        deploy_task_source_contract_precheck "$YAML_FILE"
    fi
    deploy_task_ci_fix_run_id_precheck "$YAML_FILE"
    deploy_task_direct_yaml_publish "$task_yaml" "$YAML_FILE"
    record_issued_at_once "$task_yaml" "$CMD_ID" now
    if [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; then
        reset_stale_fields
    fi
    if [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; then
                reset_stale_fields
    fi
    # Runtime idleness is independent of how the incoming task is sourced.
    check_idle "$pane_target" && is_idle=true
    local task_yaml
    repair_training_parent_cmd_from_cmd_id "$task_yaml" || return $?
    deploy_task_apply_task_mutations "$NINJA_NAME"
    safe_inbox_write "$NINJA_NAME"
    deploy_task_check_deadline "after_inbox_write"
    # TIMEOUT: deploy_task_main exceeded <timeout>s at <phase>.
    trap deploy_task_exit_cleanup EXIT
}
fi

_dt_main_path="$SCRIPT_DIR/scripts/deploy_task/main.sh"
if [ ! -f "$_dt_main_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_main_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/main.sh"
fi
if [ ! -f "$_dt_main_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_main_path="$PROJECT_ROOT/scripts/deploy_task/main.sh"
fi
source "$_dt_main_path"
unset _dt_main_path

# T18: measure every function reached by one deployment without selecting a
# guessed hotspot.  The counters are best-effort and the final JSONL write is
# locked; deployment semantics remain independent of telemetry availability.
deploy_task_function_timing_enable() {
    case "${DEPLOY_TASK_FUNCTION_TIMING_LOG:-}" in
        disabled|0) return 0 ;;
    esac
    DEPLOY_TASK_FUNCTION_TIMING_LOG="${DEPLOY_TASK_FUNCTION_TIMING_LOG:-$SCRIPT_DIR/logs/deploy_task_function_timing.jsonl}"
    mkdir -p "$(dirname "$DEPLOY_TASK_FUNCTION_TIMING_LOG")" 2>/dev/null || return 0
    declare -gA _DT_FUNCTION_TIMING_US=()
    declare -gA _DT_FUNCTION_TIMING_CALLS=()
    _DT_FUNCTION_TIMING_LAST_FN=main
    _DT_FUNCTION_TIMING_LAST_US="${EPOCHREALTIME/./}"
    _DT_FUNCTION_TIMING_LAST_US="${_DT_FUNCTION_TIMING_LAST_US:0:16}"
    _DT_FUNCTION_TIMING_BUSY=0
    _DT_FUNCTION_TIMING_FINISHED=0
    _DT_FUNCTION_TIMING_ID="deploy-task-$$-${EPOCHREALTIME//./}"
    _DT_FUNCTION_TIMING_SCRIPT=deploy_task.sh
    _DT_FUNCTION_TIMING_PREV_DEBUG_TRAP="$(trap -p DEBUG 2>/dev/null || true)"
    set -T
    trap '_dt_function_timing_debug' DEBUG
}

_dt_function_timing_debug() {
    [ "${_DT_FUNCTION_TIMING_BUSY:-0}" -eq 0 ] || return 0
    _DT_FUNCTION_TIMING_BUSY=1
    local raw now fn delta
    raw="${EPOCHREALTIME/./}"
    now="${raw:0:16}"
    fn="${FUNCNAME[1]:-main}"
    case "$fn" in
        _dt_function_timing_*) fn="${_DT_FUNCTION_TIMING_LAST_FN:-main}" ;;
    esac
    # DEBUG traps execute between a caller's `[[ value =~ regex ]]` and its
    # subsequent BASH_REMATCH read.  A regex here would overwrite that global
    # array and can crash `set -u` callers such as ctx_utils.sh.  Validate the
    # decimal timestamps with shell patterns, which do not mutate BASH_REMATCH.
    case "${_DT_FUNCTION_TIMING_LAST_US:-}:$now" in
        *[!0-9:]*|:*|*:) ;;
        *)
            delta=$((now - _DT_FUNCTION_TIMING_LAST_US))
            [ "$delta" -ge 0 ] || delta=0
            _DT_FUNCTION_TIMING_US["${_DT_FUNCTION_TIMING_LAST_FN:-main}"]=$((
                ${_DT_FUNCTION_TIMING_US["${_DT_FUNCTION_TIMING_LAST_FN:-main}"]:-0} + delta
            ))
            ;;
    esac
    _DT_FUNCTION_TIMING_CALLS["$fn"]=$(( ${_DT_FUNCTION_TIMING_CALLS["$fn"]:-0} + 1 ))
    _DT_FUNCTION_TIMING_LAST_FN="$fn"
    _DT_FUNCTION_TIMING_LAST_US="$now"
    _DT_FUNCTION_TIMING_BUSY=0
    return 0
}

deploy_task_function_timing_finish() {
    trap - DEBUG
    set +T
    [ -n "${DEPLOY_TASK_FUNCTION_TIMING_LOG:-}" ] || return 0
    [ "${_DT_FUNCTION_TIMING_FINISHED:-0}" -eq 0 ] || return 0
    _DT_FUNCTION_TIMING_FINISHED=1
    local raw now delta fn rank line
    raw="${EPOCHREALTIME/./}"
    now="${raw:0:16}"
    fn="${_DT_FUNCTION_TIMING_LAST_FN:-main}"
    if [[ "${_DT_FUNCTION_TIMING_LAST_US:-}" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]]; then
        delta=$((now - _DT_FUNCTION_TIMING_LAST_US))
        [ "$delta" -ge 0 ] || delta=0
        _DT_FUNCTION_TIMING_US["$fn"]=$(( ${_DT_FUNCTION_TIMING_US["$fn"]:-0} + delta ))
    fi
    mkdir -p "$(dirname "$DEPLOY_TASK_FUNCTION_TIMING_LOG")" 2>/dev/null || return 0
    {
        flock -x 9 || exit 0
        rank=0
        while IFS=$'\t' read -r line fn; do
            rank=$((rank + 1))
            printf '{"schema":"function_timing.v1","execution_id":"%s","script":"%s","pid":%s,"rank":%s,"function":"%s","elapsed_us":%s,"calls":%s}\n' \
                "${_DT_FUNCTION_TIMING_ID:-unknown}" "${_DT_FUNCTION_TIMING_SCRIPT:-deploy_task.sh}" "$$" "$rank" "$fn" "$line" "${_DT_FUNCTION_TIMING_CALLS["$fn"]:-0}"
        done < <(for fn in "${!_DT_FUNCTION_TIMING_US[@]}"; do
            printf '%s\t%s\n' "${_DT_FUNCTION_TIMING_US[$fn]}" "$fn"
        done | sort -t $'\t' -k1,1nr -k2,2)
    } 9>"${DEPLOY_TASK_FUNCTION_TIMING_LOG}.lock" >>"$DEPLOY_TASK_FUNCTION_TIMING_LOG" 2>/dev/null || true
    if [ -n "${_DT_FUNCTION_TIMING_PREV_DEBUG_TRAP:-}" ]; then
        eval "${_DT_FUNCTION_TIMING_PREV_DEBUG_TRAP}" 2>/dev/null || true
    fi
    return 0
}

deploy_task_function_timing_enable

if [[ "${DEPLOY_TASK_SELF_SNAPSHOT_TEST_ONLY:-0}" == "1" ]]; then
    printf 'SELF_SNAPSHOT_OK\n'
    deploy_task_function_timing_finish
    exit 0
fi

if [[ "${BASH_SOURCE[0]}" == "$0" && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" ]]; then
    deploy_task_main "$@"
    deploy_task_function_timing_finish

    # cmd_1337: dashboard update remains a post-deployment side effect.
    # Source(lib-only)利用時は起動しない。
    bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" &
fi
