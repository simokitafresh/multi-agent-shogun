# karo_workaround_validation test speed

## Baseline

- Ledger baseline: 45 tests, 23.709 seconds, FAIL 0, SKIP 0.
- Incoming backlink baseline: 0 for this new note.
- Direct file-link baseline: 0 for this new note.

## Improvement candidates

1. Highest impact: `setup()` copied three immutable production inputs for every test (45 × 3 = 135 `/mnt/c` reads). Cache them once in `setup_file()` and copy from `BATS_FILE_TMPDIR`.
2. `setup()` recreates identical settings, task placeholders, and three stub scripts 45 times. A shared immutable fixture tree plus per-test mutable overlay can remove repeated shell I/O.
3. Many cases invoke the same script with only arguments and expected classification changed. Table-driven grouping can reduce Bats process startup while retaining every input/expectation.

## Implemented change

[[test_karo_workaround_validation.bats]] now caches the three immutable inputs once per suite. The linked file's `setup_file()` comment states: “Cache immutable production inputs once per file.” This preserves per-test writable isolation and all 45 behavioral checks.

The pattern follows [[write-edit-combined-hooks-test-speed]]: immutable fixtures live under `BATS_FILE_TMPDIR`, while mutable state remains test-local.
