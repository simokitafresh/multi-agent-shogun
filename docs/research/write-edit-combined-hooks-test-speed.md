# Write/edit combined hooks test speed

- Test contract: [[test_write_edit_combined_hooks.bats]]
- Pre-hook implementation: [[pre-write-edit-combined.sh]]
- Post-hook implementation: [[post-write-edit-combined.sh]]
- Full-suite baseline: [[test-suite-time-immune-asis-tobe-5w1h_20260714.md]]

The suite uses `BATS_FILE_TMPDIR` for immutable file fixtures and
`BATS_TEST_TMPDIR` for per-test mutation isolation. Bats owns both cleanup
lifecycles, avoiding a second `mktemp` plus recursive delete in every test.
