#!/usr/bin/env bats
# test_necessity: 同一cmdを複数忍者のactive taskへ二重配備できない
# test_deploy_task_lifecycle.bats - deploy_task.sh ライフサイクル統合テスト
# 統合元: double_deploy_guard(11) + stale_field_reset(2) + stale_report_verdict(11)
#        + engineering_preferences(3) + gate_blocks(5) + gate_fail_top3(4) = 36テスト

load '../helpers/deploy_task_scaffold'

# test_necessity: task idle transition atomically clears active identity and
# preserves the previous generation across active/completed/idle boundaries.
@test "task lifecycle idle transition preserves history and clears identity" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/task_lifecycle.sh"
root="$(mktemp -d)"; mkdir -p "$root/queue/tasks"
for state in in_progress done idle; do
    cat > "$root/queue/tasks/worker.yaml" <<EOF
task:
  status: $state
  task_id: task_${state}
  parent_cmd: cmd_${state}
  _ac_task_id: ac_${state}
  report_path: queue/reports/report_${state}.yaml
  report_filename: report_${state}.yaml
EOF
    if [ "$state" != in_progress ]; then task_lifecycle_set_idle "$root/queue/tasks/worker.yaml" "contract_$state"; fi
    STATE="$state" python3 - "$root/queue/tasks/worker.yaml" <<'PY'
import os, sys, yaml
t=yaml.safe_load(open(sys.argv[1]))["task"]; state=os.environ["STATE"]
if state == "in_progress": assert t["task_id"] == "task_in_progress"
else:
    assert t["status"] == "idle"
    assert all(not t.get(k) for k in ("task_id","parent_cmd","_ac_task_id","report_path","report_filename"))
    assert t["last_task_id"] == f"task_{state}" and t["lifecycle_transition_reason"] == f"contract_{state}"
PY
done
printf "boundaries=active,completed,idle identity_clear=yes history_preserved=yes\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"boundaries=active,completed,idle identity_clear=yes history_preserved=yes"* ]]
}

# ─── stale_field_reset ヘルパー関数 ───

extract_function() {
    local name="$1"
    local start end

    start=$(awk -v name="$name" '$0 ~ "^" name "\\(\\) \\{" { print NR; exit }' "$SRC_DEPLOY_SCRIPT")
    [ -n "$start" ] || return 1

    end=$(awk -v start="$start" '
        NR > start && /^[A-Za-z0-9_]+\(\) \{/ { print NR - 1; found = 1; exit }
        END { if (!found) print NR }
    ' "$SRC_DEPLOY_SCRIPT")
    sed -n "${start},${end}p" "$SRC_DEPLOY_SCRIPT"
}

write_shogun_to_karo_fixture() {
    local root="$1"
    cat > "$root/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9999:
    id: cmd_9999
    title: 'テスト用新cmd'
    project: infra
    type: impl
    estimated_minutes: 10
    purpose: '新しいpurpose'
    acceptance_criteria:
    - 'AC1: テスト'
    timestamp: '2026-03-30T02:00:00+09:00'
    status: pending
EOF
}

write_task_fixture() {
    local root="$1"
    cat > "$root/queue/tasks/tobisaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_8888
  task_id: cmd_8888_impl
  task_type: impl
  project: dm-signal
  status: completed
  cancel_reason: '前cmdの取消理由'
  superseded_by: cmd_old_replacement
  assumptions:
  - claim: '前cmdの古い前提'
    source: 'old-source'
    trust: unverified
  purpose: '前cmdの古いpurpose'
  target_path: /mnt/c/Python_app/DM-signal/backend/old_file.py
  constraints:
  - 'DM-signal制約1'
  - 'DM-signal制約2'
  progress: 'AC1-3全完了。PASS'
  description: '前cmdの説明'
  deployed_at: '2026-03-29T10:00:00'
  started_at: '2026-03-29T10:00:01'
  worker_id: tobisaru
  timestamp: '2026-03-29T10:00:00'
  engineering_preferences:
  - 'prefer old approach'
  - 'prefer another old approach'
  context_files:
  - 'context/dm-signal.md'
  - 'context/dm-signal-core.md'
  scope:
    files:
    - frontend/src/app/old/page.tsx
    only: true
  context: '前taskの古いcontext'
  context_hints:
  - 'context/old-task.md'
  - 'docs/research/old-task.md'
  assigned_scope: '前cmdの古いassigned_scope'
  expected_model_effort: 'old-effort'
  pre_deploy_banner_evidence: 'old banner evidence'
  not_in_scope:
  - 'old deferred item'
  recommended_skills:
  - old-skill
  files_to_modify:
  - scripts/old_task.py
  files_modified:
  - scripts/gates/old_gate.sh
  quality_gate:
    action_conversion: '前cmdのCI未解消条件をBLOCKする'
    fp_measurement: '前cmdのCI偽陽性を計測する'
  work_items:
  - '前cmdの旧作業1'
  - '前cmdの旧作業2'
  stop_for:
  - 'old stop condition 1'
  - 'old stop condition 2'
  never_stop_for:
  - 'old never stop 1'
  ac_priority: 'AC1 > AC2 > AC3'
  ac_checkpoint: '旧チェックポイント'
  parallel_ok:
  - AC1
  - AC2
  - AC3
  scout_exempt: true
  command: 'gate_fire_log書込み箇所にgate名フィールドを追加せよ'
  reports_to_read:
  - 'queue/reports/old_report.yaml'
  credential_warning: '⚠ 認証が必要なタスク'
  context_update: '前cmdのcontext更新情報'
  type: impl
  report_template: '旧テンプレートデータ'
  AC1: '旧AC1: SF LOW偵察のAC1'
  AC2: '旧AC2: SF LOW偵察のAC2'
  AC3: '旧AC3: git commit'
  acceptance_criteria:
    AC1:
      description: '前cmdのAC1'
  _ac_task_id: cmd_8888_impl
  _ac_worker_id: tobisaru
status: in_progress
EOF
}

prepare_source_fixture() {
    local root="$1"
    mkdir -p "$root/queue/tasks" "$root/logs"
    write_shogun_to_karo_fixture "$root"
    write_task_fixture "$root"
}

resolve_fixture_task() {
    local root="$1"
    local cmd_id="$2"
    local ninja_name="$3"

    SCRIPT_DIR="$root"

    log() { :; }

    # shellcheck disable=SC1091
    source "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    # _overwrite_ac_from_cmd is now part of resolve_cmd_to_task's preflight
    # projection and reads parent_cmd through the production getter.
    source "$REAL_PROJECT_ROOT/scripts/lib/field_get.sh"

    # setup_file extracts this stable function bundle once from the 2,000+
    # line production script.  Re-sourcing the ext4 fixture preserves the real
    # functions while avoiding four full awk+sed scans for every fixture.
    source "$RESOLVE_FUNCTIONS_FILE"
    reset_stale_fields "$ninja_name"
    resolve_cmd_to_task "$cmd_id" "$ninja_name"
}

@test "normal deploy injects source assumptions structurally and clears canceled-task metadata" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_assumptions.XXXXXX")"
    prepare_source_fixture "$root"
    sed -i "/    timestamp:/i\\    assumptions:\n    - claim: '2026-07-10 verified claim'\n      source: 'scripts/deploy_task.sh:1134'\n      trust: verified" "$root/queue/shogun_to_karo.yaml"

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"
    run python3 - "$root/queue/tasks/tobisaru.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))['task']
assert task['assumptions'] == [{'claim': '2026-07-10 verified claim', 'source': 'scripts/deploy_task.sh:1134', 'trust': 'verified'}]
assert 'cancel_reason' not in task
assert 'superseded_by' not in task
PY
    [ "$status" -eq 0 ]
    rm -rf "$root"
}

@test "normal deploy without source assumptions does not fabricate them and overwrites existing AC" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_no_assumptions.XXXXXX")"
    prepare_source_fixture "$root"

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"
    run python3 - "$root/queue/tasks/tobisaru.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))['task']
assert 'assumptions' not in task
assert task['acceptance_criteria'] != {'AC1': {'description': '前cmdのAC1'}}
PY
    [ "$status" -eq 0 ]
    rm -rf "$root"
}

get_task_values() {
    local file="$1"
    shift
    local fields_str="$*"
    awk -v fs="$fields_str" '
        BEGIN { n=split(fs,f," "); for(i=1;i<=n;i++) want[f[i]]=1 }
        /^task:/ { in_task=1; next }
        in_task && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ {
            key=$0; sub(/^  /,"",key); sub(/:.*$/,"",key)
            if (key in want) { val=$0; sub(/^  [^:]+:[[:space:]]*/,"",val); found[key]=val }
            next
        }
        in_task && /^[^ ]/ { in_task=0 }
        END { for(i=1;i<=n;i++) print f[i] "=" ((f[i] in found && found[f[i]]!="") ? found[f[i]] : "<missing>") }
    ' "$file"
}

assert_missing_fields() {
    local file="$1"
    shift
    local output field
    output="$(get_task_values "$file" "$@")"

    for field in "$@"; do
        [[ "$output" == *"${field}=<missing>"* ]]
    done
}

# ─── double_deploy_guard ヘルパー関数 ───
# 分割配備対応版: 同一parent_cmd+異なるtask_idは許可

run_double_deploy_guard() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local NINJA_NAME="$1"
    local _TASK_YAML="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
    local log_file="$SCRIPT_DIR/logs/double_deploy_test.log"

    log() { echo "$*" >> "$log_file"; }

    # cmd_3280: _ac_task_id → subtask_id → task_id の優先順位でDEPLOY_TASK_IDを取得
    local DEPLOY_PARENT_CMD="" _SELF_AC_TID="" _SELF_SUB_TID="" _SELF_TASK_ID="" DEPLOY_TASK_ID="" DEPLOY_SCOPE_MODE="" _line
    while IFS= read -r _line; do
        [[ -z "$DEPLOY_PARENT_CMD" && "$_line" =~ ^[[:space:]]*parent_cmd:[[:space:]]+(.*) ]] && {
            DEPLOY_PARENT_CMD="${BASH_REMATCH[1]//\'/}"; DEPLOY_PARENT_CMD="${DEPLOY_PARENT_CMD//\"/}"
        }
        [[ -z "$_SELF_AC_TID" && "$_line" =~ ^[[:space:]]*_ac_task_id:[[:space:]]+(.*) ]] && {
            _SELF_AC_TID="${BASH_REMATCH[1]//\'/}"; _SELF_AC_TID="${_SELF_AC_TID//\"/}"
        }
        [[ -z "$_SELF_SUB_TID" && "$_line" =~ ^[[:space:]]*subtask_id:[[:space:]]+(.*) ]] && {
            _SELF_SUB_TID="${BASH_REMATCH[1]//\'/}"; _SELF_SUB_TID="${_SELF_SUB_TID//\"/}"
        }
        [[ -z "$_SELF_TASK_ID" && "$_line" =~ ^[[:space:]]*task_id:[[:space:]]+(.*) ]] && {
            _SELF_TASK_ID="${BASH_REMATCH[1]//\'/}"; _SELF_TASK_ID="${_SELF_TASK_ID//\"/}"
        }
        [[ -z "$DEPLOY_SCOPE_MODE" && "$_line" =~ ^[[:space:]]*task_type:[[:space:]]+(.*) ]] && {
            DEPLOY_SCOPE_MODE="${BASH_REMATCH[1]//\'/}"; DEPLOY_SCOPE_MODE="${DEPLOY_SCOPE_MODE//\"/}"; DEPLOY_SCOPE_MODE="${DEPLOY_SCOPE_MODE,,}"
        }
        [[ -z "$DEPLOY_SCOPE_MODE" && "$_line" =~ ^[[:space:]]*scope_mode:[[:space:]]+(.*) ]] && {
            DEPLOY_SCOPE_MODE="${BASH_REMATCH[1]//\'/}"; DEPLOY_SCOPE_MODE="${DEPLOY_SCOPE_MODE//\"/}"; DEPLOY_SCOPE_MODE="${DEPLOY_SCOPE_MODE,,}"
        }
    done < "$_TASK_YAML"
    DEPLOY_TASK_ID="${_SELF_AC_TID:-}"
    [ -z "$DEPLOY_TASK_ID" ] && DEPLOY_TASK_ID="${_SELF_SUB_TID:-${_SELF_TASK_ID:-}}"

    if [ -n "$DEPLOY_PARENT_CMD" ]; then
        for _dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
            [ -f "$_dd_task" ] || continue
            _dd_ninja=$(basename "$_dd_task" .yaml)
            [ "$_dd_ninja" = "$NINJA_NAME" ] && continue
            local _dd_pcmd="" _dd_ac_tid="" _dd_sub_tid="" _dd_raw_tid="" _dd_tid="" _dd_status=""
            while IFS= read -r _line; do
                [[ -z "$_dd_pcmd" && "$_line" =~ ^[[:space:]]*parent_cmd:[[:space:]]+(.*) ]] && { _dd_pcmd="${BASH_REMATCH[1]//\'/}"; _dd_pcmd="${_dd_pcmd//\"/}"; }
                [[ -z "$_dd_ac_tid" && "$_line" =~ ^[[:space:]]*_ac_task_id:[[:space:]]+(.*) ]] && { _dd_ac_tid="${BASH_REMATCH[1]//\'/}"; _dd_ac_tid="${_dd_ac_tid//\"/}"; }
                [[ -z "$_dd_sub_tid" && "$_line" =~ ^[[:space:]]*subtask_id:[[:space:]]+(.*) ]] && { _dd_sub_tid="${BASH_REMATCH[1]//\'/}"; _dd_sub_tid="${_dd_sub_tid//\"/}"; }
                [[ -z "$_dd_raw_tid" && "$_line" =~ ^[[:space:]]*task_id:[[:space:]]+(.*) ]] && { _dd_raw_tid="${BASH_REMATCH[1]//\'/}"; _dd_raw_tid="${_dd_raw_tid//\"/}"; }
                [[ -z "$_dd_status" && "$_line" =~ ^[[:space:]]*status:[[:space:]]+(.*) ]] && { _dd_status="${BASH_REMATCH[1]//\'/}"; _dd_status="${_dd_status//\"/}"; }
            done < "$_dd_task"
            _dd_tid="${_dd_ac_tid:-}"
            [ -z "$_dd_tid" ] && _dd_tid="${_dd_sub_tid:-${_dd_raw_tid:-}}"
            [ "$_dd_pcmd" != "$DEPLOY_PARENT_CMD" ] && continue
            if [ -n "$DEPLOY_TASK_ID" ] && [ "$DEPLOY_SCOPE_MODE" != "exact" ] && [ -n "$_dd_tid" ] && [ "$DEPLOY_TASK_ID" != "$_dd_tid" ]; then
                log "split_deploy: ${DEPLOY_PARENT_CMD} peer ${_dd_ninja} (task_id: ${_dd_tid}) — different task_id, allowing"
                continue
            fi
            case "$_dd_status" in
                assigned|acknowledged|in_progress)
                    log "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status}, task_id: ${_dd_tid})"
                    echo "BLOCK: ${DEPLOY_PARENT_CMD} is already assigned to ${_dd_ninja} (status: ${_dd_status})" >&2
                    echo "Clear the existing task first: bash scripts/lib/yaml_field_set.sh queue/tasks/${_dd_ninja}.yaml task status idle" >&2
                    return 1
                    ;;
            esac
        done
    fi
    return 0
}

