# cmd_4106 semantic / lesson injection experiment (hanzo)

- base: `75f7c530f59093db4562fbf0a21fbad3b2e75893`
- isolation: detached worktree `/tmp/hanzo4106.TRY3eC/base`
- fixture: `queue/tasks/hanzo.yaml` copied once, reset byte-for-byte before every run
- repetitions: 5 per candidate; `wall_ms=(date +%s%N end-start)`; noop measured identically
- receipt: `/tmp/hanzo4106.TRY3eC/results.tsv`

## Results

| independently enabled candidate | runs (ms) | median | warm median (runs 2-5) | injected result | missing |
|---|---:|---:|---:|---|---:|
| noop / all three phases disabled | 6,5,4,4,9 | 5 | 4.5 | none | 0 |
| `related_lessons` / `inject_related_lessons` | 3801,381,449,398,412 | 412 | 405 | L147,L594,L088 (3/3 with summary+detail) | 0 |
| related internal WA supplement / `inject_workaround_pattern_lessons` | 7,8,7,11,8 | 8 | 8 | base fixture unchanged; no new mapped lesson at this base | 0 (candidate correctly empty) |
| `semantic_context` / `inject_semantic_concepts` | 644,348,308,352,376 | 352 | 350 | 5 concepts; 6 recommended-skill strings | 0 |
| `memory_context` / `inject_memory_db_context` | 405,495,471,423,355 | 423 | 447 | DB hits 0; `memory_db_context` absent | 0 (query returned no candidates) |

The disable baseline is the noop row. Each enabled row invokes only the named injector against a fresh copy of the same fixture. The `related_lessons` cold run (3801ms) is a reproducible cold-start outlier; the warm median is used for steady-state comparison and the outlier is retained rather than discarded.

## Candidate inventory and decision

- Keep `related_lessons`: 3 concrete lessons injected, 0 missing. Warm contribution above noop: about 400.5ms. Individual selected candidates were L147, L594, L088; all had both summary and detail.
- Keep `semantic_context`: 5/5 concepts injected with 0 missing: `agent_formation_management`, `skill_design_rules`, `systems_knowledge_base`, `daemon_supervision`, `hook_automation_framework`. Warm contribution: about 345.5ms.
- Reject the six `recommended_skills` strings for this fixture as task guidance: they are all role-restricted or unrelated to a ninja recon (`shogun-cli-switch` twice, `skill-installer`, `reset-layout`, `shogun-clear-prep`, `dream`). They are produced inside the semantic candidate and add no useful task content here.
- Reject `memory_context` for this fixture: it is the steady-state dominant unsuccessful candidate (about 442.5ms above noop) and injected 0 rows. This is a measured fixture-specific decision, not authorization to modify `deploy_task.sh`.
- Reject/skip the WA supplement at this base: 8ms warm median and 0 additions. No content was lost because the candidate set was empty.

## Dominant term and completeness

Steady state dominant term is `memory_context` (447ms warm median), narrowly above `related_lessons` (405ms) and `semantic_context` (350ms). Cold-path dominant term is `related_lessons` (3801ms first run). Measured candidates: 4/4 injector candidates plus noop baseline. Output candidates inspected: lessons 3/3, semantic concepts 5/5, semantic recommended-skill strings 6/6, memory hits 0/0, WA additions 0/0. Unmeasured candidates: 0. Injection-content omissions among returned candidates: 0.

No production script, gate, hook, or test was changed.
