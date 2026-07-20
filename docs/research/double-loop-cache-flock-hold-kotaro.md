# Double-loop cache flock hold experiment — kotaro

- Source HEAD: `b715cab59de647b45d8f6d3c7db7b8d23a6dfa13`
- Isolated clone: `/tmp/kotaro-double-loop.a7BUpP/repo`
- Source function SHA-256: `c88351cb91b24c5ed43ca76e66d74cc60ceb4c0fd8c2abb5ea5002a7aa87382d`
- Fixture: isolated `/tmp` directory per candidate/scenario/repetition.
- Producer: fixed 50 ms, deterministic `payload-generation-N`.
- Repetitions: every candidate × cold/warm/two-contender scenario = 5 runs.

## Aggregate measurements

Values are worker means in milliseconds; p95 is worker wall time.

| Candidate | Scenario | Workers | Runs | wait_ms | hold_ms | wall_ms | p95_ms | Identity mismatch | Duplicate producer | Missing |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| current | cold | 1 | 5 | 0.179 | 51.483 | 52.089 | 51.889 | 0 | 0 | 0 |
| current | warm | 1 | 5 | 0.000 | 0.000 | 0.642 | 0.477 | 0 | 0 | 0 |
| current | 2 contenders | 2 | 5 | 26.526 | 53.853 | 80.843 | 108.599 | 0 | 5 | 0 |
| double-check | cold | 1 | 5 | 0.421 | 51.524 | 52.252 | 52.279 | 0 | 0 | 0 |
| double-check | warm | 1 | 5 | 0.000 | 0.000 | 0.354 | 0.270 | 0 | 0 | 0 |
| double-check | 2 contenders | 2 | 5 | 25.524 | 26.370 | 52.359 | 53.535 | 0 | 0 | 0 |
| producer outside | cold | 1 | 5 | 0.596 | 3.037 | 56.345 | 54.206 | 0 | 0 | 0 |
| producer outside | warm | 1 | 5 | 0.000 | 0.000 | 2.786 | 4.396 | 0 | 0 | 0 |
| producer outside | 2 contenders | 2 | 5 | 0.362 | 0.340 | 53.272 | 55.114 | 0 | 5 | 0 |
| atomic claim/publish | cold | 1 | 5 | 0.890 | 0.192 | 53.913 | 54.500 | 0 | 0 | 0 |
| atomic claim/publish | warm | 1 | 5 | 0.000 | 0.000 | 0.309 | 0.384 | 0 | 0 | 0 |
| atomic claim/publish | 2 contenders | 2 | 5 | 0.167 | 0.122 | 54.192 | 58.468 | 0 | 0 | 0 |

## Candidate decisions

- Current: reject. Under two contenders it ran two producers in every repetition (5 duplicates) and had the highest wall mean, 80.843 ms.
- Double-check: retain as the minimal safe baseline. It removed all duplicate producers, but the losing contender still waited while the 50 ms producer held the lock.
- Producer outside: reject. Lock hold fell to 0.340 ms, but both contenders produced in every repetition (5 duplicates).
- Atomic claim/publish: adopt for the next implementation experiment. A short exclusive section elects one producer, production occurs outside the lock, and other contenders wait for the atomically published snapshot. It had 0 duplicates and 0 missing results.

## Fastest-candidate correctness

Atomic claim/publish was rerun across freshness generations 1 and 2, each with cold and two-contender scenarios.

- Identity mismatch: **0**
- Freshness mismatch: **0** (generation-specific payload and cache key observed)
- Duplicate producer: **0**
- Missing result: **0**

Compared with current two-contender behavior, atomic claim/publish reduced mean lock hold from 53.853 ms to 0.122 ms (99.77%), wait from 26.526 ms to 0.167 ms (99.37%), and wall from 80.843 ms to 54.192 ms (32.97%), while eliminating five duplicate producer executions.

## Scope and test-policy note

This recon changed no production script, gate, hook, or persistent test. The instrumented harness consumed its value within the experiment and was not persisted, consistent with the default-delete test policy. Gunshi draft review supplemental verdict: APPROVE, confidence HIGH.
