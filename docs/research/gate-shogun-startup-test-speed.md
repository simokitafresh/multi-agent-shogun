# Gate shogun startup test speed

## Direct links

- Test contract: [[test_gate_shogun_startup.bats]]
- Production implementation: [[gate_shogun_startup.sh]]
- Full-suite performance design: [[test-suite-time-immune-asis-tobe-5w1h_20260714.md]]
- Training policy: [[training-cycle.md]]

## Verified design anchor

`tests/unit/test_gate_shogun_startup.bats:318` uses Bats' per-test
`BATS_TEST_TMPDIR` as the fixture root. Bats owns cleanup, so the suite no
longer launches a second `mktemp` and recursive removal for each of its 92
cases; each case still receives an isolated copy of the shared base fixture.

## Remaining measured opportunities

1. The test file sources the roughly 147 KB startup gate in every test process.
   Keep this until a bounded loader avoids the `MAX_ARG_STRLEN` failure recorded
   by L930; exporting the function is not safe.
2. Every test copies the shared base fixture. Measure reflink support and
   mutation isolation before replacing `cp -a`.
3. The gate itself launches many subprocesses per case. If fixture improvements
   plateau, profile the production script and remove repeated scans without
   weakening FAIL, SKIP, or coverage contracts.
