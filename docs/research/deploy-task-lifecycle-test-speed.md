# deploy task lifecycle test speed

## Improvement cycle

| Priority | Target | Evidence | Action |
|---|---|---|---|
| 1 | [[test_deploy_task_lifecycle.bats]] `resolve_fixture_task` | Each call scanned the 2,378-line test source's production dependency four times with `awk` plus four times with `sed`; affected tests measured about 2.06–2.15 seconds each | Extract the four real production functions once in `setup_file`, then source the ext4 bundle per fixture |
| 2 | [[deploy_task_scaffold.bash]] ordinary setup | The shared helper already owns a project template, but the lifecycle suite's ordinary setup repeats directory and symlink creation | Measure template copy after the function-scan bottleneck is removed |
| 3 | [[test_deploy_task_lifecycle.bats]] direct-mode tests | Several tests repeat the same deploy-task stubs in separate quoted shells | Consider a shared stub library only if profiling shows Bash parse time is still dominant |

## Design anchor

The extracted bundle comes from [[deploy_task.sh]] without replacing behavior. `reset_stale_fields`, `resolve_cmd_source_path`, `resolve_cmd_to_task`, and `inject_cmd_assumptions` remain the production function bodies; only repeated source-file discovery is cached. Expectations, 73-test coverage, and failure behavior remain unchanged.
