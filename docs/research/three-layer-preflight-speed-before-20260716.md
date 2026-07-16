# three_layer_preflight.sh CoDD Before設計書

## 問題

`UserPromptSubmit` ごとに memory DB、semantic index、Obsidian graph を独立した重いCLIで検索していた。三層は並列でも、最遅層がhook wallを支配する。

## 定量プロファイル

同一queryを実データへ10回実行。単位ms。

| 層 | sum | p50 | p95 | 非0 rc |
|---|---:|---:|---:|---:|
| memory | 12927 | 1028.5 | 3801 | 0 |
| semantic | 11554 | 1148 | 1192 | 0 |
| Obsidian | 5486 | 530.5 | 620 | 10（NO_MATCH=正常完了） |
| issue総wall | 18855 | 1621 | 4504 | 0 |

支配層はmemory/semanticのprocess・index初期化。別測定で `git grep -- docs` は1955–2639msとなり、第一巡後の最大残存寄与だった。

## 凍結契約

- 三層すべてrc=0の場合だけ証跡を公開する。
- global deadlineは9500ms。timeout・欠落・破損はfail-closed。
- nonceを先にatomic publishし、最新世代だけがevidenceをpublishできる。
- isolated fixtureは既存CLI経路を維持する。

origin: [[cmd_karo_hotfix_speed_pipeline_user_prompt_hook_202607162302]] -> [[per-prompt-process-and-index-reload]] -> [[three-layer-preflight-speed]]
