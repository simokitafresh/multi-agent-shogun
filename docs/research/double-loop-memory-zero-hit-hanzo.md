# memory_context zero-hit fast-path experiment (hanzo)

Date: 2026-07-20  
Task: `cmd_karo_double_loop_memory_zero_hit_202607202038_normal`  
Scope: read-only ext4 SQLite snapshot; production script/gate/hook unchanged.

## Fixture and method

- DB: `/tmp/shogun_memory_db_cache/_mnt_c_tools_multi-agent-shogun_multi_agent_shogun_memory.db`
- Rows: 209,138 events; `events_fts` uses FTS5 `tokenize='trigram'`.
- Queries: hit0=`zz_nohit_7f3a9c qq_absent_91de2 never_seen_62ac1`; hit=`二重ループ インフラ改善`; ambiguous=`memory 改善 仕組み`.
- Each candidate was run 9 times in one read-only SQLite process. Wall values below are medians; output comparison uses the current per-keyword `LIKE`, event-type filter, timestamp order, and limit 2 as baseline.

## Results

| Query | Candidate | wall_ms median (min-max) | rows | missing | extra / false result | output hash |
|---|---|---:|---:|---:|---:|---|
| hit0 | current LIKE | 427.549 (284.738-570.234) | 0 | 0 | 0 | e3b0c44298fc |
| hit0 | FTS existence guard, then current on hit | 2.329 (1.338-8.922) | 0 | 0 | 0 | e3b0c44298fc |
| hit0 | FTS direct result | 2.252 (1.505-6.851) | 0 | 0 | 0 | e3b0c44298fc |
| hit0 | recent-rowid 10k window | 13.191 (7.194-14.755) | 0 | 0 | 0 | e3b0c44298fc |
| hit | current LIKE | 300.828 (280.735-453.978) | 3 | 0 | 0 | 96aff7ecdb9a |
| hit | FTS existence guard, then current on hit | 351.541 (268.944-653.626) | 3 | 0 | 0 | 96aff7ecdb9a |
| hit | FTS direct result | 0.867 (0.463-2.336) | 4 | 1 | 2 | 4f73da4af2fa |
| hit | recent-rowid 10k window | 8.489 (6.732-11.673) | 2 | 1 | 0 | 351ef6fd5384 |
| ambiguous | current LIKE | 419.904 (396.133-474.158) | 6 | 0 | 0 | 2f0a56a3d8f8 |
| ambiguous | FTS existence guard, then current on hit | 422.582 (369.251-540.516) | 6 | 0 | 0 | 2f0a56a3d8f8 |
| ambiguous | FTS direct result | 34.074 (29.697-45.099) | 4 | 2 | 1 | 32a1e4155868 |
| ambiguous | recent-rowid 10k window | 13.252 (7.930-15.005) | 6 | 0 | 0 | 2f0a56a3d8f8 |

## Decision

Adopt only the FTS existence guard proposal: if none of the extracted terms has an event-type-qualified FTS hit, return without running the current `LIKE`; otherwise run the current query unchanged. It reduced the measured hit0 median from 427.549ms to 2.329ms (425.220ms, 99.46%) while producing the same hash and zero missing/extra rows in all three fixed query classes. Hit and ambiguous paths add only the guard and preserve the current bytes.

Reject FTS-direct because hit/ambiguous returned 1/2 missing rows and 2/1 extras. Reject a recent-row window because the hit fixture lost one row; its zero misses on this ambiguous fixture do not establish completeness. No production edit was made under this reconnaissance task.

The guard relies on the existing trigram FTS index and the existing extractor's minimum term length of three characters. Before implementation, retain the current path for terms that cannot be represented safely as an FTS phrase; this is a structural fallback, not a displayed gate.
