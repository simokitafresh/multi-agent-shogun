#!/usr/bin/env bats

# test_necessity: parallel --yaml deployments must keep task/report/lesson postcondition identity isolated per cmd+ninja+generation; a shared marker can attribute one ninja's lessons and task_id to another deployment.
@test "parallel --yaml lesson postconditions keep task report and lesson identity isolated" {
    root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    fixture="$(mktemp -d "$BATS_TMPDIR/deploy_postcond_isolation.XXXXXX")"
    mkdir -p "$fixture/queue/tasks" "$fixture/queue/reports" "$fixture/queue/inbox" \
        "$fixture/logs" "$fixture/results"

    run python3 - "$root/scripts/deploy_task.sh" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'POSTCOND_FILE_ENV="$DEPLOY_TASK_POSTCOND_FILE"' in source
assert "postcond_file = os.environ['POSTCOND_FILE_ENV']" in source
assert "with open(postcond_file, 'w')" in source
assert 'pc_file="$DEPLOY_TASK_POSTCOND_FILE"' in source
assert 'pc_file="$SCRIPT_DIR/queue/tasks/.postcond_lesson_inject"' not in source
PY
    [ "$status" -eq 0 ]

    cat > "$fixture/kagemaru.source.yaml" <<'YAML'
task:
  status: assigned
  parent_cmd: cmd_parallel_kagemaru
  task_id: task_parallel_kagemaru
  project: alpha
  report_path: queue/reports/kagemaru_report_cmd_parallel_kagemaru.yaml
YAML
    cat > "$fixture/saizo.source.yaml" <<'YAML'
task:
  status: assigned
  parent_cmd: cmd_parallel_saizo
  task_id: task_parallel_saizo
  project: beta
  report_path: queue/reports/saizo_report_cmd_parallel_saizo.yaml
YAML
    printf 'worker_id: kagemaru\nparent_cmd: cmd_parallel_kagemaru\n' \
        > "$fixture/queue/reports/kagemaru_report_cmd_parallel_kagemaru.yaml"
    printf 'worker_id: saizo\nparent_cmd: cmd_parallel_saizo\n' \
        > "$fixture/queue/reports/saizo_report_cmd_parallel_saizo.yaml"

    run_lane() (
        set -euo pipefail
        local ninja="$1" source_yaml="$2" lesson_id="$3" project="$4" other_ready="$5"
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090
        source "$root/scripts/deploy_task.sh"
        SCRIPT_DIR="$fixture"
        LOG="$fixture/logs/${ninja}.log"
        log() { printf '%s\n' "$*" >> "$LOG"; }

        # Exercise the public parallel deployment argument contract before the
        # isolated producer/consumer boundary.
        parse_deploy_task_args --yaml "$source_yaml" "$ninja"
        local task_file="$fixture/queue/tasks/${ninja}.yaml"
        cp "$source_yaml" "$task_file"
        DEPLOY_TASK_STARTED_US="${EPOCHREALTIME/./}"
        deploy_task_postcondition_prepare "$task_file"
        printf '%s\n' "$DEPLOY_TASK_POSTCOND_FILE" > "$fixture/results/${ninja}.path"
        {
            printf 'available=1\n'
            printf 'injected=1\n'
            printf 'task_id=task_parallel_%s\n' "$ninja"
            printf 'project=%s\n' "$project"
            printf 'injected_ids=%s\n' "$lesson_id"
        } > "$DEPLOY_TASK_POSTCOND_FILE"
        : > "$fixture/results/${ninja}.ready"

        local spins=0
        while [ ! -f "$fixture/results/${other_ready}.ready" ]; do
            spins=$((spins + 1))
            [ "$spins" -lt 500 ] || return 70
            sleep 0.01
        done
        local inj_project inj_ids
        inj_project=$(grep '^project=' "$DEPLOY_TASK_POSTCOND_FILE" | cut -d= -f2)
        inj_ids=$(grep '^injected_ids=' "$DEPLOY_TASK_POSTCOND_FILE" | cut -d= -f2)
        deploy_task_queue_lesson_scores "$task_file" "$inj_project" "$inj_ids"
        deploy_task_queue_lesson_scores "$task_file" infra "$inj_ids"
        postcondition_lesson_inject "$task_file"
    )

    run_lane kagemaru "$fixture/kagemaru.source.yaml" L_KAGEMARU alpha saizo &
    kagemaru_pid=$!
    run_lane saizo "$fixture/saizo.source.yaml" L_SAIZO beta kagemaru &
    saizo_pid=$!
    wait "$kagemaru_pid"
    wait "$saizo_pid"

    kagemaru_path="$(<"$fixture/results/kagemaru.path")"
    saizo_path="$(<"$fixture/results/saizo.path")"
    [ "$kagemaru_path" != "$saizo_path" ]
    [[ "$kagemaru_path" == *'.postcond_lesson_inject.kagemaru.kagemaru.cmd_parallel_kagemaru.'* ]]
    [[ "$saizo_path" == *'.postcond_lesson_inject.saizo.saizo.cmd_parallel_saizo.'* ]]
    [ "$(find "$fixture/queue/tasks" -maxdepth 1 -name '.postcond_lesson_inject*' | wc -l)" -eq 0 ]

    run grep -F 'task=task_parallel_kagemaru' "$fixture/logs/kagemaru.log"
    [ "$status" -eq 0 ]
    run grep -F 'task_parallel_saizo' "$fixture/logs/kagemaru.log"
    [ "$status" -ne 0 ]
    run grep -F 'task=task_parallel_saizo' "$fixture/logs/saizo.log"
    [ "$status" -eq 0 ]
    run grep -F 'task_parallel_kagemaru' "$fixture/logs/saizo.log"
    [ "$status" -ne 0 ]

    queue="$fixture/queue/deferred/lesson_scores.tsv"
    [ "$(awk -F '\t' '$3=="alpha" && $4=="L_KAGEMARU" {n++} END{print n+0}' "$queue")" -eq 1 ]
    [ "$(awk -F '\t' '$3=="beta" && $4=="L_SAIZO" {n++} END{print n+0}' "$queue")" -eq 1 ]
    [ "$(awk -F '\t' '($3=="alpha" && $4=="L_SAIZO") || ($3=="beta" && $4=="L_KAGEMARU") {n++} END{print n+0}' "$queue")" -eq 0 ]

    run python3 - "$fixture" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
for ninja, cmd in (("kagemaru", "cmd_parallel_kagemaru"), ("saizo", "cmd_parallel_saizo")):
    task = yaml.safe_load((root / "queue/tasks" / f"{ninja}.yaml").read_text())["task"]
    report = yaml.safe_load((root / task["report_path"]).read_text())
    assert task["task_id"] == f"task_parallel_{ninja}"
    assert task["parent_cmd"] == cmd
    assert report == {"worker_id": ninja, "parent_cmd": cmd}
PY
    [ "$status" -eq 0 ]

    find "$fixture" -depth -delete
}
