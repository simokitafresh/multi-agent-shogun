#!/bin/bash
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

set -euo pipefail

# cmd_2078: SCRIPT_DIR string ops — $(cd dirname pwd)サブシェル2個→bash文字列演算 (~10ms節約)
_dt_self="${BASH_SOURCE[0]}"
[[ "$_dt_self" != /* ]] && _dt_self="$PWD/$_dt_self"
SCRIPT_DIR="${_dt_self%/scripts/deploy_task.sh}"
unset _dt_self
LOG="$SCRIPT_DIR/logs/deploy_task.log"

# cli_lookup.sh — CLI Profile SSOT参照（CLI種別判定・パターン取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/ctx_utils.sh"
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/firefighting_keywords.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"

# WSL2 NTFS最適化: field_getの依存ログ(flock+stat+write)を抑制。65回×20ms=1.3s削減
export FIELD_GET_NO_LOG=1

DEFAULT_MESSAGE="前taskの情報は無効。タスクYAMLを最初から読み直して作業開始せよ。"
DIRECT_MODE=false
YAML_FILE=""
NINJA_NAME=""
CMD_ID=""
CMD_FORCED=""
MESSAGE="$DEFAULT_MESSAGE"
TYPE="task_assigned"
FROM="karo"

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

parse_deploy_task_args() {
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
        current_notify_flag="$SCRIPT_DIR/queue/gates/${current_parent_cmd}/gunshi_notify_${ninja_name}.done"
        if [ -f "$current_notify_flag" ]; then
            rm -f "$current_notify_flag"
            log "[STALE_RESET] Removed stale gunshi notify flag for ${ninja_name}: queue/gates/${current_parent_cmd}/gunshi_notify_${ninja_name}.done"
        fi
    fi

    python3 - "$task_file" <<'STALE_FIELD_RESET_PY'
import os, sys, tempfile, yaml, re

task_file = sys.argv[1]
# スカラー+リスト両方を確実にクリアするフィールド一覧
STALE_FIELDS = [
    # 第1層: cmd固有メタデータ(スカラー)
    'purpose', 'target_path', 'constraints', 'progress', 'description', 'deployed_at',
    # 第2層: inject_task_modifiers.pyが「存在チェック」するフィールド(リスト含む)
    'engineering_preferences', 'context_files', 'stop_for', 'never_stop_for',
    'ac_priority', 'ac_checkpoint', 'parallel_ok',
    # 第3層: 忍者書込み+per-cmdフラグ
    'AC1', 'AC2', 'AC3', 'acceptance_criteria', 'scout_exempt', 'binary_checks',
    # 第4層: 旧版由来の残留フィールド(現在の配備パイプラインでは設定されないが使い回しで残る)
    'command', 'reports_to_read', 'credential_warning', 'context_update',
    # 第5層: task_typeと重複するレガシーフィールド(修行001 hayate発見)
    'type', 'report_template',
    # 第9層: resolve_cmd_to_taskで上書きされるが安全網(cmd_2231 saizo stale contamination: title/report_path残留)
    'title', 'report_path', 'report_filename', 'assigned_acs',
    # 第6層: ネスト残留+旧メタデータ(cmd_1527発見: 前cmdの全task:ブロックが残留)
    'task', 'worker_id', 'timestamp',
    # 第7層: GP-198 session state (新cmd配備時に前cmdの失敗履歴をクリア)
    'session_state', 'previous_failures',
    # 第8層: GP-201 CoDD failure history (CoDD改善cmd配備時にregistryから再注入するため毎回クリア)
    'codd_failure_history',
    # 第10層: inject_related_lessons/inject_task_modifiersで毎回再注入されるが、
    # 配備前に旧値が残るとCodex忍者がSTALLする(LK092: cmd_2250 hayate STALL実証)
    'related_lessons', 'ninja_weak_points', 'role_reminder', 'bloom_level',
]

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

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

# ─── --yamlモード: task YAMLに記録されたスクリプトの鮮度チェック ───
# command欄から "bash scripts/..." or "scripts/..." パターンを抽出し、
# YAML作成後にgitコミットされたスクリプトがあればWARN。BLOCKにはしない（段階的導入）。
check_yaml_freshness() {
    local yaml_file="$1"
    local git_root="$2"

    # command欄からスクリプトパスを抽出（bash scripts/foo.sh または scripts/foo.sh 形式）
    local script_paths
    script_paths=$(grep -oE '(bash )?scripts/[^ "\\]+\.sh' "$yaml_file" 2>/dev/null \
        | sed 's/^bash //' | sort -u)

    [ -z "$script_paths" ] && return 0

    # YAMLファイルのmtime (Unix epoch秒)
    local yaml_mtime
    yaml_mtime=$(stat -c %Y "$yaml_file" 2>/dev/null || echo 0)

    while IFS= read -r script_path; do
        [ -z "$script_path" ] && continue

        # git log で最新commit時刻とhashを取得
        local commit_iso commit_hash commit_epoch
        commit_iso=$(git -C "$git_root" log -1 --format="%aI" -- "$script_path" 2>/dev/null || true)
        [ -z "$commit_iso" ] && continue

        commit_epoch=$(date -d "$commit_iso" +%s 2>/dev/null || true)
        [ -z "$commit_epoch" ] && continue

        commit_hash=$(git -C "$git_root" log -1 --format="%h" -- "$script_path" 2>/dev/null || true)

        if [ "$commit_epoch" -gt "$yaml_mtime" ]; then
            echo "[DEPLOY] WARN: ${script_path} はYAML作成後に更新されている(commit: ${commit_hash})。task YAMLを再作成せよ" >&2
        fi
    done <<< "$script_paths"
}

# ─── cmd_id→task YAML自動解決（なぜなぜL5根因対策: 家老の手動ステップ排除） ───
# cmd_id指定時、shogun_to_karo.yamlからメタデータを取得しtask YAMLの中核フィールドを自動設定。
# これにより「task YAML更新 → deploy_task.sh」の2ステップが原子的操作になる。
resolve_cmd_to_task() {
    local cmd_id="$1"
    local ninja_name="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"

    if [ ! -f "$stk" ]; then
        log "resolve_cmd: ERROR shogun_to_karo.yaml not found"
        return 1
    fi

    # shogun_to_karo.yamlからcmdメタデータ抽出（awk方式: Python subprocess除去 cmd_deploy_yaml_speedup）
    local _resolve_output
    _resolve_output=$(awk -v cmd="$cmd_id" '
        /^  [^ ]/ {
            if (in_cmd) { exit }
            s = $0; sub(/^  /, "", s); sub(/:.*/, "", s)
            if (s == cmd) { in_cmd = 1; next }
        }
        in_cmd && /^    [a-z_]+:/ {
            key = $0; sub(/^    /, "", key); sub(/:.*/, "", key)
            val = $0; sub(/^[^:]+:[[:space:]]*/, "", val)
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
        log "resolve_cmd: ${cmd_id} not found in shogun_to_karo.yaml"
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

    # LK054: depends_on検出時にAC単位依存分析を促すWARN
    if [ -n "$_depends_on" ]; then
        echo "WARN: depends_on=${_depends_on} 検出。全ACが依存先に本当に依存するか？並列可能なACはないか？(LK054)" >&2
    fi

    local task_id="${cmd_id}_${task_type}"

    # R1: task YAMLの中核フィールドを一括設定（7回flock→1回batch。CoDD refactor_sequence準拠）
    local _deploy_ts
    _deploy_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    local _batch_args=("parent_cmd=$cmd_id" "task_id=$task_id" "task_type=$task_type" "status=assigned" "_ac_task_id=" "_ac_worker_id=" "_deploy_notice=STALE TASK INVALID. This YAML is the latest instruction for ${cmd_id} (deployed ${_deploy_ts}). Read from the beginning.")
    [ -n "$project" ] && _batch_args+=("project=$project")
    [ -n "$purpose" ] && _batch_args+=("purpose=$purpose")
    [ -n "$_target_path" ] && _batch_args+=("target_path=$_target_path")
    # scout_exempt: STKからtask YAMLに転記（reset_stale_fieldsでクリアされるため復元が必要）
    [ "$_scout_exempt_stk" = "true" ] && _batch_args+=("scout_exempt=true")
    yaml_field_set_batch "$task_file" "task" "${_batch_args[@]}" \
        || { log "FATAL: yaml_field_set_batch failed for resolve_cmd_to_task"; return 1; }

    log "resolve_cmd: ${cmd_id} → ninja=${ninja_name}, task_id=${task_id}, project=${project:-none}, type=${task_type}, title=${title}"
    return 0
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

    yaml_field_set "$task_file" "task" "task_id" "$subtask_id" \
        || { log "FATAL: yaml_field_set failed for task_id (inject_task_id)"; return 1; }
    log "inject_task_id: set task_id=$subtask_id"
}

# ─── ac_version自動注入（cmd_530: stale作業検知, cmd_1053: ハッシュ化, cmd_1493: 再配備AC上書き） ───
# acceptance_criteriaの各descriptionをソート→連結→md5先頭8桁をtask.ac_versionとして保持。
# 件数が同じでも内容が変われば異なるハッシュになる。再配備時に再計算される。
# cmd_1493: ac_version同一でもtask_id/worker_id変更時はcmdソースからAC上書き
# cmd_1393: Python→awk+md5sum置換

