# report_merge.sh リファクタリング CoDD Spec (事後作成)

## cmd: cmd_1956 (CoDD改善#4)
## 実施者: hanzo

## 問題（ボトルネック関数+計測値）

report_merge.sh の実行時間 1947ms。
ボトルネック: field_get 呼び出し 1回あたり約14ms。1ファイルにつき4-5回呼び出し x Nファイル。
10ファイル処理時に ~470ms を field_get サブシェルに消費。

## 定量プロファイル(実測 before)

| 処理 | 時間 | 根因 |
|------|------|------|
| field_get x (4-5回/ファイル) x Nファイル | ~470ms (10ファイル時) | 毎回サブシェル+grep/awk起動 |
| parent_cmd フィルタ | field_get依存 | ファイルごとにfield_getで取得→比較 |
| task_type フィルタ | field_get依存 | 同上 |
| **合計** | **1947ms** | field_get繰り返しが支配的 |

### field_get 1回あたりのコスト
- サブシェル起動
- grep/sed/awk で YAML 解析
- **計: ~14ms/回**

## リファクタリング対象

### R1: field_get x N回ループ → awk 1パス全ファイル走査

**現状**:
- ファイルごとに field_get を 4-5回呼び出し(parent_cmd, task_type 等)
- 各呼び出しでサブシェル+grep/awk 起動
- 10ファイルで ~470ms

**改善**:
- awk 1パスで全ファイルを走査
- parent_cmd フィルタ + task_type フィルタ + 出力生成を同時実行
- サブシェル起動を完全排除

- 期待効果: ~470ms → ~28ms(field_get部分のみの比較で17x高速化)
- 実績(直接比較): 旧方式 ~470ms → 新方式 ~28ms(17x高速化)
- 実績(全体): 1947ms → 76ms(96%削減, 25.6x高速化)

## 制約

- テスト全PASS必須(既存テスト50件: test_deploy_task_ac_handling.bats)
- API互換（出力形式変更なし）: マージされたレポート出力のフォーマット・内容は不変
- 凍結ロジック: レポートマージ後の出力フォーマット生成、エラーハンドリング

## 結果

- before: 1947ms
- after: 76ms
- 改善率: 96%削減(25.6x高速化, 目標300ms達成)
- テスト: 既存テスト50件全PASS(test_deploy_task_ac_handling.bats)
- 対象ファイル: `scripts/report_merge.sh`
