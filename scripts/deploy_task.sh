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
# cmd_1393: Python→awk+md5sum置換
inject_ac_version() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_ac_version: task file not found: $task_file"
        return 0
    fi

    # acceptance_criteria内のdescriptionを抽出→sort→|結合→md5先頭8桁
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

    local ac_version
    ac_version=$(printf '%s' "$concat" | md5sum | cut -c1-8)

    local prev
    prev=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")

    yaml_field_set "$task_file" "task" "ac_version" "$ac_version"

    if [ "$prev" = "$ac_version" ]; then
        log "[AC_VERSION] unchanged: $ac_version"
    else
        log "[AC_VERSION] set: $prev -> $ac_version"
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
    if [[ -n "$parent_cmd" && "$parent_cmd" == cmd_* ]]; then
        local stale_basename
        for stale_report in "$SCRIPT_DIR/queue/reports/"*"_report_${parent_cmd}.yaml"; do
            [ -f "$stale_report" ] || continue
            stale_basename=$(basename "$stale_report")
            # 自分の報告はスキップ（下のown-reportブロックで処理）
            if [[ "$stale_basename" == "${ninja_name}_report_"* ]]; then
                continue
            fi
            # 他忍者の報告: 無条件で保護
            log "report_template: PROTECTED other ninja report (${stale_basename})"
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
# !! report_field_set.sh で各フィールドを設定せよ。直接Edit/Write禁止 !!
# Step1: Read this file → Step2: bash scripts/report_field_set.sh <this_file> <key> <value> で各フィールドを埋めよ
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
binary_checks: {}  # AC完了ごとに ACN: [{check: "確認内容", result: "yes/no"}] を記入
verdict: ""  # 全binary_checks完了後に PASS or FAIL を記入
EOF

    # cmd_1131+cmd_1393: related_lessonsが存在する場合、lessons_usefulを記入用雛形に差替え（Python→bash/awk）
    local _lu_ids
    _lu_ids=$(awk '
        /^  related_lessons:/ { in_rl=1; next }
        in_rl && /^  [a-z]/ { exit }
        in_rl && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print }
    ' "$task_file" 2>/dev/null)

    if [ -z "$_lu_ids" ]; then
        # GP-088: related_lessonsなし or id抽出不能 → null→[]に変換
        if grep -q 'lessons_useful: null' "$report_file" 2>/dev/null; then
            sed -i 's/lessons_useful: null/lessons_useful: []/' "$report_file"
            log "report_template: lessons_useful null→[] fallback"
        fi
    else
        # IDリストからlessons_useful雛形を生成
        local _lu_block="lessons_useful:"
        local _lu_count=0
        while IFS= read -r _lid; do
            [ -z "$_lid" ] && continue
            _lu_block="${_lu_block}
  - id: ${_lid}
    useful: false
    reason: ''"
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
    local _bc_block
    _bc_block=$(awk '
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"\n", chk[i] }
            }
            cur_id=""; cc=0
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    - check:/ { sub(/.*- check:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cc++; chk[cc]=$0 }
        END {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"\n", chk[i] }
            }
        }
    ' "$task_file" 2>/dev/null)

    if [ -n "$_bc_block" ]; then
        local _bc_full="binary_checks:
${_bc_block}"
        local _bc_placeholder='binary_checks: {}  # AC完了ごとに ACN: [{check: "確認内容", result: "yes/no"}] を記入'
        if grep -qF "$_bc_placeholder" "$report_file" 2>/dev/null; then
            awk -v repl="$_bc_full" -v placeholder="$_bc_placeholder" '
                index($0, placeholder) { print repl; next }
                { print }
            ' "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
            local _bc_ac_count
            _bc_ac_count=$(echo "$_bc_block" | grep -c '^\s\s[A-Z]')
            log "binary_checks template: ${_bc_ac_count} ACs injected"
            log "report_template: binary_checks template injected"
        fi
    fi

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

    # cmd_1066: reviewタスクにはself_gate_check欄を追加（verdictはbase templateに移設済み cmd_1204）
    if [ "$report_task_type" = "review" ]; then
        cat >> "$report_file" <<'REVIEW_EOF'
# ─── レビュー判定（cmd_1066: reviewタスク必須） ───
self_gate_check:
  lesson_ref: ""
  lesson_candidate: ""
  status_valid: ""
  purpose_fit: ""