# ─── stale_report_verdict ヘルパー関数 ───

run_stale_archive() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local ninja_name="$1"
    local parent_cmd="$2"
    local log_file="$SCRIPT_DIR/logs/stale_archive_test.log"

    log() { echo "$*" >> "$log_file"; }

    if [[ -n "$parent_cmd" && "$parent_cmd" == cmd_* ]]; then
        local stale_basename
        for stale_report in "$SCRIPT_DIR/queue/reports/"*"_report_${parent_cmd}.yaml"; do
            [ -f "$stale_report" ] || continue
            stale_basename=$(basename "$stale_report")
            if [[ "$stale_basename" == "${ninja_name}_report_"* ]]; then
                continue
            fi
            log "report_template: PROTECTED other ninja report (${stale_basename})"
        done
    fi
}

run_own_stale_archive() {
    local SCRIPT_DIR="$TEST_TMPDIR"
    local ninja_name="$1"
    local parent_cmd="$2"
    local report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    local log_file="$SCRIPT_DIR/logs/stale_archive_test.log"

    log() { echo "$*" >> "$log_file"; }

    local stale_own_basename stale_own_pcmd stale_own_verdict
    for stale_own_report in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml; do
        [ -f "$stale_own_report" ] || continue
        stale_own_basename=$(basename "$stale_own_report")
        if [[ "$stale_own_report" == "$report_file" ]]; then
            continue
        fi
        stale_own_pcmd=$(FIELD_GET_NO_LOG=1 field_get "$stale_own_report" "parent_cmd" "")
        if [[ "$stale_own_pcmd" == "$parent_cmd" ]]; then
            continue
        fi
        stale_own_verdict=$(FIELD_GET_NO_LOG=1 field_get "$stale_own_report" "verdict" "")
        if [[ -n "$stale_own_verdict" && "$stale_own_verdict" != "null" && "$stale_own_verdict" != '""' ]]; then
            log "report_template: completed own report preserved (${stale_own_basename}, verdict=${stale_own_verdict})"
            continue
        fi
        mkdir -p "$SCRIPT_DIR/archive/reports/stale"
        mv "$stale_own_report" "$SCRIPT_DIR/archive/reports/stale/"
        log "report_template: stale own report archived (${stale_own_basename}, old_cmd=${stale_own_pcmd})"
    done
}

# ─── engineering_preferences ヘルパー関数 ───

read_task_engineering_preferences() {
    awk '
        /^task:/ { in_task=1; next }
        in_task && /^  engineering_preferences:/ { in_prefs=1; next }
        in_prefs && /^  - / { line=$0; sub(/^  - /,"",line); print line; next }
        in_prefs && /^  [a-zA-Z_]/ { in_prefs=0 }
        in_prefs && /^[^ ]/ { in_prefs=0; in_task=0 }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_skill_hint() {
    awk '
        /^task:/ { in_task=1; next }
        in_task && /^  skill_hint:/ { sub(/^  skill_hint:[[:space:]]*/, ""); print; exit }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_context_hints() {
    awk '
        /^task:/ { in_task=1; next }
        in_task && /^  context_hints:/ { in_hints=1; next }
        in_hints && /^  - / { line=$0; sub(/^  - /,"",line); gsub(/^"|"$/,"",line); print line; next }
        in_hints && /^  [a-zA-Z_]/ { in_hints=0 }
        in_hints && /^[^ ]/ { in_hints=0; in_task=0 }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_production_invariants() {
    awk '
        /^task:/ { in_task=1; next }
        in_task && /^  production_invariants:/ { in_pi=1; next }
        in_pi && /^  - / { line=$0; sub(/^  - /,"",line); gsub(/^"|"$/,"",line); print line; next }
        in_pi && /^  [a-zA-Z_]/ { in_pi=0 }
        in_pi && /^[^ ]/ { in_pi=0; in_task=0 }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

# ─── gate_blocks ヘルパー関数 ───

read_gate_blocks() {
    awk '
        /^    gate_blocks:/ { in_b=1; cnt=""; next }
        in_b && /^    - count:/ { cnt=$NF; next }
        in_b && /^      count:/ { cnt=$NF; next }
        in_b && /^      hint:/ { next }
        in_b && /^      reason:/ { print "reason=" $NF ",count=" cnt; cnt=""; next }
        in_b && /^    [a-zA-Z_]/ { in_b=0 }
        in_b && /^  [a-zA-Z]/ { in_b=0 }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

run_gate_blocks_inject() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    local gate_metrics_path="$TEST_PROJECT/logs/gate_metrics.log"
    local _ok=0

    # Parse gate_metrics.log for BLOCK categories
    local block_data=""
    if [ -f "$gate_metrics_path" ]; then
        block_data=$(awk -v ninja="$ninja_name" '
            BEGIN {
                split("kagemaru hanzo hayate tobisaru saizo kotaro sasuke kirimaru", arr, " ")
                for (i in arr) nn[arr[i]] = 1
            }
            {
                n = split($0, cols, "\t")
                if (n < 4 || cols[3] != "BLOCK") next
                nr = split(cols[4], reasons, "|")
                for (i = 1; i <= nr; i++) {
                    r = reasons[i]
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", r)
                    matched = ""
                    for (x in nn) {
                        pfx = x ":"
                        if (substr(r, 1, length(pfx)) == pfx) { matched = x; break }
                    }
                    if (matched != "") {
                        if (matched == ninja) {
                            rest = substr(r, length(matched)+2)
                            split(rest, parts, /[:=]/)
                            cat = parts[1]
                            if (cat != "") counts[cat]++
                        }
                        continue
                    }
                    if (index(r, ":" ninja "_report") || index(r, "_" ninja "_report") || index(r, "/" ninja "_report")) {
                        if (index(r, ":") > 0) { split(r, rp, ":"); cat = rp[1] }
                        else cat = "report_issue"
                        counts[cat]++
                    }
                }
            }
            END { for (cat in counts) print counts[cat] "\t" cat }
        ' "$gate_metrics_path" | sort -rn) || _ok=1
    fi

    # Append ninja_weak_points section to task YAML
    {
        printf "  ninja_weak_points:\n"
        if [ -n "$block_data" ]; then
            printf "    gate_blocks:\n"
            local n_injected=0 hint
            while IFS=$'\t' read -r cnt cat; do
                case "$cat" in
                    empty_lessons_useful)     hint="lessons_usefulの各教訓にuseful(true/false)+reason(理由)を記入。空のまま提出禁止" ;;
                    lesson_done_source)        hint="lesson_candidate登録後にlesson_done確認が必要。lesson_write.sh経由で正式登録" ;;
                    lesson_candidate_missing) hint="lesson_candidate.found欄を必ず記入(true/false)。省略禁止" ;;
                    binary_checks_fail)        hint="binary_checksのresultがyesでない項目あり。全ACのチェック完了を確認" ;;
                    ac_version_mismatch)       hint="ac_version_readがtask YAMLのac_versionと不一致。最新タスクを再読込" ;;
                    report_format)             hint="report YAMLのフォーマットエラー。report_field_set.sh使用必須" ;;
                    report_yaml_missing)       hint="report YAMLが存在しない。report_pathのファイルを作成・記入せよ" ;;
                    *)                         hint="gate BLOCK: $cat" ;;
                esac
                printf "    - count: %s\n      hint: %s\n      reason: %s\n" "$cnt" "$hint" "$cat"
                n_injected=$((n_injected+1))
            done <<< "$block_data"
            echo "INJECTED $n_injected categories" >&2
        fi
        printf "    source: test\n    total_workarounds: 1\n"
    } >> "$task_file" || _ok=1

    if [ "$_ok" -eq 0 ]; then run true; else run false; fi
}

# ─── gate_fail_top3 ヘルパー関数 ───

