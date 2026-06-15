# Useful Rate計測バグ修正 — min_samples=5がhealth計測を不能化
<!-- generated: 2026-06-15T12:52:00+09:00 by gunshi idle analysis -->

## 問題

gate_lesson_health.shのuseful_rate計測が3セッション連続で0%(0/8)を報告し偽ALERTを発生。
startup gateで「教訓注入有効率10%」としてALERT表示され、将軍・軍師ともに洗脳#5(先送り)と自己検出していた。

## 根因

gate_lesson_health.sh L402: `if (lesson_total[lid] >= min_samples)` でmin_samples=5を適用。
30cmd窓で100+種類の教訓が分散注入されるため、各教訓のfeedback件数は最大4件。
min_samples=5に到達する教訓がゼロ → useful計算対象ゼロ → 0/0 = 0%。

## 実測データ

| 計測方法 | useful | total | rate |
|----------|--------|-------|------|
| gate修正前(min_samples=5) | 0 | 8 | 0.0% |
| gate修正後(useful_min=2) | 28 | 112 | 25.0% |
| TSV全体(フィルタなし) | 74 | 338 | 21.9% |

## 修正内容 (commit fcec9b309)

- `LESSON_EFFECT_USEFUL_MIN=2` を新設(health計測用)
- awk内でuseful計算にuseful_minを使用
- 退役スキャン用min_samples=5は独立維持(影響なし)

## 次課題: 教訓品質改善

useful_rate 25%は真のシグナル(ALERT閾値30%未満)。改善ターゲット:

### NEVER_USEFUL教訓 (2026-06-16再分析: lesson_impact.tsv全件)

| lesson_id | injected | useful | 内容 | 共通根因 |
|-----------|----------|--------|------|---------|
| L775 | 5 | 0 | auto_commit_before_clear scripts/gates除外 | infra固有→DM-Signal taskに無関係注入 |
| L577 | 4 | 0 | 月次cache exact date lookupミスマッチ | GS cache固有→PF登録に不要 |
| L791 | 3 | 0 | context_freshness gate timeout | gate固有→PF登録に不要 |
| L783 | 3 | 0 | PASS文言とexit code分離 | gate固有→PF登録に不要 |
| L633 | 3 | 0 | monthly専用GS serial path | GS固有→PF登録に不要 |
| L544 | 3 | 0 | EW terminal≠selection_block=0 | FoF研究固有→PF登録に不要 |
| L299 | 3 | 0 | GS shared metrics乖離 | GS固有→PF登録に不要 |

**共通根因**: tag精度不足。GS/gate/infra固有教訓がPF登録等の無関係cmdに無差別注入。
20件以上のNEVER_USEFUL教訓が存在(feedback>=2かつuseful=0)。

### 改善方向

1. **tag精度向上(最優先)**: deploy_task.shの教訓注入フィルタにtask_type/target_path基準追加。教訓にtag(gs_only/gate_only/infra_only等)を付与しタスク属性とマッチング
2. **effectiveness_scoreによる自動淘汰**: injected>=5かつuseful=0%の教訓は自動的にwithheldに降格
3. **注入数削減**: 1cmd当たり7-10件→top-3に絞ればS/N比が改善

## 因果リンク

- -> [[LG027]] referenced率≠useful率の再計測
- -> [[startup_gate_lesson_health_ALERT]] 3セッション連続偽ALERT
- -> [[洗脳#5先送り]] 計測バグだと気づかず先送りした構造