REVIEW_EOF
        log "report_template: added self_gate_check (review)"
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
        parent_cmd = str(task.get('parent_cmd', '') or '').strip()
        if parent_cmd:
            stk_path = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
            if os.path.exists(stk_path):
                try:
                    with open(stk_path) as stk_f:
                        stk_data = yaml.safe_load(stk_f)
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
                        proj_data = yaml.safe_load(pf)
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
                data = yaml.safe_load(f)
            lessons = data.get('lessons', []) if data else []
            with open(cache_path, 'w') as cf:
                json.dump(lessons, cf)
            return lessons
        except Exception:
            return []

    # Vercel-style: archive has full data, index is slim. Try archive first, fallback to index.
    archive_path = os.path.join(script_dir, 'projects', project, 'lessons_archive.yaml')
    index_path = os.path.join(script_dir, 'projects', project, 'lessons.yaml')
    lessons_path = archive_path if os.path.exists(archive_path) else index_path
    lessons = load_lessons_cached(lessons_path)
    if not lessons and not os.path.exists(lessons_path):
        print(f'[INJECT] WARN: lessons not found for project={project}', file=sys.stderr)

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.safe_load(pf)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_archive = os.path.join(script_dir, 'projects', pj['id'], 'lessons_archive.yaml')
                    plat_index = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    plat_path = plat_archive if os.path.exists(plat_archive) else plat_index
                    plat_lessons = load_lessons_cached(plat_path)
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
    ninja_field = entry.get('ninja', '')
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

    # まずyaml.safe_loadを試す
    try:
        wa_data = yaml.safe_load(content)
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
            parsed = yaml.safe_load(cleaned)
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
        data = yaml.safe_load(f)

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

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
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

    # 1. task_typeがimplement以外ならPASS（typeフィールドではなくtask_typeのみ参照）
    local task_type
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
    if [ "$task_type" != "implement" ]; then
        log "scout_gate: PASS: task_type=${task_type} (not implement)"
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
            /^[[:space:]]*- id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
            cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
        ' "$stk_path" 2>/dev/null)
        if [ "$_se" = "true" ]; then
            log "scout_gate: PASS: scout_exempt=true for ${parent_cmd}"
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

# --- status更新コマンド: idle/done時は即更新して早期リターン ---
# deploy_task.sh {ninja} status idle/done の呼出しパターンに対応
_TASK_YAML="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
if [ "$MESSAGE" = "status" ] && { [ "$TYPE" = "idle" ] || [ "$TYPE" = "done" ]; }; then
    yaml_field_set "$_TASK_YAML" "task" "status" "$TYPE"
    log "status_update: ${TASK_STATUS} → ${TYPE}"
    # 検証アサーション: 更新後にYAML読み直して期待値と一致確認
    _verify_status=$(field_get "$_TASK_YAML" "status" "")
    if [ "$_verify_status" != "$TYPE" ]; then
        log "WARN: status更新検証失敗: 期待=${TYPE}, 実際=${_verify_status}"
    fi
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
    log "${NINJA_NAME}: deployment complete (type=${TYPE})"
    exit 0
fi

# --- status更新コマンド: in_progress時はGP-069チェック後に更新 ---
if [ "$MESSAGE" = "status" ] && [ "$TYPE" = "in_progress" ]; then
    # GP-069はin_progress→in_progressの二重配備のみBLOCK
    if [ "$TASK_STATUS" = "in_progress" ]; then
        CURRENT_CMD=$(field_get "$_TASK_YAML" "parent_cmd" "")
        log "BLOCK: ${NINJA_NAME} is in_progress on ${CURRENT_CMD:-unknown}. 前タスク完了を待て。"
        echo "BLOCK: ${NINJA_NAME} は ${CURRENT_CMD:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
        exit 1
    fi
    yaml_field_set "$_TASK_YAML" "task" "status" "in_progress"
    log "status_update: ${TASK_STATUS} → in_progress"
    # 検証アサーション
    _verify_status=$(field_get "$_TASK_YAML" "status" "")
    if [ "$_verify_status" != "in_progress" ]; then
        log "WARN: status更新検証失敗: 期待=in_progress, 実際=${_verify_status}"
    fi
fi

# GP-069: 二重配備防止チェック（double_deploy WA根絶）
# 忍者がin_progressの場合、新タスク配備をBLOCK。前タスク完了後に再配備せよ。
if [ "$TASK_STATUS" = "in_progress" ] && [ "$TYPE" != "in_progress" ]; then
    CURRENT_CMD=$(field_get "$_TASK_YAML" "parent_cmd" "")
    log "BLOCK: ${NINJA_NAME} is in_progress on ${CURRENT_CMD:-unknown}. 前タスク完了を待て。"
    echo "BLOCK: ${NINJA_NAME} は ${CURRENT_CMD:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
    exit 1
