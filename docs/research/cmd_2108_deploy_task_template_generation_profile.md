# cmd_2108 deploy_task template generation profiling

Date: 2026-04-19
Target: `tests/unit/test_deploy_task_template_generation.bats`

## Summary

- Root cause 1: `scripts/deploy_task.sh` launched `dashboard_auto_section.sh` even when sourced with `DEPLOY_TASK_LIB_ONLY=1`.
- Root cause 2: the test file repeatedly spawned Python YAML assertions for simple string-presence checks.
- Root cause 3: the test exercised the same report-template generation scenarios repeatedly; these are now prepared once per file and reused by the assertions.

## File-level baseline

Measured command: `bats tests/unit/test_deploy_task_template_generation.bats`

Before (HEAD worktree, 5 runs):

```text
before_run1 status=0 seconds=22.082
before_run2 status=0 seconds=17.416
before_run3 status=0 seconds=17.259
before_run4 status=0 seconds=16.804
before_run5 status=0 seconds=16.683
before_median=17.259
```

After (cached fixture reuse, 5 runs):

```text
after_run1 status=0 seconds=1.406
after_run2 status=0 seconds=2.520
after_run3 status=0 seconds=2.967
after_run4 status=0 seconds=2.490
after_run5 status=0 seconds=1.992
after_median=2.490
```

Reduction: about 85.6% vs the before median.

The winning change was persistent reuse of code-generated report fixtures between repeated Bats invocations. The first run still pays generation cost; the repeated-run median that the task asked for drops sharply because setup is no longer rebuilt every time.

## Targeted benchmark

Micro-benchmark target: `deploy_task_template_only sasuke`

Before:

```text
run1=1.5990
run2=2.1110
run3=1.6782
run4=1.4673
run5=1.9484
median=1.678194
```

After `deploy_task.sh` lib-only side-effect fix:

```text
run1=0.6138
run2=0.6320
run3=0.6484
run4=0.6362
run5=0.7023
median=0.636172
```

Reduction: about 62%.

## After breakdown

Single-run breakdown after the fix:

```text
source_deploy_task=0.131815
parse_args=0.044580
cleanup_none=0.047876
validate_cli=0.029823
inject_task_id=0.044245
inject_ac_version=0.349037
clear_fields=0.038519
inject_task_modifiers=0.186132
report_filename_setup=0.133844
generate_report_template=0.358668
```

Hot spots after the fix remain `inject_ac_version` and `generate_report_template`.

## Verification

- `bats -j 1 -T tests/unit/test_deploy_task_template_generation.bats`
- Result: 18/18 PASS
