# 軍師idle自走: /clear耐久率是正+startup WARN全件解消 (2026-05-16)

## 概要
自走サイクル7ステップ完了。automatedフラグGoodhart4度目を発見・是正。

## 成果

### 1. automated フラグ是正 (LG007, LG026)
- LG007 (capture-pane残像): pre-bash-combined.sh Guard 6にINFO(LG007)リマインダー実装済み → automated: false→true, enforcement_level: 2→4
- LG026 (S0セルフレビュー): pre-write-edit-combined.sh Guard 9にINFO(LG026)リマインダー実装済み → automated: false→true, enforcement_level: 2→4
- /clear耐久率: 75.8% → 81.8% (27/33)
- 残6件(LG003/023/024/028/030/032)は判断ベースの教訓でLevel 2が適切

### 2. GATE未確認2件→0件
- cmd_karo_rebalancer_push_2: gate_result=null→CLEAR (gates/全ステップdone確認)
- cmd_karo_ci_fix_semantic_codd: gate_result=null→BLOCK (軍師FAIL→再配備なし)

### 3. CS ambiguity_points WARN 3件→0件
- cmd_2743/2744/2745 draftエントリに`ambiguity_points: none`追加

### 4. WA安定期確認
- 直近10件全clean (WA=0)。修行サイクル(training_codd)のloop2-4+final全クリーン

## 因果鎖
automated自己申告フラグ→他覚的検証なし→実態との乖離蓄積→/clear耐久率75%が不正確
→前セッションGoodhart監査で原理発見→今回2件追加修正→81.8%に是正
→Goodhart原理の4度目再現(accuracy→automated→precheck→automatedフラグ乖離)

## 根因パターン: 自己申告指標の信頼性劣化
LG027(計測対象のズレ)と同根。代理指標を本来目標の代わりに最適化すると乖離が蓄積する。
他覚的検証(grepで実在確認)を挟まないと幻想が永続する。

## 次のアクション
- gate_lesson_enforcement_verify.sh (前セッション提案) の実装 → enforced/automated乖離の自動検出
- numbers/adversarial観点冷え(直近10件連続0)の再活性化 → 次回draftレビューで意識的にチェック
