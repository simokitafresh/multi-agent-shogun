# 教訓useful率分析 — 0%教訓のretire/フィルタ改善提案

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-03
- データ源: logs/lesson_impact.tsv (2011件)

## 要約

useful率19.7%(105/533 feedback)。0%教訓17件がNOT_USEFULの21%を占有。
retireまたはtarget_files限定注入でuseful率25%+に改善見込み。

## 全体統計

| 指標 | 値 |
|------|-----|
| feedback件数 | 533 |
| USEFUL | 105 (19.7%) |
| NOT_USEFUL | 428 (80.3%) |
| 0%教訓(5件+) | 17件 |
| 0%教訓のNOT_USEFUL | 90件 (21%) |

## 高精度教訓 (useful率>50%、5件以上)

| ID | useful率 | 件数 | ���徴 |
|----|---------|------|------|
| L559 | 100% | 11/11 | CoDD台帳比較。target_files指定+直近作業一致 |
| L342 | 75% | 9/12 | .gitignoreホワイトリスト。全忍者git操作で頻出 |
| L509 | 70% | 30/43 | hot-cache計測。パフォーマンス計測タスクで有効 |

## 0%教訓 (useful率=0%、5件以上)

17件。全てNOT_USEFUL。共通特徴: **特定ファイル限定のバグ修正記録**。

| ID | 件数 | 内容 | target_files |
|----|------|------|-------------|
| L175 | 7 | - | - |
| L079 | 6 | - | - |
| L097 | 6 | - | - |
| L393 | 6 | - | - |
| L502 | 5 | rg vs awk (WSL2) | gate_vercel_phase.sh |
| L340 | 5 | YAMLエスケープ | cmd_quality_log.sh |
| L287 | 5 | YAML構造破損fallback | gate_shogun_startup.sh |
| L524 | 5 | yaml_field_set AWK継続行 | cmd_save.sh |
| L357 | 5 | yaml.dump安全違反 | lesson_auto_tag.sh |
| L351 | 5 | insight_write yaml.dump | queue/insights.yaml |
| L543 | 5 | bats fixture可変ID | test_cmd_save_environment_change.bats |
| L319 | 5 | テスト重複統合 | - |
| L417 | 5 | heredoc YAMLエスケープ | cmd_friction_log.sh |
| L101 | 5 | - | - |
| L300 | 5 | - | - |
| L170 | 5 | - | - |
| L169 | 5 | - | - |

## 因果鎖

target_files限定のバグ修正教訓 → universalまたは広いタグで注入 → 非関連タスクで忍者CTX消費 → NOT_USEFUL → useful率低下
→ 10回繰返し: 各教訓5-7回×17件=90件NOT_USEFUL=忍者CTX浪費(負の複利)

## 提案

1. **retire候補**: useful率0%かつtarget_filesが1-2本限定の教訓はretire
2. **フィルタ改善**: target_files持ちの教訓は、タスクのtarget_pathとマッチ時のみ注入
3. **既存タグフィルタとの統合**: deploy_task.shのlesson注入ロジックにtarget_files突合を追加

## 期待効果

- NOT_USEFUL 90件削減(21%) → useful率19.7%→~25%
- 忍者CTX��費: 教訓1件≈100-200トークン × 90件 = 9,000-18,000トークン節約

## 根因特定 (CS3: 実コード確認)

deploy_task.sh L2535-2585の注入ロジックを現物確認。

### 注入フロー
1. `universal`タグ教訓 → **常に注入**(L2550-2553)。target_filesフィルタを通過しない
2. タグマッチ教訓 → target_files不一致でも**タグ優先原則**(L2573)で除外されない
3. target_filesフィルタが効くのは「タグマッチしない AND target_files不一致」の場合のみ

### 真の根因
- `[universal]`タグ+target_files指定の教訓がtarget_filesフィルタをバイパスする
- タグ優先原則(L2573)により、広タグ(bash/yaml/process)でタグマッチすればtarget_filesフィルタ無効

### 改善案
- **Option A**: universal教訓+target_files指定 → target_filesマッチ時のみ注入(universal意味変更)
- **Option B**(推奨): useful率0%の教訓のuniversalタグを除去し、target_files限定タグに変更
- **Option C**: タグ優先原則をtarget_files優先に反転(影響範囲大)

Option Bが最小影響。17件のuseful率0%教訓から`[universal]`や広タグを除去→target_files限定に変更。

generated: 2026-05-03T10:25:00+09:00
