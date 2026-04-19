# cmd_2115 test_cmd_save.bats profiling

Date: 2026-04-19
Target: `tests/unit/test_cmd_save.bats`
Goal: `cmd_save` unit test runtime reduction

## Before

Command:

```bash
/usr/bin/time -f 'elapsed=%e' bash scripts/run_tests.sh file tests/unit/test_cmd_save.bats
```

5-run results before any edits:

| run | seconds |
|---|---:|
| 1 | 6.79 |
| 2 | 5.88 |
| 3 | 4.50 |
| 4 | 4.19 |
| 5 | 4.28 |

Median: `4.50s`

## Profiling findings

- `setup_file()` extracts many snippets from `scripts/cmd_save.sh`, but a 1-pass `awk` rewrite regressed badly (`10.51s`, `10.46s`, `12.36s`, `12.12s`, `9.05s`) because large string concatenation inside the extractor cost more than the original `sed/grep` pipeline.
- The repeat hot path is `check_quality_gate()` calling `load_cmd_block()` across many tests. The original helper spawned `awk` and `grep` for every test case.
- Replacing only the test-harness `load_cmd_block()` path with a pure-Bash scanner, and making `_setup_cmd_block()` pure Bash as well, removed one `awk` + one `grep` from each test invocation without changing the inline logic under test.
- After that change, a direct probe run reached `4.21s`, showing the hot-path change helps locally.
- However, repeated cold runs on this WSL2 `/mnt/c` workspace remained highly unstable (`8.01s`, `9.36s`, `8.65s`, `6.75s`, `6.14s`; median `8.01s`). This matches prior infra lessons that cold I/O on WSL2 can dominate and mask small harness wins.

## Conclusion

Result: `PASS_NO_IMPROVEMENT`

- A low-risk harness improvement was kept: pure-Bash `CMD_BLOCK` loading in the test harness.
- A reliable `30%` median reduction could not be demonstrated in this environment.
- Further large gains would require rewriting the `check_quality_gate()` inline logic itself (many `grep`/`sed`/`awk` subprocesses inside the function body), which would reduce fidelity for a test whose purpose is to exercise the real `cmd_save.sh` logic.
