# Prompt state skill-trigger Unit 高速化

対象: [[test_prompt_state_inject_skill_trigger.bats]] / 被テスト: [[prompt_state_inject.sh]]

## 改善点

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | role/cache用skill treeを`setup_file`で一度だけ複製 | test内`cp -a` 2回を除去し、16 test全体のwall中央値を3.71秒から2.79秒へ短縮 |
| 2 | cache cleanup先をfixtureのcache dirへ統一 | testは`PROMPT_STATE_SKILL_RECOMMEND_CACHE_DIR`を設定する一方、`/tmp/skill_recommend_cache_hayate_cache_test`を削除しており対象が不一致 |
| 3 | test固有directory作成をsetup helperへ集約 | `mkdir -p`とskill生成が複数testに残り、fixture責務が分散 |

## 検証

- focused test 3回: 16/16 PASS、FAIL 0、SKIP 0
- wall: 2.78秒 / 2.79秒 / 2.81秒（中央値2.79秒）
- `scripts/hooks/prompt_state_inject.sh:595`: inbox nudgeを早期returnする既存契約を維持
