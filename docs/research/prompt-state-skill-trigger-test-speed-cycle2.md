# Prompt state skill-trigger Unit 高速化 cycle 2

対象: [[test_prompt_state_inject_skill_trigger.bats]] / 被テスト: [[prompt_state_inject.sh]] / 推薦器: [[skill_recommend.sh]]

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | BATSが作成済みのtest固有directoryを直接使う | `setup`ごとのsubdirectory生成16回は隔離を増やさず反復I/Oだけを増やす |
| 2 | skill recommendation cache cleanup先を環境変数へ統一 | fixture cache directory指定と固定`/tmp`削除先が一致しない |
| 3 | semantic mock生成を共通helper化 | executable生成・chmod・heredocが複数testへ分散している |

## 守る契約

- test固有の可変outputは`BATS_TEST_TMPDIR`に隔離する。
- `scripts/hooks/prompt_state_inject.sh:595` のinbox nudge早期returnを変更しない。
