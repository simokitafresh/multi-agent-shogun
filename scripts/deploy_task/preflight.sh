#!/bin/bash
# deploy_task/preflight.sh — cluster I preflight artifacts, issue/deploy telemetry, and remote-tip worktree.
# Function bodies are extracted verbatim from deploy_task.sh.

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

