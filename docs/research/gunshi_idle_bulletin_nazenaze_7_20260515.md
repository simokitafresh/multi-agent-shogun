# 掲示板3件 なぜなぜ7回分析
<!-- generated: 2026-05-15T23:28:00+09:00 by gunshi idle analysis -->

## 対象

掲示板 blt_20260515_231505 (家老idle自走分析3件):
1. 教訓注入有効率30% (10件中3件USEFUL)
2. when/how欠落69件 (auto-ops/gc/db)
3. dashboard CI表示が実態と乖離

## 課題1: 教訓注入有効率30%

### なぜなぜ7回

| # | 問い | 回答 |
|---|------|------|
| 1 | なぜ有効率30%？ | 10件注入中7件が「対象外」と忍者が報告 |
| 2 | なぜ対象外？ | deploy_task.shがtask_type=exactでもimpl向け教訓を注入 |
| 3 | なぜimpl向けが混入？ | type推定がimpactログベースで実態とズレ |
| 4 | なぜtype推定がズレる？ | task_typeの定義境界(exact/impl/recon/research)が曖昧 |
| 5 | なぜ境界が曖昧？ | 教訓のwhenフィールドがタスクタイプに紐づいていない |
| 6 | なぜwhenが注入ロジックに読まれない？ | project+category+ninja_weak_pointsでマッチ。whenは未評価 |
| 7 | **根因**: 注入設計が「量>精度」。関連しそうなものを全部渡す設計で、必要なものだけ渡す設計ではない |

### 行動提案

- effectiveness_score閾値調整(0.40→0.50)で低有効教訓をさらに刈込（既存仕組みを磨く/LG023）
- 新しいマッチングエンジンは不要。cmd_2700で導入済みのeffectiveness_scoreを活用

## 課題2: when/how欠落69件

### なぜなぜ7回

| # | 問い | 回答 |
|---|------|------|
| 1 | なぜ69件にwhen/howがない？ | auto-ops(57件)/gc(11件)/db(2件)が古いフォーマットで登録 |
| 2 | なぜ古いフォーマットが放置？ | 低頻度PJで更新機会がない |
| 3 | なぜ低頻度PJの品質が管理されない？ | gate_lesson_health.shはWARN出力するが対処は意志依存 |
| 4 | なぜ対処されない？ | dm-signalが優先でスキップ。LG034違反 |
| 5 | なぜスキップが許される？ | 69件補完は大量作業。cmd起票コスト>WARN解消動機 |
| 6 | なぜ1件ずつ手動？ | lesson_write.shにbatch補完モードがない |
| 7 | **根因**: 道具の粒度がタスク規模に合っていない。batch補完ツール不在が行動障壁 |

### 行動提案

- 道具を磨く: batch when/how補完スクリプト設計（既存教訓のdetailからwhen/howを自動推定→人間レビュー）
- 69件を6忍者に分割投入（11-12件/忍者）
- 先に道具(batch補完ツール)を作ってから教訓補完cmd（CLAUDE.md「計算量が多い時→道具を磨け」）

## 課題3: dashboard CI表示乖離

家老が調査cmd起票を要請済み。軍師の範囲外（dashboard_auto_section.shはインフラ）。将軍がcmd起票判断。

## 因果鎖の共通構造

3件全てに共通: **「WARNを出すが対処を強制しない」パターン**。
- 教訓注入: effectiveness_scoreで計測はしたが閾値を刈込みに活用していない
- when/how欠落: gate_lesson_healthがWARNするが補完する道具がない
- CI乖離: dashboardに表示するが正確性を検証するgateがない

Phase 4（自動化×強制）の適用不足。計測→可視化で止まり、可視化→行動の接続がない。

## 実測値

- auto-ops: 57件 when=0 how=未計測
- google-classroom: 11件 when=0 how=未計測
- database: 2件 when=0 how=未計測
- dm-signal: 718件 when=718 (100%)
- infra lessons_gunshi: 33件 when=33 (100%)
