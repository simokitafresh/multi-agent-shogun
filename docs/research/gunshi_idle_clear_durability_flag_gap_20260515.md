# 教訓耐久率 automatedフラグ実態乖離分析
<!-- generated: 2026-05-15T23:06:29+09:00 by gunshi idle analysis -->

## 問題

startup gateが教訓耐久率60% (20/33 automated) < 70%でWARNを出力。
13件がLevel 2（意志依存）と分類されている。

## 分析結果

13件のautomated: false教訓を現物grep確認した結果、5件が既にgate/hook化済みだがフラグが未更新。

| 教訓 | gate化実態 | 場所 | 備考 |
|------|-----------|------|------|
| LG001 | ac_physical_verify.sh L255 + gate_gunshi_startup.sh L553 | 既実装判定時のgit show HEAD警告 | startup gateで毎回表示 |
| LG010 | gate_gunshi_cs_checklist.sh L526-532 | defense_level<4のGP提案WARN | cs_checklistで自動検出 |
| LG020 | cmd_save.sh L4239, L4343 | 数値リテラル検出+算出元記載推奨 | cmd保存時に自動WARN |
| LG033 | gate_gunshi_cs_checklist.sh L534-547 | GP提案前のgrep証跡なしWARN | cs_checklistで自動検出 |
| LG034 | gate_gunshi_cs_checklist.sh L518-524 | 低ROI/対応不要の言語検出WARN | cs_checklistで自動検出 |

## 修正後の耐久率

- 現状: 20/33 = 60%
- 修正後: 25/33 = 76% (> 70% WARN閾値)
- 残り8件の真のLevel 2: LG003, LG007, LG023, LG024, LG026, LG028, LG030, LG032

## 真のLevel 2（8件）の評価

| 教訓 | gate化方針 | 判定 |
|------|-----------|------|
| LG003 | 反証探索の自動化は困難(false negative高) | ドキュメント強制で十分 |
| LG007 | 状態確認順序はreview_logヘッダで毎回読込済み | 非gate強制で十分 |
| LG023 | コード意図の自動判定困難 | 原理埋込み済み |
| LG024 | 人間判断に委ねるべき領域 | gate化不要(有害) |
| LG026 | S0プロトコル文書化済み。pre-edit hook追加可能 | low難易度で追加可能 |
| LG028 | 内部ループ計上は計算量依存 | ドキュメント強制で十分 |
| LG030 | 利他完了の4ステップチェック | medium難易度で追加可能 |
| LG032 | 既存強制メカニズムcatalog参照 | 原理埋込み済み |

## 因果鎖

automatedフラグ未更新→startup gate WARN→「13件未自動化」と認識→gate化設計に時間投入→
しかし5件は既に環境に埋込み済み→**計測(フラグ)と実態の乖離がidle自走の方向を歪めている**。
LG027(計測対象のズレは盲点を構造的に生む)の再現。referenced率≠useful率と同根。

## 対処

1. 家老にautomatedフラグ更新依頼送信済み(inbox_write gunshi_lesson_candidate)
2. 残り8件のうちLG026(pre-edit hook)とLG030(利他完了チェック)が次のgate化候補