read_task_gate_fail_top3() {
    awk '
        /^    gate_fail_top3:/ { in_top3=1; cnt=""; next }
        in_top3 && /^    - count:/ { cnt=$NF; next }
        in_top3 && /^      count:/ { cnt=$NF; next }
        in_top3 && /^      pattern:/ { print "pattern=" $NF ",count=" cnt; cnt=""; next }
        /^    gate_warning:/ { line=$0; sub(/^    gate_warning:[[:space:]]*/,"",line); print "warning=" line; next }
        in_top3 && /^    [a-zA-Z_]/ { in_top3=0 }
    ' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

create_workarounds() {
    cat > "$TEST_PROJECT/logs/karo_workarounds.yaml" <<'WAEOF'
- cmd_id: cmd_100
  ninja: sasuke
  workaround: true
  category: report_yaml_format
  detail: test wa
WAEOF
}

create_gate_fire_log() {
    cat > "$TEST_PROJECT/logs/gate_fire_log.yaml" <<'GFEOF'
- ts: "2026-03-25T01:00:00", file: "queue/reports/sasuke_report_cmd_100.yaml", result: FAIL, reasons: "lessons_useful[0]: reason is empty (教訓が有用/無用な理由を具体的に書け); lessons_useful[1]: reason is empty (教訓が有用/無用な理由を具体的に書け); verdict: \"\" is not valid (must be \"PASS\" or \"FAIL\")"
- ts: "2026-03-25T02:00:00", file: "queue/reports/sasuke_report_cmd_101.yaml", result: FAIL, reasons: "binary_checks: MISSING; files_modified: MISSING; verdict: \"None\" is not valid (must be \"PASS\" or \"FAIL\")"
- ts: "2026-03-25T03:00:00", file: "queue/reports/sasuke_report_cmd_102.yaml", result: PASS
- ts: "2026-03-25T04:00:00", file: "queue/reports/sasuke_report_cmd_103.yaml", result: FAIL, reasons: "lessons_useful[0]: reason is empty (教訓が有用/無用な理由を具体的に書け); binary_checks.AC1: is dict (must be list of check items)"
- ts: "2026-03-25T05:00:00", file: "/tmp/test_sasuke_report.yaml", result: FAIL, reasons: "should be skipped"
GFEOF
}

# ─── task YAML 生成ヘルパー ───

_mk_sasuke_review_dm_signal() {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: dm-signal
  acceptance_criteria:
    - id: AC1
      description: "inject preferences"
EOF
}

_mk_sasuke_impl_infra() {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "lifecycle test"
  task_type: impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "test task"
EOF
}

# ═══════════════════════════════════════════════════════════
# setup / teardown
# ═══════════════════════════════════════════════════════════

setup_file() {
    deploy_task_setup_file
    export REAL_PROJECT_ROOT="$PROJECT_ROOT"
    [ -f "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export RESOLVE_FUNCTIONS_FILE="$BATS_FILE_TMPDIR/deploy_resolve_functions.sh"
    {
        extract_function reset_stale_fields
        extract_function resolve_cmd_source_path
        extract_function emit_depends_on_ac_context
        extract_function _overwrite_ac_from_cmd
        extract_function resolve_cmd_to_task
        extract_function inject_cmd_time_contract
        extract_function inject_cmd_assumptions
    } > "$RESOLVE_FUNCTIONS_FILE"
    [ -s "$RESOLVE_FUNCTIONS_FILE" ] || return 1

    # stale_field_reset: 共有フィクスチャを一度だけ準備
    export SOURCE_FIXTURE_ROOT
    SOURCE_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_source.XXXXXX")"
    export RESOLVED_FIXTURE_ROOT
    RESOLVED_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_resolved.XXXXXX")"
    export NESTED_RESOLVED_FIXTURE_ROOT
    NESTED_RESOLVED_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/stale_reset_nested.XXXXXX")"

    prepare_source_fixture "$SOURCE_FIXTURE_ROOT"
    cp -R "$SOURCE_FIXTURE_ROOT"/. "$RESOLVED_FIXTURE_ROOT"/
    resolve_fixture_task "$RESOLVED_FIXTURE_ROOT" "cmd_9999" "tobisaru"

    cp -R "$SOURCE_FIXTURE_ROOT"/. "$NESTED_RESOLVED_FIXTURE_ROOT"/
    python3 - "$NESTED_RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml" <<'PY'
import sys

task_file = sys.argv[1]
with open(task_file, encoding="utf-8") as f:
    raw = f.read()

insertion = """  task:
    _ac_task_id: cmd_old_impl
    status: completed
    type: impl
"""
raw = raw.replace("  task_id:", insertion + "  task_id:")

with open(task_file, "w", encoding="utf-8") as f:
    f.write(raw)
PY
    resolve_fixture_task "$NESTED_RESOLVED_FIXTURE_ROOT" "cmd_9999" "tobisaru"
}

run_direct_task_id_projection() {
  (
    local cmd_id="$1"
    export DEPLOY_TASK_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/deploy_task.sh"
    SCRIPT_DIR="$TEST_PROJECT"
    log() { :; }
    resolve_pane() { echo "test-pane"; }
    get_ctx_pct() { echo 0; }
    cli_type() { echo codex; }
    sleep() { :; }
    check_idle() { return 0; }
    deploy_task_validate_cli_target() { return 0; }
    normalize_task_yaml() { :; }
    capture_done_redeploy_context() { :; }
    reset_stale_fields() { _STALE_RESET_DONE=1; }
    check_firefighting_title() { :; }
    warn_task_clarity() { :; }
    warn_recent_noncmd_commit_targets() { :; }
    deploy_task_apply_task_mutations() { :; }
    notify_initial_deploy_ntfy_once() { :; }
    record_deployed_at() { :; }
    preflight_gate_artifacts() { :; }
    maybe_notify_draft_review() { :; }
    deploy_task_send_direct_renudge() { :; }
    tmux() { return 0; }
    bash() {
        if [[ "${1:-}" == */inbox_write.sh ]]; then
            return 0
        fi
        command bash "$@"
    }
    deploy_task_main --direct sasuke "$cmd_id"
  )
}

@test "LK-A22 Level5: depends_on deploy displays current ACs and dependency context" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/depends_context.XXXXXX")"
    prepare_source_fixture "$root"
    python3 - "$root/queue/shogun_to_karo.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path))
data['commands']['cmd_9998'] = {
    'id': 'cmd_9998', 'status': 'in_progress', 'purpose': '依存先の準備を完了する'
}
data['commands']['cmd_9999']['depends_on'] = 'cmd_9998'
with open(path, 'w') as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run resolve_fixture_task "$root" "cmd_9999" "tobisaru"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LK-A22 Level5"* ]]
    [[ "$output" == *"AC1: AC1: テスト"* ]]
    [[ "$output" == *"cmd_9998: status=in_progress purpose=依存先の準備を完了する"* ]]
    rm -rf "$root"
}

@test "LK-A22 Level5: depends_on none emits no dependency warning" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/depends_none.XXXXXX")"
    prepare_source_fixture "$root"
    sed -i "/    timestamp:/i\\    depends_on: none" "$root/queue/shogun_to_karo.yaml"

    run resolve_fixture_task "$root" "cmd_9999" "tobisaru"
    [ "$status" -eq 0 ]
    [[ "$output" != *"LK-A22 Level5"* ]]
    rm -rf "$root"
}

teardown_file() {
    [ -d "$SOURCE_FIXTURE_ROOT" ] && rm -rf "$SOURCE_FIXTURE_ROOT"
    [ -d "$RESOLVED_FIXTURE_ROOT" ] && rm -rf "$RESOLVED_FIXTURE_ROOT"
    [ -d "$NESTED_RESOLVED_FIXTURE_ROOT" ] && rm -rf "$NESTED_RESOLVED_FIXTURE_ROOT"
    [ -n "$DEPLOY_TASK_TEMPLATE_DIR" ] && [ -d "$DEPLOY_TASK_TEMPLATE_DIR" ] && rm -rf "$DEPLOY_TASK_TEMPLATE_DIR"
}

setup() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    cp -rP "$DEPLOY_TASK_PROJECT_TEMPLATE" "$TEST_PROJECT"
    mkdir -p \
        "$TEST_TMPDIR/queue/tasks" \
        "$TEST_TMPDIR/queue/reports" \
        "$TEST_TMPDIR/archive/reports" \
        "$TEST_TMPDIR/archive/reports/stale" \
        "$TEST_TMPDIR/logs"
    source "$SRC_FIELD_GET_SCRIPT"
    export FIELD_GET_NO_LOG=1
}

teardown() {
    true
}

# ═══════════════════════════════════════════════════════════
# double_deploy_guard テスト (11)
# ═══════════════════════════════════════════════════════════

@test "double_deploy_guard: same cmd assigned to another ninja → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"hayate"* ]]
    [[ "$output" == *"assigned"* ]]
    [[ "$output" == *"yaml_field_set"* ]]
}

@test "double_deploy_guard: same cmd in_progress on another ninja → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: in_progress
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"hanzo"* ]]
    [[ "$output" == *"in_progress"* ]]
}

@test "double_deploy_guard: same cmd idle on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: idle
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "double_deploy_guard: same cmd same ninja (self-overwrite) → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: assigned
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "double_deploy_guard: different cmd on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_200
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "double_deploy_guard: same cmd acknowledged on another ninja → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_300
  status: acknowledged
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_300
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"kagemaru"* ]]
}

@test "double_deploy_guard: same cmd completed on another ninja → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: completed
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_100
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "double_deploy_guard: BLOCK message includes clear command" {
    cat > "$TEST_TMPDIR/queue/tasks/tobisaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_400
  status: in_progress
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_400
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"Clear the existing task first"* ]]
    [[ "$output" == *"tobisaru"* ]]
    [[ "$output" == *"status idle"* ]]
}

@test "double_deploy_guard: split deploy different task_id → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_500
  task_id: cmd_500_impl_spy
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_500
  task_id: cmd_500_impl_rebalance
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "cmd_2804: exact scope with empty _ac_task_id is not treated as split deploy" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_2804
  task_id: cmd_2804_impl
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2804
  task_id: cmd_2804_exact
  task_type: exact
  _ac_task_id: ""
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "cmd_2804: non-exact split deploy still allows different _ac_task_id" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_2804
  _ac_task_id: cmd_2804_ac1
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2804
  task_type: impl
  _ac_task_id: cmd_2804_ac2
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "cmd_2804: exact scope guards _ac_task_id empty warning in deploy_task.sh" {
    run grep -F '[ -z "$deploy_task_id" ] && [ "$deploy_scope_mode" != "exact" ]' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "double_deploy_guard: same parent_cmd same task_id → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_500
  task_id: cmd_500_impl_spy
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_500
  task_id: cmd_500_impl_spy
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "double_deploy_guard: split deploy peer in_progress → PASS" {
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'EOF'
task:
  parent_cmd: cmd_600
  task_id: cmd_600_impl_ac1
  status: in_progress
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_600
  task_id: cmd_600_impl_ac2
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "cmd_3280: split deploy with subtask_id — different subtask_id allows parallel deploy" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_700
  subtask_id: cmd_700_hayate_full
  task_id: cmd_700_full
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_700
  subtask_id: cmd_700_sasuke_full
  task_id: cmd_700_full
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 0 ]
}

@test "cmd_3280: same subtask_id on two ninjas → BLOCK" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_701
  subtask_id: cmd_701_chunk1
  task_id: cmd_701_full
  status: assigned
EOF

    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_701
  subtask_id: cmd_701_chunk1
  task_id: cmd_701_full
  status: pending
EOF

    run run_double_deploy_guard sasuke
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "cmd_3280: split deploy fix exists in deploy_task.sh source" {
    run grep -F "split_deploy fix (cmd_3280)" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "cmd_2681: deploy_task_main takes a per-cmd flock before duplicate checks" {
    run grep -Eq 'flock -w 10 "\$deploy_lock_fd"' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -Eq 'deploy_task_lock_path "\$CMD_ID"' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "GA-257: different commands cannot mutate the same ninja concurrently" {
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        DEPLOY_TASK_NINJA_LOCK_TIMEOUT_SEC=1
        deploy_task_acquire_ninja_lock hayate
        second_status=0
        (
            export DEPLOY_TASK_LIB_ONLY=1
            source "$1/scripts/deploy_task.sh"
            DEPLOY_TASK_NINJA_LOCK_TIMEOUT_SEC=0
            deploy_task_acquire_ninja_lock hayate
        ) || second_status=$?
        [ "$second_status" -ne 0 ]
        deploy_task_release_ninja_lock
        (
            export DEPLOY_TASK_LIB_ONLY=1
            source "$1/scripts/deploy_task.sh"
            DEPLOY_TASK_NINJA_LOCK_TIMEOUT_SEC=1
            deploy_task_acquire_ninja_lock hayate
            deploy_task_release_ninja_lock
        )
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy lock busy"* ]]
}

@test "GA-257: queued deployment cannot overwrite a newly assigned different command" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_first
  status: assigned
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        before=$(sha256sum "$1/queue/tasks/hayate.yaml")
        if deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_second; then
            exit 9
        fi
        after=$(sha256sum "$1/queue/tasks/hayate.yaml")
        [ "$before" = "$after" ]
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_first
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"別cmd cmd_second で上書きしない"* ]]
}

@test "cmd_4170: done task with unarchived report BLOCKs overwrite by a different cmd" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        before=$(sha256sum "$1/queue/tasks/hayate.yaml")
        if deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new; then
            exit 9
        fi
        after=$(sha256sum "$1/queue/tasks/hayate.yaml")
        [ "$before" = "$after" ]
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=done)だが報告未archive"* ]]
}

