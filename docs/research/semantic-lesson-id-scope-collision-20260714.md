# Semantic lesson ID scope collision artifact

- Before algorithm: two `L893` candidates collapsed into one bare dictionary key; candidate_count=2, key_count=1, wrong_link_count=1.
- Infra source: `projects/infra/lessons.yaml:1991`, title `CLEAR時ベストエフォート(&)は並列実行規模増大でサイレント失敗化する`, origin `[[cmd_3622_kotaro_r3]]`.
- DM-Signal source: `/mnt/c/Python_app/DM-signal/tasks/lessons.md:10087`, title `managed DB capabilityはactual環境identity付き往復を入口必須にする`, origin `[[RC2三重FAIL]] -> [[Render capability未実測]] -> [[actual環境preflight強制]]`.
- Before index evidence: both resources used bare `L893`; the DM-Signal resource received infra origin `[[cmd_3622_kotaro_r3]]`.
- After: `infra:L893` and `dm-signal:L893` remain two resources with two exact causal chains; cross_link_count=0.
- Regression fixture: `tests/unit/test_semantic_map_generate.bats` creates the same two-source collision plus an ambiguous bare resource and a unique bare resource. Expected: qualified exact=2, ambiguous_injection=0, unique_bare_injection=1.
- Origin: [[project別L893衝突]] -> [[bare ID単一dict]] -> [[source-qualified lesson ref]].
