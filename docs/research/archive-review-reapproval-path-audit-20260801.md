# Archive review reapproval path audit (2026-08-01)

## Contract matrix

`review verdict` and `report verdict` are independent axes. A reviewer FAIL may
reject a completed/PASS report without rewriting the reporter's evidence.

| Spec | Review | Report | Expected |
|---|---|---|---|
| present | APPROVE | completed/PASS | success |
| present | APPROVE | failed/FAIL | nonzero |
| present | FAIL | completed/PASS | success |
| present | FAIL | failed/FAIL | success |
| absent | APPROVE | completed/PASS | success |
| absent | APPROVE | failed/FAIL | nonzero |
| absent | FAIL | completed/PASS | success |
| absent | FAIL | failed/FAIL | success |

The parametrized contract executes all 8 combinations. Expected-success is
6/6 and expected-nonzero is 2/2; all 8/8 outcomes match. No expected rejection
is counted as a test failure.
