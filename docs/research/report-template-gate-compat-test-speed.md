# report-template gate compatibility test

- Test contract: [[test_report_template_gate_compat.bats]]
- Gate implementation: [[gate_report_format.sh]]
- Shared validator: [[gate_report_format_combined.py]]
- Timing runner and ledger publisher: [[run_timed_bats.sh]]
- Cause: the shared valid-report fixture still used legacy terminal status `done`; the current gate requires `completed`, so 15 of 53 tests failed before optimization could be measured.
- Fix: normalize the shared fixture once. This preserves all 53 cases and their expectations while restoring the valid-report baseline for every dependent test.
- Next speed candidates: profile serialized FIFO gate calls; then reduce repeated per-test fixture copies only if measurement shows either dominates wall time.

origin: [[cmd_training_test_speed_test_report_template_gate_compat__20260715022413]] -> [[stale-shared-report-fixture]] -> [[report-template-gate-compat-test-speed]]
