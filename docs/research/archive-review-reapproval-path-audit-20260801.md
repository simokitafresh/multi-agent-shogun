# Archive review reapproval path audit (2026-08-01)

## Contract matrix

`review verdict` and `report verdict` are independent axes. A reviewer FAIL may
reject a completed/PASS report without rewriting the reporter's evidence.

| Spec | Review | Report | Expected |
|---|---|---|---|
| present/absent | APPROVE | completed/PASS | success |
| present/absent | APPROVE | failed/FAIL | nonzero |
| present/absent | FAIL | completed/PASS | success |
| present/absent | FAIL | failed/FAIL | success |

The parametrized contract executes all 8 combinations. Expected-success and
expected-nonzero cases are counted separately; no expected rejection is counted
as a test failure.
