# セマンティック監査レポート — 2026-05-09

## 概要

- 対象: 直近7日間に変更された63スクリプト
- 5カテゴリ並列監査: silent_failure / state_transition / race_condition / implicit_assumption / semantic_index

## 結果: 全カテゴリ新規問題なし

| カテゴリ | 検出数(エージェント) | 検証後 | 判定理由 |
|---------|---------------------|--------|---------|
| silent_failure | P1×1, P2×2 | 偽陽性 | auto_draft_lesson.sh L13でファイル存在事前チェック済み |
| state_transition | P1×3, P2×2 | 偽陽性 | delegated一方向遷移は設計意図(途中修正の二択=殿厳命) |
| race_condition | P1×2, P2×3 | 既知M4 | SA-014(yaml_field_set非atomic)。deploy_task.shは単一プロセス実行でリスク低 |
| implicit_assumption | P1×1, P2×3, P3×1, P4×2 | 偽陽性 | archive.doneは循環でなく一方向因果。ntfy.shはfallback+WARNING有り |
| semantic_index | drift=0, gap=infra | 健全 | 参照切れなし。gapはテスト/ログ等の管理ファイル |

## 偽陽性分析

### state_transition P1「delegated dead state」
- エージェントがcmdライフサイクルの設計哲学を理解していなかった
- 殿厳命「途中修正の二択: (1)別CMD発令 or (2)神速停止→回復再CMD」に基づき、delegatedは設計上の一方向遷移
- 修正が必要なら新cmdを作る。delegated→doneが唯一の正常フロー

### silent_failure P1「auto_draft_lesson.sh awk失敗」
- L13で`[ ! -f "$REPORT_PATH" ]`チェック済み。awk到達時点でファイル実在保証
- cmd_idが空の場合はL36の`[[ "$cmd_id" == cmd_* ]]`で弾かれる→skip扱い(設計意図)

### implicit_assumption P1「archive.done循環参照」
- archive.doneの生成元=cmd_complete_gate.sh(GATE CLEAR時)
- archive.doneの参照元=archive_completed.sh(アーカイブ判定時)
- 因果は一方向。循環ではない

## 教訓

- 5カテゴリ×並列エージェントは効率的だが偽陽性率が高い(15件検出→0件実質問題)
- 設計意図を知らないエージェントが「遷移パスがない=バグ」と判断する傾向
- 検証ステップ(想像するな確認せよ)なしに報告すると家老/将軍のCTXを浪費する

## 前回監査(2026-05-03)との比較

- 前回: 55件検出→18cmd起票→残M4(TOCTOU)のみ
- 今回: 新規0件。前回の修正が安定稼働している証拠

## D0直接実装 — インフラ隠れバグ2件修正 (commit 14254fbf)

### バグ1: knowledge_candidate str→dict autofix改善
- 問題: 忍者がEdit toolでdict→strに崩壊させるパターンが18回繰返しFAIL
- 修正: gate_report_autofix_main.py L120-127で"false"/"no"/"none"→{found:false}に正しく変換
- テスト: python 5case PASS

### バグ2: check_self_reread_red_flag偽陽性条件絞込み
- 問題: 「確認」「自問」等の汎用キーワードがAND条件に引っかかり14回偽陽性
- 修正: cmd_save.sh L472で条件を「自己再読」「読み直し」「セルフレビュー」に絞込み
- テスト: bash 8case PASS(偽陽性4排除+真陽性4保持), bats 17 PASS
- 家老承認済み

## 自走発見: スキル成長ループ段階3-4は実装済み

- skill_auto_improve.sh --applyモードが存在(L231 apply_prevention_steps)
- cmd_2604で帰属修正完了→正しいスキルに正しい注意ポイントが書ける状態に
- 提案: --applyの定期実行をninja_monitor/cronに組込めば段階3-4が自走
- insight INS-20260509-193005850-fed8に保存済み

## GP効果計測(2026-05-09 軍師自走)

学習ループ穴検査で「GP 234件implemented→効果計測0件」を発見。即計測。

| 期間 | WA率 | 件数 |
|------|------|------|
| 2026-03 | 51.0% | 26/51 |
| 2026-04 | 10.7% | 74/689 |
| 2026-05 | 5.2% | 12/231 |
| 直近50件 | 2.0% | 1/50 |

**結論**: GP群の集合効果でWA率51%→2%(96%削減)。免疫系は構造的に機能。
ただし個別GP毎のbefore/after計測は未実装。月次集計は効果の全体像を示すが、どのGPが効いたかは追跡不能。
