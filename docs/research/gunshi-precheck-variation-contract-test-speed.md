# gunshi precheck variation contract speed

## Improvement candidates

1. [[gate_gunshi_report_precheck.sh]] ran unrelated git-history and repository scans after the shared engine had already computed SG-PRE33; implemented a focused `GUNSHI_PRECHECK_ONLY=SG-PRE33` exit.
2. [[test_gate_gunshi_precheck_variation_contract.bats]] creates the same task fixture three times; a suite fixture could be shared if file setup becomes dominant.
3. The three variation reports differ only in one YAML block; table-driven engine-level coverage is a future option, provided shell-wrapper coverage remains.

The selector preserves the normal full precheck by default. Focused mode still executes [[gate_gunshi_report_precheck_engine.py]], reads both report and task YAML, emits the same `VARIATION_CHECKS_MSG`, and returns failure when that message contains `ERROR:`.
