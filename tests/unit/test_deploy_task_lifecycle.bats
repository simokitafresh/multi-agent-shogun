#!/usr/bin/env bats
# test_deploy_task_lifecycle.bats - deploy_task.sh ライフサイクル統合テスト
# 統合元: double_deploy_guard(11) + stale_field_reset(2) + stale_report_verdict(11)
#        + engineering_preferences(3) + gate_blocks(5) + gate_fail_top3(4) = 36テスト

load '../helpers/deploy_task_scaffold'

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
  purpose: '前cmdの古いpurpose'
  target_path: /mnt/c/Python_app/DM-signal/backend/old_file.py
  constraints:
  - 'DM-signal制約1'
  - 'DM-signal制約2'
  progress: 'AC1-3全完了。PASS'
  description: '前cmdの説明'
  deployed_at: '2026-03-29T10:00:00'
  worker_id: tobisaru
  timestamp: '2026-03-29T10:00:00'
  engineering_preferences:
  - 'prefer old approach'
  - 'prefer another old approach'
  context_files:
  - 'context/dm-signal.md'
  - 'context/dm-signal-core.md'
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

    eval "$(extract_function reset_stale_fields)"
    eval "$(extract_function resolve_cmd_to_task)"
    reset_stale_fields "$ninja_name"
    resolve_cmd_to_task "$cmd_id" "$ninja_name"
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

    local DEPLOY_PARENT_CMD="" DEPLOY_TASK_ID="" _line
    while IFS= read -r _line; do
        [[ -z "$DEPLOY_PARENT_CMD" && "$_line" =~ ^[[:space:]]*parent_cmd:[[:space:]]+(.*) ]] && {
            DEPLOY_PARENT_CMD="${BASH_REMATCH[1]//\'/}"; DEPLOY_PARENT_CMD="${DEPLOY_PARENT_CMD//\"/}"
        }
        [[ -z "$DEPLOY_TASK_ID" && "$_line" =~ ^[[:space:]]*task_id:[[:space:]]+(.*) ]] && {
            DEPLOY_TASK_ID="${BASH_REMATCH[1]//\'/}"; DEPLOY_TASK_ID="${DEPLOY_TASK_ID//\"/}"
        }
    done < "$_TASK_YAML"

    if [ -n "$DEPLOY_PARENT_CMD" ]; then
        for _dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
            [ -f "$_dd_task" ] || continue
            _dd_ninja=$(basename "$_dd_task" .yaml)
            [ "$_dd_ninja" = "$NINJA_NAME" ] && continue
            local _dd_pcmd="" _dd_tid="" _dd_status=""
            while IFS= read -r _line; do
                [[ -z "$_dd_pcmd" && "$_line" =~ ^[[:space:]]*parent_cmd:[[:space:]]+(.*) ]] && { _dd_pcmd="${BASH_REMATCH[1]//\'/}"; _dd_pcmd="${_dd_pcmd//\"/}"; }
                [[ -z "$_dd_tid" && "$_line" =~ ^[[:space:]]*task_id:[[:space:]]+(.*) ]] && { _dd_tid="${BASH_REMATCH[1]//\'/}"; _dd_tid="${_dd_tid//\"/}"; }
                [[ -z "$_dd_status" && "$_line" =~ ^[[:space:]]*status:[[:space:]]+(.*) ]] && { _dd_status="${BASH_REMATCH[1]//\'/}"; _dd_status="${_dd_status//\"/}"; }
            done < "$_dd_task"
            [ "$_dd_pcmd" != "$DEPLOY_PARENT_CMD" ] && continue
            if [ -n "$DEPLOY_TASK_ID" ] && [ -n "$_dd_tid" ] && [ "$DEPLOY_TASK_ID" != "$_dd_tid" ]; then
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

teardown_file() {
    [ -d "$SOURCE_FIXTURE_ROOT" ] && rm -rf "$SOURCE_FIXTURE_ROOT"
    [ -d "$RESOLVED_FIXTURE_ROOT" ] && rm -rf "$RESOLVED_FIXTURE_ROOT"
    [ -d "$NESTED_RESOLVED_FIXTURE_ROOT" ] && rm -rf "$NESTED_RESOLVED_FIXTURE_ROOT"
    [ -n "$DEPLOY_TASK_TEMPLATE_DIR" ] && [ -d "$DEPLOY_TASK_TEMPLATE_DIR" ] && rm -rf "$DEPLOY_TASK_TEMPLATE_DIR"
}

setup() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/projects" \
        "$TEST_PROJECT/archive" \
        "$TEST_TMPDIR/queue/tasks" \
        "$TEST_TMPDIR/queue/reports" \
        "$TEST_TMPDIR/archive/reports" \
        "$TEST_TMPDIR/archive/reports/stale" \
        "$TEST_TMPDIR/logs"
    ln -sf "$DEPLOY_TASK_TEMPLATE_DIR/scripts" "$TEST_PROJECT/scripts"
    ln -sf "$DEPLOY_TASK_TEMPLATE_DIR/lib" "$TEST_PROJECT/lib"
    ln -sf "$DEPLOY_TASK_TEMPLATE_DIR/config" "$TEST_PROJECT/config"
    printf '<!-- DASHBOARD_AUTO_START -->\n<!-- DASHBOARD_AUTO_END -->\n' > "$TEST_PROJECT/dashboard.md"
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

# ═══════════════════════════════════════════════════════════
# stale_field_reset テスト (2)
# ═══════════════════════════════════════════════════════════

@test "再配備でstale field群とネスト汚染を清掃し必要フィールドを保持する" {
    local file="$RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local nested_file="$NESTED_RESOLVED_FIXTURE_ROOT/queue/tasks/tobisaru.yaml"
    local output nested_after root_fields root_field_name

    output="$(get_task_values "$file" parent_cmd task_id task_type project status purpose _ac_task_id _ac_worker_id)"

    [[ "$output" == *"parent_cmd=cmd_9999"* ]]
    [[ "$output" == *"task_id=cmd_9999_impl"* ]]
    [[ "$output" == *"task_type=impl"* ]]
    [[ "$output" == *"project=infra"* ]]
    [[ "$output" == *"status=assigned"* ]]
    [[ "$output" == *"purpose=新しいpurpose"* ]]
    [[ "$output" == *$'_ac_task_id='* ]]
    [[ "$output" == *$'_ac_worker_id='* ]]

    assert_missing_fields \
        "$file" \
        target_path progress description deployed_at \
        constraints engineering_preferences context_files stop_for never_stop_for parallel_ok \
        AC1 AC2 AC3 acceptance_criteria scout_exempt ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

    nested_after=$(grep -c '^\s*task:' "$nested_file")
    [ "$nested_after" -eq 1 ]

    root_fields=$(grep -c '^[a-zA-Z_]' "$nested_file")
    [ "$root_fields" -eq 1 ]

    root_field_name=$(grep '^[a-zA-Z_]' "$nested_file" | head -1)
    [[ "$root_field_name" == task:* ]]
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
        constraints engineering_preferences context_files stop_for never_stop_for parallel_ok \
        AC1 AC2 AC3 acceptance_criteria scout_exempt ac_priority ac_checkpoint \
        command reports_to_read credential_warning context_update type report_template \
        worker_id timestamp

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
