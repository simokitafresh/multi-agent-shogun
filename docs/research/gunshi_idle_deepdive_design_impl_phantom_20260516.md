# 設計=実装幻想のDeepdive: PHANTOM教訓検出
<!-- generated: 2026-05-16T00:06:00+09:00 by gunshi idle analysis -->

## 発端

本セッションで3件の「計測と実態の乖離」を発見:
1. automatedフラグ5件が実態と乖離(60%→76%)
2. 前セッション設計書が100%と主張→実態75.8%
3. SG-PRE20がスケルトンのみで未実装

## なぜなぜ7回

| # | 問い | 回答 |
|---|------|------|
| 1 | なぜ3件も乖離？ | 全て「記録はあるが実体がない」パターン |
| 2 | なぜ蓄積？ | 設計→記録→/clear→実装消失。/clear前の軍師が「やったつもり」で記録 |
| 3 | なぜ消失が検出されない？ | startup gateがYAMLフラグを信頼。フラグ vs 実装の突合gateがない |
| 4 | なぜ突合gateがない？ | 従来は意志依存の手順。Phase 4(自動化×強制)適用漏れ |
| 5 | なぜ意志依存？ | automatedフラグは自己申告。計測者=実装者 |
| 6 | なぜ自己申告が問題？ | 「やったつもり」を許す。他覚的検証がない。LG027(計測ズレ)と同根 |
| 7 | **根因**: 教訓のautomatedフラグは自己申告。実装存在をgrepで他覚的検証する免疫がない |

## 検証結果(実測)

教訓35件のautomated:true 25件を検証:

| 分類 | 件数 | 内容 |
|------|------|------|
| OK(スクリプト存在) | 14件 | enforcementのスクリプトが実在 |
| NO_SCRIPT(ドキュメント強制) | 7件 | enforcement=review_logヘッダ/gunshi.md。スクリプトBLOCKではない |
| MISSING_SCRIPT(名前マッチ問題) | 2件 | combined.sh→.claude/hooks/pre-bash-combined.shで実在 |

NO_SCRIPT 7件の内訳:
- LG001: review_logヘッダ+gunshi.md → **Gate 6拡張(LG007)はINFO化済みだがLG001は未**
- LG010/LG020/LG029/LG033/LG034: cs_checklist/cmd_save/PRE3に実装済み。**enforcementの記述が古い**
- LG014: 真のLevel 2(ドキュメント強制のみ)

## 構造的発見

**enforcementフィールドの更新漏れが根因**。実装はあるのに記述が古く、検証スクリプトがfalse negativeを出す。

3つの問題:
1. **automatedフラグ**: 自己申告。他覚的検証なし
2. **enforcementフィールド**: 実装後に更新されない。陳腐化する
3. **設計書**: 「実装済み」と書いたが実装していない。/clear後に検証されない

共通根因: **自己申告を他覚的に検証する仕組みがない**

## 行動提案

### 即時(D0実装可能)
- LG001のGuard化: pre-bash-combined.shで`git show HEAD:`コマンド実行時に「これは既実装判定か？Read toolは使うな」INFOを出す
  → ただしgit show HEADは多用途。既実装判定時のみ発火は困難。保留

### 中期(cmd起票)
- enforcement自動検証スクリプト: `gate_lesson_enforcement_verify.sh`
  - automated:trueの教訓→enforcementからスクリプト名抽出→find/grep存在確認
  - PHANTOM検出→startup gate WARN
  - 推定実装: 20行。既存gate_lesson_health.shに統合可能

### 設計原則
- **記録したら検証。検証なき記録は幻想。** (deepdive Phase 4の教訓版)
- フラグ更新時にgrep確認を強制するhookは過剰(LG032: 新しい強制を作るな)
- startup gateに検証を追加するのが最小コスト(既存強制に乗せる)
