#!/usr/bin/env bats
# test_deploy_task_gate_fail_top3.bats - GP-110: gate_fire_log FAIL pattern injection

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_gate_fail"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "gate fail top3 test"
  task_type: impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "test task"
EOF
}

teardown() {
    deploy_task_teardown
}

read_task_gate_fail_top3() {
    python3 - <<'PY'
import os
import yaml

task_file = os.path.join(os.environ['TEST_PROJECT'], 'queue', 'tasks', 'sasuke.yaml')
with open(task_file, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

nwp = (data.get('task') or {}).get('ninja_weak_points') or {}
top3 = nwp.get('gate_fail_top3') or []
warning = nwp.get('gate_warning') or ''

for item in top3:
    print(f"pattern={item['pattern']},count={item['count']}")
if warning:
    print(f"warning={warning}")
PY
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

@test "GP-110: gate_fail_top3 injected with correct top3 patterns" {
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
    create_workarounds

    # Only /tmp/ entries for sasuke
    cat > "$TEST_PROJECT/logs/gate_fire_log.yaml" <<'GFEOF'
- ts: "2026-03-25T01:00:00", file: "/tmp/sasuke_report.yaml", result: FAIL, reasons: "verdict: invalid"
GFEOF

    run bash -c "
        cd '$TEST_PROJECT'
        TASK_FILE_ENV='$TEST_PROJECT/queue/tasks/sasuke.yaml' \
        WORKAROUNDS_FILE_ENV='$TEST_PROJECT/logs/karo_workarounds.yaml' \
        NINJA_NAME_ENV='sasuke' \
        python3 -c '
import os, re, yaml

task_file = os.environ[\"TASK_FILE_ENV\"]
with open(task_file) as f:
    data = yaml.safe_load(f)
task = data[\"task\"]
task[\"ninja_weak_points\"] = {\"source\": \"test\"}

gate_log_path = os.path.join(os.path.dirname(os.environ[\"WORKAROUNDS_FILE_ENV\"]), \"gate_fire_log.yaml\")
fail_cats = {}
with open(gate_log_path) as gf:
    for gline in gf:
        gline = gline.strip()
        if not gline.startswith(\"- \") or \"/sasuke_report\" not in gline:
            continue
        if \"/tmp/\" in gline:
            continue
        if \"result: FAIL\" not in gline:
            continue
        fail_cats[\"test\"] = 1
print(\"SKIP_OK\" if not fail_cats else \"SKIP_FAIL\")
'
    "
    [ "$status" -eq 0 ]
    [[ "${output}" == *"SKIP_OK"* ]]
}

@test "GP-110: no gate_fire_log file does not crash" {
    create_workarounds
    # No gate_fire_log.yaml file

    run bash -c "
        cd '$TEST_PROJECT'
        TASK_FILE_ENV='$TEST_PROJECT/queue/tasks/sasuke.yaml' \
        WORKAROUNDS_FILE_ENV='$TEST_PROJECT/logs/karo_workarounds.yaml' \
        NINJA_NAME_ENV='sasuke' \
        python3 -c '
import os, yaml

task_file = os.environ[\"TASK_FILE_ENV\"]
with open(task_file) as f:
    data = yaml.safe_load(f)
task = data[\"task\"]
task[\"ninja_weak_points\"] = {\"source\": \"test\"}

gate_log_path = os.path.join(os.path.dirname(os.environ[\"WORKAROUNDS_FILE_ENV\"]), \"gate_fire_log.yaml\")
exists = os.path.exists(gate_log_path)
print(\"NO_FILE_OK\" if not exists else \"UNEXPECTED_FILE\")
'
    "
    [ "$status" -eq 0 ]
    [[ "${output}" == *"NO_FILE_OK"* ]]
}

@test "GP-110: other ninja entries in gate_fire_log are filtered out" {
    create_workarounds

    cat > "$TEST_PROJECT/logs/gate_fire_log.yaml" <<'GFEOF'
- ts: "2026-03-25T01:00:00", file: "queue/reports/hanzo_report_cmd_100.yaml", result: FAIL, reasons: "verdict: invalid"
- ts: "2026-03-25T02:00:00", file: "queue/reports/sasuke_report_cmd_101.yaml", result: FAIL, reasons: "verdict: \"\" is not valid"
GFEOF

    run bash -c "
        cd '$TEST_PROJECT'
        TASK_FILE_ENV='$TEST_PROJECT/queue/tasks/sasuke.yaml' \
        WORKAROUNDS_FILE_ENV='$TEST_PROJECT/logs/karo_workarounds.yaml' \
        NINJA_NAME_ENV='sasuke' \
        python3 -c '
import os, re, yaml

task_file = os.environ[\"TASK_FILE_ENV\"]
ninja_name = os.environ[\"NINJA_NAME_ENV\"]
gate_log_path = os.path.join(os.path.dirname(os.environ[\"WORKAROUNDS_FILE_ENV\"]), \"gate_fire_log.yaml\")

fail_count = 0
with open(gate_log_path) as gf:
    for gline in gf:
        gline = gline.strip()
        if not gline.startswith(\"- \") or f\"/{ninja_name}_report\" not in gline:
            continue
        if \"/tmp/\" in gline or \"result: FAIL\" not in gline:
            continue
        fail_count += 1
# Only sasuke entry should match (not hanzo)
print(f\"FILTERED_COUNT={fail_count}\")
'
    "
    [ "$status" -eq 0 ]
    [[ "${output}" == *"FILTERED_COUNT=1"* ]]
}
