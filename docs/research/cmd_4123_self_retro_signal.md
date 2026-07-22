# cmd_4123 self-retro signal preservation

- verified_at: 2026-07-23
- SSOT: `logs/self_retro.jsonl` 188/188 JSON records
- change boundary: JSONL recording and validation remain unchanged; only known zero-signal `INSIGHT_FIX_KNOWN` delivery is suppressed

## Production-ledger reconciliation

| Metric | Before | After simulation | Delta |
|---|---:|---:|---:|
| Recorded self-retro rows | 188 | 188 | 0 |
| INSIGHT delivery candidates | 180 | 107 | -73 (-40.6%) |
| Known-template share of candidates | 180/180 (100%) | 107/107 (100%) | 0pp; all four candidates are repeated templates |
| completion_total median | 23,561ms | 23,561ms | 0ms (measurement preserved) |

The after value replays records chronologically with the production threshold 3. A delivery is suppressed only when the exact `improvement_candidate` has appeared at least three times and either `wall_ms == 0` or `max(phase_ms) == 0`.

## Completion pipeline signal

Population: 60 records whose `phase_ms` contains `completion_total`.

| Required item | Actual |
|---|---:|
| dashboard share of summed completion_total | 50.8% (1,401,333ms) |
| ntfy share of summed completion_total | 11.9% (328,656ms) |
| inbox_archive share of summed completion_total | 0.6% (16,647ms) |
| completion_total median | 23,561ms |

Dashboard is the dominant measured phase. The delivery filter therefore removes repetitive zero-duration prose while retaining the phase measurements that identify the next speed target.

## Binary evidence

- Emitter inventory: `rg -n 'self_retro|INSIGHT_FIX_KNOWN' scripts` found the self-retro promotion call at `scripts/lib/defense_overhead_writer.sh:103`; `insight_write.sh` owns downstream bulletin/inbox delivery.
- Boundary fixture: known template + `wall_ms=0` is recorded twice and delivered zero times; repeated measured template with positive dominant phase is delivered once.
- Focused contract: `bats tests/unit/test_defense_overhead_writer.bats` = 10/10 PASS, FAIL 0, SKIP 0.
- Syntax: `bash -n scripts/lib/defense_overhead_writer.sh` = exit 0.

