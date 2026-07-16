# inbox review round-trip CoDD generation 2

- cmd: `cmd_karo_hotfix_speed_pipeline_inbox_roundtrip_gen2_202607162312`
- fixture: generation 1's isolated 60-read mailbox, identical entry types, ten independent runs per direction

## Generation 1 baseline and generation 2 before

| Stage | karo -> gunshi p50/p95 (ms) | gunshi -> karo p50/p95 (ms) |
|---|---:|---:|
| generation 1 after | 94.248 / 120.875 | 53.744 / 117.587 |
| generation 2 before (10 runs) | 122.247 / 197.933 | 83.466 / 96.482 |

The generation 2 profile showed review-context setup as the direction-specific maximum and `mktemp` plus atomic overflow reconstruction as the largest common fixed interval.

## Generation 2 changes

1. Run independent memory DB and semantic review-context lookups concurrently, retaining their timeout and fail-soft contracts and deterministic merge order.
2. Return before temporary allocation when neither lookup helper exists.
3. Generate the overflow same-directory temporary name with Bash builtins under the existing exclusive inbox flock; retain atomic replace/retry.

## Generation 2 after

| Direction | Ten samples (ms) | p50 | p95/max | Gen2-before p50/p95 delta |
|---|---|---:|---:|---:|
| karo -> gunshi | 105.977, 99.057, 91.842, 94.550, 92.641, 98.618, 107.298, 109.643, 93.473, 86.959 | 96.584 | 109.643 | -21.0% / -44.6% |
| gunshi -> karo | 68.884, 62.851, 67.784, 71.374, 64.589, 60.594, 63.517, 64.277, 69.986, 78.440 | 66.187 | 78.440 | -20.7% / -18.7% |

No direction regressed against the generation 2 before measurement; both directions shortened strictly at p50 and p95. Relative to generation 1, both p95 values also improved.

## Residual top three and next iteration

1. Review query construction plus bounded context lookup.
2. Single-pass awk overflow selection/emission.
3. Flock and same-directory atomic replace filesystem I/O.

Continue only if a ten-run p95 exceeds 110ms or one measured residual interval contributes at least 10% of p50. Otherwise stop to avoid optimizing noise.