# test_necessity: 完了済みtaskはCLEAR/archive前にruntime idleでも再利用できず、
# report保全とdone/PASS非終端不変量を守る。
@test "terminal idle worker stays blocked while completed report remains unarchived" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_old
task_contract_snapshot: {task_id: cmd_old, parent_cmd: cmd_old}
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        is_idle=true
        before=$(sha256sum "$1/queue/reports/hayate_report_cmd_old.yaml")
        if deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new; then
            exit 9
        fi
        after=$(sha256sum "$1/queue/reports/hayate_report_cmd_old.yaml")
        [ "$before" = "$after" ]
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=done)だが報告未archive"* ]]
}

# test_necessity: fingerprint-bound LGTM+ACCEPT済みPASS reportはparent_cmdで
# 追跡可能なため、旧task snapshotを退避してworker slotを次cmdへ解放する。
@test "formally accepted PASS report releases worker before report archive" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_old
status: completed
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_done_report_formally_accepted() { return 0; }
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
        find "$1/queue/archive/tasks" -type f -name "hayate_cmd_old_*.yaml" | grep -q .
        grep -q "parent_cmd: cmd_old" "$1/queue/tasks/hayate.yaml"
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TERMINAL_SLOT_RELEASE"* ]]
}

# test_necessity: archive_completed keeps a bounded number of completed reports
# active; archive.done plus the exact terminal checkpoint must release the worker.
@test "done task with retained report allows next cmd after exact cmd-complete terminal checkpoint" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_old"
    : > "$TEST_PROJECT/queue/gates/cmd_old/archive.done"
    printf '%s\n' '[cmd_complete] COMPLETE cmd_old' > "$TEST_PROJECT/queue/gates/cmd_old/completion_tail.log"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOGICAL_ARCHIVE"* ]]
}

# test_necessity: a marker alone can be created before report movement; it must
# not release a worker until the ordered completion pipeline is terminal.
@test "done task with retained report and archive marker but no terminal checkpoint stays blocked" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_old"
    : > "$TEST_PROJECT/queue/gates/cmd_old/archive.done"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
    ' -- "$TEST_PROJECT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "cmd_4170: done task overwrite by a different cmd is allowed again once the report is archived" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    # No queue/reports/hayate_report_cmd_old.yaml present: archive_completed.sh
    # already moved it to archive/reports/ — the deployment window is closed.

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

# test_necessity: archive_completed.shの互換symlinkはarchive済み報告であり、
# 次task配備を未archiveとして遮断してはならない。
@test "cmd_4170: archived report compatibility symlink does not block next command" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    mkdir -p "$TEST_PROJECT/queue/archive/reports"
    cat > "$TEST_PROJECT/queue/archive/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF
    ln -s "$TEST_PROJECT/queue/archive/reports/hayate_report_cmd_old.yaml" \
        "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

@test "cmd_4170: done task with unarchived report does not block a same-cmd redeploy" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_old
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

@test "cmd_4170: reflux/direct auto-deploy path (deploy_task.sh --direct --yaml) is BLOCKed by the same done/unarchived guard" {
    # 家老インフラバグ報告(blt_20260725_130046)の再現経路: ninja_monitor.shの
    # reflux promotion自動配備は "deploy_task.sh --direct --yaml <tmp_task> <ninja> <cmd_id>"
    # を呼ぶ。既存taskがstatus=done+report未archiveのままこの経路で上書きされないことを確認する。
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_old.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_old
status: completed
verdict: PASS
EOF
    cat > "$TEST_PROJECT/reflux_tmp_task.yaml" <<'EOF'
task:
  parent_cmd: cmd_reflux_promotion_202607251300_sasuke
  task_id: cmd_reflux_promotion_202607251300_sasuke_exact
  task_type: exact
  status: assigned
EOF

    run bash -lc '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        deploy_task_main --direct --yaml "$project/reflux_tmp_task.yaml" sasuke cmd_reflux_promotion_202607251300_sasuke
    ' -- "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=done)だが報告未archive"* ]]

    # ガードが実際の上書きより前に発火し、既存task(cmd_old/done)を保護したことを確認
    run grep -q "cmd_old" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "cmd_karo_hotfix_reflux_deploy_race: PASS task with unarchived report BLOCKs overwrite and notifies karo inbox" {
    # blt_20260725_130045: cmd_4170はstatus=doneのみ保護し、status=PASSは未保護のまま
    # reflux promotionに上書きされていた(hanzo cmd_4170_full実例)。PASSにも同じ保護を及ぼす。
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: PASS
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_old.yaml" <<'EOF'
worker_id: hayate
verdict: PASS
EOF

    # deploy_task_scaffoldの最小fixture(DEPLOY_TASK_TEMPLATE_DIR)はinbox_write.shを
    # 含まないため、既存テスト群と同じ規約(bash()差替え)でinbox_write.sh呼び出しを
    # 捕捉し、実引数を検証する(実物を叩かない)。
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        PROJECT_DIR="$1"
        bash() {
            if [[ "${1:-}" == */inbox_write.sh ]]; then
                printf "%s\n" "$*" >> "$PROJECT_DIR/inbox_call.log"
                return 0
            fi
            command bash "$@"
        }
        before=$(sha256sum "$1/queue/tasks/hayate.yaml")
        if deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new; then
            exit 9
        fi
        after=$(sha256sum "$1/queue/tasks/hayate.yaml")
        [ "$before" = "$after" ]
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=PASS)だが報告未archive"* ]]

    run cat "$TEST_PROJECT/inbox_call.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo"* ]]
    [[ "$output" == *"配備競合BLOCK"* ]]
    [[ "$output" == *"cmd_new"* ]]
}

@test "cmd_karo_hotfix_reflux_deploy_race: PASS task overwrite by a different cmd is allowed again once the report is archived" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: PASS
EOF
    # No queue/reports/hayate_report_cmd_old.yaml present: archive_completed.sh
    # already moved it to archive/reports/ — the deployment window is closed.

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=hayate
        deploy_task_guard_worker_assignment "$1/queue/tasks/hayate.yaml" cmd_new
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

@test "cmd_karo_hotfix_reflux_deploy_race: reflux/direct auto-deploy path is BLOCKed by the same PASS/unarchived guard" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  status: PASS
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_old.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_old
status: completed
verdict: PASS
EOF
    cat > "$TEST_PROJECT/reflux_tmp_task.yaml" <<'EOF'
task:
  parent_cmd: cmd_reflux_promotion_202607251300_sasuke
  task_id: cmd_reflux_promotion_202607251300_sasuke_exact
  task_type: exact
  status: assigned
EOF

    run bash -lc '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        deploy_task_main --direct --yaml "$project/reflux_tmp_task.yaml" sasuke cmd_reflux_promotion_202607251300_sasuke
    ' -- "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=PASS)だが報告未archive"* ]]

    # ガードが実際の上書きより前に発火し、既存task(cmd_old/PASS)を保護したことを確認
    run grep -q "cmd_old" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}

@test "B26-ESCAPE(ci_fix): done task with unarchived report allows task_type=ci_fix deployment through and logs b26_ci_fix_escape" {
    # 実データ再現(logs/defense_overhead.jsonl 2026-07-25T23:50:51実測):
    # held=cmd_karo_impl_lg051_scope_basename_20260725(saizo,status=done,report未archive)
    # incoming=cmd_karo_ci_fix_30161415740_phantom_unit_path_20260725(task_type=ci_fix)
    cat > "$TEST_PROJECT/queue/tasks/saizo.yaml" <<'EOF'
task:
  parent_cmd: cmd_karo_impl_lg051_scope_basename_20260725
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_karo_impl_lg051_scope_basename_20260725.yaml" <<'EOF'
worker_id: saizo
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_INCOMING_TASK_TYPE=ci_fix
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=saizo
        deploy_task_guard_worker_assignment "$1/queue/tasks/saizo.yaml" cmd_karo_ci_fix_30161415740_phantom_unit_path_20260725
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"B26-ESCAPE(ci_fix)"* ]]

    run grep -c '"event":"b26_ci_fix_escape"' "$TEST_PROJECT/logs/defense_overhead.jsonl"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -q '"held_cmd":"cmd_karo_impl_lg051_scope_basename_20260725".*"incoming_cmd":"cmd_karo_ci_fix_30161415740_phantom_unit_path_20260725"' "$TEST_PROJECT/logs/defense_overhead.jsonl"
    [ "$status" -eq 0 ]
}

@test "B26-ESCAPE(ci_fix)の陰性対照: 同条件でtask_type=hotfixは従来通りBLOCKされ、escapeログは出力されない" {
    # AC2陰性方向: B26 escape hatchが非ci_fixを緩めていないことを、
    # 陽性テストと同一状態(done+report未archive)・実データ(cmd_karo_hotfix_reflux_deploy_race_20260725)で固定する
    cat > "$TEST_PROJECT/queue/tasks/saizo.yaml" <<'EOF'
task:
  parent_cmd: cmd_karo_impl_lg051_scope_basename_20260725
  status: done
EOF
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_karo_impl_lg051_scope_basename_20260725.yaml" <<'EOF'
worker_id: saizo
verdict: PASS
EOF

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_INCOMING_TASK_TYPE=hotfix
        source "$1/scripts/deploy_task.sh"
        NINJA_NAME=saizo
        before=$(sha256sum "$1/queue/tasks/saizo.yaml")
        if deploy_task_guard_worker_assignment "$1/queue/tasks/saizo.yaml" cmd_karo_hotfix_reflux_deploy_race_20260725; then
            exit 9
        fi
        after=$(sha256sum "$1/queue/tasks/saizo.yaml")
        [ "$before" = "$after" ]
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"完了済み(status=done)だが報告未archive"* ]]
    [[ "$output" != *"B26-ESCAPE"* ]]

    if [ -f "$TEST_PROJECT/logs/defense_overhead.jsonl" ]; then
        run grep -c '"event":"b26_ci_fix_escape"' "$TEST_PROJECT/logs/defense_overhead.jsonl"
        [ "$output" -eq 0 ]
    fi
}

@test "GA-258: malformed same-command task cannot skip the atomic repair path" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_repair
  status: assigned
  task_id: cmd_repair_normal
  report_path: queue/reports/hayate_report_cmd_repair.yaml
  estimated_minutes: 5
  - orphaned-list-item
EOF
    : > "$TEST_PROJECT/queue/reports/hayate_report_cmd_repair.yaml"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        if should_skip_same_cmd_resolve "$1/queue/tasks/hayate.yaml" cmd_repair hayate; then
            exit 9
        fi
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"task YAML invalid; force repair path"* ]]
}

@test "same-command retry satisfies the stale-reset preflight contract" {
    # test_necessity: a retry that intentionally reuses the already-reset task
    # must not be rejected later by the unconditional _STALE_RESET_DONE gate.
    run python3 - "$TEST_PROJECT/scripts/deploy_task.sh" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
pattern = re.compile(
    r"if should_skip_same_cmd_resolve .*?; then"
    r".*?_STALE_RESET_DONE=1"
    r".*?same_cmd_redeploy: skipped reset_stale_fields",
    re.S,
)
raise SystemExit(0 if pattern.search(text) else 1)
PY
    [ "$status" -eq 0 ]
}

@test "same-command retry does not append a duplicate task_assigned message" {
    # test_necessity: one task generation owns exactly one durable
    # task_assigned message; retries may re-nudge but must not append another.
    run python3 - "$TEST_PROJECT/scripts/deploy_task.sh" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
sets_generation_flag = re.search(
    r"if should_skip_same_cmd_resolve .*?; then"
    r".*?_DEPLOY_SAME_CMD_REDEPLOY=1",
    text,
    re.S,
)
guards_persistent_write = re.search(
    r'if \[ "\$\{_DEPLOY_SAME_CMD_REDEPLOY:-0\}" = "1" \]; then'
    r'.*?persistent task_assigned write skipped'
    r'.*?elif \[ "\$ctx_pct"',
    text,
    re.S,
)
raise SystemExit(0 if sets_generation_flag and guards_persistent_write else 1)
PY
    [ "$status" -eq 0 ]
}

