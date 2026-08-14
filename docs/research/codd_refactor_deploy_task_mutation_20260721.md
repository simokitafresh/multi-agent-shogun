# deploy_task.sh task-mutation speed CoDD spec

## Problem and measured profile

The 2026-07-21 throughput CI-fix deployment measured total wall 118.482s. The
task-mutation phase consumed 68.356s, report publication 10.185s, and semantic
context 5.328s. A warm Kotaro audit measured 20.998s total and 13.592s task
mutation. The tail is therefore shared-cache/lesson/report mutation work, not
the target code itself.

## Refactoring target

R1: preserve output, YAML safety, lesson identity, and report fingerprints while
reusing existing bounded wave-cache and batch field helpers across one deploy.
R2: make telemetry report real subprocess counts or explicit unmeasured state;
do not change gate semantics or hide semantic-context nonzero results.

## Order and constraints

Measure existing logs first; implement R1 only; run affected tests and verify
FAIL0/SKIP0; then consider R2. Do not alter frozen hash/awk logic, safety
guards, or acceptance contracts. Before/after must use the same source and
target and retain SHA evidence.