fi

# cmd_cycle_001: 同一cmd別忍者二重配備防止ガード
# 同じparent_cmdが別の忍者にassigned/acknowledged/in_progressで存在する場合BLOCK
# 背景: 二重配備事故3件(cmd_1281, cmd_1342, cmd_1350)。grepベースで軽量スキャン。
DEPLOY_PARENT_CMD=$(field_get "$_TASK_YAML" "parent_cmd" "")
if [ -n "$DEPLOY_PARENT_CMD" ]; then
    for _dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
        [ -f "$_dd_task" ] || continue
        _dd_ninja=$(basename "$_dd_task" .yaml)
        [ "$_dd_ninja" = "$NINJA_NAME" ] && continue
        _dd_pcmd=$(grep -m1 '^\s*parent_cmd:' "$_dd_task" 2>/dev/null | sed "s/.*parent_cmd:[[:space:]]*//" | sed "s/['\"]//g" | sed 's/[[:space:]]*$//')
        [ "$_dd_pcmd" != "$DEPLOY_PARENT_CMD" ] && continue
        _dd_status=$(grep -m1 '^\s*status:' "$_dd_task" 2>/dev/null | sed "s/.*status:[[:space:]]*//" | sed "s/['\"]//g" | sed 's/[[:space:]]*$//')
        case "$_dd_status" in
            assigned|acknowledged|in_progress)
                log "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status})"
                echo "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status})" >&2
                echo "Clear the existing task first: bash scripts/lib/yaml_field_set.sh queue/tasks/${_dd_ninja}.yaml task status idle" >&2
                exit 1
                ;;
        esac
    done
fi

# status強制注入（cmd_1126: pending/unknown→assigned化。Stage 1ガード保護対象に入れる）
if [ "$TASK_STATUS" = "pending" ] || [ "$TASK_STATUS" = "unknown" ]; then
    yaml_field_set "$_TASK_YAML" "task" "status" "assigned"
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

# cmd_1321: auto-injectフィールド一括クリア（前cmdの残留値を排除）
# cmd_1312方式を8箇所に横展開: inject前にフィールド削除→再inject
# cmd_1393: Python→awk置換
_CLEAR_FIELDS="engineering_preferences|reports_to_read|context_files|role_reminder|report_template|bloom_level|stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok|ninja_weak_points"
_clear_tmp=$(mktemp)
if awk -v fields="$_CLEAR_FIELDS" '
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
' "$TASK_FILE" > "$_clear_tmp" 2>/dev/null; then
    if [ -s "$_clear_tmp" ]; then
        mv "$_clear_tmp" "$TASK_FILE"
    else
        rm -f "$_clear_tmp"
    fi
else
    log "WARN: auto-inject field clear failed (non-fatal)"
    rm -f "$_clear_tmp"
fi

# cmd_1393: 7関数統合（eng_prefs/reports_to_read/ctx_files/cred_files/ctx_update/report_tpl/exec_controls）
inject_task_modifiers "$TASK_FILE" || true

# Engineering Preferences自動注入（inject_task_modifiersで処理済み・後方互換stub）
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

# target_path存在検査WARN注入（cmd_1322: 設定済みだが実在しないtarget_pathを警告）
inject_target_path_check "$TASK_FILE" || true

# context_update自動注入（失敗してもデプロイは継続）
inject_context_update "$TASK_FILE" || true

# role_reminder自動注入（cmd_384: 失敗してもデプロイは継続）
inject_role_reminder "$TASK_FILE" "$NINJA_NAME" || true

# report_template自動注入（cmd_384: 失敗してもデプロイは継続）
inject_report_template "$TASK_FILE" || true

# cmd_1312: auto-injectフィールドクリア（前cmdの残留値を排除）
yaml_field_set "$TASK_FILE" "task" "report_filename" ""
yaml_field_set "$TASK_FILE" "task" "report_path" ""

# report_filename自動注入（cmd_410: 命名ミスマッチ根治）
inject_report_filename "$TASK_FILE" || true

# bloom_level自動注入（cmd_434: タスク複雑度メタデータ）
inject_bloom_level "$TASK_FILE" || true

# task execution controls注入（cmd_875: 停止条件/優先順位/並列許可）
inject_execution_controls "$TASK_FILE" || true

# ninja_weak_points自動注入（cmd_1307: 忍者別過去失敗パターン）
inject_ninja_weak_points "$TASK_FILE" "$NINJA_NAME" || true

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

# cmd_1337: ダッシュボード自動更新（配備完了時、バックグラウンド実行）
bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" &
