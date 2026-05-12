# 軍師自走分析: 構造的問題3点+修正 (2026-05-10)

## 1. draft review全滅バグ (修正済み)

- **when**: 05-10 00:07以降、18件連続SKIP
- **what**: count_acs_from_value()が新AC形式(list[dict{AC1,AC2}])でlen(list)=1→ac_count<=1→SKIP
- **why**: AC形式変更にカウント関数が追従していなかった
- **where**: deploy_task.sh L4960-4961
- **who**: deploy_task.shの自動判定ロジック
- **how**: AC*キーdrill-down追加 (commit 4e4f0bb0, 家老LGTM)

## 2. karo_direct誤FAIL (lesson_candidate送信済み)

- **when**: cmd_karo_lesson_4fieldレビュー時
- **what**: karo_direct配備を認識せず報告YAML不在→FAILと誤判定
- **why**: 軍師レビューフローにkaro_direct判定がない
- **where**: 家老のkaro_direct完了フロー(通常フローと分離されていない)
- **who**: 家老が手動でreport_review送信(karo_directでは不要)
- **how**: 家老にlesson_candidate送信済み(karo_direct完了時は軍師レビューSKIP)

## 3. accuracy 99.6% Goodhart疑い (分析途中)

- RC率低下が「深く見ていない」のか「問題が減った」のかの切り分け未完了
- observations品質は直近20件で具体性維持(commit hash/行数/テスト結果)
- WA率0%は家老負担吸収の証拠
- GATE未確認63件=全てtraining cmd(正常)

## 4. numbers/ambiguity冷え (対応開始)

- cmd_2654でnumbers観点使用(collection error 9→0検算)
- cmd種別による自然変動(infra Level5化→研究cmd少ない)だが、検算対象はあった(cmd_2653 results[:3]等)
- 「自然変動」は即断だった。研究cmd到来時に惰性でOKを出さない意識を維持

## 5. L6 scan全CLEAR発火+日本語対応 (修正済み)

- **問題**: L6 scanがLevel5シグナルワード限定で全CLEARから発火しなかった(4 CLEAR→0 insight)
- **修正1**: シグナルワードフィルタ撤廃(commit 90066806, 家老LGTM)
- **修正2**: 日本語トークン分割改善(cmd_2658 才蔵実装, CLEAR)
- **検証**: 英語cmd→6候補検出確認。日本語cmd→漢字n-gram分割で対応

## 6. 5W1H環境埋込み (完了)

- **WHEN/HOW**: cmd_save.sh q8 WARN(cmd_2655 CLEAR)
- **WHERE/WHO**: cmd_save.sh q8 WARN追加(D0 commit e5ca705b)
- **教訓when/how補完**: gunshi 32件(0%→100%)+karo 25件(0%→100%)+dm-signal TOP20(0%→2.8%)

## D0直接実装4件

| # | 修正内容 | commit | 家老 |
|---|---------|--------|------|
| 1 | draft review全滅バグ(AC形式追従) | 4e4f0bb0 | LGTM |
| 2 | gate AC偽BLOCK(description配下ACカウント) | b5debae6 | LGTM |
| 3 | L6 scanフィルタ撤廃(全CLEAR発火) | 90066806 | LGTM |
| 4 | q8 WHERE/WHO WARN追加(5W1H完全化) | e5ca705b | 待ち |

## 教訓登録3件

- L586: 分析報告で止まるな。D0即判定→即実装(LG018根治)
- L587: report_review+YAML不在→karo_direct確認してからFAIL判定
- L588: 因果分析は5W1H+WHO。6項目全て埋まるまで終えない

## review_logヘッダ埋込み3行

- 気づき→D0判定→即行動(L586)
- report_review+YAML不在→karo_direct確認(L587)
- 因果分析5W1H+WHO(L588)

## セッションの学び

1. **報告≠行動** (LG018 3回再発→根治): 掲示板投稿で終わらず、D0実装権限があるなら即修正。教訓+review_logヘッダに埋込み
2. **5W1H+WHO**: 6Wで見えない因果はない。whoで「家老が手動送信」が判明。殿指摘→即環境埋込み
3. **karo_direct認識漏れ**: 前提確認(配備方式)をスキップした。deepdive Phase 1と同構造。教訓登録済み
4. **L6は仕組みが入っても動かなければゼロ**: フィルタ撤廃+日本語対応で初めて全CLEARから候補検出可能に
