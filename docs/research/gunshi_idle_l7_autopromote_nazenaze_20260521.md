# L7 auto-promote未発火 なぜなぜ7回
<!-- generated: 2026-05-21T14:36:00+09:00 by gunshi idle analysis -->

## 結論

auto-promoteが一度も発火しない根因 = **入力品質問題**。stress_testがNO_MATCH全件をcandidate_aliasesに蓄積→operational noise(ALERT/INFO/復帰等)が大半→概念aliasesと無関係→similarity score低い(最大13.8, 閾値16.0)。

## なぜなぜ7回

| # | なぜ | 答え | 証拠 |
|---|------|------|------|
| 1 | auto-promoteが発火しない | 全scoreが16.0未満（最大13.8） | `bash semantic_index_update.sh cmd_complete`実行結果 |
| 2 | scoreが低い | 候補がoperational noise | PENDING_ALIAS_SCORE出力: 「【INFOバッチ】CI緑」→run_077で13.8 |
| 3 | noiseが候補に入る | stress_testがNO_MATCH全件蓄積 | insights.yaml pending 11件中9件がnoise |
| 4 | 選別なし | `is_semantic_wiki_target`はcmd_id/L-idフィルタのみ | L334-342: 日本語ノイズを通す |
| 5 | 日本語ノイズを通す | strip_noiseが英語transport語のみ | L133-139+L156: generic set英語のみ |
| 6 | 入力品質を設計しなかった | 「蓄積→昇格」に注目し入力品質未検証 | cmd_2920設計時にテストなし |
| 7 | Phase 3の変形 | 仕組み作り×データ未観察 | 1回動かせば13.8/16.0を発見できた |

## 計測データ

```
PENDING_ALIAS_SCORE: 【家老】復帰済み -> daemon_supervision score=0.8
PENDING_ALIAS_SCORE: gistに共有して -> infra_design_intent score=3.3
PENDING_ALIAS_SCORE: 【将軍】context鮮度ALERT... -> external_project_registry score=12.2
PENDING_ALIAS_SCORE: 【三層ループALERT】WARNING... -> semantic_dictionary_design score=9.5
PENDING_ALIAS_SCORE: 【CLI再起動成功】hayate... -> semantic_dictionary_design score=11.8
PENDING_ALIAS_SCORE: 【INFOバッチ】CI緑... -> gs_ninpo_research score=13.8
PENDING_ALIAS_SCORE: 【INFOバッチ】CI緑... -> gs_ninpo_research score=13.8
PENDING_ALIAS_SCORE: 速度計測テスト用のダミーcmd -> training_cycle_quality score=2.1
PENDING_ALIAS_SCORE: title セマンティクスマップ -> semantic_dictionary_design score=5.3
PENDING_ALIAS_SCORE: modules -> report_quality_protocol score=6.4
PENDING_ALIAS_SCORE: ではサボりを構造的に... -> codd_methodology score=4.0
```

最大score=13.8。閾値16.0に2.2pt不足。全件false positive的マッチ。

## 修正案

### cmd A: 入力ノイズフィルタ + pending resolve
- `is_semantic_wiki_target`に日本語運用語彙除外追加: 【】プレフィックス, ALERT, INFO, CI緑, 復帰, gist, ダミー
- pending 11件をresolve（ノイズのため概念候補ではない）
- テスト: ノイズ除外+正当候補通過の二値

### cmd B: 修行AC5 → auto-promote直結
- 修行中の忍者がAC5で`[[概念名]] alias: 候補1, 候補2`形式で提案
- parse_pending_semantic_insights がこの形式を認識→概念名で直接マッチ→similarity_score不要
- 修行10-15分/回 × 6忍者で高品質aliases蓄積を加速

### 修行加速の期待効果
- 1修行回で2-3 aliases候補/概念
- 6忍者 × 4回/時間 = 48-72候補/時間
- うち有効率50%として24-36件/時間がindex成長
- ヒット率77.8%→修行1日で90%+到達の見込み

## 因果リンク

- → [[L7_aliases_auto_growth]] auto-promoteの設計元
- → [[Goodhart_metric_5]] resource coverage≠hit rateと同根(計測対象のズレ)
- → [[deepdive_why_chain Phase 3]] 考えて進む×仕組み未検証
- → [[training_cycle_quality]] 修行サイクルとの接続点
