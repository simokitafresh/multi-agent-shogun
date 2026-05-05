# cmd_absorb.sh リファクタリング CoDD Spec

## 問題（ボトルネット関数+計測値）

### Phase 1 定量プロファイル（実測）

| 指標 | 計測値 |
|------|--------|
| 1テスト実行(5件) | 0.663〜0.837s（平均 0.74s） |
| awk呼出し数 | 5回（うち多重読込み: get_cmd_field 2回） |
| get_cmd_field呼出し | 2回（purpose + project を別々に読む） |
| yaml_escape_double_quoted呼出し | 4回（update_cmd_yaml: 1回, append_changelog: 2回, 合計実質4） |
| flock使用 | 2箇所（update_cmd_yaml + append_changelog） |

### ボトルネット分析

**R1対象: get_cmd_field 2回呼出し（append_changelog内）**
```
L116: purpose="$(get_cmd_field purpose)"   # CMD_FILEをawk読込み
L117: project="$(get_cmd_field project)"   # CMD_FILEをawk読込み（2回目）
```
同一ファイルへの逐次awk読込みを1パスに統合できる。

**R2対象: yaml_escape_double_quoted冗長呼出し**
```
update_cmd_yaml:  reason_escaped="$(yaml_escape_double_quoted "$REASON")"
append_changelog: purpose_escaped="$(yaml_escape_double_quoted "$purpose")"
                  reason_escaped="$(yaml_escape_double_quoted "$REASON")"  ← REASONは同じ値
```
`$REASON`のエスケープはスクリプト先頭で1回だけ実施し、以降は再利用する。

**R3対象: check_stale_lessons内の2段階project_path取得**
```
# 段階1: projects/{id}.yaml から取得 (awk)
# 段階2: config/projects.yaml から取得 (awk)
```
2段階は必要な場合があるが、1パスで両方対応できる設計に整理する。

## リファクタリング対象

| ID | 対象 | 内容 | 期待効果 |
|----|------|------|---------|
| R1 | get_cmd_fields_multi | purpose+project を1回のawkパスで取得 | awk実行1回削減 |
| R2 | REASON_ESCAPED グローバル変数化 | REASONエスケープをスクリプト先頭で1回実施 | サブシェル生成1回削減 |

## 実施順序

1. R1: `get_cmd_fields_multi`関数追加 → `append_changelog`を修正 → テスト全PASS確認
2. R2: `REASON_ESCAPED`をトップレベルで事前計算 → 各関数で再利用 → テスト全PASS確認
3. Phase 5: before/after計測比較

## 制約

- テスト全PASS必須（test_cmd_absorb.bats 5件）
- API互換: 引数 `<absorbed_cmd> <absorbing_cmd> <reason>` の変更不可
- 凍結ロジック: `update_cmd_yaml`のawk変換ロジック（cmd statusの書換え処理）は変更しない
- L387準拠: `check_stale_lessons`内のpython呼出しパターンは変更しない
- flock安全: ファイル書込みは必ずflockで保護する

## 測定コマンド

```bash
# before/after計測
for i in 1 2 3; do
  { time bats tests/unit/test_cmd_absorb.bats > /dev/null 2>&1; } 2>&1 | grep real
done
```