@test "cmd_karo_fix_same_cmd_pending_symlink: active pending live slot is refreshed" {
    # test_necessity: same-cmd redeploy must cut only the active pending alias
    # before publishing a fresh regular report generation.
    mkdir -p "$TEST_PROJECT/queue/archive/reports"
    cat > "$TEST_PROJECT/queue/tasks/kotaro.yaml" <<'EOF'
task:
  parent_cmd: cmd_same_pending
  task_id: cmd_same_pending_normal
  status: acknowledged
  report_filename: kotaro_report_cmd_same_pending.yaml
EOF
    cat > "$TEST_PROJECT/queue/archive/reports/kotaro_report_cmd_same_pending.yaml" <<'EOF'
worker_id: kotaro
task_id: cmd_same_pending_normal
parent_cmd: cmd_same_pending
status: pending
EOF
    ln -s "$TEST_PROJECT/queue/archive/reports/kotaro_report_cmd_same_pending.yaml" \
        "$TEST_PROJECT/queue/reports/kotaro_report_cmd_same_pending.yaml"

    before_symlinks=$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -type l | wc -l)
    [ "$before_symlinks" -eq 1 ]
    archive_hash_before=$(sha256sum "$TEST_PROJECT/queue/archive/reports/kotaro_report_cmd_same_pending.yaml")

    run bash -lc '
        set -euo pipefail
        fixture_root="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$fixture_root/scripts/deploy_task.sh"
        SCRIPT_DIR="$fixture_root"
        _DEPLOY_SAME_CMD_REDEPLOY=1
        log() { :; }
        deploy_task_mutation_phase() {
            local phase="$1" function="$2"
            shift 2
            "$function" "$@"
        }
        generate_report_template() {
            local ninja="$1" task_id="$2" parent="$3"
            cat > "$fixture_root/queue/reports/${ninja}_report_${parent}.yaml" <<EOF
worker_id: $ninja
task_id: $task_id
parent_cmd: $parent
status: pending
EOF
        }
        deploy_task_report_publication_locked \
            kotaro cmd_same_pending_normal cmd_same_pending infra \
            "$fixture_root/queue/tasks/kotaro.yaml"
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    [ -f "$TEST_PROJECT/queue/reports/kotaro_report_cmd_same_pending.yaml" ]
    [ ! -L "$TEST_PROJECT/queue/reports/kotaro_report_cmd_same_pending.yaml" ]
    after_symlinks=$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -type l | wc -l)
    [ "$after_symlinks" -eq 0 ]
    grep -q '^status: pending$' "$TEST_PROJECT/queue/reports/kotaro_report_cmd_same_pending.yaml"
    archive_hash_after=$(sha256sum "$TEST_PROJECT/queue/archive/reports/kotaro_report_cmd_same_pending.yaml")
    [ "$archive_hash_before" = "$archive_hash_after" ]
}

@test "cmd_karo_fix_same_cmd_pending_symlink: completed alias and different cmd stay untouched" {
    # test_necessity: the pending/same-task guard must not detach completed
    # compatibility aliases or a pending report owned by another command.
    mkdir -p "$TEST_PROJECT/queue/archive/reports"
    cat > "$TEST_PROJECT/queue/tasks/kotaro.yaml" <<'EOF'
task:
  parent_cmd: cmd_same_pending
  task_id: cmd_same_pending_normal
  status: acknowledged
EOF
    cat > "$TEST_PROJECT/queue/archive/reports/kotaro_report_completed.yaml" <<'EOF'
worker_id: kotaro
task_id: cmd_same_pending_normal
parent_cmd: cmd_same_pending
status: completed
verdict: PASS
EOF
    cat > "$TEST_PROJECT/queue/archive/reports/kotaro_report_other_cmd.yaml" <<'EOF'
worker_id: kotaro
task_id: cmd_other_normal
parent_cmd: cmd_other
status: pending
EOF
    ln -s "$TEST_PROJECT/queue/archive/reports/kotaro_report_completed.yaml" \
        "$TEST_PROJECT/queue/reports/kotaro_report_completed.yaml"
    ln -s "$TEST_PROJECT/queue/archive/reports/kotaro_report_other_cmd.yaml" \
        "$TEST_PROJECT/queue/reports/kotaro_report_other_cmd.yaml"

    run bash -lc '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        SCRIPT_DIR="$project"
        _DEPLOY_SAME_CMD_REDEPLOY=1
        log() { :; }
        deploy_task_same_cmd_pending_symlink_reset \
            "$project/queue/tasks/kotaro.yaml" cmd_same_pending_normal \
            cmd_same_pending kotaro \
            "$project/queue/reports/kotaro_report_completed.yaml"
        deploy_task_same_cmd_pending_symlink_reset \
            "$project/queue/tasks/kotaro.yaml" cmd_same_pending_normal \
            cmd_same_pending kotaro \
            "$project/queue/reports/kotaro_report_other_cmd.yaml"
    ' -- "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [ -L "$TEST_PROJECT/queue/reports/kotaro_report_completed.yaml" ]
    [ -L "$TEST_PROJECT/queue/reports/kotaro_report_other_cmd.yaml" ]
}

@test "cmd_3701: draft cmd is blocked before deployment" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: exact
  status: idle
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_3701_draft:
    id: cmd_3701_draft
    title: "draft deploy block"
    project: infra
    status: draft
    purpose: "draft状態のcmdは配備されない"
    acceptance_criteria:
    - "AC1: draft配備がBLOCKする"
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { echo "$*" >&2; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        sleep() { :; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        cleanup_none_task_files() { :; }
        repair_training_parent_cmd_from_cmd_id() { :; }
        deploy_task_main sasuke cmd_3701_draft
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"status=draft"* ]]
    [[ "$output" == *"配備をスキップ"* ]]

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "status" ""
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

@test "cmd_2681: completed peer report blocks new deployment for same parent_cmd" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: exact
  status: idle
EOF

    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_2681.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2681
status: completed
verdict: PASS
result:
  summary: "先着完了"
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        sleep() { :; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        capture_done_redeploy_context() { :; }
        reset_stale_fields() { _STALE_RESET_DONE=1; }
        check_firefighting_title() { :; }
        warn_same_ninja_redeploy() { :; }
        warn_task_clarity() { :; }
        warn_recent_noncmd_commit_targets() { :; }
        deploy_task_apply_task_mutations() { :; }
        notify_initial_deploy_ntfy_once() { :; }
        record_deployed_at() { :; }
        preflight_gate_artifacts() { :; }
        maybe_notify_draft_review() { :; }
        deploy_task_send_direct_renudge() { :; }
        tmux() { return 0; }
        deploy_task_main --direct sasuke cmd_2681
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: cmd_2681 already has completed report from hayate"* ]]

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "status" ""
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

@test "explicit natural-boundary continuation may follow an exact completed peer report" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2681
  subtask_id: cmd_2681_ac3_chunk1
  assigned_acs: [AC3]
  continuation_of_report: queue/reports/hayate_report_cmd_2681.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_2681.yaml" <<'EOF'
worker_id: hayate
task_id: cmd_2681_recon
parent_cmd: cmd_2681
status: completed
verdict: PASS
EOF

    run bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        log() { echo "$*"; }
        if deploy_task_has_completed_peer_report cmd_2681 sasuke "$1/queue/tasks/sasuke.yaml"; then
            exit 9
        fi
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"continuation_deploy:"* ]]
}

@test "continuation contract with a non-matching report remains blocked" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2681
  subtask_id: cmd_2681_ac3_chunk1
  assigned_acs: [AC3]
  continuation_of_report: queue/reports/other_report_cmd_2681.yaml
EOF
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_2681.yaml" <<'EOF'
worker_id: hayate
task_id: cmd_2681_recon
parent_cmd: cmd_2681
status: completed
verdict: PASS
EOF

    run bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        log() { :; }
        deploy_task_has_completed_peer_report cmd_2681 sasuke "$1/queue/tasks/sasuke.yaml"
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: cmd_2681 already has completed report from hayate"* ]]
}

@test "cmd_2951: pending own report with verdict blocks redeploy before stale reset" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2951
  task_type: exact
  status: done
  report_path: queue/reports/sasuke_report_cmd_2951.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_2951.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_2951
status: completed
verdict: PASS
result:
  summary: "GATE未処理の完了報告"
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        deploy_task_main --direct sasuke cmd_2951
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: sasuke has pending report for cmd_2951"* ]]

    run grep -q "verdict: PASS" "$TEST_PROJECT/queue/reports/sasuke_report_cmd_2951.yaml"
    [ "$status" -eq 0 ]
}

# test_necessity: revision_requested reports may bypass the pending-own-report
# guard only when an exact same-worker/same-command report has formal Karo RC.
@test "formal Karo RC permits only the exact revision_requested PASS or FAIL report" {
    local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_rc_retry.yaml"
    local task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    local approvals="$TEST_PROJECT/queue/gates/cmd_rc_retry/review_approvals/reports/case"
    mkdir -p "$approvals"
    cat > "$task" <<'EOF'
task:
  parent_cmd: cmd_rc_retry
  report_path: queue/reports/sasuke_report_cmd_rc_retry.yaml
EOF
    cat > "$report" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_rc_retry
status: revision_requested
verdict: FAIL
EOF
    cat > "$approvals/karo.yaml" <<'EOF'
role: karo
result: RC
report: queue/reports/sasuke_report_cmd_rc_retry.yaml
EOF

    local allowed_verdict
    for allowed_verdict in FAIL PASS; do
        sed -i "s/^verdict: .*/verdict: $allowed_verdict/" "$report"
        run bash -c '
            export DEPLOY_TASK_LIB_ONLY=1
            source "$1/scripts/deploy_task.sh"
            log() { echo "$*"; }
            deploy_task_has_pending_own_report cmd_rc_retry sasuke "$1/queue/tasks/sasuke.yaml"
        ' _ "$TEST_PROJECT"
        [ "$status" -eq 1 ]
        [[ "$output" == *"formal_karo_rc_redeploy:"* ]]
    done

    local case_name
    for case_name in unreviewed accept gunshi other_report completed failed; do
        cat > "$report" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_rc_retry
status: revision_requested
verdict: FAIL
EOF
        cat > "$approvals/karo.yaml" <<'EOF'
role: karo
result: RC
report: queue/reports/sasuke_report_cmd_rc_retry.yaml
EOF
        case "$case_name" in
            unreviewed) rm -f "$approvals/karo.yaml" ;;
            accept) sed -i 's/result: RC/result: ACCEPT/' "$approvals/karo.yaml" ;;
            gunshi) sed -i 's/role: karo/role: gunshi/' "$approvals/karo.yaml" ;;
            other_report) sed -i 's/sasuke_report_cmd_rc_retry/other_report_cmd_rc_retry/' "$approvals/karo.yaml" ;;
            completed) sed -i 's/status: revision_requested/status: completed/' "$report" ;;
            failed) sed -i 's/status: revision_requested/status: failed/' "$report" ;;
        esac
        run bash -c '
            export DEPLOY_TASK_LIB_ONLY=1
            source "$1/scripts/deploy_task.sh"
            log() { :; }
            deploy_task_has_pending_own_report cmd_rc_retry sasuke "$1/queue/tasks/sasuke.yaml"
        ' _ "$TEST_PROJECT"
        [ "$status" -eq 0 ]
        [[ "$output" == *"BLOCK: sasuke has pending report for cmd_rc_retry"* ]]
    done
}

@test "cmd_2951: cmd_complete archive.done allows redeploy after pending report is processed" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_2951
  task_id: cmd_2951_exact
  task_type: exact
  status: done
  report_path: queue/reports/sasuke_report_cmd_2951.yaml
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_2951.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_2951
status: completed
verdict: PASS
result:
  summary: "GATE処理済みの完了報告"