# ─── _compute_ac_hash: ACハッシュ計算ヘルパー ───
_compute_ac_hash() {
    local task_file="$1"
    local concat
    concat=$(awk '
        BEGIN { in_ac=0; in_item=0; desc=""; n=0 }
        /^[[:space:]]*acceptance_criteria:/ {
            ac_indent = match($0, /[^ ]/) - 1
            in_ac=1; next
        }
        !in_ac { next }
        {
            if (match($0, /[^ ]/)) ci = RSTART - 1; else next
            if (ci <= ac_indent && $0 !~ /^[[:space:]]*-/) {
                if (in_item) { descs[n++]=desc; desc=""; in_item=0 }
                in_ac=0; next
            }
            if ($0 ~ /^[[:space:]]*- /) {
                if (in_item) { descs[n++]=desc; desc="" }
                in_item=1; next
            }
            if (in_item) {
                line=$0; sub(/^[[:space:]]+/,"",line)
                if (line ~ /^description:/) {
                    sub(/^description:[[:space:]]*/,"",line)
                    sub(/[[:space:]]*$/,"",line)
                    gsub(/^["'"'"']|["'"'"']$/,"",line)
                    desc=line
                }
            }
        }
        END {
            if (in_item) descs[n++]=desc
            for(i=0;i<n;i++) for(j=i+1;j<n;j++) if(descs[i]>descs[j]){t=descs[i];descs[i]=descs[j];descs[j]=t}
            r=""
            for(i=0;i<n;i++){if(i>0)r=r"|"; r=r descs[i]}
            printf "%s",r
        }
    ' "$task_file" 2>/dev/null)
    printf '%s' "$concat" | md5sum | cut -c1-8
}

# ─── _overwrite_ac_from_cmd: cmdソースからAC上書き（cmd_1493） ───
# shogun_to_karo.yaml → archive/cmds/ の順でparent_cmdのACを探し、task YAMLに上書き。
# 教訓マーカー(【注入教訓】)もクリアして再注入を促す。
_overwrite_ac_from_cmd() {
    local task_file="$1"
    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    [ -z "$parent_cmd" ] && return 1

    local py_output
    py_output=$(mktemp)
    if python3 - "$task_file" "$parent_cmd" "$SCRIPT_DIR" <<'OVERWRITE_AC_PY' > "$py_output" 2>&1; then
import glob
import os
import re
import sys
import tempfile

import yaml

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
        if isinstance(criteria, list):
            entry['checks'] = [{'check': str(c)} for c in criteria]
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
            result.append({'id': ac_id, 'checks': [{'check': ac_text}]})
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
def _sv(v):
    if v is None: return 'null'
    if isinstance(v, bool): return str(v).lower()
    if isinstance(v, (int, float)): return str(v)
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('  ' + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq + sq) + sq
def _yaml_lines(key, val, ind=0):
    p = ' ' * ind
    if not isinstance(val, (dict, list)):
        s = _sv(val)
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
        s = _sv(item)
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
                sv = _sv(v) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
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

# Clear lesson injection marker so inject_related_lessons re-injects with new ACs
raw = re.sub(r'【注入教訓】.*?─{10,}\n\n?', '', raw, flags=re.DOTALL)

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

inject_ac_version() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_ac_version: task file not found: $task_file"
        return 0
    fi

    local ac_version
    ac_version=$(_compute_ac_hash "$task_file")

    local prev
    prev=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")

    # R2: field_get 6-7回→field_get_multi 1回(CoDD batch_read_flow準拠)
    local curr_task_id curr_worker_id prev_ac_task_id prev_ac_worker_id
    local task_id="" _ac_task_id="" worker_id="" _ac_worker_id=""
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_id _ac_task_id worker_id _ac_worker_id)"
    # task_idが空なら_ac_task_idをfallback(家老が_ac_task_idを直接設定するケース)
    if [ -z "$task_id" ]; then
        curr_task_id="$_ac_task_id"
    else
        curr_task_id="$task_id"
    fi
    if [ -z "$worker_id" ]; then
        curr_worker_id="$_ac_worker_id"
    else
        curr_worker_id="$worker_id"
    fi
    prev_ac_task_id="$_ac_task_id"
    prev_ac_worker_id="$_ac_worker_id"

    if [ "$curr_task_id" != "$prev_ac_task_id" ] || [ "$curr_worker_id" != "${prev_ac_worker_id:-}" ]; then
        log "[AC_VERSION] deploy detected (task_id: ${prev_ac_task_id:-empty}→${curr_task_id}, worker: ${prev_ac_worker_id:-empty}→${curr_worker_id}). Overwriting ACs from cmd source."
        if _overwrite_ac_from_cmd "$task_file"; then
            ac_version=$(_compute_ac_hash "$task_file")
            log "[AC_VERSION] recomputed after AC overwrite: $ac_version"
        else
            log "[AC_VERSION] WARN: AC overwrite failed, keeping existing ACs"
        fi
    fi

    # R2: yaml_field_set 3回→batch 1回(CoDD batch_write_flow準拠)
    yaml_field_set_batch "$task_file" "task" \
        "ac_version=$ac_version" \
        "_ac_task_id=$curr_task_id" \
        "_ac_worker_id=$curr_worker_id" \
        || { log "FATAL: yaml_field_set_batch failed for inject_ac_version"; return 1; }

    if [ "$prev" = "$ac_version" ]; then
        log "[AC_VERSION] unchanged: $ac_version"
    else
        log "[AC_VERSION] set: $prev -> $ac_version"
    fi
}

# ─── verify_ac_consistency: task YAML vs cmdソースのAC件数・ID突合（cmd_1619） ───
# inject_ac_version後に実行。不一致時はWARNING。BLOCKではない（配備続行）。
verify_ac_consistency() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 0
    fi

    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    [ -z "$parent_cmd" ] && return 0

    local py_output
    py_output=$(mktemp)
    python3 - "$task_file" "$parent_cmd" "$SCRIPT_DIR" <<'VERIFY_AC_PY' > "$py_output" 2>&1 || true
import glob
import os
import sys

import yaml

task_file = sys.argv[1]
parent_cmd = sys.argv[2]
script_dir = sys.argv[3]

def extract_ac_id(entry):
    """AC entryからIDを抽出。'AC1: desc' → 'AC1', {id: 'AC1'} → 'AC1'"""
    if isinstance(entry, str):
        colon_idx = entry.find(':')
        if colon_idx > 0:
            return entry[:colon_idx].strip()
        return entry.strip()
    if isinstance(entry, dict):
        if 'id' in entry:
            return str(entry['id'])
        for k in entry:
            return str(k)
    return str(entry)

def _extract_acs_from_cmd(cmd):
    acs = cmd.get('acceptance_criteria')
    if acs:
        if isinstance(acs, (list, dict)):
            return acs
    ac_nested = cmd.get('ac')
    if ac_nested and isinstance(ac_nested, dict):
        return list(ac_nested.keys())
    return None

def find_cmd_acs(pcmd, sdir):
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

def to_list(acs):
    if isinstance(acs, dict):
        return [{'id': k, 'value': v} for k, v in acs.items()]
    if isinstance(acs, list):
        return acs
    return []

# Load task YAML
with open(task_file, encoding='utf-8') as f:
    task_data = yaml.load(f, Loader=yaml.SafeLoader) or {}
task = task_data.get('task', task_data)
task_acs = to_list(task.get('acceptance_criteria', []))

# Load cmd source ACs
cmd_acs_raw = find_cmd_acs(parent_cmd, script_dir)
if cmd_acs_raw is None:
    print(f'[AC_VERIFY] SKIP: No cmd source found for {parent_cmd}', file=sys.stderr)
    sys.exit(0)
cmd_acs = to_list(cmd_acs_raw)

task_count = len(task_acs)
cmd_count = len(cmd_acs)

# AC1: Count comparison
if task_count != cmd_count:
    print(f'[AC_VERIFY] WARNING: AC count mismatch — task={task_count} cmd_source={cmd_count} (parent_cmd={parent_cmd})', file=sys.stderr)

# AC2: ID comparison
task_ids = [extract_ac_id(a) for a in task_acs]
cmd_ids = [extract_ac_id(a) for a in cmd_acs]

if task_count == cmd_count:
    mismatched = []
    for i, (tid, cid) in enumerate(zip(task_ids, cmd_ids)):
        if tid != cid:
            mismatched.append(f'{i}: task={tid} cmd={cid}')
    if mismatched:
        print(f'[AC_VERIFY] WARNING: AC id mismatch — {"; ".join(mismatched)} (parent_cmd={parent_cmd})', file=sys.stderr)
    elif task_count > 0:
        print(f'[AC_VERIFY] OK: AC count={task_count} ids match (parent_cmd={parent_cmd})', file=sys.stderr)
else:
    print(f'[AC_VERIFY] WARNING: AC ids — task={task_ids} cmd_source={cmd_ids} (parent_cmd={parent_cmd})', file=sys.stderr)
VERIFY_AC_PY
    log "$(cat "$py_output")"
    rm -f "$py_output"
    return 0
}

# ─── 報告YAML雛形生成（cmd_138: lesson_candidate欠落防止） ───
is_before_after_required_task() {
    local task_file="$1"
    local parent_cmd="$2"
    local task_title task_type

    # cmd_1983: 第3・第4引数が渡された場合はpre-read値を使用（field_get subprocess削減）
    if [[ ${3+x} ]] && [[ ${4+x} ]]; then
        task_title="$3"
        task_type="$4"
    else
        task_title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null)
        task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null)
    fi

    case "$parent_cmd" in
        cmd_karo_gp*) return 0 ;;
    esac

    case "${task_type,,}" in
        gp|improvement) return 0 ;;
    esac

    case "$task_title" in
        GP*|強化*|改善*|*"GP/"*|*" GP "*|*"改善"*|*"強化"*) return 0 ;;
    esac

    return 1
}

