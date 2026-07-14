# deploy_task YAML injection test speed

## 2026-07-15 baseline and change

- Baseline: 32 PASS / 0 FAIL / 0 SKIP, wall 7.463s via [[run_timed_bats.sh]].
- Dominant repeated path: modifier cases repeatedly parse and atomically rewrite task YAML through [[inject_task_modifiers.py]].
- Tested change: selecting PyYAML's `CSafeLoader`/`CSafeDumper` produced 9.850s, 10.532s, and 8.034s, so it was reverted instead of shipping a non-improvement.
- Next highest-impact implementation is a persistent/batched modifier fixture that preserves all cases while removing repeated process boundaries. Contract coverage remains in [[test_deploy_task_yaml_injection.bats]]; no cases, assertions, or parameter space were removed.

The production path's atomic write remains in `scripts/lib/inject_task_modifiers.py`: `os.replace(tmp_path, task_file)` is the fail-closed publication boundary.
