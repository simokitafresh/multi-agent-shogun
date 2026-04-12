# 教訓効果率分析 (2026-04-12)
<!-- gunshi idle自走 Step 1完了後の教訓分析 -->

## データソース
- `logs/lesson_impact.tsv` (2003行, 2026-04-09〜)
- `logs/karo_workarounds.yaml` (直近10件)

## WA率分析（直近10件）

| WA | category | 対処 | Level | 状態 |
|---|---|---|---|---|
| cmd_1860 | premature_shelve | header L23(並行commit HEAD~1確認) | L2 | 軍師判定ミス |
| cmd_1859 | scout_exempt_missing | 将軍側 | - | 将軍対処 |
| cmd_1858 | stale_ac_contamination | cmd_1861 reset_stale_fields | L4 | 修正済み |
| cmd_1855 | verdict_override | header L24(絶対条件→例外確認) | L2 | 対処済み |

WA率: 4/10 = 40%。Level 4 gate根絶実績(report_yaml_format 14→0, ci_gate_mismatch 13→0)に対し、直近WAは新カテゴリ(Level 2対処)。

## 教訓活用パターン

### 高活用(injected率高)
- L074/L063: 各62回injected。29回feedback。最も高頻度で参照される教訓
- L094: 11回injected, 10回feedback。高feedback率=品質への貢献大

### 正常dormant(100% withheld)
- L428(deploy_task.sh重複)/L398(Python変数注入)/L387(cmd_absorb.sh注入)/L254/L364
- 全て特定スクリプトにバインド。対象コード変更時のみ活性化する設計
- retired候補ではない。フィルタ正常動作

## 結論
- 教訓フィルタリングは正常。高withheld≠低品質。スクリプト固有教訓の正常動作
- 改善対象: なし。WA率低下は教訓ではなくLevel 4 gateが主因(S40実証: gate>lesson 10倍)
