# DB capability launcher test speed

## Direct links

- Test contract: [[test_db_capability_launcher.bats]]
- Production launcher: [[db_capability_launcher.py]]
- Timing wrapper: [[run_timed_bats.sh]]

## Improvement candidates

1. Share Git author configuration at suite scope. Five fixture repositories each launched `git config user.email` and `git config user.name`, for ten repeated subprocesses.
2. Build committed repository archetypes once in `setup_file` and copy isolated fixtures per test. This has higher implementation complexity because the five repositories have different tracked files and project roots.
3. If fixture setup plateaus, profile repeated Python launcher/module imports and move optimization to the production script without relaxing fail-closed expectations.

## Adopted change and measurement

`setup_file` now creates one owner-local Git configuration under `BATS_FILE_TMPDIR`; every test exports it through `GIT_CONFIG_GLOBAL`. Repository contents, independent `.git` directories, commits, and launcher expectations remain isolated.

- Before: 12.451 seconds in the current shared-host run; campaign best was 10.586 seconds.
- After: 12.790 and 10.376 seconds; best-after improved the campaign best by 0.210 seconds (1.98%).
- Contract: both after runs passed 22/22 with FAIL 0 and SKIP 0.

The timing boundary is explicit in [[run_timed_bats.sh]]: line 13 records `started_ns` immediately before line 15 invokes `bats`, and lines 19-24 derive wall time, test count, skip count, and pass/fail status. This preserves the campaign's direct single-file measurement contract.
