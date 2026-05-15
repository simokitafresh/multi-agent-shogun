# なぜなぜ7回: cmd_2788 LGTM→BLOCK
<!-- generated: 2026-05-16T00:15:00+09:00 by gunshi idle analysis -->

## 事象

cmd_2788(record_lesson_feedback.sh task_typeフォールバック修正)
- 軍師verdict: LGTM
- GATE結果: BLOCK (empty_lessons_useful)
- 原因: lessons_useful: [] だが related_lessons 10件注入済み
- 結末: 忍者修正→再GATE CLEAR

## なぜなぜ7回

| # | 問い | 回答 |
|---|------|------|
| 1 | なぜLGTM→BLOCK？ | lessons_useful: []を見たのにLGTMを出した |
| 2 | なぜ空リストでLGTM？ | 「注入0件なら正常」と判断。task YAMLのrelated_lessonsを未確認 |
| 3 | なぜrelated_lessonsを未確認？ | precheck PRE11が「2件形式OK」→形式問題なしと信頼 |
| 4 | なぜPRE11出力を鵜呑み？ | PRE11=形式チェックのみ。PRE20(整合チェック)はスケルトン未実装 |
| 5 | なぜPRE20未実装？ | 前セッションの設計=実装幻想(100%→実態75.8%) |
| 6 | なぜ手動でも見落とし？ | 「形式OK」を見た瞬間にlessons_useful検証を完了とみなした |
| 7 | **根因**: gate/precheck PASSを「内容PASS」と混同する認知バイアス。形式チェックが内容チェックの代理指標になるGoodhart構造 |

## 構造的発見

deepdive Phase 1-2と同構造:
- Phase 1: 「nudgeで解決すると仮定した」
- cmd_2788: 「precheckがPASSと言ったから問題ないと仮定した」

共通: **ツール出力を鵜呑みにして現物確認をスキップ**

LG027(計測ズレ)の3度目:
1. accuracy Goodhart (99.6%→97.1%)
2. automated flag乖離 (100%→75.8%)
3. precheck形式PASS→内容PASS混同 ← NEW

**代理指標が最適化されるほど本来の目標から乖離する**

## 対処(実装済み)

| 対処 | Level | 効果 |
|------|-------|------|
| SG-PRE20実装: related_lessons+lessons_useful照合 | L4(BLOCK) | 空リスト+注入ありを自動検出 |
| review_logヘッダ追記: 「precheck PASS≠内容OK」 | L2(ドキュメント) | 毎レビュー時に読まれる |

## 残る課題

- PRE11が「2件形式OK」と出力した理由が不明(報告ファイルアーカイブ済みで再現不能)
- precheck PASS後の手動確認を**強制**する仕組みはない(L2止まり)
- 「gateの出力を信頼しすぎる」はLLMの構造的弱点(Phase 4: 生存本能の不在)
