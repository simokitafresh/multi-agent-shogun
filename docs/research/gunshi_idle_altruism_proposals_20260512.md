# 利他提案2件 — 家老BLOCK時系列 + 教訓注入精度
<!-- generated: 2026-05-12T11:46:00+09:00 by gunshi idle analysis -->

## 提案1: lesson_done_missing BLOCK時系列問題

### 現象
軍師LGTM(GATE_PREDICTION:WARN)→review_gate.done→cmd_complete_gate即時起動→lesson_done_missing BLOCK。
家老がlesson登録する前にgateが走る。

### 根因
review_gate.done作成→cmd_complete_gate.sh起動が同期的。家老のlesson_write.sh実行の猶予がない。

### 提案
(A) cmd_complete_gate.shのlesson_done_missingチェックにregister_recommended判定を組込み、推奨時のみBLOCK・非推奨時はWARN
(B) review_gate.done作成前にlesson_candidate有→家老にlesson登録催促inbox_writeを先行送信

### 効果
家老のBLOCK→lesson登録→再GATE→CLEARの無駄サイクル削減。

## 提案2: 教訓注入useful率改善

### 計測結果
- 直近20報告: 32/139 = 23% useful
- useful=false 107件の61%(66件)がtopic_mismatch

### 根因
jaccard類似度のキーワード表面マッチ。例: L512(insight dedup)がdeploy_task.shのflock実装に「dedup/重複」で誤マッチ。

### 提案
(1) useful_rate_threshold 30%→40%引上げ（低有効教訓の退場促進）
(2) target_pathベースのスコープフィルタ追加（同一ファイル変更の教訓を優先）

### 期待効果
ノイズ率77%→推定50%。忍者のノイズ教訓読み時間を27%削減。