_apply_binary_check_waivers() {
    local task_file="$1"
    local bc_full="$2"

    TASK_FILE_ENV="$task_file" BC_FULL_ENV="$bc_full" python3 - <<'PY_BC_WAIVE'
import os
import sys

import yaml


def to_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        if text.startswith('[') and text.endswith(']'):
            text = text[1:-1]
        return [part.strip().strip('"\'') for part in text.replace(',', ' ').split() if part.strip()]
    return [str(value).strip()] if str(value).strip() else []


def is_research_target(path):
    raw = str(path or '').strip().strip('"\'')
    if not raw:
        return False
    normalized = raw.replace('\\', '/')
    stripped = normalized
    while stripped.startswith('./'):
        stripped = stripped[2:]
    prefixes = ('outputs', 'docs/research')
    if any(stripped == prefix or stripped.startswith(prefix + '/') for prefix in prefixes):
        return True
    if '/outputs/' in normalized or normalized.endswith('/outputs'):
        return True
    if '/docs/research/' in normalized or normalized.endswith('/docs/research'):
        return True
    return False


task_path = os.environ['TASK_FILE_ENV']
bc_full = os.environ['BC_FULL_ENV']

try:
    with open(task_path, encoding='utf-8') as f:
        task_raw = yaml.safe_load(f) or {}
except Exception:
    print(bc_full.rstrip())
    raise SystemExit(0)

task = task_raw.get('task', task_raw)

try:
    parsed = yaml.safe_load(bc_full) or {}
except Exception:
    print(bc_full.rstrip())
    raise SystemExit(0)

bc = parsed.get('binary_checks')
if not isinstance(bc, dict):
    print(bc_full.rstrip())
    raise SystemExit(0)

waive_ac = set(to_list(task.get('waive_ac')))

scope_mode = str(task.get('scope_mode') or task.get('task_type') or task.get('type') or '')
targets = to_list(task.get('target_path'))
is_research = ('RESEARCH' in scope_mode.upper()) or (bool(targets) and all(is_research_target(p) for p in targets))

for ac_id in waive_ac:
    items = bc.get(ac_id)
    if not isinstance(items, list):
        continue
    for item in items:
        if not isinstance(item, dict):
            continue
        item['result'] = 'no'
        item['waive_reason'] = 'waive_ac指定'

if is_research:
    items = bc.get('commit')
    if isinstance(items, list):
        for item in items:
            if not isinstance(item, dict):
                continue
            item['result'] = 'no'
            if not str(item.get('waive_reason') or '').strip():
                item['waive_reason'] = '研究cmd: commit不要'

print(yaml.safe_dump({'binary_checks': bc}, allow_unicode=True, sort_keys=False).rstrip())
PY_BC_WAIVE
}

