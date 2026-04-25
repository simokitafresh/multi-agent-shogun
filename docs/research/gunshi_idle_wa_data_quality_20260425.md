# karo_workarounds.yaml データ品質分析

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-25
- トリガー: idle自走 Step 1-5

## §1 発見事項

### 1.1 clean+workaround=true 矛盾: 9件

| cmd_id | ninja | timestamp | detail |
|--------|-------|-----------|--------|
| cmd_1790 | saizo | 2026-04-07 | (空) |
| cmd_2011 | kagemaru | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2001 | saizo | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2012 | hayate | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2013 | hayate | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2015 | saizo | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2014 | hayate | 2026-04-17 | 報告クリーン。全AC PASS |
| cmd_2018 | saizo | 2026-04-17 | 報告クリーン |
| cmd_2019 | saizo | 2026-04-17 | 報告クリーン。bats 218件PASS |

**パターン**: 7/9件が2026-04-17に集中。detail=「報告クリーン」なのにworkaround=true。
**推定根因**: karo_workaround_log.shの引数順序ミスまたは家老のバッチ記録時の誤入力。
実害は低い(WA率計算で9件のノイズ)が、112件中9件=8%のデータ汚染。

### 1.2 resolved_by_cmd 空: 96/112 (86%)

修正コミットの追跡が行われていない。修正が効いたかの検証ループが回っていない。
例: cmd_2237(MAX_INJECT未定義) → commit a9326c35で修正済みだがresolved_by_cmd空。

### 1.3 category名にdetail文が混入: 1件

cmd_karo_ctx_reflux_2188のcategory=「yaml_field_set verdictがresultフィールドを上書き→YAML破損。sed修正+RFS再適用で解消」
→ categoryに集計不能な文が入っている。

### 1.4 deploy_task.sh起因WA: 29件 (全WA中26%)

| サブパターン | 件数 | 修正状態 |
|-------------|------|---------|
| target_path/chunk未クリーンアップ | 2 | reset_stale_fields()で修正済み |
| stale notice二重挿入 | 1 | apply_patch改修済み |
| MAX_INJECT未定義 | 1 | L2264で早期定義済み(a9326c35) |
| その他(旧task残留等) | 25 | 個別対処済み |

## §2 因果鎖

データ品質低下→WA傾向分析の集計精度低下→軍師の成績表(karo_workarounds)の信頼性低下→免疫系の抗体生成精度が劣化する(根因パターン誤判定)。

clean+workaround=true矛盾→WA率を過大計算(本来cleanなのにWAとしてカウント)→「まだWAが多い」という偽の問題認識→改善投資の優先順位が歪む。

## §3 改善提案

1. **clean+workaround=true 9件の修正**: 家老にworkaround=falseへの更新を依頼
2. **karo_workaround_log.shに二値検証追加**: category=clean時にworkaround=trueならWARN
3. **resolved_by_cmd自動推定**: WA記録後に同一カテゴリの修正commitをgit log --grepで検索し候補提示

提案2が最も複利効果が高い(今後のデータ品質を恒久的に保証)。
