# 教訓注入クロスプロジェクト問題分析

## 分析日時
2026-06-03T00:55+09:00

## 背景
gate_lesson_health.sh ALERT: useful率24.0% (12/50件)

## 発見
100% NOT_USEFUL教訓5件を特定:
| lesson_id | title | project | NOT_USEFUL率 |
|-----------|-------|---------|-------------|
| L633 | monthly専用GS serial path | dm-signal | 4/4 (100%) |
| L630 | dict.get(target_date)禁止 | dm-signal | 4/4 (100%) |
| L598 | numpy savetxt float32 | dm-signal | 4/4 (100%) |
| L255 | ticker precompute fallback | dm-signal | 4/4 (100%) |
| L147 | signal_cache値型 | dm-signal | 3/3 (100%) |

## 根因
DM-Signal固有の教訓が修行タスク(cmd_training_backlinks_*、project=infra)にクロスプロジェクト注入されている。

注入経路: deploy_task.shの教訓選択で、タスクのprojectフィールド(infra)とは無関係にDM-Signal lessons.yamlから選択。
特にtag: universalの教訓(L633, L598)がプロジェクト境界を越えて注入。

## 教訓の品質自体は正常
5件の教訓はDM-Signal文脈では有用(backendバグ/パイプライン規約/GS知見)。
問題は教訓の品質ではなくスコープ不一致。

## 影響
- useful率24%の主因: infra/trainingタスクへのDM-Signal教訓注入が分母を膨らませている
- 忍者のCTX浪費: 無関係な教訓10件≈500-1000トークン/タスク
- useful率のGoodhart化リスク: 教訓を削除すればuseful率は上がるが、DM-Signal文脈での有用性が消える

## 対策案
1. deploy_task.shの教訓選択にproject一致フィルタ追加(task.project == lesson.project or project==infra)
2. tag: universalの定義を「全プロジェクト共通」から「プロジェクト内全文脈」に限定
3. infra lessons(always inject)とproject-specific lessons(project match時のみ)の明示的分離

推奨: 対策1(project一致フィルタ)。5件×4cmd=20件のNOT_USEFULが除去され、useful率は12/(50-20)=40%に改善予測。
