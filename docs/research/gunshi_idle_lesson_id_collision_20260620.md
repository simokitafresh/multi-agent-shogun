# 教訓ID衝突分析 2026-06-20

## 発見

infra/lessons.yaml(821件)とdm-signal/lessons.yaml(751件)で746件のIDが衝突。
前セッション(blt_20260619_210627)で「重複」と報告したが、実態は**ID衝突(同一IDで内容が異なる)**。

## 実測データ

| 項目 | 値 |
|------|-----|
| infra lessons | 821件 |
| dm-signal lessons | 751件 |
| ID衝突 | 746件 |
| infra固有 | 75件 |
| dm-signal固有 | 5件 |

## 衝突の実態

IDは連番(L1, L2, ...)で両PJ独立採番のため衝突。内容は完全に別物:
- infra L754: "bash_speed_training.sh update_entry_field..."
- dm-signal L754: "WeightedMultiViewMomentumFilterBlock追加は..."

## useful率への影響

- 現在のuseful率: 18.5% (5/27)
- ID衝突は注入精度を直接低下させない（deploy_task.shはPJ別にlessonsを読む）
- useful率低下の主因はID衝突ではなく、教訓とタスクの関連度マッチングの精度

## 前セッション報告の訂正

blt_20260619_210627で「同一教訓の二重存在がuseful率低下の構造的根因」と報告したが、
実態はID衝突であり二重注入ではない。deploy_task.shのinject_related_lessonsは
PJ固有lessons+platform(infra) lessonsを読み込むが、IDが衝突していても
内容は別物のためuseful率への直接影響は軽微。

## 次の行動

useful率改善の真の対処:
1. deploy_task.shの教訓マッチング精度向上(キーワードスコア閾値の調整)
2. 低useful率教訓の淘汰(effectiveness_score < 0.40で自動除外=既実装)
3. ID衝突自体はPJ接頭辞(INF-XXX, DMS-XXX)で解決可能だが緊急度は低い
