#!/usr/bin/env bats
# test_deploy_task_gate_blocks.bats - cmd_1534: gate_metrics.log BLOCK pattern injection

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_gate_blocks"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "gate blocks test"
  task_type: impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "test task"
EOF

    cat > "$TEST_PROJECT/logs/karo_workarounds.yaml" <<'WAEOF'
- cmd_id: cmd_100
  ninja: sasuke
  workaround: true
  category: report_yaml_format
  detail: test wa
WAEOF
}

teardown() {
    deploy_task_teardown
}

read_gate_blocks() {
    python3 - <<'PY'
import os
import yaml

task_file = os.path.join(os.environ['TEST_PROJECT'], 'queue', 'tasks', 'sasuke.yaml')
with open(task_file, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

nwp = (data.get('task') or {}).get('ninja_weak_points') or {}
blocks = nwp.get('gate_blocks') or []

for item in blocks:
    print(f"reason={item['reason']},count={item['count']}")
PY
}

# Inline Python that mirrors the gate_metrics.log parsing from deploy_task.sh
run_gate_blocks_inject() {
    local ninja_name="$1"
    run bash -c "
        cd '$TEST_PROJECT'
        python3 -c '
import os, re, sys, yaml, tempfile

task_file = \"$TEST_PROJECT/queue/tasks/sasuke.yaml\"
ninja_name = \"$ninja_name\"
logs_dir = \"$TEST_PROJECT/logs\"

with open(task_file) as f:
    data = yaml.safe_load(f)

task = data[\"task\"]
task[\"ninja_weak_points\"] = {\"source\": \"test\", \"total_workarounds\": 1}

gate_metrics_path = os.path.join(logs_dir, \"gate_metrics.log\")
if os.path.exists(gate_metrics_path):
    NINJA_NAMES = {\"kagemaru\", \"hanzo\", \"hayate\", \"tobisaru\", \"saizo\", \"kotaro\", \"sasuke\", \"kirimaru\"}
    BLOCK_HINT_MAP = {
        \"empty_lessons_useful\": \"lessons_usefulの各教訓にuseful(true/false)+reason(理由)を記入。空のまま提出禁止\",
        \"lesson_done_source\": \"lesson_candidate登録後にlesson_done確認が必要。lesson_write.sh経由で正式登録\",
        \"lesson_candidate_missing\": \"lesson_candidate.found欄を必ず記入(true/false)。省略禁止\",
        \"binary_checks_fail\": \"binary_checksのresultがyesでない項目あり。全ACのチェック完了を確認\",
        \"ac_version_mismatch\": \"ac_version_readがtask YAMLのac_versionと不一致。最新タスクを再読込\",
        \"report_format\": \"report YAMLのフォーマットエラー。report_field_set.sh使用必須\",
        \"report_yaml_missing\": \"report YAMLが存在しない。report_pathのファイルを作成・記入せよ\",
    }
    block_cats = {}
    with open(gate_metrics_path, encoding=\"utf-8\") as gmf:
        for line in gmf:
            cols = line.rstrip(\"\\n\").split(\"\\t\")
            if len(cols) < 4 or cols[2] != \"BLOCK\":
                continue
            reasons = cols[3].split(\"|\")
            for reason in reasons:
                reason = reason.strip()
                matched_ninja = False
                for nn in NINJA_NAMES:
                    if reason.startswith(nn + \":\"):
                        if nn == ninja_name:
                            rest = reason[len(nn)+1:]
                            cat = re.split(r\"[:=]\", rest)[0]
                            if cat:
                                block_cats[cat] = block_cats.get(cat, 0) + 1
                        matched_ninja = True
                        break
                if matched_ninja:
                    continue
                if f\":{ninja_name}_report\" in reason or f\"_{ninja_name}_report\" in reason or f\"/{ninja_name}_report\" in reason:
                    cat = reason.split(\":\")[0] if \":\" in reason else \"report_issue\"
                    block_cats[cat] = block_cats.get(cat, 0) + 1
    if block_cats:
        sorted_blocks = sorted(block_cats.items(), key=lambda x: -x[1])
        gate_blocks = [
            {\"reason\": cat, \"count\": cnt, \"hint\": BLOCK_HINT_MAP.get(cat, f\"gate BLOCK: {cat}\")}
            for cat, cnt in sorted_blocks
        ]
        task[\"ninja_weak_points\"][\"gate_blocks\"] = gate_blocks
        print(f\"INJECTED {len(gate_blocks)} categories\", file=sys.stderr)

with open(task_file, \"w\") as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
'
    " 2>&1
}

@test "cmd_1534: gate_blocks injected from gate_metrics.log BLOCK entries" {
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
    # No gate_metrics.log created

    run_gate_blocks_inject sasuke
    [ "$status" -eq 0 ] || { echo "inject failed: $output"; false; }

    run read_gate_blocks
    [ "$status" -eq 0 ]
    # gate_blocks should be empty/absent
    [ "${#lines[@]}" -eq 0 ]
}

@test "cmd_1534: CLEAR entries are not counted" {
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
