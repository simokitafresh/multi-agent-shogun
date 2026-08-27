<!-- last_updated: 2026-07-19 cmd_karo_hotfix_ga299_context_source_boundary_202607190158 -->
<!-- source_commit:3b778381995556e9f59a3df02e18ee311af72e2a reason:ga299-reviewed-exact-boundary evidence:query-runner-contract-classified -->
# Memory DB Query Templates

DB: `data/multi_agent_shogun_memory.db`
Runner: `bash scripts/memory_db_query.sh '<SQL>'`
Schema reference: `context/memory-db-schema.md`
Freshness source: `context/memory-db-schema.md` generated 2026-06-06 by cmd_karo_hotfix_context_freshness_ga005_20260606, plus `scripts/memory_db_query.sh`.

Freshness check 2026-07-01: `bash scripts/memory_db_query.sh 'SELECT event_type, COUNT(*) FROM events GROUP BY event_type ORDER BY COUNT(*) DESC LIMIT 3;'` returned `conversation|44336`, `inbox|11633`, `report|11316`. The runner contract and read-only SELECT templates below remain valid; post-2026-06-23 memory-related commits were operational/session commits and did not change these query examples.

Freshness check 2026-07-09: the same top-3 distribution query returned `conversation|48819`, `report|23732`, `inbox|17646`. Post-2026-07-01 memory commits were semantic/three-layer chain operations (`memory_db_knowledge_write.sh`, `memory_db_live_insert.py`, `semantic_search.sh`, semantic index resources) and did not change the read-only `scripts/memory_db_query.sh '<SQL>'` contract or the SELECT templates below.

All templates below are read-only `SELECT` / `WITH` queries that work with
`scripts/memory_db_query.sh`. Output is pipe-separated, without headers. The runner uses the ext4 cache path by default for the live DB and falls back to the source DB when cache creation is disabled, unavailable, or non-default DB caching is not requested.

## 0. Direct Layer1 Knowledge Write

Use case: Write a knowledge event directly to Layer1 SQLite without using
bulletin, inbox, insight, or any communication side effect. This is for facts
that must enter the memory DB as knowledge, not for sending reports.

```bash
bash scripts/memory_db_knowledge_write.sh "knowledge text" "source" --cmd-id cmd_3455
echo "knowledge text" | bash scripts/memory_db_knowledge_write.sh - "source"
```

The writer stores `event_type='knowledge'`, `direction='direct_insert'`,
keeps the original text in `raw_content`, indexes FTS text, and extracts
Obsidian-style `[[links]]` into `event_links`. It defaults to
`data/multi_agent_shogun_memory.db` or `SHOGUN_MEMORY_DB`.

Source: commit `a29eea6ee` (`scripts/memory_db_knowledge_write.sh`,
`tests/unit/test_cmd_quality_memory_db.bats`).

## 1. Recent Conversation Turns By Agent

Use case: Check the latest conversation turns for one agent and direction, for
example the Lord's newest inbound requests or Shogun's recent responses.

```sql
SELECT ts, agent, direction, substr(summary, 1, 160) AS summary
FROM conversations
WHERE agent = 'lord'
  AND direction = 'inbound'
ORDER BY ts DESC
LIMIT 20;
```

Expected output example:

```text
2026-05-22T16:46:36+09:00|lord|inbound|<task-notification> ...
2026-05-22T16:12:04+09:00|lord|inbound|記憶DBのInput配管...
```

## 2. Full-Text Search Across Memory Events

Use case: Find memory entries whose `summary` or `detail` mention a phrase,
including long conversation records, reports, bulletins, and insights.

```sql
SELECT e.ts, e.event_type, e.agent, e.cmd_id, substr(e.summary, 1, 160) AS summary
FROM events_fts
JOIN events AS e ON e.rowid = events_fts.rowid
WHERE events_fts MATCH 'semantic'
ORDER BY e.ts DESC
LIMIT 20;
```

Expected output example:

```text
2026-05-22T12:59:18+09:00|insight|semantic_stress_test|cmd_2965|[[**PASS DELEGATED**]] semantic_stress_test...
2026-05-22T11:04:40+09:00|conversation|shogun||semantic index...
```

