#!/usr/bin/env bash
# deploy_task/resolve.sh — cluster D: CLI, pane/idle, stale reset, direct YAML, cmd resolution.
# Function bodies are extracted verbatim from deploy_task.sh.
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
