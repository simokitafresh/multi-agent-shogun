#!/bin/bash
# deploy_task/report.sh — cluster F: report identity, generation, scope, template, and publication.
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