## 3. Command Timeline

Use case: Reconstruct all memory events connected to one command, ordered by
time, regardless of whether the source was a cmd archive, report, gate, inbox,
or conversation.

```sql
SELECT ts, event_type, agent, direction, substr(summary, 1, 140) AS summary
FROM events
WHERE cmd_id = 'cmd_2965'
ORDER BY ts ASC
LIMIT 100;
```

Expected output example:

```text
2026-05-22T12:58:11+09:00|cmd_save|shogun|outbound|cmd_2965 saved...
2026-05-22T12:59:18+09:00|insight|semantic_stress_test|pending|[[**PASS DELEGATED**]] ...
```

## 4. Event Type Distribution

Use case: Confirm whether the DB contains the expected source classes after a
rebuild, and detect missing import streams such as `report`, `gate`, or
`pending_decision`.

```sql
SELECT event_type, COUNT(*) AS count
FROM events
GROUP BY event_type
ORDER BY count DESC, event_type ASC;
```

Expected output example:

```text
conversation|30775
bulletin|4175
cmd_archive|3336
skill_execution|108
pending_decision|43
```

## 5. Concept-Linked Events

Use case: Retrieve the newest events attached to a semantic concept, using
`event_concepts` rather than text matching. This is useful when aliases have
already mapped records to a stable concept.

```sql
SELECT e.ts, e.event_type, e.agent, e.cmd_id, substr(e.summary, 1, 160) AS summary
FROM event_concepts AS c
JOIN events AS e ON e.id = c.event_id
WHERE c.concept_name = 'semantic_dictionary_design'
ORDER BY e.ts DESC
LIMIT 20;
```

Expected output example:

```text
2026-05-22T12:59:19+09:00|insight|semantic_stress_test||[[この危険思想を封じる方法は？...
2026-05-22T12:59:18+09:00|insight|semantic_stress_test|cmd_2965|[[**PASS DELEGATED**]] ...
```

## 6. Gate And Quality Failures For Review

Use case: Review recent gate and command-quality events for BLOCK/WARN patterns
before designing a prevention layer or lesson candidate.

```sql
SELECT ts, event_type, agent, cmd_id, importance, substr(detail, 1, 180) AS detail
FROM events
WHERE event_type IN ('gate', 'cmd_quality')
  AND (
    detail LIKE '%BLOCK%'
    OR detail LIKE '%WARN%'
    OR summary LIKE '%BLOCK%'
    OR summary LIKE '%WARN%'
  )
ORDER BY ts DESC
LIMIT 30;
```

Expected output example:

```text
2026-05-22T14:20:07+09:00|cmd_quality|shogun|cmd_2998|high|BLOCK理由: ...
2026-05-22T13:44:51+09:00|gate|saizo|cmd_2997|normal|gate_report_format...
```

## 7. Source File Audit

Use case: Check which source files contributed events to the DB and whether a
specific import stream is unexpectedly absent or too small.

```sql
SELECT source_file, event_type, COUNT(*) AS count
FROM events
WHERE source_file IS NOT NULL
  AND source_file != ''
GROUP BY source_file, event_type
ORDER BY count DESC, source_file ASC
LIMIT 50;
```

Expected output example:

```text
/home/simokitafresh/multi-agent-shogun/queue/lord_conversation.jsonl|conversation|27449
/home/simokitafresh/multi-agent-shogun/queue/bulletin_board.yaml|bulletin|3230
/home/simokitafresh/multi-agent-shogun/archive/completed/cmd_2965.yaml|cmd_archive|1
```

## 8. Agent Activity Summary

Use case: Compare recent DB activity by agent and event type when checking
whether a role's reports, inbox events, or lessons are being inserted.

```sql
SELECT agent, event_type, COUNT(*) AS count, MAX(ts) AS latest_ts
FROM events
WHERE ts >= '2026-05-01'
GROUP BY agent, event_type
ORDER BY latest_ts DESC, count DESC
LIMIT 50;
```

Expected output example:

```text
shogun|conversation|1200|2026-05-22T16:47:12+09:00
lord|conversation|740|2026-05-22T16:46:36+09:00
saizo|report|18|2026-05-22T14:03:00+09:00
```
