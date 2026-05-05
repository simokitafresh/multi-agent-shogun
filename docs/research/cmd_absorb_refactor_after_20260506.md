# cmd_absorb.sh リファクタリング After設計書

## Phase 6: After計測・比較

### before/after 比較表

| 指標 | Before | After | 改善 |
|------|--------|-------|------|
| テスト実行時間(最小) | 0.830s | 0.415s | -50% |
| テスト実行時間(最大) | 0.910s | 0.481s | -47% |
| awk呼出し数(append_changelog) | 2回(purpose+project別々) | 1回(1パス) | -1回 |
| yaml_escape_double_quoted呼出し | 3回(update+append×2) | 2回(update+グローバル1回) | -1回 |
| 行数 | 257行 | 267行 | +10行(コメント・関数追加) |

### 実施内容

**R1: get_cmd_fields_multi (1パスawk)**

```bash
# Before: 2回のawk実行
purpose="$(get_cmd_field purpose)"  # 1回目
project="$(get_cmd_field project)"  # 2回目

# After: 1回のawk実行で両フィールドを取得
fields="$(get_cmd_fields_multi)"
purpose="$(echo "$fields" | sed -n '1p')"
project="$(echo "$fields" | sed -n '2p')"
```

**R2: REASON_ESCAPED グローバル変数化**

```bash
# Before: update_cmd_yaml と append_changelog でそれぞれ計算
# update_cmd_yaml内: reason_escaped="$(yaml_escape_double_quoted "$REASON")"
# append_changelog内: reason_escaped="$(yaml_escape_double_quoted "$REASON")"

# After: スクリプト先頭で1回計算、両関数で再利用
REASON_ESCAPED="$(yaml_escape_double_quoted "$REASON")"
```

### テスト結果

- test_cmd_absorb.bats: 5/5 PASS

### 制約遵守確認

- API互換(引数 `<absorbed_cmd> <absorbing_cmd> <reason>`): 変更なし
- 凍結ロジック(update_cmd_yamlのawk変換): 変更なし
- flock安全: 全ファイル書込みはflock保護継続
- L387準拠(check_stale_lessons内python呼出し): 変更なし