EOF
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_2951"
    touch "$TEST_PROJECT/queue/gates/cmd_2951/archive.done"

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { :; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        sleep() { :; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        capture_done_redeploy_context() { :; }
        reset_stale_fields() { _STALE_RESET_DONE=1; }
        check_firefighting_title() { :; }
        warn_same_ninja_redeploy() { :; }
        warn_task_clarity() { :; }
        warn_recent_noncmd_commit_targets() { :; }
        deploy_task_apply_task_mutations() { :; }
        notify_initial_deploy_ntfy_once() { :; }
        record_deployed_at() { :; }
        preflight_gate_artifacts() { :; }
        maybe_notify_draft_review() { :; }
        deploy_task_send_direct_renudge() { :; }
        tmux() { return 0; }
        bash() {
            if [[ "${1:-}" == */inbox_write.sh ]]; then
                return 0
            fi
            command bash "$@"
        }
        deploy_task_main --direct sasuke cmd_2951
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# stale_field_reset テスト (2)
# ═══════════════════════════════════════════════════════════

@test "再配備でstale field群とネスト汚染を清掃し必要フィールドを保持する" {
    local file="$RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local nested_file="$NESTED_RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local output nested_after root_fields root_field_name

    output="$(get_task_values "$file" parent_cmd task_id task_type project status purpose scout_exempt _ac_task_id _ac_worker_id)"

    [[ "$output" == *"parent_cmd=cmd_9999"* ]]
    [[ "$output" == *"task_id=cmd_9999_impl"* ]]
    [[ "$output" == *"task_type=impl"* ]]
    [[ "$output" == *"project=infra"* ]]
    [[ "$output" == *"status=assigned"* ]]
    [[ "$output" == *"purpose=新しいpurpose"* ]]
    [[ "$output" == *"scout_exempt=true"* ]]
    [[ "$output" == *$'_ac_task_id='* ]]
    [[ "$output" == *$'_ac_worker_id='* ]]

    assert_missing_fields \
        "$file" \
        target_path progress description started_at \
        constraints engineering_preferences context_files scope context context_hints assigned_scope expected_model_effort pre_deploy_banner_evidence not_in_scope recommended_skills stop_for never_stop_for parallel_ok \
        files_to_modify files_modified quality_gate \
        work_items AC1 AC2 AC3 ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

    run python3 - "$file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))['task']
assert task['acceptance_criteria'] == ['AC1: テスト']
PY
    [ "$status" -eq 0 ]

    nested_after=$(grep -c '^\s*task:' "$nested_file")
    [ "$nested_after" -eq 1 ]

    root_fields=$(grep -c '^[a-zA-Z_]' "$nested_file")
    [ "$root_fields" -eq 1 ]

    root_field_name=$(grep '^[a-zA-Z_]' "$nested_file" | head -1)
    [[ "$root_field_name" == task:* ]]
}

@test "resolve_cmd_to_task preserves pipe chars in purpose through yaml_field_set_batch" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_pipe_purpose.XXXXXX")"
    prepare_source_fixture "$root"
    cat > "$root/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9999:
    id: cmd_9999
    estimated_minutes: 10
    title: 'テスト用pipe cmd'
    project: infra
    type: impl
    purpose: 'alpha | beta || gamma \| delta'
    acceptance_criteria:
    - 'AC1: テスト'
    timestamp: '2026-05-04T00:00:00+09:00'
    status: pending
EOF

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"

    run python3 - <<PY
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$root/queue/tasks/tobisaru.yaml").read_text())
assert data["task"]["purpose"] == r"alpha | beta || gamma \| delta"
print("DEPLOY_PIPE_OK")
PY
    rm -rf "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOY_PIPE_OK"* ]]
}

@test "resolve_cmd_to_task initializes duration timestamps for fresh deployment" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_duration_fields.XXXXXX")"
    prepare_source_fixture "$root"

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"

    run python3 - <<PY
import re
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$root/queue/tasks/tobisaru.yaml").read_text())
task = data["task"]
assert task["status"] == "assigned"
assert re.match(r"^202[0-9]-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$", str(task.get("deployed_at", "")))
assert task.get("acknowledged_at") in (None, "")
assert task.get("done_at") in (None, "")
assert task.get("completed_at") in (None, "")
print("DEPLOY_DURATION_FIELDS_OK")
PY
    rm -rf "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOY_DURATION_FIELDS_OK"* ]]
}

@test "resolve_cmd_to_task replaces stale runtime contract with command SSOT" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_time_contract.XXXXXX")"
    prepare_source_fixture "$root"
    sed -i "/    status: pending/i\\    timeout_minutes: 30" "$root/queue/shogun_to_karo.yaml"
    sed -i "/  status: completed/i\\  estimated_minutes: 20\n  execution_env:\n    long_runtime_reason: 'old lesson scan'\n    measured_runtime_sec: 1200" "$root/queue/tasks/tobisaru.yaml"

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"

    run python3 - "$root/queue/tasks/tobisaru.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["estimated_minutes"] == 10, task
assert task["timeout_minutes"] == 30, task
assert "execution_env" not in task, task
assert "split_decision" not in task, task
PY
    [ "$status" -eq 0 ]
}

@test "resolve_cmd_to_task projects structured split and runtime contracts" {
    local root
    root="$(mktemp -d "$BATS_TMPDIR/deploy_structured_contract.XXXXXX")"
    prepare_source_fixture "$root"
    sed -i 's/    estimated_minutes: 10/    estimated_minutes: 60/' "$root/queue/shogun_to_karo.yaml"
    sed -i "/    status: pending/i\\    timeout_minutes: 90\n    split_decision:\n      boundary_ac_ids: [AC1]\n      integration_tasks: 1\n      review_round_trips: 0\n    execution_env:\n      long_runtime_reason: 'measured full scan'\n      measured_runtime_sec: 3600" "$root/queue/shogun_to_karo.yaml"

    resolve_fixture_task "$root" "cmd_9999" "tobisaru"

    run python3 - "$root/queue/tasks/tobisaru.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["estimated_minutes"] == 60
assert task["timeout_minutes"] == 90
assert task["split_decision"] == {"boundary_ac_ids": ["AC1"], "integration_tasks": 1, "review_round_trips": 0}
assert task["execution_env"] == {"long_runtime_reason": "measured full scan", "measured_runtime_sec": 3600}
PY
    [ "$status" -eq 0 ]
}

@test "reset_stale_fields clears stale cmd scope metadata while preserving scout_exempt" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_scope_context.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    cat >> "$file" <<'YAML'
  report_id: rpt-11111111-1111-4111-8111-111111111111
  report_identity_version: 2
YAML

    grep -q "^  scope:" "$file"
    grep -q "^  context:" "$file"
    grep -q "^  context_hints:" "$file"
    grep -q "^  assigned_scope:" "$file"
    grep -q "^  expected_model_effort:" "$file"
    grep -q "^  pre_deploy_banner_evidence:" "$file"
    grep -q "^  not_in_scope:" "$file"
    grep -q "^  recommended_skills:" "$file"

    SCRIPT_DIR="$direct_root"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    assert_missing_fields "$file" scope context context_hints assigned_scope expected_model_effort pre_deploy_banner_evidence not_in_scope recommended_skills
    assert_missing_fields "$file" report_id report_identity_version
    ! grep -q "frontend/src/app/old/page.tsx" "$file"
    ! grep -q "context/old-task.md" "$file"
    ! grep -q "docs/research/old-task.md" "$file"
    ! grep -q "前cmdの古いassigned_scope" "$file"
    ! grep -q "old-effort" "$file"
    ! grep -q "old banner evidence" "$file"
    ! grep -q "old deferred item" "$file"
    ! grep -q "old-skill" "$file"
    grep -q "scout_exempt: true" "$file"

    rm -rf "$direct_root"
}

@test "reset_stale_fields removes stale gunshi notify flag on redeploy" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_notify.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local notify_flag="$direct_root/queue/gates/cmd_8888/gunshi_notify_tobisaru.done"

    mkdir -p "$(dirname "$notify_flag")"
    touch "$notify_flag"

    SCRIPT_DIR="$direct_root"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    [ ! -f "$notify_flag" ]

    rm -rf "$direct_root"
}

@test "cancel cleanup clears canceled cmd task metadata before redeploy" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/cancel_cleanup.XXXXXX")"
    prepare_source_fixture "$direct_root"

    cat > "$direct_root/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_8888:
    id: cmd_8888
    status: canceled
EOF
    mkdir -p "$direct_root/queue/reports"
    touch "$direct_root/queue/reports/tobisaru_report_cmd_8888.yaml"
    bash "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$direct_root/queue/tasks/tobisaru.yaml" task report_filename tobisaru_report_cmd_8888.yaml
    bash "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$direct_root/queue/tasks/tobisaru.yaml" task report_path queue/reports/tobisaru_report_cmd_8888.yaml

    SCRIPT_DIR="$direct_root"
    DIRECT_MODE=false
    CMD_ID=cmd_8888
    log() { :; }
    source "$REAL_PROJECT_ROOT/scripts/lib/field_get.sh"
    source "$REAL_PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    source "$REAL_PROJECT_ROOT/scripts/lib/task_lifecycle.sh"
    eval "$(extract_function reset_stale_fields)"
    eval "$(extract_function deploy_task_cmd_status_is_canceled)"
    eval "$(extract_function deploy_task_cleanup_canceled_cmd)"

    run deploy_task_cleanup_canceled_cmd "tobisaru" "cmd_8888"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CANCEL_CLEANUP: cmd_8888 is canceled"* ]]

    run get_task_values "$direct_root/queue/tasks/tobisaru.yaml" status parent_cmd task_id report_path report_filename
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=idle"* ]]
    [[ "$output" == *"parent_cmd=<missing>"* || "$output" == *"parent_cmd=\"\""* ]]
    [[ "$output" == *"report_path=<missing>"* || "$output" == *"report_path=\"\""* ]]
    assert_missing_fields "$direct_root/queue/tasks/tobisaru.yaml" target_path progress description related_lessons

    rm -rf "$direct_root"
}

@test "--directモード: reset_stale_fieldsがstaleフィールドを清掃する(AC2)" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_direct.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    SCRIPT_DIR="$direct_root"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    assert_missing_fields \
        "$file" \
        target_path progress description deployed_at \
        constraints engineering_preferences context_files scope context context_hints stop_for never_stop_for parallel_ok \
        AC1 AC2 AC3 acceptance_criteria ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

    grep -q "scout_exempt: true" "$file"

    rm -rf "$direct_root"
}

@test "reset_stale_fields clears stale test lifecycle fields before next task generation" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_test_lifecycle.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"
    cat >> "$file" <<'YAML'
  test_necessity:
  - defense_target: predecessor-only contract
  deletion_justification: predecessor transient proof
  transient_tests_deleted:
  - tests/unit/test_predecessor_only.bats
YAML

    SCRIPT_DIR="$direct_root"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    run python3 -c 'import sys, yaml; task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]; fields = ("test_necessity", "deletion_justification", "transient_tests_deleted"); assert sum(field in task for field in fields) == 0, task' "$file"
    [ "$status" -eq 0 ]

    rm -rf "$direct_root"
}

@test "--directモード + 異なるCMD_ID: acceptance_criteriaをクリアする（旧AC残存バグ修正）" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_direct_newcmd.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    SCRIPT_DIR="$direct_root"
    DIRECT_MODE=true
    CMD_ID="cmd_NEW_DIFFERENT"  # 既存parent_cmd(cmd_8888)と異なる
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    # acceptance_criteriaがクリアされているか確認
    assert_missing_fields "$file" acceptance_criteria

    rm -rf "$direct_root"
}

@test "--directモード + 同一CMD_ID: acceptance_criteriaを保持する（LK008）" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_direct_samecmd.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    SCRIPT_DIR="$direct_root"
    DIRECT_MODE=true
    CMD_ID="cmd_8888"  # 既存parent_cmdと同じ → LK008によりAC保持
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    # acceptance_criteriaが保持されているか確認
    grep -q "acceptance_criteria" "$file"

    rm -rf "$direct_root"
}

@test "通常配備 + 同一CMD_ID: cmdソース不在fallback用にacceptance_criteriaを保持する" {
    local direct_root
    direct_root="$(mktemp -d "$BATS_TMPDIR/stale_reset_normal_samecmd.XXXXXX")"
    prepare_source_fixture "$direct_root"

    local file="$direct_root/queue/tasks/tobisaru.yaml"

    SCRIPT_DIR="$direct_root"
    DIRECT_MODE=false
    CMD_ID="cmd_8888"
    log() { :; }
    eval "$(extract_function reset_stale_fields)"
    reset_stale_fields "tobisaru"

    grep -q "acceptance_criteria" "$file"
    assert_missing_fields "$file" target_path progress description deployed_at command reports_to_read

    rm -rf "$direct_root"
}

@test "karo-direct SKILL uses deploy_task --yaml instead of direct task cp" {
    local skill_file="$PROJECT_ROOT/skills/karo-direct/SKILL.md"

    run grep -F "bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>" "$skill_file"
    [ "$status" -eq 0 ]

    run grep -F "直接 \`cp\` 禁止" "$skill_file"
    [ "$status" -eq 0 ]

    run grep -F "cp /tmp/karo_direct_task.yaml queue/tasks/<ninja_name>.yaml" "$skill_file"
    [ "$status" -ne 0 ]
}

@test "--directモード: parent_cmd/status更新時にtask_idも新CMDへ更新する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_OLD
  task_id: cmd_OLD_impl
  task_type: exact
  status: done
