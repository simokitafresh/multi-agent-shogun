# スキル自動成長サイクル なぜなぜ7回 — gate FIXヒント伝播不在
<!-- generated: 2026-05-12T13:52:00+09:00 by gunshi idle analysis -->

## 問題

スキル自動成長サイクルで防止ステップ20件が蓄積されたが、report_format BLOCKが4月10件→5月57件に増加。

## なぜなぜ7回

| # | なぜ | 検証方法 | 結果 |
|---|------|---------|------|
| 1 | なぜBLOCK増加？ | gate_metrics.log月別集計 | 配備数増加に比例。BLOCK率は低下傾向 |
| 2 | なぜスキル使用後もBLOCK？ | skill_execution_log cmd_2678 | スキル使用済み(FAIL→PASS遷移)。サイクルは回っている |
| 3 | なぜ初回BLOCKを防げない？ | 防止ステップ内容分析 | 20件中3件が汎用テンプレート(具体的コマンドなし) |
| 4 | なぜ具体的コマンドがない？ | skill_auto_improve.sh L158-195 | BLOCK理由→パターンマッチ生成。gate FIXヒント未参照 |
| 5 | なぜFIXヒント未参照？ | grep FIX skill_auto_improve.sh → 0件 | gate_report_format_main.pyのFIXヒント75件と未接続 |
| 6 | なぜ未接続？ | skill_auto_improve.sh設計 | BLOCK理由文字列のみ処理。gateソースにアクセスしない |
| 7 | **根因** | — | gate→スキルの知識伝播がBLOCK理由文字列という狭い経路のみ。FIXヒント75件が防止ステップに転写されていない |

## 免疫系定量(修正: 機能している)

| 指標 | 値 |
|------|-----|
| 一発CLEAR率 | 71.6%(257/359) |
| BLOCK→CLEAR(自力修正) | 83件(81.4%) |
| 最終CLEAR率 | 94.7%(340/359) |
| BLOCKのみ(未解決) | 19件(5.3%) |

## 修正設計

### 案: skill_auto_improve.shにFIXヒント読込みを追加

1. gate_report_format_main.pyからFIXヒントDB(75件)をJSON抽出
2. BLOCK理由の各フィールド名(verdict/binary_checks/lesson_candidate等)→FIXヒントを照合
3. 防止ステップに具体的修正コマンド(`report_field_set.sh`/`/verdict-check`等)を埋め込む
4. 汎用テンプレート3件を具体的コマンド付きに昇格
5. skill_auto_improve.shをcron化(定期実行)

### 効果予測

一発CLEAR率71.6%→80%+(FIXヒント転写で初回BLOCK防止率向上)

### 追加課題

- skill_auto_improve.sh実行頻度: 手動1回(5/9)→cron化で毎日実行
- 実行頻度不足はなぜなぜ3で特定: 手動→忘れる→蓄積。cron化はninja_monitorの日次タスクに統合可能
