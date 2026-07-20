# cmd_4106 cache / flock independent experiment (kotaro)

- Fixed base: `75f7c530f59093db4562fbf0a21fbad3b2e75893` (current HEAD matched).
- Isolation: shared-object local clone under `/tmp`; production scripts, gates, hooks, and operational YAML were not modified by the experiment.
- Timing: wall clock from `date +%s%N`, converted to integer milliseconds. Each candidate used a separate cache key or fixture.

## Results

| Candidate | Experiment | wall_ms | Identity / freshness result | Decision |
|---|---|---:|---|---|
| Wave cache cold | Missing snapshot; producer sleeps 50 ms then emits `payload` | 121 | output SHA `239f59ed55e737c7` | Keep: bounded miss cost |
| Wave cache warm | Same namespace/source/target | 39 | same output SHA; mismatch 0 | Keep: 82 ms faster than cold |
| flock wait | New target key; exact snapshot lock held for 200 ms before miss | 245 | same output SHA; mismatch 0 | Dominant candidate; optimize/avoid contention |
| post-flock warm | Same target after contended miss | 31 | same output SHA; mismatch 0 | Keep |
| Wave source identity change | Source mtime changed, same namespace/target | 91 | logged cache miss with new `source_fp`; output mismatch 0 | Keep invalidation contract |
| Memory DB cold resolve | New 1,000-row SQLite fixture, no ext4 snapshot | 94 | selected canonical source while async cache builds | Keep non-wait cold path |
| Memory DB warm resolve | Same fixture after snapshot publication | 93 | selected cache; source rows 1000 = cache rows 1000 | Keep; identity mismatch 0 |
| Memory DB stale recheck | Source mtime advanced after cache publication | 83 | stale detected=yes; selected last atomic cache while refresh launches | Keep freshness contract |
| Context freshness first | Real task (`project: infra`) against clone context | 29 | completed rc 0 | Keep |
| Context freshness repeat | Identical task/context | 32 | same result; mismatch 0 | Keep |
| Context freshness explicit recheck | Instrumented log | 39 | `context_freshness: OK (context/infrastructure.md updated 1 days ago)` | Keep |

## Findings

- Dominant measured term: contended wave-cache flock at **245 ms**, 2.0x cold wave and 7.9x post-flock warm.
- All candidates were measured; none were omitted.
- Cache identity mismatch count: **0** (wave output hashes 4/4 equal; memory source/cache row counts 1000/1000).
- Freshness mismatch count: **0** (source identity change caused a new wave miss; memory stale source was detected; context freshness repeated consistently).
- Adoption: retain all cache/freshness mechanisms. Prioritize reducing lock contention or miss coalescing around wave-cache publication; do not remove identity/freshness checks because their measured cost (29–94 ms) is below the 245 ms contention term and all correctness checks passed.

## Reproduction scope

Functions were extracted directly from the fixed-base `scripts/deploy_task.sh`: `deploy_task_wave_cache()` and `check_context_freshness()`. Memory resolution used fixed-base `scripts/lib/memory_db_cache.sh::prepare_memory_db_for_read()`. Fixtures and cache artifacts existed only under `/tmp`.