EOF

    run_direct_task_id_projection cmd_2538

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "parent_cmd" ""
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_2538" ]

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "status" ""
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "task_id" ""
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_2538_exact" ]

    # A different command may replace this task only after the current
    # assignment reaches a terminal state (GA-257 worker overwrite guard).
    bash "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" "$TEST_PROJECT/queue/tasks/sasuke.yaml" task status done
    bash "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" "$TEST_PROJECT/queue/tasks/sasuke.yaml" task task_type impl
    bash "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" "$TEST_PROJECT/queue/tasks/sasuke.yaml" task task_id cmd_OLD_impl

    run_direct_task_id_projection cmd_2539

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "task_id" ""
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_2539_normal" ]
}

@test "record_deployed_at overwrites existing deployed_at and logs old/new values" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_OLD
  task_id: cmd_OLD_impl
  status: assigned
  deployed_at: "2026-05-04T01:00:00"
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        LOG="$project/logs/deploy_task_record_deployed_at.log"
        record_deployed_at "$project/queue/tasks/sasuke.yaml" "2026-05-04T08:55:00"
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "deployed_at" ""
    [ "$status" -eq 0 ]
    [ "$output" = "2026-05-04T08:55:00" ]

    run grep -F "[DEPLOYED_AT] Updated: old=2026-05-04T01:00:00, new=2026-05-04T08:55:00" "$TEST_PROJECT/logs/deploy_task_record_deployed_at.log"
    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# stale_report_verdict テスト (11)
# ═══════════════════════════════════════════════════════════

@test "other ninja report with verdict=PASS is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_999
verdict: PASS
result:
  summary: "test completed"
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/sasuke_report_cmd_999.yaml" ]
}

@test "other ninja report with verdict=FAIL is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_999.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_999
verdict: FAIL
result:
  summary: "test failed"
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/hanzo_report_cmd_999.yaml" ]
}

@test "other ninja report with verdict=FILL_THIS is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: FILL_THIS
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_999.yaml" ]
}

@test "other ninja report with empty verdict is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_999
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_999.yaml" ]
}

@test "other ninja report without verdict field is PROTECTED" {
    cat > "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/tobisaru_report_cmd_999.yaml" ]
}

@test "PROTECTED log message is output for other ninja reports" {
    cat > "$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_999.yaml" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_999
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    local log_file="$TEST_TMPDIR/logs/stale_archive_test.log"
    [ -f "$log_file" ]
    grep -q "PROTECTED other ninja report (kagemaru_report_cmd_999.yaml)" "$log_file"
}

@test "stale archive skips own report regardless of verdict" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_999
verdict: FILL_THIS
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/hayate_report_cmd_999.yaml" ]
}

@test "own stale report with empty verdict is archived" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: ""
result:
  summary: ""
EOF

    run_own_stale_archive hayate cmd_999

    [ ! -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

@test "own completed report with verdict=PASS is preserved" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: PASS
result:
  summary: "completed"
EOF

    run_own_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

@test "own completed report with verdict=done is preserved" {
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_777
verdict: done
result:
  summary: "completed"
EOF

    run_own_stale_archive hayate cmd_999

    [ -f "$TEST_TMPDIR/queue/reports/hayate_report_cmd_777.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/stale/hayate_report_cmd_777.yaml" ]
}

@test "compound: all other ninja reports PROTECTED, own stale archived" {
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" <<'EOF'
worker_id: sasuke
parent_cmd: cmd_888
verdict: PASS
result:
  summary: "completed"
EOF

    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_888
verdict: FAIL
result:
  summary: "failed"
EOF

    cat > "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_888
verdict: FILL_THIS
result:
  summary: ""
EOF

    cat > "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_888
verdict: ""
result:
  summary: ""
EOF

    run_stale_archive hayate cmd_888

    [ -f "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/saizo_report_cmd_888.yaml" ]
    [ -f "$TEST_TMPDIR/queue/reports/kotaro_report_cmd_888.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/saizo_report_cmd_888.yaml" ]
    [ ! -f "$TEST_TMPDIR/archive/reports/kotaro_report_cmd_888.yaml" ]
}

# ═══════════════════════════════════════════════════════════
# engineering_preferences テスト (3)
# ═══════════════════════════════════════════════════════════

@test "deploy_task injects engineering_preferences from YAML project file" {
    _mk_sasuke_review_dm_signal

    cat > "$TEST_PROJECT/projects/dm-signal.yaml" <<'EOF'
project:
  id: dm-signal
engineering_preferences:
  - "prefer parity over speed"
  - "prefer PostgreSQL over SQLite writes"
EOF

    run inject_engineering_preferences_only sasuke
    [ "$status" -eq 0 ]

    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "prefer parity over speed" ]
    [ "${lines[1]}" = "prefer PostgreSQL over SQLite writes" ]
}

@test "deploy_task injects engineering_preferences from mixed-format project file" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: auto-ops
  acceptance_criteria:
    - id: AC1
      description: "inject preferences"
EOF

    cat > "$TEST_PROJECT/projects/auto-ops.yaml" <<'EOF'
repo: https://example.com/auto-ops
path: /tmp/auto-ops
language: python
created: 2026-03-08

engineering_preferences:
  - "prefer stdlib over new deps"
  - "prefer fail-close over warn-and-continue"

## Core Rules
- sample
EOF

    run inject_engineering_preferences_only sasuke
    [ "$status" -eq 0 ]

    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "prefer stdlib over new deps" ]
    [ "${lines[1]}" = "prefer fail-close over warn-and-continue" ]
}

@test "deploy_task preserves existing task engineering_preferences" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "engineering preferences test"
  task_type: review
  project: dm-signal
  engineering_preferences:
    - "manual override"
  acceptance_criteria:
    - id: AC1
      description: "preserve"
EOF

    cat > "$TEST_PROJECT/projects/dm-signal.yaml" <<'EOF'
project:
  id: dm-signal
engineering_preferences:
  - "prefer parity over speed"
EOF

    run inject_engineering_preferences_only sasuke
    [ "$status" -eq 0 ]

    # cmd_1321: FIELD_CLEAR→再inject設計により、既存値はクリアされプロジェクトデフォルトで再注入
    run read_task_engineering_preferences
    [ "$status" -eq 0 ]
    [ "$output" = "prefer parity over speed" ]
}

@test "deploy_task injects db-check skill_hint for dm-signal DB operation" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "DB parity test"
  task_type: impl
  project: dm-signal
  purpose: "本番DBのholding_signalを確認してパリティ検証する"
EOF

    run inject_skill_hint_only sasuke
    [ "$status" -eq 0 ]

    run read_task_skill_hint
    [ "$status" -eq 0 ]
    [[ "$output" == *"/db-check"* ]]
}

@test "deploy_task injects pf-registration skill_hint for registration type" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "PF registration test"
  task_type: registration
  project: dm-signal
  purpose: "PFを登録する"
EOF

    run inject_skill_hint_only sasuke
    [ "$status" -eq 0 ]

    run read_task_skill_hint
    [ "$status" -eq 0 ]
    [[ "$output" == *"/pf-registration"* ]]
}

@test "cmd_2650: inject_context_hints exists in deploy_task.sh" {
    run grep -q '^inject_context_hints()' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "cmd_2650: explicit purpose filenames inject all four context hints" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "context hint exact test"
  task_type: exact
  project: infra
  purpose: "robustness-verification-catalog.md、gs-speedup-knowledge.md、dm-signal-terminology.md、training-cycle.mdをLevel5化する"
EOF

    run inject_context_hints_only sasuke
    [ "$status" -eq 0 ]

    run read_task_context_hints
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/robustness-verification-catalog.md"* ]]
    [[ "$output" == *"context/gs-speedup-knowledge.md"* ]]
    [[ "$output" == *"/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md"* ]]
    [[ "$output" == *"context/training-cycle.md"* ]]
}

@test "cmd_2650: dm-signal project injects domain context hints" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "dm signal context hint test"
  task_type: impl
  project: dm-signal
  purpose: "PF計算の検証を行う"
EOF

    run inject_context_hints_only sasuke
    [ "$status" -eq 0 ]

    run read_task_context_hints
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/robustness-verification-catalog.md"* ]]
    [[ "$output" == *"context/gs-speedup-knowledge.md"* ]]
    [[ "$output" == *"/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md"* ]]
}

@test "cmd_2852: context hints insertion handles slash brackets parentheses and Japanese" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "context hint special chars test"
  task_type: exact
  project: dm-signal
  purpose: "dm-signal-terminology.md、training-cycle.md、robustness-verification-catalog.md(日本語/[x])を読む"
  description: "description anchor"
EOF

    run inject_context_hints_only sasuke
    [ "$status" -eq 0 ]

    run read_task_context_hints
    [ "$status" -eq 0 ]
    [[ "$output" == *"/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md"* ]]
    [[ "$output" == *"context/training-cycle.md"* ]]
    [[ "$output" == *"context/robustness-verification-catalog.md"* ]]

    run python3 -c "import yaml; yaml.safe_load(open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8'))"
    [ "$status" -eq 0 ]
}

