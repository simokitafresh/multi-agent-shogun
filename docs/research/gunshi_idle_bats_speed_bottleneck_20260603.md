# Bats全体テスト速度ボトルネック分析
<!-- generated: 2026-06-03T00:26:00+09:00 by gunshi idle analysis -->
<!-- source: CI run 26821340025 (2026-06-02) -->

## 現状

| 指標 | 値 |
|------|-----|
| 総テスト数 | 2041件 |
| CI実行時間 | 4分16秒 (GitHub Actions) |
| テストファイル総行数 | 54,135行 |
| 10秒超テスト | 10件 |
| 5秒超テスト | 20件 |

## Top20遅延テスト (CI run 26821340025)

| 順位 | 時間(ms) | テスト名 | パターン |
|------|---------|---------|---------|
| 1 | 15348 | AC3: 同一WARN type 2回目以降Session State grep表示 | cmd_save |
| 2 | 14567 | AC3b: resolved_by付きWARN履歴は累計から除外 | cmd_save |
| 3 | 14473 | AC2: WARN発生時にcmd_save_warn entryへnotes記録 | cmd_save |
| 4 | 11056 | pending semantic insights: AC5 alias auto-promote | semantic |
| 5 | 10786 | pending semantic insights: similar concept absorbed | semantic |
| 6 | 10544 | pending semantic insights: operational noise resolved | semantic |
| 7 | 10467 | pending semantic insights: direct alias auto-promote e2e | semantic |
| 8 | 10295 | pending semantic insights: manual direct alias auto-promote | semantic |
| 9 | 10257 | pending semantic insights: L7 round source auto-promote | semantic |
| 10 | 8881 | pending semantic insights: direct alias resolve through similar | semantic |
| 11 | 8384 | bulletin_write auto archive threshold | bulletin |
| 12 | 8204 | NO_MATCH purpose: pending aliases + L7f absorb | semantic |
| 13 | 7015 | LOW: alias expansion semantic stress test | semantic |
| 14 | 6708 | LOW: partial alias triggers expansion | semantic |
| 15 | 6238 | cmd_3135 AC2: q5対フィールド欠落Session State | cmd_save |
| 16 | 6105 | AC2-2: 同一WARN 2回目BLOCK昇格 | cmd_save |
| 17 | 5931 | AC2-3: 同一WARN 3回目BLOCK昇格 | cmd_save |
| 18 | 5435 | resolve_report_file flock timeout | report |
| 19 | 5372 | AC2-4: project違いWARN履歴 | cmd_save |
| 20 | 5246 | AC2-5: project一致WARN履歴 | cmd_save |

## パターン分析

### パターン1: cmd_save Session State系 (8件, 合計~68秒)

根因推定: 各テストがcmd_save.sh(2735行)全体をsourceしpython3サブプロセスを起動。
Session State系は複数回のcmd_save呼出しが必要(2回目以降の挙動テスト)。

### パターン2: semantic_index_update系 (10件, 合計~104秒)

根因推定: python3 semantic_index_update.py起動+FTSクエリ+alias処理。
各テストが独立してpython3を起動。fixture共有なし。

### パターン3: bulletin_write archive (1件, 8秒)

根因推定: YAMLパース+アーカイブ処理+python3。

## 合計影響

- Top20: ~186秒 = 全体256秒の**73%**
- cmd_save系8件: ~68秒 (27%)
- semantic系10件: ~104秒 (41%)
- その他2件(bulletin+report): ~14秒 (5%)

## 対策案

### 案1: cmd_save テストの関数単位source化
cmd_save.sh全体sourceではなく、テスト対象関数のみをextractしてsource。2735行の読込を数十行に削減。

### 案2: semantic テストのpython3共有fixture
setup_file()でpython3プロセスを1回起動→各テストがstdinで入力→共有。9件のpython3起動を1回に削減。

### 案3: bats --jobs最適化
現在jobs=8。WSL2 NTFSではI/O競合で逆効果の可能性。jobs=4とのA/B比較。

### 推奨優先順: 案2(104秒削減) > 案1(68秒削減) > 案3(計測必要)

## 因果リンク

- → [[殿指摘_Bats時間長すぎる]] バグに近い
- → [[test_cmd_save.bats]] 2735行(最大テストファイル)
- → [[test_semantic_index_update.bats]] python3起動×9件
