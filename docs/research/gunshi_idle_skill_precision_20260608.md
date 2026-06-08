# スキル推薦精度分析 — precision 0%の根因と改善案

## 計測データ (2026-06-08)

| 指標 | 値 | ソース |
|------|-----|--------|
| precision率 | 0% (0/18) | gate_gunshi_startup.sh |
| 偽陽性率 | 100% (18/18) | gate_gunshi_startup.sh |
| 推薦ログ最終記録 | 2026-05-31 | skill_recommend_log.yaml |
| 実行ログ最終記録 | 2026-06-08 | skill_execution_log.yaml |
| 比較対象外 | 6件(実行ログ未観測agent) | gate_gunshi_startup.sh |

## 根因分析 (なぜなぜ)

1. なぜprecision 0%か？ → 推薦されたスキルが実行ログに記録されていない
2. なぜ記録されていないか？ → 3つの根因が複合

### 根因1: 推薦ログの記録停止 (最終: 2026-05-31)

推薦ログへの書き込みが2026-05-31以降停止。約8日間新規推薦が記録されていない。
この間にcmd_3232-3243が配備・実行されているが推薦ログには反映されていない。

推薦ログ書込みはprompt_state_inject.sh:record_skill_recommendation_log()。
原因候補: (1)同一prompt_hashのキャッシュヒット(L385)でdedup除外 (2)semantic_search.shのtimeout 0.60s(L396)で空結果 (3)prompt_text空でearly return(L376)。
skill_allowed_for_agent()に忍者専用フィルタ(L349)は既に実装済み。deploy_task.sh(L3069)のフィルタとは別経路。

### 根因2: 推薦agent≠実行agentの照合不一致

推薦ログ: agent_id = shogun/gunshi/karo (配備者)
実行ログ: executor = hayate/kagemaru/saizo (忍者)

precision計測で「推薦agent Aのスキルが、実行agentとして同一Aで記録されているか」を見ている場合、忍者による実行が推薦に紐づかない。

### 根因3: 役割制限スキルの越権推薦

推薦ログに含まれる主要偽陽性:
- shogunへのreport-write/verdict-check推薦 → 忍者専用スキル
- karo/shogunへのhensei系推薦 → 将軍専用スキル
- gunshiへのcodd-refactor推薦 → 忍者向けスキル

deploy_task.shのL3069でSKILL.md内の「軍師専用/家老専用/将軍専用」フィルタがあるが、**忍者専用はフィルタされていない**。また推薦ログ記録はフィルタ前に行われている可能性がある。

## 改善案

### 案1: 推薦ログ記録の復活確認 (最優先)
- deploy_task.shのsemantic_search.sh呼出し結果と推薦ログ書き込みパスを確認
- timeout 5が発火していないか、書き込み先が変わっていないか検証

### 案2: 推薦ログにninja_nameフィールド追加
- 推薦時にtask割当先(ninja)を記録し、実行ログのexecutorと照合可能にする
- precision計測の照合キーを「推薦agent」→「割当ninja」に変更

### 案3: 役割フィルタの拡充
- deploy_task.shのフィルタ(L3069)に「忍者専用」パターンを追加
- SKILL.md descriptionに`ALLOWED_ROLES: [ninja]`等の構造化メタデータを追加し、推薦時にagent roleと照合

### 案4: aliases補完 (効果中)
- 現在aliases定義がないスキルにaliasesを追加し、semantic_search.shの検索精度を向上
- 効果: 推薦の正確性向上だが、根因1-3の解決が先

## 推奨行動順序

1. 根因1の調査(推薦ログ停止原因) → D0で調査可能
2. 根因3の修正(フィルタ拡充) → D0で修正可能(1ファイル20行以下)
3. 根因2の修正(ninja_nameフィールド) → cmd起票候補

## causal_chain

semantic_search.sh timeout/パス変更→推薦ログ記録停止→precision計測対象が古い推薦のみ→偽陽性100%。並行して推薦agent≠実行agentの照合不一致+忍者専用フィルタ欠如が偽陽性を構造的に生んでいる。
