# 冷え観点遡及適用(numbers+adversarial) cmd_3169-3178
<!-- generated: 2026-06-06T19:30:00+09:00 by gunshi idle analysis -->

## 対象

三層記憶L0-L7シリーズ: cmd_3169, cmd_3170, cmd_3171, cmd_3172, cmd_3173, cmd_3174, cmd_3175, cmd_3176, cmd_3177, cmd_3178, cmd_karo_ci_fix_three_layer_startup_tests_20260604

冷え観点:
- numbers: 直近10件で連続0件(zero_streak=10/10)
- adversarial: 直近10件で連続0件(zero_streak=10/10)

## numbers遡及適用結果

| cmd_id | 数値検算の有無 | finding_categories記録 | 判定 |
|--------|--------------|----------------------|------|
| cmd_3169 | なし(定数追加。数値検算対象なし) | 未記録 | 正当な省略 |
| cmd_3170 | なし(索引追記。数値なし) | 未記録 | 正当な省略 |
| cmd_3171 | なし(resource行3行追加。数値なし) | 未記録 | 正当な省略 |
| cmd_3172 | あり(0.1秒×4=0.4秒増、13%増をobservationsに記載) | **未記録** | **記録漏れ** |
| cmd_3173 | なし(SELECT件数表示。検算対象なし) | 未記録 | 正当な省略 |
| cmd_3174 | なし(COUNT(*)。DB出力) | 未記録 | 正当な省略 |
| cmd_3175 | なし(timeout値120秒。検算対象低) | 未記録 | 正当な省略 |
| cmd_3176 | なし(テスト件数105=実行結果) | 未記録 | 正当な省略 |
| cmd_3177 | なし(新規スクリプト。数値なし) | 未記録 | 正当な省略 |
| cmd_3178 | なし(候補確定フロー。数値なし) | 未記録 | 正当な省略 |
| CI fix | なし(テスト件数116=実行結果) | 未記録 | 正当な省略 |

**結論**: numbers記録漏れ1件(cmd_3172)。他は正当。三層記憶シリーズは小規模1ファイル変更が多く、数値検算対象が乏しい特性がある。

## adversarial遡及適用結果

| cmd_id | adversarial確認の有無 | finding_categories記録 | 判定 | 見落とし内容 |
|--------|---------------------|----------------------|------|------------|
| cmd_3169 | なし(定数追加。攻撃面なし) | 未記録 | 正当な省略 | - |
| cmd_3170 | なし(索引追記。Markdown) | 未記録 | 正当な省略 | - |
| cmd_3171 | なし(辞書resource追加。静的) | 未記録 | 正当な省略 | - |
| cmd_3172 | あり(set -e+WARN捕捉を確認) | **未記録** | **記録漏れ** | 確認はしたが記録なし |
| cmd_3173 | なし(SELECT ONLY。低リスク) | 未記録 | 正当な省略 | - |
| cmd_3174 | なし(SELECT ONLY。低リスク) | 未記録 | 正当な省略 | - |
| cmd_3175 | なし(cleanup --apply。破壊可能性) | 未記録 | **軽度見落とし** | cleanup基準誤り時のデータ消失リスク未考察 |
| cmd_3176 | なし(cmd_save.sh貫通チェック) | 未記録 | **中度見落とし** | 正規表現6パターンのすり抜けシナリオ未考察 |
| cmd_3177 | なし(state遷移+DB書込み) | 未記録 | **中度見落とし** | 同時実行でのDB破損(flock保護)未確認 |
| cmd_3178 | なし(候補確定フロー) | 未記録 | 要確認 | 確定操作のロールバック可能性未確認 |
| CI fix | なし(テストfixture修正) | 未記録 | 正当な省略 | - |

**結論**: adversarial記録漏れ1件(cmd_3172)+見落とし3件(cmd_3175/3176/3177)。scripts/gates変更cmdで攻撃者視点を明示的に確認していない。

## 根因分析

### 根因1: 記録漏れ(2件)
- cmd_3172でnumbersとadversarialの確認を実施したがfinding_categoriesに反映しなかった
- 原因: observationsに書けばfinding_categoriesは自動的に導出される「はず」と無意識に仮定
- 因果鎖: 確認実施→observationsに記載→finding_categories更新を忘れる→adaptive gating集計から除外→冷え判定(偽陰性)

### 根因2: 確認省略(3件)
- scripts変更cmd(cmd_3175/3176/3177)でadversarial視点の確認自体を省略
- 原因: 三層記憶シリーズが「小規模・定型」と認識され、adversarial確認の必要性を感じなかった
- 因果鎖: 小規模→定型→adversarial不要判断→scripts変更の破壊可能性を見逃す→冷え蓄積
- 補足: gate_gunshi_cs_checklist.shが§5.6でscripts対象cmdのadversarial未検討をWARN表示しているが、WARN時の行動(再検証)まで到達していなかった

## 対策

### 即時(本セッション)
1. **finding_categories反映の意識付け**: observationsに数値/adversarial確認を書いたら、finding_categoriesにも必ず追加する
2. **scripts変更cmd**: adversarial=必須で最低1行記載。「攻撃面なし」なら「adversarial: 低リスク(理由)」と明示

### 構造化(GP候補)
- gate_gunshi_cs_checklist.shの§5.6 WARNが出た時の行動パスが不在。WARNを出すだけでなく、次回レビュー開始時にcold_categoriesを注入するLevel5化を検討

## 付帯発見: gate_gunshi_cs_checklist.sh バグ

L721/L727で`[: 0\n0: integer expression expected`エラー。
根因: `grep -c pattern || echo 0`構文で、grep -cが「0」を出力し exit 1 → `|| echo 0`が追加の「0」を出力 → 変数が「0\n0」(2行) → 整数比較失敗。
修正: `|| echo 0` → `|| true` に変更(grep -cは0件でも「0」を出力するため`echo 0`は不要)。

## 因果リンク
- -> [[adaptive_gating]] finding_categories記録漏れ→adaptive gating偽陰性
- -> [[LG013]] CS観点のidle分析永続化
- -> [[deepdive Phase 4]] 理解≠行動。WARNを見ても行動(再検証)に至らない