generate_report_template() {
    local ninja_name="$1"
    local task_id="$2"
    local parent_cmd="$3"
    local project="$4"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local report_file=""
    local report_rel_path=""

    # cmd_1983: 12+ field_get → field_get_multi 1回 (WSL2 subprocess削減)
    # task_id・parent_cmd はパラメータと同名のため上書き前にコピー
    local _p_task_id="$task_id" _p_parent_cmd="$parent_cmd"
    local report_filename assigned_to subtask_id task_id _ac_task_id parent_cmd \
          ac_version title task_type target_path scout_exempt type scope_mode
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        report_filename assigned_to subtask_id task_id _ac_task_id \
        parent_cmd ac_version title task_type target_path scout_exempt \
        type scope_mode 2>/dev/null)" || true

    # report_filenameフィールドを優先参照（cmd_412: 命名ミスマッチ根治）
    if [ -n "$report_filename" ]; then
        report_file="$SCRIPT_DIR/queue/reports/${report_filename}"
    elif [[ -n "$_p_parent_cmd" && "$_p_parent_cmd" == cmd_* ]]; then
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${_p_parent_cmd}.yaml"
    else
        # 後方互換: parent_cmdが未設定/不正なら旧形式にフォールバック
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    fi
    report_rel_path="queue/reports/$(basename "$report_file")"

    mkdir -p "$SCRIPT_DIR/queue/reports"

    # GP-084改: gawk BEGINFILE/ENDFILE一括でverdict+parent_cmdを抽出（field_get逐次→一括化）
    # 報告ファイルが増えてもI/O 1回で済む（旧: N×field_get, 新: 1×gawk）
    declare -A _rpt_verdict _rpt_pcmd
    local _gawk_output
    _gawk_output=$(gawk '
        BEGINFILE { pcmd=""; verd="" }
        /^parent_cmd:/ { sub(/^parent_cmd:[[:space:]]*/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); sub(/[[:space:]]*$/, ""); pcmd=$0 }
        /^verdict:/ { sub(/^verdict:[[:space:]]*/, ""); sub(/^["'"'"']/, ""); sub(/["'"'"']$/, ""); sub(/[[:space:]]*$/, ""); verd=$0 }
        ENDFILE { printf "%s\t%s\t%s\n", FILENAME, pcmd, verd }
    ' "$SCRIPT_DIR/queue/reports/"*_report_*.yaml 2>/dev/null) || true
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
    for stale_own_report in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml; do
        [ -f "$stale_own_report" ] || continue
        stale_own_basename=$(basename "$stale_own_report")
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

    # 冪等性: 既存テンプレートがあればスキップ（L060: 上書き防止）
    if [ -f "$report_file" ]; then
        log "report_template: already exists, skipping (${report_file})"
        yaml_field_set "$task_file" "task" "report_path" "$report_rel_path"
        log "report_path: set (${report_rel_path})"
        return 0
    fi

    # タスクYAMLから自動記入値を取得（cmd_532: 機械的フィールド自動記入）
    # cmd_1983: field_get_multiで一括取得済み → 変数参照のみ
    local worker_id="${assigned_to:-$ninja_name}"
    local resolved_task_id="${subtask_id}"
    if [ -z "$resolved_task_id" ]; then
        resolved_task_id="${task_id:-$_p_task_id}"
    fi
    # task_id系が全て空なら_ac_task_idをfallback
    if [ -z "$resolved_task_id" ]; then
        resolved_task_id="${_ac_task_id}"
    fi
    local resolved_parent_cmd="${parent_cmd:-$_p_parent_cmd}"
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

    cat > "$report_file" <<EOF
# !! トップレベル構造を維持せよ。report: で包むな !!
# !! report_field_set.sh で各フィールドを設定せよ。直接Edit/Write禁止 !!
# Step1: Read this file → Step2: bash scripts/report_field_set.sh <this_file> <key> <value> で各フィールドを埋めよ
# ━━━ report_field_set.sh ドット記法クイックリファレンス ━━━
# RFS="bash scripts/report_field_set.sh <このファイル>"
# \$RFS result.summary "要約文"
# \$RFS result.details "詳細文"
# \$RFS lesson_candidate.found "false"
# \$RFS lesson_candidate.no_lesson_reason "既知パターンL084"
# \$RFS verdict "PASS"
# echo '[{check: "内容", result: "yes"}]' | \$RFS binary_checks.AC1 -
# !! スペース区切り(lesson_candidate found false)は不可 → ドット記法必須 !!
# ━━━ 提出手順（番号順に実行せよ）━━━
# 1. 内容記入: result.summary/details, purpose_validation, lesson_candidate, files_modified
# 2. 構造記入: binary_checks全result→yes/no, lessons_useful全reason記入, verdict→PASS/FAIL, status→completed
# 3. gate実行: bash scripts/gates/gate_report_format.sh <このファイル>
# 4. PASS確認後: inbox_writeで家老に報告
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
files_modified: []
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
  no_lesson_reason: FILL_THIS  # found:false時に必須。理由を1文で書け。理由なきfalseは家老差し戻し(L247)
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
binary_checks: {}  # AC完了ごとに ACN: [{check: "確認内容", result: "yes/no"}] を記入
# ⚠ result値は "yes" or "no" のみ。true/false/PASS/FAIL/OK等はBLOCKされる
# 例: echo '[{check: "コメント追加済みか", result: "yes"}]' | \$RFS binary_checks.AC1 -
# ─── self gate（cmd_karo_self_gate_template: 全報告テンプレートへ標準注入） ───
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: ""  # 全binary_checks完了後に PASS / FAIL / PASS_NO_IMPROVEMENT を記入(status_detailではない)
# ━━━ 提出前最終確認（gate実行前に全項目を確認せよ）━━━
# □ binary_checks: 全ACの全result欄に "yes" or "no" を記入したか（"PASS"不可）
# □ lessons_useful: 全reason欄に有用/無用の具体的理由を記入したか
# □ verdict: "PASS" or "FAIL" を記入したか
# □ status: completed に変更したか
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    # cmd_1131+cmd_1393: related_lessonsが存在する場合、lessons_usefulを記入用雛形に差替え（Python→bash/awk）
    local _lu_ids
    _lu_ids=$(awk '
        /^  related_lessons:/ { in_rl=1; next }
        in_rl && /^  [a-z]/ { exit }
        in_rl && /id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); gsub(/['"'"']/, ""); print }
    ' "$task_file" 2>/dev/null)

    if [ -z "$_lu_ids" ]; then
        # GP-088: related_lessonsなし or id抽出不能 → null→[]に変換
        if grep -q 'lessons_useful: null' "$report_file" 2>/dev/null; then
            sed -i 's/lessons_useful: null/lessons_useful: []  # ★教訓なし。追加教訓があればid\/useful\/reason形式で記入/' "$report_file"
            log "report_template: lessons_useful null→[] fallback"
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
    reason: ''  # 例: \"L246のreturn 1罠と一致し、set -e呼出元確認の指針として有用\" / \"今回の変更では未使用。対象箇所と無関係\""
            _lu_count=$((_lu_count + 1))
        done <<< "$_lu_ids"

        # report内のlessons_useful: nullを差し替え
        if grep -q 'lessons_useful: null' "$report_file" 2>/dev/null; then
            awk -v repl="$_lu_block" '
                /lessons_useful: null/ { print repl; next }
                { print }
            ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
            log "lessons_useful template: ${_lu_count} entries injected"
            log "report_template: lessons_useful template injected"
        fi
    fi

    # cmd_1260+cmd_1393: acceptance_criteriaのbinary_checksをreportに事前展開（Python→bash/awk）
    # GP-194: ac_assigned フィールド読み込み（分割配備時の担当AC範囲制限）
    # 両フォーマット対応: inline "[AC1,AC2]" と yaml.dump後の multi-line "- AC1"
    local _ac_assigned_filter=""
    _ac_assigned_filter=$(awk '
        /^  ac_assigned:[[:space:]]*\[/ {
            s=$0; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
            n=split(s, a, /[[:space:]]*,[[:space:]]*/);
            out=""
            for(i=1;i<=n;i++) { gsub(/[[:space:]"'"'"']/, "", a[i]); if(a[i]!="") out=(out=="")?a[i]:(out"|"a[i]) }
            print out; exit
        }
        /^  ac_assigned:[[:space:]]*$/ { in_aa=1; next }
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
        function normalize_check_text(text, ac_desc, out) {
            out = text
            if (ac_desc ~ /(monthly|月次)/ && out !~ /進行中月除外/) {
                out = out " (進行中月除外)"
            }
            if (out ~ /全テストPASS\(bats --jobs 4 tests\/unit\)/) {
                out = "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
            }
            return out
        }
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0 && in_filter(cur_id)) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(chk[i], cur_desc) }
            }
            cur_id=""; cur_desc=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
            if (/description:/) {
                s=$0; sub(/.*description:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s)
                while (s ~ /^["'"'"']/) sub(/^["'"'"']/, "", s)
                while (s ~ /["'"'"']$/) sub(/["'"'"']$/, "", s)
                cur_desc=s
            }
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    description:/ {
            sub(/.*description:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
            while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
            cur_desc=$0
        }
        in_ac && /    - check:/ {
            sub(/.*- check:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
            while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
            cc++
            chk[cc]=$0
        }
        END {
            if (cur_id != "" && cc > 0 && in_filter(cur_id)) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(chk[i], cur_desc) }
            }
        }
    ' "$task_file" 2>/dev/null)

    # cmd_1512: Standard commit check - skip for scout/recon (no code changes)
    # cmd_1983: field_get_multiで一括取得済み → task_type変数を直接使用
    local _deploy_task_type="${task_type}"
    local _commit_bc=""
    if [ "$_deploy_task_type" != "scout" ] && [ "$_deploy_task_type" != "recon" ]; then
        _commit_bc='  commit:
  - check: "git commitが完了したか(untracked/modified=0)"
    result: ""  # yes or no'
    fi

    # cmd_1838: gitignore対象ファイルのみ変更するcmdのcommit checkを自動でno設定
    if [ -n "$_commit_bc" ]; then
        # cmd_1983: field_get_multiで一括取得済み → 変数参照
        local _tp_raw="${target_path}"
        local _scout_exempt="${scout_exempt}"
        # GP-190改: task fileはstale resetで消えるためSTKも確認。task fileが残っている場合(テスト等)は優先
        if [ "$_scout_exempt" != "true" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ] && [ -n "$_p_parent_cmd" ]; then
            _scout_exempt=$(awk -v cmd="$_p_parent_cmd" '
                /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
                cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
            ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null)
        fi
        # GP-190修正: scout_exempt=trueはscout gate免除フラグ。commit要否とは独立。
        # impl taskはscout_exemptに関わらずcommit checkが必要。
        # (scout/recon taskはline 1336でcommit_bcが生成されないためここに到達しない)
        if [ -n "$_tp_raw" ]; then
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
                for _tp_p in "${_tp_paths[@]}"; do
                    if ! git -C "$SCRIPT_DIR" check-ignore -q "$_tp_p" 2>/dev/null; then
                        _all_ignored=false
                        break
                    fi
                done
                if [ "$_all_ignored" = "true" ]; then
                    _commit_bc='  commit:
  - check: "git commitが完了したか(untracked/modified=0)"
    result: "no"  # gitignore対象ファイルのみ: commit不要'
                    log "binary_checks: commit check auto-set to no (all target_path are gitignored)"
                fi
            fi
        fi
    fi

    # GP-190: cmd制約(commit禁止)検出 → commit checkにwaive_reason付きno設定
    # 根因: bc設計に「正当なno」の概念がなかった。waive_reasonで事実を歪めずgate通過可能にする
    if [ -n "$_commit_bc" ]; then
        local _cmd_command=""
        _cmd_command=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$CMD_ID" "command" 2>/dev/null || true)
        if echo "$_cmd_command" | grep -qiE 'commit.*禁止|commit一切禁止|登録.*のみ.*commit'; then
            _commit_bc='  commit:
  - check: "git commitが完了したか(untracked/modified=0)"
    result: "no"
    waive_reason: "cmd制約: commit禁止"'
            log "binary_checks: commit check waived (cmd constraint: commit禁止)"
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
            function normalize_check_text(text, ac_desc, out) {
                out = text
                if (ac_desc ~ /(monthly|月次)/ && out !~ /進行中月除外/) {
                    out = out " (進行中月除外)"
                }
                if (out ~ /全テストPASS\(bats --jobs 4 tests\/unit\)/) {
                    out = "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
                }
                return out
            }
            /^  acceptance_criteria:/ { in_ac=1; next }
            in_ac && /^  [a-z]/ { exit }
            in_ac && /^  - / {
                if (cur_id != "" && in_filter(cur_id)) {
                    printf "  %s:\n", cur_id
                    if (desc != "") {
                        n = split(desc, parts, "。")
                        for (i=1; i<=n; i++) {
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                            if (parts[i] != "") printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(parts[i], desc)
                        }
                    } else {
                        printf "  - check: \"FILL: %sの確認項目を記入\"\n    result: \"\"  # yes or no\n", cur_id
                    }
                }
                cur_id=""; desc=""
                if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
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
            in_ac && /^    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0; next }
            in_ac && /^    description:/ {
                sub(/.*description:[[:space:]]*/, ""); sub(/[[:space:]]*$/, "")
                while ($0 ~ /^["'"'"']/) sub(/^["'"'"']/, "")
                while ($0 ~ /["'"'"']$/) sub(/["'"'"']$/, "")
                desc=$0
                next
            }
            END {
                if (cur_id != "" && in_filter(cur_id)) {
                    printf "  %s:\n", cur_id
                    if (desc != "") {
                        n = split(desc, parts, "。")
                        for (i=1; i<=n; i++) {
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                            if (parts[i] != "") printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", normalize_check_text(parts[i], desc)
                        }
                    } else {
                        printf "  - check: \"FILL: %sの確認項目を記入\"\n    result: \"\"  # yes or no\n", cur_id
                    }
                }
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
        awk -v repl="$_bc_full" -v placeholder="$_bc_placeholder" '
            index($0, placeholder) { print repl; next }
            { print }
        ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
        if [ -n "$_bc_block" ]; then
            local _bc_ac_count
            _bc_ac_count=$(echo "$_bc_block" | grep -c '^\s\s[A-Z]')
            log "binary_checks template: ${_bc_ac_count} ACs + commit check injected"
        else
            log "binary_checks template: standard commit check injected"
        fi
        log "report_template: binary_checks template injected"
    fi

    # cmd_1734: ninja_weak_points.gate_fail_top3 を報告テンプレートの該当フィールド直上コメントへ注入
    REPORT_FILE_ENV="$report_file" TASK_FILE_ENV="$task_file" python3 - <<'PY_GATE_WARN'
import os
from pathlib import Path

import yaml

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

    # cmd_2161: gate_report_format 学習済みパターンが閾値超なら、空欄再発しやすい項目を
    # FILL_THIS placeholder に昇格して template state を明示する。
    REPORT_FILE_ENV="$report_file" \
    LEARNING_FILE_ENV="${GATE_REPORT_FORMAT_LEARNING_FILE:-$SCRIPT_DIR/logs/gate_report_format_learning.yaml}" \
    python3 - <<'PY_LEARNED_PREFILL'
import os
import re
from pathlib import Path

import yaml

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
lu_note = "# AUTO-PREFILL: gate_report_format学習済み — reason空欄再発防止。FILL_THISを具体理由へ置換せよ"
bc_note = "# AUTO-PREFILL: gate_report_format学習済み — result空欄再発防止。FILL_THISをyes/noへ置換せよ"
summary_note = "# AUTO-PREFILL: gate_report_format学習済み — result.summary空欄再発防止。FILL_THISを要約へ置換せよ"
files_note = "# AUTO-PREFILL: gate_report_format学習済み — files_modified未記入再発防止。FILL_THISを変更ファイル一覧へ置換せよ"

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
                new_lines.append("  - FILL_THIS")
                continue
        new_lines.append(line)
        continue

    if in_lessons and "lessons_useful.reason" in active_fields and "FILL_THIS" not in line:
        line = re.sub(r"^(\s+reason:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r"\1 FILL_THIS\2", line)

    if in_binary_checks and "binary_checks.result" in active_fields and "FILL_THIS" not in line:
        line = re.sub(r"^(\s+result:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r"\1 FILL_THIS\2", line)

    if in_result and "result.summary" in active_fields and "FILL_THIS" not in line:
        line = re.sub(r"^(\s+summary:)\s*(?:''|\"\")(\s*(?:#.*)?)$", r"\1 FILL_THIS\2", line)

    new_lines.append(line)

report_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY_LEARNED_PREFILL
    log "report_template: learned prefills injected"

    # cmd_754: 偵察タスクにはimplementation_readiness欄を追加
    # cmd_1983: field_get_multiで一括取得済み → task_type/type/scope_mode変数を参照
    local report_task_type="${task_type:-${type:-${scope_mode}}}"
    report_task_type=$(echo "$report_task_type" | tr '[:upper:]' '[:lower:]')
    if [ "$report_task_type" = "recon" ] || [ "$report_task_type" = "scout" ]; then
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
RECON_EOF
        log "report_template: added implementation_readiness (recon/scout)"
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
import csv
import datetime
import fnmatch
import os
import random
import re
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

DEDUP_THRESHOLD = 0.25
USEFUL_RATE_THRESHOLD = 0.30  # useful_rate below this → score decay (0.15→0.30: 忍者成長速度改善3)
USEFUL_RATE_DECAY = 0.3       # multiplier for low useful_rate lessons (0.5→0.3: より積極的に低有効教訓を退場)

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

USEFUL_RATE_MIN_SAMPLES = 5  # feedback件数がこの値未満の教訓にはdecayを適用しない

def compute_useful_rates(script_dir):
    """lesson_impact.tsvのfeedback行からlesson別useful_rateを算出。
    feedback行(action='feedback')がある教訓はそちらで計算（忍者の実フィードバック）。
    feedback行がない教訓はrateを返さない（decayなし=安全側）。
    MIN_SAMPLES未満の教訓もdecay対象外（サンプル不足でのペナルティ防止）。"""
    impact_path = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    if not os.path.exists(impact_path):
        return {}
    feedback_counts = {}  # lesson_id -> [useful_count, total_feedback_count]
    try:
        with open(impact_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                lid = (row.get('lesson_id') or '').strip()
                action = (row.get('action') or '').strip().lower()
                if not lid or action != 'feedback':
                    continue
                if lid not in feedback_counts:
                    feedback_counts[lid] = [0, 0]
                feedback_counts[lid][1] += 1
                result = (row.get('result') or '').strip().upper()
                if result == 'USEFUL':
                    feedback_counts[lid][0] += 1
    except Exception:
        return {}
    # MIN_SAMPLES以上のfeedbackがある教訓のみrateを返す
    return {
        lid: vals[0] / vals[1] if vals[1] > 0 else 0.0
        for lid, vals in feedback_counts.items()
        if vals[1] >= USEFUL_RATE_MIN_SAMPLES
    }

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
    parent_cmd = str(task.get('parent_cmd', '') or '').strip()
    CROSS_PROJECT_SCORE_THRESHOLD = 3

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
    command_keywords = extract_keywords(command_text)

    # ═══ 偵察固有教訓リスト (cmd_1340) ═══
    # recon/scout/research タスクには以下の教訓のみ注入(全スキップ→固定リスト注入に変更)
    # 選定基準: recon/偵察/scope/search タグ持ちから偵察品質に直結する教訓を選定
    # 新規偵察教訓の追加手順:
    #   1. lessons.yamlに教訓を登録(lesson_write.sh経由)
    #   2. このRECON_LESSON_IDSセットにIDを追加
    #   3. リスト外の教訓は偵察タスクではスキップされる(CTX浪費防止)
    RECON_LESSON_IDS = {'L219', 'L211', 'L213', 'L159', 'L104', 'L129', 'L128'}

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
    import hashlib
    import json

    def load_lessons_cached(yaml_path):
        """YAMLをJSONキャッシュ経由でロード。mtime不変ならキャッシュヒット"""
        if not os.path.exists(yaml_path):
            return []
        try:
            mtime = os.path.getmtime(yaml_path)
        except OSError:
            return []
        cache_key = hashlib.md5(yaml_path.encode()).hexdigest()[:12]
        cache_path = f'/tmp/deploy_lesson_cache_{cache_key}_{mtime}.json'
        # キャッシュヒット
        if os.path.exists(cache_path):
            try:
                with open(cache_path) as cf:
                    return json.load(cf)
            except Exception:
                pass
        # キャッシュミス: YAML解析 → JSONキャッシュ保存
        try:
            with open(yaml_path) as f:
                data = yaml.load(f, Loader=yaml.SafeLoader)
            lessons = data.get('lessons', []) if data else []
            with open(cache_path, 'w') as cf:
                json.dump(lessons, cf)
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
    # cmd_2270: プロジェクトソーストラッキング (project-source boostに使用)
    for _l in lessons:
        _l['_source_project'] = project

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    cross_project_count = 0
    cross_project_projects = 0
    pdata = {}
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.load(pf, Loader=yaml.SafeLoader)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_index = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    plat_archive = os.path.join(script_dir, 'projects', pj['id'], 'lessons_archive.yaml')
                    plat_path = plat_index if os.path.exists(plat_index) else plat_archive
                    plat_lessons = load_lessons_cached(plat_path)
                    # cmd_2270: platformソースをトラッキング
                    for _l in plat_lessons:
                        _l['_source_project'] = pj['id']
                    platform_count += len(plat_lessons)
                    lessons.extend(plat_lessons)
        except Exception as pe:
            print(f'[INJECT] WARN: platform lessons load failed: {pe}', file=sys.stderr)

    # GStack #13: Cross-project learnings
    # task.command由来キーワードで other project lesson.title を照合し、
    # 関連度スコア(タイトル一致回数×3)が閾値以上のもののみ opt-in 候補化する。
    if command_keywords and pdata:
        for pj in (pdata or {}).get('projects', []):
            other_id = str(pj.get('id', '') or '').strip()
            if not other_id or other_id == project or pj.get('type') == 'platform':
                continue
            other_index = os.path.join(script_dir, 'projects', other_id, 'lessons.yaml')
            other_archive = os.path.join(script_dir, 'projects', other_id, 'lessons_archive.yaml')
            other_path = other_index if os.path.exists(other_index) else other_archive
            other_lessons = load_lessons_cached(other_path)
            if not other_lessons:
                continue
            matched = []
            for _l in other_lessons:
                title_text = str(_l.get('title', '') or '').lower()
                if not title_text:
                    continue
                score = 0
                for kw in command_keywords:
                    score += title_text.count(kw) * 3
                if score < CROSS_PROJECT_SCORE_THRESHOLD:
                    continue
                _copy = dict(_l)
                _copy['_source_project'] = other_id
                _copy['_cross_project_opt_in'] = True
                _copy['_cross_project_score'] = score
                matched.append(_copy)
            if matched:
                cross_project_projects += 1
                cross_project_count += len(matched)
                lessons.extend(matched)
                print(f'[INJECT] cross_project opt-in: {other_id} matched {len(matched)} lessons (threshold={CROSS_PROJECT_SCORE_THRESHOLD})', file=sys.stderr)

    # Deduplicate lessons by ID — last wins (後勝ち: 同一IDで内容が異なる場合は後の値を採用)
    _id_to_lesson = {}
    _no_id = []
    for _l in lessons:
        _lid = _l.get('id', '')
        if _lid:
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
    _cf = task.get('context_files')
    context_files = ' '.join(str(f) for f in _cf if f) if isinstance(_cf, list) else str(_cf or '')
    ac_list = task.get('acceptance_criteria', [])
    if isinstance(ac_list, list):
        ac_text = ' '.join(str(a.get('description', '')) if isinstance(a, dict) else str(a) for a in ac_list)
    else:
        ac_text = str(ac_list or '')
    task_text = f'{title} {description} {purpose} {command_text} {target_path} {context_files} {ac_text}'

    # Extract keywords: split by non-word chars, then ASCII↔CJK boundary split, dedup
    # GP-225: ASCII↔CJK境界分割で"CDP計測"→["CDP","計測"]に分離+アクロニム(>=2,全大文字)はmin_len免除
    _CJK = r'\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF'
    _boundary = re.compile(rf'(?<=[a-zA-Z0-9_])(?=[{_CJK}])|(?<=[{_CJK}])(?=[a-zA-Z0-9_])')
    words = re.split(rf'[^a-zA-Z0-9_{_CJK}]+', task_text)
    expanded = [part for w in words for part in _boundary.split(w) if part]
    keywords = list(set(w.lower() for w in expanded if len(w) > 3 or (len(w) >= 2 and w.isupper() and w.isascii())))

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

    # Keep only active lessons: status=confirmed or undefined (default=confirmed)
    confirmed_lessons = []
    filtered_draft = 0
    filtered_deprecated = 0
    filtered_retired = 0
    for lesson in lessons:
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
        if l_status != 'confirmed':
            filtered_draft += 1
            continue
        confirmed_lessons.append(lesson)

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

    # target_filesフィルタ: タグマッチした教訓は除外しない(忍者成長速度改善: タグ優先)
    _tf_excluded_ids = set()  # target_files不一致で除外候補のID
    if _all_task_files:
        for _l in confirmed_lessons:
            if _l.get('_cross_project_opt_in'):
                continue
            _ltf = _l.get('target_files', [])
            if not _ltf:
                continue
            if isinstance(_ltf, str):
                _ltf = [_ltf]
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

        if lesson.get('_cross_project_opt_in'):
            tag_candidates.append(lesson)
            continue

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

    # target_filesフィルタ適用: タグマッチしなかった教訓のみ除外(タグ優先原則)
    if _tf_excluded_ids and task_tags:
        _pre_tf_count = len(tag_candidates)
        tag_candidates = [l for l in tag_candidates if l.get('id','') not in _tf_excluded_ids or (set(task_tags) & set(str(t).lower() for t in (l.get('tags',[]) if isinstance(l.get('tags',[]), list) else [l.get('tags','')])))]
        _tf_actually_removed = _pre_tf_count - len(tag_candidates)
        if _tf_actually_removed > 0:
            print(f'[INJECT] target_files post-filter: removed {_tf_actually_removed} (tag-matched preserved)', file=sys.stderr)
    elif _tf_excluded_ids:
        _pre_tf_count = len(tag_candidates)
        tag_candidates = [l for l in tag_candidates if l.get('id','') not in _tf_excluded_ids]
        _tf_actually_removed = _pre_tf_count - len(tag_candidates)
        if _tf_actually_removed > 0:
            print(f'[INJECT] target_files post-filter: removed {_tf_actually_removed}', file=sys.stderr)

    # cmd_karo_gp196: AC1 — MAX_INJECT=10 総合注入上限（universalは内数）
    # cmd_2270: 3→10に拡大。キーワード関連度スコアリングで上位10件に絞る
    # tag fallback/useful_rate処理より前に定義し、条件分岐での未定義参照を防ぐ
    MAX_INJECT = 10

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
            # cmd_2270: 頻度重み付きスコアリング (engram-style: presence→frequency count)
            # タイトル内出現回数×3 + その他テキスト内出現回数×1
            score += title_text.count(kw) * 3 + other_text.count(kw) * 1

        cross_project_score = lesson.get('_cross_project_score', 0) or 0
        if cross_project_score and score < cross_project_score:
            score = cross_project_score

        if score > 0:
            # cmd_2270: プロジェクト一致ボーナス — 同プロジェクト教訓を優先注入
            if lesson.get('_source_project') == project:
                score += 2
            scored.append((score, lid, l_summary or l_title))

    # 忍者成長速度改善: タグマッチしたがキーワード0点の教訓をhelpful_count順でフォールバック注入
    # GP-221: target_filesなし教訓のフォールバック注入廃止。タスク無関係教訓のNOT_USEFUL量産防止
    if not scored and task_tags and tag_candidates:
        _relevant_fallback = [l for l in tag_candidates if l.get('tags') or l.get('target_files')]
        _tag_fallback = [(l.get('helpful_count',0) or 0, l.get('id',''), str(l.get('summary', l.get('title','')))[:80]) for l in _relevant_fallback]
        _tag_fallback.sort(key=lambda x: -x[0])
        scored = [(1, lid, summ) for hc, lid, summ in _tag_fallback[:MAX_INJECT]]
        if scored:
            print(f'[INJECT] tag fallback: keyword score=0, using {len(scored)} tag-matched lessons by helpful_count', file=sys.stderr)

    # cmd_1564+karo_idle_fix: useful_rate decay — 活用率が低い教訓のスコアを減衰
    # フィードバックデータ(record_lesson_feedback.sh)から実有用率を算出
    useful_rates = compute_useful_rates(script_dir)

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
            else:
                kept.append(lesson)
        if demoted:
            demoted_ids = [l.get('id', '?') for l in demoted]
            print(f'[INJECT] universal demotion: {len(demoted)} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% useful_rate → scored candidates: {demoted_ids}', file=sys.stderr)
            tag_candidates.extend(demoted)
            universal_lessons = kept

    if useful_rates:
        new_scored = []
        decayed_count = 0
        excluded_zero_ids = []
        for score, lid, summary in scored:
            rate = useful_rates.get(lid)
            if rate is not None and rate == 0.0:
                excluded_zero_ids.append(lid)
            elif rate is not None and rate < USEFUL_RATE_THRESHOLD:
                new_scored.append((score * USEFUL_RATE_DECAY, lid, summary))
                decayed_count += 1
            else:
                new_scored.append((score, lid, summary))
        scored = new_scored
        if excluded_zero_ids:
            print(f'[INJECT] useful_rate=0% exclusion: {len(excluded_zero_ids)} lessons excluded: {excluded_zero_ids}', file=sys.stderr)
        if decayed_count > 0:
            print(f'[INJECT] useful_rate decay: {decayed_count} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% threshold (score *= {USEFUL_RATE_DECAY})', file=sys.stderr)

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
    withheld = []
    universal_added = 0
    seen_ids_final = set()

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
            withheld.append({'id': ul_id, 'summary': ul.get('summary', '') or ul.get('title', '')})
    for _, lid, summary in scored:
        if lid not in seen_ids_final:
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

    # --- Safe targeted write (avoid full yaml.dump — cmd_1407 AC2) ---
    with open(task_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
    def _sv(v):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join('  ' + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val)
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
            s = _sv(item)
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
                    sv = _sv(v) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
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
    print(f'[INJECT]   project={project} {tag_info} scored={scored_count}/{tag_candidate_count} cross_project={cross_project_count}/{cross_project_projects} top_scores={[(s,i) for s,i,_ in scored[:5]]}', file=sys.stderr)
    print(f'[INJECT]   filtered: draft={filtered_draft} deprecated={filtered_deprecated} retired={filtered_retired}', file=sys.stderr)
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
                lf.write('timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\n')
            ts = datetime.datetime.now().isoformat(timespec='seconds')
            for r in related:
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{r["id"]}\tinjected\tpending\tpending\t{project}\t{task_type}\t{bloom}\n')
            for w in withheld:
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{w["id"]}\twithheld\tpending\tno\t{project}\t{task_type}\t{bloom}\n')
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

# ─── Engineering Preferences自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_engineering_preferences() { log "inject_engineering_preferences: merged into inject_task_modifiers (no-op)"; }


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

    # target_pathフィールドを取得
    local target_path
    target_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "")
    if [ -z "$target_path" ]; then
        return 0
    fi

    # リスト形式の場合: "- /path1\n- /path2" → 各行のパスを抽出
    # 文字列形式の場合: そのまま使用
    local -a paths=()
    if echo "$target_path" | grep -q '^- '; then
        while IFS= read -r line; do
            local p="${line#- }"
            p="${p#[[:space:]]}"
            p="${p%[[:space:]]}"
            [ -n "$p" ] && paths+=("$p")
        done <<< "$target_path"
    else
        paths+=("$target_path")
    fi

    [ ${#paths[@]} -eq 0 ] && return 0

    # 存在しないパスを検出
    local -a missing=()
    for p in "${paths[@]}"; do
        [ ! -e "$p" ] && missing+=("$p")
    done

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

    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "")
    if [ -n "$existing" ]; then
        log "[REPORT_FN] Already exists, skipping"
        return 0
    fi

    local parent_cmd report_filename
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    if [ -n "$parent_cmd" ]; then
        report_filename="${NINJA_NAME}_report_${parent_cmd}.yaml"
    else
        report_filename="${NINJA_NAME}_report.yaml"
    fi

    yaml_field_set "$task_file" "task" "report_filename" "$report_filename"
    log "[REPORT_FN] Injected report_filename=${report_filename}"
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

# inject_execution_controls: cmd_1393で inject_task_modifiers.py に統合（stub）
inject_execution_controls() { log "inject_execution_controls: merged into inject_task_modifiers (no-op)"; }

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
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" WORKAROUNDS_FILE_ENV="$workarounds_file" NINJA_NAME_ENV="$ninja_name" python3 - <<'PY'; then
import os
import re
import sys
import tempfile

import yaml

task_file = os.environ['TASK_FILE_ENV']
workarounds_file = os.environ['WORKAROUNDS_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']

# 忍者名の日本語↔ローマ字マッピング
NINJA_JP_MAP = {
    'hayate': '疾風',
    'kagemaru': '影丸',
    'hanzo': '半蔵',
    'saizo': '才蔵',
    'tobisaru': '飛猿',
    'kotaro': '小太郎',
}

def match_ninja(entry, target_name):
    """エントリが対象忍者に属するか判定"""
    ninja_field = str(entry.get('ninja', '') or '')
    if ninja_field and ninja_field.lower() == target_name.lower():
        return True
    jp_name = NINJA_JP_MAP.get(target_name.lower(), '')
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
        NINJA_NAMES = {'kagemaru', 'hanzo', 'hayate', 'tobisaru', 'saizo', 'kotaro', 'sasuke', 'kirimaru'}
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
    def _sv(v):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join('  ' + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val)
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
            s = _sv(item)
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
                    sv = _sv(v) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
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
    for item in prior_attempts[-3:]:
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

# ─── deployed_at自動記録（cmd_387: 配備タイムスタンプ） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
# 既にdeployed_atが存在する場合は上書きしない（再配備時の元タイムスタンプ保持）
record_deployed_at() {
    local task_file="$1"
    local timestamp="$2"
    if [ ! -f "$task_file" ]; then
        log "record_deployed_at: task file not found: $task_file"
        return 0
    fi

    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "deployed_at" "")
    if [ -n "$existing" ]; then
        log "[DEPLOYED_AT] Already exists (${existing}), skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "deployed_at" "$timestamp"
    log "[DEPLOYED_AT] Recorded: ${timestamp}"
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
from pathlib import Path

task_file = sys.argv[1]
cmd_id = sys.argv[2].strip()
script_dir = Path(sys.argv[3])
count = 0

try:
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    task = data.get('task') or {}
    acs = task.get('acceptance_criteria')
    if isinstance(acs, list):
        count = len(acs)
    elif isinstance(acs, dict):
        count = len(acs)
    elif acs:
        count = 1
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
            with open(path, encoding='utf-8') as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue

        commands = data.get("commands") or {}
        if isinstance(commands, dict):
            cmd = commands.get(cmd_id) or {}
        elif isinstance(commands, list):
            cmd = next((c for c in commands if str(c.get("id", "")).strip() == cmd_id), {})
        else:
            cmd = {}

        acs = cmd.get("acceptance_criteria")
        if isinstance(acs, list):
            count = len(acs)
        elif isinstance(acs, dict):
            count = len(acs)
        elif acs:
            count = 1

        if count > 0:
            break

print(count)
PY
}

mark_draft_review_once() {
    local cmd_id="$1"
    local ninja_name="$2"
    local title="$3"
    local state_dir="$SCRIPT_DIR/queue/draft_review_started"
    local marker="$state_dir/${cmd_id}.started"
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

maybe_notify_draft_review() {
    local task_file="$1"
    local cmd_id="$2"
    local ninja_name="$3"
    local deploy_type="${4:-task_assigned}"
    local title ac_count message

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

    title=$(resolve_dispatch_title "$cmd_id" "$task_file")
    if printf '%s' "$title" | grep -q 'CI RED'; then
        log "draft_review: SKIP (CI RED)"
        return 0
    fi

    ac_count=$(count_task_acceptance_criteria "$task_file" "$cmd_id")
    if ! [[ "$ac_count" =~ ^[0-9]+$ ]]; then
        ac_count=0
    fi
    if [ "$ac_count" -le 1 ]; then
        log "draft_review: SKIP (ac_count<=1: ${ac_count})"
        return 0
    fi

    if ! mark_draft_review_once "$cmd_id" "$ninja_name" "${title:-$cmd_id}"; then
        log "draft_review: SKIP (already sent)"
        return 0
    fi

    message="draft ${cmd_id} レビュー依頼。${title:-$cmd_id}。ninja=${ninja_name}。"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" gunshi "$message" review_draft karo; then
        log "draft_review: SENT (gunshi)"
    else
        log "draft_review: WARN (inbox_write failed)"
    fi
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

inject_done_redeploy_hints() {
    local task_file="$1"
    local report_path report_filename existing_desc note

    [ "${_DEPLOY_DONE_REUSE:-0}" = "1" ] || return 0
    [ -f "$task_file" ] || return 0

    report_path="${_DEPLOY_DONE_REPORT_PATH:-}"
    [ -n "$report_path" ] || return 0

    note="【再配備引継ぎ】 前回報告(${report_path})の files_modified/binary_checks を引継ぎ済み。前回結果を参照し、差分のみ再検証せよ。"
    existing_desc=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "description" "" 2>/dev/null || true)
    if [[ "$existing_desc" != *"【再配備引継ぎ】"* ]]; then
        if [ -n "$existing_desc" ]; then
            yaml_field_set "$task_file" "task" "description" "${note}"$'\n'"${existing_desc}" || true
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

    local _now_epoch
    _now_epoch=$(date +%s)
    local _warned=false
    local _tp_path _git_path _log_line _commit_epoch _subject _age_sec

    for _tp_path in "${_tp_paths[@]}"; do
        [ -n "$_tp_path" ] || continue
        _git_path="$_tp_path"
        if [[ "$_git_path" = "$_repo_root/"* ]]; then
            _git_path="${_git_path#"$_repo_root/"}"
        elif [[ "$_git_path" = /* ]]; then
            continue
        fi

        _log_line=$(git -C "$_repo_root" log -1 --format='%ct%x09%s' -- "$_git_path" 2>/dev/null || true)
        [ -n "$_log_line" ] || continue

        _commit_epoch="${_log_line%%$'\t'*}"
        _subject="${_log_line#*$'\t'}"
        [[ "$_commit_epoch" =~ ^[0-9]+$ ]] || continue

        _age_sec=$((_now_epoch - _commit_epoch))
        if [ "$_age_sec" -le 86400 ] && [[ "$_subject" != *cmd_* ]]; then
            echo "WARNING: target_path=${_git_path} の直近commitが24h以内かつ非cmd message。軍師/家老の自走commit混入の可能性あり: ${_subject}" >&2
            log "recent_noncmd_commit_warn: target=${_git_path} age=${_age_sec}s subject='${_subject}'"
            _warned=true
        fi
    done

    if [ "$_warned" = "true" ]; then
        echo "  target_pathの直近commitを確認し、軍師/家老の自走修正を吸収していないか見極めよ" >&2
    fi
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
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local task_status

    task_status=$(field_get "$task_file" "status" "unknown")

    if [ "$task_status" = "pending" ] || [ "$task_status" = "unknown" ]; then
        yaml_field_set "$task_file" "task" "status" "assigned"
        log "status_force: ${task_status} → assigned (Stage 1保護対象化)"
        task_status="assigned"
    fi

    check_entrance_gate "$task_file"
    check_scout_gate "$task_file"

    inject_task_id "$task_file" || true
    inject_ac_version "$task_file" || true
    verify_ac_consistency "$task_file" || true
    inject_related_lessons "$task_file" || true

    local clear_fields clear_tmp
    clear_fields="engineering_preferences|reports_to_read|context_files|role_reminder|report_template|bloom_level|stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok|ninja_weak_points|type"
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

    inject_task_modifiers "$task_file" || true
    inject_session_state_hints "$task_file" || true  # GP-198
    inject_codd_failure_history "$task_file" || true  # GP-201
    inject_engineering_preferences "$task_file" || true
    postcondition_lesson_inject "$task_file" || true

    local pc_file inj_project inj_ids lid
    pc_file="$SCRIPT_DIR/queue/tasks/.postcond_lesson_inject"
    if [ -f "$pc_file" ]; then
        inj_project=$(grep '^project=' "$pc_file" | cut -d= -f2)
        inj_ids=$(grep '^injected_ids=' "$pc_file" | cut -d= -f2)
        if [ -n "$inj_ids" ] && [ -n "$inj_project" ]; then
            for lid in $inj_ids; do
                bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" "$inj_project" "$lid" inject 2>/dev/null || true
            done
            if [ "$inj_project" != "infra" ]; then
                for lid in $inj_ids; do
                    bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" infra "$lid" inject 2>/dev/null || true
                done
            fi
            log "injection_count: incremented for ${inj_ids}"
        fi
    fi

    inject_reports_to_read "$task_file" || true
    inject_context_files "$task_file" || true
    inject_credential_files "$task_file" || true
    inject_target_path_check "$task_file" || true
    inject_context_update "$task_file" || true
    inject_role_reminder "$task_file" "$ninja_name" || true
    inject_report_template "$task_file" || true

    yaml_field_set "$task_file" "task" "report_filename" "" \
        || { log "FATAL: yaml_field_set failed for report_filename"; return 1; }
    yaml_field_set "$task_file" "task" "report_path" "" \
        || { log "FATAL: yaml_field_set failed for report_path"; return 1; }

    inject_report_filename "$task_file" || true
    inject_bloom_level "$task_file" || true
    inject_execution_controls "$task_file" || true
    inject_ninja_weak_points "$task_file" "$ninja_name" || true
    check_context_freshness "$task_file" || true

    local task_id parent_cmd project
    task_id=$(field_get "$task_file" "task_id" "")
    # task_id空なら_ac_task_idをfallback(家老が_ac_task_idを直接設定するケース)
    if [ -z "$task_id" ]; then
        task_id=$(field_get "$task_file" "_ac_task_id" "")
    fi
    parent_cmd=$(field_get "$task_file" "parent_cmd" "")
    project=$(field_get "$task_file" "project" "")
    generate_report_template "$ninja_name" "$task_id" "$parent_cmd" "$project"
    inject_done_redeploy_hints "$task_file" || true
}

# ═══════════════════════════════════════
# メイン処理
# ═══════════════════════════════════════
deploy_task_main() {
    parse_deploy_task_args "$@"
    cleanup_none_task_files
    deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

    local pane_target ctx_pct
    local is_idle=false
    pane_target=$(resolve_pane "$NINJA_NAME")
    if [ -z "$pane_target" ]; then
        log "ERROR: Unknown ninja: $NINJA_NAME"
        return 1
    fi

    ctx_pct=$(get_ctx_pct "$pane_target" "$NINJA_NAME")
    check_idle "$pane_target" && is_idle=true

    local task_yaml pre_resolve_status pre_resolve_cmd task_status verify_status current_cmd
    local deploy_parent_cmd deploy_task_id dd_task dd_ninja dd_pcmd dd_tid dd_status
    task_yaml="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"

    normalize_task_yaml "$task_yaml" || true

    pre_resolve_status=$(field_get "$task_yaml" "status" "unknown")
    if [ "$pre_resolve_status" = "in_progress" ] && [ -n "$CMD_ID" ]; then
        pre_resolve_cmd=$(field_get "$task_yaml" "parent_cmd" "")
        log "BLOCK(GP-069): ${NINJA_NAME} is in_progress on ${pre_resolve_cmd:-unknown}. 前タスク完了を待て。"
        echo "BLOCK: ${NINJA_NAME} は ${pre_resolve_cmd:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
        return 1
    fi

    if [ -n "$CMD_ID" ]; then
        capture_done_redeploy_context "$task_yaml" "$CMD_ID"
        # GP-198: session_stateをstale reset前に保存（再配備時のhint注入用）
        # cmd_2078 B3: awk fast-path — session_stateフィールドが存在しなければpython3をスキップ (~53ms節約)
        _DEPLOY_PREV_SESSION_STATE=""
        _DEPLOY_PREV_PARENT_CMD=$(FIELD_GET_NO_LOG=1 field_get "$task_yaml" "parent_cmd" "" 2>/dev/null || true)
        if grep -qE '^[[:space:]]+session_state:' "$task_yaml" 2>/dev/null; then
            _DEPLOY_PREV_SESSION_STATE=$(python3 -c "
import yaml, json, sys
try:
    with open('$task_yaml') as f:
        d = yaml.safe_load(f) or {}
    ss = (d.get('task') or d).get('session_state')
    if ss and isinstance(ss, dict):
        print(json.dumps(ss))
except Exception:
    pass
" 2>/dev/null || true)
        fi
        export _DEPLOY_PREV_SESSION_STATE
        export _DEPLOY_PREV_PARENT_CMD
        reset_stale_fields "$NINJA_NAME"
        if [ "$DIRECT_MODE" = true ]; then
            if [ -n "$YAML_FILE" ]; then
                if [ ! -f "$YAML_FILE" ]; then
                    log "ERROR: --yaml file not found: $YAML_FILE"
                    echo "ERROR: --yaml ファイルが見つからない: $YAML_FILE" >&2
                    return 1
                fi
                cp "$YAML_FILE" "$task_yaml"
                log "direct_mode: task YAML overwritten from $YAML_FILE"
                check_yaml_freshness "$YAML_FILE" "$SCRIPT_DIR"
            fi
            log "direct_mode: skipping resolve_cmd_to_task for ${CMD_ID} (shogun_to_karo.yaml not required)"
        elif [ -n "$CMD_FORCED" ]; then
            # --cmd mode: shogun_to_karo.yaml不在cmdを強制展開（修行cmd等に対応）
            # parent_cmd/task_idを直接設定。解決失敗でもabortしない。
            yaml_field_set "$task_yaml" "task" "parent_cmd" "$CMD_FORCED" \
                || { log "FATAL: yaml_field_set failed for parent_cmd (cmd_forced)"; return 1; }
            local force_task_type
            force_task_type=$(field_get "$task_yaml" "task_type" "impl")
            if [ -z "$force_task_type" ] || [ "$force_task_type" = "unknown" ]; then
                force_task_type="impl"
            fi
            yaml_field_set "$task_yaml" "task" "task_id" "${CMD_FORCED}_${force_task_type}" \
                || { log "FATAL: yaml_field_set failed for task_id (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "status" "assigned" \
                || { log "FATAL: yaml_field_set failed for status (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "_ac_task_id" "" \
                || { log "FATAL: yaml_field_set failed for _ac_task_id (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "_ac_worker_id" "" \
                || { log "FATAL: yaml_field_set failed for _ac_worker_id (cmd_forced)"; return 1; }
            _overwrite_ac_from_cmd "$task_yaml" || true
            log "cmd_forced: ${CMD_FORCED} → parent_cmd/task_id set directly (shogun_to_karo.yaml not required)"
        elif resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
            log "cmd_resolve: ${CMD_ID} → task YAML updated for ${NINJA_NAME}"
        else
            log "ERROR: cmd_resolve failed for ${CMD_ID}. Aborting deployment."
            echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
            return 1
        fi
    fi

    task_status=$(field_get "$task_yaml" "status" "unknown")
    log "${NINJA_NAME}: CTX=${ctx_pct}%, idle=${is_idle}, task_status=${task_status}, pane=${pane_target}"

    if [ "$MESSAGE" = "status" ] && { [ "$TYPE" = "idle" ] || [ "$TYPE" = "done" ]; }; then
        yaml_field_set "$task_yaml" "task" "status" "$TYPE"
        log "status_update: ${task_status} → ${TYPE}"
        verify_status=$(field_get "$task_yaml" "status" "")
        if [ "$verify_status" != "$TYPE" ]; then
            log "WARN: status更新検証失敗: 期待=${TYPE}, 実際=${verify_status}"
        fi
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
        log "${NINJA_NAME}: deployment complete (type=${TYPE})"
        return 0
    fi

    if [ "$MESSAGE" = "status" ] && [ "$TYPE" = "in_progress" ]; then
        if [ "$task_status" = "in_progress" ]; then
            current_cmd=$(field_get "$task_yaml" "parent_cmd" "")
            log "BLOCK: ${NINJA_NAME} is in_progress on ${current_cmd:-unknown}. 前タスク完了を待て。"
            echo "BLOCK: ${NINJA_NAME} は ${current_cmd:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
            return 1
        fi
        yaml_field_set "$task_yaml" "task" "status" "in_progress"
        log "status_update: ${task_status} → in_progress"
        verify_status=$(field_get "$task_yaml" "status" "")
        if [ "$verify_status" != "in_progress" ]; then
            log "WARN: status更新検証失敗: 期待=in_progress, 実際=${verify_status}"
        fi
    fi

    if [ "$task_status" = "in_progress" ] && [ "$TYPE" != "in_progress" ]; then
        current_cmd=$(field_get "$task_yaml" "parent_cmd" "")
        log "BLOCK: ${NINJA_NAME} is in_progress on ${current_cmd:-unknown}. 前タスク完了を待て。"
        echo "BLOCK: ${NINJA_NAME} は ${current_cmd:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
        return 1
    fi

    deploy_parent_cmd=$(field_get "$task_yaml" "parent_cmd" "")
    deploy_task_id=$(field_get "$task_yaml" "_ac_task_id" "")

    if [ -n "$deploy_parent_cmd" ]; then
        warn_same_ninja_redeploy "$task_yaml" "$NINJA_NAME" "$deploy_parent_cmd"
    fi

    # _ac_task_id必須チェック: 分割配備の判定に必要。未設定だとparent_cmdクリア事故(cmd_1751/1752)
    if [ -z "$deploy_task_id" ]; then
        log "WARN: _ac_task_id is empty — split deploy detection may misfire"
        echo "WARN: _ac_task_id が未設定。分割配備時に二重配備と誤判定する可能性あり。task YAMLに _ac_task_id を設定せよ。" >&2
    fi

    if [ -n "$deploy_parent_cmd" ]; then
        for dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
            [ -f "$dd_task" ] || continue
            dd_ninja=$(basename "$dd_task" .yaml)
            [ "$dd_ninja" = "$NINJA_NAME" ] && continue
            dd_pcmd=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "parent_cmd" "")
            [ "$dd_pcmd" != "$deploy_parent_cmd" ] && continue
            dd_tid=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "_ac_task_id" "")
            # BLOCKは「両方のtask_idが存在し同一」の場合のみ(真の二重配備)。
            # task_idが片方でも空なら分割配備の可能性 → スキップ。
            # 旧ロジック: task_idが空だとBLOCK→parent_cmdクリア→report_filename破壊(cmd_1751/1752事故)
            if [ -z "$deploy_task_id" ] || [ -z "$dd_tid" ] || [ "$deploy_task_id" != "$dd_tid" ]; then
                log "split_deploy: ${deploy_parent_cmd} peer ${dd_ninja} (task_id: ${dd_tid:-empty}) — allowing"
                continue
            fi
            dd_status=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "status" "")
            case "$dd_status" in
                assigned|acknowledged|in_progress)
                    log "BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja} (status: ${dd_status}, task_id: ${dd_tid})"
                    yaml_field_set "$task_yaml" "task" "status" "idle" 2>/dev/null || true
                    yaml_field_set "$task_yaml" "task" "parent_cmd" "" 2>/dev/null || true
                    yaml_field_set "$task_yaml" "task" "_ac_task_id" "" 2>/dev/null || true
                    log "ROLLBACK: ${NINJA_NAME} task YAML reset to idle after duplicate deploy BLOCK"
                    echo "BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja} (status: ${dd_status})" >&2
                    echo "Clear the existing task first: bash scripts/lib/yaml_field_set.sh queue/tasks/${dd_ninja}.yaml task status idle" >&2
                    return 1
                    ;;
            esac
        done
    fi

    # 消火キーワードtitle検知（cmd_1807）
    if [ -n "$deploy_parent_cmd" ]; then
        check_firefighting_title "$deploy_parent_cmd" "$task_yaml"
    fi

    warn_task_clarity "$task_yaml"

    # GP-110修正版: target_pathの直近コミットが非cmd self-driveならWARN
    warn_recent_noncmd_commit_targets "$task_yaml"

    # AC3: _STALE_RESET_DONE確認ゲート — CMD_ID配備時にreset_stale_fieldsが実行済みか検証
    if [ -n "$CMD_ID" ] && [ "${_STALE_RESET_DONE:-0}" != "1" ]; then
        log "BLOCK(AC3): _STALE_RESET_DONE not set — reset_stale_fields が未実行。配備を中止。"
        echo "BLOCK: stale field reset (reset_stale_fields) が未実行。配備を中止。deploy_task.shのreset_stale_fields呼出し経路を確認せよ。" >&2
        return 1
    fi

    deploy_task_apply_task_mutations "$NINJA_NAME"

    if [ "$ctx_pct" -le 0 ] 2>/dev/null; then
        log "${NINJA_NAME}: CTX=0% detected (clear済み). Sending inbox_write (watcher handles timing)"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
    elif [ "$is_idle" = "true" ]; then
        log "${NINJA_NAME}: CTX=${ctx_pct}%, idle. Sending inbox_write (normal nudge)"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
    else
        log "${NINJA_NAME}: CTX=${ctx_pct}%, busy. Sending inbox_write (queued, watcher will nudge later)"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
    fi

    notify_initial_deploy_ntfy_once "$task_yaml" "$NINJA_NAME" || true
    record_deployed_at "$task_yaml" "$(date '+%Y-%m-%dT%H:%M:%S')" || true
    preflight_gate_artifacts "$task_yaml" || true

    local rr_pointer_file rr_lock_file
    rr_pointer_file="$SCRIPT_DIR/queue/rr_pointer.txt"
    rr_lock_file="/tmp/rr_pointer.lock"
    (
        flock -w 5 201
        echo "$NINJA_NAME" > "$rr_pointer_file"
    ) 201>"$rr_lock_file" 2>/dev/null || log "WARN: rr_pointer update failed (non-fatal)"

    maybe_notify_draft_review "$task_yaml" "$deploy_parent_cmd" "$NINJA_NAME" "$TYPE"
    log "${NINJA_NAME}: deployment complete (type=${TYPE})"
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" ]]; then
    deploy_task_main "$@"

    # cmd_1337: ダッシュボード自動更新（配備完了時、バックグラウンド実行）
    # source(lib-only)利用時は起動しない。テスト/ヘルパでの読込副作用を防ぐ。
    bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" &
fi
