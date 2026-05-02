# Cross-Project教訓注入 偽陽性分析

## 日時
2026-04-26T21:30:00+09:00 (gunshi idle自走)

## 事象
tobisaru有用率0%(37件全NOT_USEFUL)が持続。GP-221(fallback廃止)後も改善せず。

## 根因
deploy_task.sh CROSS_PROJECT_SCORE_THRESHOLD=3が低すぎる。
キーワード1回マッチ(×3)で即通過→大量の無関係教訓が注入。

### 実測データ
- cmd_karo_ci_fix_357(infraタスク): dm-signal 34件、auto-ops 3件、mcas 2件=**39件**のcross-project教訓注入
- cmd_2309(dm-signal): L005(Google Classroom), L009(Google Drive), L042(note)が混入

### tobisaru NOT_USEFUL内訳(3報告37件)
- 別PJ教訓: L005, L009, L042 → dm-signalタスクにgoogle-classroom/note教訓
- PJ内ミスマッチ: L622-L636(GS系) → ETL調査タスクに注入
- タスク種別無視: 本番DB操作教訓 → context/*.md修正タスクに注入

## 因果鎖
閾値3(1キーワード=即通過)→大量FP注入→忍者が全件NOT_USEFUL→有用率0%→教訓注入の信頼性低下→忍者が教訓を読まなくなる=負の複利

## 提案
1. **CROSS_PROJECT_SCORE_THRESHOLD: 3→9に引上げ**(3キーワード以上マッチを要求)
2. 効果予測: 39件→数件に削減。FP率大幅低下
3. 複利の問い: 10回繰り返したら→閾値3=毎回30+件FP注入(負)。閾値9=3+件の関連教訓のみ(正)