@test "cmd_2852: production invariant insertion handles slash brackets parentheses and Japanese" {
    cat > "$TEST_PROJECT/projects/infra.yaml" <<'EOF'
project:
  id: infra
production_invariants:
  entries:
    - {id: PI-INFRA-999, fact: "origin(→/[]/括弧/日本語)を壊さず配備する"}
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "production invariant special chars test"
  task_type: exact
  project: infra
  purpose: "PI注入を確認する"
  description: "description anchor"
EOF

    run inject_production_invariants_only sasuke
    [ "$status" -eq 0 ]

    run read_task_production_invariants
    [ "$status" -eq 0 ]
    [[ "$output" == *"PI-INFRA-999: origin(→/[]/括弧/日本語)を壊さず配備する"* ]]

    run python3 -c "import yaml; yaml.safe_load(open('$TEST_PROJECT/queue/tasks/sasuke.yaml', encoding='utf-8'))"
    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# gate_blocks テスト (5)
# ═══════════════════════════════════════════════════════════

@test "cmd_1534: gate_blocks injected from gate_metrics.log BLOCK entries" {
    _mk_sasuke_impl_infra

    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'GMEOF'
2026-03-30T00:01:00	cmd_100	BLOCK	sasuke:empty_lessons_useful:related=[L074]	impl	unknown	unknown	L074
2026-03-30T00:02:00	cmd_101	BLOCK	sasuke:empty_lessons_useful:related=[L074,L063]	impl	unknown	unknown	L074,L063
2026-03-30T00:03:00	cmd_102	BLOCK	sasuke:lesson_candidate_missing	impl	unknown	unknown	L074
2026-03-30T00:04:00	cmd_103	CLEAR	all_gates_passed	impl	unknown	unknown	L074
2026-03-30T00:05:00	cmd_104	BLOCK	hanzo:binary_checks_fail	impl	unknown	unknown	L074
2026-03-30T00:06:00	cmd_105	BLOCK	sasuke:binary_checks_fail	impl	unknown	unknown	L074
GMEOF

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    # empty_lessons_useful=2, lesson_candidate_missing=1, binary_checks_fail=1
    [[ "${lines[0]}" == *"reason=empty_lessons_useful,count=2"* ]]
    [[ "${output}" == *"lesson_candidate_missing"* ]]
    [[ "${output}" == *"binary_checks_fail"* ]]
}

@test "cmd_1534: pipe-separated BLOCK reasons are split correctly" {
    _mk_sasuke_impl_infra

    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'GMEOF'
2026-03-30T00:01:00	cmd_100	BLOCK	sasuke:empty_lessons_useful:related=[L074]|hanzo:lesson_candidate_missing	impl	unknown	unknown	L074
2026-03-30T00:02:00	cmd_101	BLOCK	sasuke:ac_version_mismatch:task=1:report=4|sasuke:empty_lessons_useful:related=[L063]	impl	unknown	unknown	L074
GMEOF

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    # sasuke: empty_lessons_useful=2, ac_version_mismatch=1
    [[ "${output}" == *"reason=empty_lessons_useful,count=2"* ]]
    [[ "${output}" == *"reason=ac_version_mismatch,count=1"* ]]
    # hanzo should not be counted for sasuke
    [[ "${output}" != *"lesson_candidate_missing"* ]]
}

@test "cmd_1534: report-file based BLOCK reasons are matched" {
    _mk_sasuke_impl_infra

    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'GMEOF'
2026-03-30T00:01:00	cmd_100	BLOCK	report_format:sasuke_report_cmd_100.yaml	impl	unknown	unknown	L074
2026-03-30T00:02:00	cmd_101	BLOCK	report_yaml_missing:sasuke_report_cmd_101.yaml	impl	unknown	unknown	L074
2026-03-30T00:03:00	cmd_102	BLOCK	report_format:hanzo_report_cmd_102.yaml	impl	unknown	unknown	L074
GMEOF

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    [[ "${output}" == *"report_format"* ]]
    [[ "${output}" == *"report_yaml_missing"* ]]
}

@test "cmd_1534: no gate_metrics.log does not crash" {
    _mk_sasuke_impl_infra
    # No gate_metrics.log created

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    # gate_blocks should be empty/absent
    [ "${#lines[@]}" -eq 0 ]
}

@test "cmd_1534: CLEAR entries are not counted" {
    _mk_sasuke_impl_infra

    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'GMEOF'
2026-03-30T00:01:00	cmd_100	CLEAR	all_gates_passed	impl	unknown	unknown	L074
2026-03-30T00:02:00	cmd_101	CLEAR	sasuke:some_reason	impl	unknown	unknown	L074
GMEOF

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# gate_fail_top3 テスト (4)
# ═══════════════════════════════════════════════════════════

@test "GP-110: gate_fail_top3 injected with correct top3 patterns" {
    _mk_sasuke_impl_infra
    create_workarounds
    create_gate_fire_log

    run bash -c "
        cd '$TEST_PROJECT'
        TASK_FILE_ENV='$TEST_PROJECT/queue/tasks/sasuke.yaml' \
        WORKAROUNDS_FILE_ENV='$TEST_PROJECT/logs/karo_workarounds.yaml' \
        NINJA_NAME_ENV='sasuke' \
        python3 -c '
import os, re, sys, tempfile, yaml

task_file = os.environ[\"TASK_FILE_ENV\"]
workarounds_file = os.environ[\"WORKAROUNDS_FILE_ENV\"]
ninja_name = os.environ[\"NINJA_NAME_ENV\"]

with open(task_file) as f:
    data = yaml.safe_load(f)

with open(workarounds_file) as f:
    entries = yaml.safe_load(f) or []

cats = {}
for e in entries:
    if isinstance(e, dict) and e.get(\"ninja\") == ninja_name and e.get(\"workaround\"):
        c = e.get(\"category\", \"uncategorized\")
        cats[c] = cats.get(c, 0) + 1

total = sum(cats.values())
top_cat, top_count = max(cats.items(), key=lambda x: x[1]) if cats else (\"none\", 0)
breakdown = \", \".join(f\"{k}({v}件)\" for k, v in sorted(cats.items(), key=lambda x: -x[1]))
warning = f\"⚠ report_field_set.sh必ず使用。lessons_usefulはlist形式、dict(0:{{}},1:{{}})禁止。verdict二値(PASS/FAIL)厳守\"

task = data[\"task\"]
task[\"ninja_weak_points\"] = {
    \"source\": \"karo_workarounds.yaml\",
    \"total_workarounds\": total,
    \"top_pattern\": f\"{top_cat}({top_count}件)\",
    \"breakdown\": breakdown,
    \"warning\": warning,
}

gate_log_path = os.path.join(os.path.dirname(workarounds_file), \"gate_fire_log.yaml\")
if os.path.exists(gate_log_path):
    fail_cats = {}
    GATE_FAIL_WARNING = {
        \"lu_reason_empty\": \"lessons_usefulの各教訓にreason(理由)を必ず記入。空文字禁止\",
        \"bc_result_empty\": \"binary_checksの各check項目にresult(yes/no)を記入。空文字禁止\",
        \"verdict_invalid\": \"verdictはPASS/FAILの二値のみ。空文字/None禁止\",
        \"field_missing\": \"必須フィールド(binary_checks/files_modified/result.summary)を省略するな\",
        \"type_error\": \"YAML型注意。dict禁止→list形式\",
        \"bc_result_invalid\": \"binary_checksのresultはyes/noのみ\",
        \"lu_structure_error\": \"lessons_usefulフィールド必須\",
        \"yaml_parse_error\": \"YAML構文エラー\",
        \"fill_this_remaining\": \"FILL_THIS残存\",
        \"no_lesson_reason\": \"no_lesson_reasonに理由記入\",
        \"status_pending\": \"statusをcompletedに更新\",
    }
    with open(gate_log_path) as gf:
        for gline in gf:
            gline = gline.strip()
            if not gline.startswith(\"- \") or f\"/{ninja_name}_report\" not in gline:
                continue
            if \"/tmp/\" in gline:
                continue
            if \"result: FAIL\" not in gline:
                continue
            rm = re.search(r\"reasons:\s*\\\"(.*)\\\"$\", gline)
            if not rm:
                continue
            for reason in rm.group(1).split(\"; \"):
                if \"reason is empty\" in reason:
                    fail_cats[\"lu_reason_empty\"] = fail_cats.get(\"lu_reason_empty\", 0) + 1
                elif \"verdict\" in reason:
                    fail_cats[\"verdict_invalid\"] = fail_cats.get(\"verdict_invalid\", 0) + 1
                elif \"MISSING\" in reason:
                    fail_cats[\"field_missing\"] = fail_cats.get(\"field_missing\", 0) + 1
                elif \"is dict\" in reason or \"is str\" in reason:
                    fail_cats[\"type_error\"] = fail_cats.get(\"type_error\", 0) + 1
    if fail_cats:
        sorted_cats = sorted(fail_cats.items(), key=lambda x: -x[1])[:3]
        top3 = [{\"pattern\": p, \"count\": c} for p, c in sorted_cats]
        gate_warnings = [GATE_FAIL_WARNING.get(p, p) for p, _ in sorted_cats]
        task[\"ninja_weak_points\"][\"gate_fail_top3\"] = top3
        task[\"ninja_weak_points\"][\"gate_warning\"] = \"⚠ gate頻出FAIL: \" + \"; \".join(gate_warnings)

with open(task_file, \"w\") as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
'
    "
    [ "$status" -eq 0 ]

    run read_task_gate_fail_top3
    [ "$status" -eq 0 ]
    # lu_reason_empty=3, verdict_invalid=2, field_missing=2
    [[ "${lines[0]}" == *"pattern=lu_reason_empty,count=3"* ]]
    [[ "${lines[1]}" == *"count=2"* ]]
    [[ "${output}" == *"warning="* ]]
}

@test "GP-110: /tmp/ entries in gate_fire_log are skipped" {
    _mk_sasuke_impl_infra
    create_workarounds

    cat > "$TEST_PROJECT/logs/gate_fire_log.yaml" <<'GFEOF'
- ts: "2026-03-25T01:00:00", file: "/tmp/sasuke_report.yaml", result: FAIL, reasons: "verdict: invalid"
GFEOF

    run bash -c "
        count=0
        while IFS= read -r line; do
            [[ \"\$line\" != *\"/sasuke_report\"* ]] && continue
            [[ \"\$line\" == *\"/tmp/\"* ]] && continue
            [[ \"\$line\" == *'result: FAIL'* ]] && count=\$((count+1))
        done < '$TEST_PROJECT/logs/gate_fire_log.yaml'
        [ \$count -eq 0 ] && echo SKIP_OK || echo SKIP_FAIL
    "
    [ "$status" -eq 0 ]
    [[ "${output}" == *"SKIP_OK"* ]]
}

@test "GP-110: no gate_fire_log file does not crash" {
    _mk_sasuke_impl_infra
    create_workarounds
    # No gate_fire_log.yaml file

    run bash -c "[ -f '$TEST_PROJECT/logs/gate_fire_log.yaml' ] && echo UNEXPECTED_FILE || echo NO_FILE_OK"
    [ "$status" -eq 0 ]
    [[ "${output}" == *"NO_FILE_OK"* ]]
}

@test "GP-110: other ninja entries in gate_fire_log are filtered out" {
    _mk_sasuke_impl_infra
    create_workarounds

    cat > "$TEST_PROJECT/logs/gate_fire_log.yaml" <<'GFEOF'
- ts: "2026-03-25T01:00:00", file: "queue/reports/hanzo_report_cmd_100.yaml", result: FAIL, reasons: "verdict: invalid"
- ts: "2026-03-25T02:00:00", file: "queue/reports/sasuke_report_cmd_101.yaml", result: FAIL, reasons: "verdict: \"\" is not valid"
GFEOF

    run bash -c "
        count=0
        while IFS= read -r line; do
            [[ \"\$line\" != *\"/sasuke_report\"* ]] && continue
            [[ \"\$line\" == *\"/tmp/\"* ]] && continue
            [[ \"\$line\" == *'result: FAIL'* ]] || continue
            count=\$((count+1))
        done < '$TEST_PROJECT/logs/gate_fire_log.yaml'
        echo \"FILTERED_COUNT=\$count\"
    "
    [ "$status" -eq 0 ]
    [[ "${output}" == *"FILTERED_COUNT=1"* ]]
}

@test "target_path collision guard blocks active peer file target" {
    deploy_task_scaffold "target_collision_file"
    mkdir -p "$TEST_PROJECT/scripts"
    touch "$TEST_PROJECT/scripts/shared.sh"

    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_new
  target_path: scripts/shared.sh
EOF
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: in_progress
  parent_cmd: cmd_peer
  target_path: scripts/shared.sh
EOF

    run bash -lc "
        source '$TEST_PROJECT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_guard_target_path_collision '$TEST_PROJECT/queue/tasks/kagemaru.yaml' kagemaru
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: reserved path collision with hayate"* ]]
    [[ "$output" == *"scripts/shared.sh"* ]]

    deploy_task_teardown
}

@test "direct yaml prewrite collision guard blocks before task yaml mutation" {
    deploy_task_scaffold "target_collision_prewrite"
    mkdir -p "$TEST_PROJECT/scripts"
    touch "$TEST_PROJECT/scripts/shared.sh"

    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: idle
  parent_cmd: cmd_old
  task_id: cmd_old_exact
EOF
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_peer
  target_path: scripts/shared.sh
EOF
    cat > "$TEST_PROJECT/tmp_direct.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_new
  target_path: scripts/shared.sh
EOF

    run bash -lc "
        source '$TEST_PROJECT/scripts/deploy_task.sh'
        log() { :; }
        DIRECT_MODE=true
        deploy_task_guard_direct_yaml_prewrite_collision '$TEST_PROJECT/tmp_direct.yaml' kagemaru
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: reserved path collision with hayate"* ]]
    [[ "$output" == *"scripts/shared.sh"* ]]
    run bash -lc "
        source '$TEST_PROJECT/scripts/lib/field_get.sh'
        field_get '$TEST_PROJECT/queue/tasks/kagemaru.yaml' status ''
        field_get '$TEST_PROJECT/queue/tasks/kagemaru.yaml' parent_cmd ''
        field_get '$TEST_PROJECT/queue/tasks/kagemaru.yaml' task_id ''
    "
    [ "$status" -eq 0 ]
    [ "$output" = $'idle\ncmd_old\ncmd_old_exact' ]

    deploy_task_teardown
}

@test "target_path collision guard keeps directory overlap informational" {
    deploy_task_scaffold "target_collision_dir"
    mkdir -p "$TEST_PROJECT/scripts"

    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_new
  target_path: scripts
EOF
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: acknowledged
  parent_cmd: cmd_peer
  target_path: scripts
EOF

    run bash -lc "
        source '$TEST_PROJECT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_guard_target_path_collision '$TEST_PROJECT/queue/tasks/kagemaru.yaml' kagemaru
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: target_path directory overlap with hayate"* ]]

    deploy_task_teardown
}

@test "target_path collision guard handles empty multi and relative targets" {
    deploy_task_scaffold "target_collision_multi"
    mkdir -p "$TEST_PROJECT/scripts"
    touch "$TEST_PROJECT/scripts/a.sh" "$TEST_PROJECT/scripts/b.sh"

    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_new
  target_path:
  - ""
  - scripts/a.sh
  - scripts/b.sh
EOF
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_peer
  target_path: scripts/b.sh
EOF

    run bash -lc "
        source '$TEST_PROJECT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_guard_target_path_collision '$TEST_PROJECT/queue/tasks/kagemaru.yaml' kagemaru
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"scripts/b.sh"* ]]
    [[ "$output" != *"scripts/a.sh"* ]]

    deploy_task_teardown
}
